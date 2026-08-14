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
---@field qf_id? number
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
      return self:is_active() or self.opts.auto_open == true
    end
    table.insert(self.sections, section)
  end

  self.update = Util.throttle(M.update, Util.throttle_opts(self.opts.throttle.update, { ms = 10 }))

  if self.opts.mode then
    M._lists[self.opts.mode] = self
  end

  if self.opts.auto_open then
    self:listen()
    self:refresh()
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

--- True when this list is the quickfix list that `:cnext` and friends act on.
function M:is_active()
  return Qf.is_current(self.qf_id)
end

--- True when the quickfix window is open and showing this list.
function M:is_open()
  return self:is_active() and Qf.is_open()
end

--- Writes the items to the quickfix list, creating it when needed.
function M:write()
  local entries = self:entries()
  local title = self:title()
  if Qf.exists(self.qf_id) then
    Qf.replace(self.qf_id, entries, title)
  else
    self.qf_id = Qf.create(entries, title)
  end
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
  if not (opts.opening or self:is_active() or self.opts.auto_open) then
    return Promise.resolve()
  end
  ---@param section trouble.Section
  return Promise.all(vim.tbl_map(function(section)
    return section:refresh(opts)
  end, self.sections))
end

--- Called when the results of a section changed.
function M:update()
  local count = self:count()

  if self.opts.auto_open and count > 0 and not self:is_open() then
    self:write()
    Qf.activate(self.qf_id)
    Qf.open(self.opts)
    return
  end

  -- Never clobber a quickfix list that isn't ours.
  if not self:is_active() then
    return
  end

  self:write()

  if count == 0 and self.opts.auto_close and Qf.is_open() then
    Qf.close()
  end
end

function M:open()
  self:listen()
  self
    :refresh({ update = false, opening = true })
    :next(function()
      local count = self:count()
      if count == 0 then
        if not self.opts.open_no_results then
          -- don't leave stale results behind in a list we already own
          if Qf.exists(self.qf_id) then
            self:write()
          end
          if self.opts.warn_no_results then
            local main = self.sections[1] and self.sections[1]:main()
            Util.warn({
              "No results for **" .. (self.opts.mode or "?") .. "**",
              main and ("Buffer: " .. vim.api.nvim_buf_get_name(main.buf)) or "",
            })
          end
          return
        end
      elseif count == 1 and self.opts.auto_jump then
        self:write()
        Qf.activate(self.qf_id)
        -- jump straight to the only result, without showing the list
        if Qf.is_open() then
          Qf.close()
        end
        vim.cmd("cfirst")
        return
      end
      self:write()
      Qf.activate(self.qf_id)
      Qf.open(self.opts)
    end)
    :next(self.first_update.resolve)
  return self
end

function M:close()
  if self:is_open() then
    Qf.close()
  end
  if not self.opts.auto_open then
    self:stop()
  end
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
  local idx = Qf.idx()
  if idx < 1 then
    return {}
  end
  return { idx = idx, item = self:items()[idx] }
end

--- Removes the entry at `idx` from the list, and disables auto refresh
--- so that it doesn't immediately come back.
---@param idx? number
function M:delete(idx)
  idx = idx or Qf.idx()
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

---@param id string
function M:get_filter(id)
  return self._filters[id]
end

return M
