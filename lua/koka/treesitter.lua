---@mod koka.treesitter
---@brief [[
---TreeSitter utilities for Koka
---@brief ]]

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
  local ok = pcall(vim.treesitter.language.add, 'koka')
  return ok
end

---Install Koka TreeSitter parser
---@return boolean success
function M.install_parser()
  if not M.is_available() then
    vim.notify('[koka.nvim] nvim-treesitter is required for TreeSitter support', vim.log.levels.ERROR)
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
    -- Fallback to regex
    return M._find_runnables_fallback(bufnr)
  end

  local tree = parser:parse()[1]
  if not tree then
    return M._find_runnables_fallback(bufnr)
  end

  local root = tree:root()
  local query = vim.treesitter.query.parse(
    'koka',
    [[
      (fundecl
        (identifier) @func.name
        (#match? @func.name "^(main|test.*|example.*)$")
      ) @func
    ]]
  )

  local runnables = {}
  for id, node in query:iter_captures(root, bufnr, 0, -1) do
    local name_node = query.captures[id]
    if name_node and vim.treesitter.get_node_text(name_node, bufnr) then
      local func_name = vim.treesitter.get_node_text(name_node, bufnr)
      local start_row, start_col = node:range()

      local func_type = 'run'
      if func_name:match('^test') then
        func_type = 'test'
      elseif func_name:match('^example') then
        func_type = 'example'
      end

      table.insert(runnables, {
        line = start_row,
        col = start_col,
        name = func_name,
        type = func_type,
      })
    end
  end

  if #runnables > 0 then
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
      or line:match('^%s*pub%s*fun%s+([%w%-]+)%s*%(')
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
        local col = line:find(func_name) or 1
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

return M
