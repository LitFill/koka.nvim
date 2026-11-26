local helpers = require('tests.helpers')

describe('koka.koka_cmd', function()
  local koka_cmd

  before_each(function()
    helpers.reset_mocks()
    koka_cmd = require('koka.koka_cmd')
  end)

  describe('build', function()
    it('orders the argv as koka, flags, mode, file, main-entry', function()
      local config = {
        target = 'jsnode',
        include_dirs = { 'inc1', 'inc2' },
        compiler_args = { '--O2' },
      }
      local cmd = koka_cmd.build(config, {
        mode = '-e',
        file = 'main.kk',
        main_entry = 'foo',
        buildtag = 'nvim',
        showtypesigs = true,
      })
      assert.same({
        'koka',
        '--buildtag=nvim',
        '--target=jsnode',
        '--include=inc1',
        '--include=inc2',
        '--O2',
        '--showtypesigs',
        '-e',
        'main.kk',
        '--main-entry=foo',
      }, cmd)
    end)

    it('omits the target flag when target is c', function()
      local cmd = koka_cmd.build({ target = 'c' }, { mode = '-e', file = 'main.kk' })
      assert.same({ 'koka', '-e', 'main.kk' }, cmd)
    end)

    it('omits main-entry when main_entry is nil', function()
      local cmd = koka_cmd.build({}, { mode = '-e', file = 'main.kk' })
      assert.same({ 'koka', '-e', 'main.kk' }, cmd)
    end)
  end)
end)
