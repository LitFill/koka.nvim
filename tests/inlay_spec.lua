local helpers = require('tests.helpers')

---@diagnostic disable: duplicate-set-field

describe('koka.treesitter inlay helpers', function()
  local treesitter

  before_each(function()
    helpers.reset_mocks()
    package.loaded['koka.treesitter'] = nil
    treesitter = require('koka.treesitter')
  end)

  describe('is_literal_arg', function()
    it('accepts integer literals', function()
      assert.is_true(treesitter.is_literal_arg('1'))
      assert.is_true(treesitter.is_literal_arg('-5'))
      assert.is_true(treesitter.is_literal_arg('0xFF'))
      assert.is_true(treesitter.is_literal_arg('1_000'))
    end)

    it('accepts float literals', function()
      assert.is_true(treesitter.is_literal_arg('3.14'))
      assert.is_true(treesitter.is_literal_arg('-0.5'))
      assert.is_true(treesitter.is_literal_arg('1e10'))
    end)

    it('accepts string and char literals', function()
      assert.is_true(treesitter.is_literal_arg('"hello"'))
      assert.is_true(treesitter.is_literal_arg("'c'"))
    end)

    it('accepts a literal wrapped in parentheses', function()
      assert.is_true(treesitter.is_literal_arg('(1)'))
      assert.is_true(treesitter.is_literal_arg('((2))'))
    end)

    it('rejects non-literal text', function()
      assert.is_false(treesitter.is_literal_arg('x'))
      assert.is_false(treesitter.is_literal_arg('a + 1'))
      assert.is_false(treesitter.is_literal_arg('foo(1)'))
      assert.is_false(treesitter.is_literal_arg(''))
      assert.is_false(treesitter.is_literal_arg(nil))
    end)
  end)

  describe('find_total_calls', function()
    it('finds calls whose arguments are all literals', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = {
        'fun add(a: int, b: int): total int { a + b }',
        'fun twice(x: int): int { x * 2 }',
        'fun main() {',
        '  val x = 10',
        '  println(add(1, 2))',
        '  println(twice(x))',
        '}',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local calls = treesitter.find_total_calls(bufnr)

      local found_add = false
      local found_twice = false
      for _, call in ipairs(calls) do
        if call.func_name == 'add' and call.args_text == '1, 2' then
          found_add = true
        end
        if call.func_name == 'twice' then
          found_twice = true
        end
      end
      assert.is_true(found_add)
      assert.is_false(found_twice)
    end)

    it('returns an empty list when there are no literal calls', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = {
        'fun main() {',
        '  val x = 10',
        '  println(x)',
        '}',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local calls = treesitter.find_total_calls(bufnr)
      assert.equal(0, #calls)
    end)
  end)
end)
