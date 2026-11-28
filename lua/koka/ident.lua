---@mod koka.ident
---@brief [[
---Shared Koka identifier patterns.
---
---Koka identifiers may contain `-` (`my-func`), `_` and a trailing `'`
---(`w0'`), and a parameter may be prefixed with `?` (implicit) or `^`
---(late-bound). Patterns that stop at `[A-Za-z0-9_]` split `my-x` into `my`
---and `-x`, which silently corrupts generated signatures and stubs.
---@brief ]]

local M = {}

---Identifier body without a `?`/`^` prefix.
M.PLAIN = "[%w_%-%']+"

---Identifier body without a `?`/`^` prefix, captured.
M.PLAIN_CAPTURE = "([%w_%-%']+)"

---Anchored identifier, optionally prefixed with `?` or `^`.
M.NAME = "^[%?%^]?[%w_%-%']+"

---Anchored identifier with the `?`/`^` prefix kept outside the capture.
M.NAME_CAPTURE = '^[%?%^]?(' .. M.PLAIN .. ')'

---Like `NAME_CAPTURE`, but for patterns that anchor with `^%s*` themselves.
M.NAME_CAPTURE_LOOSE = '[%?%^]?(' .. M.PLAIN .. ')'

return M
