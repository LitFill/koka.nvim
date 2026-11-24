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

    -- Create a floating window to display the configuration
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    local width = 50
    local height = #lines + 2
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)

    vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      row = row,
      col = col,
      style = 'minimal',
      border = 'rounded',
      title = 'Koka Configuration',
      title_pos = 'center',
    })

    -- Close on any key press
    vim.keymap.set('n', '<Esc>', '<cmd>close<cr>', { buffer = buf })
    vim.keymap.set('n', 'q', '<cmd>close<cr>', { buffer = buf })
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
        vim.notify(
          ([[
Koka %s: Expected subcommand.
Available subcommands:
%s
]]):format(name, table.concat(vim.tbl_keys(subcmd_tbl), ', ')),
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
    vim.notify(string.format('[koka.nvim] Unknown command: %s for :Koka', cmd), vim.log.levels.ERROR)
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
