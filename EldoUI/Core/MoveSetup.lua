-- Move mode: what setup is on screen, which frames can be picked, and the
-- layout choices of a box's right-click menu.
--
--   E:SetupIdentity()       the setup in short parts: the layout (its
--                           family, "Legacy: <title>" with the nearest
--                           family, or one of My layouts), the role, the
--                           skin and the Blizzard windows choice.
--   E:MoveSetupLines()      two short lines for the move panel: the EldoUI
--                           version, the layout (built-in or imported) and
--                           how many frames were dragged from it, and the
--                           frame selected in move mode; the skin, role,
--                           Blizzard windows and UI amount. Ready for a
--                           screenshot.
--   E:MoveSetupSummary()    the same in full for "Copy setup", with the
--                           screen, the UI and text scale, Blizzard's Edit
--                           Mode layout number and the frame check below.
--                           Nothing from the account or the character.
--   E:MoverCoverage()       every registered frame with why it can or can't
--                           be picked in move mode right now: { name, title,
--                           state, shown }. state: "box" (it has its box),
--                           "view" (it shows on screen, but the frames list
--                           leaves it out: All frames shows it), "hidden"
--                           (you hid it), "box-hidden" (its box is hidden
--                           until move mode ends), "off" (its frame or
--                           module is off). Sorted by title. The move
--                           panel's Find a frame list (Core/Movers.lua)
--                           shows these rows.
--   E:ShowMoveSetupCopy()   the summary in a box to copy.
--
-- Layout choices in a box's menu (Horizontal, Vertical, Grid, Blizzard
-- default, as each frame supports them). A module registers them for its
-- mover; every choice writes the frame's existing settings, so the options
-- page and the menu always agree:
--   E:SetMoverLayouts(name, {
--       get = function() return "horizontal" end, -- the choice in use, or nil
--       set = function(key) end,                  -- runs out of combat
--       choices = { { key = "horizontal", label = "Horizontal", desc = "..." }, ... },
--       options: a target table with page ("module:X"), key ("row.key") and tab ("Tab") for Options…
--       beforeOptions = function() end, -- optional, before Options… opens (pick a bar)
--       steps = { -- optional: Size, Spacing and similar submenus
--           { label = "Size", values = { 28, 32, 36 }, get = function() end,
--             set = function(value) end, format = "%d px" }, ...
--       },
--       store = function() return settingsTable end, -- optional, with keys:
--       keys = { "perRow", "size" },  -- what "Undo changes" puts back
--       apply = function() end,       -- after Undo wrote them back
--       snapshot = function() end, restore = function(saved) end, -- or both by hand
--   })
-- "Undo changes" in move mode puts every frame's layout choices back with
-- its position: E:MoverLayoutsSnapshot() when move mode starts,
-- E:MoverLayoutsChanged(saved) and E:RestoreMoverLayouts(saved).
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local MS = {}
E.MoveSetup = MS -- exposed for inspection

local layouts = {} -- mover name -> spec

function E:SetMoverLayouts(name, spec)
	if type(name) ~= "string" then return end
	if type(spec) ~= "table" or type(spec.choices) ~= "table" or type(spec.set) ~= "function" then
		layouts[name] = nil
		return
	end
	layouts[name] = spec
end

function E:GetMoverLayouts(name)
	return layouts[name]
end

local function SafeGet(spec)
	if type(spec.get) ~= "function" then return nil end
	local ok, key = pcall(spec.get)
	return ok and key or nil
end

-- Pick a layout choice for a mover: out of combat, and the panel and the
-- open options window follow.
function E:SetMoverLayout(name, key)
	local spec = layouts[name]
	if not spec then return false end
	local known = false
	for _, choice in ipairs(spec.choices) do
		if choice.key == key then known = true end
	end
	if not known then return false end
	self:RunOutOfCombat(function()
		local ok, err = pcall(spec.set, key)
		if not ok then geterrorhandler()(err) end
		if E.RefreshConfig then E:RefreshConfig() end
		local mover = E.movers[name]
		if mover and E:IsMoveMode() and E.SelectMover and mover.overlay:IsShown() then E:SelectMover(mover) end
	end, "MoverLayout:" .. name)
	return true
end

function E:GetMoverLayout(name)
	local spec = layouts[name]
	return spec and SafeGet(spec) or nil
end

-- The Layout submenu of a box's right-click menu (Core/Movers.lua).
function E:AddMoverLayoutEntries(root, mover)
	local spec = mover and layouts[mover.name]
	if not spec then return end
	local sub = root:CreateButton(L["Layout"])
	for _, choice in ipairs(spec.choices) do
		local radio = sub:CreateRadio(L[choice.label], function() return SafeGet(spec) == choice.key end,
			function() E:SetMoverLayout(mover.name, choice.key) end)
		if choice.desc then
			radio:SetTooltip(function(tooltip)
				E.UIKit.TipTitle(tooltip, L[choice.label])
				E.UIKit.TipText(tooltip, L[choice.desc])
			end)
		end
	end
	return sub
end

-- Size, Spacing and the other step submenus of a box's menu.
local function StepLabel(step, value)
	if type(step.format) == "function" then return step.format(value) end
	if type(step.format) == "string" then return L[step.format]:format(value) end
	return tostring(value)
end

function E:SetMoverStep(name, index, value)
	local spec = layouts[name]
	local step = spec and type(spec.steps) == "table" and spec.steps[index]
	if not step or type(step.set) ~= "function" then return false end
	self:RunOutOfCombat(function()
		local ok, err = pcall(step.set, value)
		if not ok then geterrorhandler()(err) end
		if E.RefreshConfig then E:RefreshConfig() end
		local mover = E.movers[name]
		if mover and E:IsMoveMode() and E.SelectMover and mover.overlay:IsShown() then E:SelectMover(mover) end
	end, "MoverStep:" .. name .. ":" .. index)
	return true
end

function E:AddMoverStepEntries(root, mover)
	local spec = mover and layouts[mover.name]
	if not spec or type(spec.steps) ~= "table" then return end
	for index, step in ipairs(spec.steps) do
		if type(step.values) == "table" and type(step.get) == "function" then
			local sub = root:CreateButton(L[step.label])
			for _, value in ipairs(step.values) do
				sub:CreateRadio(StepLabel(step, value), function()
					local ok, current = pcall(step.get)
					return ok and current == value
				end, function() E:SetMoverStep(mover.name, index, value) end)
			end
		end
	end
end

-- What every box's layout choices are now, for "Undo changes".
local function Snapshot(spec)
	if type(spec.snapshot) == "function" then
		local ok, saved = pcall(spec.snapshot)
		return ok and saved or nil
	end
	if type(spec.store) ~= "function" or type(spec.keys) ~= "table" then return nil end
	local ok, store = pcall(spec.store)
	if not ok or type(store) ~= "table" then return nil end
	local saved = {}
	for _, key in ipairs(spec.keys) do
		local value = store[key]
		saved[key] = type(value) == "table" and CopyTable(value) or value
	end
	return saved
end

function E:MoverLayoutsSnapshot()
	local all = {}
	for name, spec in pairs(layouts) do all[name] = Snapshot(spec) end
	return all
end

function E:MoverLayoutsChanged(saved)
	if type(saved) ~= "table" then return false end
	for name, spec in pairs(layouts) do
		if saved[name] ~= nil and not E.DeepEqual(saved[name], Snapshot(spec)) then return true end
	end
	return false
end

-- Write the saved choices back; frames whose choices did not change are
-- left alone. Runs out of combat (move mode is never on in combat).
function E:RestoreMoverLayouts(saved)
	if type(saved) ~= "table" then return 0 end
	local changed = 0
	for name, spec in pairs(layouts) do
		local before = saved[name]
		if before ~= nil and not E.DeepEqual(before, Snapshot(spec)) then
			changed = changed + 1
			local ok, err = pcall(function()
				if type(spec.restore) == "function" then
					spec.restore(CopyTable(before))
				else
					local store = spec.store()
					for _, key in ipairs(spec.keys) do
						local value = before[key]
						store[key] = type(value) == "table" and CopyTable(value) or value
					end
					if type(spec.apply) == "function" then spec.apply() end
				end
			end)
			if not ok then geterrorhandler()(err) end
		end
	end
	if changed > 0 and E.RefreshConfig then E:RefreshConfig() end
	return changed
end

-- Where a box's Options… goes: the frame's own settings, else the page of
-- its module (Core/Hideable.lua). nil when there is none.
function E:MoverOptionsTarget(name)
	local spec = layouts[name]
	if spec and type(spec.options) == "table" and type(spec.options.page) == "string" then
		return spec.options.page, spec.options.key, spec.options.tab
	end
	if self.HideableOptionsPage then return self:HideableOptionsPage(name) end
	return nil
end

function E:OpenMoverOptions(name)
	local spec = layouts[name]
	if spec and type(spec.beforeOptions) == "function" then
		local ok, err = pcall(spec.beforeOptions)
		if not ok then geterrorhandler()(err) end
	end
	if spec and type(spec.options) == "table" and type(spec.options.page) == "string" then
		self:OpenMoveBoxOptions(spec.options.page, spec.options.key, spec.options.tab)
		return
	end
	if self.OpenHideableOptions then self:OpenHideableOptions(name) end
end

---------------------------------------------------------------------------
-- The setup on screen
---------------------------------------------------------------------------
function MS.LayoutTitle(key)
	return E:LayoutTitle(key)
end

function MS.LayoutKind(key)
	local layout = key and E.layouts and E.layouts[key]
	if not layout then return L["custom"] end
	return layout.imported and L["imported"] or L["built-in"]
end

-- Frames dragged away from the layout's places (saved positions).
function MS.MovedCount()
	local count = 0
	for _, pos in pairs(E.db and E.db.movers or {}) do
		if type(pos) == "table" then count = count + 1 end
	end
	return count
end

function MS.SkinTitle()
	local general = E.db.general
	local style = E.ArtStyle and E:ArtStyle() or general.artStyle
	local info = E.artStyleInfo and E.artStyleInfo[style]
	local title = info and L[info.title] or tostring(style)
	if general.skinFollow then title = L["%s (from the layout)"]:format(title) end
	return title
end

function MS.RoleTitle()
	local role = E.GetRole and E:GetRole() or "none"
	local profile = role ~= "none" and E.roleProfiles and E.roleProfiles[role]
	local title = profile and L[profile.title or role] or L["None"]
	if profile and E.db.general.roleClass then title = L["%s, class layer"]:format(title) end
	return title
end

function MS.AmountTitle()
	local UA = E.UIAmount
	if not (UA and E.UIAmountMatch) then return L["Custom"] end
	local ok, level = pcall(E.UIAmountMatch, E)
	if not ok or not level then return L["Custom"] end
	return UA.Title(level)
end

function MS.WindowsTitle()
	local mode = E.BlizzardWindowsMode and E:BlizzardWindowsMode() or "keep"
	local titles = E.Appearance and E.Appearance.WINDOWS and E.Appearance.WINDOWS.titles or {}
	return L[titles[mode] or "Keep as set"]
end

-- The layout part: the family a built-in layout belongs to, a legacy
-- layout with its nearest family, or a layout of your own by its title.
function MS.LayoutText(key)
	local layout = type(key) == "string" and E.layouts[key]
	if not layout or E:IsLegacyLayout(key) then return E:LayoutIdentity(key) end
	if layout.imported then return E:LayoutTitle(key) end
	local family = E:LayoutFamily(key)
	return family and E:LayoutFamilyTitle(family) or E:LayoutTitle(key)
end

function E:SetupIdentity()
	local key = self.db.general.layout
	return {
		layout = key,
		legacy = self:IsLegacyLayout(key) or nil,
		text = MS.LayoutText(key),
		kind = MS.LayoutKind(key),
		role = MS.RoleTitle(),
		skin = MS.SkinTitle(),
		windows = MS.WindowsTitle(),
		amount = MS.AmountTitle(),
	}
end

function MS.PackTitle()
	local OV = E.Overview
	if not (OV and OV.CurrentPack) then return nil end
	local ok, key = pcall(OV.CurrentPack)
	local pack = ok and key and E.packs and E.packs[key]
	return pack and L[pack.title] or nil
end

local SEP = "  ·  "

function E:MoveSetupLines()
	local id = self:SetupIdentity()
	local moved = MS.MovedCount()
	local layout = id.legacy and id.text or ("%s (%s)"):format(id.text, id.kind)
	local first = ("EldoUI %s%s%s"):format(tostring(self.version), SEP, layout)
	if moved > 0 then
		first = first .. SEP .. self:Plural(moved, "%d frame moved", "%d frames moved"):format(moved)
	end
	-- In move mode: the frame the panel works on, so a screenshot names it.
	local selected = self.GetSelectedMover and self:GetSelectedMover()
	if selected then first = first .. SEP .. L["Selected: %s"]:format(L[selected.title]) end
	local second = table.concat({
		L["Skin: %s"]:format(id.skin),
		L["Role: %s"]:format(id.role),
		L["Blizzard windows: %s"]:format(id.windows),
		L["UI amount: %s"]:format(id.amount),
	}, SEP)
	return first, second
end

local function EditModeLayout()
	if not (C_EditMode and C_EditMode.GetLayouts) then return nil end
	local ok, info = pcall(C_EditMode.GetLayouts)
	if not ok or type(info) ~= "table" then return nil end
	return info.activeLayout
end

-- Every registered frame and whether it can be picked in move mode now.
function E:MoverCoverage()
	local list = {}
	local moveMode = self:IsMoveMode()
	-- The player's own group and title filters only tidy the boxes for a
	-- moment; they do not count here.
	for name, mover in pairs(self.movers or {}) do
		local module = mover.module and self.modules[mover.module]
		local on = not module or module.active
		local frame = mover.frame
		local shown = on and frame ~= nil and frame.IsVisible ~= nil and frame:IsVisible() and true or false
		local state
		if self.IsHidden and self:IsHidden(name) then
			state = "hidden"
		elseif not on or not mover:IsShown() then
			state = "off"
		elseif moveMode and self.MoverBoxHidden and self:MoverBoxHidden(name) then
			state = "box-hidden"
		elseif self.MoverInMoveView and not self:MoverInMoveView(mover) then
			state = "view"
		else
			state = "box"
		end
		list[#list + 1] = { name = name, title = tostring(L[mover.title] or mover.title or name), state = state, shown = shown }
	end
	table.sort(list, function(a, b)
		if a.title ~= b.title then return a.title < b.title end
		return a.name < b.name
	end)
	return list
end

local STATE_TEXT = {
	box = "has its box",
	view = "shows on screen; All frames lists it",
	hidden = "hidden by you (Hidden in the frames list brings it back)",
	["box-hidden"] = "box hidden until move mode ends",
	off = "off",
}
-- Shown translated: L["has its box"], L["shows on screen; All frames lists it"],
-- L["hidden by you (Hidden in the frames list brings it back)"],
-- L["box hidden until move mode ends"], L["off"]

function E:MoveSetupSummary()
	local general = self.db.general
	local first, second = self:MoveSetupLines()
	local lines = { first, second }
	local pack = MS.PackTitle()
	if pack then lines[#lines + 1] = L["Look: %s"]:format(pack) end
	lines[#lines + 1] = L["Layout key: %s"]:format(tostring(general.layout))
	local width, height = GetPhysicalScreenSize()
	lines[#lines + 1] = L["Screen: %dx%d, UI scale %d%%, text %d%%"]:format(width or 0, height or 0,
		math.floor((UIParent:GetEffectiveScale() or 1) * 100 + 0.5), math.floor((self.TextScale and self:TextScale() or 1) * 100 + 0.5))
	local editMode = EditModeLayout()
	if editMode then lines[#lines + 1] = L["Blizzard Edit Mode layout: %d"]:format(editMode) end
	local counts, outside = {}, {}
	for _, row in ipairs(self:MoverCoverage()) do
		counts[row.state] = (counts[row.state] or 0) + 1
		-- Listed by name: frames on screen right now that have no box in
		-- this view (the ones a screenshot shows without one).
		if row.shown and (row.state == "view" or row.state == "box-hidden" or row.state == "hidden") then
			outside[#outside + 1] = ("  %s: %s"):format(row.title, L[STATE_TEXT[row.state]])
		end
	end
	lines[#lines + 1] = L["Frames with a box: %d. Outside this view: %d. Hidden: %d. Off: %d."]:format( -- no-plural
		counts.box or 0, (counts.view or 0) + (counts["box-hidden"] or 0), counts.hidden or 0, counts.off or 0)
	for _, line in ipairs(outside) do lines[#lines + 1] = line end
	return table.concat(lines, "\n")
end

function E:ShowMoveSetupCopy()
	if not self.ShowCopyBox then return end
	self:ShowCopyBox(L["Your EldoUI setup"], L["Press Ctrl+C to copy, then paste it where you report a layout problem."], self:MoveSetupSummary())
end
