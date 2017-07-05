package = "lua-resty-exec"
version = "2.0.0-1"
source = {
    url = "https://github.com/jprjr/lua-resty-exec/archive/2.0.0.tar.gz",
    file = "lua-resty-exec-2.0.0.tar.gz"
}
description = {
    summary = "Run external programs in OpenResty without spawning a shell",
    homepage = "https://github.com/jprjr/lua-resty-exec",
    license = "MIT"
}
build = {
    type = "builtin",
    modules = {
        ["resty.exec"] = "lib/resty/exec.lua",
        ["resty.exec.socket"] = "lib/resty/exec/socket.lua",
    }
}
dependencies = {
    "lua >= 5.1",
    "netstring >= 1.0.6"
}
