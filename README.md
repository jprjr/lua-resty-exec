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

### Call with explicit argv and stdin

```lua
local res, err = prog( { argv = 'cat', stdin = 'fun!' } )

-- res = { stdout = "fun!", stderr = nil, exitcode = 0, termsig = nil }
-- err = nil

ngx.print(res.stdout)
```

Note: here `argv` is a string, which is fine if your program doesn't need any
arguments.

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

### But I actually want a shell!

Not a problem! You can just do something like:

```lua
local res, err = prog('bash','-c','echo $PATH')
```

Or if you want to run an entire script:

```lua
prog.stdin = script_data
local res, err = prog('bash')
```


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
