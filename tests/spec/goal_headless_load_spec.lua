-- goal_headless_load_spec.lua  ·  the .toc load guard
--
-- No spec loads a ui_* module — ui_main, ui_panel, ui_options, ui_matrix and
-- ui_sync are covered by luacheck alone. luacheck parses; it does not EXECUTE.
-- So a load-time fault in one of them (a call to a missing global, indexing a
-- module the .toc orders later) surfaced only in-game, never in CI.
--
-- This walks every goals/ file the .toc ships, in .toc order, into one shared ns
-- under the standard mock — the same environment the client provides — and
-- asserts none of them raises. It is a smoke test, not a behaviour test: the
-- assertion is "loading did not fail", nothing more.
--
-- NB the environment is wow_mock, not a bare interpreter. goals/store.lua calls
-- CreateFrame at file scope for its ADDON_LOADED binding, so the goals layer is
-- not API-free by design — it is game-safe, which is what this pins.
--
-- SCOPE: load time only. Firing PLAYER_LOGIN here would exercise the ui_* boot
-- bodies too, but that needs a far richer mock than wow_mock offers (substrate
-- alone wants UnitName), and the mock is deliberately small by design
-- (test-suite-brief §7). Those bodies stay untested glue; this guards the file
-- from never being executed at all.
--
-- Run from the repo root: busted

local function tocGoalFiles()
	local files, fh = {}, assert(io.open("TodayInWoW.toc", "r"))
	for line in fh:lines() do
		local path = line:match("^%s*(goals\\[%w_]+%.lua)%s*$")
			or line:match("^%s*(goals/[%w_]+%.lua)%s*$")
		if path then files[#files + 1] = (path:gsub("\\", "/")) end
	end
	fh:close()
	return files
end

describe("goals modules load cleanly in .toc order", function()
	after_each(function() _G.TiWDB = nil; _G.TiWCompanionDB = nil end)

	it("finds the goals files listed in the .toc", function()
		assert.is_true(#tocGoalFiles() > 10, "expected the .toc to list the goals modules")
	end)

	it("loads every goals/ module without raising", function()
		local mock = dofile("tests/wow_mock.lua")
		mock.install()
		_G.TiWDB = nil

		local ns = {}
		for _, path in ipairs(tocGoalFiles()) do
			local chunk, err = loadfile(path)
			assert(chunk, path .. " failed to parse: " .. tostring(err))
			local ok, rerr = pcall(chunk, "TiW", ns)
			assert(ok, path .. " raised while loading: " .. tostring(rerr))
		end
	end)

end)
