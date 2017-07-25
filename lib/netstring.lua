-- Copyright 2016 John Regan <john@jrjrtech.com>

local string_sub = string.sub
local string_len = string.len
local string_byte = string.byte

local M = {
  _VERSION = '1.0.6'
}

local function _decode(a)
    local i=1
    local len = 0;
    local max_len = string_len(a)

    repeat
        local t = string_byte(a,i) - 48
        if(t >= 0 and t<=9) then
            len = (len * 10) + t
            i = i + 1
        end
    until ( t<0 or t>9 or i > max_len )

    if (i > max_len) then
        return nil, nil
    end

    -- ascii 58 == colon
    if string_byte(a,i) ~= 58 then
        return nil, nil
    end
    i = i + 1

    if(i+len > max_len) then
        return nil, nil
    end

    -- ascii 44 == comma
    if(string_byte(a,i+len) ~= 44) then
        return nil, nil
    end

    if(len == 0) then
      return i, ''
    end

    return i+len, string_sub(a,i,i+len - 1)
end

local function _encode(a)
    return string_len(a) .. ':' .. a .. ','
end

local function _order(a,b)
    local ta = type(a)
    local tb = type(b)
    if(ta == "number" and tb == "number") then
        return a<b
    elseif (ta== "number" and tb =="string") then
        return true
    elseif (ta=="string" and tb == "number") then
        return false
    elseif (ta=="string" and tb=="string") then
        return a<b
    end
end

function M.decode(a)
    local i = 1
    local results = {}

    while(i<#a) do
        local j,val = _decode(string_sub(a,i))
         if j then
             table.insert(results,val)
             i = i + j
         else
             break
         end
    end
    if #results == 0 then
         results = nil
    end
    return results, string_sub(a,i)
end

function M.encode(...)
    local r = ""
    local err = {}
    local args = {...}

    for i in pairs(args) do
        local a = args[i]
        local ta = type(a)
        if ta == 'table' then
            -- grab table keys and sort
            local keys = {}
            for k in pairs(a) do keys[#keys+1] = k end
            table.sort(keys,_order)
            for _,k in ipairs(keys) do
                if(type(k) ~= "number") then
                    table.insert(err,'arg ' .. i .. ' key "' .. k .. '" is not numeric')
                else
                    r = r .. _encode(a[k])
                end
            end
         elseif ta ~= 'nil' then
             r = r .. _encode(a)
         end
    end

    if(#err == 0) then
        err = nil
    end

    if(#r == 0) then
        r = nil
    end
    return r, err
end

return M
