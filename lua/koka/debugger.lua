---@mod koka.debugger
---@brief [[
---Provide support for debugging and execution via Koka LSP
---@brief ]]

---@class koka.debugger.LaunchArguments
---@field program string An absolute path to the "program" to debug
---@field compiler_args? string[] Additional arguments
---@field program_args? string[] Additional arguments
---@field trace? boolean Enable logging
---@field function_name? string A single function to run (must have no effects and returns a type that is showable)

local M = {}

---Execute a program or function using Koka LSP
---@param client vim.lsp.Client The LSP client
---@param project_config koka.project.Config The project config
---@param args koka.debugger.LaunchArguments The execution arguments
---@param callback? function Callback function to handle the result
function M.execute(client, project_config, args, callback)
  local target = project_config.target or 'c'
  local additional_args = '--buildtag=nvim --target=' .. target

  -- Append include_dirs and compiler_args from project_config (bug fix: was ignoring them)
  if project_config.include_dirs then
    for _, include_dir in ipairs(project_config.include_dirs) do
      additional_args = additional_args .. ' --include=' .. include_dir
    end
  end
  if project_config.compiler_args then
    additional_args = additional_args .. ' ' .. table.concat(project_config.compiler_args, ' ')
  end

  if args.compiler_args then
    additional_args = additional_args .. ' ' .. table.concat(args.compiler_args, ' ')
  end

  local command_name, command_args
  if args.function_name then
    command_name = 'koka/compileFunction'
    command_args = { args.program, args.function_name, additional_args }
  else
    command_name = 'koka/compile'
    command_args = { args.program, additional_args }
  end

  -- Send LSP command request
  ---@diagnostic disable-next-line: param-type-mismatch
  client:request('workspace/executeCommand', {
    command = command_name,
    arguments = command_args,
    ---@diagnostic disable-next-line: param-type-mismatch
  }, function(err, result)
    if err then
      vim.notify('Error executing Koka command: ' .. tostring(err.message or err), vim.log.levels.ERROR)
      if callback then
        callback(nil, err)
      end
      return
    end

    if not result then
      vim.notify('Error generating code, see language server output for specifics', vim.log.levels.ERROR)
      if callback then
        callback(nil, 'No result from LSP')
      end
      return
    end

    local output_path = result
    -- Handle absolute paths correctly (bug fix: was blindly joining with cwd)
    local full_path
    if vim.startswith(output_path, '/') or vim.startswith(output_path, '%a:') then
      full_path = output_path
    else
      full_path = vim.fs.joinpath(project_config.cwd or vim.fs.dirname(args.program), output_path)
    end

    -- Check if the generated file exists
    if vim.fn.filereadable(full_path) == 0 then
      vim.notify('Error finding generated code at ' .. output_path, vim.log.levels.ERROR)
      if callback then
        callback(nil, 'Generated file not found')
      end
      return
    end

    -- Execute the generated code based on target
    M._run_generated_code(target, full_path, args.program_args or {}, project_config.cwd, callback)
  end)
end

---Run the generated code based on target platform
---@param target string The compilation target
---@param executable_path string Path to the generated executable
---@param program_args string[] Arguments to pass to the program
---@param cwd string Working directory
---@param callback? function Callback function
function M._run_generated_code(target, executable_path, program_args, cwd, callback)
  local cmd, cmd_args

  if target == 'c' or target == 'c32' or target == 'c64c' then
    cmd = executable_path
    cmd_args = program_args
  elseif target == 'jsnode' then
    cmd = 'node'
    cmd_args = vim.list_extend({ executable_path }, program_args)
  else
    vim.notify(
      string.format('Running code for target %s is not yet supported. Output is at %s', target, executable_path),
      vim.log.levels.WARN
    )
    if callback then
      callback(executable_path, nil)
    end
    return
  end

  -- Create a new terminal tab for execution using jobstart argv (handles spaces)
  vim.cmd('tabnew')
  local full_cmd = vim.list_extend({ cmd }, cmd_args)
  vim.fn.jobstart(full_cmd, {
    cwd = cwd,
    term = true,
    on_exit = function(_, exit_code)
      if exit_code == 0 then
        vim.notify('✓ Execution completed successfully', vim.log.levels.INFO)
      else
        vim.notify(string.format('✗ Execution failed with exit code %d', exit_code), vim.log.levels.ERROR)
      end
      if callback then
        callback(executable_path, exit_code)
      end
    end,
  })
end

---Compile and run a specific function
---@param client vim.lsp.Client The LSP client
---@param project_config koka.project.Config The project config
---@param program_path string Path to the Koka program
---@param function_name string Name of the function to run
---@param callback? function Callback function
function M.run_function(client, project_config, program_path, function_name, callback)
  M.execute(client, project_config, {
    program = program_path,
    function_name = function_name,
  }, callback)
end

---Compile and run the main function of a program
---@param client vim.lsp.Client The LSP client
---@param project_config koka.project.Config The project config
---@param program_path string Path to the Koka program
---@param callback? function Callback function
function M.run_main(client, project_config, program_path, callback)
  M.execute(client, project_config, {
    program = program_path,
  }, callback)
end

--- Launch the debugger (legacy interface)
---
--- @param client vim.lsp.Client The LSP client we want to send this
--- @param project_config koka.project.Config The project config this program need to use
--- @param args koka.debugger.LaunchArguments The debugger configs to use
function M.launch(client, project_config, args)
  M.execute(client, project_config, args)
end

---Read the module name from buffer lines. Fall back to the file base name.
---@param lines string[] The buffer lines
---@param program_path string Path to the Koka program
---@return string module_name
function M._module_name(lines, program_path)
  for _, line in ipairs(lines) do
    local name = line:match('^%s*module%s+([%w%-%.]+)')
    if name then
      return name
    end
  end
  local base = vim.fs.basename(program_path or '')
  return (base:gsub('%.kk$', ''))
end

---Build the wrapper source: the buffer text plus a main that prints the call.
---@param lines string[] The buffer lines
---@param func_name string Name of the total function
---@param args_text string Comma-separated literal arguments
---@return string[] wrapper_lines
function M._build_wrapper(lines, func_name, args_text)
  local wrapper = {}
  vim.list_extend(wrapper, lines)
  wrapper[#wrapper + 1] = ''
  wrapper[#wrapper + 1] = string.format('fun main() { println(%s(%s)) }', func_name, args_text)
  return wrapper
end

---Evaluate a total function with literal arguments and capture stdout.
---Writes a temp module that prints the call, runs koka -e, and returns text.
---@param project_config koka.project.Config The project config
---@param program_path string Path to the Koka program
---@param lines string[] The buffer lines
---@param func_name string Name of the total function
---@param args_text string Comma-separated literal arguments
---@param callback fun(result: string?) Called with trimmed stdout, or nil on failure
---@param timeout_ms? number Kill the run after this many milliseconds
function M.eval_total(project_config, program_path, lines, func_name, args_text, callback, timeout_ms)
  timeout_ms = timeout_ms or 3000
  local orig_dir = vim.fs.dirname(program_path)
  local module_name = M._module_name(lines, program_path)
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, 'p')
  local tmp_file = vim.fs.joinpath(tmp_dir, module_name .. '.kk')
  local wrapper = M._build_wrapper(lines, func_name, args_text)
  vim.fn.writefile(wrapper, tmp_file)

  local cmd = { 'koka' }
  if project_config.target and project_config.target ~= 'c' then
    table.insert(cmd, '--target=' .. project_config.target)
  end
  table.insert(cmd, '--include=' .. orig_dir)
  if project_config.include_dirs then
    for _, include_dir in ipairs(project_config.include_dirs) do
      table.insert(cmd, '--include=' .. include_dir)
    end
  end
  if project_config.compiler_args then
    vim.list_extend(cmd, project_config.compiler_args)
  end
  table.insert(cmd, '-e')
  table.insert(cmd, tmp_file)

  local cwd = project_config.cwd or orig_dir
  local out = {}
  local done = false
  local job

  local function finish(result)
    if done then
      return
    end
    done = true
    if job then
      pcall(vim.fn.jobstop, job)
    end
    vim.fn.delete(tmp_dir, 'rf')
    callback(result)
  end

  job = vim.fn.jobstart(cmd, {
    cwd = cwd,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(out, data)
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        finish(nil)
        return
      end
      local text = table.concat(out, '\n'):gsub('^%s+', ''):gsub('%s+$', '')
      if text == '' then
        finish(nil)
        return
      end
      finish(text)
    end,
  })

  if job <= 0 then
    finish(nil)
    return
  end

  vim.defer_fn(function()
    if not done then
      finish(nil)
    end
  end, timeout_ms)
end

return M
