---@mod koka.commands
---@brief [[
---User commands for Koka development
---@brief ]]

local M = {}
local koka_cmd = require('koka.koka_cmd')
local koka_ui = require('koka.ui')

---@class koka.commands.Subcommand
---
---The command implementation
---@field impl fun(args: string[], opts: vim.api.keyset.user_command)
---
---Command completion callback, taking the lead of the subcommand's arguments
---Or a list of subcommand
---@field complete? string[] | fun(args: string[]): string[]
---
---Whether the command supports a bang!
---@field bang? boolean

---Open a read-only scratch float and return its buffer.
---@param lines string[]
---@param title string
---@return number buf
local function open_float(lines, title)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false

  local width = math.max(40, math.min(80, vim.o.columns - 4))
  local height = #lines + 2
  local row = math.max(0, math.floor((vim.o.lines - height) / 2))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))

  vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = title,
    title_pos = 'center',
  })

  vim.keymap.set('n', '<Esc>', '<cmd>close<cr>', { buffer = buf })
  vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf })
  return buf
end

---Parse compiler output lines into a quickfix list and open it.
---@param lines string[]
---@return boolean opened true when at least one entry was set
function M.populate_quickfix(lines)
  local items = {}
  for _, line in ipairs(lines) do
    local file, lnum, col, msg = line:match('^(.+):(%d+):(%d+):%s*(.*)$')
    if file then
      items[#items + 1] = {
        filename = file,
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = msg,
      }
    else
      local f2, l2, m2 = line:match('^(.+):(%d+):%s*(.*)$')
      if f2 then
        items[#items + 1] = {
          filename = f2,
          lnum = tonumber(l2),
          text = m2,
        }
      end
    end
  end

  if #items == 0 then
    return false
  end

  vim.fn.setqflist(items, 'r')
  vim.cmd('copen')
  return true
end

---Build a Koka file
---@param file_path string
function M.build_file(file_path)
  local project = require('koka.project')

  project.get_resolved_config(file_path, function(config)
    local cmd = koka_cmd.build(config, {
      mode = '-c',
      file = file_path,
    })

    -- Change to project directory
    local cwd = config.cwd or vim.fs.dirname(file_path)

    local output = {}
    local function collect(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= '' then
          output[#output + 1] = line
        end
      end
    end

    vim.fn.jobstart(cmd, {
      cwd = cwd,
      on_stdout = collect,
      on_stderr = collect,
      on_exit = function(_, exit_code)
        if exit_code == 0 then
          koka_ui.notify('✓ Build completed successfully', vim.log.levels.INFO)
        else
          M.populate_quickfix(output)
          koka_ui.notify(string.format('✗ Build failed with exit code %d', exit_code), vim.log.levels.ERROR)
        end
      end,
    })
  end)
end

---Run each named test and report a pass/fail summary.
---@param file_path string
---@param test_names string[]
function M.run_tests(file_path, test_names)
  local project = require('koka.project')

  project.get_resolved_config(file_path, function(config)
    local cwd = config.cwd or vim.fs.dirname(file_path)
    local results = {}
    local index = 0

    local function summarize()
      local passed, failed = 0, 0
      for i = 1, index do
        if results[i] then
          passed = passed + 1
        else
          failed = failed + 1
        end
      end
      koka_ui.notify(
        string.format('Tests: %d passed, %d failed', passed, failed),
        failed > 0 and vim.log.levels.ERROR or vim.log.levels.INFO
      )
    end

    local function run_next()
      index = index + 1
      local name = test_names[index]
      if not name then
        summarize()
        return
      end

      local cmd = koka_cmd.build(config, {
        mode = '-e',
        file = file_path,
        main_entry = name,
      })

      vim.fn.jobstart(cmd, {
        cwd = cwd,
        on_exit = function(_, code)
          results[index] = code == 0
          run_next()
        end,
      })
    end

    run_next()
  end)
end

---Show current project configuration
function M.show_config()
  local file_path = vim.api.nvim_buf_get_name(0)
  local project = require('koka.project')

  project.get_resolved_config(file_path, function(config)
    local lines = {
      'Koka Project Configuration:',
      '',
      string.format('Target: %s', config.target or 'c'),
      string.format('Working Directory: %s', config.cwd or 'not set'),
    }

    local inlay = require('koka.commands.inlay')
    local lsp = require('koka.lsp')
    table.insert(lines, '')
    table.insert(lines, string.format('Inlay Hints: %s', inlay.is_enabled() and 'enabled' or 'disabled'))
    table.insert(lines, string.format('LSP: %s', lsp.get_status() and 'running' or 'stopped'))

    local plugin = require('koka.config.internal')
    local defaults = plugin.get_defaults()
    local function render(value)
      if type(value) == 'function' then
        return '<function>'
      end
      return tostring(value)
    end
    table.insert(lines, '')
    table.insert(lines, 'Plugin Settings (default -> active):')
    table.insert(
      lines,
      string.format('  lsp.auto_attach: %s -> %s', render(defaults.lsp.auto_attach), render(plugin.lsp.auto_attach))
    )
    table.insert(
      lines,
      string.format('  inlay.enabled: %s -> %s', render(defaults.inlay.enabled), render(plugin.inlay.enabled))
    )
    table.insert(
      lines,
      string.format(
        '  inlay.debounce_ms: %s -> %s',
        render(defaults.inlay.debounce_ms),
        render(plugin.inlay.debounce_ms)
      )
    )
    table.insert(
      lines,
      string.format(
        '  inlay.max_results: %s -> %s',
        render(defaults.inlay.max_results),
        render(plugin.inlay.max_results)
      )
    )
    table.insert(
      lines,
      string.format('  inlay.on_write: %s -> %s', render(defaults.inlay.on_write), render(plugin.inlay.on_write))
    )

    if config.include_dirs and #config.include_dirs > 0 then
      table.insert(lines, 'Include Directories:')
      for _, dir in ipairs(config.include_dirs) do
        table.insert(lines, string.format('  - %s', dir))
      end
    end

    if config.compiler_args and #config.compiler_args > 0 then
      table.insert(lines, 'Compiler Arguments:')
      for _, arg in ipairs(config.compiler_args) do
        table.insert(lines, string.format('  - %s', arg))
      end
    end

    open_float(lines, 'Koka Configuration')
  end)
end

---Render a config value for display.
---@param value any
---@return string
local function render_value(value)
  if type(value) == 'function' then
    return '<function>'
  end
  return tostring(value)
end

---Set a plugin configuration value at runtime by dotted key.
---@param key string e.g. "inlay.enabled"
---@param raw string The raw value from the command line
function M.set_config(key, raw)
  local plugin = require('koka.config.internal')
  local defaults = plugin.get_defaults()

  local parts = vim.split(key, '.', { plain = true })
  local def = defaults
  for _, part in ipairs(parts) do
    def = def[part]
    if def == nil then
      koka_ui.notify(string.format('set: unknown setting: %s', key), vim.log.levels.ERROR)
      return
    end
  end

  local value
  local kind = type(def)
  if kind == 'boolean' then
    if raw == 'true' then
      value = true
    elseif raw == 'false' then
      value = false
    else
      koka_ui.notify('set: expected true or false', vim.log.levels.ERROR)
      return
    end
  elseif kind == 'number' then
    value = tonumber(raw)
    if not value then
      koka_ui.notify('set: expected a number', vim.log.levels.ERROR)
      return
    end
  elseif kind == 'function' then
    koka_ui.notify(string.format('set: %s is not settable from the command', key), vim.log.levels.WARN)
    return
  else
    value = raw
  end

  local parent = plugin
  for i = 1, #parts - 1 do
    parent = parent[parts[i]]
  end
  parent[parts[#parts]] = value

  koka_ui.notify(string.format('set %s = %s', key, render_value(value)), vim.log.levels.INFO)
end

---Parse a --showtypesigs line "module/name: type" into name and type.
---@param line string
---@return string? name
---@return string? type
local function parse_sig_line(line)
  local lhs, rhs = line:match('^(.+):%s+(.+)$')
  if not lhs or not rhs then
    return nil
  end
  local name = lhs:match('([^/]+)$')
  return name, rhs
end

---Strip a leading forall<...> from a type string.
---@param t string
---@return string
local function strip_forall(t)
  local rest = t:match('^%s*forall%s*<[^>]*>%s*(.*)$')
  return rest or t
end

---Return the result type from a full function type string, or nil.
---@param t string
---@return string? ret
local function result_type(t)
  local s = strip_forall(t):match('^%s*(.*)$')
  if s:sub(1, 1) ~= '(' then
    return nil
  end
  local depth, close = 0, nil
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == '(' then
      depth = depth + 1
    elseif c == ')' then
      depth = depth - 1
      if depth == 0 then
        close = i
        break
      end
    end
  end
  if not close then
    return nil
  end
  local rest = s:sub(close + 1):match('^%s*->%s*(.*)$')
  if not rest or rest == '' then
    return nil
  end
  return rest
end

---Insert a return type annotation after the parameter list of a function.
---@param bufnr number
---@param func table {name=string, row=number}
---@param ret string
function M.apply_return_type(bufnr, func, ret)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = lines[func.row + 1]
  if not text then
    koka_ui.notify('sig: function line not found', vim.log.levels.ERROR)
    return
  end
  local open = text:find('%(', 1, true)
  if not open then
    koka_ui.notify('sig: parameter list not on the function line', vim.log.levels.WARN)
    return
  end
  local depth, close = 0, nil
  for i = open, #text do
    local c = text:sub(i, i)
    if c == '(' then
      depth = depth + 1
    elseif c == ')' then
      depth = depth - 1
      if depth == 0 then
        close = i
        break
      end
    end
  end
  if not close then
    koka_ui.notify('sig: parameter list is not closed on the function line', vim.log.levels.WARN)
    return
  end
  local brace = text:find('{', close, true)
  local between = text:sub(close + 1, brace and (brace - 1) or #text)
  if between:find(':', 1, true) then
    koka_ui.notify(string.format('sig: %s already has a return type', func.name), vim.log.levels.INFO)
    return
  end
  vim.api.nvim_buf_set_text(bufnr, func.row, close, func.row, close, ': ' .. ret)
  koka_ui.notify(string.format('sig: %s : %s', func.name, ret), vim.log.levels.INFO)
end

---Infer and write the return type of the function under the cursor.
function M.write_signature()
  local bufnr = vim.api.nvim_get_current_buf()
  local treesitter = require('koka.treesitter')
  local line = vim.api.nvim_win_get_cursor(0)[1] - 1
  local func = treesitter.find_function_at(bufnr, line)
  if not func then
    koka_ui.notify('sig: no function at cursor', vim.log.levels.WARN)
    return
  end
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local project = require('koka.project')
  project.get_resolved_config(file_path, function(config)
    local cmd = koka_cmd.build(config, { mode = '-c', file = file_path, showtypesigs = true })
    local cwd = config.cwd or vim.fs.dirname(file_path)
    vim.system(cmd, { cwd = cwd, text = true }, function(res)
      vim.schedule(function()
        local out = table.concat({ res.stdout or '', res.stderr or '' }, '\n')
        local inferred
        for _, l in ipairs(vim.split(out, '\n')) do
          local name, ty = parse_sig_line(l)
          if name == func.name then
            inferred = ty
            break
          end
        end
        if not inferred then
          koka_ui.notify(
            string.format('sig: no inferred type for %s (file may not typecheck)', func.name),
            vim.log.levels.WARN
          )
          return
        end
        local ret = result_type(inferred)
        if not ret then
          koka_ui.notify(string.format('sig: could not parse type: %s', inferred), vim.log.levels.WARN)
          return
        end
        M.apply_return_type(bufnr, func, ret)
      end)
    end)
  end)
end
---Show available subcommands in a float
function M.show_help()
  local lines = {
    'Koka.nvim commands:',
    '',
    '  :Koka run [name]       Run function at cursor or named function',
    '  :Koka build [file]     Build current file or named file',
    '  :Koka test [name]      Run test function',
    '  :Koka config           Show project configuration',
    '  :Koka set <key> <val>  Set a plugin setting at runtime',
    '  :Koka sig              Write the inferred return type at the cursor',
    '  :Koka refresh_codelens Refresh code lenses',
    '  :Koka inlay [invalidate] Toggle hints or clear the cache',
    '  :Koka goto <file>      Open a .kk file by name',
    '  :Koka help             Show this help',
    '  :Koka lsp start        Start LSP server',
    '  :Koka lsp stop         Stop LSP server',
    '  :Koka lsp restart      Restart LSP server',
    '',
    'Suggested keymaps:',
    '  <leader>kr  Run function at cursor',
    '  <leader>kb  Build current file',
    '  <leader>kt  Run tests',
    '  <leader>ki  Toggle inlay hints',
    '  <leader>kg  Goto .kk file',
    '',
    'Press q or <Esc> to close.',
  }
  open_float(lines, 'Koka Help')
end

---Get the project root directory for the given file path (synchronous).
---@param file_path string
---@return string root_dir
local function get_root_dir(file_path)
  local project = require('koka.project')
  return project.get_resolved_config(file_path).cwd or vim.fs.dirname(file_path)
end

---Find .kk files in the project, relative to the project root.
---@param root_dir string
---@return string[] rel_paths
local function find_koka_files(root_dir)
  local files = vim.fs.find(function(name)
    return name:match('%.kk$')
  end, {
    path = root_dir,
    type = 'file',
    limit = math.huge,
  })

  local rel = {}
  for _, f in ipairs(files) do
    rel[#rel + 1] = vim.fs.relpath(root_dir, f)
  end
  table.sort(rel)
  return rel
end

---Complete .kk file paths relative to the project root.
---@param lead string
---@return string[]
function M.complete_koka_files(lead)
  local root_dir = get_root_dir(vim.api.nvim_buf_get_name(0))
  return vim.tbl_filter(function(p)
    return vim.startswith(p, lead)
  end, find_koka_files(root_dir))
end

---Open a Koka file by name. The name may omit the .kk extension.
---@param name string?
function M.goto_file(name)
  if not name or name == '' then
    koka_ui.notify('goto: missing file name', vim.log.levels.ERROR)
    return
  end

  local root_dir = get_root_dir(vim.api.nvim_buf_get_name(0))

  ---@param p string
  ---@return boolean
  local function is_kk(p)
    return vim.endswith(p, '.kk')
  end

  -- Accept the name with or without the .kk extension.
  local target = is_kk(name) and name or (name .. '.kk')

  -- Absolute path.
  if name:match('^/') or name:match('^%a:') then
    if vim.uv.fs_stat(target) then
      vim.cmd.edit(vim.fn.fnameescape(target))
    else
      koka_ui.notify(string.format('goto: file not found: %s', target), vim.log.levels.ERROR)
    end
    return
  end

  -- Path relative to the project root.
  local abs = vim.fs.joinpath(root_dir, target)
  if vim.uv.fs_stat(abs) then
    vim.cmd.edit(vim.fn.fnameescape(abs))
    return
  end

  -- Match by base name anywhere in the project.
  local base = vim.fs.basename(target)
  local matches = vim.fs.find(function(n)
    return n == base
  end, {
    path = root_dir,
    type = 'file',
    limit = math.huge,
  })

  if #matches == 0 then
    koka_ui.notify(string.format('goto: no Koka file matches: %s', name), vim.log.levels.ERROR)
    return
  end

  if #matches == 1 then
    vim.cmd.edit(vim.fn.fnameescape(matches[1]))
    return
  end

  vim.ui.select(matches, {
    prompt = string.format('%d files match %s:', #matches, base),
    format_item = function(path)
      return path
    end,
  }, function(choice)
    if choice then
      vim.cmd.edit(vim.fn.fnameescape(choice))
    end
  end)
end

---@type table<string, koka.commands.Subcommand>
local command_tbl = {
  run = {
    impl = function(args)
      if #args > 0 then
        local codelens = require('koka.commands.codelens')
        local file_path = vim.api.nvim_buf_get_name(0)
        codelens.handle_run_command('run', file_path, args[1])
      else
        require('koka.commands.codelens').run_at_cursor()
      end
    end,
    complete = function(lead)
      local bufnr = vim.api.nvim_get_current_buf()
      local treesitter = require('koka.treesitter')
      local runnables = treesitter.find_runnables(bufnr)
      return vim.tbl_filter(
        function(name)
          return vim.startswith(name, lead)
        end,
        vim.tbl_map(function(r)
          return r.name
        end, runnables)
      )
    end,
  },
  build = {
    impl = function(args)
      local file_path = #args > 0 and args[1] or vim.api.nvim_buf_get_name(0)
      M.build_file(file_path)
    end,
  },
  config = {
    impl = function()
      M.show_config()
    end,
  },
  set = {
    impl = function(args)
      if not args[1] or not args[2] then
        koka_ui.notify('Usage: :Koka set <key> <value>', vim.log.levels.WARN)
        return
      end
      M.set_config(args[1], args[2])
    end,
    complete = function(lead)
      local keys = {
        'lsp.auto_attach',
        'inlay.enabled',
        'inlay.debounce_ms',
        'inlay.max_results',
        'inlay.on_write',
      }
      return vim.tbl_filter(function(k)
        return vim.startswith(k, lead)
      end, keys)
    end,
  },
  sig = {
    impl = function()
      M.write_signature()
    end,
  },
  refresh_codelens = {
    impl = function()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.lsp.codelens.enable(true, { bufnr = bufnr })
      -- Also refresh our custom code lenses
      require('koka.commands.codelens').display_custom_codelenses(bufnr)
      koka_ui.notify('Code lenses refreshed', vim.log.levels.INFO)
    end,
  },
  test = {
    impl = function(args)
      local bufnr = vim.api.nvim_get_current_buf()
      local treesitter = require('koka.treesitter')
      local runnables = treesitter.find_runnables(bufnr)
      local tests = {}
      for _, runnable in ipairs(runnables) do
        if runnable.type == 'test' then
          table.insert(tests, runnable.name)
        end
      end
      if #tests == 0 then
        koka_ui.notify('No test functions found in buffer', vim.log.levels.WARN)
        return
      end
      local file_path = vim.api.nvim_buf_get_name(bufnr)
      local target = args[1]
      if target then
        local codelens = require('koka.commands.codelens')
        codelens.handle_run_command('test', file_path, target)
        koka_ui.notify(string.format('Running test: %s (%d tests found)', target, #tests), vim.log.levels.INFO)
      else
        M.run_tests(file_path, tests)
      end
    end,
    complete = function(lead)
      local bufnr = vim.api.nvim_get_current_buf()
      local treesitter = require('koka.treesitter')
      local runnables = treesitter.find_runnables(bufnr)
      local tests = vim.tbl_filter(function(r)
        return r.type == 'test'
      end, runnables)
      return vim.tbl_filter(
        function(name)
          return vim.startswith(name, lead)
        end,
        vim.tbl_map(function(r)
          return r.name
        end, tests)
      )
    end,
  },
  ['goto'] = {
    impl = function(args)
      M.goto_file(args[1])
    end,
    complete = function(lead)
      return M.complete_koka_files(lead)
    end,
  },
  inlay = {
    impl = function(args)
      local inlay = require('koka.commands.inlay')
      if args[1] == 'invalidate' then
        inlay.invalidate()
      else
        inlay.toggle()
      end
    end,
    complete = { 'toggle', 'invalidate' },
  },
  help = {
    impl = function()
      M.show_help()
    end,
  },
}

---@param name string The name of the subcommand
---@param subcmd_tbl table<string, koka.commands.Subcommand> The subcommand's subcommand table
local function register_subcommand_tbl(name, subcmd_tbl)
  command_tbl[name] = {
    impl = function(args, ...)
      local subcmd = subcmd_tbl[table.remove(args, 1)]
      if subcmd then
        subcmd.impl(args, ...)
      else
        local available = vim.tbl_keys(subcmd_tbl)
        table.sort(available)
        koka_ui.notify(
          ([[
Koka %s: expected a subcommand.
Available subcommands: %s
Usage: :Koka %s <subcommand> [args]
]]):format(name, table.concat(available, ', '), name),
          vim.log.levels.ERROR
        )
      end
    end,
    complete = function(subcmd_arg_lead)
      local subcmd, next_arg_lead = subcmd_arg_lead:match('^(%S+)%s*(.*)$')
      if subcmd and next_arg_lead and subcmd_tbl[subcmd] and subcmd_tbl[subcmd].complete then
        return subcmd_tbl[subcmd].complete(next_arg_lead)
      end
      if subcmd_arg_lead and subcmd_arg_lead ~= '' then
        return vim.tbl_filter(function(n)
          return vim.startswith(n, subcmd_arg_lead)
        end, vim.tbl_keys(subcmd_tbl))
      end
      return vim.tbl_keys(subcmd_tbl)
    end,
  }
end

---@type table<string, koka.commands.Subcommand>
local lsp_subcmd_tbl = {
  start = {
    impl = function()
      require('koka.lsp').start()
    end,
  },
  stop = {
    impl = function()
      require('koka.lsp').stop()
    end,
  },
  restart = {
    impl = function()
      require('koka.lsp').restart()
    end,
  },
  status = {
    impl = function()
      local running = require('koka.lsp').get_status()
      local project = require('koka.project')
      local config = project.get_resolved_config(vim.api.nvim_buf_get_name(0))
      local root = config.cwd or 'not set'
      if running then
        koka_ui.notify(string.format('LSP running (root: %s)', root), vim.log.levels.INFO)
      else
        koka_ui.notify(string.format('LSP stopped (root: %s)', root), vim.log.levels.WARN)
      end
    end,
  },
}

register_subcommand_tbl('lsp', lsp_subcmd_tbl)

local function koka_command_imp(opts)
  local fargs = opts.fargs
  local cmd = fargs[1]
  if not cmd or cmd == '' then
    M.show_help()
    return
  end
  local args = #fargs > 1 and vim.list_slice(fargs, 2) or {}
  local command = command_tbl[cmd]
  if not command then
    local available = vim.tbl_keys(command_tbl)
    table.sort(available)
    koka_ui.notify(
      string.format('Unknown command: %s. Available: %s', cmd, table.concat(available, ', ')),
      vim.log.levels.ERROR
    )
    return
  end
  command.impl(args, opts)
end

---Setup Koka user commands
function M.setup()
  vim.api.nvim_create_user_command('Koka', koka_command_imp, {
    nargs = '?',
    complete = function(arg_lead, cmdline, _)
      local subcmd, subcmd_arg_lead = cmdline:match("^['<,'>]*Koka[!]*%s(%S+)%s(.*)$")
      if subcmd and subcmd_arg_lead and command_tbl[subcmd] and command_tbl[subcmd].complete then
        local complete = command_tbl[subcmd].complete
        if type(complete) == 'table' then
          return vim.tbl_filter(function(c)
            return vim.startswith(c, subcmd_arg_lead)
          end, complete)
        end
        return complete and complete(subcmd_arg_lead) or {}
      end
      if cmdline:match("^['<,'>]*Koka[!]*%s+%S*$") then
        return vim.tbl_filter(function(c)
          return vim.startswith(c, arg_lead)
        end, vim.tbl_keys(command_tbl))
      end
    end,
    bang = false,
  })
end

return M
