local netstring = require'netstring'
local pairs = pairs
local tonumber = tonumber
local unix
local table_unpack

if ngx then
    unix = ngx.socket.tcp
else
    unix = require'socket.unix'
end

if unpack then
    table_unpack = unpack
else
    table_unpack = table.unpack
end


local _M = {
  _VERSION = '1.1.1'
}

function _M.new(address)
    if not address then return nil, "must supply an address" end
    local a = address
    if ngx then
        a = 'unix:' .. a
    end
    local o = {
        argv = nil,
        stdin = nil,
        stdout = nil,
        stderr = nil,
        bufsize = 4096
    }

    function o.exec(self,...)
        local args = {...}
        local c, err, ns, nserr, success, data, partial, curfield

        local buffer = ""
        local ret = {stdout = "", stderr = "", exitcode = "", termsig = ""}

        if #args > 0 then
            if type(args[1]) == "table" then
                if args[1].argv then
                    if type(self.argv) == "table" then
                        self.argv = args[1].argv
                    else
                        self.argv = { args[1].argv }
                    end
                end
                if args[1].stdin then self.stdin = args[1].stdin end
            else
                self.argv = args
            end
        end

        if not self then return nil, "missing parameter 'self'" end
        if not self.argv or #self.argv <= 0 then return nil, "no arguments supplied" end

        ns, nserr = netstring.encode(#self.argv, self.argv, self.stdin, "")
        if nserr then
            err = ''
            for i in pairs(nserr) do
                if i > 1 then err = err .. '; ' end
                err = err .. nserr[i]
            end
            return nil, err
        end

        c, err = unix()
        if err then return nil, err end

        success, err = c:connect(a)
        if err then return nil, err end

        c:send(ns)

        while(not err) do
            data, err, partial = c:receive(self.bufsize)
            if err and err ~= "closed" then
               return nil, err
            end

            if data then
               buffer = buffer .. data
            end

            if partial then
                buffer = buffer .. partial
            end

            if #buffer then
                local t, s = netstring.decode(buffer)
                buffer = s
                if t then
                    for i,v in pairs(t) do
                        if not curfield then curfield = v
                        else
                            if curfield == "stdout" then
                                if self.stdout then
                                    self.stdout(v)
                                else
                                    ret.stdout = ret.stdout .. v
                                end
                            elseif curfield == "stderr" then
                                if self.stderr then
                                    self.stderr(v)
                                else
                                    ret.stderr = ret.stderr .. v
                                end
                            elseif curfield == "exitcode" then
                                ret.exitcode = ret.exitcode .. v
                            elseif curfield == "termsig" then
                                ret.termsig = ret.termsig .. v
                            end
                            curfield = nil
                        end
                    end
                end
            end
        end
        c:close()
        if #ret.exitcode then
            ret.exitcode = tonumber(ret.exitcode)
        else
            ret.exitcode = nil
        end
        if #ret.termsig then
            ret.termsig = tonumber(ret.termsig) 
        else
            ret.termsig = nil
        end
        if not #ret.stdout then
            ret.stdout = nil
        end
        if not #ret.stderr then
            ret.stderr = nil
        end
        return ret, nil
    end

    setmetatable(o,
        { __call = function(...)
            local args = {...}
            return o.exec(table_unpack(args))
        end })

    return o, nil
end

return _M
