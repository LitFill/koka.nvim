---@mod koka.inlay
---@brief [[
---Inlay hints that show the result of total functions at call sites.
---@brief ]]

local config = require('koka.config.internal')
local treesitter = require('koka.treesitter')
local debugger = require('koka.debugger')
local project = require('koka.project')
local koka_ui = require('koka.ui')

local M = {}

local ns = vim.api.nvim_create_namespace('koka_inlay')

-- Per-buffer state: gen (token), cache (key -> text), timer.
local state = {}

local function ensure_state(bufnr)
  local s = state[bufnr]
  if not s then
    s = { gen = 0, cache = {}, tick = 0 }
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
  koka_ui.virt_text(bufnr, ns, call.line, call.col, ' = ' .. text, 'KokaInlayHint')
end

---Draw one hint that shows the effect row. No run.
---@param bufnr number
---@param call table A call from find_total_calls
---@param effect string The effect row
function M.render_effect(bufnr, call, effect)
  koka_ui.virt_text(bufnr, ns, call.line, call.col, ' : ' .. effect, 'KokaInlayHint')
end

---Find static calls and show a hint for each result.
---Manual runs report progress. Automatic runs stay quiet.
---@param bufnr? number
---@param manual? boolean
function M.refresh(bufnr, manual)
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

  local function is_total_call(call, effects)
    if call.expr then
      return true
    end
    -- Unknown functions may be imported total functions. Run them.
    return not (effects and effects[call.func_name])
  end

  local function run_total(_total, effects)
    local to_eval = {}
    local shown = 0
    for _, call in ipairs(calls) do
      if shown >= max then
        break
      end
      shown = shown + 1
      local cached = s.cache[call.key]
      if cached then
        M.render_one(bufnr, call, cached)
      elseif is_total_call(call, effects) then
        to_eval[#to_eval + 1] = call
      elseif effects and effects[call.func_name] then
        M.render_effect(bufnr, call, effects[call.func_name])
      end
    end
    local skipped = #calls - shown
    if skipped > 0 and manual then
      koka_ui.notify(string.format('showing %d of %d calls (limit %d)', shown, #calls, max), vim.log.levels.WARN)
    end

    local pending = #to_eval
    if manual then
      if pending == 0 then
        koka_ui.notify('inlay hints up to date', vim.log.levels.INFO)
      else
        koka_ui.notify(string.format('evaluating %d call(s)...', pending), vim.log.levels.INFO)
      end
    end
    if pending == 0 then
      return
    end

    debugger.eval_calls(proj, path, lines, to_eval, function(results, _total2, _effects2, err)
      if gen == s.gen and results then
        for _, call in ipairs(to_eval) do
          local text = results[call.key]
          if text then
            s.cache[call.key] = text
            M.render_one(bufnr, call, text)
          end
        end
      end
      if err and manual then
        koka_ui.notify(err, vim.log.levels.ERROR)
      end
      if manual then
        koka_ui.notify('inlay hints updated', vim.log.levels.INFO)
      end
    end, 20000)
  end

  if s.sigs then
    run_total(s.sigs.total, s.sigs.effects)
    return
  end
  if manual then
    koka_ui.notify('first run may take longer than later ones, please wait', vim.log.levels.INFO)
  end

  -- Phase 1: get signatures. The wrapper has no calls, so nothing runs.
  debugger.eval_calls(proj, path, lines, {}, function(_results, total, effects, err)
    if gen ~= s.gen then
      return
    end
    if err then
      if manual then
        koka_ui.notify(err, vim.log.levels.ERROR)
      end
      return
    end
    s.sigs = { total = total, effects = effects }
    run_total(total, effects)
  end, 20000)
end

---Clear the cache for a buffer and refresh it with progress.
---@param bufnr? number
function M.invalidate(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local s = state[bufnr]
  if s then
    s.cache = {}
    s.sigs = nil
  end
  M.refresh(bufnr, true)
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
    M.refresh(bufnr, true)
    koka_ui.notify('inlay hints enabled', vim.log.levels.INFO)
  else
    -- Bump the generation and stop the timer. An in-flight callback is dropped.
    local s = state[bufnr]
    if s then
      s.gen = s.gen + 1
      if s.timer then
        pcall(function()
          s.timer:stop()
          s.timer:close()
        end)
        s.timer = nil
      end
    end
    M.clear(bufnr)
    koka_ui.notify('inlay hints disabled', vim.log.levels.INFO)
  end
end

---Set the highlight group, the autocommands, and the buffer cleanup.
function M.setup()
  vim.api.nvim_set_hl(0, 'KokaInlayHint', { link = 'Comment', default = true })

  local group = vim.api.nvim_create_augroup('koka_inlay', { clear = true })

  vim.api.nvim_create_autocmd('LspAttach', {
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
