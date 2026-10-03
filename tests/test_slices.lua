local slices = require("converge.slices")
local eq = MiniTest.expect.equality

local T = MiniTest.new_set()

T["names are in display order"] = function()
  eq(slices.names, { "ui", "syntax", "diagnostics", "git", "terminal", "plugins" })
end

T["is_slice()"] = function()
  eq(slices.is_slice("terminal"), true)
  eq(slices.is_slice("colors"), false)
end

T["slice_of()"] = MiniTest.new_set({
  parametrize = {
    { "Comment", "syntax" },
    { "@string", "syntax" },
    { "@lsp.type.function", "syntax" },
    { "@diff.plus", "syntax" },
    { "@lsp.mod.deprecated", "diagnostics" },
    { "DiagnosticError", "diagnostics" },
    { "LspDiagnosticsError", "diagnostics" },
    { "DiffAdd", "git" },
    { "diffAdded", "git" },
    { "GitSignsAdd", "git" },
    { "Added", "git" },
    { "Normal", "ui" },
    { "StatusLine", "ui" },
    { "CursorLineNr", "ui" },
    { "LspReferenceText", "ui" },
    { "TelescopeNormal", "plugins" },
    { "WhichKey", "plugins" },
  },
})

T["slice_of()"]["maps group to slice"] = function(group, slice)
  eq(slices.slice_of(group), slice)
end

return T
