-- EldoUI Talent Planner: suggested talent paths.
--
-- A path is a buying order of talents that EldoUI suggests for one role and
-- one situation of a class. Picking one in the planner's Builds tab copies
-- it into a new plan of the player's own; nothing is learned or overwritten,
-- and Undo takes the copy back. Following it in game is the plan's usual
-- flow: the next point on the level-up card and on Blizzard's talent window.
--
-- Paths are kept by spell ID, so they survive a talent moving to another
-- node. A talent the game's tree no longer has is skipped and counted, and
-- the planner says how many points were skipped; it is never an error.
--
-- Every path is written from scratch by EldoUI and checked on the game
-- build it names. A class file lives in Modules/Talents/Builds/<Class>.lua,
-- is listed in EldoUI.toc after this file, and looks like this:
--
--   local _, E = ...
--   local L = E.L
--   E.TalentBuilds.Add("WARRIOR", {
--       { key = "leveling", role = "damage", situation = "leveling", checked = "1.60.1.70425",
--         title = L["Two-handed leveling"], note = L["Why these talents, when to change, what to keep on your bars."],
--         order = { spellID, spellID, ... } },   -- one entry per rank, in buying order
--   })
--
--   role       "tank", "healer" or "damage"
--   situation  "leveling" (all 51 points, from level 10), "solo" (level 60 on your
--              own: quests and the open world), "dungeon", "raid", "pvp" or "farming"
--
-- API:
--   B.Add(class, paths)          adds a class's paths (entries with a bad shape are left out)
--   B.Paths(class)               the class's paths, in file order (empty table when none)
--   B.Find(class, key)           one path
--   B.Problems(path)             what is wrong with a path's shape (empty table: nothing)
--   B.Resolve(tree, path)        node order for the tree, and how many points were skipped
--   B.ForRole(class, role, level) the path the installer names for a role
--   B.Situations(class)          the situations the class has paths for, in order
--   B.Pick(class, situation, role) the path for a situation, the role's own first
--   B.DefaultSituation(class, level, maxLevel) leveling below the level cap,
--                                at the cap the first level 60 situation
local _, E = ...
local L = E.L
local P = E.TalentPlan

local B = {}
E.TalentBuilds = B

B.ROLES = { "tank", "healer", "damage" }
B.SITUATIONS = { "leveling", "solo", "dungeon", "raid", "pvp", "farming" }
B.MAX_RANKS = 120

local ROLE_ORDER, SITUATION_ORDER = {}, {}
for index, key in ipairs(B.ROLES) do ROLE_ORDER[key] = index end
for index, key in ipairs(B.SITUATIONS) do SITUATION_ORDER[key] = index end
B.ROLE_ORDER, B.SITUATION_ORDER = ROLE_ORDER, SITUATION_ORDER

local classes = {}   -- [class token] = { path, ... }
B.classes = classes

local NONE = {}

function B.Problems(path)
	local problems = {}
	local function Problem(text) problems[#problems + 1] = text end
	if type(path) ~= "table" then
		Problem("not a table")
		return problems
	end
	if type(path.key) ~= "string" or path.key == "" then Problem("no key") end
	if not ROLE_ORDER[path.role] then Problem("role " .. tostring(path.role) .. " is not tank, healer or damage") end
	if not SITUATION_ORDER[path.situation] then Problem("unknown situation " .. tostring(path.situation)) end
	if type(path.checked) ~= "string" or path.checked == "" then Problem("no game version it was checked on") end
	if type(path.title) ~= "string" or path.title == "" then Problem("no title") end
	if type(path.note) ~= "string" or path.note == "" then Problem("no note") end
	if type(path.order) ~= "table" or #path.order == 0 then
		Problem("no talents")
	else
		if #path.order > B.MAX_RANKS then Problem("too many ranks") end
		for index, spellID in ipairs(path.order) do
			if type(spellID) ~= "number" or spellID <= 0 or spellID % 1 ~= 0 then
				Problem(("entry %d is not a spell ID"):format(index))
				break
			end
		end
	end
	return problems
end

function B.Add(class, paths)
	if type(class) ~= "string" or type(paths) ~= "table" then return 0 end
	local list = classes[class] or {}
	classes[class] = list
	local taken = {}
	for _, path in ipairs(list) do taken[path.key] = true end
	local added = 0
	for _, path in ipairs(paths) do
		if #B.Problems(path) == 0 and not taken[path.key] then
			path.class = class
			list[#list + 1] = path
			taken[path.key] = true
			added = added + 1
		end
	end
	return added
end

function B.Paths(class)
	return class and classes[class] or NONE
end

function B.Find(class, key)
	for _, path in ipairs(B.Paths(class)) do
		if path.key == key then return path end
	end
end

function B.RoleText(role)
	if role == "tank" then return L["Tank"] end
	if role == "healer" then return L["Healer"] end
	return L["Damage"]
end

function B.SituationText(situation)
	if situation == "solo" then return L["Solo"] end
	if situation == "dungeon" then return L["Dungeons"] end
	if situation == "raid" then return L["Raids"] end
	if situation == "pvp" then return L["PvP"] end
	if situation == "farming" then return L["Farming"] end
	return L["Leveling"]
end

-- The path as node IDs of `tree`, legal by the plan rules (Plan.lua), and
-- how many of its points were skipped: talents the tree doesn't have, and
-- ranks that can't be bought where the path puts them or at all.
function B.Resolve(tree, path)
	if not (tree and path and type(path.order) == "table") then return {}, 0 end
	local order, missing = {}, 0
	for _, spellID in ipairs(path.order) do
		local nodeID = tree.bySpell and tree.bySpell[spellID]
		if nodeID and tree.nodes[nodeID] then order[#order + 1] = nodeID else missing = missing + 1 end
	end
	local fixed, dropped = P.Normalize(tree, order, tree.maxPoints)
	return fixed, missing + #dropped
end

-- The path the installer's Role step names for `role`: below the level
-- cap the leveling path, at the cap a group path (dungeons, then raids),
-- else the role's first path.
function B.ForRole(class, role, level, maxLevel)
	local leveling, group, first
	for _, path in ipairs(B.Paths(class)) do
		if path.role == role then
			first = first or path
			if path.situation == "leveling" then
				leveling = leveling or path
			elseif path.situation == "dungeon" or path.situation == "raid" then
				if not group or SITUATION_ORDER[path.situation] < SITUATION_ORDER[group.situation] then group = path end
			end
		end
	end
	local capped = level and maxLevel and level >= maxLevel
	if capped then return group or first end
	return leveling or first
end

function B.Situations(class)
	local seen, list = {}, {}
	for _, path in ipairs(B.Paths(class)) do seen[path.situation] = true end
	for _, situation in ipairs(B.SITUATIONS) do
		if seen[situation] then list[#list + 1] = situation end
	end
	return list
end

-- The path for a situation: the one made for `role` when there is one,
-- else the situation's first path.
function B.Pick(class, situation, role)
	local first
	for _, path in ipairs(B.Paths(class)) do
		if path.situation == situation then
			if path.role == role then return path end
			first = first or path
		end
	end
	return first
end

function B.DefaultSituation(class, level, maxLevel)
	local list = B.Situations(class)
	local capped = (level and maxLevel and level >= maxLevel) and true or false
	for _, situation in ipairs(list) do
		if (situation ~= "leveling") == capped then return situation end
	end
	return list[1]
end

---------------------------------------------------------------------------
-- The planner's side: the paths of the class a talent group plans for,
-- and copying one into a new plan.
---------------------------------------------------------------------------
local M = E.Talents

function M:BuildsClass(group)
	if self:IsOtherClass(group) then return group end
	return self:ClassToken()
end

function M:PathsOf(group)
	return B.Paths(self:BuildsClass(group))
end

-- A new plan from a suggested path, in use at once; Undo takes it back.
-- Returns the plan and how many points of the path were skipped, or nil
-- and why.
function M:CopyPath(key, group)
	local path = B.Find(self:BuildsClass(group), key)
	if not path then return nil, L["That suggested path isn't available."] end
	local tree = self:TreeOf(group)
	if not tree then return nil, self:NoTreeText(group) end
	local order, skipped = B.Resolve(tree, path)
	local plan, err = self:CreatePlan(L["%s (suggested)"]:format(path.title), order, group, { undoable = true })
	if not plan then return nil, err end
	plan.path, plan.pathChecked = path.key, path.checked
	return plan, skipped
end

-- What the planner says after a copy.
function M:CopyPathText(plan, skipped)
	if (skipped or 0) > 0 then
		return E:Plural(skipped, "%d point of this path isn't in your game's tree, so the plan skips it.",
			"%d points of this path aren't in your game's tree, so the plan skips them."):format(skipped), true
	end
	return L["%s is your plan now. Undo takes it back."]:format(plan.name)
end

---------------------------------------------------------------------------
-- The installer's Role step: one line naming the suggested path for the
-- role picked, with a button that opens it in the planner. It never makes
-- or changes a plan. Shown only when the class has a path for that role.
--   local hint = E.Talents:CreateRoleHint(parent)
--   hint:Update(role) -> true when it shows
---------------------------------------------------------------------------
function M:CreateRoleHint(parent)
	local Kit = E.UIKit
	local hint = CreateFrame("Frame", nil, parent)
	hint:SetHeight(24)
	hint.text = Kit.Text(hint, 12, "LEFT", "secondary")
	hint.text:SetPoint("LEFT", 0, 0)
	hint.text:SetWordWrap(false)
	hint.open = Kit.Button(hint, L["Open in planner"], 140, 22, function()
		if hint.path then M:OpenPlanner("builds", hint.path.key) end
	end, L["Open in planner"], L["Shows the path in the Talent Planner's Builds tab. Nothing changes until you copy it into a plan there."])
	hint.open:SetPoint("LEFT", hint.text, "RIGHT", 10, 0)
	Kit.FitButton(hint.open, 120)
	function hint.Update(own, role)
		local path = role and B.ForRole(M:ClassToken(), role, M:PlayerLevel(), M:MaxLevel())
		own.path = path
		own:SetShown(path ~= nil)
		if not path then return false end
		local name = E.UIKit.AccentHex() .. path.title .. "|r"
		if M.active then
			own.text:SetText(L["Suggested talent path: %s"]:format(name))
			own.open:Show()
		else
			own.text:SetText(L["Suggested talent path: %s (turn on the Talent Planner in the Modules step to see it)"]:format(name))
			own.open:Hide()
		end
		return true
	end
	hint:Hide()
	return hint
end
