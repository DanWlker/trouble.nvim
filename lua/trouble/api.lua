local Config = require("trouble.config")
local List = require("trouble.list")
local Qf = require("trouble.qf")
local Util = require("trouble.util")

---@alias trouble.ApiFn fun(opts?: trouble.Config|string): trouble.List

---@class trouble.api: trouble.actions
local M = {}
M.last_mode = nil ---@type string?

--- Options that only steer this call, and never justify rebuilding a list.
local transient = { mode = true, refresh = true, _action = true }

--- Signature of the extra options passed to `open`. When it changes,
--- the list is rebuilt so that things like `filter.buf=0` take effect.
--- Returns `nil` when no meaningful options were given.
---@param opts table
---@return string?
local function signature(opts)
  local ret = {} ---@type table<string, any>
  local count = 0
  for k, v in pairs(opts) do
    if not transient[k] then
      ret[k] = v
      count = count + 1
    end
  end
  return count > 0 and vim.inspect(ret, { newline = "", indent = "" }) or nil
end

--- Resolves the options and finds the list for the resulting mode.
--- When no mode is given, this falls back to the list that owns the
--- current quickfix list, and then to the last mode that was opened.
---@param opts? trouble.Config|string
---@return trouble.List?, trouble.Mode
function M._find(opts)
  if type(opts) == "string" then
    opts = { mode = opts }
  end
  opts = opts or {}

  local resolved = Config.get(opts)

  -- `Config.get` keeps the first mode it sees, so the mode has to be
  -- replaced on the resolved options and then resolved again.
  if resolved.mode == "last" then
    resolved.mode = M.last_mode
    resolved = Config.get(resolved)
  end

  if not resolved.mode then
    local list = List.active() or List.get(M.last_mode)
    if list and list.opts.mode then
      resolved.mode = list.opts.mode
      resolved = Config.get(resolved)
    end
  end

  M.last_mode = resolved.mode or M.last_mode
  ---@cast resolved trouble.Mode
  return List.get(resolved.mode), resolved
end

-- Loads the given mode into its quickfix or location list and shows it.
-- Running it again for a mode that is already on screen closes the window, so
-- `:Trouble <mode>` toggles. Switching to a different mode never closes.
---@param opts? trouble.Mode | { refresh?: boolean } | string
---@return trouble.List?
function M.open(opts)
  opts = opts or {}
  if type(opts) == "string" then
    opts = { mode = opts }
  end

  local list, _opts = M._find(opts)
  local sig = signature(opts)

  -- rebuild the list when it was created with different options.
  -- action proxies never rebuild, they just act on what is there.
  local old = list
  if old and not opts._action and old._sig ~= sig then
    old:stop()
    list = nil
  end

  if not list then
    if not _opts.mode then
      return Util.error("No mode specified")
    elseif not vim.tbl_contains(Config.modes(), _opts.mode) then
      return Util.error("Invalid mode `" .. _opts.mode .. "`")
    end
    list = List.new(_opts)
    -- keep using the quickfix list of the mode we replaced,
    -- so that changing options doesn't stack up new lists
    if old then
      list.qf_id = old.qf_id
    end
    list._sig = sig
  elseif not opts._action then
    list._sig = sig
  end

  -- toggle: same mode, same options, already on screen -> close it.
  -- A rebuild above already cleared `list`, so changing options never closes.
  -- `retarget` first: asking for a location list mode from a different window
  -- means "show me this window's results", not "close the other window's list".
  if list and not opts._action then
    list:retarget()
    if list:is_open() then
      Qf.close(list:win())
      return list
    end
  end

  if list:is_active() and opts.refresh == false then
    return list
  end
  list:open()
  return list
end

-- Closes the window showing the given mode's list.
-- With no mode, closes every window showing a trouble list, leaving windows
-- that show something else (your own `:grep` results, say) alone.
---@param opts? trouble.Mode|string
function M.close(opts)
  if type(opts) == "string" then
    opts = { mode = opts }
  end

  ---@type trouble.List[]
  local lists = List.all()
  if type(opts) == "table" and opts.mode then
    lists = { (M._find(opts)) }
  end

  for _, list in ipairs(lists) do
    if list:is_open() then
      Qf.close(list:win())
    end
  end
end

-- Refresh the given mode, or all modes when none is given.
-- Normally this is done automatically, unless you disabled auto refresh.
---@param opts? trouble.Mode|string
function M.refresh(opts)
  if opts == nil then
    for _, list in ipairs(List.all()) do
      list:refresh()
    end
    return
  end
  local list = M._find(opts)
  if list then
    -- asking for a specific mode refetches it even when its list isn't active
    list:refresh({ opening = true })
  end
end

-- Proxy to the list's action.
---@param action trouble.Action.spec
function M._action(action)
  return function(opts)
    opts = opts or {}
    if type(opts) == "string" then
      opts = { mode = opts }
    end
    opts = vim.tbl_deep_extend("force", {
      refresh = false,
      _action = true,
    }, opts)
    local list = M.open(opts)
    if list then
      list:action(action, opts)
    end
    return list
  end
end

-- Get all items for a given mode.
---@param opts? trouble.Mode|string
function M.get_items(opts)
  local list = M._find(opts)
  return list and list:items() or {}
end

-- Returns the number of entries in the list a mode writes to.
---@param opts? trouble.Mode|string
function M.count(opts)
  local list = M._find(opts)
  return Qf.count(list and list:win() or nil)
end

return setmetatable(M, {
  __index = function(_, k)
    if k == "last_mode" then
      return nil
    end
    return M._action(k)
  end,
})
