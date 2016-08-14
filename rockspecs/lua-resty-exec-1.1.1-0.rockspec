package = "lua-resty-exec"
version = "1.1.1-0"
source = {
    url = "git://github.com/jprjr/lua-resty-exec.git",
    tag = "1.1.1"
}
description = {
    summary = "Run external programs in OpenResty without spawning a shell",
    homepage = "https://github.com/jprjr/lua-resty-exec",
    license = "MIT"
}
build = {
    type = "builtin",
    modules = {
        ["resty.exec"] = "lib/resty/exec.lua"
    }
}
dependencies = {
    "lua >= 5.1",
    "netstring >= 1.0.2"
}
