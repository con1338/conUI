-- EldoUI tooltip row "NPC services": what a town NPC has for this
-- character right now, one row at most, on friendly NPCs out of combat.
--
--   Class trainer of your class   "Can teach you  3 spells · 1g 20s", or
--                                 "Nothing new until level 26"
--   Weapon master                 the weapon skills it teaches that you can
--                                 learn and lack
--   Vendor                        the recipes it sells that you can learn
--                                 (a profession you have, enough skill, not
--                                 known yet); with Shift, its limited items
--   Flight master                 "Flight path not learned" when the game
--                                 reports its flight point as undiscovered
--
-- The trainer and weapon master rows come from the Training module's class
-- and weapon lists. Vendor stock comes from the Loot Guide data
-- (EldoUI_LootData, classic values: WoW: Forever's stock can differ), which
-- also names flight masters (else their English title does); the flight
-- point's state is the game's own. Display
-- only: nothing is opened, bought or learned.
local _, E = ...
local L = E.L

local Safe = E.Plain
local S = {}
E.TooltipServices = S

-- Flight master titles in the English client, for NPCs the data lacks.
local FLIGHT_TITLES = { "Flight Master", "Gryphon Master", "Wind Rider Master", "Hippogryph Master", "Bat Handler" }
local MAX_NAMES = 3

-- The NPC ID in a creature GUID, or nil.
function S.NpcID(unit)
	local guid = Safe(UnitGUID(unit))
	if type(guid) ~= "string" then return nil end
	local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind ~= "Creature" then return nil end
	return tonumber(npc)
end

-- The NPC's title line (the tooltip's second line), or nil.
local function Title(tooltip)
	local name = tooltip and tooltip.GetName and tooltip:GetName()
	local line = name and _G[name .. "TextLeft2"]
	local text = line and Safe(line:GetText())
	if type(text) ~= "string" or text == "" then return nil end
	return (text:gsub("^<", ""):gsub(">$", ""))
end

-- What the Loot Guide data says about the NPC: kinds ("c", "w", "f" ...)
-- and its title, or nil.
function S.Service(npc)
	local data = rawget(_G, "EldoUI_LootData")
	local text = npc and type(data) == "table" and type(data.services) == "table" and data.services[npc]
	if type(text) ~= "string" then return nil end
	local kinds, title = text:match("^(%a+)|.-|([^|]*)$")
	return kinds, title
end

local function Names(ids, limit)
	local names = {}
	for _, id in ipairs(ids) do
		if #names >= limit then break end
		local name = C_Item.GetItemNameByID and Safe((C_Item.GetItemNameByID(id)))
		if type(name) == "string" then names[#names + 1] = name end
	end
	return names
end

-- Recipes on the vendor's list you can learn, and its limited items.
function S.VendorRecipes(npc)
	local LG = E.LootGuide
	if not (LG and LG.VendorItems and LG.Recipe and LG.Player and LG.HasData and LG:HasData()) then return 0, {} end
	local items = LG:VendorItems(npc)
	if type(items) ~= "table" then return 0, {} end
	local mine = LG:Player().professions or {}
	local count, limited = 0, {}
	for itemID, isLimited in pairs(items) do
		local craft = LG:Recipe(itemID)
		local skill = craft and mine[craft.skill]
		if skill and skill >= (craft.rank or 1) and not LG:CraftKnown(craft.id) then count = count + 1 end
		if isLimited then limited[#limited + 1] = itemID end
	end
	table.sort(limited)
	return count, limited
end

-- The flight point next to you on this map: undiscovered as the game
-- reports it and not one you flew from or to before.
function S.FlightUnknown()
	if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap and C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return false end
	local map = Safe(C_Map.GetBestMapForUnit("player"))
	if type(map) ~= "number" then return false end
	local position = C_Map.GetPlayerMapPosition(map, "player")
	if type(position) ~= "table" or not position.GetXY then return false end
	local px, py = position:GetXY()
	px, py = Safe(px), Safe(py)
	if type(px) ~= "number" or type(py) ~= "number" then return false end
	local ok, nodes = pcall(C_TaxiMap.GetTaxiNodesForMap, map)
	local best, distance
	for _, node in ipairs(ok and type(nodes) == "table" and nodes or {}) do
		local at = node.position
		local x, y
		if type(at) == "table" then
			if at.GetXY then x, y = at:GetXY() else x, y = at.x, at.y end
		end
		x, y = Safe(x), Safe(y)
		if type(x) == "number" and type(y) == "number" then
			local d = (x - px) ^ 2 + (y - py) ^ 2
			if not distance or d < distance then best, distance = node, d end
		end
	end
	-- Within about two hundredths of the map: the flight master you look at.
	if not best or distance > 0.0004 or Safe(best.isUndiscovered) ~= true then return false end
	local store = E:GetPrivate("Transport")
	local id = Safe(best.nodeID)
	return not (type(store) == "table" and type(store.known) == "table" and id and store.known[id])
end

local function IsFlightTitle(title)
	if not title then return false end
	for _, word in ipairs(FLIGHT_TITLES) do
		if title:find(word, 1, true) then return true end
	end
	return false
end

-- The one row for the NPC: label, text, and the text's color kind.
function S.Row(tooltip, unit)
	local npc = S.NpcID(unit)
	if not npc then return nil end
	local kinds, dataTitle = S.Service(npc)
	local title = dataTitle or Title(tooltip)
	kinds = kinds or ""
	local T = E.Training
	if T and T.active then
		if (kinds:find("c", 1, true) or not dataTitle) and T.TeachesYou and T.TeachesYou(title) then
			local summary = T:TrainerSummary()
			if summary.count > 0 then
				local spells = E:Plural(summary.count, "%d spell", "%d spells"):format(summary.count)
				local cost = summary.cost > 0 and (" · " .. E:TooltipMoney(summary.cost)) or ""
				return L["Can teach you"], spells .. cost
			elseif summary.next then
				return L["Trainer"], L["Nothing new until level %d"]:format(summary.next), "secondary"
			end
			return nil
		end
		local weapons = T:WeaponsFrom(npc)
		if #weapons > 0 then return L["Teaches you"], table.concat(weapons, ", ") end
	end
	local recipes, limited = S.VendorRecipes(npc)
	if recipes > 0 then
		return L["Sells"], E:Plural(recipes, "%d recipe you can learn", "%d recipes you can learn"):format(recipes), nil, limited
	end
	if #limited > 0 then return nil, nil, nil, limited end
	if (kinds:find("f", 1, true) or not dataTitle and IsFlightTitle(title)) and S.FlightUnknown() then
		return L["Flight path not learned"], nil, "warn"
	end
end

function S.SectionUnit(tooltip, unit, add)
	if InCombatLockdown() or Safe(UnitIsPlayer(unit)) or not Safe(UnitIsFriend("player", unit)) then return end
	local left, right, color, limited = S.Row(tooltip, unit)
	if left then
		if color and not right then
			add(left, nil, E:TokenColor(color))
		elseif color then
			local r, g, b = E:TokenColor(color)
			add(left, right, nil, nil, nil, r, g, b)
		else
			add(left, right)
		end
	end
	if limited and #limited > 0 and IsShiftKeyDown() then
		local names = Names(limited, MAX_NAMES)
		if #names > 0 then
			local more = #limited > #names and (" " .. L["(+%d more)"]:format(#limited - #names)) or ""
			add(L["Limited supply"], table.concat(names, ", ") .. more)
			add(L["Vendor stock is classic data; WoW: Forever can differ."], nil, 0.65, 0.65, 0.7)
		end
	end
end

E:RegisterTooltipSection("npcServices", {
	order = 44,
	title = "NPC services",
	desc = "On trainers, weapon masters, vendors and flight masters: what they have for this character right now. Vendors need the Loot Guide data.",
	default = "always",
	unit = S.SectionUnit,
})
