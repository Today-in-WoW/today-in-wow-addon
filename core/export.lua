local _, ns = ...
ns = ns or {}

-- ===========================================================================
-- core/export.lua  ·  copy-paste export (data_storage §6/§8)
--
-- For users WITHOUT the companion: `/tiw export` produces a single string they
-- paste on the site, carrying the SAME payload the companion would ship (§8) —
-- the account checkpoint + every character's session bundles. The string is the
-- WeakAuras-style pipeline (§8 encoding table):
--
--   AceSerializer:Serialize(payload)  →  LibDeflate:CompressDeflate
--                                     →  LibDeflate:EncodeForPrint  →  "!TIW:1!"..body
--
-- The site/companion implement the matching DECODE (their language); decode() here
-- exists so the round-trip is verifiable in-Lua (tests) and is harmless in-game.
--
-- Bundles ship INTACT, with their per-category/per-event chain hashes. Stripping the
-- derivable hashes was tried — but deflate already compresses the hex digests (a
-- 16-symbol alphabet), so the win was modest, not worth making the backend
-- reconstruct the chain from genesis just to verify. Keeping the hashes lets the site
-- check each row/category on its own (parse-and-check) and reject per-category (§9).
-- Only addon-internal per-character state (daily-dedup) is dropped — not site data.
--
-- Pruning is decoupled from generating the string: a copy-paste isn't proof of
-- delivery (the user may never submit it), so we never drop data just because an
-- export string was made. markExported() — driven by an explicit "I've imported
-- this" confirmation in the popup / `/tiw export clear` — records the delivered
-- session_ids into TiWDB.exported_sessions, which Drain.run then drains next login
-- exactly like the companion's shipped_sessions (§6). Because the export is always
-- "everything", anything not yet cleared is simply re-included in the next string,
-- so there is never a window where un-cleared data is unrecoverable.
-- ===========================================================================

local Export = {}
ns.Export = Export

local FORMAT = 1                         -- export envelope version (the "1" in !TIW:1!)
local PREFIX = "!TIW:" .. FORMAT .. "!"

-- Resolve the embedded libs via LibStub (set up by the .toc load order). Held in
-- locals so a missing lib degrades to a clear error instead of a nil index.
local function libs()
	local LibStub = _G.LibStub
	if not LibStub then return nil end
	return LibStub("AceSerializer-3.0", true), LibStub("LibDeflate", true)
end

-- payload table -> branded, compressed, print-safe string (nil, err on lib miss).
-- No explicit level: LibDeflate defaults to 3 for large input. Level 9 is "VERY
-- SLOW" (max_chain 4096 vs 32) for ~1-3% gain on our hash-heavy data — most of the
-- bytes are high-entropy FNV digests that don't compress — so the default is the
-- right speed/size trade and keeps the export from freezing the client.
function Export.encode(payload)
	local AceSerializer, LibDeflate = libs()
	if not (AceSerializer and LibDeflate) then return nil, "export libs unavailable" end
	local serialized = AceSerializer:Serialize(payload)
	local compressed = LibDeflate:CompressDeflate(serialized)
	return PREFIX .. LibDeflate:EncodeForPrint(compressed)
end

-- string -> payload table (nil, err on any framing/decode/decompress/deserialize
-- failure). The inverse of encode; the authoritative decoder is the site's.
function Export.decode(str)
	if type(str) ~= "string" then return nil, "not a string" end
	local ver, body = str:match("^!TIW:(%d+)!(.+)$")
	if not ver then return nil, "bad prefix" end
	if tonumber(ver) ~= FORMAT then return nil, "unsupported export version " .. ver end

	local AceSerializer, LibDeflate = libs()
	if not (AceSerializer and LibDeflate) then return nil, "export libs unavailable" end

	local compressed = LibDeflate:DecodeForPrint(body)
	if not compressed then return nil, "decode failed" end
	local serialized = LibDeflate:DecompressDeflate(compressed)
	if not serialized then return nil, "decompress failed" end
	local ok, payload = AceSerializer:Deserialize(serialized)
	if not ok then return nil, "deserialize failed" end
	return payload
end

-- Assemble the export payload from the SavedVariables: the account checkpoint and
-- every character's session bundles — "everything" (§8). Bundles ship intact (chain
-- hashes included, see header) so the backend verifies per-row without recomputing
-- the chain. Only char_guid + the bundles are the site's data, so addon-internal
-- per-character state (daily-dedup, §3.2/§3.10) is dropped. `v` is the data schema;
-- transient SV fields (trace, …) are excluded. We reference the live bundles (never
-- mutate them — the running session still needs them); serialize only reads.
function Export.buildPayload()
	local db = TiWDB or {}
	local characters = {}
	for key, rec in pairs(db.characters or {}) do
		characters[key] = { char_guid = rec.char_guid, sessions = rec.sessions or {} }
	end
	return {
		v          = ns.SCHEMA_VERSION,
		account    = db.account or {},
		characters = characters,
	}
end

-- Convenience: the export string for the whole SV (nil, err on lib miss).
function Export.string()
	return Export.encode(Export.buildPayload())
end

-- Async variant for the UI. LibDeflate's compress is one monolithic call with no
-- yield hook, so the compress itself can't be sliced — but running the pipeline on
-- the coroutine runner (§4c) and yielding between stages puts serialize / compress
-- / encode each on its own frame instead of one mega-hitch, and lets the caller
-- print feedback first. onReady(str) on success, onReady(nil, err) on failure.
-- With no runner (tests) it falls back to the synchronous string().
function Export.stringAsync(onReady)
	local AceSerializer, LibDeflate = libs()
	if not (AceSerializer and LibDeflate) then return onReady(nil, "export libs unavailable") end
	if not (ns.Schedule and ns.Schedule.Run) then return onReady(Export.string()) end
	ns.Schedule.Run(function()
		local payload = Export.buildPayload()
		coroutine.yield()
		local serialized = AceSerializer:Serialize(payload)
		coroutine.yield()
		local compressed = LibDeflate:CompressDeflate(serialized)
		coroutine.yield()
		onReady(PREFIX .. LibDeflate:EncodeForPrint(compressed))
	end)
end

-- Record every COMPLETED session as delivered (the active session is still
-- collecting, so it's excluded and re-exported next time). Drain.run drops these
-- next login. Returns how many newly-marked. Call ONLY after the user confirms the
-- paste landed on the site.
function Export.markExported()
	if not TiWDB then return 0 end
	TiWDB.exported_sessions = TiWDB.exported_sessions or {}
	local active = ns.session and ns.session.session_id
	local n = 0
	for _, rec in pairs(TiWDB.characters or {}) do
		local sessions = rec.sessions or {}
		for i = 1, #sessions do
			local id = sessions[i].session_id
			if id and id ~= active and not TiWDB.exported_sessions[id] then
				TiWDB.exported_sessions[id] = true
				n = n + 1
			end
		end
	end
	return n
end

return ns
