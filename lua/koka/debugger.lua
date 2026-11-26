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
local koka_cmd = require('koka.koka_cmd')
local koka_ui = require('koka.ui')
local koka_run = require('koka.run')

---Execute a program or function using Koka LSP
---@param client vim.lsp.Client The LSP client
---@param project_config koka.project.Config The project config
---@param args koka.debugger.LaunchArguments The execution arguments
---@param callback? function Callback function to handle the result
function M.execute(client, project_config, args, callback)
  local target = project_config.target or 'c'
  local additional_args = table.concat(koka_cmd.common_args(project_config, { buildtag = 'nvim' }), ' ')
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
      koka_ui.notify('Error executing Koka command: ' .. tostring(err.message or err), vim.log.levels.ERROR)
      if callback then
        callback(nil, err)
      end
      return
    end

    if not result then
      koka_ui.notify('Error generating code, see language server output for specifics', vim.log.levels.ERROR)
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
      koka_ui.notify('Error finding generated code at ' .. output_path, vim.log.levels.ERROR)
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
    koka_ui.notify(
      string.format('Running code for target %s is not yet supported. Output is at %s', target, executable_path),
      vim.log.levels.WARN
    )
    if callback then
      callback(executable_path, nil)
    end
    return
  end

  local full_cmd = vim.list_extend({ cmd }, cmd_args)
  koka_run.run_term(full_cmd, cwd, 'Execution', function(exit_code)
    if callback then
      callback(executable_path, exit_code)
    end
  end)
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

---Build the wrapper source: the buffer text plus an entry that prints the call.
---@param lines string[] The buffer lines
---@param func_name string Name of the total function
---@param args_text string Comma-separated literal arguments
---@return string[] wrapper_lines
function M._build_wrapper(lines, func_name, args_text)
  local wrapper = {}
  vim.list_extend(wrapper, lines)
  wrapper[#wrapper + 1] = ''
  wrapper[#wrapper + 1] = string.format('fun kokaInlayEntry() { println(%s(%s)) }', func_name, args_text)
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
  local call = {
    func_name = func_name,
    args_text = args_text,
    key = func_name .. '(' .. args_text .. ')',
  }
  M.eval_calls(project_config, program_path, lines, { call }, function(results, _total, _effects, err)
    if err then
      callback(nil, err)
      return
    end
    local text = results and results[call.key] or nil
    callback(text, nil)
  end, timeout_ms)
end

---Build the wrapper source for many calls. Each result follows a marker line.
---@param lines string[] The buffer lines
---@param calls table[] The calls
---@return string[] wrapper_lines
function M._build_wrapper_calls(lines, calls)
  local wrapper = {}
  vim.list_extend(wrapper, lines)
  wrapper[#wrapper + 1] = ''
  wrapper[#wrapper + 1] = 'fun kokaInlayEntry() {'
  -- Koka rejects an empty body. A unit statement makes it valid.
  wrapper[#wrapper + 1] = '  ()'
  for i, call in ipairs(calls) do
    wrapper[#wrapper + 1] = string.format('  println("@@KI%d@@")', i)
    if call.expr then
      wrapper[#wrapper + 1] = string.format('  println(%s)', call.expr)
    else
      wrapper[#wrapper + 1] = string.format('  println(%s(%s))', call.func_name, call.args_text)
    end
  end
  wrapper[#wrapper + 1] = '}'
  return wrapper
end

local effect_words = {
  pure = true,
  exn = true,
  div = true,
  console = true,
  ndet = true,
  fsys = true,
  st = true,
  io = true,
  random = true,
  read = true,
  write = true,
  state = true,
  global = true,
  async = true,
}

---Parse --showtypesigs output. Return the set of total definition names.
---@param out string[] The stdout lines
---@return table<string,boolean>
---Parse --showtypesigs output. Return the total set and the effect map.
---@param out string[] The stdout lines
---@return table<string,boolean> total
---@return table<string,string> effects
function M._parse_sigs(out)
  local total = {}
  local effects = {}
  for _, line in ipairs(out) do
    local name = line:match('^sig/([^%s:]+)')
    local rest = line:match('%-%>%s*(.*)$')
    if name and rest then
      local first = rest:match('^(%S+)')
      local is_effect = rest:sub(1, 1) == '<' or (first and (first:find('/') or effect_words[first]))
      if is_effect then
        effects[name] = rest
      elseif first then
        total[name] = true
      end
    end
  end
  return total, effects
end

---Evaluate many total calls in one koka run. Returns a map of key to result text.
---@param project_config koka.project.Config The project config
---@param program_path string Path to the Koka program
---@param lines string[] The buffer lines
---@param calls table[] The calls
---@param callback fun(results: table<string,string>?, total: table<string,boolean>?, error_text: string?)
---@param timeout_ms? number Kill the run after this many milliseconds
function M.eval_calls(project_config, program_path, lines, calls, callback, timeout_ms)
  timeout_ms = timeout_ms or 20000
  local orig_dir = vim.fs.dirname(program_path)
  local module_name = M._module_name(lines, program_path)
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, 'p')
  local tmp_file = vim.fs.joinpath(tmp_dir, module_name .. '.kk')
  local wrapper = M._build_wrapper_calls(lines, calls)
  vim.fn.writefile(wrapper, tmp_file)

  local cmd = koka_cmd.build(project_config, {
    mode = '-e',
    file = tmp_file,
    main_entry = 'kokaInlayEntry',
    showtypesigs = true,
    buildtag = 'nvim',
    include = { orig_dir },
  })

  local cwd = project_config.cwd or orig_dir
  local out = {}
  local err = {}
  local done = false
  local job

  local function finish(results, total, effects, error_text)
    if done then
      return
    end
    done = true
    if job then
      pcall(vim.fn.jobstop, job)
    end
    vim.fn.delete(tmp_dir, 'rf')
    pcall(callback, results, total, effects, error_text)
  end

  job = vim.fn.jobstart(cmd, {
    cwd = cwd,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(out, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(err, data)
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code ~= 0 then
        local errout = table.concat(err, '\n'):gsub('^%s+', ''):gsub('%s+$', '')
        local outtail = table.concat(out, '\n'):match('([^\n]+)%s*$') or ''
        local msg = outtail
        if errout ~= '' then
          msg = (msg ~= '' and (msg .. '\n' .. errout) or errout)
        end
        if msg == '' then
          msg = 'koka exited with code ' .. exit_code
        end
        finish(nil, nil, nil, msg)
        return
      end
      -- Parse marker lines. The next non-empty line is that call's result.
      local results = {}
      local expect = nil
      for _, line in ipairs(out) do
        if expect then
          local text = line:gsub('^%s+', ''):gsub('%s+$', '')
          if text ~= '' then
            results[expect] = text
            expect = nil
          end
        else
          local idx = line:match('^@@KI(%d+)@@$')
          if idx then
            local call = calls[tonumber(idx)]
            if call then
              expect = call.key
            end
          end
        end
      end
      local total, effects = M._parse_sigs(out)
      finish(results, total, effects, nil)
    end,
  })

  if job <= 0 then
    finish(nil, nil, nil, 'could not start koka')
    return
  end

  vim.defer_fn(function()
    if not done then
      finish(nil, nil, nil, 'koka timed out')
    end
  end, timeout_ms)
end

return M
