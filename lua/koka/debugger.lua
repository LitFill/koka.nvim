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
local project = require('koka.project')

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
    if project.is_absolute_path(output_path) then
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

---Build the wrapper source for many calls.
---Each call becomes its own function, so `--showtypesigs` reports that call's
---effect row under a stable name (`call.chk`) and a call that cannot be shown
---fails on its own instead of the whole batch. With `sigs_only` no entry point
---is emitted, so nothing runs.
---@param lines string[] The buffer lines
---@param calls table[] The calls
---@param sigs_only boolean? Only declare the per-call functions
---@return string[] wrapper_lines
function M._build_wrapper_calls(lines, calls, sigs_only)
  local wrapper = {}
  vim.list_extend(wrapper, lines)
  wrapper[#wrapper + 1] = ''
  for i, call in ipairs(calls) do
    local name = call.chk or string.format('kokaChk%d', i)
    call.chk = name
    local body = call.expr or string.format('%s(%s)', call.func_name, call.args_text)
    wrapper[#wrapper + 1] = string.format('fun %s() { %s }', name, body)
  end
  if sigs_only then
    return wrapper
  end
  wrapper[#wrapper + 1] = ''
  wrapper[#wrapper + 1] = 'fun kokaInlayEntry() {'
  -- Koka rejects an empty body. A unit statement makes it valid.
  wrapper[#wrapper + 1] = '  ()'
  for i, call in ipairs(calls) do
    wrapper[#wrapper + 1] = string.format('  println("@@KI%d@@")', i)
    wrapper[#wrapper + 1] = string.format('  println(%s())', call.chk)
  end
  wrapper[#wrapper + 1] = '}'
  return wrapper
end

---Find the first top-level `->`, ignoring arrows nested in parentheses, angle
---brackets or square brackets.
---@param text string
---@return number? byte index of the arrow
local function find_top_arrow(text)
  local depth = 0
  for pos = 1, #text do
    local c = text:sub(pos, pos)
    if c == '(' or c == '<' or c == '[' then
      depth = depth + 1
    elseif c == ')' or c == '>' or c == ']' then
      depth = depth - 1
    elseif depth == 0 and c == '-' and text:sub(pos + 1, pos + 1) == '>' then
      return pos
    end
  end
  return nil
end

---Whether a type has a space at top level. Koka prints a closed effect row as
---`exn int`, so the space is what separates the effect from the result type.
---@param text string
---@return boolean
local function has_top_space(text)
  local depth = 0
  for pos = 1, #text do
    local c = text:sub(pos, pos)
    if c == '(' or c == '<' or c == '[' then
      depth = depth + 1
    elseif c == ')' or c == '>' or c == ']' then
      depth = depth - 1
    elseif depth == 0 and c == ' ' then
      return true
    end
  end
  return false
end

---Parse --showtypesigs output. Return the total set and the effect map.
---Koka prints `module/name: <params> -> <effect>? <result>`; older builds used a
---`sig/` prefix. Only a top-level arrow counts, so `(f : (int) -> int) -> int`
---is read correctly.
---@param out string[] The stdout lines
---@return table<string,boolean> total
---@return table<string,string> effects
function M._parse_sigs(out)
  local total = {}
  local effects = {}
  for _, line in ipairs(out) do
    local name, rest = line:match('^sig/([^%s:]+)%s*:%s*(.*)$')
    if not name then
      name, rest = line:match('^([%w%-%.]+/[%w%-%.~/]+)%s*:%s*(.*)$')
    end
    if name and rest then
      local arrow = find_top_arrow(rest)
      if arrow then
        local result = rest:sub(arrow + 2):gsub('^%s+', '')
        if result:sub(1, 1) == '<' or has_top_space(result) then
          effects[name] = result
        else
          total[name] = true
        end
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
---@param callback fun(results: table<string,string>?, total: table<string,boolean>?, effects: table<string,string>?, error_text: string?)
---@param timeout_ms? number Kill the run after this many milliseconds
---@param opts? {sigs_only: boolean?} Only emit signatures, run nothing
function M.eval_calls(project_config, program_path, lines, calls, callback, timeout_ms, opts)
  opts = opts or {}
  timeout_ms = timeout_ms or 20000
  local orig_dir = vim.fs.dirname(program_path)
  local module_name = M._module_name(lines, program_path)
  local tmp_dir = vim.fn.tempname()
  vim.fn.mkdir(tmp_dir, 'p')
  local tmp_file = vim.fs.joinpath(tmp_dir, module_name .. '.kk')
  local wrapper = M._build_wrapper_calls(lines, calls, opts.sigs_only)
  vim.fn.writefile(wrapper, tmp_file)

  local cmd = koka_cmd.build(project_config, {
    mode = opts.sigs_only and '-l' or '-e',
    file = tmp_file,
    main_entry = opts.sigs_only and nil or 'kokaInlayEntry',
    showtypesigs = true,
    -- Inlay compiles its own module with a per-call entry point; sharing the
    -- `nvim` tag with the LSP and the debugger would poison that cache.
    buildtag = 'nvim-eval',
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
    stdout_buffered = true,
    stderr_buffered = true,
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
