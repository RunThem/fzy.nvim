local api = vim.api
local vfn = vim.fn
local M = {}

local function fst(xs)
  return xs and xs[1] or nil
end


local function popup()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_buf_set_keymap(buf, 't', '<ESC>', '<C-\\><C-c>', {})
  api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  local columns = api.nvim_get_option('columns')
  local lines = api.nvim_get_option('lines')
  local width = math.floor(columns * 0.9)
  local height = math.floor(lines * 0.8)
  local opts = {
    relative = 'editor',
    style = 'minimal',
    row = math.floor((lines - height) * 0.5),
    col = math.floor((columns - width) * 0.5),
    width = width,
    height = height
  }
  local win = api.nvim_open_win(buf, true, opts)
  return win, buf, opts
end


local sinks = {}
M.sinks = sinks
function sinks.edit_file(selection)
  if selection and vim.trim(selection) ~= '' then
    vim.cmd('e ' .. selection)
  end
end


function sinks.edit_buf(buf_with_name)
  if buf_with_name then
    local parts = vim.split(buf_with_name, ':')
    local bufnr = parts[1]
    api.nvim_set_current_buf(bufnr)
  end
end


local choices = {}

function choices.from_list(xs)
  return 'echo "' .. table.concat(xs, '\n') .. '"'
end

function choices.buffers()
  local bufs = vim.tbl_filter(
    function(b)
      return api.nvim_buf_is_loaded(b) and api.nvim_buf_get_option(b, 'buftype') ~= 'quickfix'
    end,
    api.nvim_list_bufs()
  )
  return choices.from_list(vim.tbl_map(
    function(b)
      local bufname = vfn.fnamemodify(api.nvim_buf_get_name(b), ':.')
      return string.format('%d: %s', b, bufname)
    end,
    bufs
  ))
end


function M.try(...)
  for _,fn in ipairs({...}) do
    local ok, _ = pcall(fn)
    if ok then
      return
    end
  end
end


M.actions = {}
function M.actions.buffers()
  M.execute(choices.buffers(), sinks.edit_buf, 'Buffers> ')
end

function M.actions.lsp_tags()
  local params = vim.lsp.util.make_position_params()
  params.context = {
    includeDeclaration = true
  }
  assert(#vim.lsp.buf_get_clients() > 0, "Must have a client running to use lsp_tags")
  vim.lsp.buf_request(0, 'textDocument/documentSymbol', params, function(err, _, result)
    assert(not err, vim.inspect(err))
    if not result then
      return
    end
    local items = {}
    local add_items = nil
    add_items = function(xs)
      for _, x in ipairs(xs) do
        table.insert(items, x)
        if x.children then
          add_items(x.children)
        end
      end
    end
    add_items(result)
    M.pick_one(
      items,
      'Tags> ',
      function(item) return string.format('[%s] %s', vim.lsp.protocol.SymbolKind[item.kind], item.name) end,
      function(item)
        if not item then return end
        local range = item.range or item.location.range
        api.nvim_win_set_cursor(0, {
          range.start.line + 1,
          range.start.character
        })
        vim.cmd('normal! zvzz')
      end
    )
  end)
end

function M.actions.buf_tags()
  local bufname = api.nvim_buf_get_name(0)
  assert(vfn.filereadable(bufname), 'File to generate tags for must be readable')
  local ok, output = pcall(vfn.system, {
    'ctags',
    '-f',
    '-',
    '--sort=yes',
    '--excmd=number',
    '--language-force=' .. api.nvim_buf_get_option(0, 'filetype'),
    bufname
  })
  if not ok or api.nvim_get_vvar('shell_error') ~= 0 then
    output = vfn.system({'ctags', '-f', '-', '--sort=yes', '--excmd=number', bufname})
  end
  local lines = vim.tbl_filter(
    function(x) return x ~= '' end,
    vim.split(output, '\n')
  )
  local tags = vim.tbl_map(function(x) return vim.split(x, '\t') end, lines)
  M.pick_one(
    tags,
    'Buffer Tags> ',
    fst,
    function(tag)
      if not tag then
        return
      end
      local row = tonumber(vim.split(tag[3], ';')[1])
      api.nvim_win_set_cursor(0, {row, 0})
      vim.cmd('normal! zvzz')
    end,
    'Buffer Tags> '
  )
end


function M.pick_one(items, prompt, label_fn, cb)
  local labels = {}
  label_fn = label_fn or vim.inspect
  for i, item in ipairs(items) do
    table.insert(labels, string.format('%03d ¦ %s', i, label_fn(item)))
  end
  M.execute(
    choices.from_list(labels),
    function(selection)
      if not selection or vim.trim(selection) == '' then
        cb(nil)
      else
        local parts = vim.split(selection, ' ¦ ')
        local idx = tonumber(parts[1])
        cb(items[idx])
      end
    end,
    prompt
  )
end


function M.execute(choices_cmd, on_selection, prompt)
  local tmpfile = vfn.tempname()
  local shell = api.nvim_get_option('shell')
  local shellcmdflag = api.nvim_get_option('shellcmdflag')
  local popup_win, _, popup_opts = popup()
  local fzy = (prompt
    and string.format(' | fzy -l %d -p "%s" >', popup_opts.height, prompt)
    or string.format(' | fzy -l %d > ', popup_opts.height)
  )
  local args = {shell, shellcmdflag, choices_cmd .. fzy.. tmpfile}
  vfn.termopen(args, {
    on_exit = function()
      api.nvim_win_close(popup_win, true)
      local file = io.open(tmpfile)
      if file then
        local contents = file:read("*all")
        file:close()
        os.remove(tmpfile)
        on_selection(contents)
      else
        on_selection(nil)
      end
    end;
  })
  vim.cmd('startinsert!')
end


return M
