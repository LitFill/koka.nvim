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
    it('finds a call with literal arguments', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = {
        'fun add(a: int, b: int): total int { a + b }',
        'fun twice(x: int): int { x * 2 }',
        'fun main() {',
        '  val x = 10',
        '  val a = add(1, 2)',
        '  val b = twice(x)',
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
    it('finds a call with an operator argument', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = {
        'fun add(a: int, b: int): total int { a + b }',
        'fun main() {',
        '  val x = add(1 + 2, 3)',
        '}',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local calls = treesitter.find_total_calls(bufnr)

      local found = false
      for _, call in ipairs(calls) do
        if call.func_name == 'add' and call.args_text == '1 + 2, 3' then
          found = true
        end
      end
      assert.is_true(found)
    end)
    it('finds a static val expression', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = {
        'fun main() {',
        '  val a = 33 + 34',
        '}',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local calls = treesitter.find_total_calls(bufnr)

      local found = false
      for _, call in ipairs(calls) do
        if call.expr == '33 + 34' and call.func_name == 'a' then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('skips a literal val binding', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = {
        'fun main() {',
        '  val x = 10',
        '}',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local calls = treesitter.find_total_calls(bufnr)
      assert.equal(0, #calls)
    end)

    it('finds a zero-argument call', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = {
        'fun example() { 33 + 34 }',
        'fun main() {',
        '  val y = example()',
        '}',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local calls = treesitter.find_total_calls(bufnr)

      local found = false
      for _, call in ipairs(calls) do
        if call.func_name == 'example' and call.args_text == '' then
          found = true
        end
      end
      assert.is_true(found)
    end)

    it('evaluates the outer nested call only', function()
      local bufnr = vim.api.nvim_create_buf(false, true)
      local lines = {
        'fun add(a: int, b: int): total int { a + b }',
        'fun main() {',
        '  val x = add(add(11, 22), add(33, 1))',
        '}',
      }
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

      local calls = treesitter.find_total_calls(bufnr)

      assert.equal(1, #calls)
      assert.equal('add', calls[1].func_name)
      assert.equal('add(11, 22), add(33, 1)', calls[1].args_text)
    end)

    it('returns an empty list when there are no static calls', function()
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

describe('koka.debugger eval_total', function()
  local saved = {}

  local function mock_fn(name, fn)
    saved[name] = vim.fn[name]
    vim.fn[name] = fn
  end

  after_each(function()
    for name, val in pairs(saved) do
      vim.fn[name] = val
    end
    saved = {}
    package.loaded['koka.debugger'] = nil
  end)

  it('uses a unique entry and returns the last stdout line', function()
    local captured_cmd
    local captured_wrapper
    mock_fn('tempname', function()
      return '/tmp/koka_inlay_spec'
    end)
    mock_fn('mkdir', function()
      return 0
    end)
    mock_fn('writefile', function(lines)
      captured_wrapper = table.concat(lines, '\n')
    end)
    mock_fn('jobstop', function() end)
    mock_fn('delete', function() end)
    mock_fn('jobstart', function(cmd, opts)
      captured_cmd = cmd
      opts.on_stdout(1, { 'load    : std/core', 'parse   : main.kk', 'check   : main', '3' })
      opts.on_exit(1, 0)
      return 1
    end)

    package.loaded['koka.debugger'] = nil
    local debugger = require('koka.debugger')

    local got
    debugger.eval_total(
      { target = 'c', cwd = '/tmp' },
      '/tmp/main.kk',
      { 'fun add(a: int, b: int): total int { a + b }', 'fun main() { println("hi") }' },
      'add',
      '1, 2',
      function(result)
        got = result
      end
    )

    assert.equal('3', got)
    assert.is_not_nil(table.concat(captured_cmd, ' '):find('--main-entry=kokaInlayEntry', 1, true))
    assert.is_not_nil(captured_wrapper:match('fun kokaInlayEntry%(%)'))
  end)
end)

describe('koka.debugger _parse_sigs', function()
  it('splits total definitions and effectful ones', function()
    package.loaded['koka.debugger'] = nil
    local debugger = require('koka.debugger')
    local out = {
      'sig/add  : (a : int, b : int) -> int',
      'sig/main : () -> console/console ()',
      'sig/maybe: (x : int) -> exn int',
      'sig/show : (s : string) -> pure string',
      'sig/multi: () -> <console/console,exn> int',
    }
    local total, effects = debugger._parse_sigs(out)
    assert.is_true(total.add)
    assert.is_nil(total.main)
    assert.is_nil(total.maybe)
    assert.is_nil(total.show)
    assert.is_nil(total.multi)
    assert.equal('console/console ()', effects.main)
    assert.equal('exn int', effects.maybe)
    assert.equal('pure string', effects.show)
    assert.equal('<console/console,exn> int', effects.multi)
    assert.is_nil(effects.add)
  end)
end)
