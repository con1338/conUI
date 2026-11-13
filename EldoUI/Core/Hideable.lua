-- Hiding EldoUI boxes: right-click a box and pick Hide, and it stays hidden
-- (also after a reload) until it is shown again: in move mode under
-- "Hidden (N)", on the Hidden boxes page under Modules, or with its Show
-- switch on its module's page. One setting per box, saved in the profile:
--   E.db.hidden[<mover name>] = true
-- Pieces with a switch of their own (the coordinate box) use that switch.
--
-- Every mover's box is hideable unless it is one of the frames the game
-- gives its own right-click (unit and group frames, action bars, auras,
-- chat, the minimap, bags), a window that opens on demand, a Blizzard frame
-- or another addon's frame. Unit and group frames always keep the game's
-- right-click: they never get a Hide entry, and nothing here ever touches
-- their clicks. Secure frames never get a menu.
--
-- The boxes EldoUI keeps for other addons' windows (a meter, a guide, a
-- quest tracker, the boss mods) are hidden from move mode and the Hidden
-- boxes page only:
-- Hide takes EldoUI's box away, and the addon's own window stays as that
-- addon shows it. Their windows keep their own right-click, and nothing of
-- theirs is written.
--
-- A module adds the right-click menu to a box the player sees:
--   E:RegisterHideable(frame, "EldoUI_CampPanel", { mouse = true })
-- and a box with a right-click menu of its own adds the entry to it:
--   E:AddHideEntries(root, "EldoUI_WaypointCoords")
-- A piece with its own on/off switch says so once:
--   E:SetHideableSetting("EldoUI_WaypointCoords", function() return not db.coordBox end, function(hidden) ... end)
-- The right-click lock (E.db.general.lockRightClick) makes the boxes ignore
-- right-click, so nothing is hidden by accident. Move mode's box menu is a
-- move tool and is not locked.
--
-- Presentation only: a hidden piece is a box EldoUI draws; nothing here
-- acts for the player. Written from scratch for EldoUI.
local _, E = ...
local L = E.L

E.defaults.hidden = {}
E.defaults.general.lockRightClick = false
E.defaults.general.hideNoticeShown = false

local settings = {} -- key -> { get = fn, set = fn }: pieces with a switch of their own
local veto = setmetatable({}, { __mode = "k" }) -- frame -> key: its OnShow is watched
local wanted = {}   -- key -> true: the module showed the frame while it was hidden
local hiding = {}   -- key -> true: our own Hide is running
local listeners = {}

-- Move-mode groups and modules whose boxes the game or the player handles
-- through their own clicks and switches: never hideable from a box.
local NEVER_GROUPS = { ["Unit frames"] = true, ["Group frames"] = true, ["Action bars"] = true }
local NEVER_MODULES = {
	Chat = true, ChatMessages = true, Messages = true, Minimap = true, Bags = true, BagsBlizzard = true,
	Tooltip = true, SystemUI = true, Maps = true,
}
-- Modules whose boxes stand in for another addon's window: hideable, but
-- only as EldoUI's box (no on-screen menu, the window is the addon's).
local BOX_ONLY_MODULES = { Integrations = true, DBM = true }
-- The same boxes by mover name, for movers made outside their module's setup.
local NEVER_MOVERS = {
	EldoUI_Minimap = true, EldoUI_QueueStatus = true, EldoUI_Chat = true, EldoUI_ChatRight = true,
	EldoUI_EIM = true, EldoUI_Tooltip = true, EldoUI_Popups = true, EldoUI_TopWidgets = true,
}

local function Hidden()
	local db = E.db
	if not db then return nil end
	db.hidden = type(db.hidden) == "table" and db.hidden or {}
	return db.hidden
end

-- Can this box be hidden from a right-click, the Hidden boxes page and the
-- Show switches?
-- Why a box can't be hidden ("unknown", "group", "module", "window",
-- "foreign"), or nil when it can.
function E:HideExclusion(key)
	if settings[key] then return nil end
	local mover = self.movers and self.movers[key]
	if not mover then return "unknown" end
	if mover.sample == false then return "window" end
	if NEVER_GROUPS[self:GetMoverGroup(mover)] then return "group" end
	if (mover.module and NEVER_MODULES[mover.module]) or NEVER_MOVERS[key] then return "module" end
	local frame = mover.frame
	local name = frame and frame.GetName and frame:GetName()
	-- A Blizzard frame (or another addon's) on a mover: its own switches decide.
	if type(name) == "string" and not name:find("^EldoUI") then return "foreign" end
	return nil
end

function E:CanHide(key)
	return self:HideExclusion(key) == nil
end

-- Is this one of the boxes EldoUI keeps for another addon's window?
function E:IsHideBoxOnly(key)
	local mover = self.movers and self.movers[key]
	return mover ~= nil and mover.module ~= nil and BOX_ONLY_MODULES[mover.module] == true
end

function E:IsHidden(key)
	local setting = settings[key]
	if setting then
		local ok, hidden = pcall(setting.get)
		return ok and hidden and true or false
	end
	local hidden = Hidden()
	return hidden ~= nil and hidden[key] == true and self:CanHide(key) or false
end

-- The box's name for menus and lists.
function E:HideableLabel(key)
	local mover = self.movers[key]
	return mover and L[mover.title] or key
end

-- Hide or show the frame of a piece. A frame the module shows while it is
-- hidden is hidden again at once; showing the piece again brings the frame
-- back only if its module wants it shown.
local function Target(key)
	local mover = E.movers[key]
	return mover and mover.frame
end

local function DoHide(key, frame)
	hiding[key] = true
	frame:Hide()
	hiding[key] = nil
end

local function Watch(key, frame)
	if veto[frame] then return end
	veto[frame] = key
	frame:HookScript("OnShow", function(f)
		local own = veto[f]
		if own and Hidden() and Hidden()[own] and E:CanHide(own) then
			wanted[own] = true
			E:RunOutOfCombat(function() if Hidden()[own] then DoHide(own, f) end end, "Hide:" .. own)
		end
	end)
	frame:HookScript("OnHide", function(f)
		local own = veto[f]
		if own and not hiding[own] then wanted[own] = nil end
	end)
end

local function Apply(key)
	if settings[key] then return end
	local frame = Target(key)
	if not frame then return end
	if E:IsHidden(key) then
		Watch(key, frame)
		if frame:IsShown() then
			wanted[key] = true
			E:RunOutOfCombat(function() if E:IsHidden(key) then DoHide(key, frame) end end, "Hide:" .. key)
		end
	elseif wanted[key] then
		wanted[key] = nil
		E:RunOutOfCombat(function() if not E:IsHidden(key) then frame:Show() end end, "Hide:" .. key)
	end
end

local function Changed(key)
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn, key)
		if not ok then geterrorhandler()(err) end
	end
	if E.RefreshMoveMode then E:RefreshMoveMode() end
	if E.RefreshConfig then E:RefreshConfig() end
end

-- fn(key): called after any piece is hidden or shown (key nil: all of them).
function E:RegisterHideListener(fn)
	if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

-- Hide (true) or show (false) a piece. Returns true when it can be hidden.
function E:SetHidden(key, hidden)
	if not self:CanHide(key) then return false end
	hidden = hidden and true or false
	local setting = settings[key]
	if setting then
		local ok, err = pcall(setting.set, hidden)
		if not ok then geterrorhandler()(err) end
	else
		local list = Hidden()
		if not list then return false end
		list[key] = hidden or nil
		Apply(key)
	end
	Changed(key)
	return true
end

-- A piece whose module has an on/off switch of its own: Hide writes that
-- switch, so the module page, the right-click and the Hidden boxes page agree.
function E:SetHideableSetting(key, get, set)
	if type(key) == "string" and type(get) == "function" and type(set) == "function" then
		settings[key] = { get = get, set = set }
	end
end

-- A mover was just created (Core/Movers.lua): a piece hidden in the
-- profile stays hidden from the start.
function E:ApplyHidden(key)
	local list = Hidden()
	if list and list[key] then Apply(key) end
end

-- Hidden pieces whose module is on, for move mode and the page.
function E:EachHiddenPiece()
	local list = {}
	for key, mover in pairs(self.movers) do
		local module = mover.module and self.modules[mover.module]
		if (not module or module.active) and self:CanHide(key) and self:IsHidden(key) then list[#list + 1] = key end
	end
	table.sort(list, function(a, b) return tostring(self:HideableLabel(a)) < tostring(self:HideableLabel(b)) end)
	return list
end

function E:CountHiddenPieces()
	return #self:EachHiddenPiece()
end

function E:ShowAllHidden()
	for _, key in ipairs(self:EachHiddenPiece()) do self:SetHidden(key, false) end
	local list = Hidden()
	-- Pieces of modules that are off come back too.
	if list then
		for key in pairs(list) do
			list[key] = nil
			Apply(key)
		end
	end
	Changed(nil)
end

---------------------------------------------------------------------------
-- The right-click lock
---------------------------------------------------------------------------
function E:IsRightClickLocked()
	return self.db and self.db.general and self.db.general.lockRightClick and true or false
end

function E:SetRightClickLocked(locked)
	if not (self.db and self.db.general) then return end
	self.db.general.lockRightClick = locked and true or false
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
	if self.RefreshConfig then self:RefreshConfig() end
end

---------------------------------------------------------------------------
-- Menus
---------------------------------------------------------------------------
-- Options… opens the box's own target (CreateMover opts.options: page,
-- row key, tab), else its module's page. Returns page, key, tab.
function E:HideableOptionsPage(key)
	local mover = self.movers[key]
	local target = mover and mover.options
	if type(target) == "table" and type(target.page) == "string" then return target.page, target.key, target.tab end
	local module = mover and mover.module and self.modules[mover.module]
	if not module or not (module.options or (self.styles and self.styles[module.name])) then return nil end
	return "module:" .. module.name
end

-- The one door from a box's Options… to the options window: move mode
-- ends, and the page opens scrolled to the row (or on the tab) when there
-- is one, like an options link.
function E:OpenMoveBoxOptions(page, row, tab)
	if not page or not self.OpenConfigFromMoveBox then return end
	if self:IsMoveMode() then self:ToggleMoveMode(false) end
	self:OpenConfigFromMoveBox(page, row, tab)
end

function E:OpenHideableOptions(key)
	self:OpenMoveBoxOptions(self:HideableOptionsPage(key))
end

local function Notice()
	local general = E.db and E.db.general
	if not general or general.hideNoticeShown then return end
	general.hideNoticeShown = true
	E:Print(L["Hidden. Show it again on the Hidden boxes page under Modules in /eui, or in move mode under Hidden."])
end

local function HideNow(key)
	if E:SetHidden(key, true) then Notice() end
end

-- The Hide entry at the bottom of a box's own menu. Adds nothing while the
-- right-click lock is on or the box can't be hidden.
function E:AddHideEntries(root, key)
	if type(root) ~= "table" or self:IsRightClickLocked() or not self:CanHide(key) then return end
	root:CreateButton(L["Hide"], function() HideNow(key) end)
end

-- The small menu of a box without one: its name, Options… and Hide.
function E:OpenHideMenu(owner, key)
	if self:IsRightClickLocked() or not self:CanHide(key) then return end
	self.UIKit.ContextMenu(owner, function(_, root)
		root:CreateTitle(self:HideableLabel(key))
		local options = root:CreateButton(L["Options…"], function() self:OpenHideableOptions(key) end)
		options:SetEnabled(self:HideableOptionsPage(key) ~= nil)
		self:AddHideEntries(root, key)
	end)
end

-- Can this frame get a Hide menu? Never a secure or protected frame, and
-- never one with the game's own right-click (unit and group frames).
local function MenuAllowed(frame)
	if type(frame) ~= "table" or not frame.HookScript then return false end
	if E.FrameCheck(frame, "IsForbidden") then return false end
	if E.FrameCheck(frame, "IsProtected") then return false end
	if frame.GetAttribute and (frame:GetAttribute("*type2") or frame:GetAttribute("type2") or frame:GetAttribute("unit")) then
		return false
	end
	return true
end

-- key: the mover name of the piece (or a function returning it, for frames
-- made before their mover). opts.mouse: the frame takes the mouse for it
-- (a display box that took none); without it a click-through frame stays
-- click-through. Returns true when the menu was added.
function E:RegisterHideable(frame, key, opts)
	if not MenuAllowed(frame) then return false end
	local function Key() return type(key) == "function" and key() or key end
	local resolved = Key()
	if type(resolved) == "string" and self.movers[resolved] and (not self:CanHide(resolved) or self:IsHideBoxOnly(resolved)) then
		return false
	end
	if frame.eldoHideKey then return true end
	frame.eldoHideKey = Key
	local restore = not (opts and opts.mouse) and self.UIKit and self.UIKit.KeepMouse and self.UIKit.KeepMouse(frame)
	frame:HookScript("OnMouseUp", function(f, button)
		if not E:IsHideClick(f, button) then return end
		local own = f.eldoHideKey()
		if type(own) == "string" then E:OpenHideMenu(f, own) end
	end)
	if restore then restore() end
	if opts and opts.mouse then frame:EnableMouse(true) end
	return true
end

-- True for the click that opens a registered frame's Hide menu (a
-- right-click outside move mode, the lock off), so the frame's own click
-- handler can leave it alone.
function E:IsHideClick(frame, button)
	if button ~= "RightButton" or type(frame) ~= "table" or not frame.eldoHideKey then return false end
	if self:IsMoveMode() or self:IsRightClickLocked() then return false end
	local key = frame.eldoHideKey()
	return type(key) == "string" and self:CanHide(key)
end

---------------------------------------------------------------------------
-- Profiles: a switch, a copy or an import re-applies every piece.
---------------------------------------------------------------------------
local function ApplyAll()
	for key in pairs(E.movers) do
		if not settings[key] then Apply(key) end
	end
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end
E.ApplyAllHidden = ApplyAll

if E.RefreshMovers then
	hooksecurefunc(E, "RefreshMovers", ApplyAll)
end

---------------------------------------------------------------------------
-- Show switches: the Hidden boxes page and each module's page
---------------------------------------------------------------------------
-- A settings table for the option rows: show.<key> is true while shown,
-- lockRightClick is the lock.
local showProxy = setmetatable({}, {
	__index = function(_, key) return not E:IsHidden(key) end,
	__newindex = function(_, key, value) E:SetHidden(key, not value) end,
})
local proxy = setmetatable({}, {
	__index = function(_, key)
		if key == "show" then return showProxy end
		if key == "lockRightClick" then return E:IsRightClickLocked() end
	end,
	__newindex = function(_, key, value)
		if key == "lockRightClick" then E:SetRightClickLocked(value) end
	end,
})
local function Root() return proxy end
E.HideableOptionsRoot = Root
local defaults = { lockRightClick = false, show = setmetatable({}, { __index = function() return true end }) }

local function ModuleTitle(key)
	local mover = E.movers[key]
	local module = mover and mover.module and E.modules[mover.module]
	return module and L[module.title or module.name] or nil
end

-- Show switches for a module's page: one per hideable box of the module
-- that has no switch of its own (a mover's enabledPath is one).
function E:GetHideableModuleOptions(module)
	if type(module) == "string" then module = self.modules[module] end
	local options = {}
	if not module then return options end
	local keys = {}
	for key, mover in pairs(self.movers) do
		if mover.module == module.name and not settings[key] and not mover.enabledPath and self:CanHide(key) then
			keys[#keys + 1] = key
		end
	end
	if #keys == 0 then return options end
	table.sort(keys, function(a, b) return tostring(self:HideableLabel(a)) < tostring(self:HideableLabel(b)) end)
	local boxOnly = BOX_ONLY_MODULES[module.name]
	options[1] = { type = "header", label = boxOnly and L["Boxes in move mode"] or L["On screen"], localized = true }
	for _, key in ipairs(keys) do
		local label = self:HideableLabel(key)
		local desc = boxOnly
			and L["Shows the %s box in move mode. Turned off, the box is gone from move mode and the addon's own window stays as that addon shows it; the Hidden boxes page under Modules lists every hidden box."]:format(label)
			or L["Shows %s on screen. Right-clicking it and choosing Hide turns this off; the Hidden boxes page under Modules lists every hidden box."]:format(label)
		options[#options + 1] = { type = "toggle", key = "show." .. key, root = Root, localized = true, noUndo = true,
			label = L["Show %s"]:format(label), desc = desc }
	end
	return options
end

local page, builtFor
-- The Hidden boxes page under Modules: every hidden box of a module that is
-- on, grouped like move mode, each with its Show switch.
function E:RegisterHiddenBoxesPage()
	if not self.RegisterConfigPage then return nil end
	local keys = {}
	for key in pairs(self.movers) do
		if self:CanHide(key) then keys[#keys + 1] = key end
	end
	table.sort(keys)
	local signature = table.concat(keys, ",")
	if page and signature == builtFor then return page end
	local function AnyHidden() return E:CountHiddenPieces() > 0 end
	local function Shown(key)
		local mover = E.movers[key]
		local module = mover and mover.module and E.modules[mover.module]
		return (not module or module.active) and E:IsHidden(key)
	end
	local options = {
		{ type = "description", label = "Boxes you hid with a right-click. Turn a box's switch on to show it again." },
		{ type = "toggle", key = "lockRightClick", label = "Lock right-click",
			desc = "EldoUI's boxes ignore right-click, so nothing is hidden by accident. Unit and group frames always keep the game's own right-click menu." },
		{ type = "description", empty = true, hidden = AnyHidden,
			label = "No box is hidden. Right-click a box on screen, or in move mode, and choose Hide to hide it." },
	}
	local byGroup = {}
	for _, key in ipairs(keys) do
		local group = self:GetMoverGroup(key) or "Other"
		byGroup[group] = byGroup[group] or {}
		table.insert(byGroup[group], key)
	end
	for _, group in ipairs(self.moverGroups) do
		local list = byGroup[group]
		if list then
			table.sort(list, function(a, b) return tostring(self:HideableLabel(a)) < tostring(self:HideableLabel(b)) end)
			options[#options + 1] = { type = "header", label = group, hidden = function()
				for _, key in ipairs(list) do if Shown(key) then return false end end
				return true
			end }
			for _, key in ipairs(list) do
				local label, module = self:HideableLabel(key), ModuleTitle(key)
				options[#options + 1] = { type = "toggle", key = "show." .. key, localized = true, noUndo = true,
					label = label,
					desc = module and L["Show %s (%s) again. It is hidden until you turn this on."]:format(label, module)
						or L["Show %s again. It is hidden until you turn this on."]:format(label),
					hidden = function() return not Shown(key) end }
			end
		end
	end
	options[#options + 1] = { type = "execute", label = "Show all", noUndo = true, disabled = function() return not AnyHidden() end,
		desc = "Show every hidden box again.", func = function() E:ShowAllHidden() end }
	local created = self:RegisterConfigPage("hidden", "Hidden boxes", options, Root, function() end, 1.9)
	created.desc = L["Every EldoUI box you hid, with a switch to show it again."]
	created.defaults = function() return defaults end
	if builtFor and created.options ~= options then
		created.options = options
		created.tabs = nil
	end
	page, builtFor = created, signature
	return created
end
-- Shown translated: L["Hidden boxes"], L["Show all"], L["Lock right-click"]
