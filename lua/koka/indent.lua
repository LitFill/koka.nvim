---@mod koka.indent
---@brief [[
---Indentation for Koka buffers.
---
---`indentexpr` for Koka. The expression is evaluated with `v:lnum` set to the
---line being indented and returns the number of columns for that line, or -1
---to keep the current indentation.
---
---The implementation is self-contained on purpose: it uses the TreeSitter
---parse tree when one is available, and falls back to the previous line's
---indentation otherwise. nvim-treesitter's own `indentexpr` is not used
---because its `indents.scm` handling aborts on captures this plugin's query
---does not define, which silently collapses every indent to column 0.
---@brief ]]

local ts = require('koka.treesitter')

local M = {}

---Read a buffer-local indentation option, falling back to the global value.
---@param bufnr number
---@param name string
---@return number
local function option_number(bufnr, name)
  local ok, value = pcall(vim.api.nvim_get_option_value, name, { buf = bufnr })
  if ok and type(value) == 'number' and value > 0 then
    return value
  end
  return 2
end

---Return the indent of a 1-indexed line in columns.
---@param bufnr number
---@param lnum number
---@return number
local function line_indent(bufnr, lnum)
  if lnum < 1 then
    return 0
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''
  local _, width = line:find('^%s*')
  return width or 0
end

---Return the 1-indexed line above `lnum` that holds text.
---@param bufnr number
---@param lnum number
---@return number
local function prev_text_line(bufnr, lnum)
  local row = lnum - 2
  while row >= 0 do
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
    if line:match('%S') then
      return row + 1
    end
    row = row - 1
  end
  return 0
end

---Whether a line ends an opening brace, so the next line is indented.
---@param text string
---@return boolean
local function opens_block(text)
  return text:match('{%s*$') ~= nil
end

---Whether a line starts with a closing brace, so it is outdented.
---@param text string
---@return boolean
local function closes_block(text)
  return text:match('^%s*}') ~= nil
end

---Whether a line ends an incomplete expression, so the next line is indented.
---@param text string
---@return boolean
local function continues_expr(text)
  return text:match('[%+%-%*/%%=<>!&|%.%?:%(%[%{,]$') ~= nil
end

---Find the innermost node of `types` that contains the 0-indexed row.
---@param root TSNode
---@param row number
---@param types table<string, boolean>
---@return TSNode?
local function enclosing(root, row, types)
  local node = root:named_descendant_for_range(row, 0, row, 0)
  while node do
    if types[node:type()] then
      return node
    end
    node = node:parent()
  end
  return nil
end

---TreeSitter indentation for the 0-indexed row, or nil when unavailable.
---@param bufnr number
---@param row number
---@param shift number
---@return number?
local function tree_indent(bufnr, row, shift)
  if not ts.is_parser_installed() then
    return nil
  end
  local ok, root = pcall(function()
    local parser = vim.treesitter.get_parser(bufnr)
    if not parser then
      return nil
    end
    parser:parse()
    return parser:parse()[1]:root()
  end)
  if not ok or not root then
    return nil
  end

  local block = enclosing(root, row, { block = true, funbody = true })
  if not block then
    return nil
  end

  -- A closing brace lines up with the line that opened the block.
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
  if closes_block(line) then
    return line_indent(bufnr, block:start() + 1)
  end

  return line_indent(bufnr, block:start() + 1) + shift
end

---Compute the indent for a 1-indexed line.
---@param bufnr number
---@param lnum number
---@return number
function M.indent(bufnr, lnum)
  if type(lnum) ~= 'number' or lnum < 1 then
    return -1
  end

  local shift = option_number(bufnr, 'shiftwidth')
  local prev = prev_text_line(bufnr, lnum)
  if prev == 0 then
    return 0
  end

  local prev_text = vim.api.nvim_buf_get_lines(bufnr, prev - 1, prev, false)[1] or ''
  local prev_indent = line_indent(bufnr, prev)
  local current = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ''

  if closes_block(current) then
    return tree_indent(bufnr, lnum - 1, shift) or math.max(prev_indent - shift, 0)
  end

  local tree = tree_indent(bufnr, lnum - 1, shift)
  if tree then
    return tree
  end

  if opens_block(prev_text) or continues_expr(prev_text) then
    return prev_indent + shift
  end
  return prev_indent
end

---`indentexpr` entry point.
---@return number
function M.expr()
  local ok, indent = pcall(M.indent, vim.api.nvim_get_current_buf(), vim.v.lnum)
  if not ok or type(indent) ~= 'number' then
    return -1
  end
  return indent
end

---Install buffer-local indentation for a Koka buffer.
---@param bufnr number
function M.setup(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local function set(name, value)
    pcall(vim.api.nvim_set_option_value, name, value, { buf = bufnr })
  end
  set('indentexpr', 'v:lua:require("koka.indent").expr()')
  set('indentkeys', '0{,0},0],:,0#,!^F,o,O,e')
  set('autoindent', true)
  set('smartindent', false)
  set('cindent', false)
  local ok, existing = pcall(vim.api.nvim_get_option_value, 'undo_ftplugin', { buf = bufnr })
  local undo = 'setlocal indentexpr< indentkeys< autoindent< smartindent< cindent<'
  if ok and type(existing) == 'string' and existing ~= '' then
    undo = existing .. ' | ' .. undo
  end
  pcall(vim.api.nvim_set_option_value, 'undo_ftplugin', undo, { buf = bufnr })
end

return M
