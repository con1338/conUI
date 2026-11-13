-- EldoUI Blizzard elements: one "Let EldoUI change this" switch for every
-- part of Blizzard's UI that EldoUI can touch.
--
-- Every element (player frame, minimap, group finder, ...) is listed in
-- Data/BlizzardElements.lua, generated from Blizzard's UI source for
-- WoW: Forever. Per profile each element has:
--   enabled   the master switch. Off = pure Blizzard default: EldoUI does not
--             hook, skin, move or hide it, and sets no CVars for it.
--   skin      EldoUI look (fonts, borders, textures)
--   move      EldoUI mover and scale (off = Blizzard's Edit Mode position)
--   hide      hide Blizzard's element
--   replace   EldoUI's own frame instead of Blizzard's (implies hide)
--   improve   extra info and features (item levels, coordinates, ...)
-- Only the actions Blizzard's addon rules allow for an element are offered.
--
-- Modules do the actual work and register a handler per element:
--   E:RegisterBlizzardHandler("minimap", {
--       owner   = "Minimap",                 -- module that does the work
--       apply   = function(state) end,       -- state = the element's settings
--       undo    = function() end,            -- back to Blizzard (may need a reload)
--       reload  = { skin = true },           -- actions only undone by /reload
--       install = { skin = true, move = true },  -- what the installer turns on
--       legacy  = function() return true end,    -- v0.5.0 touched it: keep it on after the update
--       owns    = true,                       -- this module owns the element (see below)
--   })
-- and ask before touching a Blizzard frame:
--   if E:BlizzardAllowed("minimap", "skin") then ... end
-- Protected frames go through E:RunOutOfCombat as always.
--
-- One owner per element. The handler marked `owns` owns its element; with
-- no such mark, the first module that registers one does. Another module
-- that registers a handler for the same element joins the owner's hook
-- list (E:HookBlizzardElement registers one that way on purpose): its
-- apply runs after the owner's, whatever order the modules were turned on
-- in, and on an element whose owner is marked `owns` its undo runs before
-- the owner's. A second handler marked `owns` from another module is
-- refused with an error that names both modules.
local _, E = ...
local L = E.L
local Key = E.Key

local ACTIONS = { "skin", "move", "hide", "replace", "improve" }
local ACTION_LABEL = {
	skin = Key("Skin"),
	move = Key("Move and scale"),
	hide = Key("Hide"),
	replace = Key("Replace with EldoUI's frame"),
	improve = Key("Improve (extra info)"),
}
-- One word each for the status line of an element.
local ACTION_SHORT = { skin = Key("Skin"), move = Key("Move"), improve = Key("Improve") }
local ACTION_DESC = {
	skin = Key("EldoUI's look: fonts, 1 px borders, flat textures and the accent color."),
	move = Key("Move and scale it with EldoUI's movers. Off keeps Blizzard's Edit Mode position."),
	hide = Key("Hides Blizzard's version completely. EldoUI's own frame for it, if there is one, stays."),
	replace = Key("Use EldoUI's own frame and hide Blizzard's."),
	improve = Key("Extra information and small features on top of Blizzard's element."),
}
-- The names stay English while the file loads and are shown translated.
-- Module pages that mirror an element's switches use the same names:
-- E.BLIZZARD_ACTION_LABEL / E.BLIZZARD_ACTION_DESC.
E.BLIZZARD_ACTION_LABEL, E.BLIZZARD_ACTION_DESC = ACTION_LABEL, ACTION_DESC
-- Sub-switch defaults when the master switch goes on.
local ACTION_DEFAULT = { skin = true, move = false, hide = false, replace = false, improve = true }
local MIGRATION_VERSION = 1

E.blizzardElements = {}      -- [id] = data (from Data/BlizzardElements.lua) + handlers
E.blizzardElementOrder = {}  -- ids in catalog order
local handlers = {}          -- [id] = { handler, ... }: the owner's first, then its hook list
local elementOwner = {}      -- [id] = the module name that owns the element
local claimed = {}           -- [id] = true when the owner marked its handler `owns`
-- Elements whose Blizzard look only comes fully back after a reload, in the
-- order they came (one reload question names them).
local Reload = { ids = {}, seen = {} }
local Windows = {}           -- the Blizzard windows choice (filled below)

for _, data in ipairs(E.blizzardElementData or {}) do
	data.handlers = {}
	data.allowed = {}
	for _, action in ipairs(data.actions) do data.allowed[action] = true end
	E.blizzardElements[data.id] = data
	E.blizzardElementOrder[#E.blizzardElementOrder + 1] = data.id
end

-- Profile defaults: every element starts as Blizzard default.
E.defaults.blizzard = {}
for id, data in pairs(E.blizzardElements) do
	local defaults = { enabled = false }
	for _, action in ipairs(data.actions) do defaults[action] = ACTION_DEFAULT[action] end
	E.defaults.blizzard[id] = defaults
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------
function E:BlizzardState(id)
	local all = self.db and self.db.blizzard
	return all and all[id]
end

-- True when the player lets EldoUI change element `id` (and, when given,
-- the action is switched on and allowed for it).
function E:BlizzardAllowed(id, action)
	local data = self.blizzardElements[id]
	local state = self:BlizzardState(id)
	if not data or not state or not state.enabled then return false end
	if not action then return true end
	if not data.allowed[action] then return false end
	if action == "hide" and state.replace and data.allowed.replace then return true end
	return state[action] and true or false
end

-- The reason a setting can't work yet because element `id` (or one of its
-- actions) is switched off on the Blizzard UI page, or nil when it can.
function E:BlizzardNeedsReason(id, action)
	if self:BlizzardAllowed(id, action) then return nil end
	local data = self.blizzardElements[id]
	local title = data and L[data.title] or tostring(id)
	if not action or not (data and data.allowed[action]) then
		return L["Turn on Blizzard UI > %s first."]:format(title)
	end
	return L["Turn on Blizzard UI > %s: %s first."]:format(title, L[ACTION_LABEL[action]])
end

-- A `disabled` function for a config row that needs an element switch:
-- the row stays visible but grayed, and its tooltip names the switch.
-- action: "skin", "move", "hide", "replace", "improve", or nil for the
-- element's own "Let EldoUI change this". `other` is the row's own
-- disabled function, asked once the switch is on.
function E:BlizzardNeeds(id, action, other)
	local data = self.blizzardElements[id]
	if not data or (action and not data.allowed[action]) then
		geterrorhandler()(("EldoUI: BlizzardNeeds(%s, %s): no such element switch"):format(tostring(id), tostring(action)))
	end
	return function(...)
		local reason = E:BlizzardNeedsReason(id, action)
		if reason then return reason end
		if other then return other(...) end
		return false
	end
end

-- True when EldoUI should keep Blizzard's frame hidden: Hide is on, or
-- Replace is on.
function E:BlizzardHidden(id)
	return self:BlizzardAllowed(id, "hide") or self:BlizzardAllowed(id, "replace")
end

---------------------------------------------------------------------------
-- Handlers
---------------------------------------------------------------------------
-- True when the handler is part of the owner's hook list (another
-- module's handler on an owned element).
local function IsHook(id, handler)
	return handler.owner ~= nil and elementOwner[id] ~= nil and handler.owner ~= elementOwner[id]
end

-- Put the owner's handlers (and handlers of no module) first, the hook
-- list after them, each in the order it registered.
local function Order(id, list)
	local own, hooks = {}, {}
	for _, handler in ipairs(list) do
		if IsHook(id, handler) then hooks[#hooks + 1] = handler else own[#own + 1] = handler end
	end
	for index = #list, 1, -1 do list[index] = nil end
	for _, handler in ipairs(own) do list[#list + 1] = handler end
	for _, handler in ipairs(hooks) do list[#list + 1] = handler end
end

function E:RegisterBlizzardHandler(id, handler)
	local data = self.blizzardElements[id]
	assert(data, ("EldoUI: unknown Blizzard element %q"):format(tostring(id)))
	local module = handler.owner
	if module and handler.owns then
		if claimed[id] and elementOwner[id] ~= module then
			geterrorhandler()(("EldoUI: Blizzard element %q already belongs to %s; the handler of %s was refused. One element has one owner: add it to the owner's hook list with E:HookBlizzardElement(%q, handler)."):format(
				id, tostring(elementOwner[id]), tostring(module), id))
			return nil
		end
		elementOwner[id], claimed[id] = module, true
	elseif module and not elementOwner[id] then
		elementOwner[id] = module
	end
	handlers[id] = handlers[id] or {}
	table.insert(handlers[id], handler)
	table.insert(data.handlers, handler)
	Order(id, handlers[id])
	Order(id, data.handlers)
	return handler
end

-- A handler for an element another module owns: it joins the owner's hook
-- list and never takes the element over.
function E:HookBlizzardElement(id, handler)
	handler.owns = nil
	return self:RegisterBlizzardHandler(id, handler)
end

-- The module that owns element `id`, and whether it said so (`owns`).
function E:BlizzardElementOwner(id)
	return elementOwner[id], claimed[id] or false
end

-- The modules on the owner's hook list for element `id`, in the order they
-- run.
function E:BlizzardElementHooks(id)
	local list, seen = {}, {}
	for _, handler in ipairs(handlers[id] or {}) do
		if IsHook(id, handler) and not seen[handler.owner] then
			seen[handler.owner] = true
			list[#list + 1] = handler.owner
		end
	end
	return list
end

local function OwnerActive(handler)
	if not handler.owner then return true end
	local module = E:GetModule(handler.owner)
	return module and module.active
end

function Reload.Mark(id)
	if Reload.seen[id] then return end
	Reload.seen[id] = true
	Reload.ids[#Reload.ids + 1] = id
end

function Reload.Pending()
	return #Reload.ids > 0
end

function Reload.Clear()
	Reload.ids, Reload.seen = {}, {}
end

-- A copy to put back later (a quiet change leaves the question as it was).
function Reload.Save()
	return { ids = CopyTable(Reload.ids), seen = CopyTable(Reload.seen) }
end

function Reload.Restore(saved)
	Reload.ids, Reload.seen = saved.ids, saved.seen
end

-- Re-apply one element after a change: handlers whose module is on get
-- apply(state); when the element went back to Blizzard default they get undo().
-- The owner applies first and its hook list after it; on an element whose
-- owner said so (`owns`), the hook list comes off before the owner does.
local function ApplyElement(id, previous)
	local data = E.blizzardElements[id]
	local state = E:BlizzardState(id)
	if not data or not state then return end
	local list = handlers[id] or {}
	if claimed[id] and previous and previous.enabled and not state.enabled then
		local reversed = {}
		for index = #list, 1, -1 do reversed[#reversed + 1] = list[index] end
		list = reversed
	end
	for _, handler in ipairs(list) do
		if OwnerActive(handler) then
			local wasOn = previous and previous.enabled
			if state.enabled and handler.apply then
				E:RunOutOfCombat(function()
					local ok, err = pcall(handler.apply, E:BlizzardState(id), id)
					if not ok then geterrorhandler()(err) end
				end)
			elseif not state.enabled and wasOn and handler.undo then
				E:RunOutOfCombat(function()
					local ok, err = pcall(handler.undo, id)
					if not ok then geterrorhandler()(err) end
				end)
			end
			if previous and handler.reload then
				for action in pairs(handler.reload) do
					local before = previous.enabled and previous[action]
					local now = state.enabled and state[action]
					if before and not now then Reload.Mark(id) end
				end
			end
			-- Modules re-read their settings (they check BlizzardAllowed).
			if handler.owner and handler.refreshModule ~= false then
				local module = E:GetModule(handler.owner)
				if module and module.active and module.OnProfileChanged then
					E:RunOutOfCombat(function()
						local ok, err = pcall(module.OnProfileChanged, module)
						if not ok then geterrorhandler()(err) end
					end)
				end
			end
		end
	end
	if previous and previous.enabled and not state.enabled then
		E:RestoreCVars(id)
	end
end

function E:ApplyBlizzardElements()
	for _, id in ipairs(self.blizzardElementOrder) do ApplyElement(id) end
end

-- Change one switch from code, options or /eui blizz. `quiet` skips the
-- reload question: the options window marks the row and shows its own
-- reload banner instead.
function E:SetBlizzardElement(id, key, value, quiet)
	local state = self:BlizzardState(id)
	local data = self.blizzardElements[id]
	if not state or not data then return false end
	if key ~= "enabled" and not data.allowed[key] then return false end
	local previous = CopyTable(state)
	state[key] = value and true or false
	-- A window switched on takes the look the Blizzard windows choice asks for.
	if key == "enabled" and state.enabled and not previous.enabled then Windows.OnEnable(id, state) end
	ApplyElement(id, previous)
	if quiet then Reload.Clear() else self:AskReload() end
	return true
end

-- The titles of a list of elements for one line of text: "Minimap, Chat"
-- or "Minimap, Chat and 4 more".
local function ElementList(ids)
	local titles = {}
	for _, id in ipairs(ids) do
		local data = E.blizzardElements[id]
		titles[#titles + 1] = data and L[data.title] or tostring(id)
	end
	if #titles <= 3 then return table.concat(titles, ", ") end
	return L["%s, %s and %d more"]:format(titles[1], titles[2], #titles - 2)
end

-- One reload question after switches that need it (secure /reload button,
-- see E:ShowReloadPrompt: Forever blocks ReloadUI() from addon code). It
-- names only the elements whose handler declares that the switch just
-- turned off needs a reload; a switch that undoes itself asks nothing.
function E:AskReload()
	if not Reload.Pending() then return end
	local ids = Reload.ids
	Reload.Clear()
	self:ShowReloadPrompt(L["Blizzard's own look comes fully back after a reload: %s."]:format(ElementList(ids)))
end

---------------------------------------------------------------------------
-- The reload declaration: one answer per module to "does switching it off
-- need a reload?", read by the options window, the reload question and the
-- profile switch.
--   reload = false            never (E:NewModule)
--   reload = true             always; the module's title is the reason
--   reload = { "Reason" }     always, with these reasons
-- A module that leaves it out is answered by the Blizzard elements it
-- handles: an element that is on, with a switch on that its handler marks
-- `reload` (Skin, Move, Hide or Replace), only comes fully back after a
-- reload. A module that handles none needs no reload to switch off.
---------------------------------------------------------------------------
local function HoldsReload(handler, state)
	for action, on in pairs(handler.reload) do
		if on and state[action] then return true end
	end
	return false
end

-- The reasons switching the module off needs a reload (player-readable
-- titles); an empty list when it needs none.
function E:ModuleReloadReasons(module)
	if type(module) == "string" then module = self:GetModule(module) end
	local reasons = {}
	if type(module) ~= "table" then return reasons end
	local descriptor = self.GetModuleDescriptor and self:GetModuleDescriptor(module)
	local declared = descriptor and descriptor.reload
	if declared == true then
		reasons[1] = L[module.title]
		return reasons
	elseif type(declared) == "table" then
		for _, reason in ipairs(declared) do
			if type(reason) == "string" then reasons[#reasons + 1] = L[reason] end
		end
		if #reasons == 0 and next(declared) ~= nil then reasons[1] = L[module.title] end
		return reasons
	elseif declared == false then
		return reasons
	end
	for _, id in ipairs(self.blizzardElementOrder) do
		local state = self:BlizzardState(id)
		if state and state.enabled then
			for _, handler in ipairs(handlers[id] or {}) do
				if handler.owner == module.name and type(handler.reload) == "table" and HoldsReload(handler, state) then
					reasons[#reasons + 1] = L[self.blizzardElements[id].title]
					break
				end
			end
		end
	end
	return reasons
end

function E:ModuleNeedsReload(module)
	return #self:ModuleReloadReasons(module) > 0
end

-- Every element (or one category) back to Blizzard default. `quiet`
-- skips the reload question; the result says whether a reload is needed.
function E:ResetBlizzard(category, quiet)
	for _, id in ipairs(self.blizzardElementOrder) do
		local data = self.blizzardElements[id]
		local state = self:BlizzardState(id)
		if state and (not category or data.category == category) and state.enabled then
			local previous = CopyTable(state)
			state.enabled = false
			ApplyElement(id, previous)
		end
	end
	if not category then self:RestoreCVars() end
	local needed = Reload.Pending()
	if quiet then Reload.Clear() else self:AskReload() end
	return needed
end

-- A copy of every element's switches, and the way back to it (the
-- installer's "Revert this"). An element that changes goes through its
-- handlers like a click on its switch: apply, or undo when it is switched
-- off, and the CVars it set come back. Returns how many changed.
function E:SnapshotBlizzard()
	return CopyTable(self.db and self.db.blizzard or {})
end

function E:RestoreBlizzard(snapshot)
	if type(snapshot) ~= "table" then return 0 end
	local changed = 0
	for _, id in ipairs(self.blizzardElementOrder) do
		local state, saved = self:BlizzardState(id), snapshot[id]
		if state and type(saved) == "table" and not self.DeepEqual(state, saved) then
			local previous = CopyTable(state)
			wipe(state)
			for key, value in pairs(saved) do state[key] = value end
			ApplyElement(id, previous)
			changed = changed + 1
		end
	end
	self:AskReload()
	return changed
end

---------------------------------------------------------------------------
-- Blizzard windows: one choice for how Blizzard's own windows look
-- (general.blizzardWindows).
--   keep      writes nothing: every window keeps its own Skin switch
--   layout    what the active layout was made for (its `windows` field:
--             "original" or "match", match when it names none)
--   original  Blizzard's own look
--   match     painted in the skin
-- Only the Skin switch of the windows below is written, and only while the
-- player lets EldoUI change that window. "Let EldoUI change this", Move,
-- Hide, Replace and Improve are never written, so this choice never gives
-- EldoUI new permissions. Each write is kept as { from, to } in
-- general.blizzardWindowsRestore: a new choice first puts back what the old
-- one set, as long as the switch still holds it. A switch the player
-- changed since stays as the player set it, through every later choice.
---------------------------------------------------------------------------
E.windowLookElements = {
	"character-frame", "inspect-frame", "dressing-room", "item-socketing", "player-spells", "professions",
	"class-trainer", "legacy-achievements", "collections",
	"friends-frame", "communities-guild", "calendar", "group-finder", "pvp-match",
	"bags-containers", "bank", "merchant", "mail", "auction-house", "trade", "loot-window",
	"quest-gossip-npc", "pet-stable", "barber-shop",
	"world-map-quest-log", "flight-map",
	"game-menu", "settings-panel", "addon-list", "keybindings", "macros-click-binding", "dialogs", "menus",
}
Windows.MODES = { keep = true, layout = true, original = true, match = true }
Windows.offNeedsReload = {}  -- [id] = true: this session turned its Skin off and only a reload undoes the paint
E.defaults.general.blizzardWindowsRestore = E.defaults.general.blizzardWindowsRestore or {}

-- The saved choice ("keep" for anything unknown).
function E:BlizzardWindowsMode()
	local general = self.db and self.db.general
	local mode = general and general.blizzardWindows
	return Windows.MODES[mode] and mode or "keep"
end

-- The look the choice asks for: "original", "match", or nil for keep.
function E:BlizzardWindowsLook()
	local mode = self:BlizzardWindowsMode()
	if mode == "keep" then return nil end
	if mode == "layout" then
		local general = self.db.general
		local layout = self.layouts and (self.layouts[general.layout] or self.layouts[self.defaults.general.layout])
		local windows = type(layout) == "table" and layout.windows
		return windows == "original" and "original" or "match"
	end
	return mode
end

-- The saved record of what the choice wrote, [id] = { from, to }.
function Windows.Record()
	local general = E.db and E.db.general
	if not general then return nil end
	if type(general.blizzardWindowsRestore) ~= "table" then general.blizzardWindowsRestore = {} end
	return general.blizzardWindowsRestore
end

function Windows.Listed()
	if not Windows.listed then
		Windows.listed = {}
		for _, id in ipairs(E.windowLookElements) do Windows.listed[id] = true end
	end
	return Windows.listed
end

-- The state of a listed window the choice may write: the player lets EldoUI
-- change it and Skin is offered for it.
function Windows.Writable(id)
	local data, state = E.blizzardElements[id], E:BlizzardState(id)
	if Windows.Listed()[id] and data and data.allowed.skin and state and state.enabled then return state end
end

-- What the Skin switch of one window should be: true/false, or nil to leave
-- it. Updates the record. `look` is E:BlizzardWindowsLook().
function Windows.Target(id, now, record, look)
	local entry = record[id]
	if type(entry) ~= "table" or type(entry.from) ~= "boolean" or type(entry.to) ~= "boolean" then entry = nil end
	local target
	if entry then
		-- The player changed it since: theirs.
		if now ~= entry.to then return nil end
		if look then target = look == "match" else target = entry.from end
	elseif look then
		target = look == "match"
	else
		return nil
	end
	local from = entry and entry.from
	if from == nil then from = now end
	if target == from then record[id] = nil else record[id] = { from = from, to = target } end
	return target
end

-- A listed window that was just switched on (the Blizzard UI page, a module,
-- the setup) takes the chosen look before its handlers run. It was off, so
-- nothing was painted yet and no reload is needed. A record left from before
-- it was switched off no longer says anything: switching on starts afresh.
function Windows.OnEnable(id, state)
	local record = Windows.Record()
	if record then record[id] = nil end
	local look = E:BlizzardWindowsLook()
	if not (record and look and Windows.Writable(id)) then return end
	local target = Windows.Target(id, state.skin and true or false, record, look)
	if target ~= nil then state.skin = target end
end

-- Apply the choice to every listed window. The old choice's writes are put
-- back by value in the same pass (a window that ends on the same look is not
-- touched twice). `quiet` skips the reload question; the second result says
-- whether a reload is needed to take the paint fully off.
-- Returns changed (how many Skin switches changed), needsReload.
function E:ApplyBlizzardWindows(quiet)
	local record = Windows.Record()
	if not record then return 0, false end
	local look = self:BlizzardWindowsLook()
	local before = Reload.Save()
	local changed, needed = 0, false
	for _, id in ipairs(self.windowLookElements) do
		local state = Windows.Writable(id)
		if state then
			local now = state.skin and true or false
			local target = Windows.Target(id, now, record, look)
			if target ~= nil and target ~= now then
				local marked = Reload.seen[id]
				local previous = CopyTable(state)
				state.skin = target
				ApplyElement(id, previous)
				if Reload.seen[id] and not marked then
					Windows.offNeedsReload[id] = true
					needed = true
				elseif target then
					Windows.offNeedsReload[id] = nil
				end
				changed = changed + 1
			end
		end
	end
	if quiet then Reload.Restore(before) else self:AskReload() end
	return changed, needed
end

-- Pick the choice and apply it. Returns true when the mode is known, and
-- whether a reload is needed (the options window shows it in its banner).
function E:SetBlizzardWindows(mode, quiet)
	if not (Windows.MODES[mode] and self.db and self.db.general) then return false, false end
	self.db.general.blizzardWindows = mode
	local _, needed = self:ApplyBlizzardWindows(quiet)
	return true, needed
end

-- True when some part of EldoUI paints window `id` when its Skin switch is
-- on: one of its handlers sets Skin up or takes it back off.
function E:BlizzardWindowHasSkin(id)
	local data = self.blizzardElements[id]
	for _, handler in ipairs(data and data.handlers or {}) do
		if (handler.install and handler.install.skin) or (handler.reload and handler.reload.skin)
			or (handler.restore and handler.restore.skin) then return true end
	end
	return false
end

-- Where the look of a listed window comes from, for its row on the Blizzard
-- UI page: "choice" (the Blizzard windows choice set it, or it already looks
-- the way the choice asks), "own" (the player's pick: the choice is Keep as
-- set, or the switch was changed by hand since) or "nohandler" (no EldoUI
-- skin for it yet), with the text to show. nil for a window EldoUI may not
-- change or one that is not on the list.
-- Shown translated: L["Look: set by the Blizzard windows choice on the Appearance page."],
-- L["Look: your own pick. The Blizzard windows choice on the Appearance page leaves it as you set it."],
-- L["Look: no EldoUI skin for this window yet, so it keeps Blizzard's look."]
Windows.SOURCE_TEXT = {
	choice = "Look: set by the Blizzard windows choice on the Appearance page.",
	own = "Look: your own pick. The Blizzard windows choice on the Appearance page leaves it as you set it.",
	nohandler = "Look: no EldoUI skin for this window yet, so it keeps Blizzard's look.",
}
function E:BlizzardWindowSkinSource(id)
	local state = Windows.Writable(id)
	if not state then return nil end
	local key
	if not self:BlizzardWindowHasSkin(id) then
		key = "nohandler"
	else
		local look = self:BlizzardWindowsLook()
		local now = state.skin and true or false
		local entry = (Windows.Record() or {})[id]
		if type(entry) == "table" and type(entry.to) == "boolean" then
			key = (entry.to == now and look) and "choice" or "own"
		elseif look and now == (look == "match") then
			key = "choice"
		else
			key = "own"
		end
	end
	return key, L[Windows.SOURCE_TEXT[key]]
end

-- Counts for the Appearance page: listed windows, how many EldoUI may change
-- (allowed), of those how many are skinned or original, how many have no
-- EldoUI skin yet (unhandled: they keep Blizzard's look whatever the switch
-- says), how many the player set by hand against the choice (own), how many
-- stay Blizzard's (not allowed), and whether a reload is still needed for
-- Blizzard's look to come fully back.
function E:BlizzardWindowsSummary()
	local summary = { mode = self:BlizzardWindowsMode(), look = self:BlizzardWindowsLook(), listed = #self.windowLookElements,
		allowed = 0, skinned = 0, original = 0, unhandled = 0, own = 0, blizzard = 0, reload = false }
	local record = Windows.Record() or {}
	for _, id in ipairs(self.windowLookElements) do
		local state = Windows.Writable(id)
		if state then
			summary.allowed = summary.allowed + 1
			local now = state.skin and true or false
			if not self:BlizzardWindowHasSkin(id) then
				summary.unhandled = summary.unhandled + 1
			elseif now then
				summary.skinned = summary.skinned + 1
			else
				summary.original = summary.original + 1
			end
			local entry = record[id]
			if type(entry) == "table" and type(entry.to) == "boolean" and entry.to ~= now then summary.own = summary.own + 1 end
			if Windows.offNeedsReload[id] and not now then summary.reload = true end
		else
			summary.blizzard = summary.blizzard + 1
		end
	end
	return summary
end

-- After the update to the element switches: elements EldoUI already changed
-- in v0.5.0 stay changed, so nobody's UI jumps back to Blizzard's.
local function Migrate()
	local db = E.db
	if (db.blizzardVersion or 0) >= MIGRATION_VERSION then return end
	local installed = EldoUIDB.installed and EldoUIDB.installed[E.charKey]
	if installed then
		for _, id in ipairs(E.blizzardElementOrder) do
			local state = db.blizzard[id]
			local data = E.blizzardElements[id]
			for _, handler in ipairs(handlers[id] or {}) do
				local ok, keep = true, false
				if handler.legacy then ok, keep = pcall(handler.legacy) end
				if ok and keep then
					state.enabled = true
					for action, on in pairs(handler.install or {}) do
						if data.allowed[action] then state[action] = on and true or false end
					end
				end
			end
		end
	end
	db.blizzardVersion = MIGRATION_VERSION
end

---------------------------------------------------------------------------
-- CVars: EldoUI remembers the player's own value before it changes a CVar,
-- so "Blizzard default" can put it back.
---------------------------------------------------------------------------
local function CVarSnapshot(root)
	if E:IsSecret(root) or type(root) ~= "table" or type(getmetatable(root)) ~= "nil" then return end
	local snapshot = rawget(root, "cvarSnapshot")
	if E:IsSecret(snapshot) or (snapshot ~= nil and (type(snapshot) ~= "table" or type(getmetatable(snapshot)) ~= "nil")) then return end
	if type(getmetatable(root)) ~= "nil" or not E:SafeEquals(rawget(_G, "EldoUIDB"), root)
		or not E:SafeEquals(rawget(root, "cvarSnapshot"), snapshot) then return end
	return snapshot, root
end

-- Read the current store without creating it or querying a game setting.
-- The root accompanies it so callers can verify the same saved-data owner.
function E:GetCVarSnapshot()
	return CVarSnapshot(rawget(_G, "EldoUIDB"))
end

-- A secure game setting refuses an addon's write (C_CVar.SetCVar), so
-- EldoUI never tries one and keeps no entry for it. A page that needs one
-- shows its value and builds the player's own chat command instead.
function E:CVarSecure(name)
	if not (C_CVar and C_CVar.GetCVarInfo) then return false end
	local ok, _, _, _, _, _, secure = pcall(C_CVar.GetCVarInfo, name)
	return ok and not self:IsSecret(secure) and secure == true
end

local secureTold = {}
function E:SetCVar(name, value, id, admit)
	if not (C_CVar and C_CVar.GetCVar) then return end
	if self:CVarSecure(name) then
		-- Once per setting, so a new case shows up in the error log.
		if not secureTold[name] and self.errors then
			secureTold[name] = true
			self.errors:Add("warning", ("EldoUI left the protected game setting %s unchanged."):format(tostring(name)))
		end
		return false
	end
	local current
	if type(admit) ~= "nil" then
		assert(not self:IsSecret(admit) and type(admit) == "function", "CVar admission callback must be a function")
		current = C_CVar.GetCVar(name)
		if self:IsSecret(current) or type(current) ~= "string" then return false end
		local allowed = admit(current)
		if self:IsSecret(allowed) or allowed ~= true then return false end
	end
	EldoUIDB.cvarSnapshot = EldoUIDB.cvarSnapshot or {}
	local snapshot = EldoUIDB.cvarSnapshot
	if type(admit) == "nil" then current = C_CVar.GetCVar(name) end
	if current == nil then return end -- not a CVar on this client
	if snapshot[name] == nil then
		snapshot[name] = { value = current, owner = id or "general" }
	end
	-- held: EldoUI writes this setting now (see E:ReleaseCVar).
	if snapshot[name].owner == (id or "general") then snapshot[name].held = true end
	value = tostring(value)
	if current ~= value then pcall(C_CVar.SetCVar, name, value) end
end

function E:RestoreCVars(id)
	local snapshot = EldoUIDB and EldoUIDB.cvarSnapshot
	if not snapshot or not (C_CVar and C_CVar.SetCVar) then return end
	for name, saved in pairs(snapshot) do
		if not id or saved.owner == id then
			if saved.value ~= nil then
				self:RunOutOfCombat(function() C_CVar.SetCVar(name, saved.value) end)
			end
			snapshot[name] = nil
		end
	end
end

-- Put one CVar back to the player's own value, for an option set back to
-- "Game setting". id (optional) only restores it if that element owns it.
function E:RestoreCVar(name, id)
	local snapshot = EldoUIDB and EldoUIDB.cvarSnapshot
	local saved = snapshot and snapshot[name]
	if not saved or (id and saved.owner ~= id) or not (C_CVar and C_CVar.SetCVar) then return end
	if saved.value ~= nil then
		self:RunOutOfCombat(function() C_CVar.SetCVar(name, saved.value) end)
	end
	snapshot[name] = nil
end

-- Drop an element's entry without writing: for a setting EldoUI no longer
-- changes and never could (a secure one an older version tried).
function E:ForgetCVar(name, id)
	local snapshot = self:GetCVarSnapshot()
	local saved = snapshot and snapshot[name]
	if saved and (not id or saved.owner == id) then snapshot[name] = nil end
end

-- For an element that shows the game's own part again: the player's value
-- comes back once. An entry without `held` is one an older version wrote
-- back on every load and kept; the game already has the player's value
-- (or their later choice), so the entry is only dropped.
function E:ReleaseCVar(name, id)
	local snapshot = self:GetCVarSnapshot()
	local saved = snapshot and snapshot[name]
	if not saved or (id and saved.owner ~= id) then return end
	if saved.held then
		self:RestoreCVar(name, id)
	else
		snapshot[name] = nil
	end
end

---------------------------------------------------------------------------
-- Load-on-demand Blizzard addons: run fn now if `addon` is loaded, else
-- once it loads.
---------------------------------------------------------------------------
local waiting = {}

function E:OnBlizzardAddOn(addon, fn)
	if not addon or C_AddOns.IsAddOnLoaded(addon) then
		fn()
		return
	end
	waiting[addon] = waiting[addon] or {}
	table.insert(waiting[addon], fn)
	E:RegisterEvent("ADDON_LOADED", function(_, _, loaded)
		local list = waiting[loaded]
		if not list then return end
		waiting[loaded] = nil
		for _, callback in ipairs(list) do
			local ok, err = pcall(callback)
			if not ok then geterrorhandler()(err) end
		end
	end, waiting)
end

---------------------------------------------------------------------------
-- The game's gamepad interface. While it is on, the controller cursor
-- walks the buttons of the game's own windows, so EldoUI's buttons inside
-- those windows (the talent planner row, Check ranks, the Training tab and
-- the trainer list) step aside and come back with the mouse interface.
-- Modules listen to INPUT_DEVICE_INTERFACE_TRANSITION to follow a swap.
---------------------------------------------------------------------------
function E:GamepadUIActive()
	local style = C_InputInterfaceStyle
	local types = Enum and Enum.InputDeviceInterfaceType
	if not (style and style.GetCurrentStyle and types and types.Gamepad) then return false end
	return style.GetCurrentStyle() == types.Gamepad
end

---------------------------------------------------------------------------
-- Options page: "Blizzard UI", one tab per category
---------------------------------------------------------------------------
local function Owners(id)
	local owners, seen = {}, {}
	for _, handler in ipairs(handlers[id] or {}) do
		if handler.owner and not seen[handler.owner] then
			seen[handler.owner] = true
			owners[#owners + 1] = handler.owner
		end
	end
	return owners
end

local function StatusText(id)
	local state = E:BlizzardState(id)
	local text = E.tokens.text
	if not state or not state.enabled then return E:TokenHex(text.dim) .. "Blizzard|r" end -- no-L: the name of Blizzard's own version
	if E:BlizzardAllowed(id, "replace") then return E:Highlight(L["Replaced"]) end
	if E:BlizzardAllowed(id, "hide") then return E:TokenHex(text.warn) .. L["Hidden"] .. "|r" end
	local parts = {}
	for _, action in ipairs({ "skin", "move", "improve" }) do
		if E:BlizzardAllowed(id, action) then parts[#parts + 1] = L[ACTION_SHORT[action]] end
	end
	return E:TokenHex(text.good) .. (#parts > 0 and table.concat(parts, ", ") or L["On"]) .. "|r"
end

local function ElementOptions(options, id)
	local data = E.blizzardElements[id]
	local function Off() local s = E:BlizzardState(id); return not (s and s.enabled) end
	table.insert(options, { type = "header", label = data.title, status = function() return StatusText(id) end })
	local owners = Owners(id)
	local names = {}
	for _, owner in ipairs(owners) do
		local module = E:GetModule(owner)
		names[#names + 1] = module and module.title and L[module.title] or owner
	end
	-- Switches whose handlers need a reload to take a change back off show
	-- in the window's reload banner, like every other page.
	local reloads = {}
	for _, handler in ipairs(handlers[id] or {}) do
		for action in pairs(handler.reload or {}) do reloads[action] = true end
	end
	local desc = #names > 0 and L["Changed by: %s."]:format(table.concat(names, ", ")) or L["No EldoUI module changes this element yet."]
	if data.unsure then desc = desc .. " " .. L["May not exist on every Forever build."] end
	table.insert(options, { type = "toggle", key = id .. ".enabled", label = "Let EldoUI change this",
		reload = next(reloads) and "off" or nil,
		desc = L["Off keeps Blizzard's own version, untouched."] .. " " .. desc })
	for _, action in ipairs(ACTIONS) do
		if data.allowed[action] then
			table.insert(options, { type = "toggle", key = id .. "." .. action, label = ACTION_LABEL[action],
				desc = ACTION_DESC[action], hidden = Off, reload = reloads[action] and "off" or nil })
		end
	end
	local notes, byReason = {}, {}
	for _, action in ipairs(ACTIONS) do
		local reason = data.notOffered and data.notOffered[action]
		if reason then
			local actions = byReason[reason]
			if not actions then
				actions = {}
				byReason[reason] = actions
				notes[#notes + 1] = reason
			end
			actions[#actions + 1] = ("\"%s\""):format(L[ACTION_LABEL[action]])
		end
	end
	for index, reason in ipairs(notes) do
		local actions = byReason[reason]
		local list = #actions > 1 and L["%s or %s"]:format(table.concat(actions, ", ", 1, #actions - 1), actions[#actions]) or actions[1]
		notes[index] = L["No %s: %s"]:format(list, L[reason])
	end
	if #notes > 0 then
		table.insert(options, { type = "description", label = table.concat(notes, " "), hidden = Off })
	end
	-- A window on the Blizzard windows list says where its look comes from.
	if Windows.Listed()[id] then
		table.insert(options, { type = "description", source = true,
			hidden = function() return E:BlizzardWindowSkinSource(id) == nil end,
			label = function()
				local _, text = E:BlizzardWindowSkinSource(id)
				return text or ""
			end })
	end
	for _, owner in ipairs(owners) do
		local module = E:GetModule(owner)
		if module and module.options then
			table.insert(options, { type = "execute", label = L["%s settings"]:format(L[module.title]), desc = "Open the settings of the module that does this.", hidden = Off,
				func = function() E:ToggleConfig("module:" .. owner) end })
		end
	end
end

-- The rows of one element as the Blizzard UI page shows them.
function E:BlizzardElementOptionsFor(id)
	local options = {}
	if self.blizzardElements[id] then ElementOptions(options, id) end
	return options
end

-- How many elements of a category EldoUI replaces (its own frame, or
-- Blizzard's hidden), changes in place (skin, move, improve) or leaves to
-- Blizzard.
function E:BlizzardCategoryCounts(categoryId)
	local own, changed, blizzard = 0, 0, 0
	for _, id in ipairs(self.blizzardElementOrder or {}) do
		if self.blizzardElements[id].category == categoryId then
			local state = self:BlizzardState(id)
			if not (state and state.enabled) then
				blizzard = blizzard + 1
			elseif self:BlizzardAllowed(id, "replace") or self:BlizzardAllowed(id, "hide") then
				own = own + 1
			else
				changed = changed + 1
			end
		end
	end
	return own, changed, blizzard
end

-- "2 EldoUI  3 skinned  7 Blizzard", each part in its status color.
local function CountsText(categoryId)
	local own, changed, blizzard = E:BlizzardCategoryCounts(categoryId)
	local text = E.tokens.text
	local parts = {}
	if own > 0 then parts[#parts + 1] = E:Highlight(L["%d EldoUI"]:format(own)) end
	if changed > 0 then parts[#parts + 1] = E:TokenHex(text.good) .. L["%d skinned"]:format(changed) .. "|r" end
	if blizzard > 0 then parts[#parts + 1] = E:TokenHex(text.dim) .. L["%d Blizzard"]:format(blizzard) .. "|r" end
	return table.concat(parts, "   ")
end

-- The open config window jumps to a category's tab of this page.
local function OpenCategory(category)
	if E.ShowConfigTab then E:ShowConfigTab("blizzard", category.title) end
end

local proxy = {}

local function BuildPage()
	local options = {
		{ type = "tab", label = "Overview" },
		{ type = "description", label = "One switch per part of Blizzard's UI. Off leaves Blizzard's version untouched; on lets you pick what EldoUI may do with it." },
	}
	-- One section per category: what EldoUI does there now, and the way
	-- to its tab.
	for _, category in ipairs(E.blizzardCategories or {}) do
		table.insert(options, { type = "header", label = category.title, status = function() return CountsText(category.id) end })
		table.insert(options, { type = "execute", label = "Open", desc = category.desc, width = 120,
			keywords = category.title, func = function() OpenCategory(category) end })
	end
	table.insert(options, { type = "header", label = "Reset" })
	table.insert(options, { type = "execute", label = "Blizzard default for everything", desc = "Turn every switch off and put your own CVar values back. If a part needs a reload to look like Blizzard's again, you are asked once.",
		func = function() E:ConfirmBlizzardReset() end })
	for _, category in ipairs(E.blizzardCategories or {}) do
		table.insert(options, { type = "tab", label = category.title })
		table.insert(options, { type = "description", label = category.desc })
		table.insert(options, { type = "execute", label = "Blizzard default for this tab", desc = "Turn every switch on this tab off and put your own CVar values back.",
			confirm = L["Turn every switch on this tab off and put your own CVar values back? The choices you made on this tab are lost."],
			func = function()
				-- The window's reload banner carries the reload, like every switch.
				if E:ResetBlizzard(category.id, true) and E.ConfigNeedsReload then
					E:ConfigNeedsReload("blizzard:" .. category.id, L["Blizzard default for %s"]:format(L[category.title]))
				end
				E:RefreshConfig()
			end })
		for _, id in ipairs(E.blizzardElementOrder) do
			if E.blizzardElements[id].category == category.id then ElementOptions(options, id) end
		end
	end
	local page = E:RegisterConfigPage("blizzard", "Blizzard UI", options,
		function()
			for id in pairs(E.blizzardElements) do
				local state = E:BlizzardState(id)
				proxy[id] = proxy[id] or {}
				for key, value in pairs(state) do proxy[id][key] = value end
			end
			return proxy
		end,
		function()
			for id, values in pairs(proxy) do
				local state = E:BlizzardState(id)
				for key, value in pairs(values) do
					if state[key] ~= value then E:SetBlizzardElement(id, key, value, true) end
				end
			end
		end, 1.6)
	page.desc = L["Choose which parts of Blizzard's UI EldoUI may change. Off = Blizzard default."]
end

-- The question on the shared dialog shell (E:ShowConfirm).
function E:ConfirmBlizzardReset()
	return self:ShowConfirm({ title = L["Reset to Blizzard default"],
		text = L["Put every part of Blizzard's UI back to Blizzard default? EldoUI's own frames stay. If a part needs a reload to finish, you are asked once."],
		accept = YES, cancel = NO, danger = true, onAccept = function()
			-- One reload question, and only when a switch needs it.
			E:ResetBlizzard(nil)
		end })
end

---------------------------------------------------------------------------
-- /eui blizz
---------------------------------------------------------------------------
local function FindElement(word)
	word = (word or ""):lower()
	if E.blizzardElements[word] then return word end
	local found, count
	count = 0
	for _, id in ipairs(E.blizzardElementOrder) do
		local title = E.blizzardElements[id].title:lower()
		if id:find(word, 1, true) == 1 or title:find(word, 1, true) == 1 then
			found, count = id, count + 1
		end
	end
	if count == 1 then return found end
end

local function Switch(word)
	word = (word or ""):lower()
	if word == "on" or word == "1" then return true end
	if word == "off" or word == "0" then return false end
	if word == "toggle" then return "toggle" end
end

E:AddCommand("blizz", "[element] [on | off | toggle] | <element> skin | move | hide | replace | improve on | off | reset [category]  which Blizzard parts EldoUI may change", function(arg)
	local first, second, third = strsplit(" ", (arg or ""):lower())
	if first == "" or first == nil then
		for _, category in ipairs(E.blizzardCategories) do
			E:Print(E:TextHex("accent") .. L[category.title] .. "|r")
			for _, id in ipairs(E.blizzardElementOrder) do
				if E.blizzardElements[id].category == category.id then
					print(("   %s  %s  (%s)"):format(id, StatusText(id), L[E.blizzardElements[id].title]))
				end
			end
		end
		return
	end
	if first == "reset" then
		if second and second ~= "" then
			local found
			for _, category in ipairs(E.blizzardCategories) do
				if category.id:lower() == second or L[category.title]:lower() == second then found = category end
			end
			if not found then
				local ids = {}
				for _, category in ipairs(E.blizzardCategories) do ids[#ids + 1] = category.id end
				E:Print(L["No Blizzard category %q. Use one of: %s."]:format(second, table.concat(ids, ", ")))
				return
			end
			E:ShowConfirm({ title = L["Reset to Blizzard default"], danger = true, accept = YES, cancel = NO,
				text = L["Turn every %s switch off and put your own CVar values back?"]:format(E:Highlight(L[found.title])),
				onAccept = function()
					E:ResetBlizzard(found.id)
					E:Print(L["Blizzard default for %s."]:format(L[found.title]))
				end })
		else
			E:ConfirmBlizzardReset()
		end
		return
	end
	local id = FindElement(first)
	if not id then
		E:Print(L["No Blizzard element %q. Type /eui blizz for the list."]:format(first))
		return
	end
	local key, word = "enabled", second
	if second and E.blizzardElements[id].allowed[second] then
		key, word = second, third
	elseif second and ACTION_LABEL[second] then
		local reason = E.blizzardElements[id].notOffered and E.blizzardElements[id].notOffered[second]
		E:Print(L["%s can't be used on %s: %s"]:format(L[ACTION_LABEL[second]], L[E.blizzardElements[id].title],
			reason and L[reason] or L["not offered"]))
		return
	end
	-- No word flips the switch; a word that is not on, off or toggle is a typo.
	local value = Switch(word)
	if value == nil and word and word ~= "" then
		E:Print(L["Use on, off or toggle after %s. Type %s for the list."]:format(E:Highlight(key == "enabled" and id or (id .. " " .. key)), E:Highlight("/eui blizz")))
		return
	end
	local state = E:BlizzardState(id)
	if value == "toggle" or value == nil then value = not state[key] end
	E:SetBlizzardElement(id, key, value)
	E:Print(("%s: %s"):format(L[E.blizzardElements[id].title], StatusText(id)))
end, "Layout & frames")

---------------------------------------------------------------------------
-- Keeping Blizzard frames where EldoUI puts them.
--
-- Blizzard puts its frames back in several ways on WoW: Forever:
--   * Edit Mode systems re-apply their saved anchor on every layout pass
--     (EditModeManagerFrame:UpdateLayoutInfo: login, EDIT_MODE_LAYOUTS_UPDATED,
--     a spec change, closing Edit Mode).
--   * Frames in their default Edit Mode position go back into the bottom,
--     right or player managed container, which re-parents them
--     (SetParent) and lays them out (SetPoint).
--   * Some frames re-anchor themselves when they show or a vehicle starts.
-- Every module that moves, hides or replaces a Blizzard frame uses these:
--
--   E:HideBlizzardFrame(frame, opts)  replaced or hidden (lesson 11a): the
--       frame goes to a hidden parent, and a SetParent post-hook sends it
--       back there whenever Blizzard re-parents it. opts.events = true also
--       stops its events (undone only by /reload). opts.check() = false
--       lets Blizzard have it right now. Protected frames wait for combat.
--   E:UnhideBlizzardFrame(frame[, parent])  back to its own parent.
--   E:KeepBlizzardParent(frame, parent, opts) / E:ReleaseBlizzardParent(frame)
--       the same guard for any parent (a fader, a holder, UIParent).
--   E:PinBlizzardFrame(frame, spec)   re-placed (11b and 11c): a SetPoint
--       post-hook puts the frame back on EldoUI's anchor whenever anything
--       else anchors it, and every Blizzard layout pass re-applies it.
--         spec.anchor(frame) -> point, relativeTo, relativePoint, x, y, or a
--             list of such points ({ { "TOP", holder, "TOP", 0, 0 }, ... }),
--             or nil for "no anchor now"
--         spec.anchor2(frame) -> a second point (optional)
--         spec.scale -> number or function() -> number (optional)
--         spec.size()  -> width, height (optional)
--         spec.parent -> frame or function() -> frame: keep this parent.
--             Managed frames (frame.isManagedFrame) get UIParent when no
--             parent is given, so the managed container neither re-parents
--             nor lays them out (without a write to the frame).
--         spec.active() / spec.wants(frame) -> false leaves it to Blizzard now
--         spec.pauseInEditMode = true: leave it to Edit Mode while it is open
--         spec.holder = frame: a SetPoint onto this frame counts as EldoUI's
--   E:UnpinBlizzardFrame(frame[, keep])  give it back; keep = true leaves it
--       where it is (Blizzard's next layout pass settles it).
--   E:OnBlizzardRelayout(owner, fn)   fn(reason) runs out of combat after
--       every Blizzard layout pass, for module work beyond a pin.
--   E:BlizzardRelayout(reason[, now]) runs that pass (next frame unless now).
--   E.BlizzardKeep.SetPoint / ClearAllPoints / SetScale: the plain widget
--       methods (SetPointBase ... on Edit Mode systems).
--
-- Taint rules kept: hooksecurefunc post-hooks only, no Blizzard function
-- or script is replaced and no field is written into a Blizzard frame (all
-- state lives in weak tables here). Edit Mode systems are moved with the
-- plain methods Blizzard keeps as SetPointBase / ClearAllPointsBase /
-- SetScaleBase, so EldoUI never runs Edit Mode's overrides (snap state,
-- OnEditModeSystemAnchorChanged). C_EditMode is never written. Hooks guard
-- IsForbidden() and never compare a secret value. Written for EldoUI.
---------------------------------------------------------------------------
local Keep = {}
E.BlizzardKeep = Keep

local weak = { __mode = "k" }
local issecret = issecretvalue or function() return false end

Keep.hider = CreateFrame("Frame")
Keep.hider:Hide()

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end
Keep.Usable = Usable

-- The plain widget method behind an Edit Mode override.
local function Raw(frame, method)
	return frame[method .. "Base"] or frame[method]
end
function Keep.ClearAllPoints(frame) Raw(frame, "ClearAllPoints")(frame) end
function Keep.SetPoint(frame, ...) Raw(frame, "SetPoint")(frame, ...) end
function Keep.SetScale(frame, scale) Raw(frame, "SetScale")(frame, scale) end

-- A protected frame cannot be changed in combat.
local function Locked(frame)
	return InCombatLockdown() and E.FrameCheck(frame, "IsProtected") and true or false
end
Keep.Locked = Locked

local function EditModeOpen()
	local manager = _G.EditModeManagerFrame
	return Usable(manager) and manager.IsEditModeActive and manager:IsEditModeActive() or false
end
Keep.EditModeOpen = EditModeOpen

local function Report(ok, err)
	if not ok then geterrorhandler()(err) end
end

local function Resolve(value, ...)
	if type(value) == "function" then return value(...) end
	return value
end

---------------------------------------------------------------------------
-- Shared hooks: one SetParent and one SetPoint post-hook per frame.
---------------------------------------------------------------------------
local parents = setmetatable({}, weak)     -- frame -> { parent = wanted, original = parent or false, check, events }
local pins = setmetatable({}, weak)        -- frame -> spec while EldoUI places it
local pinSaved = setmetatable({}, weak)    -- frame -> { points, parent, scale } before EldoUI did
local busy = setmetatable({}, weak)        -- frame -> true while EldoUI itself changes it
local queued = setmetatable({}, weak)      -- frame -> { [fn] = true } waiting for combat to end
local hookedParent = setmetatable({}, weak)
local hookedPoint = setmetatable({}, weak)
local hookedScale = setmetatable({}, weak)
local hookedSize = setmetatable({}, weak)
Keep.parents, Keep.pins = parents, pins

local ApplyParent, ApplyPin

local function Later(frame, fn)
	local pending = queued[frame]
	if not pending then
		pending = {}
		queued[frame] = pending
	end
	if pending[fn] then return end
	pending[fn] = true
	E:RunOutOfCombat(function()
		pending[fn] = nil
		fn(frame)
	end)
end

local function IsHidden(frame)
	local state = parents[frame]
	return state ~= nil and state.parent == Keep.hider
end

local function OnSetParent(frame)
	if busy[frame] then return end
	if parents[frame] then ApplyParent(frame) end
	if pins[frame] then ApplyPin(frame) end
end

local function HookParent(frame)
	if hookedParent[frame] then return end
	hookedParent[frame] = true
	hooksecurefunc(frame, "SetParent", OnSetParent)
end

---------------------------------------------------------------------------
-- (a) Hidden or replaced frames, and frames that keep an EldoUI parent
---------------------------------------------------------------------------
ApplyParent = function(frame)
	local state = parents[frame]
	if not state or busy[frame] then return end
	local parent, original, check, events = state.parent, state.original, state.check, state.events
	local function Owns()
		return parents[frame] == state and state.parent == parent and state.original == original
			and state.check == check and state.events == events
	end
	if check and not check(frame) then return end
	if not Owns() then return end
	local current = frame:GetParent()
	if not Owns() then return end
	if current == parent and not events then return end
	if Locked(frame) then
		Later(frame, ApplyParent)
		return
	end
	busy[frame] = true
	local ok, err = pcall(function()
		if events then
			state.events, events = nil, nil
			frame:UnregisterAllEvents()
			if not Owns() then return end
		end
		current = frame:GetParent()
		if not Owns() then return end
		if current ~= parent then frame:SetParent(parent) end
	end)
	busy[frame] = nil
	Report(ok, err)
end

-- Keep `frame` under `parent` whatever Blizzard re-parents it to.
-- opts.check(frame) -> false leaves it alone right now; opts.events stops
-- its events once. Returns true when the frame has that parent now.
function E:KeepBlizzardParent(frame, parent, opts)
	if not Usable(frame) or not Usable(parent) then return false end
	local state = parents[frame]
	if not state then
		state = { original = frame:GetParent() or false }
		parents[frame] = state
	end
	opts = opts or {}
	state.parent = parent
	state.check = opts.check
	if opts.events then state.events = true end
	HookParent(frame)
	ApplyParent(frame)
	return frame:GetParent() == parent
end

-- Back to the parent it had before EldoUI (or `parent`), out of combat.
function E:ReleaseBlizzardParent(frame, parent, expected, owns)
	local state = frame and parents[frame]
	if not state or (expected and state ~= expected) or (owns and not owns()) then return end
	if parents[frame] ~= state then return end
	parents[frame] = nil
	local target = parent or state.original or UIParent
	local function Back(f)
		if parents[f] then return end
		local current = f:GetParent()
		if parents[f] then return end
		if current ~= target then
			busy[f] = true
			local ok, err = pcall(f.SetParent, f, target)
			busy[f] = nil
			Report(ok, err)
		end
		if pins[f] then ApplyPin(f) end
	end
	if Locked(frame) then
		E:RunOutOfCombat(function() Back(frame) end)
	else
		Back(frame)
	end
end

-- The parent `frame` had before EldoUI changed it.
function E:BlizzardFrameParent(frame)
	local state = frame and parents[frame]
	if state then return state.original or nil end
	return frame and frame:GetParent()
end

-- Returns true when the frame is hidden now (false: waits for combat).
function E:HideBlizzardFrame(frame, opts)
	return self:KeepBlizzardParent(frame, Keep.hider, opts)
end

function E:IsBlizzardFrameHidden(frame)
	return frame ~= nil and IsHidden(frame)
end

function E:UnhideBlizzardFrame(frame, parent)
	if frame and IsHidden(frame) then self:ReleaseBlizzardParent(frame, parent) end
end
---------------------------------------------------------------------------
-- (b) and (c) Frames EldoUI places
---------------------------------------------------------------------------
local function Plain(...)
	for i = 1, select("#", ...) do
		if issecret((select(i, ...))) then return false end
	end
	return true
end

local function Points(frame, spec, owns)
	if not spec.anchor then return nil end
	local point, relativeTo, relativePoint, x, y = spec.anchor(frame)
	if owns and not owns() then return nil end
	if type(point) == "table" then return point end
	if not point then return nil end
	local list = { { point, relativeTo, relativePoint, x, y } }
	if spec.anchor2 then
		local p2, r2, rp2, x2, y2 = spec.anchor2(frame)
		if owns and not owns() then return nil end
		if p2 then list[2] = { p2, r2, rp2, x2, y2 } end
	end
	return list
end

local function WantedParent(frame, spec)
	if parents[frame] then return nil end -- E:KeepBlizzardParent decides
	local parent = Resolve(spec.parent)
	if parent then return parent end
	if frame.isManagedFrame then return UIParent end
end

local function Wanted(frame, spec)
	if spec.active and not spec.active() then return false end
	if pins[frame] ~= spec then return false end
	if spec.wants and not spec.wants(frame) then return false end
	if pins[frame] ~= spec then return false end
	if spec.pauseInEditMode and EditModeOpen() then return false end
	return true
end

ApplyPin = function(frame, replayed)
	local spec = pins[frame]
	if not spec then return end
	if busy[frame] then
		if spec.admit and type(busy[frame]) == "table" then busy[frame].again = spec end
		return
	end
	if IsHidden(frame) then return end
	if not Wanted(frame, spec) or pins[frame] ~= spec then return end
	if Locked(frame) then
		Later(frame, ApplyPin)
		return
	end
	local operation = spec.admit and {} or true
	busy[frame] = operation
	local ok, err = pcall(function()
		-- An opt-in owner can bind its current profile and independent
		-- placement channels once for this operation, including queued work.
		local guard = spec.admit and spec.admit(frame, "apply")
		if spec.admit and type(guard) ~= "function" then return end
		local function Owns() return pins[frame] == spec and (not guard or guard()) end
		if not Owns() then return end
		local parent = WantedParent(frame, spec)
		if not Owns() then return end
		if Usable(parent) then
			local current = frame:GetParent()
			if not Owns() then return end
			if current ~= parent then frame:SetParent(parent) end
			if not Owns() then return end
		end
		local scale = Resolve(spec.scale)
		if not Owns() then return end
		if scale and scale > 0 then
			local current = frame:GetScale()
			if not Owns() then return end
			if not Plain(current) or math.abs(current - scale) > 0.001 then Keep.SetScale(frame, scale) end
			if not Owns() then return end
		end
		if spec.size then
			local width, height = spec.size()
			if not Owns() then return end
			if width and height then frame:SetSize(width, height) end
			if not Owns() then return end
		end
		local points = Points(frame, spec, Owns)
		if not Owns() then return end
		if points and #points > 0 then
			Keep.ClearAllPoints(frame)
			if not Owns() then return end
			for _, p in ipairs(points) do
				Keep.SetPoint(frame, p[1], p[2] or UIParent, p[3] or p[1], p[4] or 0, p[5] or 0)
				if not Owns() then return end
			end
		end
		if spec.applied then
			spec.applied(frame, scale, points)
			if not Owns() then return end
		end
	end)
	busy[frame] = nil
	Report(ok, err)
	if type(operation) == "table" and operation.again and pins[frame] == operation.again then
		if replayed then
			Report(false, "Blizzard frame placement changed repeatedly during its update")
		else
			ApplyPin(frame, true)
		end
	end
end
Keep.ApplyPin = ApplyPin

-- Re-anchor only when something else anchored the frame (never in a loop:
-- our own SetPoint calls run with busy set).
local function OnSetPoint(frame, _, relativeTo)
	if busy[frame] then return end
	local spec = pins[frame]
	if not spec or IsHidden(frame) then return end
	if spec.holder and relativeTo == spec.holder then return end
	ApplyPin(frame)
end

local function OnSetScale(frame)
	if not busy[frame] and pins[frame] then ApplyPin(frame) end
end

local function CopyPinOriginal(saved, channel)
	if not saved then return end
	local copy = {}
	if channel ~= "points" then
		local scale = saved.scale
		if not Plain(scale) or type(scale) ~= "number" or scale <= 0 or scale ~= scale or scale == math.huge then return end
		copy.scale = scale
	end
	if channel ~= "scale" then
		local points = saved.points
		if not Plain(points) or type(points) ~= "table" or type(getmetatable(points)) ~= "nil" then return end
		local count = 0
		for key in pairs(points) do
			if not Plain(key) or type(key) ~= "number" or key < 1 or key > 9 or key % 1 ~= 0 then return end
			count = count + 1
			if count > 9 then return end
		end
		if count ~= #points then return end
		local anchors = { TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
			RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true }
		copy.points = {}
		for i = 1, count do
			local point = points[i]
			if not Plain(point) or type(point) ~= "table" or type(getmetatable(point)) ~= "nil" then return end
			for key in pairs(point) do
				if not Plain(key) or type(key) ~= "number" or key < 1 or key > 5 or key % 1 ~= 0 then return end
			end
			if not Plain(unpack(point)) or type(point[1]) ~= "string" or type(point[3]) ~= "string"
				or not anchors[point[1]] or not anchors[point[3]] or (point[2] ~= nil and type(point[2]) ~= "table")
				or type(point[4]) ~= "number" or type(point[5]) ~= "number" or point[4] ~= point[4] or point[5] ~= point[5]
				or math.abs(point[4]) == math.huge or math.abs(point[5]) == math.huge then return end
			copy.points[i] = { unpack(point) }
		end
	end
	return copy
end

local function Remember(frame, owns, bounded, baseline)
	if pinSaved[frame] then return true end
	local saved = { points = {}, parent = frame:GetParent() }
	if owns and not owns() then return end
	local function Original(channel)
		if not baseline then return true end
		local answer = baseline(frame, channel)
		if not owns() or not Plain(answer) or type(answer) ~= "table" or type(getmetatable(answer)) ~= "nil"
			or not Plain(answer.kind) then return false end
		if answer.kind == "native" then return true end
		if answer.kind ~= "original" then return false end
		local input = channel == "scale" and { scale = answer.value } or { points = answer.value }
		local checked = CopyPinOriginal(input, channel)
		return checked ~= nil, checked and checked[channel]
	end
	local ok, scale = Original("scale")
	if not ok then return false end
	if scale == nil then scale = frame:GetScale() end
	if owns and not owns() then return end
	if bounded and (not Plain(scale) or type(scale) ~= "number" or scale <= 0
		or scale ~= scale or scale == math.huge) then return false end
	if Plain(scale) then saved.scale = scale end
	local points
	ok, points = Original("points")
	if not ok then return false end
	if points then
		saved.points = points
	else
		local count = frame:GetNumPoints()
		if owns and not owns() then return end
		if bounded and (not Plain(count) or type(count) ~= "number" or count < 0 or count > 9 or count % 1 ~= 0) then return false end
		for i = 1, count do
			local point = { frame:GetPoint(i) }
			if owns and not owns() then return end
			if bounded and not Plain(unpack(point)) then return false end
			if Plain(point[4], point[5]) then table.insert(saved.points, point) end
		end
	end
	if bounded then
		local checked = CopyPinOriginal(saved)
		if not checked then return false end
		checked.parent = saved.parent
		saved = checked
	end
	if owns and not owns() then return end
	pinSaved[frame] = saved
	return true
end

function E:PinBlizzardFrame(frame, spec)
	if not Usable(frame) or type(spec) ~= "table" then return end
	local previous = pins[frame]
	local guard = spec.admit and spec.admit(frame, "remember")
	if spec.admit and type(guard) ~= "function" then return end
	local function Owns() return pins[frame] == previous and (not guard or guard()) end
	if not Owns() then return end
	local baseline = spec.baseline
	if baseline ~= nil and (not Plain(baseline) or type(baseline) ~= "function" or not spec.admit) then return end
	local remembered = Remember(frame, Owns, spec.admit ~= nil, baseline)
	if (spec.admit and not remembered) or not Owns() then return end
	pins[frame] = spec
	if not hookedPoint[frame] and type(frame.SetPoint) == "function" then
		hookedPoint[frame] = true
		hooksecurefunc(frame, "SetPoint", OnSetPoint)
	end
	if spec.scale and not hookedScale[frame] and type(frame.SetScale) == "function" then
		hookedScale[frame] = true
		hooksecurefunc(frame, "SetScale", OnSetScale)
	end
	if spec.size and not hookedSize[frame] then
		hookedSize[frame] = true
		for _, method in ipairs({ "SetSize", "SetWidth", "SetHeight" }) do
			if type(frame[method]) == "function" then hooksecurefunc(frame, method, OnSetScale) end
		end
	end
	HookParent(frame)
	if pins[frame] == spec then ApplyPin(frame) end
end

-- A cooperating window owner may retain the pre-pin channels. Copies
-- leave the weak-table snapshot private, and a replaced pin gets no data.
function E:BlizzardPinOriginal(frame, expected, channel)
	if pins[frame] ~= expected or not expected then return end
	return CopyPinOriginal(pinSaved[frame], channel)
end

function E:IsBlizzardFramePinned(frame)
	return frame ~= nil and pins[frame] ~= nil
end

-- Every Blizzard frame EldoUI places now (frame -> spec), read only: move
-- mode's stand-ins skip a holder whose Blizzard frame shows.
function E:EachBlizzardPin()
	return pairs(pins)
end

function E:UnpinBlizzardFrame(frame, keep, expected)
	local spec = frame and pins[frame]
	if not spec or (expected and spec ~= expected) then return end
	local guard = spec.releaseAdmit and spec.releaseAdmit(frame)
	if spec.releaseAdmit and type(guard) ~= "function" then return end
	if pins[frame] ~= spec or (guard and not guard()) then return end
	local channels = spec.releaseChannels and spec.releaseChannels(frame)
	if not Plain(channels) then return end
	if spec.releaseChannels and (not channels or type(channels.scale) ~= "boolean" or type(channels.points) ~= "boolean") then return end
	local parentChannel
	if type(channels) == "table" then parentChannel = rawget(channels, "parent") end
	if not Plain(parentChannel) then return end
	if parentChannel ~= nil and type(parentChannel) ~= "boolean" then return end
	if pins[frame] ~= spec or (guard and not guard()) then return end
	pins[frame] = nil
	local saved = pinSaved[frame]
	if keep or not saved then pinSaved[frame] = nil; return end
	local function Back()
		local function Owns()
			return pins[frame] == nil and pinSaved[frame] == saved and (not guard or guard())
		end
		if not Owns() then return end
		local operation = spec.admit and {} or true
		busy[frame] = operation
		local ok, err = pcall(function()
			if saved.parent and parentChannel ~= false and not parents[frame] then
				local current = frame:GetParent()
				if not Owns() then return end
				if current ~= saved.parent then frame:SetParent(saved.parent) end
				if not Owns() then return end
			end
			if saved.scale and (not channels or channels.scale) then Keep.SetScale(frame, saved.scale) end
			if not Owns() then return end
			if #saved.points > 0 and (not channels or channels.points) then
				Keep.ClearAllPoints(frame)
				if not Owns() then return end
				for _, point in ipairs(saved.points) do
					Keep.SetPoint(frame, point[1], point[2] or UIParent, point[3], point[4], point[5])
					if not Owns() then return end
				end
			end
			if Owns() then pinSaved[frame] = nil end
		end)
		busy[frame] = nil
		Report(ok, err)
		if type(operation) == "table" and operation.again and pins[frame] == operation.again then ApplyPin(frame) end
	end
	if Locked(frame) then E:RunOutOfCombat(Back) else Back() end
end

---------------------------------------------------------------------------
-- Blizzard layout passes
---------------------------------------------------------------------------
local relayout, relayoutOrder = {}, {}
local relayoutRunning, relayoutQueued, relayoutCombat = false, false, false
Keep.passes = 0

function E:OnBlizzardRelayout(owner, fn)
	if relayout[owner] == nil then table.insert(relayoutOrder, owner) end
	relayout[owner] = fn or false
end

function E:OffBlizzardRelayout(owner)
	if relayout[owner] then relayout[owner] = false end
end

local function RunCallbacks(reason)
	for _, owner in ipairs(relayoutOrder) do
		local fn = relayout[owner]
		if fn then Report(pcall(fn, reason)) end
	end
end

local function RunRelayout(reason)
	if relayoutRunning then return end
	relayoutRunning = true
	Keep.passes = Keep.passes + 1
	for frame in pairs(parents) do ApplyParent(frame) end
	for frame in pairs(pins) do ApplyPin(frame) end
	if InCombatLockdown() then
		if not relayoutCombat then
			relayoutCombat = true
			E:RunOutOfCombat(function()
				relayoutCombat = false
				RunCallbacks(reason)
			end)
		end
	else
		RunCallbacks(reason)
	end
	relayoutRunning = false
end

function E:BlizzardRelayout(reason, now)
	if now then
		RunRelayout(reason)
		return
	end
	if relayoutQueued then return end
	relayoutQueued = true
	C_Timer.After(0, function()
		relayoutQueued = false
		RunRelayout(reason)
	end)
end

local RELAYOUT_EVENTS = {
	"PLAYER_ENTERING_WORLD", "EDIT_MODE_LAYOUTS_UPDATED", "PLAYER_SPECIALIZATION_CHANGED",
	"ACTIVE_TALENT_GROUP_CHANGED", "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR",
	"PET_BATTLE_CLOSE", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "LOADING_SCREEN_DISABLED",
}
local PLAYER_EVENTS = { UNIT_ENTERED_VEHICLE = true, UNIT_EXITED_VEHICLE = true }

local function HookEditMode()
	local manager = _G.EditModeManagerFrame
	if Keep.editModeHooked or not Usable(manager) or type(manager.UpdateLayoutInfo) ~= "function" then return end
	Keep.editModeHooked = true
	-- Right after Edit Mode applied its layout (systems, managed
	-- containers, action bar positions): put EldoUI's frames back in the
	-- same frame, so nothing flickers.
	hooksecurefunc(manager, "UpdateLayoutInfo", function() E:BlizzardRelayout("editmode", true) end)
end

local relayoutOwner = {}
E:RegisterEvent("PLAYER_LOGIN", function()
	for _, event in ipairs(RELAYOUT_EVENTS) do
		E:RegisterEvent(event, function() E:BlizzardRelayout(event) end, relayoutOwner)
	end
	for event in pairs(PLAYER_EVENTS) do
		E:RegisterEvent(event, function(_, _, unit)
			if unit == "player" then E:BlizzardRelayout(event) end
		end, relayoutOwner)
	end
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Exit", function() E:BlizzardRelayout("EditMode.Exit") end, relayoutOwner)
	end
	E:OnBlizzardAddOn("Blizzard_EditMode", HookEditMode)
end, relayoutOwner, "engines")

---------------------------------------------------------------------------
-- The game's PvP page: on WoW: Forever it is the PvP tab of the character
-- window (rank, honor and the season track). Panel toggles are not
-- protected, so this works in combat too. False when the client has none.
---------------------------------------------------------------------------
function E:OpenPvPPage()
	if not (ToggleCharacter and rawget(_G, "PVPRankFrame")) then return false end
	return (pcall(ToggleCharacter, "PVPRankFrame"))
end

---------------------------------------------------------------------------
-- Startup: migrate, build the page, apply after modules are on.
---------------------------------------------------------------------------
E:RegisterEvent("PLAYER_LOGIN", function()
	Migrate()
	BuildPage()
	E:ApplyBlizzardElements()
end, {}, "modules")
