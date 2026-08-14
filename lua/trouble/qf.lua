local Format = require("trouble.format")

--- Conversion of `trouble.Item`s to quickfix entries, and writing them to the
--- quickfix list. Nothing here opens, closes or focuses a window: that is what
--- `:copen`, `:cclose` and `:cwindow` are for.
local M = {}

---@class trouble.Qf.entry
---@field bufnr? number
---@field filename? string
---@field lnum number
---@field col number
---@field end_lnum? number
---@field end_col? number
---@field text string
---@field type? string
---@field valid number

--- Maps `vim.diagnostic.severity` to a quickfix entry type.
---@type table<number, string>
M.types = {
  [vim.diagnostic.severity.ERROR] = "E",
  [vim.diagnostic.severity.WARN] = "W",
  [vim.diagnostic.severity.INFO] = "I",
  [vim.diagnostic.severity.HINT] = "N",
}

--- Converts a single item to a quickfix entry.
--- `pos`/`end_pos` are `(1,0)`-indexed, while quickfix columns are `1`-indexed.
---@param item trouble.Item
---@param format string
---@param opts trouble.Config
---@return trouble.Qf.entry
function M.entry(item, format, opts)
  ---@type trouble.Qf.entry
  local entry = {
    lnum = item.pos[1],
    col = item.pos[2] + 1,
    text = Format.text(format, { item = item, opts = opts }),
    valid = 1,
  }

  -- prefer a real buffer, so that quickfix picks up unsaved changes
  if item.buf and vim.api.nvim_buf_is_valid(item.buf) then
    entry.bufnr = item.buf
  else
    entry.filename = item.filename
  end

  local end_pos = item.end_pos
  if end_pos and end_pos[1] >= entry.lnum then
    entry.end_lnum = end_pos[1]
    entry.end_col = end_pos[2] + 1
  end

  local severity = item.severity
  if severity and M.types[severity] then
    entry.type = M.types[severity]
  end

  return entry
end

---@param items trouble.Item[]
---@param format string
---@param opts trouble.Config
---@return trouble.Qf.entry[]
function M.entries(items, format, opts)
  local ret = {} ---@type trouble.Qf.entry[]
  for _, item in ipairs(items) do
    ret[#ret + 1] = M.entry(item, format, opts)
  end
  return ret
end

--- Returns the id of the current quickfix list, or `0` when the stack is empty.
---@return number
function M.current()
  return vim.fn.getqflist({ id = 0 }).id or 0
end

--- True when `id` still refers to a list in the quickfix stack.
---@param id? number
function M.exists(id)
  if not id or id == 0 then
    return false
  end
  return vim.fn.getqflist({ id = id, nr = 0 }).id == id
end

--- True when `id` is the list the quickfix commands currently operate on.
---@param id? number
function M.is_current(id)
  return id ~= nil and id ~= 0 and M.current() == id
end

--- Creates a new quickfix list and returns its id.
---@param entries trouble.Qf.entry[]
---@param title string
---@return number id
function M.create(entries, title)
  vim.fn.setqflist({}, " ", { title = title, items = entries })
  return M.current()
end

--- Replaces the contents of an existing quickfix list, keeping its position in
--- the stack, the current entry, and the cursor position in the quickfix window.
--- Without this, every auto refresh would send `:cnext` back to the first entry.
---@param id number
---@param entries trouble.Qf.entry[]
---@param title string
function M.replace(id, entries, title)
  local win = M.is_current(id) and M.win() or nil
  local cursor = win and vim.api.nvim_win_get_cursor(win) or nil
  local idx = vim.fn.getqflist({ id = id, idx = 0 }).idx or 0

  local what = { id = id, title = title, items = entries }
  if idx > 0 and #entries > 0 then
    what.idx = math.min(idx, #entries)
  end
  vim.fn.setqflist({}, "r", what)

  if win and cursor and vim.api.nvim_win_is_valid(win) then
    local lines = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(win))
    cursor[1] = math.max(1, math.min(cursor[1], lines))
    pcall(vim.api.nvim_win_set_cursor, win, cursor)
  end
end

--- Makes the list with the given id the current one.
---@param id number
function M.activate(id)
  if M.is_current(id) or not M.exists(id) then
    return
  end
  local nr = vim.fn.getqflist({ id = id, nr = 0 }).nr
  if nr and nr > 0 then
    pcall(vim.cmd, ("silent %dchistory"):format(nr))
  end
end

--- Returns the window id of the quickfix window, if it is open.
--- Only used to keep the cursor steady across a rewrite. Opening and closing
--- the window is `:copen` / `:cclose` / `:cwindow`, and is left to the user.
---@return number?
function M.win()
  for _, win in ipairs(vim.fn.getwininfo()) do
    if win.quickfix == 1 and win.loclist == 0 then
      return win.winid
    end
  end
end

--- Fires `QuickFixCmdPost` with a `Trouble` pattern, the same way `:vimgrep`
--- and `:make` do, so that the usual `cwindow` autocmd picks up the results.
function M.post()
  vim.api.nvim_exec_autocmds("QuickFixCmdPost", { pattern = "Trouble", modeline = false })
end

--- Index of the entry the quickfix commands currently point at.
---@return number
function M.idx()
  local win = M.win()
  if win and vim.api.nvim_get_current_win() == win then
    return vim.api.nvim_win_get_cursor(win)[1]
  end
  return vim.fn.getqflist({ idx = 0 }).idx or 0
end

function M.count()
  return vim.fn.getqflist({ size = 0 }).size or 0
end

return M
