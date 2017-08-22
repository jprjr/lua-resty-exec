local exec = require"resty.exec.socket"
local tonumber = tonumber
local table_unpack = unpack or table.unpack -- luacheck: compat
local insert = table.insert
local concat = table.concat

local _M = {
  _VERSION = "3.0.3"
}

function _M.new(address)
    if not address then return nil, "must supply an address" end

    local o = {
        argv = nil,
        stdin = nil,
        stdout = nil,
        stderr = nil,
        unknown = nil,
        timeout = 60000,
        timeout_fatal = true,
    }

    function o.exec(self,...)
        local args = {...}
        local c, err, _

        local ret = {unknown = {}, stdout = {}, stderr = {}, exitcode = "", termsig = ""}

        if #args > 0 then
            if type(args[1]) == "table" then
                if args[1].argv then
                    if type(args[1].argv) == "table" then
                        self.argv = args[1].argv
                    else
                        self.argv = { args[1].argv }
                    end
                end
                if args[1].stdin then self.stdin = args[1].stdin end
                if args[1].timeout_fatal ~= nil then self.timeout_fatal = args[1].timeout_fatal end

                if args[1].stdout then
                    if type(args[1].stdout) == "function" then
                        self.stdout = args[1].stdout
                    else
                        return nil, "invalid argument 'stdout' (requires function)"
                    end
                end

                if args[1].stderr then
                    if type(args[1].stderr) == "function" then
                        self.stderr = args[1].stderr
                    else
                        return nil, "invalid argument 'stderr' (requires function)"
                    end
                end

                if args[1].unknown then
                    if type(args[1].unknown) == "function" then
                        self.unknown = args[1].unknown
                    else
                        return nil, "invalid argument 'unknown' (requires function)"
                    end
                end

                if args[1].timeout then
                  self.timeout = args[1].timeout
                end

            else
                self.argv = args
            end
        end

        if not self then return nil, "missing parameter 'self'" end
        if not self.argv or #self.argv <= 0 then return nil, "no arguments supplied" end

        local cbs = {
          ["unknown"] = function(v)
            if self.unknown then
              self.unknown(v)
            else
              insert(ret.unknown,v)
            end
          end,
          ["stdout"] = function(v)
            if self.stdout then
              self.stdout(v)
            else
              insert(ret.stdout,v)
            end
          end,
          ["stderr"] = function(v)
            if self.stderr then
              self.stderr(v)
            else
              insert(ret.stderr,v)
            end
          end,
          ["termsig"] = function(v)
            ret.termsig = ret.termsig .. v
          end,
          ["exitcode"] = function(v)
            ret.exitcode = ret.exitcode .. v
          end,
        }

        c,err = exec:new({timeout = self.timeout})
        if err then return nil, err end
        _, err = c:connect(address)
        if err then return nil, err end

        c:send_args(self.argv)
        if self.stdin then c:send(self.stdin) end
        c:send_close()
        err = nil

        while(not err) do
            local data, typ
            data, typ, err = c:receive()

            if err then
                if err == "timeout" then
                    if self.timeout_fatal then
                        return nil, err
                   else
                        err = nil
                    end
                else
                    if err ~= "timeout" and err ~= "closed" then
                        return nil, err
                    end
                end
            end

            if typ then
              cbs[typ](data)
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
        else
            ret.stdout = concat(ret.stdout,'')
        end
        if not #ret.stderr then
            ret.stderr = nil
        else
            ret.stderr = concat(ret.stderr,'')
        end
        if not #ret.unknown then
            ret.unknown = nil
        else
            ret.unknown = concat(ret.unknown,'')
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
