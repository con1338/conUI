-- EldoUI Legacy Planner: sharing a build as an "!EUL1!" string.
--
-- A build travels through EldoUI's share kit (Core/Share.lua): the same
-- encoder, the /eui import box and the "Send to" offer. The string holds a
-- name, the game build it was made on and the ranks by node ID (with the
-- chosen option of a choice node). No character name.
--
-- Importing only ever saves a profile: ranks are checked against your
-- Legacy trees and clamped. Nothing is spent, and the draft stays as it is.
local _, E = ...
local L = E.L
local M = E.Legacy

local KIND = "legacy"
local MAX_NODES = 200

-- The payload: a profile (by id) or the draft.
function M:SharePayload(profileID)
	local profile = profileID and self:FindProfile(tonumber(profileID))
	local build = profile and profile.build or self:Draft()
	local nodes = {}
	local count = 0
	for nodeID, item in pairs(build or {}) do
		if type(item) == "table" and (tonumber(item.r) or 0) > 0 and count < MAX_NODES then
			count = count + 1
			nodes[tonumber(nodeID) or nodeID] = { r = item.r, e = item.e }
		end
	end
	if count == 0 then return nil end
	local gameBuild = GetBuildInfo and select(2, GetBuildInfo()) or nil
	return { name = profile and profile.name or L["Legacy draft"], build = gameBuild, nodes = nodes }
end

-- Check a received payload: a clean build or nil and why.
function M:ReadPayload(data)
	if type(data) ~= "table" or type(data.nodes) ~= "table" then
		return nil, L["the string is damaged or cut short. Copy it again in full."]
	end
	local snapshot = self:Snapshot()
	if not snapshot then return nil, L["Your Legacy trees aren't loaded yet. Open Blizzard's Legacy window once, then try again."] end
	local raw, count = {}, 0
	for nodeID, item in pairs(data.nodes) do
		count = count + 1
		if count > MAX_NODES then break end
		raw[nodeID] = item
	end
	local build, dropped = M.Clean(raw, snapshot.nodes)
	local name = M.CleanName(data.name)
	return { name = name ~= "" and name or L["Shared Legacy build"], build = build, dropped = dropped }
end

function M:ImportPayload(data)
	local clean, err = self:ReadPayload(data)
	if not clean then
		E:Print(L["Import failed: %s"]:format(err))
		return nil
	end
	local profile, why = self:SaveProfile(clean.name, clean.build)
	if not profile then
		E:Print(L["Import failed: %s"]:format(why))
		return nil
	end
	local note = ""
	if clean.dropped > 0 then note = " " .. L["%d nodes aren't on your Legacy trees and were left out."]:format(clean.dropped) end
	E:Print(L["Saved the Legacy profile %s. Nothing was spent.%s"]:format(E.UIKit.AccentHex() .. profile.name .. "|r", note))
	return profile
end

E:RegisterShareKind(KIND, {
	prefix = "!EUL1!",
	version = 1,
	title = function(data)
		local name = type(data) == "table" and type(data.name) == "string" and data.name or nil
		return name and L["Legacy build: %s"]:format((name:gsub("|", ""))) or L["Legacy build"]
	end,
	build = function(profileID) return M:SharePayload(profileID) end,
	describe = function(data)
		local lines = {}
		local clean, err = M:ReadPayload(data)
		if not clean then
			local bad = E.UIKit.BAD
			lines[#lines + 1] = E.UIKit.Hex(bad[1], bad[2], bad[3]) .. err .. "|r"
			return lines
		end
		local snapshot = M:Snapshot()
		local cost = M.Cost(clean.build, snapshot and snapshot.nodes)
		lines[#lines + 1] = L["%d ranks, %d Legacy points"]:format(M.CountRanks(clean.build), cost)
		if clean.dropped > 0 then lines[#lines + 1] = L["%d nodes aren't on your Legacy trees and are left out."]:format(clean.dropped) end
		lines[#lines + 1] = L["It is saved as a profile. Nothing is spent."]
		return lines
	end,
	apply = function(data) M:ImportPayload(data) end,
})

function M:ShowImportBox()
	E:ShowPasteBox(L["Import a Legacy build"], L["Paste a Legacy build string (Ctrl+V) and click Save. You see what it holds before it is saved as a profile; nothing is spent."],
		function(text) E:ImportString(text) end)
end

-- Export a profile (by id), or the draft without an id.
function M:ExportDraft(profileID)
	if not self:SharePayload(profileID) then
		E:Print(L["The draft is empty. Add ranks in the Legacy Planner first."])
		return false
	end
	E:ShowExport("share:" .. KIND .. (profileID and (":" .. profileID) or ""))
	return true
end
