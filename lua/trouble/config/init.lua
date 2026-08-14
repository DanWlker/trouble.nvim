---@class trouble.Config.mod: trouble.Config
local M = {}

---@class trouble.Mode: trouble.Config,trouble.Section.spec
---@field desc? string
---@field sections? string[]

---@class trouble.Config
---@field mode? string
---@field config? fun(opts:trouble.Config)
---@field formatters? table<string,trouble.Formatter> custom formatters
---@field filters? table<string, trouble.FilterFn> custom filters
---@field sorters? table<string, trouble.SorterFn> custom sorters
local defaults = {
  debug = false,
  auto_close = false, -- close the quickfix window when there are no items
  auto_open = false, -- open the quickfix window when there are items
  auto_refresh = true, -- auto refresh while the list is active
  auto_jump = false, -- auto jump to the item when there's only one
  focus = true, -- focus the quickfix window when opened
  max_items = 200, -- limit number of items that can be displayed per section
  pinned = false, -- When pinned, the list will be bound to the current buffer
  warn_no_results = true, -- show a warning when there are no results
  open_no_results = false, -- open the quickfix window when there are no results
  -- Options for the quickfix window itself.
  ---@type trouble.Qf.opts
  qf = {
    open_cmd = "botright copen", -- command used to open the quickfix window
    height = 10, -- height of the quickfix window. Set to `false` for the Neovim default.
  },
  -- Throttle/Debounce settings. Should usually not be changed.
  ---@type table<string, number|{ms:number, debounce?:boolean}>
  throttle = {
    refresh = 20, -- fetches new data when needed
    update = 10, -- writes the results to the quickfix list
  },
  ---@type table<string, trouble.Mode>
  modes = {
    -- sources define their own modes, which you can use directly,
    -- or override like in the example below
    lsp_references = {
      -- some modes are configurable, see the source code for more details
      params = {
        include_declaration = true,
      },
    },
    -- The LSP base mode for:
    -- * lsp_definitions, lsp_references, lsp_implementations
    -- * lsp_type_definitions, lsp_declarations, lsp_command
    lsp_base = {
      params = {
        -- don't include the current location in the results
        include_current = false,
      },
    },
    -- more advanced example that extends the lsp_document_symbols
    symbols = {
      desc = "document symbols",
      mode = "lsp_document_symbols",
      focus = false,
      filter = {
        -- remove Package since luals uses it for control flow structures
        ["not"] = { ft = "lua", kind = "Package" },
        any = {
          -- all symbol kinds for help / markdown files
          ft = { "help", "markdown" },
          -- default set of symbol kinds
          kind = {
            "Class",
            "Constructor",
            "Enum",
            "Field",
            "Function",
            "Interface",
            "Method",
            "Module",
            "Namespace",
            "Package",
            "Property",
            "Struct",
            "Trait",
          },
        },
      },
    },
  },
  -- stylua: ignore
  icons = {
    kinds = {
      Array         = " ",
      Boolean       = "󰨙 ",
      Class         = " ",
      Constant      = "󰏿 ",
      Constructor   = " ",
      Enum          = " ",
      EnumMember    = " ",
      Event         = " ",
      Field         = " ",
      File          = " ",
      Function      = "󰊕 ",
      Interface     = " ",
      Key           = " ",
      Method        = "󰊕 ",
      Module        = " ",
      Namespace     = "󰦮 ",
      Null          = " ",
      Number        = "󰎠 ",
      Object        = " ",
      Operator      = " ",
      Package       = " ",
      Property      = " ",
      String        = " ",
      Struct        = "󰆼 ",
      TypeParameter = " ",
      Variable      = "󰀫 ",
    },
  },
}

---@type trouble.Config
local options

---@param opts? trouble.Config
function M.setup(opts)
  if vim.fn.has("nvim-0.9.2") == 0 then
    local msg = "trouble.nvim requires Neovim >= 0.9.2"
    vim.notify_once(msg, vim.log.levels.ERROR, { title = "trouble.nvim" })
    error(msg)
    return
  end
  opts = opts or {}

  if opts.auto_open then
    require("trouble.util").warn({
      "You specified `auto_open = true` in your global config.",
      "This is probably not what you want.",
      "Add it to the mode you want to auto open instead.",
      "```lua",
      "opts = {",
      "  modes = {",
      "    diagnostics = { auto_open = true },",
      "  }",
      "}",
      "```",
      "Disabling global `auto_open`.",
    })
    opts.auto_open = nil
  end
  opts.mode = nil
  options = {}
  options = M.get(opts)
  vim.api.nvim_create_user_command("Trouble", function(input)
    require("trouble.command").execute(input)
  end, {
    nargs = "*",
    complete = function(...)
      return require("trouble.command").complete(...)
    end,
    desc = "Trouble",
  })
  require("trouble.main").setup()
  vim.schedule(function()
    for mode, mode_opts in pairs(options.modes) do
      if mode_opts.auto_open then
        require("trouble.list").new(M.get(mode))
      end
    end
  end)
  return options
end

--- Update the default config.
--- Should only be used by source to extend the default config.
---@param config trouble.Config
function M.defaults(config)
  options = vim.tbl_deep_extend("force", config, options)
end

function M.modes()
  require("trouble.sources").load()
  local ret = {} ---@type string[]
  for k, v in pairs(options.modes) do
    if v.source or v.mode or v.sections then
      ret[#ret + 1] = k
    end
  end
  table.sort(ret)
  return ret
end

---@param ...? trouble.Config|string
---@return trouble.Config
function M.get(...)
  options = options or M.setup()

  -- check if we need to load sources
  for i = 1, select("#", ...) do
    ---@type trouble.Config?
    local opts = select(i, ...)
    if type(opts) == "string" or (type(opts) == "table" and opts.mode) then
      M.modes() -- trigger loading of sources
      break
    end
  end

  ---@type trouble.Config[]
  local all = { {}, defaults, options or {} }

  ---@type table<string, boolean>
  local modes = {}
  local first_mode ---@type string?

  for i = 1, select("#", ...) do
    ---@type trouble.Config?
    local opts = select(i, ...)
    if type(opts) == "string" then
      opts = { mode = opts }
    end
    if opts then
      table.insert(all, opts)
      local idx = #all
      while opts.mode and not modes[opts.mode] do
        first_mode = first_mode or opts.mode
        modes[opts.mode or ""] = true
        opts = options.modes[opts.mode] or {}
        table.insert(all, idx, opts)
      end
    end
  end

  local ret = vim.tbl_deep_extend("force", unpack(all))

  if type(ret.config) == "function" then
    ret.config(ret)
  end
  ret.mode = first_mode

  return ret
end

return setmetatable(M, {
  __index = function(_, key)
    options = options or M.setup()
    assert(options, "should be setup")
    return options[key]
  end,
})
