# fzy.nvim

A `vim.ui.select` implementation for the `fzy` CLI.

## Installation

- Requires Neovim (latest stable or nightly)
- Install `fzy` and make sure it is in your `$PATH`.

## Usage

`fzy.nvim` provides the `vim.ui.select` implementation and a `execute` function
to feed the output of commands to `fzy`.

Create some mappings like this:

```lua
vim.keymap.set('n', '<Leader>ff', function ()
  local fzy = require('fzy')
  fzy.execute('fd', fzy.sinks.edit_file)
end)

vim.keymap.set('n', '<Leader>fa', function ()
  local fzy = require('fzy')
  fzy.execute('rg --no-heading --trim -nH .', fzy.sinks.edit_live_grep)
end)
```
