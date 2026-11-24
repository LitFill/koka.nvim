---@mod koka.codelens
---@brief [[
---Code lens support for Koka runnable functions
---@brief ]]

local M = {}

---Find runnable functions in buffer using TreeSitter
---@param bufnr number
---@return table[] runnables Array of {line, col, name, type}
local function find_runnables(bufnr)
  local treesitter = require('koka.treesitter')
  return treesitter.find_runnables(bufnr)
end

---Create code lens for runnable function
---@param runnable table
---@param bufnr number
---@return table codelens
local function create_codelens(runnable, bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local text = string.format('▶ %s', runnable.name)

  return {
    range = {
      start = {
        line = runnable.line,
        character = runnable.col,
      },
      ['end'] = {
        line = runnable.line,
        character = runnable.col + #runnable.name,
      },
    },
    command = {
      title = text,
      command = 'koka.run',
      arguments = {
        runnable.type,
        bufname,
        runnable.name,
      },
    },
  }
end

---Get code lenses for buffer
---@param bufnr number
---@return table[] codelenses
function M.get_codelenses(bufnr)
  local runnables = find_runnables(bufnr)
  local codelenses = {}

  for _, runnable in ipairs(runnables) do
    table.insert(codelenses, create_codelens(runnable, bufnr))
  end

  return codelenses
end

---Handle koka.run command
---@param action_type string "run", "test", or "example"
---@param file_path string Path to the file containing the function
---@param func_name string Name of the function to run
function M.handle_run_command(action_type, file_path, func_name)
  local project = require('koka.project')
  local lsp_helpers = require('koka.lsp.helpers')
  local debugger = require('koka.debugger')
  -- Get current buffer for LSP client lookup
  local bufnr = vim.api.nvim_get_current_buf()
  local clients = lsp_helpers.get_active_lsp_clients(bufnr)

  if #clients == 0 then
    -- Fallback to direct compilation if no LSP client
    M._handle_run_command_fallback(action_type, file_path, func_name)
    return
  end

  local client = clients[1]
  -- Use get_resolved_config which provides defaults
  project.get_resolved_config(file_path, function(config)
    if func_name == 'main' then
      -- For main function, compile and run the entire program
      debugger.run_main(client, config, file_path)
    else
      -- For other functions, use the specific function compilation
      debugger.run_function(client, config, file_path, func_name)
    end
  end)
end

---Fallback handler when no LSP client is available
---@param action_type string "run", "test", or "example"
---@param file_path string Path to the file containing the function
---@param func_name string Name of the function to run
function M._handle_run_command_fallback(action_type, file_path, func_name)
  local project = require('koka.project')

  -- Use get_resolved_config which provides defaults
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

    -- Add execute flag with file and optional entrypoint
    table.insert(cmd, '-e')
    table.insert(cmd, file_path)
    if func_name ~= 'main' then
      table.insert(cmd, '--main-entry=' .. func_name)
    end

    -- Change to project directory
    local cwd = config.cwd or vim.fs.dirname(file_path)

    local title = string.format('Koka %s: %s', action_type, func_name)

    -- Run in terminal using jobstart with argv list (handles spaces)
    vim.fn.jobstart(cmd, {
      cwd = cwd,
      term = true,
      on_exit = function(_, exit_code)
        if exit_code == 0 then
          vim.notify(string.format('✓ %s completed successfully', title), vim.log.levels.INFO)
        else
          vim.notify(string.format('✗ %s failed with exit code %d', title, exit_code), vim.log.levels.ERROR)
        end
      end,
    })
  end)
end

---Setup code lens for Koka buffers
function M.setup()
  -- Add LSP command for code lens
  local lsp_helpers = require('koka.lsp.helpers')

  vim.lsp.commands['koka.run'] = function(command, _)
    local args = command.arguments
    if args and #args >= 3 then
      M.handle_run_command(args[1], args[2], args[3])
    end
  end

  local group = vim.api.nvim_create_augroup('koka_codelens', { clear = true })

  -- Auto-refresh code lenses for Koka files
  vim.api.nvim_create_autocmd({ 'LspAttach', 'BufWritePost', 'InsertLeave' }, {
    group = group,
    pattern = '*.kk',
    callback = function(args)
      local bufnr = args.buf
      local clients = lsp_helpers.get_active_lsp_clients(bufnr)
      if #clients > 0 then
        -- Clear fallback virtual text lenses when LSP is active
        local ns_id = vim.api.nvim_create_namespace('koka_codelens')
        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
        vim.lsp.codelens.refresh { bufnr = bufnr }
      else
        -- Provide our own code lens display if no LSP
        M.display_custom_codelenses(bufnr)
      end
    end,
  })
end

---Display custom code lenses using virtual text (fallback when no LSP)
---@param bufnr number
function M.display_custom_codelenses(bufnr)
  local ns_id = vim.api.nvim_create_namespace('koka_codelens')
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)

  local runnables = find_runnables(bufnr)
  for _, runnable in ipairs(runnables) do
    local text = string.format('▶ %s', runnable.name)
    vim.api.nvim_buf_set_extmark(bufnr, ns_id, runnable.line, runnable.col, {
      virt_text = { { text, 'Comment' } },
      virt_text_pos = 'eol',
      hl_mode = 'combine',
    })
  end
end

---Run function at cursor
function M.run_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line_nr = cursor[1] - 1 -- Convert to 0-indexed

  local runnables = find_runnables(bufnr)
  for _, runnable in ipairs(runnables) do
    if runnable.line == line_nr then
      local bufname = vim.api.nvim_buf_get_name(bufnr)
      M.handle_run_command(runnable.type, bufname, runnable.name)
      return
    end
  end

  vim.notify('No runnable function found at cursor', vim.log.levels.WARN)
end

return M
