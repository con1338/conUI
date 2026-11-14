-- EldoUI Raid Loot: DKP and EPGP standings from the guild notes.
--
-- Guilds that run DKP or EPGP keep each member's standing in the guild
-- roster's notes, written there by their DKP or EPGP addon or by an
-- officer. This reads those notes (read only) and shows the standings:
--   * after each name on the SR and TMB lines (item tooltips, loot rolls);
--   * on a guild member's tooltip (Tooltip module section "Guild points");
--   * in the Info Bar block "Guild points": yours, and the members of your
--     group (or the guild's best) in its tooltip.
-- The chat post of the reservations never carries them: officer notes are
-- for officers.
--
-- What a note may hold (setting "Read standings"):
--   * EPGP: "EP,GP" as EPGP and CEPGP write it, e.g. "1250,830". The
--     priority is EP / (GP + base GP); the base GP comes from the guild
--     information text ("@BASE_GP:1000", the EPGP addon's line), else 0.
--     An alt whose note is its main's name (EPGP's alt rule) shows the
--     main's standing.
--   * DKP: "Net:350" (QDKP), "DKP: 350" or "350 DKP"; with "DKP" chosen
--     also a plain number ("350").
-- "Automatic" takes EPGP notes and labelled DKP notes, never a bare
-- number, which a note may hold for anything. The officer note is read only
-- when the game lets you see it.
local _, E = ...
local L = E.L
local M = E.RaidLoot

M.defaults.points = "auto"         -- auto | epgp | dkp | off
M.defaults.pointsNote = "officer"  -- officer | public | both
M.defaults.pointsInLines = true    -- standings after the names on SR and TMB lines

local Clean = E.Plain
local P = {}
M.Points = P

---------------------------------------------------------------------------
-- Reading notes
---------------------------------------------------------------------------
local NUMBER = "(%-?%d+%.?%d*)"

-- The standing one note holds: { kind = "epgp", ep, gp } or
-- { kind = "dkp", dkp }, or nil.
function P.Parse(note, format)
	if type(note) ~= "string" or E.Secret(note) or note == "" or format == "off" then return nil end
	if format ~= "dkp" then
		local ep, gp = note:match("^%s*(%-?%d+)%s*,%s*(%-?%d+)%s*$")
		if ep then return { kind = "epgp", ep = tonumber(ep), gp = tonumber(gp) } end
		if format == "epgp" then return nil end
	end
	local dkp = note:match("[Nn][Ee][Tt]%s*[:=]%s*" .. NUMBER) or note:match("[Dd][Kk][Pp]%s*[:=]?%s*" .. NUMBER)
		or note:match(NUMBER .. "%s*[Dd][Kk][Pp]")
	if not dkp and format == "dkp" then dkp = note:match("^%s*" .. NUMBER .. "%s*$") end
	if dkp then return { kind = "dkp", dkp = tonumber(dkp) } end
	return nil
end

-- The base GP from the guild information text, else 0.
function P.BaseGP(text)
	if type(text) ~= "string" or E.Secret(text) then return 0 end
	return tonumber(text:match("@BASE_GP:%s*(%d+)")) or 0
end

-- A name as a key: lower case, without the realm.
function P.Key(name)
	if type(name) ~= "string" or E.Secret(name) then return nil end
	name = name:match("^([^%-]+)") or name
	if name == "" then return nil end
	return name:lower()
end

-- The standings of a roster: rows of { name, publicNote, officerNote } ->
-- { [key] = entry }. An entry has kind, ep, gp, pr or dkp, name (as in the
-- roster) and main (the main's name, for an alt).
function P.Build(rows, format, which, baseGP)
	local out, alts = {}, {}
	if format == "off" then return out end
	for _, row in ipairs(rows) do
		local key = P.Key(row.name)
		if key then
			local notes = {}
			if which ~= "public" and row.officerNote then notes[#notes + 1] = row.officerNote end
			if which ~= "officer" and row.publicNote then notes[#notes + 1] = row.publicNote end
			local entry
			for _, note in ipairs(notes) do
				entry = P.Parse(note, format)
				if entry then break end
			end
			if entry then
				entry.name = row.name:match("^([^%-]+)") or row.name
				if entry.kind == "epgp" then
					local divisor = entry.gp + (baseGP or 0)
					entry.pr = divisor > 0 and entry.ep / divisor or nil
				end
				out[key] = entry
			else
				-- EPGP's alt rule: the note holds the main's name.
				for _, note in ipairs(notes) do
					local main = type(note) == "string" and not E.Secret(note) and note:match("^%s*([^%s%d%p][^%s%d%p]+)%s*$")
					if main then
						alts[key] = { name = row.name:match("^([^%-]+)") or row.name, main = main:lower() }
						break
					end
				end
			end
		end
	end
	for key, alt in pairs(alts) do
		local main = out[alt.main]
		if main and not main.main then
			out[key] = { kind = main.kind, ep = main.ep, gp = main.gp, pr = main.pr, dkp = main.dkp, name = alt.name, main = main.name }
		end
	end
	return out
end

-- "PR 1.51" or "350 DKP".
function P.Short(entry)
	if not entry then return nil end
	if entry.kind == "epgp" then
		return entry.pr and ("PR %.2f"):format(entry.pr) or ("%d / %d"):format(entry.ep, entry.gp)
	end
	return ("%s DKP"):format(P.Number(entry.dkp))
end

-- "1250 / 830, PR 1.51" or "350" (and the main for an alt).
function P.Detail(entry)
	local text
	if entry.kind == "epgp" then
		text = ("%d / %d"):format(entry.ep, entry.gp)
		if entry.pr then text = ("%s, PR %.2f"):format(text, entry.pr) end
	else
		text = P.Number(entry.dkp)
	end
	if entry.main then text = ("%s (%s)"):format(text, L["from %s"]:format(entry.main)) end
	return text
end

function P.Number(value)
	if value == math.floor(value) then return ("%d"):format(value) end
	return ("%.1f"):format(value)
end

function P.Label(entry)
	return entry.kind == "epgp" and "EPGP" or "DKP"
end

-- For sorting: the priority, else the DKP.
function P.Value(entry)
	if entry.kind == "epgp" then return entry.pr or 0 end
	return entry.dkp or 0
end

---------------------------------------------------------------------------
-- The guild roster
---------------------------------------------------------------------------
M.points = {}

local function OfficerNotesVisible()
	local can = _G.CanViewOfficerNote
	if type(can) ~= "function" then return true end
	local ok, visible = pcall(can)
	return ok and Clean(visible) == true
end

-- Read the roster again; a change redraws the lines that show standings.
function M:RefreshPoints()
	local format = self.db and self.db.points or "off"
	local cache = {}
	if self.active and format ~= "off" and IsInGuild and Clean(IsInGuild()) then
		local rows, officer = {}, OfficerNotesVisible()
		local count = Clean(GetNumGuildMembers and GetNumGuildMembers())
		for index = 1, type(count) == "number" and count or 0 do
			local name, _, _, _, _, _, publicNote, officerNote = GetGuildRosterInfo(index)
			name = Clean(name)
			if type(name) == "string" then
				rows[#rows + 1] = { name = name, publicNote = Clean(publicNote), officerNote = officer and Clean(officerNote) or nil }
			end
		end
		cache = P.Build(rows, format, self.db.pointsNote, P.BaseGP(Clean(GetGuildInfoText and GetGuildInfoText())))
	end
	local signature = P.Signature(cache)
	self.points = cache
	if signature ~= self.pointsSignature then
		self.pointsSignature = signature
		self:Changed()
		if self.active and E.modules.InfoBar and E.modules.InfoBar.RefreshDataText then
			E.modules.InfoBar:RefreshDataText("GuildPoints")
		end
	end
end

function P.Signature(cache)
	local keys = {}
	for key, entry in pairs(cache) do keys[#keys + 1] = key .. "=" .. P.Detail(entry) end
	table.sort(keys)
	return table.concat(keys, ";")
end

-- The standing of a name, or nil.
function M.PointsEntry(name)
	local key = P.Key(Clean(name))
	return key and M.points[key] or nil
end

-- "PR 1.51" after a name on the SR and TMB lines.
function M.PointsText(name)
	if not (M.active and M.db.pointsInLines) then return nil end
	return P.Short(M.PointsEntry(name))
end

local EVENTS = { "GUILD_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" }

function M:EnablePoints()
	for _, event in ipairs(EVENTS) do
		E:RegisterEvent(event, function() M:RefreshPoints() end, "RaidLootPoints")
	end
	-- Ask the game for the roster; it answers with GUILD_ROSTER_UPDATE.
	if IsInGuild and Clean(IsInGuild()) and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
	self:RefreshPoints()
end

function M:DisablePoints()
	for _, event in ipairs(EVENTS) do E:UnregisterEvent(event, "RaidLootPoints") end
	self.points, self.pointsSignature = {}, nil
end

---------------------------------------------------------------------------
-- Where they show: a guild member's tooltip
---------------------------------------------------------------------------
local function UnitPoints(_, unit, add)
	if not M.active then return end
	unit = Clean(unit)
	if type(unit) ~= "string" or Clean(UnitIsPlayer(unit)) ~= true then return end
	-- The same name on another realm is someone else.
	if UnitIsInMyGuild and Clean(UnitIsInMyGuild(unit)) ~= true then return end
	local entry = M.PointsEntry(UnitName(unit))
	if not entry then return end
	local s, b = E.tokens.text.secondary, E.tokens.text.body
	add(P.Label(entry), P.Detail(entry), s[1], s[2], s[3], b[1], b[2], b[3])
end
P.UnitPoints = UnitPoints

function M:InitPoints()
	if E.RegisterTooltipSection then
		E:RegisterTooltipSection("guildPoints", { order = 48, title = "Guild points (DKP and EPGP)", default = "always", module = "RaidLoot", -- no-L (translated where shown)
			desc = "A guild member's DKP or EPGP standing, read from the guild notes (Raid Loot > Guild points).", -- no-L (translated where shown)
			unit = UnitPoints })
	end
end

---------------------------------------------------------------------------
-- Where they show: the Info Bar block
---------------------------------------------------------------------------
local MAX_ROWS = 15

local function Grey(text) return E:TextHex("secondary") .. text .. "|r" end

-- The rows for the tooltip: your group's members with a standing, or the
-- guild's best when you are in no group. Highest first.
function P.Rows(cache, groupNames)
	local rows = {}
	for key, entry in pairs(cache) do
		if not groupNames or groupNames[key] then rows[#rows + 1] = entry end
	end
	table.sort(rows, function(a, b)
		if P.Value(a) ~= P.Value(b) then return P.Value(a) > P.Value(b) end
		return a.name < b.name
	end)
	while #rows > MAX_ROWS do table.remove(rows) end
	return rows
end

---------------------------------------------------------------------------
-- Options (before "Posting" on the Raid Loot page)
---------------------------------------------------------------------------
local function PointsOff() return M.db.points == "off" end
local OPTIONS = {
	{ type = "header", label = "Guild points" },
	{ type = "select", key = "points", label = "Read standings", order = { "auto", "epgp", "dkp", "off" },
		values = { auto = "Automatic", epgp = "EPGP", dkp = "DKP", off = "Off" },
		desc = "DKP or EPGP standings from the guild notes, after the names on the SR and TMB lines, on guild members' tooltips and in the Info Bar block \"Guild points\". Automatic: EPGP notes (\"1250,830\") and DKP notes with a label (\"Net:350\", \"DKP: 350\"). DKP also takes a plain number." },
	{ type = "select", key = "pointsNote", label = "From the note", order = { "officer", "public", "both" }, hidden = PointsOff,
		values = { officer = "Officer note", public = "Public note", both = "Both" },
		desc = "Which guild note holds the standings. The officer note counts only when the game lets you see it." },
	{ type = "toggle", key = "pointsInLines", label = "After the names", hidden = PointsOff,
		desc = "Each player's standing after their name on the SR and TMB lines. The chat post of the reservations never carries it." },
}
do
	local at = #M.options + 1
	for index, option in ipairs(M.options) do
		if option.type == "header" and option.label == "Posting" then at = index break end
	end
	for offset, option in ipairs(OPTIONS) do table.insert(M.options, at + offset - 1, option) end
end

if E.RegisterDataText then
	E:RegisterDataText("GuildPoints", {
		title = "Guild points", -- no-L (translated where shown)
		events = { "GUILD_ROSTER_UPDATE", "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE" },
		text = function()
			if not M.active or M.db.points == "off" then return Grey(L["Off"]) end
			return P.Short(M.PointsEntry(E:PlayerName())) or Grey("-")
		end,
		tooltip = function(tooltip)
			if not M.active or M.db.points == "off" then
				tooltip:AddLine(L["Off"])
				return
			end
			if not (IsInGuild and Clean(IsInGuild())) then
				tooltip:AddLine(L["You are not in a guild."], 1, 1, 1)
				return
			end
			local mine = M.PointsEntry(E:PlayerName())
			if mine then E.UIKit.TipPair(tooltip, P.Label(mine), P.Detail(mine)) end
			local inGroup = IsInGroup and Clean(IsInGroup())
			local groupNames
			if inGroup then
				groupNames = {}
				for key in pairs(M:GroupNames()) do groupNames[key] = true end
			end
			local rows = P.Rows(M.points, groupNames)
			if #rows == 0 then
				tooltip:AddLine(L["No DKP or EPGP standings in the guild notes."], 1, 1, 1, true)
				return
			end
			tooltip:AddLine(" ")
			tooltip:AddLine(inGroup and L["Your group"] or L["Guild"], 1, 0.82, 0)
			for _, entry in ipairs(rows) do E.UIKit.TipPair(tooltip, entry.name, P.Detail(entry)) end
		end,
	})
end
