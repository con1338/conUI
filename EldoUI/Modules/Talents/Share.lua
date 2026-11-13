-- EldoUI Talent Planner: sharing plans as "!EUT1!" strings.
--
-- A plan travels through EldoUI's share kit (Core/Share.lua): the same
-- encoder, the /eui import box and the "Send to" offer (E:SendShare). The
-- string holds only the plan: class, tree, game build, name, the buying
-- order by node ID and each node's spell ID (so a hotfix that moves a
-- talent doesn't break it). No character name.
--
-- Importing only ever saves a plan: it is checked against the class's
-- tree, clamped to legal ranks, and becomes a plan for the talent group you
-- use. A plan for another class is saved for later with your account's
-- plans for that class (read-only on this character). Nothing is learned.
local _, E = ...
local L = E.L
local P = E.TalentPlan
local M = E.Talents

local KIND = "talents"
local MAX_ORDER = 120

local function ClassName(token)
	return M:ClassName(token)
end

-- A plan by ID in your own groups or the account's plans for other classes.
function M:FindAnyPlan(planID)
	local plan = self:FindPlan(planID)
	if plan then return plan, E:TalentGroup() end
	for group = 1, 2 do
		plan = self:FindPlan(planID, group)
		if plan then return plan, group end
	end
	for class, data in pairs(self.AccountStore().classes) do
		for _, other in ipairs(type(data) == "table" and type(data.plans) == "table" and data.plans or {}) do
			if other.id == planID then return other, class end
		end
	end
end

-- The payload for one plan (the active plan without an id).
function M:SharePayload(planID)
	local plan, group
	if planID then plan, group = self:FindAnyPlan(planID) else plan = self:ActivePlan() end
	if not plan then return nil end
	local tree = self:TreeOf(group)
	local order, spells = {}, {}
	for index, nodeID in ipairs(plan.order) do
		order[index] = nodeID
		local node = tree and tree.nodes[nodeID]
		local spellID = node and node.spellID or (type(plan.spells) == "table" and plan.spells[nodeID])
		if spellID then spells[nodeID] = spellID end
	end
	local build = GetBuildInfo and select(2, GetBuildInfo()) or nil
	local class = self:IsOtherClass(group) and group or self:ClassToken()
	return { class = class, tree = tree and tree.treeID or plan.tree, build = build, name = plan.name, order = order, spells = spells }
end

local KNOWN_CLASS = {}
for _, token in ipairs(M.CLASSES) do KNOWN_CLASS[token] = true end

-- Check a received payload: returns a clean plan table or nil and why.
-- clean.class is the plan's class; clean.other is true when it is not
-- yours (saved for later), clean.unchecked when its tree couldn't be read.
function M:ReadPayload(data)
	if type(data) ~= "table" then return nil, L["the string is damaged or cut short. Copy it again in full."] end
	local class = type(data.class) == "string" and data.class or nil
	if not (class and KNOWN_CLASS[class]) then
		return nil, L["The plan names no class EldoUI knows."]
	end
	local other = self:IsOtherClass(class)
	local tree = self:TreeOf(class)
	if not tree and not other then return nil, L["Your talents aren't loaded yet. Try again in a moment."] end
	local order, spells = {}, {}
	if type(data.order) == "table" then
		for index = 1, math.min(#data.order, MAX_ORDER) do
			local nodeID = tonumber(data.order[index])
			if nodeID then order[#order + 1] = nodeID end
		end
	end
	if type(data.spells) == "table" then
		for nodeID, spellID in pairs(data.spells) do
			nodeID, spellID = tonumber(nodeID), tonumber(spellID)
			if nodeID and spellID then spells[nodeID] = spellID end
		end
	end
	local plan = { order = order, spells = spells }
	local moved, dropped = 0, 0
	if tree then moved, dropped = P.Verify(tree, plan, tree.maxPoints) end
	local name = type(data.name) == "string" and E:Utf8Sub((strtrim(data.name):gsub("|", "")), 40) or ""
	return {
		name = name ~= "" and name or L["Shared plan"], order = plan.order, spells = plan.spells, moved = moved, dropped = dropped,
		build = type(data.build) == "string" and data.build:sub(1, 20) or nil,
		class = class, other = other, unchecked = tree == nil,
	}
end

function M:DescribePlanOrder(order, group)
	local tree = self:TreeOf(group)
	if not tree then return "" end
	local spent = P.Count(tree, order).spent
	local parts = {}
	for _, treeGroup in ipairs(tree.groups) do parts[#parts + 1] = ("%s %d"):format(treeGroup.name, spent[treeGroup.groupID] or 0) end
	return table.concat(parts, " / ")
end

-- Save an import as a new plan: for the talent group in use, or for later
-- with the account's plans of another class. notify(text, warn), when
-- given, gets the result instead of chat: a click in a window answers in
-- that window (M:WindowNotice), the slash command and chat links in chat.
function M.ChatNotice(text)
	E:Print(text)
end

function M:ImportPayload(data, notify)
	notify = notify or M.ChatNotice
	local clean, err = self:ReadPayload(data)
	if not clean then
		notify(L["Import failed: %s"]:format(err), true)
		return nil
	end
	local group = clean.other and clean.class or nil
	local plan, why = self:CreatePlan(clean.name, clean.order, group, { spells = clean.spells })
	if not plan then
		notify(L["Import failed: %s"]:format(why), true)
		return nil
	end
	local note = ""
	if clean.dropped > 0 then note = " " .. L["%d ranks didn't fit your tree and were left out."]:format(clean.dropped) end
	M:SavedNotice(plan, clean.other and clean.class or nil, note, notify)
	return plan
end

-- What an import says once it is saved, in chat (with a link that opens
-- the planner) or through a window's notify.
function M:SavedNotice(plan, otherClass, note, notify)
	local name = E.UIKit.AccentHex() .. plan.name .. "|r"
	if otherClass then
		notify(L["Saved the %s plan %s for later. It opens on your %s characters and under %s in the planner. Nothing was learned."]:format(
			ClassName(otherClass), name, ClassName(otherClass), ClassName(otherClass)))
	elseif notify ~= M.ChatNotice then
		notify(L["Saved the talent plan %s. Nothing was learned."]:format(name) .. (note or ""))
	else
		notify(L["Saved the talent plan %s. Nothing was learned.%s %s"]:format(name, note or "", E:ChatLink("talents", "open", L["Open planner"])))
	end
end

-- A plan string pasted into a window: the same preview the share kit
-- shows, and the result in that window instead of chat.
function M:PreviewPlanString(text, notify)
	local kind, data = E:DecodeShareData(text)
	if kind ~= KIND then
		notify(L["Import failed: %s"]:format(kind and L["this string isn't a talent plan."] or tostring(data)), true)
		return false
	end
	local def = E:ShareKind(KIND)
	local lines = { E:Highlight(L["EldoUI string:"]) .. " " .. def.title(data) }
	for _, line in ipairs(def.describe(data)) do lines[#lines + 1] = line end
	E:ShowConfirm({ key = "ELDOUI_IMPORT_KIND", title = L["Import"], accept = ACCEPT, data = data,
		text = table.concat(lines, "\n") .. "\n\n" .. L["Import it? Nothing changes until you accept."],
		onAccept = function(payload) M:ImportPayload(payload, notify) end })
	return true
end

E:RegisterShareKind(KIND, {
	prefix = "!EUT1!",
	version = 1,
	title = function(data)
		local name = type(data) == "table" and type(data.name) == "string" and data.name or nil
		return name and L["Talent plan: %s"]:format(name:gsub("|", "")) or L["Talent plan"]
	end,
	build = function(planID) return M:SharePayload(planID) end,
	describe = function(data)
		local lines = {}
		local class = type(data) == "table" and data.class or nil
		lines[#lines + 1] = L["Class: %s"]:format(ClassName(type(class) == "string" and class or nil))
		local clean, err = M:ReadPayload(data)
		if not clean then
			local bad = E.UIKit and E.UIKit.BAD
			lines[#lines + 1] = bad and (E.UIKit.Hex(bad[1], bad[2], bad[3]) .. err .. "|r") or err
			return lines
		end
		if clean.unchecked then
			lines[#lines + 1] = E:Plural(#clean.order, "%d point", "%d points"):format(#clean.order)
		else
			lines[#lines + 1] = L["%d points: %s"]:format(#clean.order, M:DescribePlanOrder(clean.order, clean.other and clean.class or nil))
		end
		if clean.dropped > 0 then lines[#lines + 1] = L["%d ranks don't fit your tree and are left out."]:format(clean.dropped) end
		if clean.moved > 0 then lines[#lines + 1] = L["%d ranks follow talents that moved in a game update."]:format(clean.moved) end
		if clean.other then
			lines[#lines + 1] = L["Not your class: it is saved for later with your %s plans, read-only on this character."]:format(ClassName(clean.class))
			if clean.unchecked then lines[#lines + 1] = L["The game doesn't show the %s tree here, so the plan is checked when a %s opens it."]:format(ClassName(clean.class), ClassName(clean.class)) end
		end
		lines[#lines + 1] = L["It is saved as a plan. Nothing is learned."]
		return lines
	end,
	apply = function(data) M:ImportPayload(data) end,
})

-- Paste box for /eui talents import, the Plans tab and Import build.
-- notify: where a click in a window gets its answer (nil: chat).
function M:ShowImportBox(notify)
	E:ShowPasteBox(L["Import a talent plan"], L["Paste a talent plan string or a talent calculator link (Ctrl+V) and click Save. You see what it holds before it is saved; nothing is learned."],
		function(text) M:ImportText(text, notify) end)
end

function M:ExportPlan(planID)
	if not planID then return end
	E:ShowExport("share:" .. KIND .. ":" .. planID)
end

function M:SendPlan(planID, target)
	if not planID then return false end
	return E:SendShare("share:" .. KIND .. ":" .. planID, target)
end
