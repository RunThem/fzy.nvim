local api = vim.api
local vfn = vim.fn
local M = {}

function M.new_popup()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_keymap(buf, 't', '<ESC>', '<C-\\><C-c>', {})
  api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

  local lines = api.nvim_get_option('lines')
  local columns = api.nvim_get_option('columns')

  local opts = {
    relative = 'editor',
    style = 'minimal',
    row = lines - 24,
    col = 0,
    width = columns - 2,
    height = 20,
    border = 'single',
  }

  local win = api.nvim_open_win(buf, true, opts)
  return win, buf
end

local sinks = {}
M.sinks = sinks
function sinks.edit_file(selection)
  if selection and vim.trim(selection) ~= '' then
    vim.cmd('e ' .. selection)
  end
end

function sinks.edit_live_grep(selection)
  -- fzy returns search input if zero results found. This case is mapped to nil as well.
  selection = string.match(selection, '.+:%d+:')
  if selection then
    local parts = vim.split(selection, ':')
    local path, line = parts[1], parts[2]
    vim.cmd('e +' .. line .. ' ' .. path)
  end
end

function M.execute(choices_cmd, on_selection)
  if api.nvim_get_mode().mode == 'i' then
    vim.cmd('stopinsert')
  end
  local tmpfile = vfn.tempname()
  local shell = api.nvim_get_option('shell')
  local shellcmdflag = api.nvim_get_option('shellcmdflag')
  local popup_win, buf = M.new_popup()
  local height = api.nvim_win_get_height(popup_win)
  local fzy

  fzy = string.format('%s | fzy -l %d -p "_> " > "%s"', choices_cmd, height, tmpfile)
  api.nvim_create_autocmd({ 'TermOpen', 'BufEnter' }, {
    buffer = buf,
    command = 'startinsert!',
    once = true,
  })

  local args = { shell, shellcmdflag, fzy }

  vfn.termopen(args, {
    on_exit = function()
      -- popup could already be gone if user closes it manually; Ignore that case
      pcall(api.nvim_win_close, popup_win, true)
      local contents = nil
      local file = io.open(tmpfile)
      if file then
        contents = file:read('*all')
        file:close()
        os.remove(tmpfile)
      end

      -- After on_exit there will be a terminal related cmdline update that would
      -- override any messages printed by the `on_selection` callback.
      -- The timer+schedule combo ensures users see messages printed within the callback
      local timer = vim.loop.new_timer()
      if timer then
        timer:start(0, 0, function()
          timer:stop()
          timer:close()
          vim.schedule(function()
            on_selection(contents)
          end)
        end)
      else
        on_selection(contents)
      end
    end,
  })
end

return M
