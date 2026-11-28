local helpers = require('tests.helpers')

describe('koka.ui', function()
  local ui

  before_each(function()
    helpers.reset_mocks()
    ui = require('koka.ui')
  end)

  describe('virt_text', function()
    it('does nothing when the buffer is invalid', function()
      local set_extmark_called = false
      vim.api.nvim_buf_is_valid = function(_)
        return false
      end
      vim.api.nvim_buf_set_extmark = function()
        set_extmark_called = true
        return 1
      end
      ui.virt_text(1, 0, 0, 0, 'text', 'Comment')
      assert.is_false(set_extmark_called)
    end)

    it('draws the extmark when the buffer is valid', function()
      local captured
      vim.api.nvim_buf_is_valid = function(_)
        return true
      end
      vim.api.nvim_buf_set_extmark = function(_, _, line, col, opts)
        captured = { line = line, col = col, opts = opts }
        return 1
      end
      ui.virt_text(2, 5, 3, 7, 'hi', 'Comment')
      assert.same({ line = 3, col = 7 }, { line = captured.line, col = captured.col })
      assert.same({ { 'hi', 'Comment' } }, captured.opts.virt_text)
      assert.same('inline', captured.opts.virt_text_pos)
      assert.is_false(captured.opts.strict)
    end)
  end)
end)
