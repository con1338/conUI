-- EldoUI combat HUD kit: shared helpers for the modules that skin and place
-- Blizzard's own combat displays (Cooldown Manager, damage meter, swing
-- timer, loss of control, combat text, mirror and quest timers, death
-- recap). Nothing here computes combat data: it changes how Blizzard's
-- frames look and where they sit, and hands on the cooldowns the game
-- itself reports.
--
--   K.Pin(frame, spec)        keep a Blizzard frame on EldoUI's anchor/scale/size
--   K.Unpin(frame)            give the frame back (best effort, see below)
--   K.Holder(module, name, title, point, w, h[, opts])   a frame with an EldoUI mover
--                                                (opts go to E:CreateMover, e.g. sizeKeys)
--   K.Parent(frame, parent)   reparent and remember the original parent
--   K.Alpha0 / K.Font / K.TexCoord / K.Backdrop / K.BarTexture
--                             skin steps that record how to undo themselves
--   K.Undo(group)             run every recorded undo step of a group
--   K.Visibility(key, ...)    fader on the shared visibility engine (Core/Visibility.lua)
--   K.SpellFlags(spellID)     the game's own cooldown flags of one of your spells
--   K.ItemActive(item, slot)  the game's own "cooldown runs" flag of an item
--   K.Cooldowns               the one cooldown source: events, readers, swipes
--   K.CooldownStack           what hangs above and below the main cooldown row,
--                             and which side of a bar is clear of it
--
-- Taint notes (Core/Skin.lua rules apply here too):
--   * Edit Mode systems replace SetPoint, ClearAllPoints and SetScale with Lua
--     overrides that write snap state into the frame and call into the Edit
--     Mode manager. EldoUI never calls those overrides: it uses the plain
--     widget methods Blizzard keeps as SetPointBase / ClearAllPointsBase /
--     SetScaleBase, so Edit Mode's own tables stay untouched.
--   * Blizzard code that re-anchors a frame is followed with hooksecurefunc;
--     the hook checks the element switch every time it runs.
--   * No field is ever written into a Blizzard frame; per-frame state lives in
--     local weak tables.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local K = {}
E.CombatKit = K

local issecret = issecretvalue or function() return false end

-- A hidden parent for frames the player chose to hide (the core's, so
-- E:IsBlizzardFrameHidden knows them).
K.hider = E.BlizzardKeep.hider

---------------------------------------------------------------------------
-- Small utilities
---------------------------------------------------------------------------
function K.Usable(frame)
	return E:SkinUsable(frame)
end

-- True when none of the values is a secret (safe for math and compares).
function K.Plain(...)
	for i = 1, select("#", ...) do
		if issecret((select(i, ...))) then return false end
	end
	return true
end

function K.EditModeActive()
	local manager = EditModeManagerFrame
	return manager and manager.IsEditModeActive and manager:IsEditModeActive() or false
end

-- The plain widget method behind an Edit Mode override.
local function Raw(frame, method)
	return frame[method .. "Base"] or frame[method]
end
function K.ClearPoints(frame) Raw(frame, "ClearAllPoints")(frame) end
function K.SetPoint(frame, ...) Raw(frame, "SetPoint")(frame, ...) end
function K.SetScale(frame, scale) Raw(frame, "SetScale")(frame, scale) end

-- Run fn now, or after combat when the frame is protected.
function K.Safe(frame, fn)
	if frame and E.FrameCheck(frame, "IsProtected") and InCombatLockdown() then
		E:RunOutOfCombat(fn)
		return false
	end
	fn()
	return true
end

-- The theme font on a FontString, keeping its size unless one is given.
local function FontSize(fs, size)
	if size then return size end
	local _, current = fs:GetFont()
	if current and K.Plain(current) and current > 0 then return current end
	return 12
end

---------------------------------------------------------------------------
-- Undo records: every skin step stores how to put the region back, once
-- per region and kind. K.Undo(group) restores a whole element.
---------------------------------------------------------------------------
local records = {}   -- group -> { { region, kind, restore }, ... }
local recorded = setmetatable({}, { __mode = "k" }) -- region -> group -> kind -> true

-- True when `region` already has its restore step for this group and kind:
-- callers check first, so a region skinned again builds no new closure.
local function Recorded(group, region, kind)
	local seen = recorded[region]
	seen = seen and seen[group]
	return seen ~= nil and seen[kind] == true
end
K.Recorded = Recorded

local function Record(group, region, kind, restore)
	local seen = recorded[region]
	if not seen then
		seen = {}
		recorded[region] = seen
	end
	local kinds = seen[group]
	if not kinds then
		kinds = {}
		seen[group] = kinds
	end
	if kinds[kind] then return end
	kinds[kind] = true
	K.records = (K.records or 0) + 1
	records[group] = records[group] or {}
	table.insert(records[group], { region = region, group = group, kind = kind, restore = restore })
end

function K.Undo(group)
	local list = records[group]
	if not list then return end
	local pending = {}
	for i = #list, 1, -1 do
		local entry = list[i]
		local ok, result = pcall(entry.restore)
		if not ok then geterrorhandler()(result) end
		if ok and result == false then
			table.insert(pending, 1, entry)
		else
			local seen = recorded[entry.region]
			if seen and seen[entry.group] then seen[entry.group][entry.kind] = nil end
		end
	end
	records[group] = #pending > 0 and pending or nil
	return #pending
end

-- Make Blizzard art invisible (never hidden or reparented).
function K.Alpha0(group, ...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		if type(region) == "table" and region.SetAlpha and not E.FrameCheck(region, "IsForbidden") then
			if not Recorded(group, region, "alpha") then
				local alpha = region:GetAlpha()
				Record(group, region, "alpha", function() region:SetAlpha(K.Plain(alpha) and alpha or 1) end)
			end
			region:SetAlpha(0)
		end
	end
end

-- Every texture of a frame (not its children) invisible, except `keep`.
function K.StripTextures(group, frame, keep)
	if not K.Usable(frame) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") and not (keep and keep[region]) then
			K.Alpha0(group, region)
		end
	end
end

function K.Font(group, fs, size, outline, font)
	if type(fs) ~= "table" or not fs.SetFont then return end
	if not Recorded(group, fs, "font") then
		local oldFont, oldSize, oldFlags = fs:GetFont()
		local sx, sy = fs:GetShadowOffset()
		Record(group, fs, "font", function()
			if oldFont then fs:SetFont(oldFont, oldSize, oldFlags or "") end
			if sx then fs:SetShadowOffset(sx, sy) end
		end)
	end
	fs:SetFont(font or E.media.font, FontSize(fs, size), outline or E.db.general.fontOutline or "")
	fs:SetShadowOffset(0, 0)
end

-- Icon crop; `zoom` is the share cut from each edge (0.08 = DESIGN.md default).
function K.TexCoord(group, texture, zoom)
	if type(texture) ~= "table" or not texture.SetTexCoord then return end
	if not Recorded(group, texture, "coord") then
		local coords = { texture:GetTexCoord() }
		Record(group, texture, "coord", function()
			if #coords == 8 and K.Plain(unpack(coords)) then texture:SetTexCoord(unpack(coords)) else texture:SetTexCoord(0, 1, 0, 1) end
		end)
	end
	texture:SetTexCoord(E:IconCoords(zoom))
end

-- Masks give Blizzard's Cooldown Manager icons their rounded corners.
function K.RemoveMasks(group, frame, texture)
	if not (K.Usable(frame) and texture and texture.RemoveMaskTexture) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("MaskTexture") then
			local mask = region
			if not Recorded(group, mask, "mask") then
				Record(group, mask, "mask", function() pcall(texture.AddMaskTexture, texture, mask) end)
			end
			pcall(texture.RemoveMaskTexture, texture, mask)
		end
	end
end

-- An EldoUI box behind `target` (or around `anchor`), one per target. A
-- solid box (not `transparent`) frames an icon.
local backdrops = setmetatable({}, { __mode = "k" })
local RING_OUTSIDE = { outside = true }

function K.Backdrop(group, target, anchor, inset, transparent)
	if not K.Usable(target) then return end
	local bd = backdrops[target]
	if not bd then
		bd = CreateFrame("Frame", nil, target)
		bd:SetFrameLevel(math.max(target:GetFrameLevel() - 1, 0))
		backdrops[target] = bd
	end
	inset = inset or E.pixel
	anchor = anchor or target
	bd:ClearAllPoints()
	bd:SetPoint("TOPLEFT", anchor, "TOPLEFT", -inset, inset)
	bd:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", inset, -inset)
	E:SetTemplate(bd, transparent)
	-- A box around an icon takes the skin's thin icon ring.
	if not transparent then E:PaintSurface(bd, "icon", "cooldowns", RING_OUTSIDE) end
	bd:Show()
	if not Recorded(group, bd, "backdrop") then Record(group, bd, "backdrop", function() bd:Hide() end) end
	return bd
end

function K.GetBackdrop(target)
	return backdrops[target]
end

local barTextures = setmetatable({}, { __mode = "k" })

local function BarTextureState(bar)
	local region = bar:GetStatusBarTexture()
	if not region then return nil, nil, true end
	local atlas, readable = E.FrameAtlas(region)
	if not readable then return nil, nil, false end
	local ok, path = pcall(region.GetTexture, region)
	if not ok or issecret(path) or (type(path) ~= "nil" and type(path) ~= "string" and type(path) ~= "number") then
		return nil, nil, false
	end
	return atlas ~= "" and atlas or nil, path, true
end

function K.BarTexture(group, bar, texture)
	if not (K.Usable(bar) and bar.SetStatusBarTexture) then return end
	local atlas, path, readable = BarTextureState(bar)
	if not readable then return end
	local states = barTextures[bar]
	if not states then
		states = {}
		barTextures[bar] = states
	end
	local state = states[group]
	if not Recorded(group, bar, "bartexture") then
		state = { atlas = atlas, path = path }
		states[group] = state
		Record(group, bar, "bartexture", function()
			local currentAtlas, currentPath, currentReadable = BarTextureState(bar)
			if not currentReadable then return false end
			if currentAtlas == nil and currentPath == state.applied then
				if state.atlas then bar:GetStatusBarTexture():SetAtlas(state.atlas)
				else bar:SetStatusBarTexture(state.path) end
			end
			states[group] = nil
		end)
	end
	state.applied = texture or E.media.statusbar
	bar:SetStatusBarTexture(state.applied)
end

---------------------------------------------------------------------------
-- Reparenting (hide, fader) with the original parent remembered.
---------------------------------------------------------------------------
-- The core keeps the parent (E:KeepBlizzardParent, Core/Blizzard.lua): its
-- SetParent post-hook sends the frame back when Blizzard re-parents it
-- (Edit Mode, managed containers), after combat for protected frames.
function K.Parent(frame, parent)
	if not K.Usable(frame) then return end
	E:KeepBlizzardParent(frame, parent)
end

function K.RestoreParent(frame)
	E:ReleaseBlizzardParent(frame)
end

---------------------------------------------------------------------------
-- Pins: keep a Blizzard frame on EldoUI's anchor, scale and size, also when
-- Blizzard (Edit Mode, managed frame containers) re-anchors it later.
--   spec.anchor() -> point, relativeTo, relativePoint, x, y   (or nil)
--   spec.scale()  -> scale (or nil)
--   spec.size()   -> width, height (or nil)
--   spec.active() -> false to leave the frame alone right now
-- While Blizzard's Edit Mode is open the frame is left to Edit Mode.
-- The work is the core pin (E:PinBlizzardFrame), which re-applies after
-- every Edit Mode layout pass and loading screen.
---------------------------------------------------------------------------
local kitPins = setmetatable({}, { __mode = "k" })

function K.ApplyPin(frame)
	E.BlizzardKeep.ApplyPin(frame)
end

function K.Pin(frame, spec)
	if not K.Usable(frame) then return end
	spec.pauseInEditMode = true
	kitPins[frame] = spec
	E:PinBlizzardFrame(frame, spec)
end

function K.IsPinned(frame, expected)
	local spec = kitPins[frame]
	return spec ~= nil and (not expected or spec == expected)
		and E.BlizzardKeep.pins[frame] == spec
end

-- Back to the anchor and scale the frame had before EldoUI pinned it.
-- Blizzard's next layout pass (Edit Mode, /reload) settles the rest.
function K.Unpin(frame, expected)
	local spec = kitPins[frame]
	if not spec or (expected and spec ~= expected) then return end
	if E.BlizzardKeep.pins[frame] ~= spec then return end
	E:UnpinBlizzardFrame(frame, nil, spec)
	if kitPins[frame] == spec and E.BlizzardKeep.pins[frame] ~= spec then kitPins[frame] = nil end
end

-- Re-apply every pin, e.g. after leaving Edit Mode or a layout change.
function K.RefreshPins()
	for frame in pairs(kitPins) do K.ApplyPin(frame) end
end

---------------------------------------------------------------------------
-- Holders: an EldoUI frame with a mover that a Blizzard frame is pinned to.
-- The holder follows the Blizzard frame's size so the mover overlay matches.
---------------------------------------------------------------------------
local holders = {}

function K.Holder(module, name, title, defaultPoint, width, height, opts)
	local holder = holders[name]
	if holder then return holder end
	holder = CreateFrame("Frame", nil, UIParent)
	holder:SetSize(width or 100, height or 20)
	holders[name] = holder
	-- Tag the mover with its module, so the module's export carries it.
	local previous = E.currentModule
	E.currentModule = module
	E:CreateMover(holder, name, title, defaultPoint, opts)
	E.currentModule = previous
	return holder
end

function K.GetHolder(name)
	return holders[name]
end

-- Size the holder like `frame` (skipping secret or empty sizes).
function K.FitHolder(holder, frame, minWidth, minHeight)
	if not (holder and K.Usable(frame)) then return end
	local width, height = frame:GetSize()
	if not K.Plain(width, height) then return end
	local scale = frame:GetScale()
	if not K.Plain(scale) then scale = 1 end
	width = math.max(width * scale, minWidth or 20)
	height = math.max(height * scale, minHeight or 10)
	local w, h = holder:GetSize()
	if math.abs(w - width) > 0.5 or math.abs(h - height) > 0.5 then holder:SetSize(width, height) end
end

---------------------------------------------------------------------------
-- Visibility: a fader frame per display whose alpha follows a rule of the
-- shared visibility engine (Core/Visibility.lua). The Blizzard frame
-- is parented to the fader, so Blizzard keeps full control of its own
-- alpha and shown state.
--   rule: always | combat | nocombat | target | combatOrTarget | mouseover
--         | never, or a full visibility block from the module's settings
-- "target" here means a hostile target, as the kit always did.
---------------------------------------------------------------------------
local faders = {}
local legacyBlocks = {}   -- key -> block built from a plain rule

-- The fader for `key` (created on first use).
function K.Fader(key)
	local fader = faders[key]
	if not fader then
		fader = CreateFrame("Frame", nil, UIParent)
		fader:SetAllPoints(UIParent)
		fader:SetFrameStrata(E.FrameStrata(UIParent, "MEDIUM"))
		faders[key] = fader
	end
	return fader
end

-- watch: the frame the mouse-over test looks at (nil = none).
-- fadeAlpha: alpha while the rule says "hide" (0-1), for plain rules.
function K.Visibility(key, watch, rule, fadeAlpha)
	local fader = K.Fader(key)
	local block
	if type(rule) == "table" then
		block = rule
	else
		block = legacyBlocks[key] or {}
		legacyBlocks[key] = block
		local fresh = E:VisibilityFromLegacy(rule or "always", fadeAlpha or 0)
		wipe(block)
		for field, value in pairs(fresh) do block[field] = value end
	end
	-- A fader is reused by key after StopVisibility; the rule decides its
	-- alpha from here, so it starts out shown.
	if not fader:IsShown() then fader:Show() end
	E:AttachVisibility(fader, block, { watch = watch or false, hostileTarget = true })
	return fader
end

function K.StopVisibility(key)
	local fader = faders[key]
	if fader then E:DetachVisibility(fader) end
end

-- Leaving Edit Mode re-applies every pin through the core's layout pass
-- (E:BlizzardRelayout on "EditMode.Exit", Core/Blizzard.lua).

---------------------------------------------------------------------------
-- The element switches (Core/Blizzard.lua) inside a module's own page.
-- The config window reads and writes option keys in the module's settings,
-- so `<module.db>.blizz` is a stand-in table: reading `blizz.<id>.<action>`
-- returns the element's switch, writing it goes through
-- E:SetBlizzardElement (which re-applies and asks for a reload when needed).
-- Nothing is stored in the stand-in itself.
---------------------------------------------------------------------------
local leafMeta = {
	__index = function(leaf, key)
		local state = E:BlizzardState(rawget(getmetatable(leaf), "id"))
		return state and state[key]
	end,
	__newindex = function(leaf, key, value)
		E:SetBlizzardElement(rawget(getmetatable(leaf), "id"), key, value)
	end,
}
local leaves = {}
local switchProxy = setmetatable({}, {
	__index = function(_, id)
		if not E.blizzardElements[id] then return nil end
		local leaf = leaves[id]
		if not leaf then
			leaf = setmetatable({}, { id = id, __index = leafMeta.__index, __newindex = leafMeta.__newindex })
			leaves[id] = leaf
		end
		return leaf
	end,
	__newindex = function() end, -- the config's path walk re-assigns existing leaves
})

function K.BindSwitches(module)
	if module.db and rawget(module.db, "blizz") ~= switchProxy then
		rawset(module.db, "blizz", switchProxy)
	end
end

-- Option rows: the master switch and the action switches of element `id`,
-- named as on the Blizzard UI page; `descs` holds what the
-- switch does for this element.
function K.SwitchOptions(options, id, descs)
	local data = E.blizzardElements[id]
	if not data then return end
	local function Off() return not E:BlizzardAllowed(id) end
	table.insert(options, { type = "header", label = "Blizzard switches" })
	table.insert(options, { type = "toggle", key = "blizz." .. id .. ".enabled", label = "Let EldoUI change this",
		desc = "Master switch for Blizzard's %s. Off keeps Blizzard's own frame, untouched: no skin, no move, no CVars.", descFill = data.title })
	for _, action in ipairs({ "skin", "move", "hide", "replace", "improve" }) do
		if data.allowed[action] then
			table.insert(options, { type = "toggle", key = "blizz." .. id .. "." .. action,
				label = E.BLIZZARD_ACTION_LABEL[action], desc = (descs and descs[action]) or E.BLIZZARD_ACTION_DESC[action], hidden = Off })
		end
	end
	table.insert(options, { type = "description", hidden = function() return not Off() end,
		label = "Blizzard's own version is showing. Turn on \"Let EldoUI change this\" to use the settings below." })
end

-- Option list helpers.
K.ANCHORS = {
	CENTER = "Center", TOP = "Top", BOTTOM = "Bottom", LEFT = "Left", RIGHT = "Right",
	TOPLEFT = "Top left", TOPRIGHT = "Top right", BOTTOMLEFT = "Bottom left", BOTTOMRIGHT = "Bottom right",
}

function K.TextureValues()
	local values = {}
	for name in pairs(E.media.statusbars) do values[name] = name end
	return E:RawValues(values)
end

-- A font row's value as a file: the theme font for "THEME", else the
-- EldoUI font or one another addon brought.
function K.FontPath(name)
	if E:IsThemeFont(name) then return E.media.font end
	return E.media.fonts[name] or E:FetchMedia("font", name) or E.media.font
end

function K.TexturePath(name)
	return (name and E.media.statusbars[name]) or E.media.statusbar
end

---------------------------------------------------------------------------
-- Cooldown flags. Only the game's own flags are read, never a time:
--   C_Spell.GetSpellCooldown   isActive, isOnGCD     (NeverSecret)
--   C_Spell.GetSpellCharges    isActive, maxCharges  (NeverSecret)
--   C_Spell.GetItemCooldown    isActive              (NeverSecret)
-- A flag that comes back secret anyway stays nil ("don't know"); nothing
-- is compared or guessed from start times, durations or charge counts.
---------------------------------------------------------------------------
-- active      the spell's own cooldown runs (no charge left)
-- gcd         the running cooldown is only the global cooldown
-- charging    a charge is coming back (spells with more than one charge)
-- maxCharges  the spell's charge count when readable, else nil
-- skipCharges: leave out the charge query (for spells known to have none).
function K.SpellFlags(spellID, skipCharges)
	if not K.Plain(spellID) or type(spellID) == "nil" then return nil end
	local active, gcd, charging, maxCharges
	local getCooldown = C_Spell and C_Spell.GetSpellCooldown
	local info = getCooldown and getCooldown(spellID)
	if type(info) == "table" then
		if K.Plain(info.isActive) and type(info.isActive) ~= "nil" then active = info.isActive and true or false end
		if K.Plain(info.isOnGCD) and type(info.isOnGCD) ~= "nil" then gcd = info.isOnGCD and true or false end
	end
	local getCharges = not skipCharges and C_Spell and C_Spell.GetSpellCharges
	local charges = getCharges and getCharges(spellID)
	if type(charges) == "table" then
		local max = charges.maxCharges
		if K.Plain(max) and type(max) == "number" then maxCharges = max end
		if maxCharges and maxCharges > 1 and K.Plain(charges.isActive) and type(charges.isActive) ~= "nil" then
			charging = charges.isActive and true or false
		end
	end
	return active, gcd, charging, maxCharges
end

local INVSLOT_LAST = 19 -- INVSLOT_LAST_EQUIPPED

-- True while the item's cooldown runs, false when it is ready, nil when the
-- game doesn't say. `item` is an item ID, or an equipment slot (1-19) when
-- `isSlot` is true: K.ItemActive(13, true) asks about the first trinket.
function K.ItemActive(item, isSlot)
	if not K.Plain(item) or type(item) == "nil" then return nil end
	local itemID = item
	if isSlot then
		if type(item) ~= "number" or item < 1 or item > INVSLOT_LAST then return nil end
		itemID = GetInventoryItemID and GetInventoryItemID("player", item)
		if not itemID or not K.Plain(itemID) then return nil end
	end
	local get = C_Spell and C_Spell.GetItemCooldown
	if not get then return nil end
	local ok, info = pcall(get, itemID)
	if ok and type(info) == "table" and K.Plain(info.isActive) and type(info.isActive) ~= "nil" then
		return info.isActive and true or false
	end
end

---------------------------------------------------------------------------
-- Cooldown source: the one place that listens for the game's cooldown
-- events and reads spell, item and totem cooldowns for the cooldown rows,
-- tracking bars, cooldown pulse, cursor ring, consumable bar and class
-- resources.
--   K.Cooldowns.Subscribe(key, fn[, opts])  fn(changes) once per frame
--       after the game said a cooldown changed; opts.totems = true also
--       listens for totems. changes = {
--         spells   = true when a spell cooldown or charge changed,
--         spellIDs = { [id] = true } for the spells the game named (nil:
--                    every spell may have changed),
--         items    = true when an item cooldown changed,
--         totems   = { [slot] = true } for the totem slots that changed }
--   K.Cooldowns.Unsubscribe(key) / IsSubscribed(key) / Count()
--   K.Cooldowns.Flush()   hand out pending changes now instead of next frame
-- Readers (the game's answers, never a time worked out by EldoUI):
--   SpellFlags(id[, skipCharges])  K.SpellFlags
--   SpellCharges(id)       the game's charge info; give currentCharges to
--                          SetText as it is (it may be secret)
--   SpellDuration(id[, charge])  the game's duration object for the swipe
--   GCDDuration()          the same for the global cooldown
--   ItemFlags(itemID)      active, gcd: the game's own flags
--   ItemActive(item[, isSlot])     K.ItemActive
--   ItemDuration(itemID)   a duration object made from the game's start
--                          and duration (nil while there is none)
--   TotemDuration(slot)    the game's duration object for a totem slot
-- Drawing (a Cooldown frame gets the swipe the game describes):
--   DrawSpell(cooldown, id[, opts])  opts.charge: the recharge swipe;
--                          opts.hideGCD: no swipe while only the global
--                          cooldown runs
--   DrawItem(cooldown, itemID[, opts])  opts.hideGCD as above
-- Every event is collected and handed out once on the next frame (one
-- shared ticker call), so a burst of events costs one update. Secret
-- values are never compared or added up: flags are read only when plain,
-- and times go to the Cooldown frame inside the game's duration objects.
---------------------------------------------------------------------------
local CD = {}
K.Cooldowns = CD

CD.GCD_SPELL = 29515 -- the global cooldown's reference spell

local listeners = {}    -- key -> { fn, totems }
local listenerOrder = {} -- keys in the order they subscribed
local pendingChanges    -- changes collected since the last hand-out
local EVENT_OWNER = "combatkit:cooldowns"
local TICK_KEY = "combatkit:cooldowns"
local COOLDOWN_EVENTS = { "SPELL_UPDATE_COOLDOWN", "SPELL_UPDATE_CHARGES", "BAG_UPDATE_COOLDOWN" }
local listening, listeningTotems = false, false

local function Pending()
	if not pendingChanges then pendingChanges = { spellIDs = {} } end
	return pendingChanges
end

function CD.Flush()
	if E.Ticker then E.Ticker:Unsubscribe(TICK_KEY) end
	local changes = pendingChanges
	pendingChanges = nil
	if not changes then return end
	if changes.allSpells or not next(changes.spellIDs) then changes.spellIDs = nil end
	changes.allSpells = nil
	-- A copy: a listener may subscribe or leave while it runs.
	local order = { unpack(listenerOrder) }
	for _, key in ipairs(order) do
		local entry = listeners[key]
		if entry and (entry.totems or changes.spells or changes.items) then
			local ok, err = pcall(entry.fn, changes)
			if not ok then geterrorhandler()(err) end
		end
	end
end

local function Queue()
	if E.Ticker then
		if not E.Ticker:IsSubscribed(TICK_KEY) then E.Ticker:Subscribe(TICK_KEY, 0, CD.Flush, "CombatKit") end
	else
		CD.Flush()
	end
end

local function OnCooldownEvent(_, event, arg)
	local changes = Pending()
	if event == "BAG_UPDATE_COOLDOWN" then
		changes.items = true
	elseif event == "PLAYER_TOTEM_UPDATE" then
		changes.totems = changes.totems or {}
		if K.Plain(arg) and type(arg) == "number" then changes.totems[arg] = true end
	else
		changes.spells = true
		-- SPELL_UPDATE_COOLDOWN may name one spell; without one, all changed.
		if event == "SPELL_UPDATE_COOLDOWN" and K.Plain(arg) and type(arg) == "number" then
			changes.spellIDs[arg] = true
		else
			changes.allSpells = true
		end
	end
	Queue()
end

local function UpdateListening()
	local want, wantTotems = next(listeners) ~= nil, false
	for _, entry in pairs(listeners) do
		if entry.totems then wantTotems = true end
	end
	if want ~= listening then
		listening = want
		for _, event in ipairs(COOLDOWN_EVENTS) do
			if want then E:RegisterEvent(event, OnCooldownEvent, EVENT_OWNER) else E:UnregisterEvent(event, EVENT_OWNER) end
		end
	end
	if wantTotems ~= listeningTotems then
		listeningTotems = wantTotems
		if wantTotems then
			E:RegisterEvent("PLAYER_TOTEM_UPDATE", OnCooldownEvent, EVENT_OWNER)
		else
			E:UnregisterEvent("PLAYER_TOTEM_UPDATE", EVENT_OWNER)
		end
	end
	if not want then
		pendingChanges = nil
		if E.Ticker then E.Ticker:Unsubscribe(TICK_KEY) end
	end
end

function CD.Subscribe(key, fn, opts)
	assert(key ~= nil and type(fn) == "function", "K.Cooldowns.Subscribe(key, fn): key and fn are required")
	if not listeners[key] then listenerOrder[#listenerOrder + 1] = key end
	listeners[key] = { fn = fn, totems = opts and opts.totems and true or false }
	UpdateListening()
end

function CD.Unsubscribe(key)
	if not listeners[key] then return false end
	listeners[key] = nil
	for index, other in ipairs(listenerOrder) do
		if other == key then
			table.remove(listenerOrder, index)
			break
		end
	end
	UpdateListening()
	return true
end

function CD.IsSubscribed(key)
	return listeners[key] ~= nil
end

function CD.Count()
	return #listenerOrder
end

CD.SpellFlags = K.SpellFlags
CD.ItemActive = K.ItemActive

-- The game's charge info of a spell (a table), or nil.
function CD.SpellCharges(spellID)
	if not K.Plain(spellID) or type(spellID) == "nil" then return nil end
	local get = C_Spell and C_Spell.GetSpellCharges
	if not get then return nil end
	local ok, info = pcall(get, spellID)
	if ok and type(info) == "table" then return info end
	return nil
end

-- The game's duration object of a spell's cooldown (charge: of the next
-- charge coming back), or nil.
function CD.SpellDuration(spellID, charge)
	if not K.Plain(spellID) or type(spellID) == "nil" or not C_Spell then return nil end
	local get = charge and C_Spell.GetSpellChargeDuration or C_Spell.GetSpellCooldownDuration
	if not get then return nil end
	local ok, duration = pcall(get, spellID)
	return ok and duration or nil
end

function CD.GCDDuration()
	return CD.SpellDuration(CD.GCD_SPELL)
end

-- A spell cooldown's start and duration as the game gives them, for a
-- display shown out of combat (such as the camp's "ready again in"). Only
-- plain numbers come back: nil, nil while either value is secret or the
-- game gives none. Nothing here works out a time; the caller may.
function CD.PlainSpellTimes(spellID)
	if not K.Plain(spellID) or type(spellID) == "nil" then return nil end
	local get = C_Spell and C_Spell.GetSpellCooldown
	if not get then return nil end
	local ok, info = pcall(get, spellID)
	if not ok or type(info) ~= "table" then return nil end
	local start, duration = info.startTime, info.duration
	if not K.Plain(start, duration) or type(start) ~= "number" or type(duration) ~= "number" then return nil end
	return start, duration
end

-- The game's own flags of an item's cooldown: active (it runs) and gcd
-- (only the global cooldown runs); nil when the game doesn't say.
function CD.ItemFlags(itemID)
	if not K.Plain(itemID) or type(itemID) == "nil" then return nil end
	local get = C_Spell and C_Spell.GetItemCooldown
	if not get then return K.ItemActive(itemID), false end
	local ok, info = pcall(get, itemID)
	if not ok or type(info) ~= "table" then return nil end
	local active, gcd
	-- K.Plain first: a secret flag compared with nil errors.
	if K.Plain(info.isActive) and type(info.isActive) ~= "nil" then active = info.isActive and true or false end
	if K.Plain(info.isOnGCD) and type(info.isOnGCD) ~= "nil" then gcd = info.isOnGCD and true or false end
	return active, gcd
end

-- The game's start, duration and enable flag of an item, as given.
local function ItemTimes(itemID)
	local get = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown)
	if not get then return nil end
	local ok, start, duration, enable = pcall(get, itemID)
	if not ok then return nil end
	return start, duration, enable
end

-- True when the game says the item's cooldown is switched off (a plain
-- enable flag of false or 0); a secret flag counts as on.
local function ItemDisabled(enable)
	return K.Plain(enable) and (enable == false or enable == 0)
end

-- An item's cooldown as a duration object, so items and spells share one
-- drawing path. The start and duration go in untouched; nil while the game
-- gives none.
function CD.ItemDuration(itemID)
	if not K.Plain(itemID) or type(itemID) == "nil" then return nil end
	if not (C_DurationUtil and C_DurationUtil.CreateDuration) then return nil end
	local start, duration, enable = ItemTimes(itemID)
	-- Only plain values are tested, and the secret test comes first (a
	-- secret compared with nil errors).
	if K.Plain(start) and type(start) == "nil" then return nil end
	if K.Plain(duration) and type(duration) == "nil" then return nil end
	if ItemDisabled(enable) then return nil end
	local made, object = pcall(C_DurationUtil.CreateDuration)
	if not made or not object then return nil end
	if not pcall(object.SetTimeFromStart, object, start, duration) then return nil end
	return object
end

function CD.TotemDuration(slot)
	if not K.Plain(slot) or type(slot) == "nil" or not GetTotemDuration then return nil end
	local ok, duration = pcall(GetTotemDuration, slot)
	return ok and duration or nil
end

local function Clear(cooldown)
	if cooldown and cooldown.Clear then cooldown:Clear() end
	return false
end

local function DrawDuration(cooldown, duration)
	if not (duration and cooldown.SetCooldownFromDurationObject) then return false end
	return (pcall(cooldown.SetCooldownFromDurationObject, cooldown, duration, true))
end

-- A spell's swipe on a Cooldown frame. Returns true when one is drawn.
function CD.DrawSpell(cooldown, spellID, opts)
	if not cooldown then return false end
	local charge = opts and opts.charge
	if not charge and opts and opts.hideGCD then
		local _, gcd = K.SpellFlags(spellID, true)
		if gcd then return Clear(cooldown) end
	end
	if DrawDuration(cooldown, CD.SpellDuration(spellID, charge)) then return true end
	return Clear(cooldown)
end

-- An item's swipe on a Cooldown frame. Returns true when one is drawn.
function CD.DrawItem(cooldown, itemID, opts)
	if not cooldown then return false end
	if not K.Plain(itemID) or type(itemID) == "nil" then return Clear(cooldown) end
	if opts and opts.hideGCD then
		local _, gcd = CD.ItemFlags(itemID)
		if gcd then return Clear(cooldown) end
	end
	if DrawDuration(cooldown, CD.ItemDuration(itemID)) then return true end
	-- No duration object (no cooldown, or the game gave none): the game's
	-- numbers go to the frame as they are; plain ones are tested first.
	local start, duration, enable = ItemTimes(itemID)
	if ItemDisabled(enable) then return Clear(cooldown) end
	if K.Plain(start, duration) and not (type(start) == "number" and type(duration) == "number" and duration > 0) then
		return Clear(cooldown)
	end
	if pcall(cooldown.SetCooldown, cooldown, start, duration) then return true end
	return Clear(cooldown)
end

---------------------------------------------------------------------------
-- Cooldown stack: the pieces that hang on the main cooldown row (the
-- Cooldown Manager's essential row, mover EldoUI_Cooldowns) share one width
-- watcher and stack in a fixed order instead of overlapping:
--   above the row   power bar (Player Power), then a cast bar set "above"
--   below the row   item row, then tracking bars, then the cast bar
-- A member registers once:
--   K.CooldownStack.Register(key, {
--     side = "ABOVE" | "BELOW",   -- default from ORDER[key]
--     order = number,             -- lower sits closer to the row
--     frame = function() -> region or nil,  -- nil = not on the stack now
--     gap = function() -> number, -- the member's own gap (default 4)
--     relayout = function(width), -- the width or the stack changed
--   })
-- A member places itself against its usual base (the row) and adds
-- K.CooldownStack.Offset(key) on the y axis: the height plus gap of every
-- member closer to the row on the same side. With one member on a side
-- the offset is 0, so a lone piece sits exactly where it always did.
-- Heights come from EldoUI's own frames only (never a secret value).
-- One ticker (1 s, out of combat) watches the width and the stack; a
-- change calls every member's relayout. A member that showed, hid or
-- resized calls K.CooldownStack.Changed().
---------------------------------------------------------------------------
local Stack = {}
K.CooldownStack = Stack

Stack.ORDER = {
	power = { side = "ABOVE", order = 10 },
	castAbove = { side = "ABOVE", order = 20 },
	items = { side = "BELOW", order = 10 },
	tracking = { side = "BELOW", order = 20 },
	cast = { side = "BELOW", order = 30 },
}

local members = {} -- key -> spec
local lastSignature
local refreshing = false
local bodySource, readGeometry, readingGeometry, readingSource, lastBodyFrame, nativeLayoutBounds
local registerWideReader = E.RegisterWideStackReadSource
local ValidateGeometryReceiver

-- The main cooldown row the stack hangs on (EldoUI's mover, else Blizzard's viewer).
function Stack.Anchor()
	return (E.movers and E.movers.EldoUI_Cooldowns) or EssentialCooldownViewer
end

-- The row's width (rounded) when readable, else nil.
function Stack.Width()
	local anchor = Stack.Anchor()
	if not anchor or not ValidateGeometryReceiver or not ValidateGeometryReceiver(anchor) or not anchor.GetWidth then return nil end
	local ok, width = pcall(anchor.GetWidth, anchor)
	if ok and type(width) == "number" and K.Plain(width) and width > 20 then return math.floor(width + 0.5) end
	return nil
end

local function MemberFrame(spec)
	if not spec.frame then return nil end
	local ok, frame = pcall(spec.frame)
	if ok and type(frame) == "table" and frame.GetHeight then return frame end
	return nil
end

local function MemberGap(spec)
	local gap = spec.gap and spec.gap()
	if type(gap) == "number" and K.Plain(gap) then return gap end
	return 4
end

local function MemberHeight(frame)
	if not ValidateGeometryReceiver or not ValidateGeometryReceiver(frame) then return 0 end
	local ok, height = pcall(frame.GetHeight, frame)
	if ok and type(height) == "number" and K.Plain(height) then return height end
	return 0
end

local function Before(a, b)
	if a.order ~= b.order then return a.order < b.order end
	return a.key < b.key
end

-- Active members of a side, closest to the row first.
function Stack.Members(side)
	local list = {}
	for key, spec in pairs(members) do
		if spec.side == side then
			local frame = MemberFrame(spec)
			if frame then list[#list + 1] = { key = key, order = spec.order, spec = spec, frame = frame } end
		end
	end
	table.sort(list, Before)
	return list
end

-- Room taken by the active members between the row and `key`.
local function LegacyOffset(key)
	local spec = members[key]
	if not spec then return 0 end
	local me = { key = key, order = spec.order }
	local offset = 0
	for _, entry in ipairs(Stack.Members(spec.side)) do
		if entry.key ~= key and Before(entry, me) then
			offset = offset + MemberHeight(entry.frame) + MemberGap(entry.spec)
		end
	end
	return math.floor(offset + 0.5)
end

local nativePlain, authorityEqual = K.Plain, rawequal
local geometrySecret = function(value) return not nativePlain(value) end
local moverGeometrySource = E.MoverAuthoritySource
local existingGeometry
if type(moverGeometrySource) == "function" then
	local _, _, _, _, existing = moverGeometrySource()
	existingGeometry = existing
end
local originalClear, originalPoint, originalScale = K.ClearPoints, K.SetPoint, K.SetScale
local function GeometrySame(value, saved) return not geometrySecret(value) and authorityEqual(value, saved) end
local nativeBinding, admitGeometry
if type(moverGeometrySource) == "function" then local _, _, _, _, _, bind, admit = moverGeometrySource();nativeBinding, admitGeometry = bind, admit end
local function ObserveMainGeometry(object)
	if type(admitGeometry) ~= "function" then return end
	return admitGeometry(object, true)
end

-- Providers without constructor binding retain their original read-only
-- metadata/getter capture. This path never admits mutation observers.
local function LegacyReadGeometry(object)
	if not bodySource or bodySource.constructorBound ~= false or type(nativeBinding) ~= "function"
		or not GeometrySame(rawget(E, "MoverAuthoritySource"), moverGeometrySource) then return end
	local _, _, _, _, _, currentBinding = moverGeometrySource()
	if not GeometrySame(currentBinding, nativeBinding) then return end
	return nativeBinding(object, true)
end

local function BodyObserver(source, admission)
	return function(object, transform)
		if geometrySecret(object) or (type(object) ~= "table" and type(object) ~= "userdata") then return end
		local saved = source.observed[object]
		if saved ~= nil and (saved or not admission) then if saved and transform then saved.transform = true end;return saved and saved.capture or nil end
		if admission then source.observed[object] = false end
		local capture, seal
		if existingGeometry then
			if not GeometrySame(rawget(E, "MoverAuthoritySource"), moverGeometrySource) then return end
			capture, seal = existingGeometry(object)
		end
		if not capture then
			local record
			if admission then record = ObserveMainGeometry(object)
			else record = LegacyReadGeometry(object) end
			if not record then return end
			capture, seal = record.capture, record.source
		end
		if type(capture) ~= "function" or type(seal) ~= "function" or not seal() then return end
		local read = nativeBinding and nativeBinding(object, true)
		if not read then return end
		source.observed[object] = { capture = capture, source = seal, read = read, transform = transform == true }
		return capture
	end
end

ValidateGeometryReceiver = function(frame)
	if not bodySource then return true end
	local capture = bodySource.observe(frame)
	return type(capture) == "function" and capture(true)()
end

-- The row owner supplies its committed body; the mover remains the anchor
-- and width reference. A provider is installed once, not replaced by readers.
local installingBodySource, bodyObservation
function Stack.RegisterBodySource(owner, read, bindGeometry)
	if installingBodySource then installingBodySource.invalid = true;return false end
	if not K.Plain(owner, read) or type(owner) ~= "table" or type(read) ~= "function"
		or not K.Plain(E.modules) or type(E.modules) ~= "table" or type(getmetatable(E.modules)) ~= "nil"
		or not rawequal(rawget(E.modules, "CooldownManager"), owner) then return false end
	if bodySource then return rawequal(bodySource.owner, owner) and rawequal(bodySource.read, read) end
	local source = bodyObservation
	if not source then
		source = { observed = setmetatable({}, { __mode = "k" }), epoch = {} }
		source.observe = BodyObserver(source, false)
		source.admit = BodyObserver(source, true)
		bodyObservation = source
	end
	if bindGeometry ~= nil then
		if not K.Plain(bindGeometry) or type(bindGeometry) ~= "function" then return false end
		local request = {};installingBodySource = request
		local ok = pcall(bindGeometry, source.admit)
		installingBodySource = nil
		if not ok or request.invalid or bodySource then return false end
	end
	source.owner, source.read = owner, read
	source.constructorBound = bindGeometry ~= nil
	bodySource = source
	if type(registerWideReader) == "function" and GeometrySame(E.RegisterWideStackReadSource, registerWideReader) then
		pcall(registerWideReader, E, owner, Stack, Stack.LayoutBounds, nativeLayoutBounds)
	end
	lastSignature = nil
	return true
end
function Stack.HasBodySource() return bodySource ~= nil end

do
	local function Number(v)
		return K.Plain(v) and type(v) == "number" and v == v and v > -math.huge and v < math.huge
	end
	local function Table(v)
		return K.Plain(v) and type(v) == "table" and type(getmetatable(v)) == "nil"
	end
	local function Same(a, b) return K.Plain(a, b) and rawequal(a, b) end
	local function Unknown() return { kind = "unavailable" } end

	readGeometry = function(stopKey, receiver, nativeOnly)
		if not bodySource or readingGeometry or readingSource then return Unknown() end
		local source = bodySource
		local sourceEpoch = source.epoch
		local sourceSeals = {}
		for _, record in pairs(source.observed) do
			if record then
				if nativeOnly and (not record.read.native or not record.read.source()) then return Unknown() end
				sourceSeals[#sourceSeals + 1] = record.source
			end
		end
		if not Table(E.modules) or not Same(rawget(E.modules, "CooldownManager"), source.owner) then return Unknown() end
		readingSource = true
		local sourceOK, body = pcall(source.read)
		readingSource = false
		if not sourceOK or not Table(body) or not K.Plain(body.kind) then return Unknown() end
		if body.kind == "pending" or body.kind == "unavailable" then return { kind = body.kind } end
		if body.kind ~= "live" and body.kind ~= "inactive" then return Unknown() end
		if not K.Plain(body.current) or type(body.current) ~= "function" then return Unknown() end
		if not Number(body.above) or body.above < 0 or not Number(body.below) or body.below < 0 then return Unknown() end
		if body.kind == "live" and (not K.Plain(body.frame, body.anchor)
			or (type(body.frame) ~= "table" and type(body.frame) ~= "userdata")
			or (type(body.anchor) ~= "table" and type(body.anchor) ~= "userdata")) then return Unknown() end
		local geometryChecks = {}
		local function Observe(object, transform)
			local capture = source.observe(object, transform)
			if type(capture) ~= "function" then return false end
			if nativeOnly and not source.observed[object].read.native then return false end
			geometryChecks[#geometryChecks + 1] = capture()
			sourceSeals[#sourceSeals + 1] = source.observed[object].source;return true
		end
		if body.kind == "live" then
			if not Observe(body.frame) or not Observe(UIParent, true) then return Unknown() end
			for _, record in pairs(source.observed) do if record and record.transform then geometryChecks[#geometryChecks + 1] = record.capture() end end
		end
		local function GeometryCurrent(full)
			if not GeometrySame(K.Plain, nativePlain) or not GeometrySame(source.epoch, sourceEpoch)
				or not GeometrySame(K.ClearPoints, originalClear) or not GeometrySame(K.SetPoint, originalPoint) or not GeometrySame(K.SetScale, originalScale) then return false end
			for _, check in ipairs(geometryChecks) do if not check() then return false end end
			if full ~= false then
				if nativeOnly and source.constructorBound == true then
					-- Constructor-owned native sources are synchronous raw seals.
					-- Share only this invocation; geometry captures remain distinct.
					local seen = {}
					for _, check in ipairs(sourceSeals) do
						if geometrySecret(check) then return false end
						if not seen[check] then
							seen[check] = true
							if not check() then return false end
						end
					end
				else
					for _, check in ipairs(sourceSeals) do if not check() then return false end end
				end
			end
			return true
		end
		local rect, parts = nil, {}
		if body.kind == "live" then
			if not Table(body.rect) or not Number(body.rect.l) or not Number(body.rect.b)
				or not Number(body.rect.r) or not Number(body.rect.t) or body.rect.r <= body.rect.l or body.rect.t <= body.rect.b then return Unknown() end
			rect = { l = body.rect.l, b = body.rect.b, r = body.rect.r, t = body.rect.t }
			if type(body.parts) ~= "nil" then
				if not Table(body.parts) then return Unknown() end
				local seen = {}
				for i, part in ipairs(body.parts) do
					if not Table(part) or not K.Plain(part.key, part.frame) or type(part.key) ~= "string"
						or seen[part.key] or (type(part.frame) ~= "table" and type(part.frame) ~= "userdata")
						or not Number(part.l) or not Number(part.b) or not Number(part.r) or not Number(part.t)
						or part.r <= part.l or part.t <= part.b then return Unknown() end
					seen[part.key] = true
					parts[i] = { key = part.key, frame = part.frame, l = part.l, b = part.b, r = part.r, t = part.t }
				end
				for key in pairs(body.parts) do if type(key) ~= "number" or key < 1 or key > #parts or key ~= math.floor(key) then return Unknown() end end
			end
		end
		body = { kind = body.kind, frame = body.frame, anchor = body.anchor, above = body.above, below = body.below,
			current = body.current, rect = rect, parts = parts }
		if body.kind == "live" then
			if not Observe(body.anchor) then return Unknown() end
			for _, part in ipairs(parts) do if not Observe(part.frame) then return Unknown() end end
		end
		local keys, specs = {}, {}
		for key, spec in pairs(members) do
			if not K.Plain(key) or type(key) ~= "string" or not Table(spec)
				or not K.Plain(spec.side, spec.order, spec.frame, spec.gap, spec.relayout)
				or (spec.side ~= "ABOVE" and spec.side ~= "BELOW") or not Number(spec.order)
				or type(spec.frame) ~= "function" or (type(spec.gap) ~= "nil" and type(spec.gap) ~= "function")
				or (type(spec.relayout) ~= "nil" and type(spec.relayout) ~= "function") then return Unknown() end
			keys[#keys + 1] = key
			specs[key] = { spec = spec, side = spec.side, order = spec.order, frame = spec.frame,
				gap = spec.gap, relayout = spec.relayout }
		end
		local stop = stopKey and specs[stopKey]
		if stopKey and not stop then return Unknown() end
		table.sort(keys, function(a, b)
			local x, y = specs[a], specs[b]
			if x.side ~= y.side then return x.side == "ABOVE" end
			return Before({ key = a, order = x.order }, { key = b, order = y.order })
		end)
		local state = { kind = "live", body = body, keys = keys, specs = specs, entries = {}, boxes = {}, prefixes = {}, invalid = false }
		local checking, nativeProof = false, false
		local function SpecsCurrent()
			local count = 0
			for key, spec in pairs(members) do
				if not K.Plain(key) or type(key) ~= "string" or not Table(spec) then return false end
				local saved = specs[key]
				if not saved or not Same(spec, saved.spec) or not Same(spec.side, saved.side)
					or not Same(spec.order, saved.order) or not Same(spec.frame, saved.frame)
					or not Same(spec.gap, saved.gap) or not Same(spec.relayout, saved.relayout) then return false end
				count = count + 1
			end
			return count == #keys
		end
		local function CheckCurrent()
			if state.invalid or not GeometryCurrent() or not Same(bodySource, source) or not Table(E.modules)
				or not Same(rawget(E.modules, "CooldownManager"), source.owner) or not SpecsCurrent() then return false end
			local bodyOK, current = pcall(body.current)
			if not bodyOK or not K.Plain(current) or current ~= true or not GeometryCurrent() then return false end
			for _, entry in ipairs(state.entries) do
				local valid, frame = pcall(specs[entry.key].frame)
				if not valid or not Same(frame, entry.frame) or not SpecsCurrent() or not GeometryCurrent() then return false end
			end
			bodyOK, current = pcall(body.current)
			if not bodyOK or not K.Plain(current) or current ~= true or not SpecsCurrent() or not GeometryCurrent() then return false end
			return not state.invalid and Same(bodySource, source) and Table(E.modules)
				and Same(rawget(E.modules, "CooldownManager"), source.owner)
		end
		local function Current()
			if nativeProof then return not state.invalid and GeometryCurrent(false) and SpecsCurrent() and Same(bodySource, source) end
			if checking then state.invalid = true; return false end
			checking = true
			local ok, result = pcall(CheckCurrent)
			checking = false
			return ok and result == true
		end
		state.current, state.geometryCurrent = Current, GeometryCurrent
		local function CheckedReturn(record, method, ok, ...)
			if not ok or not record.read.source(method) or not Current() then return false end
			return true, ...
		end
		local function Call(frame, method, ...)
			if not Current() or not K.Plain(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then return false end
			local record = rawget(source.observed, frame)
			if not record or not record.read or (nativeProof and not record.read.native) or not record.read.source(method) then return false end
			local fn = record.read.getters[method]
			if not K.Plain(fn) or type(fn) ~= "function" then return false end
			return CheckedReturn(record, method, pcall(fn, frame, ...))
		end
		local function SourceParents(frame)
			local ancestor, seen = frame, {}
			for depth = 1, 64 do
				local parentOK, parent = Call(ancestor, "GetParent")
				if not parentOK or not K.Plain(parent) then return false end
				if parent == nil then return true end
				if seen[parent] then return false end;seen[parent] = true
				if not Same(parent, body.anchor) then
					local known = rawget(source.observed, parent)
					if not known then
						local capture, seal
						if existingGeometry then capture, seal = existingGeometry(parent) end
						if type(capture) ~= "function" or type(seal) ~= "function" or not seal() then return false end
					end
					if not Observe(parent, true) then return false end
				end
				ancestor = parent
			end
			return false
		end
		local function Box(frame)
			local parentOK, parent = Call(frame, "GetParent")
			if not parentOK or not K.Plain(parent) then return end
			local ancestor, seen = parent, {}
			for depth = 1, 64 do
				if not ancestor then break end
				if seen[ancestor] then return end;seen[ancestor] = true
				if not Same(ancestor, body.anchor) and not Observe(ancestor, true) then return end
				local parentValid, nextParent = Call(ancestor, "GetParent")
				if not parentValid then return end;ancestor = nextParent
				if depth == 64 and ancestor then return end
			end
			local pointsOK, count = Call(frame, "GetNumPoints")
			if not parentOK or not pointsOK or not Number(count) or count < 1 or count > 2 or count ~= math.floor(count) then return end
			local points = {}
			for i = 1, count do
				local good, p, r, rp, x, y = Call(frame, "GetPoint", i)
				if not good or not K.Plain(p, r, rp, x, y) then return end
				if r and not Same(r, body.anchor) and not Observe(r, true) then return end
				points[i] = { p, r, rp, x, y }
			end
			local good, l, b, w, h = Call(frame, "GetRect")
			local scaleOK, scale = Call(frame, "GetEffectiveScale")
			local rootOK, rootScale = Call(UIParent, "GetEffectiveScale")
			local heightOK, height = Call(frame, "GetHeight")
			if not good or not scaleOK or not rootOK or not heightOK or not Number(l) or not Number(b)
				or not Number(w) or not Number(h) or w <= 0 or h <= 0 or not Number(height) or height <= 0
				or not Number(scale) or scale <= 0 or not Number(rootScale) or rootScale <= 0 then return end
			if math.abs(height - h) > 4 * 2^-52 * math.max(1, math.abs(height), math.abs(h)) then return end
			local validParent, afterParent = Call(frame, "GetParent")
			local validCount, afterCount = Call(frame, "GetNumPoints")
			local validScale, afterScale = Call(frame, "GetEffectiveScale")
			if not validParent or not Same(afterParent, parent) or not validCount or not Same(afterCount, count)
				or not validScale or not Same(afterScale, scale) then return end
			for i = 1, count do
				local pointValid, p, r, rp, x, y = Call(frame, "GetPoint", i)
				if not pointValid then return end
				local after = { p, r, rp, x, y }
				for j = 1, 5 do if not Same(points[i][j], after[j]) then return end end
			end
			local ratio = scale / rootScale
			if not Number(ratio) or ratio <= 0 then return end
			local box = { frame = frame, l = l * ratio, b = b * ratio, r = (l + w) * ratio,
				t = (b + h) * ratio, ratio = ratio, height = height * ratio }
			if not Number(box.l) or not Number(box.b) or not Number(box.r) or not Number(box.t)
				or not Number(box.height) then return end
			return box
		end
		local nativeSaved
		local function NativeState(compare)
			if body.kind ~= "live" then if compare then return true end;return {} end
			local frames, translate, seen = { body.anchor, body.frame }, { [body.frame] = true }, {}
			for _, part in ipairs(body.parts) do frames[#frames + 1] = part.frame;translate[part.frame] = true end
			for _, entry in ipairs(state.entries) do if entry.frame then frames[#frames + 1] = entry.frame;translate[entry.frame] = true end end
			local out, cursor = not compare and {}, 1
			local matching, dx, dy = true, 0, 0
			while cursor <= #frames do
				local frame = frames[cursor];cursor = cursor + 1
				if not seen[frame] then
					seen[frame] = true
					local parentOK, parent = Call(frame, "GetParent")
					local countOK, count = Call(frame, "GetNumPoints")
					local scaleOK, scale = Call(frame, "GetEffectiveScale")
					local shownOK, shown = Call(frame, "IsShown")
					local visibleOK, visible = Call(frame, "IsVisible")
					local rectOK, l, b, w, h = Call(frame, "GetRect")
					if not parentOK or not K.Plain(parent) or not countOK or not Number(count) or count < 0 or count > 4 or count % 1 ~= 0
						or not scaleOK or not Number(scale) or scale <= 0 or not shownOK or not K.Plain(shown) or type(shown) ~= "boolean"
						or not visibleOK or not K.Plain(visible) or type(visible) ~= "boolean" or not rectOK
						or not Number(l) or not Number(b) or not Number(w) or not Number(h) or w < 0 or h < 0 then return end
					local saved = compare and compare[frame]
					local anchor = compare and Same(frame, body.anchor)
					if compare and anchor and saved then dx, dy = l - saved.l, b - saved.b end
					if saved then
						if not Same(parent, saved.parent) or not Same(scale, saved.scale) or not Same(shown, saved.shown)
							or not Same(visible, saved.visible) or not Same(w, saved.w) or not Same(h, saved.h) then matching = false end
						if not anchor then
							local x, y = saved.translate and dx or 0, saved.translate and dy or 0
							if not Same(l, saved.l + x) or not Same(b, saved.b + y) or count ~= #saved.points then matching = false end
						end
					end
					local points = not compare and {}
					for i = 1, count do
						local pointOK, p, r, rp, x, y = Call(frame, "GetPoint", i)
						if not pointOK or not K.Plain(p, r, rp, x, y) or type(p) ~= "string" or type(rp) ~= "string" or not Number(x) or not Number(y) then return end
						if compare then
							if saved and not anchor then
								local point = saved.points[i]
								if not point or not Same(p, point[1]) or not Same(r, point[2]) or not Same(rp, point[3])
									or not Same(x, point[4]) or not Same(y, point[5]) then matching = false end
							end
						else points[i] = { p, r, rp, x, y } end
					end
					if not compare then out[frame] = { parent = parent, scale = scale, shown = shown, visible = visible, l = l, b = b, w = w, h = h, points = points, translate = translate[frame] } end
					if parent and not seen[parent] then
						if not rawget(source.observed, parent) then return end
						frames[#frames + 1] = parent
					end
				end
			end
			if compare then
				for frame in pairs(compare) do if not seen[frame] then matching = false end end
				return matching
			end
			return out
		end
		local function CheckNativeCurrent()
			if not Current() or not NativeState(nativeSaved) then return false end
			return GeometryCurrent() and SpecsCurrent()
		end
		local function NativeCurrent()
			if nativeProof or checking or not nativeSaved then return false end
			nativeProof = true
			local ok, valid = pcall(CheckNativeCurrent)
			nativeProof = false
			return ok and valid == true
		end
		state.nativeCurrent = NativeCurrent
		readingGeometry = state
		local passed, result = pcall(function()
			if not Current() then return Unknown() end
			if body.kind == "live" then
				if not SourceParents(body.frame) then return Unknown() end
				for _, part in ipairs(body.parts) do if not SourceParents(part.frame) then return Unknown() end end
			end
			local prefix = { ABOVE = body.above, BELOW = body.below }
			for _, key in ipairs(keys) do
				local saved = specs[key]
				if not stop or saved.side == stop.side then
				local success, frame = pcall(saved.frame)
				if not success or not K.Plain(frame) or not Current() then return Unknown() end
				if frame and not Observe(frame) then return Unknown() end
				local entry = { key = key, frame = frame, side = saved.side, spec = saved.spec }
				state.entries[#state.entries + 1] = entry
				if key == stopKey then
					if type(frame) == "nil" then state.kind, state.inactive = "prefix", true; return state end
					if type(receiver) ~= "nil" and not Same(receiver, frame) then return Unknown() end
					local scaleOK, scale = Call(frame, "GetEffectiveScale")
					local rootOK, rootScale = Call(UIParent, "GetEffectiveScale")
					if not scaleOK or not rootOK or not Number(scale) or scale <= 0 or not Number(rootScale) or rootScale <= 0 then return Unknown() end
					local ratio = scale / rootScale
					if not Number(ratio) or ratio <= 0 then return Unknown() end
					local amount = prefix[saved.side] / ratio
					if not Number(amount) then return Unknown() end
					entry.offset = math.floor(amount + 0.5)
					state.prefixes[key], state.kind = entry, "prefix"
					return state
				end
				if type(frame) ~= "nil" then
					local box = Box(frame)
					if not box then return Unknown() end
					entry.box, entry.offset = box, math.floor(prefix[saved.side] / box.ratio + 0.5)
					state.prefixes[key] = entry
					local gap = 4
					if saved.gap then
						local valid, value = pcall(saved.gap)
						if not valid or not Current() then return Unknown() end
						gap = value
					end
					if not Number(gap) or gap < 0 then return Unknown() end
					entry.gap = gap * box.ratio
					if not Number(entry.gap) then return Unknown() end
					prefix[saved.side] = prefix[saved.side] + box.height + entry.gap
					if not Number(prefix[saved.side]) then return Unknown() end
					box.key, box.side = key, saved.side
					state.boxes[#state.boxes + 1] = box
				end
				end
			end
			if not Current() then return Unknown() end
			nativeProof = true
			nativeSaved = NativeState()
			nativeProof = false
			if not nativeSaved or not NativeCurrent() then return Unknown() end
			return state
		end)
		readingGeometry = nil
		if not passed or not result or not Current() then return Unknown() end
		return result
	end
end

-- This view never turns a failed member callback or unreadable size into
-- an inactive member, a zero height, or the legacy default gap.
function Stack.LayoutBounds() return readGeometry() end
nativeLayoutBounds = function() return readGeometry(nil, nil, true) end
function Stack.Offset(key, receiver)
	if not K.Plain(key) or type(key) ~= "string" then
		if type(receiver) ~= "nil" then return nil, "unavailable" end
		return 0
	end
	local explicit = type(receiver) ~= "nil"
	if explicit and (not K.Plain(receiver) or (type(receiver) ~= "table" and type(receiver) ~= "userdata")) then return nil, "unavailable" end
	if not bodySource then
		local amount = LegacyOffset(key)
		if explicit then return amount, "legacy" end
		return amount
	end
	local state = readingGeometry
	if state then
		local entry = state.prefixes[key]
		if entry and (not explicit or (K.Plain(receiver) and rawequal(receiver, entry.frame))) and state.current() then
			if explicit then return entry.offset, "qualified" end
			return entry.offset
		end
		state.invalid = true
		if explicit then return nil, "unavailable" end
		return 0
	end
	state = readGeometry(key, receiver)
	if state.kind == "prefix" then
		local entry = state.prefixes[key]
		if entry and (not explicit or (K.Plain(receiver) and rawequal(receiver, entry.frame))) and state.current() then
			if explicit then return entry.offset, "qualified" end
			return entry.offset
		end
		if explicit and (entry or not state.specs[key]) then return nil, "unavailable" end
		if explicit then return LegacyOffset(key), "inactive" end
	elseif explicit and state.kind == "pending" then
		return LegacyOffset(key), "pending"
	elseif explicit then
		return nil, "unavailable"
	end
	-- Older callers still get a plain number. It is not a measured size;
	-- layout code reads LayoutBounds instead.
	return LegacyOffset(key)
end

-- Registered keys: above before below, closest to the row first.
function Stack.Keys()
	local keys = {}
	for key in pairs(members) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b)
		local sa, sb = members[a], members[b]
		if sa.side ~= sb.side then return sa.side == "ABOVE" end
		return Before({ key = a, order = sa.order }, { key = b, order = sb.order })
	end)
	return keys
end

local function Signature()
	if bodySource then
		local state = readGeometry()
		if state.kind ~= "live" then return nil end
		local parts = { tostring(Stack.Width()), state.body.kind, tostring(state.body.above), tostring(state.body.below) }
		for _, part in ipairs(state.body.parts) do
			parts[#parts + 1] = ("%s:%.17g:%.17g:%.17g:%.17g"):format(part.key, part.l - state.body.rect.l,
				part.b - state.body.rect.b, part.r - part.l, part.t - part.b)
		end
		for _, entry in ipairs(state.entries) do
			if entry.box then parts[#parts + 1] = ("%s:%.17g:%.17g:%.17g"):format(entry.key, entry.box.height, entry.gap, entry.box.ratio) end
		end
		return table.concat(parts, "|"), state.body.frame, state
	end
	local parts = { tostring(Stack.Width()) }
	for _, side in ipairs({ "ABOVE", "BELOW" }) do
		for _, entry in ipairs(Stack.Members(side)) do
			parts[#parts + 1] = ("%s:%d:%d"):format(entry.key, math.floor(MemberHeight(entry.frame) + 0.5), MemberGap(entry.spec))
		end
	end
	return table.concat(parts, "|")
end

-- Re-lay every member when the width or the stack changed (or `force`).
function Stack.Refresh(force)
	if refreshing then return end
	local signature, bodyFrame, snapshot = Signature()
	if bodySource and not signature then return end
	if not force and signature == lastSignature and rawequal(bodyFrame, lastBodyFrame) then return end
	refreshing = true
	local width = Stack.Width()
	for _, key in ipairs(snapshot and snapshot.keys or Stack.Keys()) do
		if snapshot and not snapshot.current() then break end
		local saved = snapshot and snapshot.specs[key]
		local spec = saved and saved.spec or members[key]
		local relayout = saved and saved.relayout or (spec and spec.relayout)
		if relayout then
			local ok, err = pcall(relayout, width)
			if not ok then geterrorhandler()(err) end
			if snapshot and not snapshot.current() then break end
		end
	end
	refreshing = false
	-- The relayouts may have moved or resized members: remember the result.
	lastSignature, lastBodyFrame = Signature()
	if bodySource and lastSignature and E.RefreshWideConsumableLayout then E:RefreshWideConsumableLayout(bodySource.owner) end
end

-- A member showed, hid or changed size: re-lay the stack on the next frame.
local function RefreshOutOfCombat()
	if not InCombatLockdown() then Stack.Refresh() end
end

function Stack.Changed()
	if refreshing then return end
	E:Debounce("hud:stack", 0, RefreshOutOfCombat)
end

-- The row's width changes with the tracked spells: check now and then,
-- only while the stack has members and never in combat.
local ticker
local function StackTick()
	if next(members) and not InCombatLockdown() then Stack.Refresh() end
end

function Stack.Register(key, spec)
	local defaults = Stack.ORDER[key]
	spec.side = spec.side or (defaults and defaults.side) or "BELOW"
	spec.order = spec.order or (defaults and defaults.order) or 50
	members[key] = spec
	lastSignature = nil
	if not ticker then ticker = C_Timer.NewTicker(1, StackTick) end
end

function Stack.Unregister(key)
	members[key] = nil
	lastSignature = nil
	if ticker and not next(members) then
		ticker:Cancel()
		ticker = nil
	end
end

-- True while the stack's width check runs.
function Stack.Ticking()
	return ticker ~= nil
end

function Stack.IsRegistered(key)
	return members[key] ~= nil
end

---------------------------------------------------------------------------
-- The cooldown area: the cooldown rows, the class resources and what hangs
-- on the main row take up one block in the middle of the screen. A piece
-- that sits on a bar of its own next to that block (the totem timers kept
-- with a totem bar) asks which side of its bar is clear:
--   K.CooldownStack.SideFor(host, width, height[, gap])
--       -> the first of "ABOVE", "BELOW", "RIGHT" and "LEFT" where a piece
--          of that size covers none of the block (above and below centered
--          on the bar, right and left level with it); "ABOVE" when none
--          is clear, so a piece never jumps around.
-- Boxes come from EldoUI's own movers and frames only (never a secret
-- value), in screen units, and only the ones in use count.
---------------------------------------------------------------------------
Stack.AREA = {
	"EldoUI_Cooldowns", "EldoUI_CooldownsUtility", "EldoUI_CooldownsBuffs", "EldoUI_CooldownsBars",
	"EldoUI_CooldownsItems", "EldoUI_CooldownsTrinkets", "EldoUI_CooldownsMobility",
	"EldoUI_TrackingBars", "EldoUI_PlayerPower",
}

-- A frame's box in UIParent units, or nil.
function Stack.Box(frame)
	if not (frame and frame.GetRect) then return nil end
	local ok, left, bottom, width, height = pcall(frame.GetRect, frame)
	if not (ok and K.Plain(left, bottom, width, height)) then return nil end
	if type(left) ~= "number" or type(bottom) ~= "number" or type(width) ~= "number" or type(height) ~= "number" then return nil end
	if width <= 0 or height <= 0 then return nil end
	local scale = 1
	local okScale, own = pcall(frame.GetEffectiveScale, frame)
	local parentScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()
	if okScale and K.Plain(own, parentScale) and type(own) == "number" and type(parentScale) == "number" and parentScale > 0 then
		scale = own / parentScale
	end
	return { l = left * scale, b = bottom * scale, r = (left + width) * scale, t = (bottom + height) * scale }
end

local function InUse(mover)
	if not (E.IsMoverActive and E:IsMoverActive(mover)) then return false end
	local frame = mover.frame
	return not frame or not frame.IsShown or frame:IsShown()
end

-- The boxes of the cooldown area that show right now.
function Stack.AreaBoxes()
	local boxes = {}
	for _, name in ipairs(Stack.AREA) do
		local mover = E.movers and E.movers[name]
		if mover and InUse(mover) then
			local box = Stack.Box(mover)
			if box then
				box.name = name
				boxes[#boxes + 1] = box
			end
		end
	end
	for _, side in ipairs({ "ABOVE", "BELOW" }) do
		for _, entry in ipairs(Stack.Members(side)) do
			local box = Stack.Box(entry.frame)
			if box then
				box.name = entry.key
				boxes[#boxes + 1] = box
			end
		end
	end
	return boxes
end

local function Overlap(a, b)
	return math.min(a.r, b.r) - math.max(a.l, b.l) > 1 and math.min(a.t, b.t) - math.max(a.b, b.b) > 1
end

-- True when the box covers none of the cooldown area.
function Stack.Clear(box, boxes)
	for _, other in ipairs(boxes or Stack.AreaBoxes()) do
		if Overlap(box, other) then return false end
	end
	return true
end

function Stack.SideFor(host, width, height, gap)
	local bar = Stack.Box(host)
	if not (bar and type(width) == "number" and type(height) == "number") then return "ABOVE" end
	gap = type(gap) == "number" and gap or 4
	local middle = (bar.l + bar.r) / 2
	local left, right = middle - width / 2, middle + width / 2
	local level = (bar.b + bar.t) / 2
	local low, high = level - height / 2, level + height / 2
	local boxes = Stack.AreaBoxes()
	local spots = {
		{ "ABOVE", { l = left, r = right, b = bar.t + gap, t = bar.t + gap + height } },
		{ "BELOW", { l = left, r = right, b = bar.b - gap - height, t = bar.b - gap } },
		{ "RIGHT", { l = bar.r + gap, r = bar.r + gap + width, b = low, t = high } },
		{ "LEFT", { l = bar.l - gap - width, r = bar.l - gap, b = low, t = high } },
	}
	for _, spot in ipairs(spots) do
		if Stack.Clear(spot[2], boxes) then return spot[1] end
	end
	return "ABOVE"
end
