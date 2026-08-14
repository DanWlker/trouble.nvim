# Examples

## Quickfix Window

Trouble never opens or closes the window, so this is all plain Neovim.

### Show the window automatically when there are results

```lua
vim.api.nvim_create_autocmd("QuickFixCmdPost", {
  pattern = "Trouble",
  callback = function()
    vim.cmd("cwindow")
  end,
})
vim.api.nvim_create_autocmd("QuickFixCmdPost", {
  pattern = "lTrouble",
  callback = function()
    vim.cmd("lwindow")
  end,
})
```

`:cwindow` / `:lwindow` open the window when the list is non-empty and close it
when it is empty, so this covers what `auto_open` and `auto_close` used to do —
on the initial load and on every auto refresh.

### Send a mode to the other list

```vim
:Trouble diagnostics list=loclist   " only this window
:Trouble symbols list=quickfix      " share it across windows
```

Or make it the default for a mode:

```lua
{
  modes = {
    diagnostics = { list = "loclist" },
  },
}
```

### A taller window at the top

That's a quickfix command, not a trouble option:

```vim
:topleft copen 20
```

Or wire it into the autocmd above with `vim.cmd("topleft cwindow 20")`.

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

This one is built in as `diagnostics_buffer`, and because it is buffer-scoped it
writes to the window's location list:

```lua
{
  modes = {
    diagnostics_buffer = {
      mode = "diagnostics", -- inherit from diagnostics mode
      filter = { buf = 0 }, -- filter diagnostics to the current buffer
      list = "loclist",     -- window-local, since the results are too
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

### Load diagnostics after a grep

```lua
vim.api.nvim_create_autocmd("QuickFixCmdPost", {
  pattern = "grep",
  callback = function()
    vim.cmd([[Trouble diagnostics]])
  end,
})
```

### Keeping the list fresh

Loading a mode makes its quickfix list the current one and starts auto refresh.
From then on the list follows its source until you switch to another list.

Trouble only ever touches the quickfix list it created for a mode. If you push
your own list with `:grep` or `setqflist()`, auto refresh stops writing until you
load the trouble mode again — your list is never clobbered.

Use `:colder` / `:cnewer` / `:chistory` to move between them, and
`:Trouble <mode>` to bring a specific mode's list back to the front.
