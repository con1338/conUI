-- EldoUI CastFX: settings page and style presets.
--   General       which bars, how strong, which effects; preview, test cast
--   Themes        school, class and unit themes; spell pins
--   Theme editor  every part of a theme; duplicate, reset, delete
local _, E = ...
local M = E.CastFX
local Engine = M.Engine
local L = E.L

local Plain = M.Plain

---------------------------------------------------------------------------
-- Preview: a sample bar on the page that casts, finishes, casts again and
-- gets interrupted, with the chosen theme.
---------------------------------------------------------------------------
local CAST_TIME, REST_TIME = 2.2, 0.9

local function PreviewKey(which)
	local key = which == "edit" and M.db.editTheme or M.db.previewTheme
	return M:ThemeExists(key) and key or "fire"
end

local function PreviewStart(bar)
	bar.phase, bar.clock, bar.pushed = "cast", 0, false
	bar:SetMinMaxValues(0, CAST_TIME)
	bar:SetValue(0)
	bar:SetStatusBarTexture(E.media.statusbar)
	bar:SetStatusBarColor(1, 1, 1)
	local key = PreviewKey(bar.which)
	bar.text:SetText(E:Translate(M:GetTheme(key).name or key))
	Engine.Start(Engine.Get(bar, "test"), key, { channel = false, notInterruptible = false })
end

local function PreviewUpdate(bar, elapsed)
	bar.clock = bar.clock + elapsed
	local deco = Engine.Get(bar)
	if bar.phase == "cast" then
		bar:SetValue(math.min(bar.clock, CAST_TIME))
		if not bar.pushed and bar.clock >= CAST_TIME * 0.5 then
			bar.pushed = true
			if deco then Engine.Pushback(deco) end
		end
		if bar.clock >= CAST_TIME then
			if deco then Engine.Finish(deco, bar.fail and "fail" or "success") end
			bar.text:SetText(bar.fail and (E:GameText(_G.INTERRUPTED, L["Interrupted"])) or L["Done"])
			bar.phase, bar.clock = "rest", 0
		end
	elseif bar.clock >= REST_TIME then
		bar.fail = not bar.fail
		PreviewStart(bar)
	end
end

local function PreviewRow(which, label)
	return {
		type = "preview", label = label, height = 64,
		desc = L["A sample cast with the theme: it fills, gets pushed back once, then finishes or is interrupted, in turn."],
		create = function(canvas)
			if not canvas then return end
			local bar = E:CreateStatusBar(canvas)
			bar:SetPoint("LEFT", canvas, "LEFT", 40, -4)
			bar:SetPoint("RIGHT", canvas, "RIGHT", -40, -4)
			bar:SetHeight(18)
			bar.text = E:CreateText(bar, E.tokens.size.label, "LEFT")
			bar.text:SetPoint("LEFT", 4, 0)
			bar.which = which
			bar.fail = true
			canvas.bar = bar
			PreviewStart(bar)
			bar:SetScript("OnUpdate", PreviewUpdate)
		end,
		update = function(canvas)
			if canvas and canvas.bar then PreviewStart(canvas.bar) end
		end,
	}
end

---------------------------------------------------------------------------
-- Values
---------------------------------------------------------------------------
local function Themes() return M:ThemeValues() end

local function ThemesOrAuto()
	local values = M:ThemeValues()
	values[""] = L["No pin (automatic)"]
	return values
end

local function PlayerClass()
	local _, class = UnitClass("player")
	return class or "WARRIOR"
end

-- Spells for the pin row: this session's casts and every pinned spell.
local function SpellName(id)
	local name = C_Spell and C_Spell.GetSpellName and Plain(C_Spell.GetSpellName(id))
	return type(name) == "string" and name or ("#" .. id)
end

local function PinValues()
	local values = {}
	for _, entry in ipairs(M.recent) do values[entry.id] = ("%s (%d)"):format(entry.name, entry.id) end
	for id, key in pairs(M.db.spells) do
		local theme = M:GetTheme(key)
		values[id] = ("%s (%d) " .. E:TextHex("secondary") .. "- %s|r"):format(SpellName(id), id, E:Translate(theme and theme.name or key))
	end
	return values
end

local function NoPinSpell()
	return (tonumber(M.db.pinSpell) or 0) <= 0
end

-- A typed spell ID becomes the spell of the pin row.
function M:ReadPinInput()
	local text = self.db.pinInput
	if text == nil or text == "" then return end
	self.db.pinInput = ""
	local id = tonumber(text)
	if id and id > 0 then
		self.db.pinSpell = id
		self:RememberSpell(id, SpellName(id))
	end
end

---------------------------------------------------------------------------
-- Theme editor helpers
---------------------------------------------------------------------------
local function EditKey()
	local key = M.db.editTheme
	if not M:ThemeExists(key) then key = "fire" end
	return key
end

-- A key into the edited theme; the first look makes the player's copy.
local function TKey(field)
	return function()
		local key = EditKey()
		M:EditableTheme(key)
		return ("themes.%s.%s"):format(key, field)
	end
end

local function Field(field)
	local theme = M:GetTheme(EditKey())
	return theme and theme[field]
end

local function IsBuiltin() return M.BUILTIN[EditKey()] ~= nil end

function M:DuplicateTheme()
	local source = self:GetTheme(EditKey())
	local index = 1
	while self.db.themes["custom" .. index] do index = index + 1 end
	local key = "custom" .. index
	local copy = CopyTable(source)
	copy.name = (L["%s copy"]):format(E:Translate(source.name or EditKey()))
	self.db.themes[key] = copy
	self.db.editTheme = key
	return key
end

function M:ResetTheme()
	local key = EditKey()
	if M.BUILTIN[key] then self.db.themes[key] = nil end
end

function M:DeleteTheme()
	local key = EditKey()
	if M.BUILTIN[key] then return end
	self.db.themes[key] = nil
	for id, pinned in pairs(self.db.spells) do
		if pinned == key then self.db.spells[id] = nil end
	end
	self.db.editTheme = "fire"
end

local function Refresh()
	if E.RefreshConfig then E:RefreshConfig() end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local BAR_ROWS = {
	{ "player", L["Player"], L["Your own cast bar. Your casts get the theme of their spell school."] },
	{ "target", L["Target"], L["Your target's cast bar, in the target theme (Themes tab)."] },
	{ "focus", L["Focus"], L["Your focus's cast bar, in the focus theme."] },
	{ "pet", L["Pet"], L["Your pet's cast bar, in the pet theme."] },
	{ "boss", L["Boss"], L["Boss cast bars, in the boss theme."] },
}

local function GeneralTab()
	local rows = {
		{ type = "tab", label = L["General"] },
		PreviewRow("general", L["Preview"]),
		{ type = "select", key = "previewTheme", label = L["Preview theme"], values = Themes,
			desc = L["The theme the sample above and the test cast of your own bar use."] },
		{ type = "execute", label = L["Test cast"],
			desc = L["Plays a 3-second test cast on every enabled cast bar, each in the theme it would use (out of combat; also /eui castfx test)."],
			func = function() M:TestCast() end },
		{ type = "header", label = L["Cast bars"] },
		{ type = "description", label = L["EldoUI's own cast bars get effects. For a unit whose EldoUI cast bar is off, Blizzard's own cast bar gets them instead."] },
	}
	for _, row in ipairs(BAR_ROWS) do
		rows[#rows + 1] = { type = "toggle", key = "bars." .. row[1], label = row[2], desc = row[3] }
	end
	rows[#rows + 1] = { type = "toggle", key = "blizzard", label = L["Blizzard's cast bars too"],
		desc = L["When EldoUI's cast bar for a checked unit is off, decorate Blizzard's own cast bar for that unit instead."] }
	local more = {
		{ type = "header", label = L["Effects"] },
		{ type = "range", key = "intensity", label = L["Intensity"], min = 0, max = 200, step = 10,
			desc = L["Scales particle rates, flashes and the shine together. 100 is the theme as made."] },
		{ type = "toggle", key = "tint", label = L["Theme color"],
			desc = L["The fill takes the theme's color (or gradient). Casts that can't be interrupted keep the bar's gray."] },
		{ type = "select", key = "spark", label = L["Spark"],
			values = { THEME = L["The theme's spark"], LINE = L["EldoUI's thin line"], OFF = L["None"] },
			desc = L["The light that rides the fill edge."] },
		{ type = "toggle", key = "trail", label = L["Light trail"], desc = L["A short streak of light behind the spark."] },
		{ type = "toggle", key = "shimmer", label = L["Shine"], desc = L["A shine sweeping over the filled part of the bar."] },
		{ type = "toggle", key = "frameLight", label = L["Border light"], desc = L["The bar's top and bottom edge light up as the cast fills."] },
		{ type = "toggle", key = "castGlow", label = L["Glow while casting"],
			desc = L["A glow round the bar during the cast, in the theme color. Its style is set on the Glows page."] },
		{ type = "header", label = L["Particles"] },
		{ type = "toggle", key = "particles", label = L["Enable"],
			desc = L["Small sprites flying off the fill edge and drifting inside the bar. Off keeps colors, spark and flashes."],
			cog = {
				{ type = "range", key = "budget", label = L["Particle budget"], min = 0, max = 250, step = 5,
					desc = L["Most particles alive at once across all bars. Lower it if your frame rate drops."] },
				{ type = "range", key = "barBudget", label = L["Per bar"], min = 0, max = 100, step = 5,
					desc = L["Most particles alive at once on one bar."] },
			} },
		{ type = "select", key = "combat", label = L["In combat"], dependsOn = "particles",
			values = { FULL = L["All particles"], REDUCED = L["Half, no ambient"], OFF = L["No particles"] },
			desc = L["Fewer or no particles while you are in combat. Colors, spark and flashes stay."] },
		{ type = "header", label = L["Finish"] },
		{ type = "select", key = "success", label = L["Cast finished"],
			values = { BURST = L["Flash and burst"], FLASH = L["Flash"], OFF = L["Nothing"] },
			desc = L["What the bar does when a cast completes: a short flash, and particles bursting from the edge."] },
		{ type = "select", key = "fail", label = L["Cast interrupted"],
			values = { SHAKE = L["Flash and shake"], FLASH = L["Flash"], OFF = L["Nothing"] },
			desc = L["What the bar does when a cast fails or is interrupted: a flash in the theme's fail color, and a short shake."] },
		{ type = "toggle", key = "pushback", label = L["Pushback pulse"],
			desc = L["A short orange pulse when a cast is pushed back or a channel changes."] },
	}
	for _, row in ipairs(more) do rows[#rows + 1] = row end
	return rows
end

local function ThemesTab()
	local rows = {
		{ type = "tab", label = L["Themes"] },
		{ type = "description", label = L["Your casts get their spell school's theme (pinned spells first, then your class theme). Other units get one fixed theme each."] },
		{ type = "header", label = L["Spell schools"] },
	}
	for _, school in ipairs(M.SCHOOLS) do
		rows[#rows + 1] = { type = "select", key = "schools." .. school, label = M.SCHOOL_NAMES[school], values = Themes,
			desc = "Theme for your %s spells.", descFill = M.SCHOOL_NAMES[school] }
	end
	local more = {
		{ type = "header", label = L["Class and units"] },
		{ type = "select", key = function() return "classes." .. PlayerClass() end, label = L["Your class"],
			values = Themes, desc = L["Theme for your spells that are in no school above (not in EldoUI's list and not pinned)."] },
		{ type = "select", key = "units.target", label = L["Target"], values = Themes, desc = L["Theme of every cast on the target cast bar."] },
		{ type = "select", key = "units.focus", label = L["Focus"], values = Themes, desc = L["Theme of every cast on the focus cast bar."] },
		{ type = "select", key = "units.pet", label = L["Pet"], values = Themes, desc = L["Theme of every cast on the pet cast bar."] },
		{ type = "select", key = "units.boss", label = L["Boss"], values = Themes, desc = L["Theme of every cast on the boss cast bars."] },
		{ type = "select", key = "fallback", label = L["Fallback"], values = Themes, desc = L["Used when a theme above was deleted."] },
		{ type = "header", label = L["Spell pins"] },
		{ type = "description", label = L["Pin a theme to one of your spells; a pin wins over everything else. The list holds the spells you cast this session and your pins."] },
		{ type = "select", key = "pinSpell", label = L["Spell"], values = PinValues,
			desc = L["A spell you cast lately, or one you pinned. Cast the spell once to see it here, or type its ID below."] },
		{ type = "input", key = "pinInput", label = L["Or spell ID"],
			desc = L["Type a spell ID and press Enter to put that spell in the Spell row."] },
		{ type = "select", key = function() return ("spells.%d"):format(tonumber(M.db.pinSpell) or 0) end, label = L["Theme for this spell"],
			values = ThemesOrAuto, hidden = NoPinSpell,
			desc = L["The theme this spell always gets. No pin lets EldoUI choose by school."] },
	}
	for _, row in ipairs(more) do rows[#rows + 1] = row end
	return rows
end

local function EditorTab()
	return {
		{ type = "tab", label = L["Theme editor"] },
		PreviewRow("edit", L["Preview"]),
		{ type = "select", key = "editTheme", label = L["Theme"], values = Themes,
			desc = L["The theme the rows below change. Built-in themes can be reset; copies can be renamed and deleted."] },
		{ type = "execute", label = L["Duplicate"], desc = L["Makes a copy of this theme to change freely."],
			func = function() M:DuplicateTheme() Refresh() end },
		{ type = "execute", label = L["Reset theme"], confirm = true, hidden = function() return not IsBuiltin() end,
			desc = L["Puts this built-in theme back as EldoUI ships it."],
			func = function() M:ResetTheme() M:OnProfileChanged() Refresh() end },
		{ type = "execute", label = L["Delete theme"], confirm = true, hidden = IsBuiltin,
			desc = L["Deletes this copy. Pins and rows that used it go back to automatic."],
			func = function() M:DeleteTheme() M:OnProfileChanged() Refresh() end },
		{ type = "input", key = TKey("name"), label = L["Name"], hidden = IsBuiltin, desc = L["The name of this theme in every list."] },

		{ type = "header", label = L["Bar"] },
		{ type = "color", key = TKey("color"), label = L["Fill color"], desc = L["Color of the filled part."] },
		{ type = "toggle", key = TKey("gradient"), label = L["Gradient"], desc = L["Blend the fill towards a second color at the growing edge."] },
		{ type = "color", key = TKey("color2"), label = L["Edge color"], hidden = function() return not Field("gradient") end,
			desc = L["The gradient's color at the fill edge."] },
		{ type = "media", mediaKind = "statusbar", key = TKey("texture"), label = L["Fill texture"], default = "default",
			defaultLabel = L["The bar's own"], desc = L["Bar texture during the cast. EldoUI bars only; Blizzard's bars keep theirs."] },

		{ type = "header", label = L["Spark and shine"] },
		{ type = "select", key = TKey("spark"), label = L["Spark"], values = M.SPARKS, desc = L["The light on the fill edge."],
			cog = {
				{ type = "color", key = TKey("sparkColor"), label = L["Spark color"], desc = L["Color of the spark and its trail."] },
				{ type = "range", key = TKey("sparkSize"), label = L["Spark size"], min = 0.5, max = 2, step = 0.1, desc = L["Size of the spark relative to the bar height."] },
				{ type = "toggle", key = TKey("trail"), label = L["Light trail"], desc = L["A short streak of light behind the spark."] },
			} },
		{ type = "select", key = TKey("shine"), label = L["Shine"], values = M.SHINES, desc = L["What sweeps over the filled part."],
			cog = {
				{ type = "color", key = TKey("shineColor"), label = L["Shine color"], desc = L["Color of the shine."] },
				{ type = "range", percent = true, key = TKey("shineAlpha"), label = L["Shine strength"], min = 0, max = 1, step = 0.05, desc = L["How bright the shine is."] },
				{ type = "range", key = TKey("shineSpeed"), label = L["Shine speed"], min = 0.2, max = 3, step = 0.1, desc = L["How fast the shine sweeps."] },
			} },
		{ type = "color", key = TKey("lightColor"), label = L["Border light"], desc = L["Color of the bar's edges lighting up as it fills."] },
		{ type = "range", percent = true, key = TKey("lightAlpha"), label = L["Border light strength"], min = 0, max = 1, step = 0.05, zeroText = "Off", desc = L["How strongly the bar's edges light up in this theme."] },

		{ type = "header", label = L["Particles from the edge"] },
		{ type = "toggle", key = TKey("frontOn"), label = L["Edge particles"], desc = L["Particles that leave the fill edge as it moves."] },
		{ type = "media", mediaKind = "particle", key = TKey("frontTexture"), label = L["Particle"], desc = L["The particle's picture."] },
		{ type = "color", key = TKey("frontColor"), label = L["Particle color"], desc = L["Each particle gets a color between this and the second color."] },
		{ type = "range", key = TKey("frontRate"), label = L["Particles per second"], min = 0, max = 40, step = 1, desc = L["How many particles start each second at intensity 100."] },
		{ type = "range", key = TKey("frontSize"), label = L["Particle size"], min = 2, max = 24, step = 1, desc = L["Average size in pixels; each one varies a little."],
			cog = {
				{ type = "color", key = TKey("frontColor2"), label = L["Second color"], desc = L["The other end of the particles' color range."] },
				{ type = "range", unit = "s", key = TKey("frontLife"), label = L["Lifetime"], min = 0.2, max = 3, step = 0.1, desc = L["Seconds a particle lives on average."] },
				{ type = "range", key = TKey("frontSpeed"), label = L["Speed"], min = 0, max = 80, step = 1, desc = L["How fast particles drift back along the bar, in pixels per second."] },
				{ type = "range", key = TKey("frontSpread"), label = L["Spread"], min = 0, max = 180, step = 5, desc = L["How far up and down particles fan out, in degrees."] },
				{ type = "range", key = TKey("frontRise"), label = L["Rise"], min = -80, max = 80, step = 1, desc = L["Upward drift in pixels per second; negative values make particles fall."] },
				{ type = "toggle", key = TKey("frontSpin"), label = L["Spin"], desc = L["Particles turn as they fly."] },
				{ type = "select", key = TKey("frontBlend"), label = L["Blend"], values = { ADD = L["Glowing (additive)"], BLEND = L["Solid"] },
					desc = L["Glowing particles light up what is behind them; solid ones cover it."] },
			} },

		{ type = "header", label = L["Particles in the fill"] },
		{ type = "toggle", key = TKey("ambientOn"), label = L["Fill particles"], desc = L["Particles drifting inside the filled part of the bar. Not in combat with In combat set to Half."] },
		{ type = "media", mediaKind = "particle", key = TKey("ambientTexture"), label = L["Particle"], desc = L["The particle's picture."] },
		{ type = "color", key = TKey("ambientColor"), label = L["Particle color"], desc = L["Color of the fill particles."] },
		{ type = "range", key = TKey("ambientRate"), label = L["Particles per second"], min = 0, max = 20, step = 1, desc = L["How many fill particles start each second at intensity 100."],
			cog = {
				{ type = "range", key = TKey("ambientSize"), label = L["Particle size"], min = 2, max = 24, step = 1, desc = L["Average size in pixels."] },
				{ type = "range", unit = "s", key = TKey("ambientLife"), label = L["Lifetime"], min = 0.2, max = 3, step = 0.1, desc = L["Seconds a particle lives on average."] },
				{ type = "range", key = TKey("ambientRise"), label = L["Rise"], min = -40, max = 40, step = 1, desc = L["Upward drift in pixels per second; negative values sink."] },
				{ type = "select", key = TKey("ambientBlend"), label = L["Blend"], values = { ADD = L["Glowing (additive)"], BLEND = L["Solid"] },
					desc = L["Glowing particles light up what is behind them; solid ones cover it."] },
			} },

		{ type = "header", label = L["Finish"] },
		{ type = "color", key = TKey("successColor"), label = L["Finish color"], desc = L["Color of the flash when a cast completes."] },
		{ type = "color", key = TKey("failColor"), label = L["Interrupt color"], desc = L["Color of the flash and falling particles when a cast is interrupted."] },
		{ type = "range", key = TKey("burst"), label = L["Burst particles"], min = 0, max = 24, step = 1, desc = L["How many particles burst from the edge when a cast completes."] },
	}
end

function M.options()
	local options = {}
	for _, row in ipairs(GeneralTab()) do options[#options + 1] = row end
	for _, row in ipairs(ThemesTab()) do options[#options + 1] = row end
	for _, row in ipairs(EditorTab()) do options[#options + 1] = row end
	return options
end

-- Page changes while the module is off still tidy pins and themes.
M.refreshWhenOff = function(module)
	module:ReadPinInput()
	module:TidyThemes()
end

---------------------------------------------------------------------------
-- Style presets: the look only; your pins and edited themes stay.
---------------------------------------------------------------------------
local ALL_ON = { particles = true, shimmer = true, frameLight = true, trail = true, tint = true, spark = "THEME", pushback = true }

local function Preset(theme, extra)
	local settings = { fallback = theme, units = { target = theme, focus = theme, pet = theme, boss = theme } }
	for key, value in pairs(ALL_ON) do settings[key] = value end
	for key, value in pairs(extra or {}) do settings[key] = value end
	return settings
end

E:RegisterStyles("CastFX", {
	{ key = "Arcane", title = L["Arcane"], desc = L["Every school in its own theme; other units arcane. Rising motes, light lines."],
		settings = Preset("arcane", { intensity = 100, castGlow = false, success = "BURST", fail = "SHAKE" }) },
	{ key = "Inferno", title = L["Inferno"], desc = L["Fire for other units and physical spells, dense embers and bursts."],
		settings = Preset("fire", { intensity = 140, castGlow = false, success = "BURST", fail = "SHAKE", schools = { physical = "fire" } }) },
	{ key = "Frost", title = L["Frost"], desc = L["Frost for other units, gentle flakes and a cold border light."],
		settings = Preset("frost", { intensity = 80, castGlow = false, success = "FLASH", fail = "SHAKE" }) },
	{ key = "Shadow", title = L["Shadow"], desc = L["Shadow for other units, dark wisps and a glow while casting."],
		settings = Preset("shadow", { intensity = 100, castGlow = true, success = "FLASH", fail = "SHAKE" }) },
	{ key = "Holy", title = L["Holy"], desc = L["Holy for other units, golden motes and a bright finish."],
		settings = Preset("holy", { intensity = 110, castGlow = false, success = "BURST", fail = "FLASH" }) },
	{ key = "Nature", title = L["Nature"], desc = L["Nature for other units, leaves and a green shine; professions in their own themes."],
		settings = Preset("nature", { intensity = 100, castGlow = false, success = "BURST", fail = "SHAKE",
			schools = { crafting = "crafting", mining = "mining", herbalism = "herbalism", fishing = "fishing" } }) },
	{ key = "Minimal", title = L["Minimal"], desc = L["Theme color and spark with a short flash; no particles, shine or glow. Lowest cost."],
		settings = { fallback = "minimal", units = { target = "minimal", focus = "minimal", pet = "minimal", boss = "minimal" },
			particles = false, shimmer = false, frameLight = false, trail = false, castGlow = false, tint = true,
			spark = "THEME", success = "FLASH", fail = "FLASH", pushback = true, intensity = 100 } },
})
