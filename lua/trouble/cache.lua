--- Namespaced caches. `Cache.<name>` creates the namespace on first access,
--- so `Cache.symbols[buf] = items` just works.
---@class trouble.CacheM: {[string]: trouble.Cache}
local M = {}

---@class trouble.Cache: {[string]: any}
---@field data table<string, any>
local C = {}

function C:__index(key)
  local ret = C[key]
  if ret ~= nil then
    return ret
  end
  return self.data[key]
end

function C:__newindex(key, value)
  self.data[key] = value
end

function C:clear()
  self.data = {}
end

function M.new()
  return setmetatable({ data = {} }, C)
end

function M.__index(_, k)
  M[k] = M.new()
  return M[k]
end

return setmetatable(M, M)
