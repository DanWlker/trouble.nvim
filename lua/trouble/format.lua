local Util = require("trouble.util")

local M = {}

---@alias trouble.spec.format string|trouble.Format|(string|trouble.Format)[]
---@alias trouble.Format {text:string, fi?:string}

---@alias trouble.Formatter fun(ctx: trouble.Formatter.ctx): trouble.spec.format?
---@alias trouble.Formatter.ctx {item: trouble.Item, field:string, value:string, opts:trouble.Config}

---@type (fun(file: string, ext: string): string, string)[]
local icons = {
  function(file)
    return require("mini.icons").get("file", file)
  end,
  function(file, ext)
    return require("nvim-web-devicons").get_icon(file, ext, { default = true })
  end,
}
function M.get_icon(file, ext)
  while #icons > 0 do
    local ok, icon = pcall(icons[1], file, ext)
    if ok then
      return icon
    end
    table.remove(icons, 1)
  end
end

---@param fn trouble.Formatter
---@param field string
function M.cached_formatter(fn, field)
  local cache = {}
  ---@param ctx trouble.Formatter.ctx
  return function(ctx)
    local key = ctx.item.source .. field .. (ctx.item[field] or "")
    local result = cache[key]
    if result then
      return result
    end
    result = fn(ctx)
    cache[key] = result
    return result
  end
end

---@type table<string, trouble.Formatter>
M.formatters = {
  pos = function(ctx)
    return {
      text = "[" .. ctx.item.pos[1] .. ", " .. (ctx.item.pos[2] + 1) .. "]",
    }
  end,
  code = function(ctx)
    if not ctx.item.code or ctx.item.code == vim.NIL then
      return
    end
    return { text = "(" .. ctx.item.code .. ")" }
  end,
  severity = function(ctx)
    local severity = ctx.item.severity or vim.diagnostic.severity.ERROR
    local name = vim.diagnostic.severity[severity] or "OTHER"
    return { text = name }
  end,
  severity_icon = function(ctx)
    local severity = ctx.item.severity or vim.diagnostic.severity.ERROR
    if not vim.diagnostic.severity[severity] then
      return
    end
    if type(severity) == "string" then
      severity = vim.diagnostic.severity[severity:upper()] or vim.diagnostic.severity.ERROR
    end
    local name = Util.camel(vim.diagnostic.severity[severity]:lower())
    local sign = vim.fn.sign_getdefined("DiagnosticSign" .. name)[1]
    if vim.fn.has("nvim-0.10.0") == 1 then
      local config = vim.diagnostic.config() or {}
      if config.signs == nil or type(config.signs) == "boolean" then
        return { text = sign and sign.text or name:sub(1, 1) }
      end
      local signs = config.signs or {}
      if type(signs) == "function" then
        signs = signs(0, 0) --[[@as vim.diagnostic.Opts.Signs]]
      end
      return {
        text = type(signs) == "table" and signs.text and signs.text[severity] or sign and sign.text or name:sub(1, 1),
      }
    else
      return sign and { text = sign.text } or { text = name } or nil
    end
  end,
  file_icon = function(ctx)
    local item = ctx.item --[[@as Diagnostic|trouble.Item]]
    local file = vim.fn.fnamemodify(item.filename, ":t")
    local ext = vim.fn.fnamemodify(item.filename, ":e")
    local icon = M.get_icon(file, ext)
    return icon and { text = icon .. " " } or ""
  end,
  -- Indents nested items (LSP document symbols) by their depth,
  -- since the quickfix list has no notion of a hierarchy.
  indent = function(ctx)
    local depth = 0
    local parent = ctx.item.parent
    while parent do
      depth = depth + 1
      parent = parent.parent
    end
    if depth == 0 then
      return
    end
    return { text = ("  "):rep(depth) }
  end,
  filename = function(ctx)
    return {
      text = vim.fn.fnamemodify(ctx.item.filename, ":p:~:."),
    }
  end,
  dirname = function(ctx)
    return {
      text = vim.fn.fnamemodify(ctx.item.dirname, ":p:~:."),
    }
  end,
  kind_icon = function(ctx)
    if not ctx.item.kind then
      return
    end
    local icon = ctx.opts.icons.kinds[ctx.item.kind]
    if icon then
      return { text = icon }
    end
  end,
}
M.formatters.severity_icon = M.cached_formatter(M.formatters.severity_icon, "severity")
M.formatters.severity = M.cached_formatter(M.formatters.severity, "severity")

---@param ctx trouble.Formatter.ctx
function M.field(ctx)
  -- NOTE: not trimmed here. `M.text` collapses whitespace for multi-field
  -- formats, and a lone `{text}` has to keep the source line's indentation
  -- so that `col`/`end_col` still index into it.
  ---@type trouble.Format[]
  local format = { { fi = ctx.field, text = tostring(ctx.item[ctx.field] or "") } }

  local opts = ctx.opts

  local formatter = opts.formatters and opts.formatters[ctx.field] or M.formatters[ctx.field]

  if formatter then
    local result = formatter(ctx)
    if not result then
      return
    end
    result = type(result) == "table" and Util.islist(result) and result or { result }
    format = {}
    ---@cast result (string|trouble.Format)[]
    for _, f in ipairs(result) do
      ---@diagnostic disable-next-line: assign-type-mismatch
      format[#format + 1] = type(f) == "string" and { text = f } or f
    end
  end
  for _, f in ipairs(format) do
    f.fi = f.fi or ctx.field
  end
  return format
end

---@param format string
---@param ctx {item: trouble.Item, opts:trouble.Config}
function M.format(format, ctx)
  ---@type trouble.Format[]
  local ret = {}
  while true do
    ---@type string?,string,string
    local before, fields, after = format:match("^(.-){(.-)}(.*)$")
    if not before then
      break
    end
    format = after
    if #before > 0 then
      ret[#ret + 1] = { text = before }
    end

    for _, field in Util.split(fields, "|") do
      -- a `{field:Group}` suffix used to pick a highlight group. The quickfix
      -- list has no per-entry highlights, so the suffix is accepted and ignored.
      field = field:match("^(.-):.+$") or field
      ---@cast ctx trouble.Formatter.ctx
      ctx.field = field
      ctx.value = ctx.item[field]
      local ff = M.field(ctx)
      if ff then
        vim.list_extend(ret, ff)
        -- only render the first field that resolves
        break
      end
    end
  end
  if #format > 0 then
    ret[#ret + 1] = { text = format }
  end
  return ret
end

--- Renders a format template to a single line of plain text.
--- Quickfix entries can't span multiple lines and have no highlights,
--- so newlines are squashed and highlight groups are dropped.
--- A leading `{indent}` is kept, everything else is trimmed.
---@param format string
---@param ctx {item: trouble.Item, opts:trouble.Config}
---@return string
function M.text(format, ctx)
  local segments = M.format(format, ctx)

  -- A format that is nothing but `{text}` passes the source line through
  -- verbatim, including its indentation, so that `col`/`end_col` still index
  -- into it. nvim-bqf and quicker.nvim rely on that to highlight the match.
  if #segments == 1 and segments[1].fi == "text" then
    return (segments[1].text:gsub("[\n\r]+", " "))
  end

  local indent = ""
  local parts = {} ---@type string[]

  for i, f in ipairs(segments) do
    if i == 1 and f.fi == "indent" then
      indent = f.text
    else
      parts[#parts + 1] = f.text
    end
  end

  local text = table.concat(parts):gsub("[\n\r]+", " ")
  -- fields that resolve to an empty string leave gaps behind
  text = vim.trim(text):gsub("%s%s+", " ")
  return indent .. text
end

return M
