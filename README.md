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

This requires your web server to have an active instance of
[sockexec](https://github.com/jprjr/sockexec) running.

## Installation

`lua-resty-exec` is available on [luarocks](https://luarocks.org/modules/jprjr/lua-resty-exec)
as well as [opm](https://opm.openresty.org/), you can install it with `luarocks install
lua-resty-exec` or `opm get jprjr/lua-resty-exec`.

If you're using this outside of OpenResty, you'll also need the LuaSocket
module installed, ie `luarocks install luasocket`.

Additionally, you'll need `sockexec` running, see [its repo](https://github.com/jprjr/sockexec)
for instructions.

## Usage

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
-- set bufsize to some smaller value, the default is 4096
-- this allows data to stream in smaller chunks
prog.bufsize = 10

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
        prog.bufsize = 10
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
