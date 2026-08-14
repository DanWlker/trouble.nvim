# Examples

## Quickfix Window

### A taller quickfix window at the top

```lua
{
  qf = {
    open_cmd = "topleft copen",
    height = 20,
  },
}
```

### Let Neovim decide the height

```lua
{
  qf = { height = false },
}
```

### Show the file name in the entry text

The quickfix window already prints the file name in its own column, but you can
put a shortened path in the entry text as well:

```lua
{
  modes = {
    diagnostics = {
      format = "{basename} {message} {item.source} {code}",
    },
  },
}
```

## Filtering

### Diagnostics for the current buffer only

```lua
{
  modes = {
    diagnostics_buffer = {
      mode = "diagnostics", -- inherit from diagnostics mode
      filter = { buf = 0 }, -- filter diagnostics to the current buffer
    },
  }
}
```

### Diagnostics for the current buffer and errors from the current project

```lua
{
  modes = {
    mydiags = {
      mode = "diagnostics", -- inherit from diagnostics mode
      filter = {
        any = {
          buf = 0, -- current buffer
          {
            severity = vim.diagnostic.severity.ERROR, -- errors only
            -- limit to files in the current project
            function(item)
              return item.filename:find((vim.loop or vim.uv).cwd(), 1, true)
            end,
          },
        },
      },
    }
  }
}
```

### Diagnostics Cascade

The following example shows how to create a new mode that
shows only the most severe diagnostics.

Once those are resolved, less severe diagnostics will be shown.

```lua
{
  modes = {
    cascade = {
      mode = "diagnostics", -- inherit from diagnostics mode
      filter = function(items)
        local severity = vim.diagnostic.severity.HINT
        for _, item in ipairs(items) do
          severity = math.min(severity, item.severity)
        end
        return vim.tbl_filter(function(item)
          return item.severity == severity
        end, items)
      end,
    },
  },
}
```

## Other

### Send diagnostics to the quickfix list after a grep

```lua
vim.api.nvim_create_autocmd("QuickFixCmdPost", {
  callback = function()
    vim.cmd([[Trouble diagnostics open focus=false]])
  end,
})
```

### Keep the quickfix list in sync while you work

Any mode with `auto_open` writes to the quickfix list and opens the window as
soon as there is something to show, and `auto_close` hides it again once the
list is empty:

```lua
{
  modes = {
    diagnostics_auto = {
      mode = "diagnostics",
      filter = { buf = 0 },
      auto_open = true,
      auto_close = true,
      focus = false,
    },
  },
}
```

Trouble only ever touches the quickfix list it created for a mode. If you push
your own list with `:grep` or `setqflist()`, auto refresh stops writing until
you open the trouble mode again.
