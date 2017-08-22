local netstring = require'netstring'
local pairs = pairs
local ngx = ngx or false -- luacheck: ignore
local unix, socket
local string_len = string.len
local insert = table.insert
local sub = string.sub
local byte = string.byte

if ngx then -- luacheck: ignore
  unix = ngx.socket.tcp -- luacheck: ignore
else
  socket = require'socket'
  unix = require'socket.unix'
end

local _M = {
  _VERSION = '3.0.3'
}
local mt = { __index = _M }

local function ns_encode(...)
  local ns, nserr = netstring.encode(unpack({...}))
  if nserr then
    local err = ''
    for i in pairs(nserr) do
      if i> 1 then err = err .. '; ' end
      err = err .. nserr[i]
    end
    return nil, err
  end
  return ns, nil
end

local function ns_send(sock,...)
  local ns, nserr = ns_encode(unpack({...}))
  if nserr then
    return nil, 'netstring: ' .. nserr
  end

  local bytes, err = sock:send(ns)
  if err then
    return nil, 'socket: ' .. err
  end
  return bytes, nil
end

-- returns data, typ, newindex
-- newindex == -1 indicates all pairs are processed
local function ns_pairs_shift(ns_pairs,ns_pairs_index)
  local data, typ
  local index = ns_pairs_index
  if (#ns_pairs - index > 1) then
    data = ns_pairs[index + 2]
    typ = ns_pairs[index + 1]

    index = index + 2

    if index == #ns_pairs then
      index = -1
    end
  end
  return data, typ, index
end

local function grab_ns(self, timeout)
  if self.bufsize == -1 then
    local t
    repeat
      if not ngx then -- luacheck: ignore
        local _, _, sockerr = socket.select({self.sock},nil,timeout)

        if sockerr then
          return nil, sockerr
        end
        self.sock:settimeout(0)
      else
        if timeout == 0 then
          timeout = 1
        end
        self.sock:settimeout(timeout)
      end

      local dat, err, partial = self.sock:receive(1)

      if err == 'closed' then
        self.closed = true
        self.bufsize = -1
        self.bufsize_rem = 0
        self.bufsize_cur = 0
        self.chunk = ''
        return nil, 'closed'
      end

      if not ngx then
        self.sock:settimeout(timeout)
      end

      if partial then
        dat = partial
      end

      if not dat or string_len(dat) <= 0 then return nil, err end

      t = byte(dat,1) - 48
      if(t >= 0 and t <= 9) then
        self.bufsize_cur = (self.bufsize_cur * 10) + t
      end
    until( t<0 or t>9 )

    if t == 10 then -- colon = 58, then -48 from above loop
      self.bufsize = self.bufsize_cur + 1
      self.bufsize_rem = self.bufsize_cur + 1
    else
      self.bufsize = -1
      self.bufsize_rem = 0
      self.chunk = ''
      self.sock:close()
      return nil, 'error: netstring violated'
    end
  end

  self.bufsize_cur = 0

  while (self.bufsize_rem > 0) do
    local b = self.bufsize_rem > 8192 and 8192 or self.bufsize_rem

    if not ngx then -- luacheck: ignore
      local _, _, sockerr = socket.select({self.sock},nil,timeout)

      if sockerr then
        return nil, sockerr
      end
      self.sock:settimeout(0)
    else
        self.sock:settimeout(timeout)
    end

    local dat, err, partial = self.sock:receive(b)

    if not ngx then
      self.sock:settimeout(timeout)
    end

    if partial then
      dat = partial
    end

    if not dat then return nil, nil, err end
    self.chunk = self.chunk .. dat
    self.bufsize_rem = self.bufsize_rem - b
  end

  if(byte(self.chunk,self.bufsize) ~= 44) then
    self.bufsize = -1
    self.chunk = ''
    self.bufsize_cur = 0
    self.sock:close()
    return nil, 'error: netstring violated'
  end

  insert(self.ns_pairs,sub(self.chunk,1,self.bufsize-1))
  self.bufsize = -1
  self.chunk = ''

  return true, nil
end

function _M.new(self, opts) -- luacheck: ignore
  local sock, err = unix()

  if not sock then
    return nil, err
  end

  local timeout = 60000

  if opts then
    if opts.timeout then
      timeout = opts.timeout
    end
  end

  if not ngx then
    timeout = timeout / 1000
  end

  sock:settimeout(timeout)

  return setmetatable({
    sock = sock,
    timeout = timeout,
    args_sent = false,
    bufsize = -1,
    bufsize_cur = 0,
    chunk = '',
    ns_pairs = {},
    ns_pairs_index = 0,
    closed = true,
  }, mt)

end

function _M.connect(self, uri)
  if not self.sock then
    return nil, 'user_error: not setup'
  end

  local u = uri

  if ngx then -- luacheck: ignore
    u = 'unix:' .. u
  end

  local ok, err = self.sock:connect(u)
  if not ok then
    return nil, err
  end
  self.closed = false

  return true, nil
end

function _M.send_args(self, args)
  if self.args_sent then
    return nil, 'user_error: args already sent'
  end

  if(self.closed) then
    return nil, 'user_error: connection closed'
  end

  if(type(args)) ~= 'table' or #args < 1 then
    return nil, 'user_error: args must be array-like table'
  end

  local bytes, err = ns_send(self.sock,#args, args)
  if err then
    return nil, err
  end

  self.args_sent = true
  return bytes, nil
end

function _M.send_data(self, data)
  if(self.closed) then
    return nil, 'user_error: connection closed'
  end
  if not self.args_sent then
    return nil, 'user_error: must send args first'
  end

  local bytes, err = ns_send(self.sock, data)
  if err then
    return nil, err
  end

  return bytes, nil
end

function _M.send_close(self)
  return _M.send_data(self, '')
end

function _M.send(self, data)
  return _M.send_data(self, data)
end

function _M.receive(self)
  if not self.sock then
    return nil, 'user_error: socket not created'
  end

  if not self.args_sent then
    return nil, 'user_error: must send args first'
  end

  if self.closed and #self.ns_pairs == 0 then
    return nil, nil, 'closed'
  end

  local data, typ, index

  data, typ, index = ns_pairs_shift(self.ns_pairs,self.ns_pairs_index)

  if index == -1 then
    self.ns_pairs = {}
    self.ns_pairs_index = 0
  else
    self.ns_pairs_index = index
  end

  if data then
    return data, typ, nil
  end

  local read_ns = true
  local attempt = 0
  while read_ns do
    local timeout = attempt == 0 and self.timeout or 0
    attempt = attempt + 1
    local ok, _ = grab_ns(self,timeout)
    if not ok then
      read_ns = false
    end
  end

  data, typ, index = ns_pairs_shift(self.ns_pairs,self.ns_pairs_index)
  if index == -1 then
    self.ns_pairs = {}
    self.ns_pairs_index = 0
  else
    self.ns_pairs_index = index
  end

  if data then
    return data, typ, nil
  end

  return nil, nil, 'timeout'
end

function _M.close(self)
  if not self.sock then
    return nil, 'user:error: socket not setup'
  end
  if not self.closed then
    self.closed = true
  end
  return self.sock:close()
end

function _M.getfd(self)
  if not self.sock then
    return nil, 'user_error: socket not setup'
  end
  return self.sock:getfd()
end

return _M
