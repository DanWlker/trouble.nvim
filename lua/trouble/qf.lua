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

--- True when two entry lists would render identically.
--- Rewriting the list replaces the whole quickfix buffer, which makes the
--- window redraw and its syntax flash, so an unchanged result must not be
--- written back.
---@param a trouble.Qf.entry[]
---@param b? trouble.Qf.entry[]
function M.same(a, b)
  if not b or #a ~= #b then
    return false
  end
  for i = 1, #a do
    local x, y = a[i], b[i]
    if
      x.bufnr ~= y.bufnr
      or x.filename ~= y.filename
      or x.lnum ~= y.lnum
      or x.col ~= y.col
      or x.end_lnum ~= y.end_lnum
      or x.end_col ~= y.end_col
      or x.type ~= y.type
      or x.text ~= y.text
    then
      return false
    end
  end
  return true
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

--- Every function below takes a `win`:
---   * `nil`    -> the quickfix list
---   * a winid  -> that window's location list
--- Location lists are window-local, which is what makes them the right home for
--- buffer-scoped results (document symbols, diagnostics for the current buffer).

---@param win? number
---@param what table
local function get(win, what)
  if win then
    return vim.fn.getloclist(win, what)
  end
  return vim.fn.getqflist(what)
end

---@param win? number
---@param action string
---@param what table
local function set(win, action, what)
  if win then
    return vim.fn.setloclist(win, {}, action, what)
  end
  return vim.fn.setqflist({}, action, what)
end

--- Returns the id of the current list, or `0` when the stack is empty.
---@param win? number
---@return number
function M.current(win)
  return get(win, { id = 0 }).id or 0
end

--- True when `id` still refers to a list in the stack.
---@param win? number
---@param id? number
function M.exists(win, id)
  if not id or id == 0 then
    return false
  end
  if win and not vim.api.nvim_win_is_valid(win) then
    return false
  end
  return get(win, { id = id, nr = 0 }).id == id
end

--- True when `id` is the list that `:cnext`/`:lnext` currently operate on.
---@param win? number
---@param id? number
function M.is_current(win, id)
  if id == nil or id == 0 then
    return false
  end
  if win and not vim.api.nvim_win_is_valid(win) then
    return false
  end
  return M.current(win) == id
end

--- Creates a new list and returns its id.
---@param win? number
---@param entries trouble.Qf.entry[]
---@param title string
---@return number id
function M.create(win, entries, title)
  set(win, " ", { title = title, items = entries })
  return M.current(win)
end

--- Replaces the contents of an existing list, keeping its position in the
--- stack, the current entry, and the cursor position in its window.
--- Without this, every auto refresh would send `:cnext` back to the first entry.
---@param win? number
---@param id number
---@param entries trouble.Qf.entry[]
---@param title string
function M.replace(win, id, entries, title)
  local lwin = M.is_current(win, id) and M.win(win) or nil
  local cursor = lwin and vim.api.nvim_win_get_cursor(lwin) or nil
  local idx = get(win, { id = id, idx = 0 }).idx or 0

  local what = { id = id, title = title, items = entries }
  if idx > 0 and #entries > 0 then
    what.idx = math.min(idx, #entries)
  end
  set(win, "r", what)

  if lwin and cursor and vim.api.nvim_win_is_valid(lwin) then
    local lines = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(lwin))
    cursor[1] = math.max(1, math.min(cursor[1], lines))
    pcall(vim.api.nvim_win_set_cursor, lwin, cursor)
  end
end

--- Makes the list with the given id the current one.
---@param win? number
---@param id number
function M.activate(win, id)
  if M.is_current(win, id) or not M.exists(win, id) then
    return
  end
  local nr = get(win, { id = id, nr = 0 }).nr
  if not (nr and nr > 0) then
    return
  end
  if win then
    vim.api.nvim_win_call(win, function()
      pcall(vim.cmd, ("silent %dlhistory"):format(nr))
    end)
  else
    pcall(vim.cmd, ("silent %dchistory"):format(nr))
  end
end

--- The window displaying the list, if it is open.
--- Only used to keep the cursor steady across a rewrite. Opening and closing is
--- `:copen`/`:cclose`/`:cwindow` (or `:lopen`/`:lclose`/`:lwindow`), and is
--- left to the user.
---@param win? number
---@return number?
function M.win(win)
  if win and not vim.api.nvim_win_is_valid(win) then
    return nil
  end
  local id = get(win, { winid = 0 }).winid or 0
  return id ~= 0 and id or nil
end

---@param win? number
function M.is_open(win)
  return M.win(win) ~= nil
end

--- `:cwindow` / `:lwindow`: opens the window when the list has entries, closes
--- it when it doesn't. Deliberately not `:copen` — letting Vim decide is what
--- makes "no results" and "results went away" behave sensibly for free.
---@param win? number
function M.open(win)
  if win then
    vim.api.nvim_win_call(win, function()
      vim.cmd("lwindow")
    end)
  else
    vim.cmd("cwindow")
  end
end

---@param win? number
function M.close(win)
  if not M.is_open(win) then
    return
  end
  if win then
    vim.api.nvim_win_call(win, function()
      vim.cmd("lclose")
    end)
  else
    vim.cmd("cclose")
  end
end

--- Fires `QuickFixCmdPost` the way `:vimgrep` and `:lvimgrep` do, so any
--- existing autocmds pick the results up. The pattern mirrors Vim's own
--- `grep` vs `lgrep` naming, so `[^l]*` and `l*` filters keep working.
---@param win? number
function M.post(win)
  vim.api.nvim_exec_autocmds("QuickFixCmdPost", {
    pattern = win and "lTrouble" or "Trouble",
    modeline = false,
  })
end

--- Index of the entry the quickfix commands currently point at.
---@return number
---@param win? number
function M.idx(win)
  local lwin = M.win(win)
  if lwin and vim.api.nvim_get_current_win() == lwin then
    return vim.api.nvim_win_get_cursor(lwin)[1]
  end
  return get(win, { idx = 0 }).idx or 0
end

---@param win? number
function M.count(win)
  return get(win, { size = 0 }).size or 0
end

return M
