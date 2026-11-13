-- EldoUI media registry: one list of every sound, font and bar texture the
-- UI can use. It holds EldoUI's own media, the game's sound kits, and
-- whatever LibSharedMedia packs the player has installed. EldoUI does not
-- embed LibSharedMedia; it reads it when another addon brought it, and
-- publishes its own media to it.
--
--   E:RegisterMedia(kind, id, name, value, info)  -- kind: sound, font, statusbar, border, background
--   E:FetchMedia(kind, id, fallback)              -- path / sound value, or nil
--   E:MediaValues(kind, filter)                   -- { [id] = label } for dropdowns
--   E:MediaList(kind, filter)                     -- sorted entries, grouped by source
--   E:PlayMedia(id, channel, opts)                -- the one way EldoUI plays a sound
--
-- Sound ids: "none", "eldo:<key>", "kit:<SOUNDKIT name>", "fid:<FileDataID>",
-- "lsm:<LibSharedMedia name>". Fonts and bar textures use their display name
-- as id, so saved settings from before the registry keep working.
local _, E = ...

E.defaults.general.soundChannel = "Master"
E.defaults.general.soundMute = false

E.soundChannels = { Master = "Master", SFX = "Effects", Music = "Music", Ambience = "Ambience", Dialog = "Dialog" }

local KINDS = { "sound", "font", "statusbar", "border", "background", "particle" }
local registry, order, dirty = {}, {}, {}
for _, kind in ipairs(KINDS) do registry[kind] = {}; dirty[kind] = true end
E.mediaRegistry = registry

local SOURCE_ORDER = { EldoUI = 1, Game = 2 }

local callbacks = {}
local function Changed(kind)
	dirty[kind] = true
	-- 100 LibSharedMedia registrations in a row make one refresh.
	E:Debounce("media:changed", 0.2, function()
		for _, fn in pairs(callbacks) do
			local ok, err = pcall(fn)
			if not ok then geterrorhandler()(err) end
		end
	end)
end

function E:OnMediaChanged(owner, fn)
	callbacks[owner] = fn
end

function E:RegisterMedia(kind, id, name, value, info)
	local list = registry[kind]
	if not list or type(id) ~= "string" or value == nil then return end
	info = info or {}
	local entry = {
		id = id, name = name or id, kind = kind, value = value,
		source = info.source or "EldoUI", type = info.type, tags = info.tags, latinOnly = info.latinOnly,
	}
	list[id] = entry
	Changed(kind)
	return entry
end

-- Bare values saved before the registry existed: "EldoAlarm" (an EldoUI
-- sound key), "RAID_WARNING" (a SOUNDKIT name) or a number (FileDataID).
-- A player-typed sound file: only .ogg or .mp3 inside an addon folder.
function E:IsSoundPath(path)
	if type(path) ~= "string" then return false end
	local lower = path:lower()
	return lower:match("^interface\\addons\\[%w_%-\\%. ]+%.ogg$") ~= nil or lower:match("^interface\\addons\\[%w_%-\\%. ]+%.mp3$") ~= nil
end

local function ResolveSoundId(id)
	if id == nil or id == "" or id == "none" then return nil end
	if type(id) == "number" then return "fid:" .. id end
	if id:find(":", 1, true) then return id end
	if registry.sound["eldo:" .. id] then return "eldo:" .. id end
	if SOUNDKIT and SOUNDKIT[id] then return "kit:" .. id end
	return "lsm:" .. id
end

function E:GetMedia(kind, id)
	if kind == "sound" then
		id = ResolveSoundId(id)
		if not id then return nil end
		local entry = registry.sound[id]
		if entry then return entry end
		-- Kits and file IDs work without being listed.
		local prefix, rest = id:match("^(%a+):(.+)$")
		if prefix == "kit" and SOUNDKIT and SOUNDKIT[rest] then
			return { id = id, name = rest, kind = "sound", type = "kit", value = SOUNDKIT[rest], source = "Game" }
		elseif prefix == "fid" and tonumber(rest) then
			return { id = id, name = rest, kind = "sound", type = "file", value = tonumber(rest), source = "Game" }
		elseif prefix == "file" and E:IsSoundPath(rest) then
			return { id = id, name = rest, kind = "sound", type = "file", value = rest, source = "Custom" }
		end
		return nil
	end
	local list = registry[kind]
	return list and list[id]
end

-- The value to hand the game API. Latin-only fonts give way to the game
-- font in locales they have no glyphs for.
local LATIN = { enUS = true, enGB = true, deDE = true, frFR = true, esES = true, esMX = true, itIT = true, ptBR = true }
local latinLocale = LATIN[GetLocale()]
-- Fonts without the Danish ø give way to the game font while EldoUI's
-- language is Dansk (tools/l10n_check.py --fonts lists them).
local NO_DANISH = { Orbitron = true }

function E:FetchMedia(kind, id, fallback)
	local entry = self:GetMedia(kind, id) or (fallback and self:GetMedia(kind, fallback))
	if not entry then return nil end
	if kind == "font" and entry.latinOnly and not latinLocale then return STANDARD_TEXT_FONT end
	if kind == "font" and NO_DANISH[entry.name] and self:GetLanguage() == "daDK" then return STANDARD_TEXT_FONT end
	return entry.value
end

local function Rebuild(kind)
	local list = {}
	for _, entry in pairs(registry[kind]) do table.insert(list, entry) end
	table.sort(list, function(a, b)
		local sa, sb = SOURCE_ORDER[a.source] or 3, SOURCE_ORDER[b.source] or 3
		if sa ~= sb then return sa < sb end
		if a.source ~= b.source then return a.source < b.source end
		return a.name < b.name
	end)
	order[kind] = list
	dirty[kind] = false
end

-- filter: { none = true (add "None"), playable = "file" (sounds the game
-- can play from a file), source = "...", tags = "fun" }
local function Pass(entry, filter)
	if not filter then return true end
	if filter.playable == "file" and entry.type ~= "file" then return false end
	if filter.source and entry.source ~= filter.source then return false end
	if filter.tag then
		local found = false
		for _, tag in ipairs(entry.tags or {}) do
			if tag == filter.tag then found = true end
		end
		if not found then return false end
	end
	return true
end

function E:MediaList(kind, filter)
	if dirty[kind] or not order[kind] then Rebuild(kind) end
	local list = {}
	for _, entry in ipairs(order[kind] or {}) do
		if Pass(entry, filter) then table.insert(list, entry) end
	end
	return list
end

function E:IterateMedia(kind, filter)
	local list, i = self:MediaList(kind, filter), 0
	return function()
		i = i + 1
		if list[i] then return list[i].id, list[i] end
	end
end

function E:MediaValues(kind, filter)
	local values = {}
	if filter and filter.none then values.none = E.L["None"] end
	for _, entry in ipairs(self:MediaList(kind, filter)) do
		values[entry.id] = entry.source == "EldoUI" and E:Translate(entry.name) or ("%s " .. E:TextHex("secondary") .. "· %s|r"):format(E:Translate(entry.name), entry.source)
	end
	return E:RawValues(values)
end

-- Label for a saved id, also when its media is not installed right now.
function E:MediaLabel(kind, id)
	if id == nil or id == "none" or id == "" then return E.L["None"] end
	local entry = self:GetMedia(kind, id)
	if entry then return E:Translate(entry.name) end
	local name = type(id) == "string" and (id:match("^%a+:(.+)$") or id) or tostring(id)
	return name .. " " .. E:TextHex("secondary") .. E.L["(missing)"] .. "|r"
end

---------------------------------------------------------------------------
-- Playback
---------------------------------------------------------------------------
local lastPlayed = {}

function E:SoundChannel(channel)
	if channel == nil or channel == "default" then channel = self.db.general.soundChannel or "Master" end
	return channel
end

-- Plays a sound id, or its fallback when the first is missing or the game
-- refuses to play it. Returns willPlay, handle like the game's own calls,
-- and the entry it tried.
function E:PlayMedia(id, channel, opts)
	opts = opts or {}
	if self.db.general.soundMute and not opts.preview then return false end
	local entry = self:GetMedia("sound", id) or (opts.fallback and self:GetMedia("sound", opts.fallback))
	if not entry then
		if id and id ~= "none" then self:Debug("Sound not found:", tostring(id)) end
		return false
	end
	local now = GetTime()
	if not opts.preview and lastPlayed[entry.id] and now - lastPlayed[entry.id] < 0.25 then return false end
	lastPlayed[entry.id] = now
	channel = self:SoundChannel(channel)
	local ok, willPlay, handle
	if entry.type == "kit" then
		ok, willPlay, handle = pcall(PlaySound, entry.value, channel, opts.noDup)
	else
		ok, willPlay, handle = pcall(PlaySoundFile, entry.value, channel)
	end
	if not (ok and willPlay) then
		self:Debug("Sound failed:", entry.id, ok and "the game would not play it" or willPlay)
		-- The file exists in the list but the game refused it (missing file,
		-- new file before a game restart): try the fallback once.
		local fallback = opts.fallback and self:GetMedia("sound", opts.fallback)
		if fallback and fallback.id ~= entry.id then
			return self:PlayMedia(fallback.id, channel, { preview = opts.preview, noDup = opts.noDup })
		end
		return false, nil, entry
	end
	return willPlay, handle, entry
end

function E:StopMedia(handle, fadeMs)
	if handle then pcall(StopSound, handle, fadeMs) end
end

-- A font setting that follows the theme font: "THEME" (font rows), and
-- the older "default", "" or nil.
function E:IsThemeFont(id)
	return id == nil or id == "" or id == "default" or id == "THEME"
end

-- Like E:SetFont, with a chosen font. The theme font when the setting
-- follows it. The size is used as given: HUD texts (combat text, plates,
-- bars, splashes) keep the size the player picked for them. Text inside a
-- window passes scaled = true, so it grows with General > Large text like
-- the rest of the window (DESIGN.md 1).
function E:SetMediaFont(fontString, id, size, outline, scaled)
	local path = not self:IsThemeFont(id) and self:FetchMedia("font", id) or self.media.font
	size = size or self.db.general.fontSize
	if scaled then size = size * self:TextScale() end
	-- A text marked for names keeps every alphabet (E:UseNameFont).
	if self.UsesNameFont and self:UsesNameFont(fontString)
		and self:SetNameFont(fontString, path or self.media.font, size, outline or self.db.general.fontOutline) then
		return
	end
	if not fontString:SetFont(path or self.media.font, size, outline or self.db.general.fontOutline) then
		fontString:SetFont(self.media.font, size, outline or self.db.general.fontOutline)
	end
	fontString:SetShadowOffset(0, 0)
end

---------------------------------------------------------------------------
-- EldoUI's own media and the game's sound kits
---------------------------------------------------------------------------
local SOUNDS = "Interface\\AddOns\\EldoUI\\Media\\Sounds\\"

-- Tones made for EldoUI (keys as Danger Alerts saves them).
local OWN_SOUNDS = {
	{ "EldoAlarm", "Alarm", "EldoAlarm.ogg", "alert" },
	{ "EldoWarning", "Warning", "EldoWarning.ogg", "alert" },
	{ "EldoChime", "Chime", "EldoChime.ogg", "alert" },
	{ "EldoFail", "Fail", "EldoFail.ogg", "alert" },
	-- Pack: CC0 / CC-BY / public domain, credited in Media/LICENSES.md.
	{ "Tada", "Tada", "Pack\\TadaFanfare.ogg", "fun" },
	{ "SynthChord", "Synth Chord", "Pack\\SynthChord.ogg", "fun" },
	{ "Guitar", "Guitar Strum", "Pack\\AcousticGuitar.ogg", "fun" },
	{ "Xylophone", "Xylophone", "Pack\\Xylophone.ogg", "fun" },
	{ "DrumRoll", "Drum Roll", "Pack\\Drums.ogg", "fun" },
	{ "Brass", "Brass", "Pack\\Brass.mp3", "alert" },
	{ "Glass", "Glass", "Pack\\Glass.mp3", "ui" },
	{ "Whoosh", "Whoosh", "Pack\\DoubleWhoosh.ogg", "ui" },
	{ "ErrorBeep", "Error Beep", "Pack\\ErrorBeep.ogg", "ui" },
	{ "SqueakyToy", "Squeaky Toy", "Pack\\SqueakyToyShort.ogg", "fun" },
	{ "ChickenAlarm", "Chicken Alarm", "Pack\\ChickenAlarm.ogg", "fun" },
	{ "Rooster", "Rooster", "Pack\\RoosterChickenCalls.ogg", "fun" },
	{ "Sheep", "Sheep", "Pack\\SheepBleat.ogg", "fun" },
	{ "Goat", "Goat", "Pack\\GoatBleating.ogg", "fun" },
	{ "OhNo", "Oh No", "Pack\\OhNo.ogg", "voice" },
}

-- Game sounds by SOUNDKIT name. Only names the running client has are
-- listed, so a name Forever lacks never shows up.
local GAME_KITS = {
	{ "READY_CHECK", "Ready check" },
	{ "RAID_WARNING", "Raid warning" },
	{ "TELL_MESSAGE", "Whisper" },
	{ "MAP_PING", "Map ping" },
	{ "ALARM_CLOCK_WARNING_3", "Alarm clock" },
	{ "PVP_THROUGH_QUEUE", "Queue pop" },
	{ "IG_PLAYER_INVITE", "Invite" },
	{ "IG_QUEST_LIST_COMPLETE", "Quest complete" },
	{ "UI_EPICLOOT_TOAST", "Epic loot" },
	{ "UI_LEGENDARY_LOOT_TOAST", "Legendary loot" },
	{ "UI_BNET_TOAST", "Battle.net toast" },
	{ "UI_RAID_BOSS_WHISPER_WARNING", "Boss whisper" },
	{ "LFG_REWARDS", "Dungeon reward" },
	{ "ACHIEVEMENT_MENU_OPEN", "Achievement" },
	{ "AUCTION_WINDOW_OPEN", "Auction" },
	{ "UI_GARRISON_TOAST_MISSION_COMPLETE", "Mission complete" },
	{ "IG_BACKPACK_COIN_SELECT", "Coin" },
	{ "MONEY_FRAME_OPEN", "Money" },
}

function E:SeedMedia()
	for _, sound in ipairs(OWN_SOUNDS) do
		self:RegisterMedia("sound", "eldo:" .. sound[1], sound[2], SOUNDS .. sound[3], { source = "EldoUI", type = "file", tags = { sound[4] } })
	end
	if SOUNDKIT then
		for _, kit in ipairs(GAME_KITS) do
			if SOUNDKIT[kit[1]] then
				self:RegisterMedia("sound", "kit:" .. kit[1], kit[2], SOUNDKIT[kit[1]], { source = "Game", type = "kit", tags = { "game" } })
			end
		end
	end
	for name, path in pairs(self.media.fonts) do
		local game = path:find("^Fonts") ~= nil
		self:RegisterMedia("font", name, name, path, { source = game and "Game" or "EldoUI", latinOnly = not game })
	end
	for name, path in pairs(self.media.statusbars) do
		self:RegisterMedia("statusbar", name, name, path, { source = path:find("^Interface\\AddOns\\EldoUI") and "EldoUI" or "Game" })
	end
	-- "Follow skin": the bar texture of the skin in use (E:UpdateStylePalette
	-- keeps its value current; Smooth for the flat skins).
	self:RegisterMedia("statusbar", "Skin", E.L["Follow skin"], self.media.statusbars.Smooth, { source = "EldoUI", type = "follow" })
	self:RegisterMedia("border", "Eldo 1px", "Eldo 1px", self.media.flat, { source = "EldoUI" })
	self:RegisterMedia("background", "Eldo Flat", "Eldo Flat", self.media.flat, { source = "EldoUI" })
end
E:SeedMedia()

---------------------------------------------------------------------------
-- LibSharedMedia (read when another addon brought it; never embedded)
---------------------------------------------------------------------------
local LSM
local known = {}  -- path -> true for media EldoUI already lists

local function SourceOf(value)
	if type(value) == "number" then return "Game" end
	if type(value) ~= "string" then return "SharedMedia" end
	local folder = value:match("^[Ii]nterface\\[Aa]dd[Oo]ns\\([^\\]+)\\")
	if folder then
		if folder == "EldoUI" then return "EldoUI" end
		local title = C_AddOns and C_AddOns.GetAddOnMetadata(folder, "Title")
		if type(title) == "string" and title ~= "" then
			return (title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
		end
		return folder
	end
	if value:find("^[Ff]onts\\") or value:find("^[Ss]ound\\") or value:find("^[Ii]nterface\\") then return "Game" end
	return "SharedMedia"
end

function E:ImportLSMEntry(kind, name, value)
	if not registry[kind] or type(name) ~= "string" or value == nil then return end
	if type(value) == "string" and known[value:lower()] then return end
	if kind == "sound" then
		if type(value) == "string" and value:lower():find("quiet%.ogg$") then return end
		local id = "lsm:" .. name
		if registry.sound[id] then return end
		self:RegisterMedia("sound", id, name, value, { source = SourceOf(value), type = "file" })
	else
		-- Fonts and textures are keyed by name; EldoUI's own name wins.
		if registry[kind][name] then return end
		self:RegisterMedia(kind, name, name, value, { source = SourceOf(value) })
	end
end

-- EldoUI's media becomes available to every other addon that uses
-- LibSharedMedia. Registering only shares paths; the first name wins.
local function PublishOwnMedia()
	local western = LSM.LOCALE_BIT_western
	for _, entry in pairs(registry.font) do
		if entry.source == "EldoUI" then pcall(LSM.Register, LSM, "font", entry.name, entry.value, entry.latinOnly and western or nil) end
	end
	for _, entry in pairs(registry.statusbar) do
		if entry.source == "EldoUI" and entry.type ~= "follow" then pcall(LSM.Register, LSM, "statusbar", "Eldo " .. entry.name, entry.value) end
	end
	for _, entry in pairs(registry.sound) do
		if entry.source == "EldoUI" then pcall(LSM.Register, LSM, "sound", "EldoUI: " .. entry.name, entry.value) end
	end
end

local function HookLSM()
	if LSM then return true end
	LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
	if not LSM then return false end
	for _, kind in ipairs(KINDS) do
		for _, entry in pairs(registry[kind]) do
			if type(entry.value) == "string" then known[entry.value:lower()] = true end
		end
	end
	PublishOwnMedia()
	for _, kind in ipairs(KINDS) do
		local ok, list = pcall(LSM.HashTable, LSM, kind)
		if ok and type(list) == "table" then
			for name, value in pairs(list) do E:ImportLSMEntry(kind, name, value) end
		end
	end
	if LSM.RegisterCallback then
		LSM.RegisterCallback(registry, "LibSharedMedia_Registered", function(_, kind, name)
			local ok, value = pcall(LSM.Fetch, LSM, kind, name, true)
			if ok then E:ImportLSMEntry(kind, name, value) end
		end)
	end
	E:Debug("LibSharedMedia found; media imported.")
	return true
end
E.HookLSM = HookLSM

-- At load (OptionalDeps lets SharedMedia packs load first), on every
-- addon load until found (load-on-demand packs), and once at login.
if not HookLSM() then
	E:RegisterEvent("ADDON_LOADED", function()
		if HookLSM() then E:UnregisterEvent("ADDON_LOADED", registry) end
	end, registry)
end
E:RegisterEvent("PLAYER_LOGIN", function()
	HookLSM()
	E:UnregisterEvent("PLAYER_LOGIN", registry)
end, registry, "engines")

-- A theme font or bar texture saved in the profile may come from a pack
-- that registered after login; apply it once it shows up.
E:OnMediaChanged("theme", function()
	if not E.db then return end
	local general = E.db.general
	local font = registry.font[general.font]
	local bar = registry.statusbar[general.statusbar]
	if (font and E.media.font ~= E:FetchMedia("font", general.font)) or (bar and E.media.statusbar ~= bar.value) then
		E:RefreshTheme()
	end
end)


---------------------------------------------------------------------------
-- General > Fonts and Text, Textures, Colors
--
-- One place for the shared media. The rows under "Per module" are found
-- in each module's own options (a font or bar texture picker) and write
-- straight into that module's setting, so the module page and this page
-- always show the same value. "Set every module" fills them all at once
-- wherever the module offers that font or texture.
---------------------------------------------------------------------------
local L = E.L

local function LastSegment(key)
	return type(key) == "string" and (key:match("([^%.]+)$") or key):lower() or ""
end

local function OptionValues(option)
	local values = option.values
	if type(values) == "function" then
		local ok, result = pcall(values)
		values = ok and result or nil
	end
	return type(values) == "table" and values or {}
end

-- Does a select row offer media of this kind (any known font / texture)?
local function OffersMedia(option, kind)
	for value in pairs(OptionValues(option)) do
		if type(value) == "string" and registry[kind][value] then return true end
	end
	return false
end

local function MediaKindOf(option)
	if type(option.key) ~= "string" then return nil end
	if option.type == "media" and (option.mediaKind == "font" or option.mediaKind == "statusbar") then return option.mediaKind end
	if option.type == "select" then
		local last = LastSegment(option.key)
		if last:find("font$") and OffersMedia(option, "font") then return "font" end
		if (last:find("texture$") or last:find("statusbar$")) and OffersMedia(option, "statusbar") then return "statusbar" end
	end
	return nil
end

-- "Use the EldoUI font" switches some modules have for Blizzard's text.
local function IsFontToggle(option)
	return option.type == "toggle" and type(option.key) == "string" and LastSegment(option.key) == "font"
end

local function IsHidden(option)
	local hidden = option.hidden
	if type(hidden) == "function" then
		local ok, result = pcall(hidden)
		return ok and result
	end
	return hidden
end

-- Rows of every module for one kind: { module, option, path }.
local function ModuleRows(kind)
	local rows = {}
	for name, module in E:IterateModules() do
		-- The tab or header a row sits under names it when its own label is
		-- generic ("Font"), so six Combat HUD fonts read as six different rows.
		local section
		for _, option in ipairs(E:GetModuleOptions(module) or {}) do
			if option.type == "tab" or option.type == "header" then
				section = option.englishLabel or option.label
			else
				local found = (kind == "fonttoggle" and IsFontToggle(option)) or (kind ~= "fonttoggle" and MediaKindOf(option) == kind)
				if found then rows[#rows + 1] = { module = module, option = option, path = name .. "." .. option.key, section = section } end
			end
		end
	end
	return rows
end

-- Built from the English texts (also when the module's page already
-- translated its options), so the row translates as a whole.
local GENERIC = { font = true, ["eldoui font"] = true, ["bar texture"] = true, texture = true }
local function RowLabel(row)
	local label = tostring(row.option.englishLabel or row.option.label or "")
	local title = L[row.module.title]
	if label == "" or GENERIC[label:lower()] then
		local section = type(row.section) == "string" and row.section ~= "" and L[row.section]
		if section and section ~= title then return L["%s: %s"]:format(title, section) end
		return title
	end
	return L["%s: %s"]:format(title, L[label])
end

-- Rows sorted by the label the player reads.
local function SortRows(rows)
	for _, row in ipairs(rows) do row.label = RowLabel(row) end
	table.sort(rows, function(a, b)
		if a.label ~= b.label then return a.label < b.label end
		return a.path < b.path
	end)
	return rows
end

-- Copy a module option as a row of this page (path prefixed with the module).
local function RowOption(row)
	local option, module = row.option, row.module
	local copy = {}
	for key, value in pairs(option) do copy[key] = value end
	copy.key = row.path
	copy.label = row.label or RowLabel(row)
	copy.englishLabel = nil
	copy.desc = (option.englishDesc or option.desc) and L[option.englishDesc or option.desc]
		or L["This module's setting; the module's own page shows the same value."]
	copy.englishDesc = nil
	copy.localized = true
	copy.hidden = function() return not module:IsEnabled() or IsHidden(option) end
	return copy
end

-- A page whose rows read and write several modules' settings. Each module
-- that changed re-applies once; a change to the core values (General,
-- language) refreshes the theme. `before(proxy)` runs first on a change.
local function MultiModulePage(id, title, options, extra, sortOrder, before)
	local proxy, snapshot = {}, {}
	local function Target()
		for key, value in pairs(extra) do proxy[key] = type(value) == "function" and value() or value end
		for name, module in E:IterateModules() do
			if module.db then proxy[name] = module.db end
		end
		return proxy
	end
	local function Snapshot()
		for _, option in ipairs(options) do
			if type(option.key) == "string" then
				local value = E.GetPath(proxy, option.key)
				snapshot[option.key] = type(value) == "table" and CopyTable(value) or value
			end
		end
	end
	local function Refresh()
		Target()
		if before then before(proxy) end
		local changed, core = {}, false
		for _, option in ipairs(options) do
			if type(option.key) == "string" then
				local value = E.GetPath(proxy, option.key)
				if not E.DeepEqual(value, snapshot[option.key]) then
					local moduleName = option.key:match("^([^%.]+)%.")
					local module = moduleName and E.modules[moduleName]
					if module then changed[module] = true else core = true end
				end
			end
		end
		Snapshot()
		if core then
			-- RefreshTheme re-applies every module too.
			E:RefreshTheme()
			return
		end
		for module in pairs(changed) do
			if module.active and module.OnProfileChanged then
				E:RunOutOfCombat(function()
					local ok, err = pcall(module.OnProfileChanged, module)
					if not ok then geterrorhandler()(err) end
				end)
			end
		end
	end
	local page = E:RegisterConfigPage(id, title, options, function()
		Target()
		if not next(snapshot) then Snapshot() end
		return proxy
	end, Refresh, sortOrder)
	return page
end

-- Fill every row of a kind with one value where the module offers it.
local function SetEveryModule(rows, value)
	local count = 0
	for _, row in ipairs(rows) do
		local option = row.option
		local accepts = option.type == "media" or OptionValues(option)[value] ~= nil
		if accepts and row.module.db then
			E.SetPath(row.module.db, option.key, value)
			count = count + 1
		end
	end
	return count
end

local function FontChoices(extraKey, extraLabel)
	return function()
		local values = E:MediaValues("font")
		if extraKey then values[extraKey] = extraLabel end
		return values
	end
end

local function BuildFontsPage()
	local fontRows, toggleRows = SortRows(ModuleRows("font")), SortRows(ModuleRows("fonttoggle"))
	local function GameFontsOff() return not E.db.general.gameFonts end
	local styles = {}
	for key, example in pairs(E.numberStyles) do styles[key] = L[example] end
	local options = {
		{ type = "tab", label = L["Text"] },
		{ type = "header", label = L["Theme font"] },
		{ type = "media", mediaKind = "font", key = "general.font", label = L["Font"],
			desc = L["The EldoUI font for every EldoUI text that has no font of its own. Languages these fonts lack keep the game font."] },
		{ type = "range", key = "general.fontSize", label = L["Text size"], min = 10, max = 20, step = 1,
			desc = L["Base text size of EldoUI windows and bars."] },
		{ type = "select", key = "general.fontOutline", label = L["Outline"],
			desc = L["Outline around EldoUI text. Thin reads well on bars; none suits windows."],
			values = { [""] = L["None"], OUTLINE = L["Thin"], THICKOUTLINE = L["Thick"] } },
		{ type = "toggle", key = "general.fontShadow", label = L["Text shadow"],
			desc = L["A 1-pixel shadow under EldoUI's text, softer when there is an outline too. With no outline, the shadow keeps text readable over bright ground."] },
		{ type = "header", label = L["Numbers"] },
		{ type = "select", key = "general.numberStyle", label = L["Big numbers"], values = styles,
			desc = L["How tags, datatexts and tooltips shorten big numbers. Secret values in combat use the game's own style."] },
		{ type = "range", key = "general.numberDecimals", label = L["Decimals"], min = 0, max = 2, step = 1,
			desc = L["Digits after the point in shortened numbers (1.2k with 1, 1.23k with 2)."],
			hidden = function() return E.db.general.numberStyle == "full" or E.db.general.numberStyle == "game" end },
		{ type = "select", key = "general.moneyStyle", label = L["Money"], values = E:MoneyStyleValues(),
			desc = L["How gold is written in every EldoUI window, bar and tooltip. Bags, Auction House, Merchant and Trade can keep their own choice."] },
		{ type = "header", label = L["Cooldown numbers"] },
		{ type = "media", mediaKind = "font", key = "general.cooldownFont", label = L["Font"], default = "THEME", defaultLabel = L["Theme font"],
			desc = L["Font of the countdown numbers on action bars, bag slots, aura icons and every other cooldown swipe that uses EldoUI's cooldown text. Theme font follows the Font above."] },
		{ type = "range", key = "general.cooldownFontSize", label = L["Size"], min = 8, max = 32, step = 1,
			desc = L["Base size of the countdown numbers; 16 is normal. Action bars, bag slots and aura icons scale their own number size by this."] },
		{ type = "select", key = "general.cooldownFontOutline", label = L["Outline"],
			desc = L["Outline around the countdown numbers, with the theme font or a picked one."],
			values = { [""] = L["None"], OUTLINE = L["Thin"], THICKOUTLINE = L["Thick"] } },
		{ type = "range", key = "general.cooldownExpiring", label = L["Expiring below"], min = 0, max = 30, step = 1, unit = "s",
			desc = L["Seconds left when the countdown numbers turn the expiring color."] },
		{ type = "range", key = "general.cooldownTenths", label = L["Tenths below"], min = 0, max = 10, step = 1, unit = "s",
			desc = L["Seconds left when tenths of a second show. 0 never shows tenths."] },
		{ type = "color", key = "general.cooldownColor", label = L["Minutes and hours"],
			desc = L["Color of countdown numbers of a minute or more."] },
		{ type = "color", key = "general.cooldownSecondsColor", label = L["Seconds"],
			desc = L["Color of countdown numbers under a minute."] },
		{ type = "color", key = "general.cooldownExpiringColor", label = L["Expiring"],
			desc = L["Color of countdown numbers about to end."] },

		{ type = "tab", label = L["Game fonts"] },
		{ type = "description", label = L["Blizzard's windows, tooltips, quest, mail, error and zone text in the EldoUI font. Off leaves every game font as Blizzard made it."] },
		{ type = "toggle", key = "general.gameFonts", label = L["Use the EldoUI font for the whole game"], reload = true,
			desc = L["Sets the theme font on the game's own font objects. Switching it off puts Blizzard's fonts back; text that is already on screen follows after a reload."] },
		{ type = "range", percent = true, key = "general.gameFontScale", label = L["Game font scale"], min = 0.8, max = 1.4, step = 0.05, hidden = GameFontsOff,
			desc = L["Scales every game font from Blizzard's size. Chat keeps the size each chat window has."] },
		{ type = "header", label = L["Text in the world"] },
		{ type = "select", key = "general.worldFont", label = L["Names over heads"], values = FontChoices("none", L["Blizzard's font"]),
			desc = L["Font of the names above characters. The game reads it when the world loads: log out and back in to see it."] },
		{ type = "select", key = "general.combatTextFont", label = L["Floating combat text"], values = FontChoices("none", L["Blizzard's font"]),
			desc = L["Font of the game's floating damage and healing numbers. The game reads it when the world loads: log out and back in to see it."] },
	}
	if #fontRows > 0 or #toggleRows > 0 then
		table.insert(options, { type = "tab", label = L["Per module"] })
		if #fontRows > 0 then
			table.insert(options, { type = "description", label = L["Each module's own font setting. Theme font or Default means the module follows the theme font."] })
			table.insert(options, { type = "select", key = "setAll.font", label = L["Set every module to"], values = FontChoices(), noUndo = true,
				desc = L["Writes this font into every module below that offers it."] })
			for _, row in ipairs(fontRows) do table.insert(options, RowOption(row)) end
		end
		if #toggleRows > 0 then
			table.insert(options, { type = "header", label = L["EldoUI font in Blizzard's parts"] })
			for _, row in ipairs(toggleRows) do table.insert(options, RowOption(row)) end
		end
	end
	local page = MultiModulePage("fonts", L["Fonts and text"], options, {
		general = function() return E.db.general end,
		setAll = {},
	}, 1.1, function(proxy)
		local value = proxy.setAll.font
		if value ~= nil then
			proxy.setAll.font = nil
			local count = SetEveryModule(fontRows, value)
			E:ConfigNotice(E:Plural(count, "%s set in %d module.", "%s set in %d modules."):format(E:MediaLabel("font", value), count))
		end
	end)
	if page then page.desc = L["Theme font, number format, the game's own fonts and every module's font in one place."] end
end

---------------------------------------------------------------------------
-- Panel tint cards (Textures page): one small sample panel per tint in the
-- art style in effect; a click picks it. The selected card has the accent
-- border. Under Classic and High contrast, which keep their own
-- background, the cards are dimmed and do nothing.
---------------------------------------------------------------------------
local TINT_CARD_HEIGHT = 40
local TINT_CARD_GAP = 8

local function TintOff()
	return not E:PanelTintApplies() and L["Your skin keeps its own background: tints color the flat skins (Modern, Minimal Modern, Blizzard and WoW Forever)."]
end

local function PickTint(card)
	if not E:PanelTintApplies() then return end
	E.db.general.panelTint = card.tintKey
	E:RefreshTheme()
	if E.RefreshConfig then E:RefreshConfig() end
end

local function PaintTintCard(card, selected, hover)
	local r, g, b = E:PanelBackdropColor(card.tintKey)
	card:SetBackdropColor(r, g, b, E:PanelAlpha())
	if selected then
		card:SetBackdropBorderColor(unpack(E.media.accentColor))
		card.label:SetTextColor(E:TokenColor("accent"))
	else
		local edge = E.tokens.edge.window
		card:SetBackdropBorderColor(1, 1, 1, hover and edge[4] * 3 or edge[4])
		card.label:SetTextColor(E:TokenColor("body"))
	end
end

local function CreateTintCards(canvas)
	if not canvas then return end
	canvas.cards = {}
	for index, key in ipairs(E.panelTintOrder) do
		local card = CreateFrame("Button", nil, canvas)
		E:AddBackdrop(card)
		card:SetBackdrop({ bgFile = E.media.flat, edgeFile = E.media.flat, edgeSize = E.pixel })
		card.tintKey = key
		card.label = E:CreateText(card, E.tokens.size.label)
		card.label:SetPoint("CENTER")
		card.label:SetText(L[E.panelTintNames[key]])
		card:SetScript("OnClick", PickTint)
		card:SetScript("OnEnter", function(self) PaintTintCard(self, self.selected, true) end)
		card:SetScript("OnLeave", function(self) PaintTintCard(self, self.selected, false) end)
		E.UIKit.Tooltip(card, L[E.panelTintNames[key]], key == "none" and L["The plain dark panels."]
			or L["A subtle tint in the background of EldoUI windows and panels."])
		canvas.cards[index] = card
	end
end

local function UpdateTintCards(canvas, settings)
	if not (canvas and canvas.cards) then return end
	local general = settings and settings.general or E.db.general
	local current = general.panelTint or "none"
	local count = #canvas.cards
	local width = math.floor((math.max(200, canvas:GetWidth()) - TINT_CARD_GAP * (count - 1)) / count)
	local on = E:PanelTintApplies()
	for index, card in ipairs(canvas.cards) do
		card:ClearAllPoints()
		card:SetSize(width, TINT_CARD_HEIGHT)
		card:SetPoint("LEFT", canvas, "LEFT", (index - 1) * (width + TINT_CARD_GAP), 0)
		card.selected = card.tintKey == current
		PaintTintCard(card, card.selected, false)
		card:SetAlpha(on and 1 or E.tokens.disabledAlpha)
	end
end

local function TintValues()
	local values = {}
	for key, name in pairs(E.panelTintNames) do values[key] = L[name] end
	return values
end

-- Frame shadows belong to the flat skins (Modern, Minimal Modern).
local function NoShadows() return not E:SkinAllowsShadows() end

local function BuildTexturesPage()
	local rows = SortRows(ModuleRows("statusbar"))
	local options = {
		{ type = "header", label = L["Bars"] },
		{ type = "media", mediaKind = "statusbar", key = "general.statusbar", label = L["Bar texture"],
			desc = L["Texture of every EldoUI bar that has no texture of its own. Follow skin uses your skin's bar texture. Textures from SharedMedia packs you have installed are listed under their addon."] },
		{ type = "toggle", key = "general.smoothBars", label = L["Smooth bars"],
			desc = L["Bars glide to new values instead of jumping. The game animates them, so this works in combat too."] },
		{ type = "header", label = L["Panels"] },
		{ type = "range", percent = true, key = "general.panelAlpha", label = L["Panel opacity"], min = E.tokens.panel.minAlpha, max = 1, step = 0.02,
			desc = L["How solid EldoUI's panels on the screen are, such as chat, tooltips and meters. Windows are always solid. See-through panels never drop below 80%, so their text stays readable."] },
		{ type = "select", key = "general.panelTint", label = L["Panel tint"], values = TintValues, order = E.panelTintOrder,
			disabled = TintOff, keywords = "color theme background",
			desc = L["A subtle color in the background of EldoUI windows and panels: Midnight blue, Pine green, Wine red or Dusk violet. None keeps the plain dark panels. Text keeps its contrast in every tint."] },
		{ type = "preview", label = L["Panel tint"], height = TINT_CARD_HEIGHT + 16, create = CreateTintCards, update = UpdateTintCards,
			desc = L["Each tint on a sample panel in your skin. Click one to use it."] },
		{ type = "toggle", key = "general.shadows", label = L["Frame shadows"],
			desc = L["A soft shadow around EldoUI windows and panels in the flat skins, Modern and Minimal Modern."],
			hidden = NoShadows },
		{ type = "range", percent = true, key = "general.shadowAlpha", label = L["Shadow strength"], dependsOn = "general.shadows",
			min = E.tokens.shadow.minAlpha, max = 1, step = 0.05, hidden = NoShadows,
			desc = L["How dark the frame shadows are."] },
		{ type = "range", key = "general.shadowSize", label = L["Shadow size"], dependsOn = "general.shadows", unit = "px",
			min = E.tokens.shadow.minSize, max = E.tokens.shadow.maxSize, step = 1, hidden = NoShadows,
			desc = L["How far the frame shadows reach beyond the edge of a window or panel."] },
		{ type = "description", label = L["Frame shadows belong to the flat skins, Modern and Minimal Modern. Other skins draw a frame of their own."],
			hidden = function() return E:SkinAllowsShadows() end },
	}
	if #rows > 0 then
		table.insert(options, { type = "header", label = L["Per module"] })
		table.insert(options, { type = "select", key = "setAll.statusbar", label = L["Set every module to"], noUndo = true,
			values = function() return E:MediaValues("statusbar") end,
			desc = L["Writes this texture into every module below that offers it."] })
		for _, row in ipairs(rows) do table.insert(options, RowOption(row)) end
	end
	local page = MultiModulePage("textures", L["Textures"], options, {
		general = function() return E.db.general end,
		setAll = {},
	}, 1.2, function(proxy)
		local value = proxy.setAll.statusbar
		if value ~= nil then
			proxy.setAll.statusbar = nil
			local count = SetEveryModule(rows, value)
			E:ConfigNotice(E:Plural(count, "%s set in %d module.", "%s set in %d modules."):format(E:MediaLabel("statusbar", value), count))
		end
	end)
	if page then page.desc = L["Bar texture, smooth bars, panel opacity and tint, frame shadows and every module's bar texture in one place."] end
end

---------------------------------------------------------------------------
-- Colors: a proxy per table. Reading gives the color in use, writing a
-- color equal to the game's own removes the custom one.
---------------------------------------------------------------------------
local function SameColor(a, r, g, b)
	if type(a) ~= "table" or not r then return false end
	local x, y, z = a[1] or a.r, a[2] or a.g, a[3] or a.b
	return x and math.abs(x - r) < 0.002 and math.abs(y - g) < 0.002 and math.abs(z - b) < 0.002
end

local function ColorProxy(group)
	return setmetatable({}, {
		__index = function(_, key)
			local r, g, b = E:GetColor(group, key)
			if not r and group == "class" then r, g, b = E:GameColor("class", key) end
			return r and { r, g, b } or nil
		end,
		__newindex = function(_, key, value)
			local list = E.db.general.colors[group]
			if value == nil or SameColor(value, E:GameColor(group, key)) then
				list[key] = nil
			elseif type(value) == "table" then
				list[key] = { value[1] or value.r, value[2] or value.g, value[3] or value.b }
			end
		end,
	})
end

-- Ready-made color sets (DESIGN: presets first). Each writes the raw
-- colors, which can still be fine-tuned below.
local function Scale(group, key, factor, toward)
	local r, g, b = E:GameColor(group, key)
	if not r then return nil end
	toward = toward or 0
	return { r + (toward - r) * factor, g + (toward - g) * factor, b + (toward - b) * factor }
end

local COLOR_PRESETS = {
	{ key = "game", title = "Game colors", desc = "Every color back to the game's own." },
	{ key = "soft", title = "Soft", desc = "Calmer, slightly pale colors that sit well on dark panels.",
		make = function(group, key) return Scale(group, key, 0.25, 0.85) end },
	{ key = "dark", title = "Dark", desc = "Deeper colors for a dark, low-glare look.",
		make = function(group, key) return Scale(group, key, 0.3, 0) end },
	{ key = "bright", title = "Bright", desc = "Stronger colors for quick reading in busy fights.",
		make = function(group, key)
			local r, g, b = E:GameColor(group, key)
			if not r then return nil end
			local top = math.max(r, g, b, 0.01)
			return { math.min(1, r / top), math.min(1, g / top), math.min(1, b / top) }
		end },
}

local function ApplyColorPreset(preset)
	local colors = E.db.general.colors
	for _, group in ipairs(E.colorGroups) do
		wipe(colors[group.key])
		if preset.make then
			for _, entry in ipairs(group.list) do
				local color = preset.make(group.key, entry[1])
				if color then colors[group.key][entry[1]] = color end
			end
		end
	end
	wipe(colors.class)
	colors.blizzardClass = true
	E:RefreshTheme()
	if E.RefreshConfig then E:RefreshConfig() end
end

local function BuildColorsPage()
	local proxy = { blizzardClass = nil }
	for _, group in ipairs(E.colorGroups) do proxy[group.key] = ColorProxy(group.key) end
	proxy.class = ColorProxy("class")
	local function Custom() return E.db.general.colors.blizzardClass end
	local options = {
		{ type = "description", label = L["Colors EldoUI uses for classes, power, reactions, dispel types and threat. Everything starts as the game's own colors or EldoUI's defaults."] },
		{ type = "header", label = L["Presets"] },
	}
	for _, preset in ipairs(COLOR_PRESETS) do
		table.insert(options, { type = "execute", label = L[preset.title], desc = L[preset.desc], width = 160, testSafe = true,
			confirm = L["Use this color preset? Colors you picked yourself on this page are replaced."],
			func = function() ApplyColorPreset(preset) end })
	end
	table.insert(options, { type = "header", label = L["Class"] })
	table.insert(options, { type = "toggle", key = "blizzardClass", label = L["Use the game's class colors"],
		desc = L["Off lets you pick a color per class below. Only EldoUI uses these; Blizzard's frames keep theirs."] })
	for _, class in ipairs(E:ClassList()) do
		table.insert(options, { type = "color", key = "class." .. class[1], label = class[2], hidden = Custom,
			desc = L["Every EldoUI frame, bar and name drawn in the %s class color uses this."]:format(class[2]) })
	end
	for _, group in ipairs(E.colorGroups) do
		-- A group no module reads yet stays hidden (no dead rows).
		local hidden = group.inUse and function() return not group.inUse() end or nil
		table.insert(options, { type = "header", label = L[group.title], hidden = hidden })
		for _, entry in ipairs(group.list) do
			table.insert(options, { type = "color", key = group.key .. "." .. entry[1], label = L[entry[2]], hidden = hidden,
				desc = L["Every EldoUI bar, text and tag that shows \"%s\" (%s) uses this color. The Game colors preset puts the game's color back."]:format(L[entry[2]], L[group.title]) })
		end
	end
	local page = E:RegisterConfigPage("colors", L["Colors"], options,
		function()
			proxy.blizzardClass = E.db.general.colors.blizzardClass
			return proxy
		end,
		function()
			E.db.general.colors.blizzardClass = proxy.blizzardClass and true or false
			E:RefreshTheme()
		end, 1.3)
	if page then page.desc = L["Class, power, reaction, dispel and threat colors for every EldoUI frame."] end
end

E:RegisterEvent("PLAYER_LOGIN", function()
	BuildFontsPage()
	BuildTexturesPage()
	BuildColorsPage()
	E:UnregisterEvent("PLAYER_LOGIN", BuildFontsPage)
end, BuildFontsPage, "modules")
