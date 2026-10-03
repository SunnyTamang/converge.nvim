---Slices: named parts of a color scheme. Every highlight group belongs to exactly one.
local M = {}

---All slice names, in picker display order.
M.names = { "ui", "syntax", "diagnostics", "git", "terminal", "plugins" }

local function set(list)
  local out = {}
  for _, item in ipairs(list) do
    out[item] = true
  end
  return out
end

local SLICE_NAMES = set(M.names)

-- Built-in syntax groups, see `:h group-name`.
local SYNTAX = set({
  "Comment",
  "Constant",
  "String",
  "Character",
  "Number",
  "Boolean",
  "Float",
  "Identifier",
  "Function",
  "Statement",
  "Conditional",
  "Repeat",
  "Label",
  "Operator",
  "Keyword",
  "Exception",
  "PreProc",
  "Include",
  "Define",
  "Macro",
  "PreCondit",
  "Type",
  "StorageClass",
  "Structure",
  "Typedef",
  "Special",
  "SpecialChar",
  "Tag",
  "Delimiter",
  "SpecialComment",
  "Debug",
  "Underlined",
  "Ignore",
  "Error",
  "Todo",
})

-- Built-in editor groups, see `:h highlight-groups`, plus LSP UI groups.
local UI = set({
  "ColorColumn",
  "Conceal",
  "CurSearch",
  "Cursor",
  "lCursor",
  "CursorIM",
  "CursorColumn",
  "CursorLine",
  "Directory",
  "EndOfBuffer",
  "TermCursor",
  "TermCursorNC",
  "ErrorMsg",
  "WinSeparator",
  "VertSplit",
  "Folded",
  "FoldColumn",
  "SignColumn",
  "IncSearch",
  "Substitute",
  "LineNr",
  "LineNrAbove",
  "LineNrBelow",
  "CursorLineNr",
  "CursorLineFold",
  "CursorLineSign",
  "MatchParen",
  "ModeMsg",
  "MsgArea",
  "MsgSeparator",
  "MoreMsg",
  "NonText",
  "Normal",
  "NormalFloat",
  "FloatBorder",
  "FloatTitle",
  "FloatFooter",
  "NormalNC",
  "Pmenu",
  "PmenuSel",
  "PmenuKind",
  "PmenuKindSel",
  "PmenuExtra",
  "PmenuExtraSel",
  "PmenuSbar",
  "PmenuThumb",
  "PmenuMatch",
  "PmenuMatchSel",
  "ComplMatchIns",
  "Question",
  "QuickFixLine",
  "Search",
  "SnippetTabstop",
  "SpecialKey",
  "SpellBad",
  "SpellCap",
  "SpellLocal",
  "SpellRare",
  "StatusLine",
  "StatusLineNC",
  "StatusLineTerm",
  "StatusLineTermNC",
  "TabLine",
  "TabLineFill",
  "TabLineSel",
  "Title",
  "Visual",
  "VisualNOS",
  "WarningMsg",
  "Whitespace",
  "WildMenu",
  "WinBar",
  "WinBarNC",
  "Menu",
  "Scrollbar",
  "Tooltip",
  "LspReferenceText",
  "LspReferenceRead",
  "LspReferenceWrite",
  "LspReferenceTarget",
  "LspInlayHint",
  "LspCodeLens",
  "LspCodeLensSeparator",
  "LspSignatureActiveParameter",
})

local function starts(name, prefix)
  return name:sub(1, #prefix) == prefix
end

---@param name string
---@return boolean
function M.is_slice(name)
  return SLICE_NAMES[name] == true
end

---Which slice owns highlight group `group`. The first matching rule wins.
---Never returns "terminal": terminal colors are values, not highlight groups.
---@param group string
---@return string
function M.slice_of(group)
  if
    starts(group, "Diagnostic")
    or starts(group, "LspDiagnostics")
    or group == "@lsp.mod.deprecated"
  then
    return "diagnostics"
  end
  if
    starts(group, "GitSigns")
    or starts(group, "Diff")
    or starts(group, "diff")
    or group == "Added"
    or group == "Changed"
    or group == "Removed"
  then
    return "git"
  end
  if SYNTAX[group] or starts(group, "@") then
    return "syntax"
  end
  if UI[group] then
    return "ui"
  end
  return "plugins"
end

return M
