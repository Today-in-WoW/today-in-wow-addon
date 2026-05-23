std = "lua51"
max_line_length = false

-- WoW addon files are called with (addonName, ns) varargs and read the bit lib.
globals = { "bit" }

exclude_files = {
	"tools/",      -- dev tooling, not shipped
	"contract/",
}

ignore = {
	"212",  -- unused argument (the addonName vararg `_`)
	"213",  -- unused loop variable
}

-- test files use busted's describe/it/assert globals
files["tests/**/*.lua"] = { std = "lua51+busted" }
