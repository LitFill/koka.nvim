---@mod koka.treesitter
---@brief [[
---TreeSitter utilities for Koka
---@brief ]]

local koka_ui = require('koka.ui')

local M = {}

---Check if TreeSitter is available
---@return boolean
function M.is_available()
  local ok = pcall(require, 'nvim-treesitter')
  return ok
end

---Check if parser is installed
---@return boolean
function M.is_parser_installed()
  local has_parser = #vim.api.nvim_get_runtime_file('parser/koka.*', false) > 0
  return has_parser
end

---Install Koka TreeSitter parser
---@return boolean success
function M.install_parser()
  if not M.is_available() then
    koka_ui.notify('nvim-treesitter is required for TreeSitter support', vim.log.levels.DEBUG)
    return false
  end

  local parsers = require('nvim-treesitter.parsers')
  local list = parsers.get_parser_configs and parsers.get_parser_configs() or parsers

  -- Check if parser already configured
  if list.koka then
    return true
  end

  list.koka = {
    install_info = {
      url = 'https://github.com/koka-community/tree-sitter-koka',
      files = { 'src/parser.c', 'src/scanner.c' },
      branch = 'main',
    },
  }

  vim.api.nvim_create_autocmd('User', {
    pattern = 'TSUpdate',
    callback = function()
      local p = parsers.get_parser_configs and parsers.get_parser_configs() or parsers
      p.koka = {
        install_info = {
          url = 'https://github.com/koka-community/tree-sitter-koka',
          files = { 'src/parser.c', 'src/scanner.c' },
          branch = 'main',
        },
      }
    end,
  })

  return true
end

---Find runnable functions using TreeSitter
---@param bufnr number
---@return table[] runnables Array of {line, col, name, type}
function M.find_runnables(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Try to use TreeSitter if available
  local has_parser, parser = pcall(vim.treesitter.get_parser, bufnr, 'koka')
  if not has_parser or not parser then
    return M._find_runnables_fallback(bufnr)
  end

  local tree = parser:parse()[1]
  if not tree then
    return M._find_runnables_fallback(bufnr)
  end

  local root = tree:root()
  local ok, query = pcall(
    vim.treesitter.query.parse,
    'koka',
    [[
    (puredecl
      (qidentifier) @func.name
      (#match? @func.name "^(main|test.*|example.*)$")
    ) @func
    ]]
  )
  if not ok then
    return M._find_runnables_fallback(bufnr)
  end

  local runnables = {}
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    if query.captures[id] == 'func.name' then
      local func_name = vim.treesitter.get_node_text(node, bufnr)
      local row, col = node:range()

      local func_type = 'run'
      if func_name:match('^test') then
        func_type = 'test'
      elseif func_name:match('^example') then
        func_type = 'example'
      end

      table.insert(runnables, {
        line = row,
        col = col,
        name = func_name,
        type = func_type,
      })
    end
  end

  if #runnables > 0 then
    -- When a module is declared, only `pub` functions are runnable.
    if M._has_module_declaration(bufnr) then
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      runnables = vim.tbl_filter(function(r)
        local text = lines[r.line + 1] or ''
        return text:match('^%s*pub%s+fun') ~= nil
      end, runnables)
    end
    return runnables
  end

  -- Fallback if query didn't find anything
  return M._find_runnables_fallback(bufnr)
end

---Fallback regex-based runnable finder
---@param bufnr number
---@return table[] runnables
function M._find_runnables_fallback(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local has_module = M._has_module_declaration(bufnr)
  local runnables = {}

  for line_nr, line in ipairs(lines) do
    local pub_match = has_module and line:match('^%s*pub%s+fun%s+([%w%-]+)%s*%(')
      or line:match('^%s*pub%s+fun%s+([%w%-]+)%s*%(')
    local fun_match = not has_module and line:match('^%s*fun%s+([%w%-]+)%s*%(')

    local func_name = pub_match or fun_match
    if func_name then
      local func_type = nil
      if func_name == 'main' then
        func_type = 'run'
      elseif func_name:match('^test') then
        func_type = 'test'
      elseif func_name:match('^example') then
        func_type = 'example'
      end

      if func_type then
        local col = line:find(func_name, 1, true) or 1
        table.insert(runnables, {
          line = line_nr - 1,
          col = col - 1,
          name = func_name,
          type = func_type,
        })
      end
    end
  end

  return runnables
end

---Check if buffer has module declaration
---@param bufnr number
---@return boolean
function M._has_module_declaration(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, line in ipairs(lines) do
    if line:match('^%s*module%s+[%w%-]+') then
      return true
    end
  end
  return false
end

---Check whether an argument source text is a single literal value.
---Accepts int, float, char, and string literals, with optional outer parens.
---@param text string The argument source text
---@return boolean
function M.is_literal_arg(text)
  if not text then
    return false
  end
  local s = text:gsub('^%s+', ''):gsub('%s+$', '')

  -- Strip balanced outer parentheses.
  local changed = true
  while changed do
    changed = false
    if s:sub(1, 1) == '(' and s:sub(-1) == ')' then
      local depth = 0
      local balanced = true
      for i = 1, #s do
        local c = s:sub(i, i)
        if c == '(' then
          depth = depth + 1
        elseif c == ')' then
          depth = depth - 1
          if depth == 0 and i < #s then
            balanced = false
            break
          end
        end
      end
      if balanced and depth == 0 then
        s = s:sub(2, -2):gsub('^%s+', ''):gsub('%s+$', '')
        changed = true
      end
    end
  end

  if s == '' then
    return false
  end
  -- String literal. A single string has no quote in the middle.
  if s:sub(1, 1) == '"' and s:sub(-1) == '"' and #s >= 2 then
    if not s:sub(2, -2):find('"') then
      return true
    end
  end
  -- Char literal. A single char has no quote in the middle.
  if s:sub(1, 1) == "'" and s:sub(-1) == "'" and #s >= 2 then
    if not s:sub(2, -2):find("'") then
      return true
    end
  end
  -- Hex integer.
  if s:match('^%-?0[xX]%x+') then
    return true
  end
  -- Decimal or float. Allow digits, separators, dot, exponent, and sign.
  if s:match('^%-?%d') and s:match('^%-?[0-9a-fA-FxX._eE%+%-]+$') then
    return true
  end
  return false
end

---Forward declarations for static-argument analysis.
local is_static, is_static_call

---Check if a node is static: a literal, or a call whose arguments are static.
---@param node TSNode
---@param bufnr number
---@return boolean
is_static = function(node, bufnr)
  local t = node:type()
  if t == 'int' or t == 'float' or t == 'char' or t == 'string' then
    return true
  end
  if t == 'opexpr' or t == 'ntlexpr' then
    local text = vim.treesitter.get_node_text(node, bufnr)
    if text:sub(-1) == ')' then
      return is_static_call(node, bufnr)
    end
    -- Operator expression: every atom operand must be static.
    local has_op = false
    for i = 0, node:named_child_count() - 1 do
      local ct = node:named_child(i):type()
      if ct == 'op' or ct == 'idop' or ct == 'qidop' then
        has_op = true
      end
    end
    if has_op then
      for i = 0, node:named_child_count() - 1 do
        local c = node:named_child(i)
        if c:type() == 'atom' and not is_static(c, bufnr) then
          return false
        end
      end
      return true
    end
  end
  -- Parentheses, tuples, and lists: every part must be static.
  if t == 'aexprs' or t == 'cexprs' then
    for i = 0, node:named_child_count() - 1 do
      if not is_static(node:named_child(i), bufnr) then
        return false
      end
    end
    return true
  end
  if node:named_child_count() == 1 then
    return is_static(node:named_child(0), bufnr)
  end
  return false
end

---Check if a node is a call whose arguments are all static.
---@param node TSNode
---@param bufnr number
---@return boolean
is_static_call = function(node, bufnr)
  if vim.treesitter.get_node_text(node, bufnr):sub(-1) ~= ')' then
    return false
  end
  local atom, args
  for i = 0, node:named_child_count() - 1 do
    local c = node:named_child(i)
    local ct = c:type()
    if ct == 'atom' then
      if atom then
        return false
      end
      atom = c
    elseif ct == 'arguments' then
      if args then
        return false
      end
      args = c
    else
      return false
    end
  end
  if not atom then
    return false
  end
  local name_node = atom:named_child(0)
  if not name_node or name_node:type() ~= 'name' then
    return false
  end
  if args then
    for i = 0, args:named_child_count() - 1 do
      if not is_static(args:named_child(i), bufnr) then
        return false
      end
    end
  end
  return true
end

---Try to read one opexpr/ntlexpr node as a call with static arguments.
---A call has an atom name and an optional arguments list, and ends with ')'.
---A zero-argument call has only the atom.
---@param node TSNode The candidate node
---@param bufnr number The buffer
---@return table? call {line, col, func_name, args_text, key}, or nil
function M._try_call(node, bufnr)
  local count = node:named_child_count()
  if count ~= 1 and count ~= 2 then
    return nil
  end

  local atom = node:named_child(0)
  if atom:type() ~= 'atom' then
    return nil
  end

  local call_args
  if count == 2 then
    call_args = node:named_child(1)
    if call_args:type() ~= 'arguments' then
      return nil
    end
  end

  -- A call ends with ')'. An index ends with ']'. Reject the index.
  if vim.treesitter.get_node_text(node, bufnr):sub(-1) ~= ')' then
    return nil
  end

  local name_node = atom:named_child(0)
  if not name_node or name_node:type() ~= 'name' then
    return nil
  end
  local qid = name_node:named_child(0)
  if not qid or qid:type() ~= 'qidentifier' then
    return nil
  end
  local func_name = vim.treesitter.get_node_text(qid, bufnr)
  if func_name:find('%.') then
    return nil
  end

  -- Skip effectful output builtins. Evaluate the inner total call instead.
  if func_name == 'println' or func_name == 'print' then
    return nil
  end

  local args_text = ''
  if call_args then
    for i = 0, call_args:named_child_count() - 1 do
      if not is_static(call_args:named_child(i), bufnr) then
        return nil
      end
    end
    args_text = vim.treesitter.get_node_text(call_args, bufnr)
  end

  local row, col = node:end_()
  return {
    line = row,
    col = col,
    func_name = func_name,
    args_text = args_text,
    key = func_name .. '(' .. args_text .. ')',
  }
end

---Try to read a val/var binding as a static expression hint.
---@param node TSNode The decl node
---@param bufnr number The buffer
---@return table? call {line, col, func_name, args_text, expr, key}, or nil
function M._try_val(node, bufnr)
  local pattern, expr
  for i = 0, node:named_child_count() - 1 do
    local c = node:named_child(i)
    local ct = c:type()
    if ct == 'pattern' then
      pattern = c
    elseif ct == 'expr' or ct == 'basicexpr' then
      expr = c
    end
  end
  if not pattern or not expr then
    return nil
  end
  if not is_static(expr, bufnr) then
    return nil
  end
  -- If the expr is a call, let the call handler take it.
  local inner = expr
  while inner and inner:named_child_count() == 1 and inner:type() ~= 'opexpr' and inner:type() ~= 'ntlexpr' do
    inner = inner:named_child(0)
  end
  if inner and (inner:type() == 'opexpr' or inner:type() == 'ntlexpr') then
    if M._try_call(inner, bufnr) then
      return nil
    end
  end
  local text = vim.treesitter.get_node_text(expr, bufnr)
  -- Skip a single literal. It is trivial.
  if M.is_literal_arg(text) then
    return nil
  end
  local name = vim.treesitter.get_node_text(pattern, bufnr)
  local row, col = expr:end_()
  return {
    line = row,
    col = col,
    func_name = name,
    args_text = '',
    expr = text,
    key = 'val:' .. name .. '=' .. text,
  }
end

---Try to read a UCFM dot chain as a static expression hint.
---A chain is an atom, then dot names or dot-call arguments only.
---@param node TSNode The candidate node
---@param bufnr number The buffer
---@return table? call {line, col, func_name, args_text, expr, key}, or nil
function M._try_ucfm(node, bufnr)
  local count = node:named_child_count()
  if count < 2 then
    return nil
  end

  local head = node:named_child(0)
  local ht = head:type()
  -- The head is an atom (literal) or a static call like add(1, 2).
  if ht ~= 'atom' and ht ~= 'opexpr' and ht ~= 'ntlexpr' then
    return nil
  end

  local text = vim.treesitter.get_node_text(node, bufnr)
  -- A UCFM chain has a dot. A plain call has no dot.
  if not text:find('%.') then
    return nil
  end

  -- Every child after the atom must be a name (dot) or arguments (dotcall).
  for i = 1, count - 1 do
    local c = node:named_child(i)
    local ct = c:type()
    if ct ~= 'name' and ct ~= 'arguments' then
      return nil
    end
    if ct == 'arguments' then
      for j = 0, c:named_child_count() - 1 do
        if not is_static(c:named_child(j), bufnr) then
          return nil
        end
      end
    end
  end

  -- The head is static if it is a literal, or a call head. A call head is a
  -- name followed by '(' in the chain text. This covers add(1, 2) and foo().
  -- The arguments are checked static above.
  local head_ok = is_static(head, bufnr)
  if not head_ok and head:type() == 'atom' then
    local head_text = vim.treesitter.get_node_text(head, bufnr)
    local rest = text:sub(#head_text + 1)
    if rest:match('^%s*%(') then
      head_ok = true
    end
  end
  if not head_ok then
    return nil
  end

  local row, col = node:end_()
  return {
    line = row,
    col = col,
    func_name = 'ucfm',
    args_text = '',
    expr = text,
    key = 'ucfm:' .. text,
  }
end

---Fallback regex scan for calls with literal arguments.
---@param bufnr number
---@return table[] calls
function M._find_total_calls_fallback(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local results = {}
  for idx, line in ipairs(lines) do
    for fname, args in line:gmatch('([%w_]+)%(([^%(%)]*)%)') do
      local ok = true
      local parts = {}
      if args ~= '' then
        for part in (args .. ','):gmatch('(.-),') do
          part = part:gsub('^%s+', ''):gsub('%s+$', '')
          if part ~= '' then
            if not M.is_literal_arg(part) then
              ok = false
              break
            end
            parts[#parts + 1] = part
          end
        end
        if #parts == 0 then
          ok = false
        end
      end
      if ok then
        local args_text = table.concat(parts, ', ')
        results[#results + 1] = {
          line = idx - 1,
          col = #line,
          func_name = fname,
          args_text = args_text,
          key = fname .. '(' .. args_text .. ')',
        }
      end
    end
  end
  return results
end

---Find calls to total functions where every argument is a literal.
---Uses TreeSitter when available, otherwise a regex fallback.
---@param bufnr number
---@return table[] calls Array of {line, col, func_name, args_text, key}
function M.find_total_calls(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local has_parser, parser = pcall(vim.treesitter.get_parser, bufnr, 'koka')
  if not has_parser or not parser then
    return M._find_total_calls_fallback(bufnr)
  end

  local ok, tree = pcall(function()
    return parser:parse()[1]
  end)
  if not ok or not tree then
    return M._find_total_calls_fallback(bufnr)
  end

  local root = tree:root()
  local results = {}

  local function visit(node)
    local t = node:type()
    if t == 'decl' then
      local r = M._try_val(node, bufnr)
      if r then
        results[#results + 1] = r
        return
      end
    end
    if t == 'opexpr' or t == 'ntlexpr' then
      local r = M._try_call(node, bufnr)
      if r then
        results[#results + 1] = r
        return
      end
      local u = M._try_ucfm(node, bufnr)
      if u then
        results[#results + 1] = u
        return
      end
    end
    for i = 0, node:named_child_count() - 1 do
      visit(node:named_child(i))
    end
  end

  pcall(visit, root)
  return results
end

---Find the function declaration containing a 0-indexed line.
---Returns the innermost enclosing `fun` and its name.
---@param bufnr number
---@param line number 0-indexed line
---@return table|nil {name=string, row=number}
function M.find_function_at(bufnr, line)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local has_parser, parser = pcall(vim.treesitter.get_parser, bufnr, 'koka')
  if not has_parser or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local ok, query = pcall(
    vim.treesitter.query.parse,
    'koka',
    [[
    (puredecl
      (qidentifier) @func.name
    )
  ]]
  )
  if not ok then
    return nil
  end

  local best = nil
  for id, node in query:iter_captures(tree:root(), bufnr, 0, -1) do
    if query.captures[id] == 'func.name' then
      local parent = node:parent()
      if parent then
        local srow, _, erow = parent:range()
        if line >= srow and line <= erow then
          if not best or srow > best.row then
            best = {
              name = vim.treesitter.get_node_text(node, bufnr),
              row = srow,
              erow = erow,
            }
          end
        end
      end
    end
  end

  return best
end

---Read a call node's head name and argument count.
---Mirrors _try_call's name rules but does not require static arguments.
---@param node TSNode An opexpr or ntlexpr node
---@param bufnr number
---@return table? call {name=string, nargs=number, row=number, col=number}
function M._call_name_arity(node, bufnr)
  local count = node:named_child_count()
  if count ~= 1 and count ~= 2 then
    return nil
  end

  local atom = node:named_child(0)
  if atom:type() ~= 'atom' then
    return nil
  end

  local call_args
  if count == 2 then
    call_args = node:named_child(1)
    if call_args:type() ~= 'arguments' then
      return nil
    end
  end

  if vim.treesitter.get_node_text(node, bufnr):sub(-1) ~= ')' then
    return nil
  end

  local name_node = atom:named_child(0)
  if not name_node or name_node:type() ~= 'name' then
    return nil
  end
  local qid = name_node:named_child(0)
  if not qid or qid:type() ~= 'qidentifier' then
    return nil
  end

  local func_name = vim.treesitter.get_node_text(qid, bufnr)
  if func_name:find('%.') then
    return nil
  end

  local nargs = call_args and call_args:named_child_count() or 0
  local row, col = node:range()
  return { name = func_name, nargs = nargs, row = row, col = col }
end

---Find the innermost call enclosing a 0-indexed position.
---@param bufnr number
---@param line number 0-indexed line
---@param col number 0-indexed column
---@return table? call {name=string, nargs=number, row=number, col=number}
function M.find_call_at(bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local has_parser, parser = pcall(vim.treesitter.get_parser, bufnr, 'koka')
  if not has_parser or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local node = tree:root():named_descendant_for_point_range(line, col, line, col)
  while node do
    local t = node:type()
    if t == 'opexpr' or t == 'ntlexpr' then
      local r = M._call_name_arity(node, bufnr)
      if r then
        return r
      end
    end
    node = node:parent()
  end

  return nil
end

---Find the expression (call, dot chain, or atom) at a 0-indexed position.
---Prefers the innermost enclosing call or chain, else the atom or name.
---@param bufnr number
---@param line number 0-indexed line
---@param col number 0-indexed column
---@return table? expr {text=string, srow=number, scol=number, erow=number, ecol=number}
function M.find_expr_at(bufnr, line, col)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local has_parser, parser = pcall(vim.treesitter.get_parser, bufnr, 'koka')
  if not has_parser or not parser then
    return nil
  end

  local tree = parser:parse()[1]
  if not tree then
    return nil
  end

  local node = tree:root():named_descendant_for_point_range(line, col, line, col)
  local call, atom
  local n = node
  while n do
    local t = n:type()
    if (t == 'opexpr' or t == 'ntlexpr') and not call then
      call = n
    end
    if (t == 'atom' or t == 'name') and not atom then
      atom = n
    end
    n = n:parent()
  end

  local chosen = call or atom
  if not chosen then
    return nil
  end

  local srow, scol, erow, ecol = chosen:range()
  return {
    text = vim.treesitter.get_node_text(chosen, bufnr),
    srow = srow,
    scol = scol,
    erow = erow,
    ecol = ecol,
  }
end

return M
