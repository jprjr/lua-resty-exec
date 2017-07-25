# lua-resty-exec

A small Lua module for executing processes. It's primarily
intended to be used with OpenResty, but will work in regular Lua applications
as well. When used with OpenResty, it's completely non-blocking (otherwise it
falls back to using LuaSocket and does block).

It's similar to (and inspired by)
[lua-resty-shell](https://github.com/juce/lua-resty-shell), the primary
difference being this module uses sockexec, which doesn't spawn a shell -
instead you provide an array of argument strings, which means you don't need
to worry about shell escaping/quoting/parsing rules.

Additionally, as of version 2.0.0, you can use `resty.exec.socket` to access a
lower-level interface that allows two-way communication with programs. You can
read and write to running applications!

This requires your web server to have an active instance of
[sockexec](https://github.com/jprjr/sockexec) running.

## Changelog

* `3.0.0`
  * new field returned: `unknown` - if this happens please send me a bug!
* `2.0.0`
  * New `resty.exec.socket` module for using a duplex connection
  * `resty.exec` no longer uses the `bufsize` argument
  * `resty.exec` now accepts a `timeout` argument, specify in milliseconds, defaults to 60s
  * This is a major revision, please test thoroughly before upgrading!
* No changelog before `2.0.0`

## Installation

`lua-resty-exec` is available on [luarocks](https://luarocks.org/modules/jprjr/lua-resty-exec)
as well as [opm](https://opm.openresty.org/), you can install it with `luarocks install
lua-resty-exec` or `opm get jprjr/lua-resty-exec`.

If you're using this outside of OpenResty, you'll also need the LuaSocket
module installed, ie `luarocks install luasocket`.

Additionally, you'll need `sockexec` running, see [its repo](https://github.com/jprjr/sockexec)
for instructions.

## `resty.exec` Usage

```lua
local exec = require'resty.exec'
local prog = exec.new('/tmp/exec.sock')
```

Creates a new `prog` object, using `/tmp/exec.sock` for its connection to
sockexec.

From there, you can use `prog` in a couple of different ways:

### ez-mode

```lua
local res, err = prog('uname')

-- res = { stdout = "Linux\n", stderr = nil, exitcode = 0, termsig = nil }
-- err = nil

ngx.print(res.stdout)
```

This will run `uname`, with no data on stdin.

Returns a table of output/error codes, with `err` set to any errors
encountered.

### Setup argv beforehand

```lua
prog.argv = { 'uname', '-a' }
local res, err = prog()

-- res = { stdout = "Linux localhost 3.10.18 #1 SMP Tue Aug 2 21:08:34 PDT 2016 x86_64 GNU/Linux\n", stderr = nil, exitcode = 0, termsig = nil }
-- err = nil

ngx.print(res.stdout)
```

### Setup stdin beforehand

```lua
prog.stdin = 'this is neat!'
local res, err = prog('cat')

-- res = { stdout = "this is neat!", stderr = nil, exitcode = 0, termsig = nil }
-- err = nil

ngx.print(res.stdout)
```

### Call with explicit argv, stdin data, stdout/stderr callbacks

```lua
local res, err = prog( {
    argv = 'cat',
    stdin = 'fun!',
    stdout = function(data) print(data) end,
    stderr = function(data) print("error:", data) end
} )

-- res = { stdout = nil, stderr = nil, exitcode = 0, termsig = nil }
-- err = nil
-- 'fun!' is printed
```

Note: here `argv` is a string, which is fine if your program doesn't need
any arguments.

### Setup stdout/stderr callbacks

If you set `prog.stdout` or `prog.stderr` to a function, it will be called for
each chunk of stdout/stderr data received.

Please note that there's no guarantees of stdout/stderr being a complete
string, or anything particularly sensible for that matter!

```lua
prog.stdout = function(data)
    ngx.print(data)
    ngx.flush(true)
end

local res, err = prog('some-program')

```

### Treat timeouts as non-errors

By default, `sockexec` treats a timeout as an error. You can disable this by
setting the object's `timeout_fatal` key to false. Examples:

```lua
-- set timeout_fatal = false on the prog objects
prog.timeout_fatal = false

-- or, set it at calltime:
local res, err = prog({argv = {'cat'}, timeout_fatal = false})
```

### But I actually want a shell!

Not a problem! You can just do something like:

```lua
local res, err = prog('bash','-c','echo $PATH')
```

Or if you want to run an entire script:

```lua
prog.stdin = script_data
local res, err = prog('bash')

-- this is roughly equivalent to running `bash < script` on the CLI
```

### Daemonizing processes

I generally recommend against daemonizing processes - I think it's far
better to use some kind of message queue and/or supervision system, so
you can monitor processes, take actions on failure, and so on.

That said, if you want to spin off some process, you could use
`start-stop-daemon`, ie:

```lua
local res, err = prog('start-stop-daemon','--pidfile','/dev/null','--background','--exec','/usr/bin/sleep', '--start','--','10')
```

will spawn `sleep 10` as a detached background process.

If you don't want to deal with `start-stop-daemon`, I have a small utility
for spawning a background program called [idgaf](https://github.com/jprjr/idgaf), ie:

```lua
local res, err = prog('idgaf','sleep','10')
```

This will basically accomplish the same thing `start-stop-daemon` does without
requiring a billion flags.

## `resty.exec.socket` Usage

```lua
local exec_socket = require'resty.exec.socket'

-- you can specify timeout in milliseconds, optional
local client = exec_socket:new({ timeout = 60000 })

-- every new program instance requires a new
-- call to connect
local ok, err = client:connect('/tmp/exec.sock')

-- send program arguments, only accepts a table of
-- arguments
client:send_args({'cat'})

-- send data for stdin
client:send('hello there')

-- receive data
local data, typ, err = client:receive()

-- `typ` can be one of:
--    `stdout`   - data from the program's stdout
--    `stderr`   - data from the program's stderr
--    `exitcode` - the program's exit code
--    `termsig`  - if terminated via signal, what signal was used

-- if `err` is set, data and typ will be nil
-- common `err` values are `closed` and `timeout`
print(string.format('Received %s data: %s',typ,data)
-- will print 'Received stdout data: hello there'

client:send('hey this cat process is still running')
data, typ, err = client:receive()
print(string.format('Received %s data: %s',typ,data)
-- will print 'Received stdout data: hey this cat process is still running'

client:send_close() -- closes stdin
data, typ, err = client:receive()
print(string.format('Received %s data: %s',typ,data)
-- will print 'Received exitcode data: 0'

data, typ, err = client:receive()
print(err) -- will print 'closed'
```

### `client` object methods:

* **`ok, err = client:connect(path)`**

Connects via unix socket to the path given. If this is running
in nginx, the `unix:` string will be prepended automatically.

* **`bytes, err = client:send_args(args)`**

Sends a table of arguments to sockexec and starts the program.

* **`bytes, err = client:send_data(data)`**

Sends `data` to the program's standard input

* **`bytes, err = client:send(data)`**

Just a shortcut to `client:send_data(data)`

* **`bytes, err = client:send_close()`**

Closes the program's standard input. You can also send an empty
string, like `client:send_data('')`

* **`data, typ, err = client:receive()`**

Receives data from the running process. `typ` indicates the type
of data, which can be `stdout`, `stderr`, `termsig`, `exitcode`

`err` is typically either `closed` or `timeout`

* **`client:close()`**

Forcefully closes the client connection

* **`client:getfd()`**

A getfd method, useful if you want to monitor the underlying socket
connection in a select loop

## Some example nginx configs

Assuming you're running sockexec at `/tmp/exec.sock`

```
$ sockexec /tmp/exec.sock
```

Then in your nginx config:

```nginx
location /uname-1 {
    content_by_lua_block {
        local prog = require'resty.exec'.new('/tmp/exec.sock')
        local data,err = prog('uname')
        if(err) then
            ngx.say(err)
        else
            ngx.say(data.stdout)
        end
    }
}
location /uname-2 {
    content_by_lua_block {
        local prog = require'resty.exec'.new('/tmp/exec.sock')
        prog.argv = { 'uname', '-a' }
        local data,err = prog()
        if(err) then
            ngx.say(err)
        else
            ngx.say(data.stdout)
        end
    }
}
location /cat-1 {
    content_by_lua_block {
        local prog = require'resty.exec'.new('/tmp/exec.sock')
        prog.stdin = 'this is neat!'
        local data,err = prog('cat')
        if(err) then
            ngx.say(err)
        else
            ngx.say(data.stdout)
        end
    }
}
location /cat-2 {
    content_by_lua_block {
        local prog = require'resty.exec'.new('/tmp/exec.sock')
        local data,err = prog({argv = 'cat', stdin = 'awesome'})
        if(err) then
            ngx.say(err)
        else
            ngx.say(data.stdout)
        end
    }
}
location /slow-print {
    content_by_lua_block {
        local prog = require'resty.exec'.new('/tmp/exec.sock')
        prog.stdout = function(v)
            ngx.print(v)
            ngx.flush(true)
        end
        prog('/usr/local/bin/slow-print')
    }
    # look in `/misc` of this repo for `slow-print`
}
location /shell {
    content_by_lua_block {
        local prog = require'resty.exec'.new('/tmp/exec.sock')
        local data, err = prog('bash','-c','echo $PATH')
        if(err) then
            ngx.say(err)
        else
            ngx.say(data.stdout)
        end
    }
}

```

## License

MIT license (see `LICENSE`)
