---@mod koka.commands
---@brief [[
---User commands for Koka development
---@brief ]]

local M = {}

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

---Build a Koka file
---@param file_path string
function M.build_file(file_path)
  local project = require('koka.project')

  project.get_resolved_config(file_path, function(config)
    local cmd = { 'koka' }

    -- Add target
    if config.target and config.target ~= 'c' then
      table.insert(cmd, '--target=' .. config.target)
    end

    -- Add include directories
    if config.include_dirs then
      for _, include_dir in ipairs(config.include_dirs) do
        table.insert(cmd, '--include=' .. include_dir)
      end
    end

    -- Add compiler arguments
    if config.compiler_args then
      for _, arg in ipairs(config.compiler_args) do
        table.insert(cmd, arg)
      end
    end

    -- Add compile flag
    table.insert(cmd, '-c')
    table.insert(cmd, file_path)

    -- Change to project directory
    local cwd = config.cwd or vim.fs.dirname(file_path)

    -- Run in terminal
    vim.fn.jobstart(cmd, {
      cwd = cwd,
      term = true,
      on_exit = function(_, exit_code)
        if exit_code == 0 then
          vim.notify('✓ Build completed successfully', vim.log.levels.INFO)
        else
          vim.notify(string.format('✗ Build failed with exit code %d', exit_code), vim.log.levels.ERROR)
        end
      end,
    })
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

---Show available subcommands in a float
function M.show_help()
  local lines = {
    'Koka.nvim commands:',
    '',
    '  :Koka run [name]       Run function at cursor or named function',
    '  :Koka build [file]     Build current file or named file',
    '  :Koka test [name]      Run test function',
    '  :Koka config           Show project configuration',
    '  :Koka refresh_codelens Refresh code lenses',
    '  :Koka goto <file>      Open a .kk file by name',
    '  :Koka help             Show this help',
    '  :Koka lsp start        Start LSP server',
    '  :Koka lsp stop         Stop LSP server',
    '  :Koka lsp restart      Restart LSP server',
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
    vim.notify('[koka.nvim] goto: missing file name', vim.log.levels.ERROR)
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
      vim.notify(string.format('[koka.nvim] goto: file not found: %s', target), vim.log.levels.ERROR)
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
    vim.notify(string.format('[koka.nvim] goto: no Koka file matches: %s', name), vim.log.levels.ERROR)
    return
  end

  if #matches > 1 then
    vim.notify(
      string.format('[koka.nvim] goto: %d files match %s, opening the first', #matches, base),
      vim.log.levels.WARN
    )
  end

  vim.cmd.edit(vim.fn.fnameescape(matches[1]))
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
  refresh_codelens = {
    impl = function()
      local bufnr = vim.api.nvim_get_current_buf()
      vim.lsp.codelens.enable(true, { bufnr = bufnr })
      -- Also refresh our custom code lenses
      require('koka.commands.codelens').display_custom_codelenses(bufnr)
      vim.notify('Code lenses refreshed', vim.log.levels.INFO)
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
        vim.notify('No test functions found in buffer', vim.log.levels.WARN)
        return
      end
      local target = #args > 0 and args[1] or tests[1]
      local file_path = vim.api.nvim_buf_get_name(bufnr)
      local codelens = require('koka.commands.codelens')
      codelens.handle_run_command('test', file_path, target)
      vim.notify(string.format('Running test: %s (%d tests found)', target, #tests), vim.log.levels.INFO)
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
        vim.notify(
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
}

register_subcommand_tbl('lsp', lsp_subcmd_tbl)

local function koka_command_imp(opts)
  local fargs = opts.fargs
  local cmd = fargs[1]
  local args = #fargs > 1 and vim.list_slice(fargs, 2) or {}
  local command = command_tbl[cmd]
  if not command then
    local available = vim.tbl_keys(command_tbl)
    table.sort(available)
    vim.notify(
      string.format('[koka.nvim] Unknown command: %s. Available: %s', cmd, table.concat(available, ', ')),
      vim.log.levels.ERROR
    )
    return
  end
  command.impl(args, opts)
end

---Setup Koka user commands
function M.setup()
  vim.api.nvim_create_user_command('Koka', koka_command_imp, {
    nargs = '+',
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
