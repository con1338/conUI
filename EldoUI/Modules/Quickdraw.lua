-- EldoUI Quickdraw: hold a key and a palette of your own actions
-- appears around the cursor (or the screen center). Point at an entry and
-- let go of the key to use it; let go on nothing, or press Escape, to
-- cancel. Up to 16 menus, each with its own key, in three shapes:
--   ring  entries on a circle (or an arc); the direction from the center
--         picks one, so a short flick is enough
--   fan   a strip; point at an entry, or step through it with the wheel
--   grid  fixed cells; the nearest one to the cursor is picked
-- Entries: spells, items, macros, mounts, raid target markers, world
-- markers, equipment sets, a "resurrection" entry that becomes whichever
-- resurrection spell the character knows, and one level of sub-menus.
--
-- Rules (Forever, Midnight restrictions):
--   * Every action is the player's own: it runs from the key release (or a
--     click on an entry) through a secure button and Blizzard's own action
--     types (spell, item, macro, raidtarget, worldmarker, equipmentset).
--     EldoUI decides nothing; it only shows what the key will use.
--   * The palettes are secure frames. They are built, sized, filled and
--     bound out of combat. In combat only the prepared menus work: the
--     restricted snippets below show and hide them and copy the picked
--     entry's attributes onto the key's button. Edits wait for combat to end.
--   * Cooldowns go to the cooldown widget as the game gives them (duration
--     objects); usability only desaturates an icon, and a secret answer
--     goes to SetVertexColorFromBoolean. Nothing is compared or computed.
--   * Keys are override bindings owned by the menu's button, set out of
--     combat, so nothing else's binding is changed for good. Escape and the
--     wheel, bound while a menu is open, belong to the cancel button.
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L

local MAX_MENUS = 16
local MAX_ENTRIES = 16
local PALETTE_SIZE = 4096  -- the palette is a large invisible frame, so the
                           -- restricted code can read the cursor anywhere

local M = E:NewModule("Quickdraw", {
	title = "Quickdraw",
	category = "Combat",
	desc = "Hold a key for a ring, fan or grid of your own spells, items, macros, mounts and markers; let go on one to use it.",
	frames = { "EldoUI_QuickdrawHeader" },
	movers = {},
	savedKeys = { "profile.modules.Quickdraw" },
	optionsPage = "module:Quickdraw",
	presets = { "Centre", "Clean", "Clicker", "Compact", "Flick", "Labelled" },
	defaults = {
		menus = {},            -- list of { name, key, layout, span, rotation, fanDir, steer, columns, entries }
		seeded = false,        -- the starter menu was added once
		editing = 1,           -- menu shown on the options page
		openAt = "cursor",     -- cursor | center
		offsetX = 0,
		offsetY = 0,
		release = "release",   -- release: use on key release | click: stays open, click an entry
		iconSize = 40,
		spacing = 8,
		scale = 100,           -- percent (v0.7 and older: a factor, 0.5-2)
		labels = false,
		cooldowns = true,
		unusable = "dim",      -- dim | hide | show
	},
})

local Secret = E.Secret

local function Plain(value)
	return not Secret(value) and type(value) ~= "nil"
end

---------------------------------------------------------------------------
-- Entries: what each kind uses, looks like and whether it is available.
---------------------------------------------------------------------------
local RAID_ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_%d"
local CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local SUBMENU_ICON = 134400
-- World marker n uses the raid icon of the same color.
local WORLD_TO_RAID = { 6, 4, 3, 7, 1, 2, 5, 8 }
-- Resurrection spells by class, the first one known is used.
-- Resurrection spells, first known wins; a list of ranks casts the highest
-- one known. A druid's Revive comes before Rebirth, so the out-of-combat
-- resurrection does not use the long cooldown of the combat one.
local RES_SPELLS = {
	2006,                                              -- Resurrection
	7328,                                              -- Redemption
	2008,                                              -- Ancestral Spirit
	{ 437138, 1237948, 1237949, 1237950, 1237951 },    -- Revive
	20484,                                             -- Rebirth
}
local RAID_NAMES = E:TranslateValues({ E.Key("Star"), E.Key("Circle"), E.Key("Diamond"), E.Key("Triangle"), E.Key("Moon"), E.Key("Square"), E.Key("Cross"), E.Key("Skull") })

local function SpellKnown(id)
	if not id then return false end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
		if ok and Plain(known) then return known and true or false end
	end
	return true
end

local function ResSpell()
	if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return nil end
	for _, line in ipairs(RES_SPELLS) do
		if type(line) == "table" then
			for index = #line, 1, -1 do
				if SpellKnown(line[index]) then return line[index] end
			end
		elseif SpellKnown(line) then
			return line
		end
	end
end

local function MountInfo(id)
	if not (id and C_MountJournal and C_MountJournal.GetMountInfoByID) then return nil end
	local name, spellID, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
	if not name then return nil end
	return name, spellID, icon, isCollected
end

local function MacroInfo(name)
	if not (name and GetMacroIndexByName and GetMacroInfo) then return nil end
	local index = GetMacroIndexByName(name)
	if not index or index == 0 then return nil end
	local macroName, icon = GetMacroInfo(index)
	return macroName, icon
end

local function EquipSetID(name)
	if not (name and C_EquipmentSet and C_EquipmentSet.GetEquipmentSetID) then return nil end
	return C_EquipmentSet.GetEquipmentSetID(name)
end

local function WorldMarkersAvailable()
	return PlaceRaidMarker ~= nil
end

-- Resolve an entry: attributes for the secure button, icon, label, whether
-- the character can use it at all, and its spell/item for cooldowns.
-- Returns nil for an entry that can't be resolved (deleted macro ...).
local function Resolve(entry, rankContext)
	local kind, value = entry.kind, entry.value
	local info = { attributes = {} }
	local a = info.attributes
	if kind == "spell" then
		local id = tonumber(value)
		if not id then return nil end
		local ranks = E:GetModule("ActionBars")
		if ranks and ranks.HighestKnownRank then
			if rankContext and not rankContext.scan and ranks.RankScan then rankContext.scan = ranks:RankScan() end
			id = ranks:HighestKnownRank(id, rankContext and rankContext.scan) or id
		end
		a.type, a.spell = "spell", id
		info.icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
		info.label = C_Spell.GetSpellName and C_Spell.GetSpellName(id) or L["Spell %s"]:format(id)
		info.available = SpellKnown(id)
		info.spell = id
	elseif kind == "item" then
		local id = tonumber(value)
		if not id then return nil end
		a.type, a.item = "item", "item:" .. id
		info.icon = C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
		info.label = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or L["Item %s"]:format(id)
		local count = C_Item.GetItemCount and C_Item.GetItemCount(id) or 0
		local equipped = C_Item.IsEquippedItem and C_Item.IsEquippedItem(id)
		info.available = (Plain(count) and count > 0) or (Plain(equipped) and equipped) or false
		info.item = id
	elseif kind == "macro" then
		local name, icon = MacroInfo(value)
		if not name then return nil end
		a.type, a.macro = "macro", name
		info.icon, info.label, info.available = icon, name, true
	elseif kind == "mount" then
		local name, spellID, icon, collected = MountInfo(tonumber(value))
		if not name or not spellID then return nil end
		a.type, a.spell = "spell", spellID
		info.icon, info.label, info.available = icon, name, collected and true or false
	elseif kind == "raidmarker" then
		local marker = tonumber(value) or 0
		a.type, a.unit = "raidtarget", "target"
		if marker == 0 then
			a.action = "clear"
			info.icon, info.label = CLEAR_ICON, L["Clear target marker"]
		else
			a.marker, a.action = marker, "toggle"
			info.icon, info.label = RAID_ICON:format(marker), RAID_NAMES[marker] or L["Marker %s"]:format(marker)
		end
		info.available = true
	elseif kind == "worldmarker" then
		if not WorldMarkersAvailable() then return nil end
		local marker = tonumber(value) or 0
		a.type = "worldmarker"
		if marker == 0 then
			a.action = "clear"
			info.icon, info.label = CLEAR_ICON, L["Clear all world markers"]
		else
			a.marker, a.action = marker, "toggle"
			info.icon = RAID_ICON:format(WORLD_TO_RAID[marker] or marker)
			info.label = L["World marker %d"]:format(marker)
		end
		info.available = true
	elseif kind == "equipset" then
		local setID = EquipSetID(value)
		a.type, a.equipmentset = "equipmentset", value
		info.label = value
		if setID and C_EquipmentSet.GetEquipmentSetInfo then
			local _, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
			info.icon = icon
		end
		info.available = setID ~= nil
	elseif kind == "res" then
		local id = ResSpell()
		info.label = L["Resurrection"]
		if id then
			a.type, a.spell = "spell", id
			info.icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)
			info.label = C_Spell.GetSpellName and C_Spell.GetSpellName(id) or info.label
			info.spell = id
		end
		info.icon = info.icon or 136080
		info.available = id ~= nil
	elseif kind == "submenu" then
		info.icon = entry.icon or SUBMENU_ICON
		info.label = entry.name or L["Sub-menu"]
		info.available = true
		info.submenu = true
	else
		return nil
	end
	info.icon = info.icon or SUBMENU_ICON
	return info
end
M.Resolve = Resolve

---------------------------------------------------------------------------
-- Settings helpers
---------------------------------------------------------------------------
local function NewMenu(name)
	return { name = name, key = "", layout = "ring", span = 360, rotation = 0, fanDir = "horizontal",
		steer = "pointer", columns = 4, entries = {} }
end

-- Scale is a percent, like Action Bars and the micro menu.
local SCALE_MIN, SCALE_MAX = 40, 150
M.SCALE_MIN, M.SCALE_MAX = SCALE_MIN, SCALE_MAX

-- The palette scale from the percent setting.
function M:ScaleFactor()
	local value = tonumber(self.db and self.db.scale) or 100
	return math.max(SCALE_MIN, math.min(SCALE_MAX, value)) / 100
end

-- Fill missing fields of every menu and drop broken ones (old versions, a
-- half-written profile), so the rest of the file can trust them.
function M:Normalize()
	local db = self.db
	-- One-time move of the old factor (0.5-2) to percent.
	local scale = tonumber(db.scale)
	if scale and scale <= 2 then db.scale = math.floor(scale * 100 + 0.5) end
	if type(db.menus) ~= "table" then db.menus = {} end
	db.noMenu = nil
	if not db.seeded then
		db.seeded = true
		if #db.menus == 0 then
			local menu = NewMenu(L["Markers"])
			for marker = 1, 8 do menu.entries[#menu.entries + 1] = { kind = "raidmarker", value = marker } end
			menu.entries[#menu.entries + 1] = { kind = "raidmarker", value = 0 }
			db.menus[1] = menu
		end
	end
	local clean = {}
	for _, menu in ipairs(db.menus) do
		if type(menu) == "table" and type(menu.entries) == "table" and #clean < MAX_MENUS then
			local fresh = NewMenu(menu.name or L["Menu %d"]:format(#clean + 1))
			for key, value in pairs(fresh) do
				if menu[key] == nil then menu[key] = value end
			end
			clean[#clean + 1] = menu
		end
	end
	if #clean ~= #db.menus then db.menus = clean end
	db.editing = math.max(1, math.min(tonumber(db.editing) or 1, math.max(#db.menus, 1)))
end

local function EditingIndex()
	local db = M.db
	if not db or type(db.menus) ~= "table" or #db.menus == 0 then return nil end
	local index = math.max(1, math.min(tonumber(db.editing) or 1, #db.menus))
	return index
end

-- A key path into the menu on the options page; a scratch key when there
-- is none (those rows are hidden then).
local function MenuKey(field)
	return function()
		local index = EditingIndex()
		if not index then return "noMenu." .. field end
		return ("menus.%d.%s"):format(index, field)
	end
end

---------------------------------------------------------------------------
-- Restricted snippets. `trig` is the menu's key button, `pal` its palette.
---------------------------------------------------------------------------
local ACTION_ATTRIBUTES = { "type", "spell", "item", "macro", "macrotext", "marker", "action", "unit", "equipmentset" }

local CLEAR_ACTION = ""
for _, name in ipairs(ACTION_ATTRIBUTES) do
	CLEAR_ACTION = CLEAR_ACTION .. ("\ttrig:SetAttribute(%q, nil)\n"):format(name)
end

local COPY_ACTION = ""
for _, name in ipairs(ACTION_ATTRIBUTES) do
	COPY_ACTION = COPY_ACTION .. ("\ttrig:SetAttribute(%q, pick:GetAttribute(%q))\n"):format(name, name)
end

local CLOSE = [[
	pal:Hide()
	for i = 1, (trig:GetAttribute("eldo-subs") or 0) do
		local sp = trig:GetFrameRef("s" .. i)
		if sp then sp:Hide() end
	end
	local owner = trig:GetFrameRef("cancel")
	if owner then owner:ClearBindings() end
	trig:SetAttribute("eldo-open", nil)
	trig:SetAttribute("eldo-wheel", 0)
]]

-- The entry the cursor (or the wheel) points at, into `pick`.
local PICK = [[
	local pick
	local n = pal:GetAttribute("eldo-n") or 0
	local wheel = trig:GetAttribute("eldo-wheel") or 0
	if wheel > 0 then
		pick = pal:GetFrameRef("e" .. wheel)
	else
		local mx, my = pal:GetMousePosition()
		if mx then
			local size = pal:GetAttribute("eldo-size") or 1
			local dx, dy = (mx - 0.5) * size, (my - 0.5) * size
			if trig:GetAttribute("eldo-mode") == "ring" then
				if dx * dx + dy * dy >= (trig:GetAttribute("eldo-dead") or 0) then
					local best
					for i = 1, n do
						local e = pal:GetFrameRef("e" .. i)
						if e then
							local score = dx * (e:GetAttribute("eldo-x") or 0) + dy * (e:GetAttribute("eldo-y") or 0)
							if not best or score > best then
								best = score
								pick = e
							end
						end
					end
				end
			else
				local best = trig:GetAttribute("eldo-reach") or 0
				for i = 1, n do
					local e = pal:GetFrameRef("e" .. i)
					if e then
						local ex, ey = dx - (e:GetAttribute("eldo-x") or 0), dy - (e:GetAttribute("eldo-y") or 0)
						local d = ex * ex + ey * ey
						if d <= best then
							best = d
							pick = e
						end
					end
				end
			end
		end
	end
]]

local OPEN_SUB = [[
	local sp = trig:GetFrameRef("s" .. sub)
	if sp then
		pal:Hide()
		sp:ClearAllPoints()
		sp:SetPoint("CENTER", "$cursor", "BOTTOMLEFT", 0, 0)
		sp:Show()
		trig:SetAttribute("eldo-open", 2)
	end
]]

-- The key's button: press opens, release uses the picked entry.
local TRIGGER_PRE = [[
	local trig, pal = self, self:GetFrameRef("palette")
	if not pal then return false end
]] .. CLEAR_ACTION .. [[
	if down then
		if trig:GetAttribute("eldo-open") then
]] .. CLOSE .. [[
			return false
		end
		local ox, oy = trig:GetAttribute("eldo-ox") or 0, trig:GetAttribute("eldo-oy") or 0
		pal:ClearAllPoints()
		if trig:GetAttribute("eldo-at") == "cursor" then
			pal:SetPoint("CENTER", "$cursor", "BOTTOMLEFT", ox, oy)
		else
			pal:SetPoint("CENTER", "$screen", "CENTER", ox, oy)
		end
		pal:Show()
		trig:SetAttribute("eldo-open", 1)
		trig:SetAttribute("eldo-wheel", 0)
		-- Escape and the wheel belong to the cancel button, never to the
		-- trigger: the trigger owns the menu's own key, and clearing its
		-- bindings would unbind that key until the next rebuild.
		local cancel = trig:GetFrameRef("cancel")
		if cancel then
			cancel:ClearBindings()
			cancel:SetBindingClick(true, "ESCAPE", cancel)
			local step = trig:GetFrameRef("step")
			if step and trig:GetAttribute("eldo-wheelon") then
				cancel:SetBindingClick(true, "MOUSEWHEELUP", step, "up")
				cancel:SetBindingClick(true, "MOUSEWHEELDOWN", step, "down")
			end
		end
		return false
	end
	if trig:GetAttribute("eldo-open") ~= 1 or trig:GetAttribute("eldo-release") ~= "release" then
		return false
	end
]] .. PICK .. [[
	if pick and pick:GetAttribute("eldo-sub") then
		local sub = pick:GetAttribute("eldo-sub")
]] .. OPEN_SUB .. [[
		return false
	end
]] .. CLOSE .. [[
	if not pick or not pick:GetAttribute("type") then return false end
]] .. COPY_ACTION

-- An entry clicked with the mouse: a sub-menu entry opens its palette, any
-- other entry runs its own action and the menu closes afterwards.
local ENTRY_PRE = [[
	local sub = self:GetAttribute("eldo-sub")
	if not sub then return end
	local trig = self:GetFrameRef("trigger")
	if not trig then return false end
	local pal = trig:GetFrameRef("palette")
]] .. OPEN_SUB .. [[
	return false
]]

local ENTRY_POST = [[
	local trig = self:GetFrameRef("trigger")
	if not trig then return end
	local pal = trig:GetFrameRef("palette")
]] .. CLOSE

-- Escape (an override binding while a menu is open).
local CANCEL_CLICK = [[
	if not down then return end
	local trig = self:GetFrameRef("trigger")
	if not trig then return end
	local pal = trig:GetFrameRef("palette")
]] .. CLOSE

-- Mouse wheel over a fan with wheel steering.
local STEP_CLICK = [[
	if not down then return end
	local trig = self:GetFrameRef("trigger")
	if not trig then return end
	local pal = trig:GetFrameRef("palette")
	local n = pal:GetAttribute("eldo-n") or 0
	if n == 0 then return end
	local w = trig:GetAttribute("eldo-wheel") or 0
	if button == "up" then w = w - 1 else w = w + 1 end
	if w < 1 then w = n elseif w > n then w = 1 end
	trig:SetAttribute("eldo-wheel", w)
]]

-- The restricted snippets, exposed read-only.
M.snippets = { CLOSE = CLOSE, TRIGGER_PRE = TRIGGER_PRE, ENTRY_PRE = ENTRY_PRE, ENTRY_POST = ENTRY_POST,
	CANCEL_CLICK = CANCEL_CLICK, STEP_CLICK = STEP_CLICK }

-- Restricted code failed to compile on one Forever build, so Quickdraw
-- runs a small snippet with the calls it needs first; if that fails it
-- stays off and says why instead of leaving keys that do nothing.
local PROBE = [[
	local ref = self:GetFrameRef("probe")
	local x, y = ref and ref:GetMousePosition()
	self:SetAttribute("eldo-probe", (x and 1 or 0) + 1)
]]

---------------------------------------------------------------------------
-- Secure frames
---------------------------------------------------------------------------
local header        -- owner of the wrapped scripts
local menus = {}    -- index -> { trigger, palette, cancel, step, subs = { palette ... } }
M.menus = menus    -- read-only
local probeFailed

local function SetRef(frame, label, ref)
	SecureHandlerSetFrameRef(frame, label, ref)
end

local function CreateHeader()
	if header then return not probeFailed end
	header = CreateFrame("Frame", "EldoUI_QuickdrawHeader", UIParent, "SecureHandlerBaseTemplate")
	local probe = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
	probe:SetSize(1, 1)
	SetRef(header, "probe", probe)
	local ok, err = pcall(SecureHandlerExecute, header, PROBE)
	if not ok then
		probeFailed = tostring(err)
		geterrorhandler()("EldoUI Quickdraw: this version of the game can't run the Quickdraw menu, so Quickdraw stays off: " .. probeFailed)
	end
	return not probeFailed
end

-- The look of one entry button: icon, border, cooldown, label, highlight.
local function SkinEntry(button)
	E:SetTemplate(button)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
	button.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
	E:TrimIcon(button.icon)
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button.cooldown:SetAllPoints(button.icon)
	if E.ApplyCooldownFont then E:ApplyCooldownFont(button.cooldown) end
	button.label = E:CreateText(button, E.tokens.size.small, "CENTER", "OVERLAY")
	button.label:SetPoint("TOP", button, "BOTTOM", 0, -2)
	button.selected = button:CreateTexture(nil, "OVERLAY")
	button.selected:SetPoint("TOPLEFT", -2, 2)
	button.selected:SetPoint("BOTTOMRIGHT", 2, -2)
	button.selected:SetColorTexture(1, 1, 1, 1)
	button.selected:SetDrawLayer("BACKGROUND", -1)
	button.selected:SetAlpha(0)
	-- A kit chevron marks a sub-menu.
	button.subMark = E.UIKit.Chevron(button, "right", 10, "OVERLAY")
	button.subMark:SetPoint("BOTTOMRIGHT", -2, 2)
	button.subMark:SetVertexColor(unpack(E.tokens.text.body))
end

local function CreatePalette(menu)
	local palette = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")
	palette:SetSize(PALETTE_SIZE, PALETTE_SIZE)
	palette:SetFrameStrata("DIALOG")
	palette:EnableMouse(false)
	palette:Hide()
	palette:SetAttribute("eldo-size", PALETTE_SIZE)
	palette.entries = {}
	palette.menu = menu
	SetRef(palette, "trigger", menu.trigger)
	palette:SetScript("OnShow", function(self) M:OnPaletteShow(self) end)
	palette:SetScript("OnHide", function(self) M:OnPaletteHide(self) end)
	return palette
end

local function EntryButton(palette, index)
	local button = palette.entries[index]
	if button then return button end
	button = CreateFrame("Button", nil, palette, "SecureActionButtonTemplate")
	-- Act on the release: with the game's "cast on key press" setting a
	-- secure button otherwise waits for a press it never receives.
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	SkinEntry(button)
	SetRef(button, "trigger", palette.menu.trigger)
	pcall(SecureHandlerWrapScript, button, "OnClick", header, ENTRY_PRE, ENTRY_POST)
	button:SetScript("OnEnter", function(self)
		if not self.info or E.FrameCheck(GameTooltip, "IsForbidden") then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if self.info.spell and GameTooltip.SetSpellByID then
			GameTooltip:SetSpellByID(self.info.spell)
		elseif self.info.item and GameTooltip.SetItemByID then
			GameTooltip:SetItemByID(self.info.item)
		else
			E.UIKit.TipTitle(GameTooltip, self.info.label or "")
		end
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end end)
	palette.entries[index] = button
	return button
end

local function NamedButton(name, template)
	local button = _G[name] or CreateFrame("Button", name, UIParent, template)
	return button
end

local function CreateMenuFrames(index)
	local menu = menus[index]
	if menu then return menu end
	menu = { index = index, subs = {} }
	local trigger = NamedButton("EldoUI_Quickdraw" .. index, "SecureActionButtonTemplate")
	trigger:SetSize(1, 1)
	trigger:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
	trigger:RegisterForClicks("AnyDown", "AnyUp")
	trigger:SetAttribute("useOnKeyDown", false)
	trigger:EnableMouse(false)
	menu.trigger = trigger
	local cancel = NamedButton("EldoUI_Quickdraw" .. index .. "Cancel", "SecureHandlerClickTemplate")
	menu.cancel = cancel
	cancel:RegisterForClicks("AnyDown")
	cancel:SetAttribute("_onclick", CANCEL_CLICK)
	cancel:SetSize(1, 1)
	cancel:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
	SetRef(cancel, "trigger", trigger)
	local step = NamedButton("EldoUI_Quickdraw" .. index .. "Step", "SecureHandlerClickTemplate")
	step:RegisterForClicks("AnyDown")
	step:SetAttribute("_onclick", STEP_CLICK)
	step:SetSize(1, 1)
	step:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
	SetRef(step, "trigger", trigger)
	menu.palette = CreatePalette(menu)
	SetRef(trigger, "palette", menu.palette)
	SetRef(trigger, "cancel", cancel)
	SetRef(trigger, "step", step)
	pcall(SecureHandlerWrapScript, trigger, "OnClick", header, TRIGGER_PRE)
	menus[index] = menu
	return menu
end

---------------------------------------------------------------------------
-- Layout: entry offsets from the palette center (EldoUI units at scale 1).
---------------------------------------------------------------------------
local function Layout(menuDB, count, sub)
	local db = M.db
	local size, gap = db.iconSize, db.spacing
	local step = size + gap
	local points = {}
	local layout = sub and "ring" or menuDB.layout
	if layout == "fan" and not sub then
		for i = 1, count do
			local offset = (i - (count + 1) / 2) * step
			if menuDB.fanDir == "vertical" then points[i] = { 0, -offset } else points[i] = { offset, 0 } end
		end
		return points, "nearest", (step * 0.75) ^ 2, 0
	elseif layout == "grid" and not sub then
		local columns = math.max(1, math.min(tonumber(menuDB.columns) or 4, count))
		local rows = math.ceil(count / columns)
		for i = 1, count do
			local col = (i - 1) % columns + 1
			local row = math.floor((i - 1) / columns) + 1
			points[i] = { (col - (columns + 1) / 2) * step, -(row - (rows + 1) / 2) * step }
		end
		return points, "nearest", (step * 0.75) ^ 2, 0
	end
	-- Ring (sub-menus are always a small full ring).
	local span = sub and 360 or math.max(30, math.min(tonumber(menuDB.span) or 360, 360))
	local rotation = sub and 0 or (tonumber(menuDB.rotation) or 0)
	local full = span >= 360
	local stepAngle = count > 1 and (full and 360 / count or span / (count - 1)) or 0
	local radius = size * 1.2
	if count > 1 and stepAngle > 0 then
		radius = math.max(radius, step / (2 * math.sin(math.rad(stepAngle) / 2)))
	end
	-- An arc is centered on the rotation (0 = top), a full ring starts there.
	local first = full and 0 or -span / 2
	for i = 1, count do
		local angle = math.rad(90 - rotation - (first + (i - 1) * stepAngle))
		points[i] = { radius * math.cos(angle), radius * math.sin(angle) }
	end
	return points, "ring", 0, (radius * 0.35) ^ 2
end

---------------------------------------------------------------------------
-- Building (out of combat)
---------------------------------------------------------------------------
local function ApplyAttributes(button, info)
	for _, name in ipairs(ACTION_ATTRIBUTES) do button:SetAttribute(name, nil) end
	for name, value in pairs(info.attributes) do button:SetAttribute(name, value) end
end

-- Fill one palette with `list` (resolved entries) laid out by `menuDB`.
local function FillPalette(palette, menuDB, list, sub)
	local db = M.db
	local points, mode, reach, dead = Layout(menuDB, #list, sub)
	palette:SetScale(M:ScaleFactor())
	palette.points, palette.mode, palette.reach, palette.dead = points, mode, reach, dead
	palette.list = list
	for index, item in ipairs(list) do
		local button = EntryButton(palette, index)
		local x, y = points[index][1], points[index][2]
		button:ClearAllPoints()
		button:SetSize(db.iconSize, db.iconSize)
		button:SetPoint("CENTER", palette, "CENTER", x, y)
		button:SetAttribute("eldo-x", x)
		button:SetAttribute("eldo-y", y)
		button:SetAttribute("eldo-sub", item.subIndex)
		ApplyAttributes(button, item.info)
		button.info = item.info
		button.icon:SetTexture(item.info.icon)
		button.label:SetText(item.info.label or "")
		button.label:SetShown(db.labels and true or false)
		E:SetFont(button.label, E.tokens.size.small)
		button.subMark:SetShown(item.info.submenu and true or false)
		button:Show()
		SetRef(palette, "e" .. index, button)
	end
	for index = #list + 1, #palette.entries do
		local button = palette.entries[index]
		button:Hide()
		button.info = nil
		for _, name in ipairs(ACTION_ATTRIBUTES) do button:SetAttribute(name, nil) end
		button:SetAttribute("eldo-sub", nil)
	end
	palette:SetAttribute("eldo-n", #list)
end

-- Resolved entries of a menu, with unavailable ones left out when the
-- player chose "hide".
local function ResolveList(entries, allowSub, rankContext)
	local list = {}
	for _, entry in ipairs(entries or {}) do
		if #list >= MAX_ENTRIES then break end
		if entry.kind ~= "submenu" or allowSub then
			local info = Resolve(entry, rankContext)
			if info and (info.available or M.db.unusable ~= "hide") then
				list[#list + 1] = { entry = entry, info = info }
			end
		end
	end
	return list
end

local function KeyOwned(key)
	return type(key) == "string" and key ~= ""
end

function M:BuildMenu(index, menuDB, rankContext)
	rankContext = rankContext or {}
	local menu = CreateMenuFrames(index)
	local db = self.db
	local trigger = menu.trigger
	menu.db = menuDB
	ClearOverrideBindings(trigger)
	ClearOverrideBindings(menu.cancel)
	-- Sub-menus: one palette each, in entry order.
	local list = ResolveList(menuDB.entries, true, rankContext)
	local subCount = 0
	for _, item in ipairs(list) do
		if item.info.submenu then
			subCount = subCount + 1
			local palette = menu.subs[subCount]
			if not palette then
				palette = CreatePalette(menu)
				menu.subs[subCount] = palette
			end
			palette.isSub = true
			FillPalette(palette, menuDB, ResolveList(item.entry.entries, false, rankContext), true)
			SetRef(trigger, "s" .. subCount, palette)
			item.subIndex = subCount
		end
	end
	for extra = subCount + 1, #menu.subs do menu.subs[extra]:Hide() end
	FillPalette(menu.palette, menuDB, list, false)
	local palette = menu.palette
	trigger:SetAttribute("eldo-subs", subCount)
	trigger:SetAttribute("eldo-mode", palette.mode)
	trigger:SetAttribute("eldo-reach", palette.reach)
	trigger:SetAttribute("eldo-dead", palette.dead)
	trigger:SetAttribute("eldo-at", db.openAt)
	trigger:SetAttribute("eldo-ox", db.offsetX)
	trigger:SetAttribute("eldo-oy", db.offsetY)
	trigger:SetAttribute("eldo-release", db.release)
	trigger:SetAttribute("eldo-wheelon", menuDB.layout == "fan" and menuDB.steer == "wheel" or nil)
	trigger:SetAttribute("eldo-open", nil)
	trigger:SetAttribute("eldo-wheel", 0)
	palette:Hide()
	for _, sub in ipairs(menu.subs) do sub:Hide() end
	if KeyOwned(menuDB.key) and #list > 0 then
		SetOverrideBindingClick(trigger, false, menuDB.key, trigger:GetName(), "LeftButton")
	end
end

function M:ReleaseMenu(index)
	local menu = menus[index]
	if not menu then return end
	ClearOverrideBindings(menu.trigger)
	ClearOverrideBindings(menu.cancel)
	menu.trigger:SetAttribute("eldo-open", nil)
	menu.palette:Hide()
	menu.palette:SetAttribute("eldo-n", 0)
	for _, sub in ipairs(menu.subs) do sub:Hide() end
	menu.db = nil
end

-- True while a palette of any menu is on screen.
function M:AnyMenuOpen()
	for _, menu in pairs(menus) do
		if menu.trigger:GetAttribute("eldo-open") then
			if menu.palette:IsShown() then return true end
			for _, sub in ipairs(menu.subs) do
				if sub:IsShown() then return true end
			end
		end
	end
	return false
end

-- Everything from the settings, out of combat; a change in combat waits.
function M:Rebuild()
	if InCombatLockdown() then
		if not self.rebuildQueued then
			self.rebuildQueued = true
			E:RunOutOfCombat(function()
				M.rebuildQueued = false
				M:Rebuild()
			end)
		end
		return
	end
	-- A menu the player has open (click mode, or a key still held) is left
	-- alone: rebuilding hides its palette. Try again once it is closed
	-- (looting while a click-mode menu is open closed it).
	if self.active and self:AnyMenuOpen() then
		self:QueueRebuild()
		return
	end
	self:Normalize()
	local on = self.active and CreateHeader()
	local rankContext = {}
	for index = 1, MAX_MENUS do
		local menuDB = on and self.db.menus[index]
		if menuDB then self:BuildMenu(index, menuDB, rankContext) else self:ReleaseMenu(index) end
	end
	if self.editor and self.editor:IsShown() then self:RefreshEditor(rankContext) end
end

---------------------------------------------------------------------------
-- Palette visuals (insecure, our own textures only): cooldowns, dimming and
-- the highlight of the entry the key would use. The pick in the restricted
-- code uses the same rules; this only shows it.
---------------------------------------------------------------------------
local WHITE, GREY

local function DimIcon(button, usable)
	if Secret(usable) then
		WHITE = WHITE or CreateColor(1, 1, 1, 1)
		GREY = GREY or CreateColor(0.4, 0.4, 0.4, 1)
		if button.icon.SetVertexColorFromBoolean then button.icon:SetVertexColorFromBoolean(usable, WHITE, GREY) end
		button.icon:SetDesaturated(false)
		return
	end
	button.icon:SetVertexColor(1, 1, 1, 1)
	button.icon:SetDesaturated(not usable)
end

local function UpdateEntryState(button)
	local info = button.info
	if not info then return end
	local db = M.db
	button.cooldown:Clear()
	if db.cooldowns then
		if info.spell and C_Spell.GetSpellCooldownDuration then
			local duration = C_Spell.GetSpellCooldownDuration(info.spell)
			if duration and button.cooldown.SetCooldownFromDurationObject then
				button.cooldown:SetCooldownFromDurationObject(duration, true)
			end
		elseif info.item and C_Item.GetItemCooldown then
			local start, duration = C_Item.GetItemCooldown(info.item)
			if start and duration then pcall(button.cooldown.SetCooldown, button.cooldown, start, duration) end
		end
	end
	if db.unusable == "show" then
		DimIcon(button, true)
		return
	end
	local usable = info.available
	if usable and info.spell and C_Spell.IsSpellUsable then
		usable = C_Spell.IsSpellUsable(info.spell)
	elseif usable and info.item and C_Item.IsUsableItem then
		usable = C_Item.IsUsableItem(info.item)
	end
	DimIcon(button, usable)
end

-- Where the palette center is, in UIParent units, worked out the same way
-- the restricted SetPoint placed it.
local function PaletteCentre(palette)
	local scale = palette:GetEffectiveScale()
	local trigger = palette.menu.trigger
	if palette.isSub then
		local x, y = GetCursorPosition()
		return x / scale, y / scale
	end
	local ox, oy = trigger:GetAttribute("eldo-ox") or 0, trigger:GetAttribute("eldo-oy") or 0
	if trigger:GetAttribute("eldo-at") == "cursor" then
		local x, y = GetCursorPosition()
		return x / scale + ox, y / scale + oy
	end
	return UIParent:GetWidth() * UIParent:GetEffectiveScale() / scale / 2 + ox,
		UIParent:GetHeight() * UIParent:GetEffectiveScale() / scale / 2 + oy
end

local PICK_STEP = 0.03

function M:OnPaletteShow(palette)
	palette.centreX, palette.centreY = PaletteCentre(palette)
	palette.picked = nil
	palette.elapsed = 1
	local r, g, b = unpack(E.media.accentColor)
	for index, button in ipairs(palette.entries) do
		if index <= #(palette.list or {}) then
			button.selected:SetColorTexture(r, g, b, 1)
			button.selected:SetAlpha(0)
			UpdateEntryState(button)
		end
	end
	-- The pick follows the cursor on the shared ticker while the palette
	-- is open (the palette itself is the subscription's key).
	E.Ticker:Subscribe(palette, PICK_STEP, function(elapsed) M:OnPaletteUpdate(palette, elapsed) end, M)
end

function M:OnPaletteHide(palette)
	E.Ticker:Unsubscribe(palette)
	if palette.picked then palette.picked.selected:SetAlpha(0) end
	palette.picked = nil
end

-- Mirror of the PICK snippet.
local function Picked(palette)
	local list = palette.list
	if not list or #list == 0 then return nil end
	local trigger = palette.menu.trigger
	local wheel = trigger:GetAttribute("eldo-wheel") or 0
	if not palette.isSub and wheel > 0 then return palette.entries[wheel] end
	local scale = palette:GetEffectiveScale()
	local x, y = GetCursorPosition()
	local dx, dy = x / scale - palette.centreX, y / scale - palette.centreY
	local points = palette.points
	local pick
	if palette.mode == "ring" then
		if dx * dx + dy * dy < palette.dead then return nil end
		local best
		for index = 1, #list do
			local score = dx * points[index][1] + dy * points[index][2]
			if not best or score > best then
				best = score
				pick = index
			end
		end
	else
		local best = palette.reach
		for index = 1, #list do
			local ex, ey = dx - points[index][1], dy - points[index][2]
			local d = ex * ex + ey * ey
			if d <= best then
				best = d
				pick = index
			end
		end
	end
	return pick and palette.entries[pick]
end

function M:OnPaletteUpdate(palette, elapsed)
	palette.elapsed = (palette.elapsed or 0) + elapsed
	if palette.elapsed < PICK_STEP then return end
	palette.elapsed = 0
	-- Sub-menus and click mode are clicked, so the mouse-over shows there.
	local trigger = palette.menu.trigger
	local clicking = palette.isSub or trigger:GetAttribute("eldo-release") ~= "release"
	local pick
	if clicking then
		for index = 1, #(palette.list or {}) do
			local button = palette.entries[index]
			if button:IsMouseOver() then pick = button end
		end
	else
		pick = Picked(palette)
	end
	if pick == palette.picked then return end
	if palette.picked then palette.picked.selected:SetAlpha(0) end
	palette.picked = pick
	if pick then pick.selected:SetAlpha(1) end
end

---------------------------------------------------------------------------
-- Editor window: menus, keys and entries. Out of combat only.
---------------------------------------------------------------------------
-- The shared kit's button (E.UIKit.Button: hover and press look); `tip`
-- set on it later shows on hover.
local function FlatButton(parent, width, height, text)
	local button = E.UIKit.Button(parent, text or "", { width = width, height = height })
	button:HookScript("OnEnter", function(self)
		if self.tip and not E.FrameCheck(GameTooltip, "IsForbidden") then
			E.UIKit.AnchorTooltip(self)
			E.UIKit.TipTitle(GameTooltip, self.tip, true)
			GameTooltip:Show()
		end
	end)
	button:HookScript("OnLeave", function()
		if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end
	end)
	return button
end

-- A notice: a toast in the editor while it is open, else a chat line.
local function Notify(text, warn)
	local editor = M.editor
	if editor and editor:IsShown() then
		E.UIKit.Toast(editor, text, { warn = warn })
	else
		E:Print(text)
	end
end

local function Editable()
	if InCombatLockdown() then
		Notify(L["Quickdraw menus can't be changed in combat; the prepared menus still work."], true)
		return false
	end
	return true
end

local function CurrentMenu()
	local index = EditingIndex()
	return index and M.db.menus[index], index
end

-- The list being edited: the menu's entries, or a sub-menu's.
local function EditList()
	local menu = CurrentMenu()
	if not menu then return nil end
	local sub = M.editingSub and menu.entries[M.editingSub]
	if sub and sub.kind == "submenu" then
		sub.entries = sub.entries or {}
		return sub.entries, sub
	end
	M.editingSub = nil
	return menu.entries
end

function M:AddEntry(entry)
	if not Editable() then return end
	local list = EditList()
	if not list then
		Notify(L["Make a menu first (New menu)."], true)
		return
	end
	if #list >= MAX_ENTRIES then
		Notify(L["A menu holds up to %d entries."]:format(MAX_ENTRIES), true)
		return
	end
	if entry.kind == "submenu" and self.editingSub then
		Notify(L["Sub-menus go one level deep."], true)
		return
	end
	list[#list + 1] = entry
	self:Rebuild()
end

-- Whatever the cursor holds (spellbook, bags, macro window, mount journal,
-- equipment manager) as an entry.
local function EntryFromCursor()
	local kind, a, b, c = GetCursorInfo()
	if kind == "spell" then
		local id = tonumber(c) or tonumber(b)
		if id then return { kind = "spell", value = id } end
	elseif kind == "item" then
		if tonumber(a) then return { kind = "item", value = tonumber(a) } end
	elseif kind == "macro" then
		local name = GetMacroInfo and GetMacroInfo(a)
		if name then return { kind = "macro", value = name } end
	elseif kind == "mount" then
		for _, id in ipairs({ a, b }) do
			if MountInfo(tonumber(id)) then return { kind = "mount", value = tonumber(id) } end
		end
	elseif kind == "equipmentset" then
		if a then return { kind = "equipset", value = a } end
	end
end

function M:DropOnEditor()
	local entry = EntryFromCursor()
	if not entry then
		if GetCursorInfo() then Notify(L["Quickdraw takes spells, items, macros, mounts and equipment sets."], true) end
		return
	end
	ClearCursor()
	self:AddEntry(entry)
end

local function MoveEntry(index, delta)
	if not Editable() then return end
	local list = EditList()
	local target = index + delta
	if not list or not list[target] then return end
	list[index], list[target] = list[target], list[index]
	if M.editingSub == index then M.editingSub = target elseif M.editingSub == target then M.editingSub = index end
	M:Rebuild()
end

local function RemoveEntry(index)
	if not Editable() then return end
	local list = EditList()
	if not list then return end
	table.remove(list, index)
	M.editingSub = nil
	M:Rebuild()
end

local function AddMenu()
	if not Editable() then return end
	local db = M.db
	if #db.menus >= MAX_MENUS then
		Notify(L["Up to %d menus."]:format(MAX_MENUS), true)
		return
	end
	db.menus[#db.menus + 1] = NewMenu(L["Menu %d"]:format(#db.menus + 1))
	db.editing = #db.menus
	M.editingSub = nil
	M:Rebuild()
	if E.RefreshConfig then E:RefreshConfig() end
end

-- Deletes the menu the question named, even when the player picked another
-- menu while the question was open.
local function DeleteMenu(menu)
	if not Editable() then return end
	local index
	for i, entry in ipairs(M.db.menus) do
		if entry == menu then index = i break end
	end
	if not index then return end
	local editing = M.db.editing or 1
	table.remove(M.db.menus, index)
	if editing > index then
		M.db.editing = editing - 1
	elseif editing == index then
		M.db.editing = math.max(1, index - 1)
	end
	M.editingSub = nil
	M:Rebuild()
	if E.RefreshConfig then E:RefreshConfig() end
	Notify(L["Deleted the menu %s."]:format(menu.name or ""))
end

local function ConfirmDeleteMenu()
	if not Editable() then return end
	local menu = CurrentMenu()
	if not menu then return end
	local count = #(menu.entries or {})
	E:ShowConfirm({ title = L["Delete menu"], accept = E:GameText(DELETE, L["Delete"]), danger = true,
		text = E:Plural(count, "Delete the menu %s and its %d entry?", "Delete the menu %s and its %d entries?"):format(menu.name or "", count)
			.. " " .. L["This can't be undone."],
		-- Combat may start while the question is open: DeleteMenu checks again.
		onAccept = function() DeleteMenu(menu) end })
end

local function AddMenuEntries(root)
	root:CreateTitle(L["Add to this menu"])
	local markers = root:CreateButton(L["Raid target marker"])
	for marker = 1, 8 do
		markers:CreateButton(RAID_NAMES[marker], function() M:AddEntry({ kind = "raidmarker", value = marker }) end)
	end
	markers:CreateButton(L["Clear target marker"], function() M:AddEntry({ kind = "raidmarker", value = 0 }) end)
	markers:CreateButton(L["All eight and clear"], function()
		for marker = 1, 8 do M:AddEntry({ kind = "raidmarker", value = marker }) end
		M:AddEntry({ kind = "raidmarker", value = 0 })
	end)
	if WorldMarkersAvailable() then
		local world = root:CreateButton(L["World marker"])
		for marker = 1, 8 do
			world:CreateButton(L["World marker %d"]:format(marker), function() M:AddEntry({ kind = "worldmarker", value = marker }) end)
		end
		world:CreateButton(L["Clear all world markers"], function() M:AddEntry({ kind = "worldmarker", value = 0 }) end)
	end
	root:CreateButton(L["Resurrection (whichever you know)"], function() M:AddEntry({ kind = "res" }) end)
	if C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs then
		local ids = C_EquipmentSet.GetEquipmentSetIDs() or {}
		if #ids > 0 then
			local sets = root:CreateButton(L["Equipment set"])
			for _, id in ipairs(ids) do
				local name = C_EquipmentSet.GetEquipmentSetInfo(id)
				if name then sets:CreateButton(name, function() M:AddEntry({ kind = "equipset", value = name }) end) end
			end
		end
	end
	if not M.editingSub then
		root:CreateButton(L["Sub-menu"], function()
			M:AddEntry({ kind = "submenu", name = L["Sub-menu"], entries = {} })
		end)
	end
end

local function EntryMenu(owner, index)
	local list = EditList()
	local entry = list and list[index]
	if not entry then return end
	E.UIKit.ContextMenu(owner, function(_, root)
		local info = Resolve(entry)
		root:CreateTitle(info and info.label or L["Entry"])
		if entry.kind == "submenu" then
			root:CreateButton(L["Edit its entries"], function()
				M.editingSub = index
				M:RefreshEditor()
			end)
		end
		if index > 1 then root:CreateButton(L["Move earlier"], function() MoveEntry(index, -1) end) end
		if list[index + 1] then root:CreateButton(L["Move later"], function() MoveEntry(index, 1) end) end
		root:CreateButton(E:TextHex("bad") .. L["Remove"] .. "|r", function() RemoveEntry(index) end)
	end)
end

-- Key capture: the next key (with modifiers) becomes the menu's key.
local IGNORED_KEYS = { LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true, LALT = true, RALT = true, UNKNOWN = true }

local function StartKeyCapture(button)
	if not Editable() then return end
	local editor = M.editor
	editor.capturing = true
	button.text:SetText(L["Press a key (Escape clears)"])
	editor:EnableKeyboard(true)
	editor:SetScript("OnKeyDown", function(self, key)
		if IGNORED_KEYS[key] then return end
		if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(false) end
		self:EnableKeyboard(false)
		self:SetScript("OnKeyDown", nil)
		self.capturing = false
		local menu = CurrentMenu()
		if menu and not InCombatLockdown() then
			if key == "ESCAPE" then
				menu.key = ""
				M:Rebuild()
			else
				local chord = CreateKeyChordStringUsingMetaKeyState and CreateKeyChordStringUsingMetaKeyState(key) or key
				M:ConfirmKey(menu, chord)
			end
		end
		M:RefreshEditor()
	end)
end

-- The readable name of a game binding, e.g. "Action Button 7".
local function BindingName(action)
	local name = GetBindingName and GetBindingName(action)
	if type(name) == "string" and name ~= "" then return name end
	return action
end

-- Give `chord` to `menu`. One key per menu: it is taken away from any other
-- Quickdraw menu.
function M:AssignKey(menu, chord)
	for _, other in ipairs(self.db.menus) do
		if other ~= menu and other.key == chord then other.key = "" end
	end
	menu.key = chord
	E:RunOutOfCombat(function() M:Rebuild() end)
	self:RefreshEditor()
end

-- A key the game already binds to something else asks first: the
-- menu then overrides that binding while Quickdraw is on.
function M:ConfirmKey(menu, chord)
	local action = GetBindingAction and GetBindingAction(chord)
	if type(action) ~= "string" or action == "" then
		self:AssignKey(menu, chord)
		return
	end
	local keyName = GetBindingText and GetBindingText(chord, "KEY_") or chord
	E:ShowConfirm({
		title = L["Key already in use"],
		text = L["%s is bound to %s.\n\nReplace: the menu \"%s\" takes the key while Quickdraw is on; the other binding works again when you give the menu another key.\nKeep: nothing changes."]:format(
			E:Highlight(keyName), E:Highlight(BindingName(action)), menu.name or "?"),
		accept = L["Replace"],
		cancel = L["Keep"],
		onAccept = function() M:AssignKey(menu, chord) end,
		onCancel = function() M:RefreshEditor() end,
	})
end

local function KeyLabel(key)
	if not KeyOwned(key) then return E:TokenHex(E.tokens.text.dim) .. L["No key"] .. "|r" end
	return GetBindingText and GetBindingText(key, "KEY_") or key
end

function M:CreateEditor()
	-- The shared tool window shell (E.UIKit.CreateToolWindow).
	local editor = E.UIKit.CreateToolWindow("EldoUI_QuickdrawEditor", { title = "Quickdraw", -- no-L: the module's name
		width = 560, height = 360, strata = "DIALOG" })
	editor.line = editor.headerLine

	-- Menu list on the left.
	editor.menuButtons = {}
	for index = 1, MAX_MENUS do
		local button = FlatButton(editor, 150, 18, "")
		button:SetPoint("TOPLEFT", 10, -42 - (index - 1) * 19)
		button.text:ClearAllPoints()
		button.text:SetPoint("LEFT", 6, 0)
		button.text:SetJustifyH("LEFT")
		button.text:SetWidth(138)
		button:SetScript("OnClick", function()
			M.db.editing = index
			M.editingSub = nil
			M:RefreshEditor()
			if E.RefreshConfig then E:RefreshConfig() end
		end)
		editor.menuButtons[index] = button
	end
	editor.newMenu = FlatButton(editor, 150, 20, L["New menu"])
	editor.newMenu:SetScript("OnClick", AddMenu)

	-- The selected menu on the right.
	local right = 174
	editor.nameLabel = E.UIKit.Text(editor, E.tokens.size.label, "LEFT")
	editor.nameLabel:SetPoint("TOPLEFT", right, -44)
	editor.nameLabel:SetText(L["Name"])
	editor.name = CreateFrame("EditBox", nil, editor)
	editor.name:SetSize(170, 20)
	editor.name:SetPoint("LEFT", editor.nameLabel, "LEFT", 44, 0)
	editor.name:SetAutoFocus(false)
	editor.name:SetMaxLetters(24)
	editor.name:SetFontObject(ChatFontNormal)
	editor.name:SetTextInsets(4, 4, 0, 0)
	E:SetTemplate(editor.name)
	E:SetFont(editor.name, E.tokens.size.label)
	local function SaveName(box)
		local menu, sub = CurrentMenu(), nil
		if M.editingSub and menu then sub = menu.entries[M.editingSub] end
		local text = strtrim(box:GetText() or "")
		if text ~= "" and menu then
			if sub then sub.name = text else menu.name = text end
			M:RefreshEditor()
			if not InCombatLockdown() then M:Rebuild() end
		end
		box:ClearFocus()
	end
	editor.name:SetScript("OnEnterPressed", SaveName)
	editor.name:SetScript("OnEditFocusLost", SaveName)
	editor.name:SetScript("OnEscapePressed", function(box) box:ClearFocus() end)

	editor.key = FlatButton(editor, 200, 20, "")
	editor.key:SetPoint("TOPLEFT", right, -70)
	editor.key.tip = L["Click, then press the key (with Shift, Ctrl or Alt if you like) that opens this menu. Escape clears it."]
	editor.key:SetScript("OnClick", function(button) StartKeyCapture(button) end)
	editor.delete = FlatButton(editor, 100, 20, L["Delete menu"])
	E.UIKit.SetButtonKind(editor.delete, "danger")
	editor.delete:SetPoint("LEFT", editor.key, "RIGHT", 8, 0)
	editor.delete:SetScript("OnClick", ConfirmDeleteMenu)
	editor.delete.tip = L["Delete this menu and its entries. Asks first."]
	editor.back = FlatButton(editor, 100, 20, L["Back"])
	-- A kit chevron before the label instead of the letter <.
	editor.back.arrow = E.UIKit.Chevron(editor.back, "left", 9)
	editor.back.arrow:SetPoint("RIGHT", editor.back.text, "LEFT", -3, 0)
	editor.back:SetPoint("LEFT", editor.key, "RIGHT", 8, 0)
	editor.back:SetScript("OnClick", function()
		M.editingSub = nil
		M:RefreshEditor()
	end)

	editor.hint = E.UIKit.Text(editor, E.tokens.size.small, "LEFT", "secondary")
	editor.hint:SetPoint("TOPLEFT", right, -98)
	editor.hint:SetWidth(370)
	editor.hint:SetWordWrap(true)

	-- Entry slots; the last visible one takes drops.
	editor.slots = {}
	for index = 1, MAX_ENTRIES + 1 do
		local slot = CreateFrame("Button", nil, editor)
		slot:SetSize(40, 40)
		local col, row = (index - 1) % 8, math.floor((index - 1) / 8)
		-- Under the help line, however many lines it wraps to.
		slot:SetPoint("TOPLEFT", editor.hint, "BOTTOMLEFT", col * 46, -8 - row * 46)
		E:SetTemplate(slot)
		slot.icon = slot:CreateTexture(nil, "ARTWORK")
		slot.icon:SetPoint("TOPLEFT", E.pixel, -E.pixel)
		slot.icon:SetPoint("BOTTOMRIGHT", -E.pixel, E.pixel)
		E:TrimIcon(slot.icon)
		slot.plus = E:CreateText(slot, E.tokens.size.display)
		slot.plus:SetPoint("CENTER")
		slot.plus:SetText("+")
		slot.subMark = E.UIKit.Chevron(slot, "right", 10, "OVERLAY")
		slot.subMark:SetPoint("BOTTOMRIGHT", -2, 2)
		slot.subMark:SetVertexColor(unpack(E.tokens.text.body))
		slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		slot:RegisterForDrag("LeftButton")
		slot:SetScript("OnReceiveDrag", function() M:DropOnEditor() end)
		slot:SetScript("OnClick", function(button, mouse)
			if E:IsOptionsLinkClick(button, mouse) then return end
			if GetCursorInfo() then
				M:DropOnEditor()
			elseif button.empty then
				E.UIKit.ContextMenu(button, function(_, root) AddMenuEntries(root) end)
			elseif mouse == "RightButton" or not button.isSub then
				EntryMenu(button, button.index)
			else
				M.editingSub = button.index
				M:RefreshEditor()
			end
		end)
		slot:SetScript("OnEnter", function(button)
			button:SetBackdropBorderColor(unpack(E.media.accentColor))
			if E.FrameCheck(GameTooltip, "IsForbidden") then return end
			local sr, sg, sb = unpack(E.tokens.text.secondary)
			E.UIKit.AnchorTooltip(button)
			if button.empty then
				E.UIKit.TipTitle(GameTooltip, L["Add an entry"])
				E:TooltipHint(GameTooltip, { L["Drop"], L["a spell, item, macro, mount or equipment set"] }, { L["Click"], L["markers, resurrection and sub-menus"] })
			else
				E.UIKit.TipTitle(GameTooltip, button.label or "")
				E:TooltipHint(GameTooltip, button.isSub and { L["Click"], L["edit its entries"] } or nil,
					{ button.isSub and L["Right-click"] or L["Click"], L["move or remove"] })
			end
			GameTooltip:Show()
		end)
		slot:SetScript("OnLeave", function(button)
			button:SetBackdropBorderColor(unpack(E.media.borderColor))
			if not E.FrameCheck(GameTooltip, "IsForbidden") then GameTooltip:Hide() end
		end)
		E:BindOptionsLink(slot, { page = "module:Quickdraw" })
		editor.slots[index] = slot
	end
	-- The whole window takes drops too.
	editor:SetScript("OnReceiveDrag", function() M:DropOnEditor() end)
	editor:SetScript("OnMouseUp", function() if GetCursorInfo() then M:DropOnEditor() end end)

	editor.combat = E.UIKit.Text(editor, E.tokens.size.label, "LEFT", "warn")
	editor.combat:SetPoint("BOTTOMLEFT", right, 12)
	editor.combat:SetText(L["In combat: the menus work, edits wait until combat ends."])

	editor:HookScript("OnShow", function() M:RefreshEditor() end)
	editor:HookScript("OnHide", function(frame)
		if frame.capturing then
			frame.capturing = false
			frame:EnableKeyboard(false)
			frame:SetScript("OnKeyDown", nil)
		end
		frame.name:ClearFocus()
	end)
	self.editor = editor
end

function M:RefreshEditor(rankContext)
	local editor = self.editor
	if not editor then return end
	rankContext = rankContext or {}
	self:Normalize()
	local db = self.db
	local accent = E.media.accentText
	local current = EditingIndex()
	for index, button in ipairs(editor.menuButtons) do
		local menu = db.menus[index]
		button:SetShown(menu ~= nil)
		if menu then
			button.text:SetText(("%s  %s%s|r"):format(menu.name or "?", E:TokenHex(E.tokens.text.dim), KeyOwned(menu.key) and KeyLabel(menu.key) or ""))
			if index == current then button.text:SetTextColor(unpack(accent)) else button.text:SetTextColor(1, 1, 1) end
		end
	end
	editor.newMenu:ClearAllPoints()
	editor.newMenu:SetPoint("TOPLEFT", 10, -42 - #db.menus * 19 - 4)
	editor.newMenu:SetShown(#db.menus < MAX_MENUS)

	local menu = current and db.menus[current]
	local list, sub = EditList()
	local hasMenu = menu ~= nil
	editor.nameLabel:SetShown(hasMenu)
	editor.name:SetShown(hasMenu)
	editor.key:SetShown(hasMenu and not sub)
	editor.delete:SetShown(hasMenu and not sub)
	editor.back:SetShown(sub ~= nil)
	if not editor.name:HasFocus() then editor.name:SetText(sub and sub.name or (menu and menu.name) or "") end
	if not editor.capturing then editor.key.text:SetText(menu and L["Key: %s"]:format(KeyLabel(menu.key)) or "") end
	if not hasMenu then
		editor.hint:SetText(L["No menus yet. Click New menu to make one."])
	elseif sub then
		editor.hint:SetText(L["Sub-menu of %s: it opens where you let go of (or click) its entry, and you click one of these to use it."]:format(menu.name))
	else
		editor.hint:SetText(L["Drag spells, items, macros, mounts and equipment sets onto the slots (or this window). Click the + for markers, resurrection and sub-menus. Hold the key, point, let go."])
	end
	-- The window grows when the help line wraps to more lines (Large text).
	editor.hint:SetHeight(math.max(1, editor.hint:GetStringHeight() or 0))
	local rows = math.ceil((MAX_ENTRIES + 1) / 8)
	editor:SetHeight(math.max(360, math.ceil(98 + (editor.hint:GetStringHeight() or 0) + 8 + rows * 46 + 36)))
	for index, slot in ipairs(editor.slots) do
		local entry = list and list[index]
		slot.index = index
		if entry then
			local info = Resolve(entry, rankContext)
			slot.empty = false
			slot.isSub = entry.kind == "submenu"
			slot.label = info and info.label or L["Not found"]
			slot.icon:SetTexture(info and info.icon or SUBMENU_ICON)
			slot.icon:SetDesaturated(not (info and info.available))
			slot.icon:Show()
			slot.plus:Hide()
			slot.subMark:SetShown(slot.isSub)
			slot:Show()
		elseif list and index == #list + 1 and #list < MAX_ENTRIES then
			slot.empty, slot.isSub, slot.label = true, false, nil
			slot.icon:Hide()
			slot.plus:Show()
			slot.plus:SetTextColor(unpack(accent))
			slot.subMark:Hide()
			slot:Show()
		else
			slot:Hide()
		end
	end
	editor.combat:SetShown(InCombatLockdown() and true or false)
end

function M:ToggleEditor(show)
	if not self.active then
		E:Print(E:ModuleOffHint("Quickdraw"))
		return
	end
	if probeFailed then
		E:Print(L["Quickdraw can't run on this version of the game, so it is turned off for now."])
		return
	end
	if not self.editor then self:CreateEditor() end
	if show == nil then show = not self.editor:IsShown() end
	self.editor:SetShown(show)
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnInitialize()
	self:Normalize()
	E:AddCommand("quickdraw", "open the Quickdraw menu editor", function() M:ToggleEditor() end, "Tools")
end

function M:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() M:Rebuild() end)
	-- Things that change what an entry resolves to (a new spell, a bag item,
	-- an edited macro or equipment set); rebuilt out of combat.
	for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "BAG_UPDATE_DELAYED", "UPDATE_MACROS", "EQUIPMENT_SETS_CHANGED", "NEW_MOUNT_ADDED" }) do
		self:RegisterEvent(event, function() M:QueueRebuild() end)
	end
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		if M.editor and M.editor:IsShown() then M:RefreshEditor() end
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if M.editor and M.editor:IsShown() then M:RefreshEditor() end
	end)
	self:Rebuild()
end

function M:QueueRebuild()
	if self.rebuildPending then return end
	self.rebuildPending = true
	C_Timer.After(0.5, function()
		M.rebuildPending = false
		if M.active then M:Rebuild() end
	end)
end

function M:OnDisable()
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "BAG_UPDATE_DELAYED", "UPDATE_MACROS",
		"EQUIPMENT_SETS_CHANGED", "NEW_MOUNT_ADDED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		self:UnregisterEvent(event)
	end
	if self.editor then self.editor:Hide() end
	E.Ticker:UnsubscribeOwner(M)
	-- active is false: every menu lets go of its key.
	self:Rebuild()
end

function M:OnProfileChanged()
	self:Normalize()
	if self.active then self:Rebuild() end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
local function NoMenu() return EditingIndex() == nil end
local function MenuField(field)
	local index = EditingIndex()
	return index and M.db.menus[index][field]
end

local function MenuValues()
	local values = {}
	for index, menu in ipairs(M.db and M.db.menus or {}) do values[index] = ("%d. %s"):format(index, menu.name or "?") end
	return values
end

M.options = {
	{ type = "tab", label = "Menus" },
	{ type = "description", label = "Hold a menu's key to show its entries around the cursor; point at one and let go to use it. Escape cancels. Works in combat." },
	{ type = "description", label = "Quickdraw can't run on this version of the game, so it is turned off for now.", tone = "warning",
		hidden = function() return not probeFailed end },
	{ type = "execute", label = "Open the menu editor", desc = "Make menus, set their keys and drag spells, items, macros and mounts onto them (/eui quickdraw).",
		func = function() M:ToggleEditor(true) end },
	{ type = "header", label = "Menu shape" },
	{ type = "description", label = "No menus yet: open the editor and click New menu.", hidden = function() return not NoMenu() end },
	{ type = "select", key = "editing", label = "Menu", values = MenuValues, hidden = NoMenu,
		desc = "Which menu the rows below change." },
	{ type = "select", key = MenuKey("layout"), label = "Shape", hidden = NoMenu,
		values = { ring = "Ring (point in a direction)", fan = "Fan (a strip)", grid = "Grid (cells)" },
		desc = "Ring: the direction from the center picks an entry, so a short flick is enough. Fan: a row or column; point at an entry or use the wheel. Grid: the cell nearest the cursor." },
	{ type = "range", key = MenuKey("span"), label = "Ring angle", min = 90, max = 360, step = 15,
		hidden = function() return NoMenu() or MenuField("layout") ~= "ring" end,
		desc = "How much of the circle the entries use. 360 is a full ring; less makes an arc." },
	{ type = "range", key = MenuKey("rotation"), label = "Ring rotation", min = 0, max = 345, step = 15,
		hidden = function() return NoMenu() or MenuField("layout") ~= "ring" end,
		desc = "Turns the ring: 0 puts the first entry (or the middle of an arc) at the top, clockwise." },
	{ type = "select", key = MenuKey("fanDir"), label = "Fan direction", values = { horizontal = "Row", vertical = "Column" },
		hidden = function() return NoMenu() or MenuField("layout") ~= "fan" end, desc = "A row (left to right) or a column (top to bottom)." },
	{ type = "select", key = MenuKey("steer"), label = "Fan steering", values = { pointer = "Point at it", wheel = "Mouse wheel" },
		hidden = function() return NoMenu() or MenuField("layout") ~= "fan" end,
		desc = "Point at an entry, or roll the mouse wheel to step through the entries while the key is held." },
	{ type = "range", key = MenuKey("columns"), label = "Grid columns", min = 2, max = 8, step = 1,
		hidden = function() return NoMenu() or MenuField("layout") ~= "grid" end, desc = "How many cells per row." },

	{ type = "tab", label = "Look and behavior" },
	{ type = "header", label = "Opening and firing" },
	{ type = "select", key = "openAt", label = "Opens at", values = { cursor = "The cursor", center = "Screen center" },
		desc = "Where a menu appears when you press its key." },
	{ type = "select", key = "release", label = "Use an entry by", values = { release = "Letting go of the key", click = "Clicking it" },
		desc = "Letting go: point and release the key. Clicking: the menu stays open after you let go; click an entry, press the key again or Escape to close." },
	{ type = "cog", label = "Offset", desc = "Move where menus open, in pixels.", options = {
		{ type = "range", unit = "px", key = "offsetX", label = "X offset", min = -400, max = 400, step = 1, desc = "Moves the menu center right (positive) or left." },
		{ type = "range", unit = "px", key = "offsetY", label = "Y offset", min = -400, max = 400, step = 1, desc = "Moves the menu center up (positive) or down." },
	} },
	{ type = "header", label = "Look" },
	{ type = "range", unit = "px", key = "iconSize", label = "Icon size", min = 24, max = 64, step = 1, desc = "Size of each entry in pixels." },
	{ type = "range", unit = "px", key = "spacing", label = "Spacing", min = 0, max = 24, step = 1, desc = "Gap between entries (a ring grows with it)." },
	{ type = "range", key = "scale", label = "Scale", unit = "%", min = SCALE_MIN, max = SCALE_MAX, step = 5, desc = "Size of the whole menu in percent (100 = normal size)." },
	{ type = "toggle", key = "labels", label = "Labels", desc = "The name of each entry under its icon." },
	{ type = "toggle", key = "cooldowns", label = "Cooldown swipes", desc = "Spells and items show their cooldown." },
	{ type = "select", key = "unusable", label = "Entries you can't use", values = { dim = "Grayed out", hide = "Left out", show = "Shown normally" },
		desc = "Grayed out: unknown spells, items you don't carry and entries on cooldown or out of mana are gray. Left out: spells you don't know and items you don't have are not in the menu at all." },
}

---------------------------------------------------------------------------
-- Style presets: the look and behavior, never your menus or keys.
---------------------------------------------------------------------------
E:RegisterStyles("Quickdraw", {
	{ key = "Flick", title = "Flick", desc = "At the cursor, use on release, medium icons, no labels.",
		settings = { openAt = "cursor", release = "release", iconSize = 40, spacing = 8, scale = 100, labels = false, cooldowns = true, unusable = "dim" } },
	{ key = "Compact", title = "Compact", desc = "Small, tight icons for quick muscle memory.",
		settings = { openAt = "cursor", release = "release", iconSize = 30, spacing = 4, scale = 100, labels = false, cooldowns = true } },
	{ key = "Labelled", title = "Labeled", desc = "Bigger icons with their names, for menus you use now and then.",
		settings = { openAt = "cursor", release = "release", iconSize = 44, spacing = 22, scale = 100, labels = true, cooldowns = true } },
	{ key = "Centre", title = "Screen center", desc = "Opens in the middle of the screen, a little larger.",
		settings = { openAt = "center", offsetX = 0, offsetY = 0, release = "release", iconSize = 44, spacing = 10, scale = 110, labels = false } },
	{ key = "Clicker", title = "Click palette", desc = "Stays open after the key: click an entry. Unusable entries left out.",
		settings = { openAt = "cursor", release = "click", iconSize = 40, spacing = 8, labels = true, unusable = "hide" } },
	{ key = "Clean", title = "Clean", desc = "No cooldown swipes or labels, nothing grayed out.",
		settings = { labels = false, cooldowns = false, unusable = "show", iconSize = 38, spacing = 8 } },
})
