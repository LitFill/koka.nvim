describe('koka.lsp', function()
  local lsp = require('koka.lsp')

  describe('start', function()
    it('should start LSP client with correct config', function()
      local started_config = nil

      vim.lsp.start = function(config, _)
        started_config = config
        return 1
      end

      vim.lsp.get_clients = function(_)
        return {}
      end

      package.loaded['koka.project'] = {
        get_resolved_config = function(_, callback)
          callback {
            target = 'c',
            cwd = '/test/project',
            include_dirs = { 'lib' },
            compiler_args = { '--opt' },
          }
        end,
      }

      lsp.start(0)

      assert.is_not_nil(started_config)
      assert.equal('koka', started_config.name)
      assert.same({ 'koka' }, started_config.filetypes)
      assert.equal('/test/project', started_config.root_dir)
      assert.is_not_nil(started_config.cmd and table.concat(started_config.cmd, ' '):match('koka'))
      assert.is_not_nil(started_config.cmd and table.concat(started_config.cmd, ' '):match('--language-server'))
    end)
  end)

  describe('stop', function()
    it('should stop active clients for buffer', function()
      local stopped_clients = {}

      vim.lsp.get_clients = function(opts)
        if opts and opts.name == 'koka' and opts.bufnr == 0 then
          return {
            {
              id = 1,
              stop = function(self)
                table.insert(stopped_clients, self.id)
              end,
            },
            {
              id = 2,
              stop = function(self)
                table.insert(stopped_clients, self.id)
              end,
            },
          }
        end
        return {}
      end

      lsp.stop(0)

      assert.same({ 1, 2 }, stopped_clients)
    end)
  end)

  describe('restart', function()
    it('should stop then start client', function()
      local stopped = false
      local started = false

      vim.lsp.get_clients = function(_)
        if not stopped then
          return {
            {
              id = 1,
              stop = function()
                stopped = true
              end,
            },
          }
        end
        return {}
      end

      vim.lsp.start = function(_, _)
        started = true
        return 1
      end

      package.loaded['koka.project'] = {
        get_resolved_config = function(_, callback)
          callback {
            target = 'c',
            cwd = '/test/project',
          }
        end,
      }

      lsp.restart(0)

      assert.is_true(stopped)

      vim.wait(150, function()
        return started
      end)

      assert.is_true(started)
    end)
  end)
end)
