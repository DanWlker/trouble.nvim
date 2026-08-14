local Main = require("trouble.main")
local Promise = require("trouble.promise")
local Qf = require("trouble.qf")
local Section = require("trouble.section")
local Spec = require("trouble.spec")
local Util = require("trouble.util")

---@class trouble.ListFilter
---@field id string
---@field filter trouble.Filter

---@class trouble.ListFilter.opts
---@field id? string
---@field toggle? boolean
---@field del? boolean

--- A trouble mode, backed by the quickfix list.
---@class trouble.List
---@field opts trouble.Mode
---@field sections trouble.Section[]
---@field first_update trouble.Promise
---@field list_id? number id of the quickfix / location list this mode owns
---@field list_win? number window the location list belongs to (nil for quickfix)
---@field _written? trouble.Qf.entry[] last entries written to the list
---@field _filters table<string, trouble.ListFilter>
local M = {}
M.__index = M

--- All lists, keyed by mode. There is only one quickfix list per mode.
---@type table<string, trouble.List>
M._lists = {}

---@param opts trouble.Mode
function M.new(opts)
  local self = setmetatable({}, M)
  self.opts = opts or {}
  self._filters = {}
  self.first_update = Promise.new(function() end)

  self.sections = {}
  for _, s in ipairs(Spec.sections(self.opts)) do
    local section = Section.new(s, self.opts)
    section.on_update = function()
      self:update()
    end
    -- only auto refresh while this list still owns the quickfix list
    section.enabled = function()
      return self:is_active()
    end
    table.insert(self.sections, section)
  end

  self.update = Util.throttle(M.update, Util.throttle_opts(self.opts.throttle.update, { ms = 10 }))

  if self.opts.mode then
    M._lists[self.opts.mode] = self
  end

  return self
end

--- Returns the existing list for a mode, if any.
---@param mode? string
---@return trouble.List?
function M.get(mode)
  return mode and M._lists[mode] or nil
end

---@return trouble.List[]
function M.all()
  return vim.tbl_values(M._lists)
end

--- The list that owns the quickfix list the quickfix commands act on.
---@return trouble.List?
function M.active()
  for _, list in pairs(M._lists) do
    if list:is_active() then
      return list
    end
  end
end

---@return trouble.Item[]
function M:items()
  local ret = {} ---@type trouble.Item[]
  for _, section in ipairs(self.sections) do
    vim.list_extend(ret, section.items)
  end
  return ret
end

---@return trouble.Qf.entry[]
function M:entries()
  local ret = {} ---@type trouble.Qf.entry[]
  for _, section in ipairs(self.sections) do
    vim.list_extend(ret, Qf.entries(section.items, section.section.format, self.opts))
  end
  return ret
end

function M:count()
  local count = 0
  for _, section in ipairs(self.sections) do
    count = count + #section.items
  end
  return count
end

--- Title shown by the quickfix window.
function M:title()
  local titles = {} ---@type string[]
  for _, section in ipairs(self.sections) do
    local title = section.section.title
    if type(title) == "string" and title ~= "" then
      titles[#titles + 1] = title
    end
  end
  if #titles > 0 then
    return "Trouble: " .. table.concat(titles, ", ")
  end
  return "Trouble: " .. (self.opts.mode or "results")
end

--- The window this mode's location list belongs to, or `nil` when it uses the
--- quickfix list. Location lists die with their window, so an invalid window
--- means the list is gone and has to be built again.
---@return number?
function M:win()
  if self.opts.list ~= "loclist" then
    return nil
  end
  if self.list_win and vim.api.nvim_win_is_valid(self.list_win) then
    return self.list_win
  end
  return nil
end

--- Picks the window a location list should attach to. Called when the user
--- explicitly loads the mode, so the list follows them to the window they are
--- actually working in.
function M:retarget()
  if self.opts.list ~= "loclist" then
    return
  end
  local main = Main.get()
  local win = main and main.win or vim.api.nvim_get_current_win()
  if win ~= self.list_win then
    -- a different window means a different location list
    self.list_win = win
    self.list_id = nil
    self._written = nil
  end
end

--- True when this mode's list is on screen.
function M:is_open()
  return self:is_active() and Qf.is_open(self:win())
end

--- True when this list is the one `:cnext` / `:lnext` currently act on.
function M:is_active()
  if self.opts.list == "loclist" and not self:win() then
    return false
  end
  return Qf.is_current(self:win(), self.list_id)
end

--- Writes the items to the quickfix list, creating it when needed,
--- then lets `QuickFixCmdPost` listeners (usually `cwindow`) react.
---
--- Auto refresh fires on events like `CursorHold` that usually produce the
--- exact same results. Rewriting the list anyway replaces the whole quickfix
--- buffer and makes the window flicker, so an unchanged result is skipped.
---
--- `force` means the user asked for this mode explicitly (`:Trouble <mode>`).
--- Only then is `QuickFixCmdPost` fired: that event means "a quickfix *command*
--- finished", and auto refresh is not a command. Firing it on every refresh
--- would let a `cwindow` autocmd reopen a window the user just closed.
---@param opts? {force?: boolean}
---@return boolean written
function M:write(opts)
  local win = self:win()
  if self.opts.list == "loclist" and not win then
    return false
  end
  local entries = self:entries()

  if not (opts and opts.force) and Qf.exists(win, self.list_id) and Qf.same(entries, self._written) then
    return false
  end

  local title = self:title()
  if Qf.exists(win, self.list_id) then
    Qf.replace(win, self.list_id, entries, title)
  else
    self.list_id = Qf.create(win, entries, title)
  end
  self._written = entries
  if opts and opts.force then
    Qf.post(win)
  end
  return true
end

function M:listen()
  for _, section in ipairs(self.sections) do
    section:listen()
  end
end

function M:stop()
  for _, section in ipairs(self.sections) do
    section:stop()
  end
end

---@param opts? {update?: boolean, opening?: boolean}
function M:refresh(opts)
  opts = opts or {}
  if not (opts.opening or self:is_active()) then
    return Promise.resolve()
  end
  ---@param section trouble.Section
  return Promise.all(vim.tbl_map(function(section)
    return section:refresh(opts)
  end, self.sections))
end

--- Called when the results of a section changed.
--- Never clobbers a quickfix list that isn't ours.
function M:update()
  if self:is_active() then
    self:write()
  end
end

--- Loads the mode into its list, makes it the current one, and shows it with
--- `:cwindow`/`:lwindow` (which hides it again when there are no results).
function M:open()
  self:retarget()
  self:listen()
  self
    :refresh({ update = false, opening = true })
    :next(function()
      local count = self:count()

      self:write({ force = true })
      Qf.activate(self:win(), self.list_id)

      -- `:cwindow`/`:lwindow`, so an empty result hides the window
      -- instead of leaving stale output on screen
      Qf.open(self:win())

      if count == 0 and self.opts.warn_no_results then
        local main = self.sections[1] and self.sections[1]:main()
        Util.warn({
          "No results for **" .. (self.opts.mode or "?") .. "**",
          main and ("Buffer: " .. vim.api.nvim_buf_get_name(main.buf)) or "",
        })
      end
    end)
    :next(self.first_update.resolve)
  return self
end

function M:wait(fn)
  self.first_update:next(fn)
end

--- The entry the quickfix list currently points at.
---@return {idx?: number, item?: trouble.Item}
function M:at()
  if not self:is_active() then
    return {}
  end
  local idx = Qf.idx(self:win())
  if idx < 1 then
    return {}
  end
  return { idx = idx, item = self:item_at(idx) }
end

--- The item at a 1-based index across all sections,
--- without materialising the whole list.
---@param idx number
---@return trouble.Item?
function M:item_at(idx)
  local offset = 0
  for _, section in ipairs(self.sections) do
    local n = #section.items
    if idx <= offset + n then
      return section.items[idx - offset]
    end
    offset = offset + n
  end
end

--- Removes the entry at `idx` from the list, and disables auto refresh
--- so that it doesn't immediately come back.
---@param idx? number
function M:delete(idx)
  idx = idx or Qf.idx(self:win())
  if not idx or idx < 1 then
    return
  end
  local offset = 0
  for _, section in ipairs(self.sections) do
    local n = #section.items
    if idx <= offset + n then
      table.remove(section.items, idx - offset)
      self.opts.auto_refresh = false
      self:write()
      return
    end
    offset = offset + n
  end
end

---@param action trouble.Action.spec
---@param opts? table
function M:action(action, opts)
  action = Spec.action(action)
  self:wait(function()
    local at = self:at()
    action.action(self, {
      idx = at.idx,
      item = at.item,
      opts = type(opts) == "table" and opts or {},
    })
  end)
end

---@param filter trouble.Filter
---@param opts? trouble.ListFilter.opts
function M:filter(filter, opts)
  opts = opts or {}

  ---@type trouble.ListFilter
  local list_filter = vim.tbl_deep_extend("force", {
    id = vim.inspect(filter),
    filter = filter,
  }, opts)

  if opts.del or (opts.toggle and self._filters[list_filter.id]) then
    self._filters[list_filter.id] = nil
  else
    self._filters[list_filter.id] = list_filter
  end

  local filters = vim.tbl_count(self._filters) > 0
      and vim.tbl_map(function(f)
        return f.filter
      end, vim.tbl_values(self._filters))
    or nil

  for _, section in ipairs(self.sections) do
    section.filter = filters
  end
  self:refresh({ opening = true })
end

return M
