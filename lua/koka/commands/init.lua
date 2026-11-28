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
      stdout_buffered = true,
      stderr_buffered = true,
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
      for i = 1, #test_names do
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
      local out = {}
      vim.fn.jobstart(cmd, {
        cwd = cwd,
        stdout_buffered = true,
        stderr_buffered = true,
        on_stdout = function(_, data)
          out[#out + 1] = table.concat(data, '\n')
        end,
        on_stderr = function(_, data)
          out[#out + 1] = table.concat(data, '\n')
        end,
        on_exit = function(_, code)
          local log = table.concat(out)
          results[index] = code == 0 and not log:find('uncaught exception', 1, true)
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
      table.insert(lines, '')
      table.insert(lines, 'Include Directories:')
      for _, dir in ipairs(config.include_dirs) do
        table.insert(lines, string.format('  - %s', dir))
      end
    end

    if config.compiler_args and #config.compiler_args > 0 then
      table.insert(lines, '')
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
  local lhs, rhs = line:match('^([^:]+):%s+(.+)$')
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

---Split a string by commas that are not nested in brackets or angle brackets.
---@param s string
---@return string[] parts
local function split_top_commas(s)
  local parts = {}
  local depth = 0
  local last = 1
  for i = 1, #s do
    local c = s:sub(i, i)
    if c == '(' or c == '<' or c == '[' then
      depth = depth + 1
    elseif c == ')' or c == '>' or c == ']' then
      depth = depth - 1
    elseif c == ',' and depth == 0 then
      parts[#parts + 1] = s:sub(last, i - 1)
      last = i + 1
    end
  end
  parts[#parts + 1] = s:sub(last)
  return parts
end

---Parse a full function type into parameter types and a result type.
---Strips a leading forall<...>. The first value is nil when the shape is not
---a function type.
---@param t string
---@return table? params Array of {name=string?, type=string?}
---@return string? ret
local function parse_type(t)
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

  local params = {}
  local inner = s:sub(2, close - 1)
  if inner:match('%S') then
    for _, raw in ipairs(split_top_commas(inner)) do
      local seg = raw:match('^%s*(.-)%s*$')
      local name, ty = seg:match('^[%?]?([A-Za-z_][A-Za-z0-9_]*)%s*:%s*(.+)$')
      if name and ty then
        params[#params + 1] = { name = name, type = ty }
      else
        params[#params + 1] = { name = nil, type = nil }
      end
    end
  end

  local rest = s:sub(close + 1):match('^%s*->%s*(.*)$')
  if not rest or rest == '' then
    return params, nil
  end
  return params, rest
end

---Insert inferred parameter and return types into a function signature.
---Only the single-line parameter list case is handled.
---@param bufnr number
---@param func table {name=string, row=number}
---@param params table Array of {name=string?, type=string?}
---@param ret string?
function M.apply_signature(bufnr, func, params, ret)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local text = lines[func.row + 1]
  if not text then
    koka_ui.notify('sig: function line not found', vim.log.levels.ERROR)
    return
  end
  local open = text:find('(', 1, true)
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

  -- Collect insertions as {col, text}; apply right to left.
  local inserts = {}

  local brace = text:find('{', close, true)
  local between = text:sub(close + 1, brace and (brace - 1) or #text)
  if ret and not between:find(':', 1, true) then
    inserts[#inserts + 1] = { col = close, text = ': ' .. ret }
  end

  local inner = text:sub(open + 1, close - 1)
  local src_params = inner:match('%S') and split_top_commas(inner) or {}
  if #params > 0 and #src_params == #params then
    local seg_start = open + 1
    for idx, seg in ipairs(src_params) do
      local lead = seg:match('^%s*')
      local name_part = seg:sub(#lead + 1):match('^[%?]?[A-Za-z_][A-Za-z0-9_]*')
      local has_type = seg:find(':', 1, true) ~= nil
      local is_default = seg:find('=', 1, true) ~= nil
      local inferred = params[idx]
      if
        name_part
        and not has_type
        and not is_default
        and inferred
        and inferred.type
        and not inferred.type:match('^%?')
      then
        local col = seg_start + #lead + #name_part - 1
        inserts[#inserts + 1] = { col = col, text = ': ' .. inferred.type }
      end
      seg_start = seg_start + #seg + 1
    end
  end

  if #inserts == 0 then
    koka_ui.notify(string.format('sig: %s already fully annotated', func.name), vim.log.levels.INFO)
    return
  end

  table.sort(inserts, function(a, b)
    return a.col > b.col
  end)
  for _, ins in ipairs(inserts) do
    vim.api.nvim_buf_set_text(bufnr, func.row, ins.col, func.row, ins.col, { ins.text })
  end
  koka_ui.notify(string.format('sig: annotated %s', func.name), vim.log.levels.INFO)
end

---Infer and write the signature of the function under the cursor.
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
    local cwd = config.cwd or vim.fs.dirname(file_path)

    ---Run --showtypesigs with the given mode, yield the inferred type.
    ---@param mode string
    ---@param cb fun(ty: string?)
    local function infer(mode, cb)
      local cmd = koka_cmd.build(config, { mode = mode, file = file_path, showtypesigs = true })
      vim.system(cmd, { cwd = cwd, text = true }, function(res)
        local out = table.concat({ res.stdout or '', res.stderr or '' }, '\n')
        local inferred
        for _, l in ipairs(vim.split(out, '\n')) do
          local name, ty = parse_sig_line(l)
          if name == func.name then
            inferred = ty
            break
          end
        end
        vim.schedule(function()
          cb(inferred)
        end)
      end)
    end

    ---@param inferred string
    local function apply(inferred)
      local params, ret = parse_type(inferred)
      if not params then
        koka_ui.notify(string.format('sig: could not parse type: %s', inferred), vim.log.levels.WARN)
        return
      end
      M.apply_signature(bufnr, func, params, ret)
    end

    -- A file without `main` fails `-c`; library mode (`-l`) typechecks it.
    infer('-c', function(inferred)
      if inferred then
        apply(inferred)
        return
      end
      infer('-l', function(inferred2)
        if inferred2 then
          apply(inferred2)
        else
          koka_ui.notify(
            string.format('sig: no inferred type for %s (file may not typecheck)', func.name),
            vim.log.levels.WARN
          )
        end
      end)
    end)
  end)
end

---Type variable names for generated stubs, in order.
local STUB_TVARS = {
  'a',
  'b',
  'c',
  'd',
  'e',
  'f',
  'g',
  'h',
  'i',
  'j',
  'k',
  'l',
  'm',
  'n',
  'o',
  'p',
  'q',
  'r',
  's',
  't',
  'u',
  'v',
  'w',
}

---Generate a fully polymorphic throwing stub for a call and append it.
---The stub has an open effect row; the caller is left untouched.
---@param bufnr number
---@param call table {name=string, nargs=number}
function M.apply_call_stub(bufnr, call)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local n = call.nargs
  local tvars = {}
  for i = 1, n + 1 do
    tvars[i] = STUB_TVARS[i] or ('t' .. i)
  end

  local params = {}
  for i = 1, n do
    params[i] = string.format('arg%d : %s', i, tvars[i])
  end
  local ret = tvars[n + 1]

  local sig = string.format('fun %s(%s) : _ %s', call.name, table.concat(params, ', '), ret)
  local body = string.format('  throw("not implemented: %s")', call.name)

  local last = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, last, last, false, { '', sig, body })
  koka_ui.notify(
    string.format('stub: %s/%d args appended (open effect row; a pure caller must open its row)', call.name, n),
    vim.log.levels.INFO
  )
end

---Generate a throwing stub for the call under the cursor.
function M.stub_function()
  local bufnr = vim.api.nvim_get_current_buf()
  local treesitter = require('koka.treesitter')
  local cursor = vim.api.nvim_win_get_cursor(0)
  local call = treesitter.find_call_at(bufnr, cursor[1] - 1, cursor[2])
  if not call then
    koka_ui.notify('stub: no call at cursor', vim.log.levels.WARN)
    return
  end
  M.apply_call_stub(bufnr, call)
end

---Extract the base type name from a type annotation (strip generics and module).
---@param t string
---@return string
local function type_basename(t)
  return t:match('^%s*([A-Za-z_][A-Za-z0-9_]*)') or t
end

---Parse "name : type" pairs from a parameter list string.
---@param inner string
---@return table<string,string>
local function parse_param_types(inner)
  local map = {}
  for _, seg in ipairs(split_top_commas(inner)) do
    local nm, ty = seg:match('^%s*[%?]?([A-Za-z_][A-Za-z0-9_]*)%s*:%s*(.+)$')
    if nm and ty then
      map[nm] = ty
    end
  end
  return map
end

---Find the annotated type of a local `val`/`var` binding by name.
---@param lines string[] Buffer lines
---@param name string Binding name
---@return string? ty The annotated type, or nil
local function find_val_type(lines, name)
  local pats = {
    '^%s*val%s+' .. vim.pesc(name) .. '%s*:%s*([^=]-)%s*=',
    '^%s*var%s+' .. vim.pesc(name) .. '%s*:%s*([^:]-)%s*:=',
  }
  for _, pat in ipairs(pats) do
    for _, line in ipairs(lines) do
      local ty = line:match(pat)
      if ty then
        return vim.trim(ty)
      end
    end
  end
  return nil
end

---Build one match arm per constructor, each body a throw.
---@param ctors table[] Array of {name=string, fields=string[]}
---@param fn_name string
---@param indent string
---@return string[] arms
local function build_arms(ctors, fn_name, indent)
  local arms = {}
  for _, c in ipairs(ctors) do
    local pat = c.name
    if c.fields and #c.fields > 0 then
      pat = c.name .. '(' .. table.concat(c.fields, ', ') .. ')'
    end
    arms[#arms + 1] = string.format('%s%s -> throw("not implemented: %s")', indent, pat, fn_name)
  end
  return arms
end

-- Placeholder match arm emitted by the case-split stub. Case-split replaces it
-- with one arm per constructor. Must be valid Koka (Koka has no `case` keyword).
local MATCH_STUB_ARM = '_ -> throw("not implemented")'

-- Cache for the stdlib source root, derived from `koka --version`.
local stdlib_root_cache = nil

---Return the stdlib source root (share/.../lib), or false when unknown.
---@return string|false
local function stdlib_root()
  if stdlib_root_cache ~= nil then
    return stdlib_root_cache
  end
  local out = vim.fn.system { 'koka', '--version' } or ''
  local lib = out:match('lib%s*:%s*(.-/lib/koka/v[%d%.]+)')
  if not lib then
    stdlib_root_cache = false
    return false
  end
  stdlib_root_cache = (lib:gsub('/lib/koka/', '/share/koka/')) .. '/lib'
  return stdlib_root_cache
end

---Find a stdlib type's constructors by parsing the shipped .kk sources.
---@param name string The type name
---@return table? ctors Array of {name=string, fields=string[]}
local function stdlib_constructors(name)
  local root = stdlib_root()
  if not root then
    return nil
  end
  local found = vim.fn.system {
    'grep',
    '-rlE',
    '^[[:space:]]*([[:alnum:]_]+[[:space:]]+)*type[[:space:]]+' .. name .. '([[:space:]<]|$)',
    root,
  }
  local file = vim.split(found or '', '\n')[1]
  if not file or file == '' then
    return nil
  end

  local lines = vim.fn.readfile(file)
  local start
  for i, l in ipairs(lines) do
    if l:match('^%s*.*type%s+' .. name .. '[%s<]') then
      start = i
      break
    end
  end
  if not start then
    return nil
  end

  local ctors = {}
  for i = start + 1, #lines do
    local l = lines[i]
    -- `con` is optional in modern Koka; accept both `con Name` and a bare `Name`.
    local cname, rest = l:match('^%s*con%s+([A-Za-z_][A-Za-z0-9_]*)%s*(.*)$')
    if not cname then
      cname, rest = l:match('^%s+([A-Za-z_][A-Za-z0-9_]*)%s*(.*)$')
    end
    if cname then
      local fields = {}
      local inner = rest:match('^%((.*)%)')
      if inner then
        for _, seg in ipairs(split_top_commas(inner)) do
          local fn = seg:match('^%s*[%?]?([A-Za-z_][A-Za-z0-9_]*)')
          if fn then
            fields[#fields + 1] = fn
          end
        end
      end
      ctors[#ctors + 1] = { name = cname, fields = fields }
    elseif not (l:match('^%s*$') or l:match('^%s*//') or l:match('^%s')) then
      -- a new top-level form ends the type block
      break
    end
  end

  if #ctors == 0 then
    return nil
  end
  return ctors
end

---Fill a `case -> case` match arm with one arm per local constructor.
---Returns true when it handled the cursor (async work may follow).
---@param bufnr number
---@param cursor number[]
---@return boolean
function M.try_fill_match(bufnr, cursor)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local line = cursor[1] - 1

  local arm
  for i = line, math.max(0, line - 3), -1 do
    if vim.trim(lines[i + 1] or '') == MATCH_STUB_ARM then
      arm = i
      break
    end
  end
  if not arm then
    return false
  end

  local match_line = arm - 1
  local scrutinee = (lines[match_line + 1] or ''):match('^%s*match%s+(.+)%s*$')
  if not scrutinee then
    return false
  end

  local treesitter = require('koka.treesitter')
  local func = treesitter.find_function_at(bufnr, match_line)
  if not func then
    return false
  end

  local sig = lines[func.row + 1] or ''
  local open = sig:find('(', 1, true)
  local inner = ''
  if open then
    local depth, close = 0, nil
    for i = open, #sig do
      local c = sig:sub(i, i)
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
    if close then
      inner = sig:sub(open + 1, close - 1)
    end
  end

  local ty = parse_param_types(inner)[scrutinee]
  if not ty then
    ty = find_val_type(lines, scrutinee)
  end
  if not ty then
    koka_ui.notify('case-split: scrutinee is not an annotated parameter or val binding', vim.log.levels.WARN)
    return true
  end
  local base = type_basename(ty)

  local clients = require('koka.lsp.helpers').get_active_lsp_clients(bufnr)
  if #clients == 0 then
    koka_ui.notify('case-split: no LSP client for constructors', vim.log.levels.WARN)
    return true
  end

  local file_path = vim.api.nvim_buf_get_name(bufnr)
  local indent = (lines[arm + 1] or ''):match('^%s*') or '    '
  clients[1]:request(
    'textDocument/documentSymbol',
    { textDocument = { uri = vim.uri_from_fname(file_path) } },
    function(err, result)
      if err or not result then
        koka_ui.notify('case-split: documentSymbol failed', vim.log.levels.WARN)
        return
      end
      local ctors = {}
      for _, s in ipairs(result) do
        if s.name == base then
          for _, c in ipairs(s.children or {}) do
            local fields = {}
            for _, f in ipairs(c.children or {}) do
              fields[#fields + 1] = f.name
            end
            ctors[#ctors + 1] = { name = c.name, fields = fields }
          end
          break
        end
      end
      if #ctors == 0 then
        ctors = stdlib_constructors(base) or {}
      end
      if #ctors == 0 then
        koka_ui.notify(string.format('case-split: constructors for %s not found', base), vim.log.levels.WARN)
        return
      end
      local arms = build_arms(ctors, func.name, indent)
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_set_lines(bufnr, arm, arm + 1, false, arms)
        end
      end)
      koka_ui.notify(string.format('case-split: %d constructor arms for %s', #ctors, base), vim.log.levels.INFO)
    end
  )
  return true
end

---Fill a match arm with constructors, or wrap the cursor expression in a stub.
function M.case_split()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  if M.try_fill_match(bufnr, cursor) then
    return
  end

  local treesitter = require('koka.treesitter')
  local expr = treesitter.find_expr_at(bufnr, cursor[1] - 1, cursor[2])
  if not expr then
    koka_ui.notify('case-split: no expression at cursor', vim.log.levels.WARN)
    return
  end
  if expr.erow ~= expr.srow then
    koka_ui.notify('case-split: multi-line expression not supported', vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local first = lines[expr.srow + 1] or ''
  local indent = first:match('^%s*') or ''

  vim.api.nvim_buf_set_text(
    bufnr,
    expr.srow,
    expr.scol,
    expr.erow,
    expr.ecol,
    { 'match ' .. expr.text, indent .. '  ' .. MATCH_STUB_ARM }
  )
  koka_ui.notify('case-split: wrapped in match stub', vim.log.levels.INFO)
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
    '  :Koka stub             Append a throwing stub for the call at the cursor',
    '  :Koka case-split        Wrap the expression in a match stub',
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
  if require('koka.project').is_absolute_path(name) then
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
  stub = {
    impl = function()
      M.stub_function()
    end,
  },
  ['case-split'] = {
    impl = function()
      M.case_split()
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
    nargs = '*',
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
