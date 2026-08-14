local Util = require("trouble.util")

---@alias trouble.Action.ctx {idx?: number, item?: trouble.Item, opts?: table}
---@alias trouble.ActionFn fun(list:trouble.List, ctx:trouble.Action.ctx)
---@alias trouble.Action {action: trouble.ActionFn, desc?: string, mode?: string}
---@alias trouble.Action.spec string|trouble.ActionFn|trouble.Action|{action: string}

-- NOTE: `refresh` is deliberately absent. `trouble.api` defines it, and that
-- shadows any action of the same name.

--- Only actions that do something the quickfix list can't do itself.
--- Navigation, jumping and window handling are left to Neovim.
---@class trouble.actions: {[string]: trouble.ActionFn}
local M = {
  -- Toggle whether the list is kept in sync with its source
  toggle_refresh = function(self)
    self.opts.auto_refresh = not self.opts.auto_refresh
    local enabled = self.opts.auto_refresh and "enabled" or "disabled"
    local notify = (enabled == "enabled") and Util.info or Util.warn
    notify("Auto refresh **" .. enabled .. "**", { id = "toggle_refresh" })
  end,
  -- Apply a filter to the items and rewrite the quickfix list
  filter = function(self, ctx)
    self:filter(ctx.opts.filter)
  end,
  -- Remove the item under the cursor from the list.
  -- This also disables auto refresh, so it doesn't come straight back.
  delete = function(self, ctx)
    local enabled = self.opts.auto_refresh
    self:delete(ctx.idx)
    if enabled and not self.opts.auto_refresh then
      Util.warn("Auto refresh **disabled**", { id = "toggle_refresh" })
    end
  end,
  -- Dump the source item under the cursor to the console
  inspect = function(_, ctx)
    vim.print(ctx.item)
  end,
}

return setmetatable(M, {
  __index = function(_, k)
    Util.error("Action not found: " .. k)
    -- keep callers from blowing up on a missing action
    return function() end
  end,
})
