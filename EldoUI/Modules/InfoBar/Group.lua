-- EldoUI Info Bar: the Group block.
--
-- In a group the block shows its size and the assigned roles, short
-- ("18/40  2 T  5 H  11 D") or long ("18/40  2 tanks  5 healers
-- 11 damage"), with the number of members who are offline. Outside a group
-- it takes no room.
--
-- The tooltip names the leader, the assistants and the loot method, then
-- lists the roster by group (1 to 8 in a raid) in class colors with role
-- icons; offline members are dimmed. Dead members are marked out of combat
-- only, as the group frames do.
--
-- Click opens the game's raid panel. Right-click opens Raid Tools options.
--
-- Rules (Forever): the roster, roles and loot method are the game's own,
-- as its raid panel shows them. A secret value is left out, never guessed;
-- health and range are not read.
local _, E = ...
local L = E.L
local M = E.modules.InfoBar
local Plain = E.Plain

M.defaults.groupText = "short" -- "short" or "long"

local Group = {}
M.group = Group

local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }
local LOOT_NAMES = {
	[0] = E.Key("Free for all"), [1] = E.Key("Round robin"), [2] = E.Key("Master looter"),
	[3] = E.Key("Group loot"), [4] = E.Key("Need before greed"), [5] = E.Key("Personal loot"),
}

local function Call(fn, ...)
	return E.PlainCall(fn, ...)
end

local function Grey(text) return E:TextHex("secondary") .. text .. "|r" end

-- One member from a unit token: name, class, subgroup, role, online, dead,
-- leader and assistant. Values the game keeps secret stay nil.
local function Member(unit, raidIndex)
	if not Call(UnitExists, unit) then return nil end
	local member = { unit = unit, group = 1 }
	member.name = Plain((Call(UnitName, unit)))
	member.class = Plain(select(2, E.PlainCallEach(UnitClass, unit)))
	member.role = Call(UnitGroupRolesAssigned, unit)
	if member.role == "NONE" then member.role = nil end
	local connected = Call(UnitIsConnected, unit)
	member.offline = connected == false
	if not InCombatLockdown() then member.dead = Call(UnitIsDeadOrGhost, unit) and true or false end
	member.leader = Call(UnitIsGroupLeader, unit) and true or false
	member.assist = not member.leader and Call(UnitIsGroupAssistant, unit) and true or false
	if raidIndex then
		local subgroup = select(3, E.PlainCallEach(GetRaidRosterInfo, raidIndex))
		if type(subgroup) == "number" then member.group = subgroup end
	end
	return member
end

-- The group as a list of members, or nil outside a group.
function Group.Roster()
	if not Call(IsInGroup) then return nil end
	local list = {}
	if Call(IsInRaid) then
		local count = Call(GetNumGroupMembers) or 0
		for index = 1, count do
			local member = Member("raid" .. index, index)
			if member then list[#list + 1] = member end
		end
	else
		list[1] = Member("player")
		for index = 1, 4 do
			local member = Member("party" .. index)
			if member then list[#list + 1] = member end
		end
	end
	return list
end

-- Counts for the block text: members, the group's room, roles, offline.
function Group.Counts(list)
	local counts = { total = #list, TANK = 0, HEALER = 0, DAMAGER = 0, offline = 0 }
	for _, member in ipairs(list) do
		if member.role and counts[member.role] then counts[member.role] = counts[member.role] + 1 end
		if member.offline then counts.offline = counts.offline + 1 end
	end
	counts.room = Call(IsInRaid) and 40 or 5
	return counts
end

function Group.Text(counts, long)
	local value = M.Value(("%d/%d"):format(counts.total, counts.room))
	local parts = { value }
	if long then
		parts[#parts + 1] = E:Plural(counts.TANK, "%d tank", "%d tanks"):format(counts.TANK)
		parts[#parts + 1] = E:Plural(counts.HEALER, "%d healer", "%d healers"):format(counts.HEALER)
		parts[#parts + 1] = E:Plural(counts.DAMAGER, "%d damage dealer", "%d damage dealers"):format(counts.DAMAGER)
	else
		parts[#parts + 1] = L["%d T"]:format(counts.TANK)
		parts[#parts + 1] = L["%d H"]:format(counts.HEALER)
		parts[#parts + 1] = L["%d D"]:format(counts.DAMAGER)
	end
	if counts.offline > 0 then
		parts[#parts + 1] = E:StatusText("warn", L["%d offline"]:format(counts.offline))
	end
	return table.concat(parts, "  ")
end

function Group.LootText()
	local party = C_PartyInfo
	local method = party and Call(party.GetLootMethod)
	local name = LOOT_NAMES[method]
	return name and L[name] or nil
end

local function NameText(member)
	local name = member.name or "?"
	local icon = member.role and ROLE_ATLAS[member.role] and ("|A:%s:12:12|a "):format(ROLE_ATLAS[member.role]) or ""
	if member.offline then return icon .. Grey(name .. " (" .. L["Offline"] .. ")") end
	local text = E:WrapClassColor(member.class, name)
	if member.dead then text = text .. " " .. E:StatusText("bad", L["Dead"]) end
	return icon .. text
end

function Group.Describe(tooltip, list)
	local Kit = E.UIKit
	local leader, assists = nil, {}
	for _, member in ipairs(list) do
		if member.leader then leader = member.name elseif member.assist and member.name then assists[#assists + 1] = member.name end
	end
	if leader then Kit.TipPair(tooltip, L["Leader"], leader) end
	if #assists > 0 then Kit.TipPair(tooltip, L["Assistants"], table.concat(assists, ", ")) end
	local loot = Group.LootText()
	if loot then Kit.TipPair(tooltip, L["Loot method"], loot) end
	local looter = E.MasterLooterUnit()
	local looterName = looter and Call(E.UnitWhisperName, E, looter)
	if looterName then
		local _, class = E.PlainCallEach(UnitClass, looter)
		Kit.TipPair(tooltip, L["Master looter"], E:WrapClassColor(class, looterName))
	end
	local byGroup = {}
	for _, member in ipairs(list) do
		byGroup[member.group] = byGroup[member.group] or {}
		table.insert(byGroup[member.group], member)
	end
	local raid = Call(IsInRaid)
	for group = 1, 8 do
		local members = byGroup[group]
		if members then
			if raid then Kit.TipText(tooltip, Grey(L["Group %d"]:format(group))) end
			for _, member in ipairs(members) do tooltip:AddLine(NameText(member)) end
		end
	end
end

E:RegisterDataText("Group", {
	title = "Group",
	label = "Group",
	collapseEmpty = true,
	events = { "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED", "PARTY_LEADER_CHANGED", "PARTY_LOOT_METHOD_CHANGED", "UNIT_CONNECTION" },
	text = function()
		local list = Group.Roster()
		if not list then return "" end
		return Group.Text(Group.Counts(list), (M.db or M.defaults).groupText == "long")
	end,
	tooltip = function(tooltip)
		local list = Group.Roster()
		if not list then
			E.UIKit.TipText(tooltip, L["Not in a group."])
			return
		end
		Group.Describe(tooltip, list)
	end,
	hint = { { E.Key("Click"), E.Key("raid panel") }, { E.Key("Right-click"), E.Key("Raid Tools") } },
	rightClickOptions = { page = "module:RaidTools", key = "lootMethod" },
	-- Opens a window: out of combat only (M.ClickBlock).
	onClick = function(frame, button)
		if button == "RightButton" then
			E:OpenOptionsLink(frame, button)
		elseif ToggleRaidFrame then
			pcall(ToggleRaidFrame)
		end
	end,
})

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
M.InsertOptions({
	{ type = "header", label = "Group block" },
	{ type = "select", key = "groupText", label = "Group block text", values = { short = "Short", long = "Long" }, order = { "short", "long" },
		desc = "How the Group block writes its size and roles. It shows only in a group." },
})
