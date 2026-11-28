local helpers = require('tests.helpers')

---@diagnostic disable: duplicate-set-field

describe('koka.indent', function()
  local indent
  local treesitter

  before_each(function()
    helpers.reset_mocks()
    package.loaded['koka.indent'] = nil
    package.loaded['koka.treesitter'] = nil
    treesitter = require('koka.treesitter')
    indent = require('koka.indent')
  end)

  local function new_buf(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value('shiftwidth', 2, { buf = bufnr })
    return bufnr
  end

  ---Run `fn` with the TreeSitter parser reported as installed and a fake root.
  ---@param root table
  ---@param fn function
  local function with_fake_parser(root, fn)
    local was_installed = treesitter.is_parser_installed
    treesitter.is_parser_installed = function()
      return true
    end
    vim.treesitter = vim.treesitter or {}
    local was_get_parser = vim.treesitter.get_parser
    vim.treesitter.get_parser = function()
      return {
        parse = function()
          return { {
            root = function()
              return root
            end,
          } }
        end,
      }
    end
    local ok, err = pcall(fn)
    treesitter.is_parser_installed = was_installed
    vim.treesitter.get_parser = was_get_parser
    if not ok then
      error(err)
    end
  end

  ---A node that only answers what `enclosing` and `tree_indent` ask for.
  ---@param kind string
  ---@param start_row number 0-indexed
  ---@return table
  local function fake_node(kind, start_row)
    local node = { kind = kind, start_row = start_row }
    function node:type()
      return self.kind
    end
    function node:start()
      return self.start_row
    end
    function node.parent()
      return nil
    end
    function node:named_descendant_for_range()
      return self
    end
    return node
  end

  describe('setup', function()
    it('installs buffer-local indent options', function()
      local bufnr = new_buf { 'fun f()' }
      indent.setup(bufnr)

      assert.equals('v:lua:require("koka.indent").expr()', vim.api.nvim_get_option_value('indentexpr', { buf = bufnr }))
      assert.equals('0{,0},0],:,0#,!^F,o,O,e', vim.api.nvim_get_option_value('indentkeys', { buf = bufnr }))
      assert.is_true(vim.api.nvim_get_option_value('autoindent', { buf = bufnr }))
      assert.is_false(vim.api.nvim_get_option_value('smartindent', { buf = bufnr }))
      assert.is_false(vim.api.nvim_get_option_value('cindent', { buf = bufnr }))
    end)

    it('appends to an existing undo_ftplugin', function()
      local bufnr = new_buf { 'fun f()' }
      local supported = pcall(vim.api.nvim_set_option_value, 'undo_ftplugin', 'setlocal fo<', { buf = bufnr })
      if not supported then
        -- The test host does not expose the option; setup must still succeed.
        assert.has_no.errors(function()
          indent.setup(bufnr)
        end)
        return
      end

      indent.setup(bufnr)

      local undo = vim.api.nvim_get_option_value('undo_ftplugin', { buf = bufnr })
      assert.equals(1, undo:find('setlocal fo<', 1, true))
      assert.is_not_nil(undo:find('indentexpr<', 1, true))
    end)

    it('ignores an invalid buffer', function()
      assert.has_no.errors(function()
        indent.setup(-1)
      end)
    end)
  end)

  describe('indent without a parser', function()
    before_each(function()
      treesitter.is_parser_installed = function()
        return false
      end
    end)

    it('indents after an opening brace', function()
      local bufnr = new_buf { 'fun f() {', '  val x = 1' }
      assert.equals(2, indent.indent(bufnr, 2))
    end)

    it('indents after a trailing operator', function()
      local bufnr = new_buf { 'fun f()', '  match x', '    1 ->', '' }
      assert.equals(6, indent.indent(bufnr, 4))
    end)

    it('outdents a closing brace', function()
      local bufnr = new_buf { 'fun f() {', '  val x = 1', '}' }
      assert.equals(0, indent.indent(bufnr, 3))
    end)

    it('keeps the previous indent for a plain line', function()
      local bufnr = new_buf { 'fun f() {', '  val x = 1', '  val y = 2' }
      assert.equals(2, indent.indent(bufnr, 3))
    end)

    it('returns zero for the first line', function()
      local bufnr = new_buf { 'fun f() {' }
      assert.equals(0, indent.indent(bufnr, 1))
    end)

    it('honours shiftwidth', function()
      local bufnr = new_buf { 'fun f() {' }
      vim.api.nvim_set_option_value('shiftwidth', 4, { buf = bufnr })
      assert.equals(4, indent.indent(bufnr, 2))
    end)

    it('returns -1 for an out-of-range line', function()
      local bufnr = new_buf { 'fun f() {' }
      assert.equals(-1, indent.indent(bufnr, 0))
      assert.equals(-1, indent.indent(bufnr, 'x'))
    end)
  end)

  describe('indent with a parse tree', function()
    it('indents inside the enclosing block', function()
      -- The block starts on line 2 (indent 2), so the tree path yields 4 while
      -- the previous-line fallback would yield 2.
      local bufnr = new_buf { 'fun f() {', '  val x = 1', '  val y = 2' }
      with_fake_parser(fake_node('block', 1), function()
        assert.equals(4, indent.indent(bufnr, 3))
      end)
    end)

    it('lines a closing brace up with the block start', function()
      -- The block starts on line 1 (indent 0), so the tree path yields 0 while
      -- the fallback would outdent the previous line's indent of 4 to 2.
      local bufnr = new_buf { 'fun f() {', '    val x = 1', '}' }
      with_fake_parser(fake_node('block', 0), function()
        assert.equals(0, indent.indent(bufnr, 3))
      end)
    end)

    it('falls back when the node is not a block', function()
      local bufnr = new_buf { 'fun f() {', '  val x = 1' }
      with_fake_parser(fake_node('atom', 0), function()
        assert.equals(2, indent.indent(bufnr, 2))
      end)
    end)
  end)
end)
