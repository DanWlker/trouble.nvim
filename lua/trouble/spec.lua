local Config = require("trouble.config")
local Util = require("trouble.util")

---@alias trouble.SorterFn fun(item: trouble.Item): any?

---@alias trouble.Sort.spec string|trouble.SorterFn|(string|trouble.SorterFn|trouble.Filter.spec)[]
---@alias trouble.Filter.spec table<string, any>|fun(items: trouble.Item[]): trouble.Item[]

---@alias trouble.Sections.spec (trouble.Section.spec|string)[]

---@class trouble.Section.spec
---@field source string
---@field title? string shown in the quickfix list title
---@field events? (string|trouble.Event)[]
---@field sort? trouble.Sort.spec
---@field filter? trouble.Filter.spec
---@field format? string template used to build the quickfix entry text
---@field max_items? number
---@field params? table<string, any>

---@alias trouble.Filter table<string, any>|fun(items: trouble.Item[]): trouble.Item[]

---@class trouble.Event
---@field event string|string[]
---@field pattern? string|string[]
---@field main? boolean When true, this event will refresh only when it is the main window

---@class trouble.Sort
---@field field? string
---@field sorter? trouble.SorterFn
---@field filter? trouble.Filter
---@field desc? boolean

---@class trouble.Section.opts
---@field source string
---@field title? string
---@field format string
---@field events trouble.Event[]
---@field sort? trouble.Sort[]
---@field filter? trouble.Filter
---@field max_items? number
---@field params? table<string, any>

local M = {}

---@param spec trouble.Section.spec|string
---@return trouble.Section.opts
function M.section(spec)
  local events = {} ---@type trouble.Event[]
  for _, e in ipairs(spec.events or {}) do
    if type(e) == "string" then
      local event, pattern = e:match("^(%w+)%s+(.*)$")
      event = event or e
      events[#events + 1] = { event = event, pattern = pattern }
    elseif type(e) == "table" and e.event then
      events[#events + 1] = e
    else
      error("invalid event: " .. vim.inspect(e))
    end
  end

  return {
    source = spec.source,
    title = type(spec.title) == "string" and spec.title or nil,
    sort = spec.sort and M.sort(spec.sort) or nil,
    filter = spec.filter,
    -- the quickfix list already shows the filename and position,
    -- so the default entry text is just the item's text
    format = spec.format or "{text}",
    events = events,
    params = spec.params,
  }
end

---@param action trouble.Action.spec
---@return trouble.Action
function M.action(action)
  if type(action) == "string" then
    action = { action = action, desc = action:gsub("_", " ") }
  end
  if type(action) == "function" then
    action = { action = action }
  end
  if type(action.action) == "string" then
    local desc = action.action:gsub("_", " ")
    action.action = require("trouble.config.actions")[action.action]
    if type(action.action) == "table" then
      action = action.action
    end
    action.desc = action.desc or desc
  end
  ---@cast action trouble.Action
  return action
end

---@param mode trouble.Mode
---@return trouble.Section.opts[]
function M.sections(mode)
  local ret = {} ---@type trouble.Section.opts[]

  if mode.sections then
    for _, s in ipairs(mode.sections) do
      ret[#ret + 1] = M.section(Config.get(mode, { sections = false }, s) --[[@as trouble.Mode]])
    end
  else
    local section = M.section(mode)
    section.max_items = section.max_items or mode.max_items
    ret[#ret + 1] = section
  end
  return ret
end

---@param spec trouble.Sort.spec
---@return trouble.Sort[]
function M.sort(spec)
  spec = type(spec) == "table" and Util.islist(spec) and spec or { spec }
  ---@cast spec (string|trouble.SorterFn|trouble.Filter.spec)[]
  local fields = {} ---@type trouble.Sort[]
  for f, field in ipairs(spec) do
    if type(field) == "function" then
      ---@cast field trouble.SorterFn
      fields[f] = { sorter = field }
    elseif type(field) == "table" and field.field then
      ---@cast field {field:string, desc?:boolean}
      fields[f] = field
    elseif type(field) == "table" then
      fields[f] = { filter = field }
    elseif type(field) == "string" then
      local desc = field:sub(1, 1) == "-"
      fields[f] = {
        field = desc and field:sub(2) or field,
        desc = desc and true or nil,
      }
    else
      error("invalid sort field: " .. vim.inspect(field))
    end
  end
  return fields
end

return M
