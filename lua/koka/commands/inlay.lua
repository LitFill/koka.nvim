---@mod koka.inlay
---@brief [[
---Inlay hints that show the result of total functions at call sites.
---@brief ]]

local config = require('koka.config.internal')
local treesitter = require('koka.treesitter')
local debugger = require('koka.debugger')
local project = require('koka.project')

local M = {}

local ns = vim.api.nvim_create_namespace('koka_inlay')

-- Per-buffer state: gen (token), cache (key -> text), timer.
local state = {}

local function ensure_state(bufnr)
  local s = state[bufnr]
  if not s then
    s = { gen = 0, cache = {} }
    state[bufnr] = s
  end
  return s
end

---Remove all inlay hints in a buffer.
---@param bufnr number
function M.clear(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

---Draw one hint with the evaluated text after the call.
---@param bufnr number
---@param call table A call from find_total_calls
---@param text string The evaluated result
function M.render_one(bufnr, call, text)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, call.line, call.col, {
    virt_text = { { ' = ' .. text, 'KokaInlayHint' } },
    virt_text_pos = 'eol',
  })
end

---Run one call and draw its hint. Skip when the result is already cached.
---@param bufnr number
---@param s table The buffer state
---@param call table The call
---@param proj koka.project.Config The project config
---@param lines string[] The buffer lines
---@param path string The buffer path
---@param gen number The current generation token
local function eval_and_render(bufnr, s, call, proj, lines, path, gen)
  local cached = s.cache[call.key]
  if cached then
    M.render_one(bufnr, call, cached)
    return
  end
  debugger.eval_total(proj, path, lines, call.func_name, call.args_text, function(text)
    if gen ~= s.gen then
      return
    end
    if text then
      s.cache[call.key] = text
      M.render_one(bufnr, call, text)
    end
  end, 3000)
end

---Find literal calls and show a hint for each result.
---@param bufnr? number
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not config.inlay.enabled then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local s = ensure_state(bufnr)
  s.gen = s.gen + 1
  local gen = s.gen
  M.clear(bufnr)

  local path = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local proj = project.get_resolved_config(path)
  local calls = treesitter.find_total_calls(bufnr)
  local max = config.inlay.max_results

  local shown = 0
  for _, call in ipairs(calls) do
    if shown >= max then
      break
    end
    shown = shown + 1
    eval_and_render(bufnr, s, call, proj, lines, path, gen)
  end
end

---Schedule a debounced refresh for a buffer.
---@param bufnr number
function M.schedule_refresh(bufnr)
  local s = ensure_state(bufnr)
  if s.timer then
    pcall(function()
      s.timer:stop()
      s.timer:close()
    end)
    s.timer = nil
  end
  local delay = config.inlay.debounce_ms
  local run = function()
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(bufnr) then
        pcall(M.refresh, bufnr)
      end
    end)
  end
  if vim.uv and vim.uv.new_timer then
    local t = vim.uv.new_timer()
    s.timer = t
    t:start(delay, 0, run)
  else
    vim.defer_fn(run, delay)
  end
end

---Turn the feature on or off and refresh the current buffer.
function M.toggle()
  config.inlay.enabled = not config.inlay.enabled
  local bufnr = vim.api.nvim_get_current_buf()
  if config.inlay.enabled then
    M.refresh(bufnr)
    vim.notify('koka.nvim: inlay hints enabled', vim.log.levels.INFO)
  else
    M.clear(bufnr)
    vim.notify('koka.nvim: inlay hints disabled', vim.log.levels.INFO)
  end
end

---Set the highlight group, the autocommands, and the buffer cleanup.
function M.setup()
  vim.api.nvim_set_hl(0, 'KokaInlayHint', { link = 'Comment', default = true })

  local group = vim.api.nvim_create_augroup('koka_inlay', { clear = true })

  vim.api.nvim_create_autocmd({ 'LspAttach', 'BufWritePost', 'InsertLeave', 'CursorHold' }, {
    group = group,
    pattern = '*.kk',
    callback = function(args)
      if not config.inlay.enabled then
        return
      end
      M.schedule_refresh(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd('BufDelete', {
    group = group,
    pattern = '*.kk',
    callback = function(args)
      local s = state[args.buf]
      if s and s.timer then
        pcall(function()
          s.timer:stop()
          s.timer:close()
        end)
      end
      state[args.buf] = nil
    end,
  })
end

return M
