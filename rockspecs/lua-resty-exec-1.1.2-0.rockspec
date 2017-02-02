package = "lua-resty-exec"
version = "1.1.2-0"
source = {
    url = "https://github.com/jprjr/lua-resty-exec/archive/1.1.2.tar.gz",
    file = "lua-resty-exec-1.1.2.tar.gz"
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
