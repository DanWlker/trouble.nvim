# 🚦 Trouble

Collects diagnostics, LSP results and picker results, and puts them in Neovim's
built-in **quickfix list** — filtered, sorted and formatted, and kept up to date
while you work.

This is a fork of [trouble.nvim](https://github.com/folke/trouble.nvim) with its
custom window UI removed. You get trouble's sources, filters, sorters and modes;
Neovim does everything else.

Trouble's entire job is to **fill a quickfix or location list and keep it fresh**.
`:Trouble <mode>` loads the results and shows them; running it again closes the
window, so the command toggles. Everything you then *do* with the results is a
plain quickfix command — trouble adds no navigation, jumping or preview of its own.

Project-wide results go to the **quickfix list**. Buffer-scoped results — document
symbols, diagnostics for the current buffer — go to that window's **location
list**, because that is what location lists are for.

## ✨ Features

- Diagnostics
- LSP references
- LSP implementations
- LSP definitions
- LSP type definitions
- LSP Document Symbols
- LSP Incoming/Outgoing calls

All of them land in the quickfix list, filtered, sorted and kept up to date.

Pickers are **not** included: Telescope, fzf-lua and snacks.picker all send
their results to the quickfix list themselves. See [Pickers](#-pickers).

## 📰 What's different from trouble.nvim?

Everything that draws a window is gone; everything that produces items stays:

- results are written to the **quickfix list**, and that's the whole output
- no custom window, no preview window, no folds, no indent guides, no highlight groups
- no trouble keymaps — the quickfix window keeps its own
- window handling is `:cwindow`/`:lwindow` under the hood, so there is no
  `focus`, no `auto_open`/`auto_close`, and no size or position options —
  an empty result hides the window, a non-empty one shows it
- the `qflist`, `loclist` and `quickfix` modes are gone, since the quickfix list is now the output
- the `statusline` component is gone
- the `telescope`, `fzf` and `snacks` sources are gone: those pickers already
  have a "send to quickfix list" action, which is now the same destination
- item `groups` are gone: the quickfix list is flat and already shows the filename and position
- navigation actions (`next`, `prev`, `jump*`, `focus`, `close`, ...) are gone —
  use `:cnext`, `:cprev`, `:cc`, `:copen`, `:cclose` and friends
- the actions that remain (`refresh`, `toggle_refresh`, `filter`, `delete`,
  `inspect`) act on trouble's items, which quickfix can't do itself
- everything else — sources, `modes`, `filter`, `sort`, `format`, `params`,
  custom formatters/filters/sorters — works as before

Each mode gets its **own** quickfix list, reused across opens, so switching modes
doesn't pile up entries in the quickfix stack. A quickfix list that trouble
doesn't own is never modified.

## ⚡️ Requirements

- Neovim >= 0.9.2
- Properly configured Neovim LSP client
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) or
  [mini.icons](https://github.com/echasnovski/mini.icons) is optional, to enable icons in entry text
- a [patched font](https://www.nerdfonts.com/) if you use the kind icons

## 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "folke/trouble.nvim",
  opts = {}, -- for default options, refer to the configuration section for custom setup.
  cmd = "Trouble",
  keys = {
    { "<leader>xx", "<cmd>Trouble diagnostics<cr>", desc = "Diagnostics (Trouble)" },
    { "<leader>xX", "<cmd>Trouble diagnostics_buffer<cr>", desc = "Buffer Diagnostics (Trouble)" },
    { "<leader>cs", "<cmd>Trouble symbols<cr>", desc = "Symbols (Trouble)" },
    { "<leader>cl", "<cmd>Trouble lsp<cr>", desc = "LSP Definitions / references / ... (Trouble)" },
  },
}
```

Each of those is a toggle: press it again and the window closes.

## ⚙️ Configuration

### Setup

**Trouble** is highly configurable. Please refer to the default settings below.

<details><summary>Default Settings</summary>

<!-- config:start -->

```lua
---@class trouble.Mode: trouble.Config,trouble.Section.spec
---@field desc? string
---@field sections? string[]

---@class trouble.Config
---@field mode? string
---@field list? "quickfix"|"loclist"
---@field config? fun(opts:trouble.Config)
---@field formatters? table<string,trouble.Formatter> custom formatters
---@field filters? table<string, trouble.FilterFn> custom filters
---@field sorters? table<string, trouble.SorterFn> custom sorters
local defaults = {
  -- Where results go. Buffer-scoped modes default to "loclist", since a
  -- location list is window-local; project-wide modes use the quickfix list.
  ---@type "quickfix"|"loclist"
  list = "quickfix",
  auto_refresh = true, -- keep the list in sync while it is the current one
  max_items = 200, -- limit number of items that can be displayed per section
  pinned = false, -- When pinned, the list will be bound to the current buffer
  warn_no_results = true, -- show a warning when there are no results
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
    -- diagnostics for the current buffer only. Buffer-scoped, so it belongs
    -- in the window's location list rather than the global quickfix list.
    diagnostics_buffer = {
      desc = "buffer diagnostics",
      mode = "diagnostics",
      title = "Buffer Diagnostics",
      list = "loclist",
      filter = { buf = 0 },
    },
    -- more advanced example that extends the lsp_document_symbols
    symbols = {
      desc = "document symbols",
      mode = "lsp_document_symbols",
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
```

<!-- config:end -->

</details>

Make sure to check the [Examples](/docs/examples.md)!

## 🚀 Usage

### Commands

The **Trouble** command is a wrapper around the **Trouble** API.
It can do anything the regular API can do.

- `Trouble [mode] [action] [options]`

Some examples:

- Load diagnostics for the current buffer only:
  - `Trouble diagnostics filter.buf=0`
- Load document symbols, keeping them in sync with the buffer you started the command in:
  - `Trouble symbols pinned=true`
- You can use **lua** code in the options for the `Trouble` command.
  The examples below all do the same thing.
  - `Trouble diagnostics filter.severity=vim.diagnostic.severity.ERROR`
  - `Trouble diagnostics filter.severity = vim.diagnostic.severity.ERROR`
  - `Trouble diagnostics filter = { severity=vim.diagnostic.severity.ERROR }`
- Merging of nested options, with or without quoting strings:
  - `Trouble diagnostics filter.any.buf=0 filter.any.severity=1`
  - `Trouble diagnostics filter = { any = { buf = 0, severity = 1 } }`

Loading a mode with different options rebuilds its list in place, so
`Trouble diagnostics filter.buf=0` re-filters the same quickfix list instead of
pushing a new one onto the stack.

### The quickfix window is yours

Trouble fills the list and stops there. Everything you'd do with the results is
a quickfix command, and trouble deliberately provides no equivalent:

| Task | Quickfix | Location list |
| --- | --- | --- |
| Open / close the window | `:copen` / `:cclose` | `:lopen` / `:lclose` |
| Open if there are results, close if not | `:cwindow` | `:lwindow` |
| Jump to an entry | `<CR>`, or `:cc` | `<CR>`, or `:ll` |
| Open in a split | `Ctrl-W Enter` | `Ctrl-W Enter` |
| Next / previous entry | `:cnext` / `:cprev` | `:lnext` / `:lprev` |
| First / last entry | `:cfirst` / `:clast` | `:lfirst` / `:llast` |
| Run a command over every entry | `:cdo` | `:ldo` |
| Switch between mode lists | `:colder` / `:cnewer` | `:lolder` / `:lnewer` |

### Which list does a mode use?

| Mode | List | Why |
| --- | --- | --- |
| `diagnostics` | quickfix | spans the whole project |
| `diagnostics_buffer` | location | one buffer |
| `lsp_document_symbols`, `symbols` | location | one buffer |
| every other `lsp_*` mode | quickfix | results span the project |

Override it per mode or per call with `list=quickfix` / `list=loclist`:

```vim
:Trouble diagnostics list=loclist    " just this buffer's window
:Trouble symbols list=quickfix
```

A location list belongs to the window that was current when you loaded the mode.
Load it again from another window and it retargets there, leaving the first
window's list intact. Close the window and the list goes with it.

### Showing and hiding

`:Trouble <mode>` runs `:cwindow` (or `:lwindow`), so the window appears when
there are results and stays away when there aren't. Running the same mode again
closes it. Switching to a *different* mode never closes — it shows the new list.

Auto refresh never touches the window. Close it and it stays closed while the
list keeps updating behind you, so a background re-lint can't pop it back open.

Trouble also fires **`QuickFixCmdPost`** when you load a mode — the same hook
`:vimgrep` and `:make` use — with pattern `Trouble` for the quickfix list and
`lTrouble` for a location list, mirroring Vim's `grep` / `lgrep` naming. You
don't need it for the window, but it's there if you want to hook the results.

The actions that remain are the ones the quickfix list can't do for itself,
because they act on trouble's items rather than on the window:

```vim
:Trouble diagnostics refresh         " refetch from the source
:Trouble diagnostics toggle_refresh  " stop/resume keeping the list in sync
:Trouble diagnostics filter filter.severity=1
:Trouble diagnostics delete          " drop the current entry, and stop auto refresh
:Trouble diagnostics inspect         " print the raw source item
```

Loading a mode makes its quickfix list the current one, so the quickfix commands
above act on it right away.

Please refer to the API section for more information on the available actions and options.

Modes:

<!-- modes:start -->

- **diagnostics**: diagnostics
- **diagnostics_buffer**: buffer diagnostics
- **lsp**: LSP definitions, references, implementations, type definitions, and declarations
- **lsp_command**: command
- **lsp_declarations**: declarations
- **lsp_definitions**: definitions
- **lsp_document_symbols**: document symbols
- **lsp_implementations**: implementations
- **lsp_incoming_calls**: Incoming Calls
- **lsp_outgoing_calls**: Outgoing Calls
- **lsp_references**: references
- **lsp_type_definitions**: type definitions
- **symbols**: document symbols

<!-- modes:end -->

### Filters

Please refer to the [filter docs](docs/filter.md) for more information examples on filters.

### API

You can use the following functions in your keybindings:

<details><summary>API</summary>

<!-- api:start -->

```lua
-- Loads the given mode into its quickfix or location list and shows it.
-- Running it again for a mode that is already on screen closes the window, so
-- `:Trouble <mode>` toggles. Switching to a different mode never closes.
---@param opts? trouble.Mode | { refresh?: boolean } | string
---@return trouble.List?
require("trouble").open(opts)

-- Refresh the given mode, or all modes when none is given.
-- Normally this is done automatically, unless you disabled auto refresh.
---@param opts? trouble.Mode|string
require("trouble").refresh(opts)

-- Get all items for a given mode.
---@param opts? trouble.Mode|string
require("trouble").get_items(opts)

-- Returns the number of entries in the list a mode writes to.
---@param opts? trouble.Mode|string
require("trouble").count(opts)

-- Remove the item under the cursor from the list.
-- This also disables auto refresh, so it doesn't come straight back.
---@param opts? trouble.Mode | string
---@return trouble.List
require("trouble").delete(opts)

-- Apply a filter to the items and rewrite the quickfix list
---@param opts? trouble.Mode | string
---@return trouble.List
require("trouble").filter(opts)

-- Dump the source item under the cursor to the console
---@param opts? trouble.Mode | string
---@return trouble.List
require("trouble").inspect(opts)

-- Toggle whether the list is kept in sync with its source
---@param opts? trouble.Mode | string
---@return trouble.List
require("trouble").toggle_refresh(opts)
```

<!-- api:end -->

</details>

## 🔭 Pickers

Trouble no longer wraps pickers. Every one of them can already put its results
in the quickfix list, which is where trouble puts things too, so use the
picker's own action:

| Picker | Action | Default key |
| --- | --- | --- |
| [Telescope](https://github.com/nvim-telescope/telescope.nvim) | `send_to_qflist` / `smart_send_to_qflist` (and the `add_*` variants to append) | `<C-q>` |
| [fzf-lua](https://github.com/ibhagwan/fzf-lua) | `actions.file_sel_to_qf` | `<C-q>` |
| [snacks.picker](https://github.com/folke/snacks.nvim) | `qflist` | `<C-q>` |

For Telescope, the built-in default already opens the quickfix window too:

```lua
local actions = require("telescope.actions")

require("telescope").setup({
  defaults = {
    mappings = {
      i = { ["<c-q>"] = actions.smart_send_to_qflist + actions.open_qflist },
      n = { ["<c-q>"] = actions.smart_send_to_qflist + actions.open_qflist },
    },
  },
})
```

## 🎨 Colors

Trouble no longer defines any highlight groups. The quickfix window is
highlighted by Neovim itself (`qf` syntax, `QuickFixLine`, and the
`Diagnostic*` groups your colorscheme provides).
