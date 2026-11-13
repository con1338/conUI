-- EldoUI Talent Planner: the build bar.
--
-- One row of controls on the planner's Trees tab, and the same row on
-- Blizzard's talent window next to the Planner button:
--
--   [Dungeons v] [Recommended build] [Import build]  Suggested path: ...
--
--   * the category picker: the situations the class has suggested paths
--     for (Leveling, Solo, Dungeons, Raids, PvP, Farming); it starts on
--     Leveling below the level cap and on the first level 60 situation at
--     the cap;
--   * Recommended build: copies the suggested path for that category and
--     your role (General > Role) into a new plan of your own, in use at
--     once, the same as Copy to a new plan on the Builds tab. Undo takes it
--     back. Nothing is learned: each point is still yours to click;
--   * Import build: the paste box for a talent calculator link, a talent
--     string, a talent loadout string or an EldoUI plan string.
-- The picker and Recommended build show only for a class with suggested
-- paths. Every result shows as a toast where the click was, never in chat.
--
--   local bar = M:CreateBuildBar(parent, { group = fn, notify = fn, compact = true })
--   bar:Update() -> the bar's width
local _, E = ...
local L = E.L
local M = E.Talents
local B = E.TalentBuilds
local Kit = E.UIKit

local GAP = 6

-- The category the bar shows for a talent group's class.
function M:BuildSituation(group)
	local class = self:BuildsClass(group)
	local list = B.Situations(class)
	for _, situation in ipairs(list) do
		if situation == self.buildSituation then return situation end
	end
	return B.DefaultSituation(class, self:PlayerLevel(), self:MaxLevel())
end

function M:SetBuildSituation(situation)
	self.buildSituation = situation
	self:RefreshViews()
end

-- The path Recommended build copies for a talent group, or nil.
function M:RecommendedPath(group)
	local situation = self:BuildSituation(group)
	if not situation then return nil end
	-- The paths name the three roles: Melee and Ranged read as "damage".
	local role = E.GetRoleGroup and E:GetRoleGroup() or "none"
	return B.Pick(self:BuildsClass(group), situation, role)
end

local function Group(bar)
	return bar.opts.group and bar.opts.group() or nil
end

local function Copy(bar)
	local group = Group(bar)
	local path = M:RecommendedPath(group)
	if not path then return end
	local plan, result = M:CopyPath(path.key, group)
	if not plan then
		bar.notify(result or "", true)
		return
	end
	local text, warn = M:CopyPathText(plan, result)
	bar.notify(text, warn, { L["Undo"], function() M:Undo(plan) end })
end

local function RecommendTip(bar)
	return function(tooltip)
		local path = M:RecommendedPath(Group(bar))
		if not path then return end
		Kit.TipText(tooltip, L["Copies the suggested path %s into a new plan of your own and follows it. Your other plans stay as they are, nothing is learned, and Undo takes it back."]:format(
			Kit.AccentHex() .. path.title .. "|r"))
		tooltip:AddLine(" ")
		Kit.TipPair(tooltip, L["Role"], B.RoleText(path.role))
		Kit.TipPair(tooltip, L["Situation"], B.SituationText(path.situation))
		Kit.TipText(tooltip, path.note)
		tooltip:AddLine(L["Suggested by EldoUI, checked on %s."]:format(path.checked), Kit.DIM[1], Kit.DIM[2], Kit.DIM[3], true)
	end
end

function M:CreateBuildBar(parent, opts)
	opts = opts or {}
	local bar = CreateFrame("Frame", nil, parent)
	bar.opts = opts
	bar:SetHeight(E.tokens.height.button)
	-- Results of a click: a toast where the click was.
	bar.notify = opts.notify or function(text, warn, action)
		Kit.Toast(bar, text, { warn = warn, action = action, maxWidth = 420 })
	end
	bar.category = Kit.Dropdown(bar, {
		width = 120,
		values = function()
			local list = {}
			for _, situation in ipairs(B.Situations(M:BuildsClass(Group(bar)))) do list[#list + 1] = { situation, B.SituationText(situation) } end
			return list
		end,
		get = function() return M:BuildSituation(Group(bar)) end,
		set = function(value) M:SetBuildSituation(value) end,
		tipTitle = L["Build category"],
		tip = L["Where you play: Recommended build copies the suggested path for it and your role."],
	})
	bar.recommend = Kit.Button(bar, L["Recommended build"], 150, E.tokens.height.button, function() Copy(bar) end,
		L["Recommended build"], RecommendTip(bar))
	Kit.FitButton(bar.recommend, 130)
	bar.import = Kit.Button(bar, L["Import build"], 110, E.tokens.height.button, function() M:ShowImportBox(bar.notify) end,
		L["Import build"], L["Paste a talent calculator link, a talent string, a talent loadout string or an EldoUI plan string. You see what it holds before it is saved as a plan; nothing is learned."])
	Kit.FitButton(bar.import, 100)
	bar.note = Kit.Text(bar, 12, "LEFT", "secondary")
	bar.note:SetWordWrap(false)
	bar.note:SetShown(not opts.compact)

	function bar.Update(own)
		local group = Group(own)
		local paths = #B.Situations(M:BuildsClass(group)) > 0
		own.category:SetShown(paths)
		own.recommend:SetShown(paths)
		local width, last = 0, nil
		local function Place(widget)
			widget:ClearAllPoints()
			if last then widget:SetPoint("LEFT", last, "RIGHT", GAP, 0) else widget:SetPoint("LEFT", own, "LEFT", 0, 0) end
			width = width + (last and GAP or 0) + (widget:GetWidth() or 0)
			last = widget
		end
		if paths then
			own.category:Refresh()
			Place(own.category)
			Place(own.recommend)
		end
		Place(own.import)
		local path = paths and M:RecommendedPath(group)
		own.recommend:SetEnabled(path ~= nil)
		if not opts.compact then
			own.note:ClearAllPoints()
			own.note:SetPoint("LEFT", last, "RIGHT", 12, 0)
			own.note:SetPoint("RIGHT", own, "RIGHT", 0, 0)
			if path then
				own.note:SetText(L["Suggested path: %s (%s)"]:format(Kit.AccentHex() .. path.title .. "|r", B.RoleText(path.role)))
			else
				own.note:SetText(L["Paste a talent calculator link, a talent string or a plan string to save it as a plan."])
			end
		end
		if opts.compact then own:SetWidth(math.max(width, 1)) end
		return width
	end
	return bar
end
