-- EldoUI CastFX: themed cast bars. A spell-school color on the
-- fill, a spark and a light trail riding the fill edge, a shine sweeping
-- over the filled part, a border that lights up as the cast fills, a glow,
-- small particles and finish effects (success flash and burst, interrupt
-- flash and shake, pushback pulse).
--
-- Files:
--   Core.lua     module, settings, built-in themes, particle media, theme choice
--   Engine.lua   the effect layers on one status bar and the particle pool
--   Bars.lua     EldoUI cast bars (UnitFrames cast hooks), Blizzard's own
--                cast bars, test casts, slash words
--   Options.lua  settings page and style presets
--
-- Rules (Forever, Midnight restrictions):
--   * Pure decoration on bars the game already drives. The spark, trail,
--     shine and particles hang on the bar's fill texture, so the client moves
--     them; no Lua math on cast times, ever.
--   * The theme of the player's own cast comes from its spell (our table in
--     Data/CastFXSpells.lua, the player's pins), read only when the values
--     are not secret. Other units get one fixed theme per unit (design
--     decision): nothing about their spell is guessed.
--   * notInterruptible may be secret: it is only handed to the client
--     (C_CurveUtil.EvaluateColorFromBoolean), never tested.
--   * Outcomes (success, interrupt, pushback) come from the cast bars'
--     own events. Nothing here acts for the player.
-- Written from scratch for EldoUI. The particle textures are drawn by
-- tools/gen_castfx_particles.py; the rest are EldoUI textures and atlases
-- the client ships (checked once, with fallbacks).
local _, E = ...
local L = E.L

local Key = E.Key
local issecret = issecretvalue or function() return false end

local M = E:NewModule("CastFX", {
	title = "Cast Bar Effects",
	category = "Combat",
	desc = L["Themed cast bars: a spell-school color, a spark with a light trail, a shine, particles and finish effects on EldoUI's cast bars, or on Blizzard's own when EldoUI's are off. Decoration only."],
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.CastFX" },
	optionsPage = "module:CastFX",
	presets = { "Arcane", "Frost", "Holy", "Inferno", "Minimal", "Nature", "Shadow" },
	reload = false,
	defaults = {
		enabled = false,
		bars = { player = true, target = false, focus = false, pet = false, boss = false },
		blizzard = true,        -- also Blizzard's own cast bar of a unit whose EldoUI bar is off
		intensity = 100,        -- %: particle rate, flash strength, glow
		particles = true,
		combat = "REDUCED",     -- FULL | REDUCED | OFF (particles in combat)
		budget = 80,            -- particles alive at once, all bars
		barBudget = 40,         -- particles alive at once, one bar
		tint = true,
		spark = "THEME",        -- THEME | LINE | OFF
		trail = true,
		shimmer = true,
		frameLight = true,
		castGlow = false,
		success = "BURST",      -- BURST | FLASH | OFF
		fail = "SHAKE",         -- SHAKE | FLASH | OFF
		pushback = true,
		schools = {
			arcane = "arcane", fire = "fire", frost = "frost", shadow = "shadow", holy = "holy",
			nature = "nature", physical = "physical", crafting = "crafting", mining = "mining",
			herbalism = "herbalism", fishing = "fishing",
		},
		classes = {
			MAGE = "arcane", WARLOCK = "shadow", PRIEST = "holy", DRUID = "nature", SHAMAN = "nature",
			PALADIN = "holy", HUNTER = "physical", ROGUE = "physical", WARRIOR = "physical",
		},
		units = { target = "minimal", focus = "minimal", pet = "minimal", boss = "minimal" },
		fallback = "minimal",
		spells = {},            -- [spellID] = theme key: the player's pins
		themes = {},            -- [key] = full theme: edited built-ins and custom themes
		editTheme = "fire",     -- theme shown in the editor
		previewTheme = "fire",  -- theme of the page preview and the test cast
		pinSpell = 0,           -- spell shown in the pin row
	},
})

-- "Reset to defaults" keeps the player's own data and window places
-- (E:ResetModuleSettings, Core/Config.lua).
M.keepOnReset = { "spells", "themes" }
M.keepOnResetNote = E.Key("Your pinned spells and own themes are kept too.")
E.CastFX = M

M.UNIT_KINDS = { "player", "target", "focus", "pet", "boss" }
M.SCHOOLS = { "arcane", "fire", "frost", "shadow", "holy", "nature", "physical", "crafting", "mining", "herbalism", "fishing" }
M.SCHOOL_NAMES = {
	arcane = Key("Arcane"), fire = Key("Fire"), frost = Key("Frost"), shadow = Key("Shadow"), holy = Key("Holy"),
	nature = Key("Nature"), physical = Key("Physical"), crafting = Key("Professions"), mining = Key("Mining"),
	herbalism = Key("Herbalism"), fishing = Key("Fishing"),
}

-- The unit kind of a unit token, or nil for units CastFX leaves alone.
function M.KindOf(unit)
	if type(unit) ~= "string" then return nil end
	if unit == "player" or unit == "target" or unit == "focus" or unit == "pet" then return unit end
	if unit:match("^boss%d$") then return "boss" end
end

-- A value from the game when it is not secret.
-- issecret first: comparing a secret with anything (nil included) errors.
local Plain = E.Plain
M.Plain = Plain

---------------------------------------------------------------------------
-- Textures: atlases the Forever client ships (checked once through
-- E:ClientAtlas, which logs a miss to the error log) with EldoUI fallbacks.
---------------------------------------------------------------------------
local TEX = "Interface\\AddOns\\EldoUI\\Media\\Textures\\"
local FX = "Interface\\AddOns\\EldoUI\\Media\\CastFX\\"
M.TEX, M.FX = TEX, FX

-- key -> { atlas, fallback file }
M.ART = {
	pip = { "ui-castingbar-pip", TEX .. "EldoGlow.tga" },
	pipGlow = { "cast_standard_pipglow", TEX .. "EldoGlowRadial.tga" },
	finish = { "ui-castingbar-full-glow-standard", TEX .. "EldoSheen.tga" },
	finishChannel = { "ui-castingbar-full-glow-channel", TEX .. "EldoSheen.tga" },
	interrupt = { "cast_interrupt_outerglow", TEX .. "EldoGlow.tga" },
	glowLine = { "Cast_Standard_GlowLine", TEX .. "EldoGlow.tga" },
	wisp = { "Channel_WispGlow2", TEX .. "EldoSoft.tga" },
}

-- Sets art `key` on a texture; returns true when the atlas is shown.
function M.SetArt(texture, key)
	local art = M.ART[key]
	if not art then return false end
	return E:SetClientAtlas(texture, art[1], art[2])
end

-- Spark looks a theme can pick.
M.SPARKS = { pip = Key("Cast pip"), glow = Key("Soft glow"), star = Key("Star"), line = Key("EldoUI line"), none = Key("None") }
-- Shine looks over the filled part.
M.SHINES = { sheen = Key("Sweep"), glowLine = Key("Light line"), wisp = Key("Wisps"), stripes = Key("Stripes"), none = Key("None") }

---------------------------------------------------------------------------
-- The `particle` media kind: EldoUI's own particle textures, a few EldoUI
-- glyphs, and the client's cast bar flakes and sparkles (listed only when
-- the client has them). Plugins and media packs can add their own with
-- E:RegisterMedia("particle", id, name, value, { type = "atlas" | nil }).
---------------------------------------------------------------------------
local OWN_PARTICLES = {
	{ "Ember", Key("Ember"), FX .. "EldoCastFXEmber.tga" },
	{ "Flake", Key("Frost flake"), FX .. "EldoCastFXFlake.tga" },
	{ "Leaf", Key("Leaf"), FX .. "EldoCastFXLeaf.tga" },
	{ "Mote", Key("Sparkle"), FX .. "EldoCastFXMote.tga" },
	{ "Chip", Key("Stone chip"), FX .. "EldoCastFXChip.tga" },
	{ "Puff", Key("Smoke puff"), FX .. "EldoCastFXPuff.tga" },
	{ "Drop", Key("Water drop"), FX .. "EldoCastFXDrop.tga" },
	{ "Rune", Key("Rune ring"), FX .. "EldoCastFXRune.tga" },
	{ "Dot", Key("Dot"), TEX .. "EldoDot.tga" },
	{ "Glow", Key("Glow"), TEX .. "EldoGlowRadial.tga" },
}
local GAME_PARTICLES = {
	{ "Cast_Standard_Flakes01", Key("Cast flakes 1") },
	{ "Cast_Standard_Flakes02", Key("Cast flakes 2") },
	{ "Cast_Standard_Flakes03", Key("Cast flakes 3") },
	{ "Cast_Channel_Sparkles_01", Key("Channel sparkles 1") },
	{ "Cast_Channel_Sparkles_02", Key("Channel sparkles 2") },
}
M.STREAK = FX .. "EldoCastFXStreak.tga"
M.DEFAULT_PARTICLE = "eldo:Mote"

for _, entry in ipairs(OWN_PARTICLES) do
	E:RegisterMedia("particle", "eldo:" .. entry[1], entry[2], entry[3], { source = "EldoUI", type = "file" })
end

-- At enable; each atlas is checked once (E:ClientAtlas remembers).
function M.RegisterGameParticles()
	for _, entry in ipairs(GAME_PARTICLES) do
		local _, isAtlas = E:ClientAtlas(entry[1])
		if isAtlas and not E:GetMedia("particle", "atlas:" .. entry[1]) then
			E:RegisterMedia("particle", "atlas:" .. entry[1], entry[2], entry[1], { source = "Game", type = "atlas" })
		end
	end
end

-- Puts particle media `id` on a texture (an unknown id shows the sparkle).
function M.SetParticle(texture, id)
	local entry = E:GetMedia("particle", id) or E:GetMedia("particle", M.DEFAULT_PARTICLE)
	if entry and entry.type == "atlas" then
		if E:SetClientAtlas(texture, entry.value, FX .. "EldoCastFXMote.tga") then return end
	elseif entry then
		texture:SetTexture(entry.value)
		return
	end
	texture:SetTexture(FX .. "EldoCastFXMote.tga")
end

---------------------------------------------------------------------------
-- Built-in themes. A theme is one flat table (the editor edits it by key):
--   name, color, gradient, color2, texture ("default" or a bar texture)
--   spark (M.SPARKS), sparkColor, sparkSize, trail (bool), shine (M.SHINES),
--   shineColor, shineAlpha, shineSpeed, lightColor, lightAlpha,
--   front* (particles from the fill edge): frontOn, frontTexture,
--     frontColor, frontColor2, frontRate (per second), frontSize (px),
--     frontLife (s), frontSpeed (px/s), frontSpread (degrees), frontRise
--     (px/s, negative falls), frontSpin, frontBlend ("ADD" | "BLEND")
--   ambient* (particles inside the filled part): ambientOn, ambientTexture,
--     ambientColor, ambientRate, ambientSize, ambientLife, ambientRise,
--     ambientBlend
--   successColor, failColor, burst (particles on success)
---------------------------------------------------------------------------
local function Theme(t)
	local base = {
		color = { 1, 0.82, 0.3 }, gradient = false, color2 = { 1, 1, 1 }, texture = "default",
		spark = "pip", sparkColor = { 1, 1, 1 }, sparkSize = 1, trail = true,
		shine = "sheen", shineColor = { 1, 1, 1 }, shineAlpha = 0.35, shineSpeed = 1,
		lightColor = { 1, 1, 1 }, lightAlpha = 0.5,
		frontOn = true, frontTexture = "eldo:Mote", frontColor = { 1, 1, 1 }, frontColor2 = { 1, 1, 1 },
		frontRate = 12, frontSize = 7, frontLife = 0.8, frontSpeed = 22, frontSpread = 70, frontRise = 12,
		frontSpin = false, frontBlend = "ADD",
		ambientOn = false, ambientTexture = "eldo:Dot", ambientColor = { 1, 1, 1 }, ambientRate = 6,
		ambientSize = 4, ambientLife = 1.2, ambientRise = 8, ambientBlend = "ADD",
		successColor = { 1, 1, 1 }, failColor = { 1, 0.2, 0.15 }, burst = 10,
	}
	for key, value in pairs(t) do base[key] = value end
	return base
end

M.BUILTIN_ORDER = { "minimal", "arcane", "fire", "frost", "shadow", "holy", "nature", "physical", "crafting", "mining", "herbalism", "fishing" }
M.BUILTIN = {
	minimal = Theme({ name = Key("Minimal"), color = { 0.85, 0.85, 0.9 }, spark = "line", trail = false, shine = "none",
		lightAlpha = 0, frontOn = false, burst = 0, successColor = { 1, 1, 1 } }),
	arcane = Theme({ name = Key("Arcane"), color = { 0.62, 0.38, 1 }, gradient = true, color2 = { 0.95, 0.55, 1 },
		sparkColor = { 0.9, 0.75, 1 }, shine = "glowLine", shineColor = { 0.85, 0.7, 1 }, lightColor = { 0.8, 0.55, 1 },
		frontTexture = "eldo:Mote", frontColor = { 0.85, 0.6, 1 }, frontColor2 = { 0.6, 0.85, 1 }, frontRate = 10,
		frontSpin = true, ambientOn = true, ambientTexture = "eldo:Rune", ambientColor = { 0.75, 0.5, 1 }, ambientRate = 2,
		ambientSize = 9, ambientLife = 1.4, ambientRise = 4, successColor = { 0.9, 0.7, 1 } }),
	fire = Theme({ name = Key("Fire"), color = { 1, 0.42, 0.08 }, gradient = true, color2 = { 1, 0.78, 0.2 },
		spark = "glow", sparkColor = { 1, 0.85, 0.5 }, sparkSize = 1.1, shine = "wisp", shineColor = { 1, 0.6, 0.2 },
		shineAlpha = 0.4, shineSpeed = 1.4, lightColor = { 1, 0.55, 0.15 }, lightAlpha = 0.6,
		frontTexture = "eldo:Ember", frontColor = { 1, 0.55, 0.1 }, frontColor2 = { 1, 0.85, 0.35 }, frontRate = 18,
		frontSize = 6, frontLife = 0.7, frontSpeed = 26, frontRise = 30, ambientOn = true, ambientTexture = "eldo:Puff",
		ambientColor = { 0.35, 0.25, 0.2 }, ambientRate = 3, ambientSize = 10, ambientLife = 1.1, ambientRise = 14, ambientBlend = "BLEND",
		successColor = { 1, 0.75, 0.35 }, burst = 14 }),
	frost = Theme({ name = Key("Frost"), color = { 0.35, 0.7, 1 }, gradient = true, color2 = { 0.75, 0.95, 1 },
		sparkColor = { 0.85, 0.97, 1 }, shine = "sheen", shineColor = { 0.8, 0.95, 1 }, shineSpeed = 0.7,
		lightColor = { 0.6, 0.85, 1 }, lightAlpha = 0.7, frontTexture = "eldo:Flake", frontColor = { 0.75, 0.92, 1 },
		frontColor2 = { 1, 1, 1 }, frontRate = 9, frontSize = 8, frontLife = 1.1, frontSpeed = 16, frontRise = -14,
		frontSpin = true, frontBlend = "BLEND", successColor = { 0.8, 0.95, 1 } }),
	shadow = Theme({ name = Key("Shadow"), color = { 0.45, 0.2, 0.65 }, gradient = true, color2 = { 0.2, 0.08, 0.3 },
		spark = "glow", sparkColor = { 0.75, 0.45, 1 }, shine = "wisp", shineColor = { 0.55, 0.25, 0.85 }, shineAlpha = 0.5,
		shineSpeed = 0.6, lightColor = { 0.6, 0.3, 0.9 }, frontTexture = "eldo:Puff", frontColor = { 0.3, 0.12, 0.45 },
		frontColor2 = { 0.55, 0.25, 0.8 }, frontRate = 10, frontSize = 10, frontLife = 1, frontSpeed = 14, frontRise = 10,
		frontBlend = "BLEND", successColor = { 0.7, 0.4, 1 }, failColor = { 0.5, 0.1, 0.6 } }),
	holy = Theme({ name = Key("Holy"), color = { 1, 0.85, 0.45 }, gradient = true, color2 = { 1, 1, 0.8 },
		sparkColor = { 1, 0.95, 0.75 }, sparkSize = 1.1, shine = "glowLine", shineColor = { 1, 0.95, 0.7 }, shineAlpha = 0.45,
		lightColor = { 1, 0.9, 0.6 }, lightAlpha = 0.7, frontTexture = "eldo:Mote", frontColor = { 1, 0.92, 0.6 },
		frontColor2 = { 1, 1, 1 }, frontRate = 8, frontSpeed = 12, frontRise = 18, ambientOn = true,
		ambientTexture = "eldo:Glow", ambientColor = { 1, 0.9, 0.55 }, ambientRate = 5, ambientSize = 5,
		successColor = { 1, 0.95, 0.7 }, burst = 14 }),
	nature = Theme({ name = Key("Nature"), color = { 0.3, 0.75, 0.25 }, gradient = true, color2 = { 0.7, 0.95, 0.35 },
		sparkColor = { 0.85, 1, 0.6 }, shine = "sheen", shineColor = { 0.75, 1, 0.5 }, lightColor = { 0.5, 0.95, 0.35 },
		frontTexture = "eldo:Leaf", frontColor = { 0.4, 0.8, 0.25 }, frontColor2 = { 0.75, 0.9, 0.3 }, frontRate = 8,
		frontSize = 8, frontLife = 1.2, frontSpeed = 14, frontRise = -8, frontSpin = true, frontBlend = "BLEND",
		successColor = { 0.75, 1, 0.5 } }),
	physical = Theme({ name = Key("Physical"), color = { 0.78, 0.62, 0.42 }, gradient = true, color2 = { 0.95, 0.85, 0.65 },
		sparkColor = { 1, 0.95, 0.85 }, shine = "sheen", shineAlpha = 0.25, lightAlpha = 0.35,
		frontTexture = "eldo:Dot", frontColor = { 1, 0.9, 0.7 }, frontColor2 = { 1, 1, 1 }, frontRate = 6, frontSize = 4,
		frontLife = 0.5, frontSpeed = 30, frontRise = 0, successColor = { 1, 0.95, 0.85 }, burst = 6 }),
	crafting = Theme({ name = Key("Professions"), color = { 0.95, 0.75, 0.35 }, sparkColor = { 1, 0.95, 0.75 },
		shine = "sheen", shineColor = { 1, 0.9, 0.6 }, shineSpeed = 0.8, lightAlpha = 0.3, frontTexture = "eldo:Mote",
		frontColor = { 1, 0.9, 0.55 }, frontRate = 5, frontSpeed = 10, frontRise = 10, successColor = { 1, 0.9, 0.6 }, burst = 8 }),
	mining = Theme({ name = Key("Mining"), color = { 0.6, 0.48, 0.36 }, gradient = true, color2 = { 0.8, 0.7, 0.55 },
		sparkColor = { 1, 0.85, 0.6 }, shine = "none", lightAlpha = 0.3, frontTexture = "eldo:Chip",
		frontColor = { 0.55, 0.5, 0.45 }, frontColor2 = { 0.75, 0.65, 0.5 }, frontRate = 7, frontSize = 6, frontLife = 0.8,
		frontSpeed = 30, frontRise = -40, frontSpin = true, frontBlend = "BLEND", burst = 8 }),
	herbalism = Theme({ name = Key("Herbalism"), color = { 0.4, 0.78, 0.3 }, gradient = true, color2 = { 0.8, 0.9, 0.4 },
		sparkColor = { 0.9, 1, 0.7 }, shine = "sheen", shineColor = { 0.8, 1, 0.6 }, lightAlpha = 0.3,
		frontTexture = "eldo:Leaf", frontColor = { 0.45, 0.8, 0.3 }, frontColor2 = { 0.85, 0.85, 0.35 }, frontRate = 6,
		frontSize = 7, frontLife = 1.2, frontSpeed = 12, frontRise = -10, frontSpin = true, frontBlend = "BLEND" }),
	fishing = Theme({ name = Key("Fishing"), color = { 0.2, 0.55, 0.85 }, gradient = true, color2 = { 0.45, 0.85, 0.95 },
		sparkColor = { 0.85, 0.95, 1 }, shine = "wisp", shineColor = { 0.6, 0.85, 1 }, shineSpeed = 0.5, lightAlpha = 0.35,
		frontTexture = "eldo:Drop", frontColor = { 0.6, 0.85, 1 }, frontRate = 4, frontSize = 6, frontLife = 0.9,
		frontSpeed = 18, frontRise = -30, frontBlend = "BLEND" }),
}

-- The theme in use for a key: the player's edited copy, else the built-in.
function M:GetTheme(key)
	local themes = self.db and self.db.themes
	return (themes and themes[key]) or M.BUILTIN[key]
end

function M:ThemeExists(key)
	return type(key) == "string" and self:GetTheme(key) ~= nil
end

-- Keys in display order: built-ins, then custom themes by name.
function M:ThemeKeys()
	local keys = {}
	for _, key in ipairs(M.BUILTIN_ORDER) do keys[#keys + 1] = key end
	local custom = {}
	for key in pairs(self.db and self.db.themes or {}) do
		if not M.BUILTIN[key] then custom[#custom + 1] = key end
	end
	table.sort(custom, function(a, b) return (self:GetTheme(a).name or a) < (self:GetTheme(b).name or b) end)
	for _, key in ipairs(custom) do keys[#keys + 1] = key end
	return keys
end

function M:ThemeValues()
	local values = {}
	for _, key in ipairs(self:ThemeKeys()) do values[key] = self:GetTheme(key).name or key end
	return values
end

-- The editor's copy of a theme (made on first edit from the built-in).
function M:EditableTheme(key)
	local themes = self.db.themes
	if not themes[key] and M.BUILTIN[key] then themes[key] = CopyTable(M.BUILTIN[key]) end
	return themes[key]
end

-- Edited built-ins that equal the built-in again take no room.
function M:TidyThemes()
	for key, theme in pairs(self.db.themes) do
		local builtin = M.BUILTIN[key]
		if builtin and E.DeepEqual(theme, builtin) then
			self.db.themes[key] = nil
		elseif builtin then
			-- Fields added in a later version.
			for field, value in pairs(builtin) do
				if theme[field] == nil then theme[field] = type(value) == "table" and CopyTable(value) or value end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Which theme a cast gets.
---------------------------------------------------------------------------
local bySpell, byName, byIcon = {}, {}, {}
local function Nop() end
local mapsBuilt = false

-- From Data/CastFXSpells.lua: the spell IDs, plus the names and icons the
-- client gives for them (so every rank and every language matches). An
-- icon two schools share decides nothing. `rebuild` starts over (tests).
function M.BuildSpellMaps(rebuild)
	if rebuild then
		wipe(bySpell)
		wipe(byName)
		wipe(byIcon)
		mapsBuilt = false
	end
	if mapsBuilt then return end
	local data = E.CastFXSpells
	if not data then return end
	mapsBuilt = true
	local getName = C_Spell and C_Spell.GetSpellName
	local getIcon = C_Spell and C_Spell.GetSpellTexture
	local function Add(school, id)
		bySpell[id] = bySpell[id] or school
		local okName, name = pcall(getName or Nop, id)
		name = okName and Plain(name)
		if type(name) == "string" and name ~= "" then byName[name] = byName[name] or school end
		local okIcon, icon = pcall(getIcon or Nop, id)
		icon = okIcon and Plain(icon)
		if icon then
			if byIcon[icon] == nil then
				byIcon[icon] = school
			elseif byIcon[icon] ~= school then
				byIcon[icon] = false
			end
		end
	end
	for school, list in pairs(data.schools or {}) do
		for _, id in ipairs(list) do Add(school, id) end
	end
	for school, list in pairs(data.professions or {}) do
		for _, id in ipairs(list) do Add(school, id) end
	end
end

-- The school of a readable spell, from its ID, name or icon.
function M.SchoolOf(spellID, name, icon)
	M.BuildSpellMaps()
	spellID, name, icon = Plain(spellID), Plain(name), Plain(icon)
	if spellID and bySpell[spellID] then return bySpell[spellID], "spell" end
	if type(name) == "string" and byName[name] then return byName[name], "name" end
	if icon and byIcon[icon] then return byIcon[icon], "icon" end
end

-- Theme key for a cast on a bar of `kind`. info: the cast hook's info
-- (spellID, name, texture, isTradeskill; any may be secret).
function M:ThemeKeyFor(kind, info)
	local db = self.db
	local key
	if kind == "player" then
		info = info or {}
		local spellID = Plain(info.spellID)
		if spellID and db.spells[spellID] then key = db.spells[spellID] end
		if not self:ThemeExists(key) then
			local school = M.SchoolOf(spellID, info.name, info.texture)
			if not school and Plain(info.isTradeskill) == true then school = "crafting" end
			key = school and db.schools[school]
		end
		if not self:ThemeExists(key) then
			local _, class = UnitClass("player")
			key = class and db.classes[class]
		end
	elseif kind then
		key = db.units[kind]
	end
	if not self:ThemeExists(key) then key = db.fallback end
	if not self:ThemeExists(key) then key = "minimal" end
	return key
end

-- Spells the player cast this session, newest first (for the pin row).
M.recent = {}
function M:RememberSpell(spellID, name, icon)
	spellID, name = Plain(spellID), Plain(name)
	if not spellID or type(name) ~= "string" then return end
	for index = #self.recent, 1, -1 do
		if self.recent[index].id == spellID then table.remove(self.recent, index) end
	end
	table.insert(self.recent, 1, { id = spellID, name = name, icon = Plain(icon) })
	while #self.recent > 15 do table.remove(self.recent) end
end

---------------------------------------------------------------------------
-- Module life
---------------------------------------------------------------------------
function M:OnInitialize()
	self:TidyThemes()
	-- Pins to themes that were deleted, or cleared in the pin row.
	for id, key in pairs(self.db.spells) do
		if not self:ThemeExists(key) then self.db.spells[id] = nil end
	end
end

function M:OnEnable()
	M.RegisterGameParticles()
	M.BuildSpellMaps()
	self.Engine.CombatChanged(InCombatLockdown())
	self:AttachBars()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:AttachBars() end)
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function() self.Engine.CombatChanged(true) end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function() self.Engine.CombatChanged(false) end)
end

function M:OnDisable()
	self:UnregisterEvent("PLAYER_ENTERING_WORLD")
	self:UnregisterEvent("PLAYER_REGEN_DISABLED")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:DetachBars()
end

function M:OnProfileChanged()
	if not self.db then return end
	if self.ReadPinInput then self:ReadPinInput() end
	self:TidyThemes()
	for id, key in pairs(self.db.spells) do
		if not self:ThemeExists(key) then self.db.spells[id] = nil end
	end
	if self.active then
		self:AttachBars()
		self.Engine.RefreshAll()
	end
end
