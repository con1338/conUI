-- Offline test for the guild message in the Info Bar's guild tooltip.
-- Run from the repository root:
--   lua5.1 tools/infobar/test_guild_motd.lua
-- Seen in the error log (16.11.2026, Ashenvale, in combat, 3 times):
-- "Blocked: EldoUI tried to call the protected function UNKNOWN() at
-- EldoUI/Modules/InfoBar.lua:800", the line that reads the guild message
-- (C_GuildInfo.GetMOTD). EldoUI only left it out while chat was locked down
-- (encounters, keys, PvP); WoW: Forever blocks it in any fight. Now the
-- tooltip leaves the message out in combat as well.
-- This cuts the real tooltip out of EldoUI/Modules/InfoBar.lua (between
-- fixed markers, so a renamed part makes the test fail instead of testing a
-- stale copy). Around it: a guild, the combat state, the chat lockdown and a
-- GetMOTD that is blocked in combat and in a lockdown, as in the game.
-- Checked: outside combat the message is read once and shown; in combat and
-- in a lockdown it is not read, the rest of the tooltip is there; the next
-- hover after the fight shows it again; outside a guild nothing is read.
-- Counter-check: the tooltip without the combat test calls the blocked
-- function in combat, as in the log.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/infobar/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local infobar = ReadFile("EldoUI/Modules/InfoBar.lua")
local block = Between(infobar, "function M.GuildTooltip(tooltip)", 'E:RegisterDataText("Friends", {', "InfoBar.lua guild")
local COMBAT_TEST = "not InCombatLockdown%(%) and " -- a Lua pattern
local oldBlock, guards = block:gsub(COMBAT_TEST, "", 1)
assert(guards == 1, "InfoBar.lua guild: the combat test before GetMOTD is missing")

---------------------------------------------------------------------------
-- Model of the game and EldoUI's core
---------------------------------------------------------------------------
local MOTD = "Raid on Thursday, 8 pm"
local world

local function NewWorld()
	world = { combat = false, lockdown = false, inGuild = true, motd = MOTD, reads = 0, blocked = 0, rosters = 0 }
end

function InCombatLockdown() return world.combat end
function IsInGuild() return world.inGuild end
function GetGuildInfo(unit)
	assert(unit == "player")
	if world.inGuild then return "The Patient Ones", "Officer" end
end
local ROSTER = {
	{ "Hermano", 24, "Paladin", "Ashenvale", true, "PALADIN" },
	{ "Brunhild", 31, "Warrior", "Orgrimmar", true, "WARRIOR" },
	{ "Ole", 12, "Mage", "Durotar", false, "MAGE" },
}
function GetNumGuildMembers()
	local online = 0
	for _, member in ipairs(ROSTER) do
		if member[5] then online = online + 1 end
	end
	return #ROSTER, online
end
function GetGuildRosterInfo(index)
	local m = ROSTER[index]
	return m[1], nil, nil, m[2], m[3], m[4], nil, nil, m[5], nil, m[6]
end
-- A blocked call does not run: the game raises ADDON_ACTION_BLOCKED and
-- the caller gets nothing back.
C_GuildInfo = {
	GuildRoster = function() world.rosters = world.rosters + 1 end,
	GetMOTD = function()
		world.reads = world.reads + 1
		if world.combat or world.lockdown then
			world.blocked = world.blocked + 1
			return nil
		end
		return world.motd
	end,
}

local L = setmetatable({}, { __index = function(_, key) return key end })
local E = { UIKit = {} }
function E.UIKit.TipText(tooltip, text) tooltip:AddLine(text) end
function E:TokenColor() return 0.4, 0.9, 0.4 end
function E:CommRestricted() return world.lockdown end
local SOCIAL_ROWS = 20
local function ShortName(name) return name end
local function SocialRow(tooltip, name) tooltip:AddLine(name) end

local function Load(text)
	local chunk = assert(loadstring("local E, L, M, SocialRow, ShortName, SOCIAL_ROWS = ...\n" .. text, "=InfoBar.lua guild"))
	local M = {}
	chunk(E, L, M, SocialRow, ShortName, SOCIAL_ROWS)
	return M
end

local function NewTooltip()
	local tooltip = { lines = {} }
	function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
	function tooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = left .. " | " .. right end
	function tooltip:Has(text)
		for _, line in ipairs(self.lines) do
			if line == text then return true end
		end
		return false
	end
	return tooltip
end

local function Hover(M)
	local tooltip = NewTooltip()
	M.GuildTooltip(tooltip)
	return tooltip
end

local failures, passed = 0, 0
local function Check(ok, message)
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		print("FAIL: " .. message)
	end
end

-- The rest of the tooltip: guild, count and the members online.
local function Rest(tooltip)
	return tooltip:Has("<The Patient Ones> | Officer") and tooltip:Has("Online 2 of 3")
		and tooltip:Has("Hermano") and tooltip:Has("Brunhild") and not tooltip:Has("Ole")
end

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local M = Load(block)

do
	NewWorld()
	local tooltip = Hover(M)
	Check(world.reads == 1 and tooltip:Has(MOTD), "outside combat the guild message is read once and shown")
	Check(world.blocked == 0, "outside combat nothing is blocked")
	Check(Rest(tooltip), "outside combat the rest of the tooltip is there")
end

do
	NewWorld()
	world.combat = true
	local tooltip = Hover(M)
	Check(world.reads == 0 and world.blocked == 0, "in combat the guild message is not read, nothing is blocked")
	Check(not tooltip:Has(MOTD), "in combat the tooltip has no guild message")
	Check(Rest(tooltip), "in combat the rest of the tooltip is there")
	Check(world.rosters == 1, "in combat the tooltip still asks for a fresh roster")
	world.combat = false
	tooltip = Hover(M)
	Check(world.reads == 1 and world.blocked == 0 and tooltip:Has(MOTD), "the next hover after the fight shows the guild message")
end

do
	NewWorld()
	world.lockdown = true
	local tooltip = Hover(M)
	Check(world.reads == 0 and world.blocked == 0 and not tooltip:Has(MOTD), "in a chat lockdown the guild message is not read (as before)")
	Check(Rest(tooltip), "in a chat lockdown the rest of the tooltip is there")
end

do
	NewWorld()
	world.motd = ""
	local tooltip = Hover(M)
	Check(world.reads == 1 and #tooltip.lines == 5, "an empty guild message adds no lines")
end

do
	NewWorld()
	world.inGuild = false
	local tooltip = Hover(M)
	Check(world.reads == 0 and world.rosters == 0, "outside a guild nothing is read")
	Check(tooltip:Has("You are not in a guild.") and #tooltip.lines == 1, "outside a guild the tooltip says so, and only that")
end

-- Counter-check: without the combat test the tooltip calls the blocked
-- function in combat, as in the error log.
do
	local old = Load(oldBlock)
	NewWorld()
	world.combat = true
	local tooltip = Hover(old)
	Check(world.reads == 1 and world.blocked == 1, "counter-check: the old tooltip calls the blocked function in combat")
	Check(Rest(tooltip), "counter-check: the old tooltip shows the rest all the same")
end

print(("%d checks passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
