-- Encounter Timeline: the options page (tabs Timeline, Icons, Soon,
-- Events, Visibility) with a status preview on top.
local _, E = ...
local L = E.L
local M = E:GetModule("EncounterTimeline")

local function Vertical() return M.db.orientation == "vertical" end

local SOURCES = {
	auto = "Automatic",
	dbm = "DBM only",
	bigwigs = "BigWigs only",
	both = "DBM and BigWigs",
}
local CHANNELS = function()
	local values = { default = "Default" }
	for key, name in pairs(E.soundChannels) do values[key] = name end
	return values
end

---------------------------------------------------------------------------
-- Status preview: a mini timeline in the current style (the big icon at
-- the now end while it is on), the source in use and what reached the
-- timeline this session.
---------------------------------------------------------------------------
local PREVIEW_ICONS = {
	{ left = 2.5, icon = "Interface\\Icons\\Spell_Nature_Lightning", colorType = 2 },
	{ left = 6, icon = "Interface\\Icons\\Ability_Warrior_Cleave", colorType = 3 },
	{ left = 12, icon = "Interface\\Icons\\Spell_Shadow_RaiseDead", colorType = 1 },
}
local MINI_LENGTH, MINI_THICK, MINI_ICON, MINI_BIG = 220, 30, 20, 40

local function CreatePreview(canvas)
	if not canvas then return end
	-- The holder keeps the place of the big icon and the bar together.
	local holder = CreateFrame("Frame", nil, canvas)
	holder:SetSize(MINI_BIG + M.BIG_GAP + MINI_LENGTH, MINI_BIG)
	holder:SetPoint("LEFT", canvas, "LEFT", 4, 0)
	local mini = CreateFrame("Frame", nil, holder)
	mini:SetSize(MINI_LENGTH, MINI_THICK)
	mini.holder = holder
	mini.strip = CreateFrame("Frame", nil, mini)
	mini.strip:SetAllPoints()
	mini.panel = CreateFrame("Frame", nil, mini)
	mini.panel:SetAllPoints()
	mini.top = CreateFrame("Frame", nil, mini)
	mini.top:SetAllPoints()
	mini.top:SetFrameLevel(mini:GetFrameLevel() + 4)
	mini.track = mini.top:CreateTexture(nil, "BORDER")
	mini.track:SetTexture(E.media.flat)
	mini.now = mini.top:CreateTexture(nil, "OVERLAY")
	mini.now:SetTexture(E.media.flat)
	mini.icons = {}
	for index in ipairs(PREVIEW_ICONS) do
		local icon = CreateFrame("Frame", nil, mini.top)
		E:SetTemplate(icon)
		icon:SetSize(MINI_ICON, MINI_ICON)
		icon.tex = icon:CreateTexture(nil, "ARTWORK")
		E:Hairline(icon.tex, "inset", 1)
		E:TrimIcon(icon.tex)
		icon.num = E:CreateText(icon, E.tokens.size.tiny)
		icon.num:SetPoint("CENTER")
		mini.icons[index] = icon
	end
	local big = CreateFrame("Frame", nil, holder)
	big:SetSize(MINI_BIG, MINI_BIG)
	E:SetTemplate(big)
	big.tex = big:CreateTexture(nil, "ARTWORK")
	E:Hairline(big.tex, "inset", 1)
	E:TrimIcon(big.tex)
	big.tex:SetTexture(PREVIEW_ICONS[1].icon)
	big.num = E:CreateText(big, E.tokens.size.section)
	big.num:SetPoint("CENTER")
	mini.big = big
	canvas.mini = mini
	canvas.status = E:CreateText(canvas, E.tokens.size.small, "LEFT")
	canvas.status:SetPoint("TOPLEFT", holder, "TOPRIGHT", 16, 8)
	-- The same top as its left corner: the holder sits on the canvas's
	-- middle.
	canvas.status:SetPoint("TOPRIGHT", canvas, "RIGHT", -4, MINI_BIG / 2 + 8)
	canvas.status:SetWordWrap(true)
	canvas.status:SetJustifyV("TOP")
end

local function UpdatePreview(canvas)
	local mini = canvas and canvas.mini
	if not (mini and M.db) then return end
	local s = M:Settings()
	-- The big icon at the now end (left, or right with reverse travel);
	-- the event it shows leaves the bar, as on the real frame.
	local big = mini.big
	local holder = mini.holder
	mini:ClearAllPoints()
	big:ClearAllPoints()
	if s.big then
		holder:SetWidth(MINI_BIG + M.BIG_GAP + MINI_LENGTH)
		if s.reverse then
			mini:SetPoint("LEFT", holder, "LEFT", 0, 0)
			big:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
		else
			big:SetPoint("LEFT", holder, "LEFT", 0, 0)
			mini:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
		end
	else
		holder:SetWidth(MINI_LENGTH)
		mini:SetPoint("LEFT", holder, "LEFT", 0, 0)
	end
	big:SetShown(s.big)
	E:SetTemplate(big)
	E:SetTemplate(mini.strip, true)
	E:SetStyleEdge(mini.strip, s.backing == "strip")
	mini.strip:SetShown(s.backing == "strip")
	if s.backing == "panel" then E:SetPanelTemplate(mini.panel, true) end
	mini.panel:SetShown(s.backing == "panel")
	local border, accent = E.media.borderColor, E.media.accentColor
	mini.track:ClearAllPoints()
	mini.track:SetPoint("LEFT", mini, "LEFT", 4, 0)
	mini.track:SetPoint("RIGHT", mini, "RIGHT", -4, 0)
	E:Hairline(mini.track, "h", 2)
	mini.track:SetVertexColor(border[1], border[2], border[3], 1)
	mini.track:SetShown(s.backing == "none")
	local nowX = 4 + MINI_ICON / 2
	local travel = MINI_LENGTH - 8 - MINI_ICON
	mini.now:ClearAllPoints()
	mini.now:SetPoint("CENTER", mini, "LEFT", s.reverse and (MINI_LENGTH - nowX) or nowX, 0)
	mini.now:SetHeight(MINI_THICK - 4)
	E:Hairline(mini.now, "w", 2)
	mini.now:SetVertexColor(accent[1], accent[2], accent[3], 0.8)
	local function BorderColor(sample)
		if s.border == "accent" then return accent end
		if s.border == "bossmod" then
			local text = E.tokens.text
			return sample.colorType == 2 and text.bad or sample.colorType == 3 and text.warn or text.good
		end
		return border
	end
	if s.big then
		local first = PREVIEW_ICONS[1]
		local c = BorderColor(first)
		big:SetBackdropBorderColor(c[1], c[2], c[3], 1)
		big.num:SetText(M:FormatSeconds(first.left, s.tenths))
		local stage = M:StageColor(M:Stage(first.left, s))
		big.num:SetTextColor(stage[1], stage[2], stage[3])
	end
	for index, sample in ipairs(PREVIEW_ICONS) do
		local icon = mini.icons[index]
		icon:SetShown(not (s.big and index == 1 and sample.left <= s.bigSeconds))
		local x = nowX + sample.left / 15 * travel
		if s.reverse then x = MINI_LENGTH - x end
		icon:ClearAllPoints()
		icon:SetPoint("CENTER", mini, "LEFT", x, 0)
		icon.tex:SetTexture(sample.icon)
		local color = BorderColor(sample)
		icon:SetBackdropBorderColor(color[1], color[2], color[3], 1)
		local showNumber = s.numbers > 0 and sample.left <= s.numbers
		icon.num:SetText(showNumber and M:FormatSeconds(sample.left, s.tenths) or "")
		local c = M:StageColor(M:Stage(sample.left, s))
		icon.num:SetTextColor(c[1], c[2], c[3])
	end
	-- Status lines
	local lines = {}
	local secondary = E:TokenHex(E.tokens.text.secondary)
	local _, conflict = E:GetModuleConflict(M)
	if conflict then
		lines[#lines + 1] = E:TokenHex(E.tokens.text.warn) .. L["Off while %s is loaded."]:format(conflict) .. "|r"
	end
	local listen = M:ActiveSources()
	local dbmVersion, bwVersion = M:DBMVersion(), M:BigWigsVersion()
	local using
	if listen.dbm and listen.bigwigs then
		using = L["DBM %s and BigWigs %s"]:format(dbmVersion or "", bwVersion or "")
	elseif listen.dbm then
		using = L["DBM %s"]:format(dbmVersion or "")
	elseif listen.bigwigs then
		using = L["BigWigs %s"]:format(bwVersion or "")
	else
		using = L["no boss mod loaded; the pull countdown still shows"]
	end
	lines[#lines + 1] = L["Timers from: %s"]:format(using)
	lines[#lines + 1] = secondary .. L["Shown now: %d. Secret values skipped this session: %d."]:format(M:CountShown(), M.secretDrops or 0) .. "|r"
	canvas.status:SetText(table.concat(lines, "\n"))
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
M.options = {
	{ type = "preview", label = "Preview", height = 76, create = CreatePreview, update = UpdatePreview,
		desc = "A sample of the timeline in your current look, the boss mod the timers come from and what reached the timeline this session." },

	{ type = "tab", label = "Timeline" },
	{ type = "description", label = "The bar shows only while DBM, BigWigs or a pull countdown has a timer. It shows only what your boss mod publishes." },
	{ type = "header", label = "Test fights" },
	{ type = "execute", label = "Dungeon boss", testSafe = true, func = function() M:StartTest("dungeon") end,
		desc = "Plays a sample dungeon boss on the timeline so you can judge the look and the place. Click again to stop." },
	{ type = "execute", label = "Raid boss", testSafe = true, func = function() M:StartTest("raid") end,
		desc = "Plays a busy sample raid boss: close timers in two lanes and waiting events. Click again to stop." },
	{ type = "execute", label = "Pull and break", testSafe = true, func = function() M:StartTest("pull") end,
		desc = "Plays a pull countdown and a break timer. Click again to stop." },
	{ type = "execute", label = "Move", func = function() E:ToggleMoveMode(true); E:SetMoverGroupFilter("Combat") end,
		desc = "Unlocks the combat frames so you can drag the timeline. The big icon and the bar move together." },
	{ type = "header", label = "Bar" },
	{ type = "select", key = "source", label = "Timers from", values = SOURCES, order = { "auto", "dbm", "bigwigs", "both" },
		desc = "Where the timers come from. Automatic uses the boss mod EldoUI set up, so nothing shows twice. Both shows DBM and BigWigs and drops doubles." },
	{ type = "select", key = "orientation", label = "Direction", values = { horizontal = "Horizontal", vertical = "Vertical" },
		order = { "horizontal", "vertical" },
		desc = "Horizontal fits the layout spot. Vertical has no layout spot: drag it in move mode." },
	{ type = "toggle", key = "reverse", label = "Reverse travel",
		desc = "Icons travel toward the other end: right on a horizontal bar, top on a vertical one." },
	{ type = "range", unit = "s", key = "window", label = "Seconds ahead", min = 10, max = 60, step = 1,
		desc = "How far ahead the bar looks. Events further out wait at the far end." },
	{ type = "toggle", key = "waiting.enabled", label = "Show waiting events",
		desc = "Events beyond the window wait in a small grid at the far end." },
	{ type = "range", key = "waiting.max", label = "Waiting icons", min = 1, max = 6, step = 1, cog = true,
		desc = "How many waiting icons show before a +N count." },
	{ type = "toggle", key = "ticks.enabled", label = "Enable",
		desc = "A thin mark at every tick step, so you can read the distance." },
	{ type = "range", key = "ticks.every", label = "Tick step", min = 2, max = 15, step = 1, cog = true,
		desc = "Seconds between tick marks." },
	{ type = "toggle", key = "ticks.labels", label = "Tick numbers", cog = true,
		desc = "The second count beside the bar at each tick mark, clear of the icons." },
	{ type = "toggle", key = "zones", label = "Warning zones",
		desc = "Tints the last seconds of the bar in the warning and danger colors, so you see at a glance what is close." },
	{ type = "select", key = "backing", label = "Background", values = { strip = "Strip", panel = "Framed", none = "None" },
		order = { "strip", "panel", "none" },
		desc = "Strip is a flat bar. Framed follows your art style (Blizzard border, Classic stone, Forever bronze). None leaves only the track line." },
	{ type = "range", key = "length", label = "Length", min = 160, max = 600, step = 2, cog = true,
		desc = "Bar length along the travel direction. The layouts set it; a longer bar may cover the boss frames." },
	{ type = "range", key = "thickness", label = "Thickness", min = 32, max = 48, step = 1, cog = true,
		desc = "Bar size across the travel direction. Above 40 it leaves the space the layouts keep free." },

	{ type = "tab", label = "Icons" },
	{ type = "range", key = "iconSize", label = "Icon size", min = 16, max = 36, step = 1,
		desc = "Size of the icons on the bar. At most the thickness minus 4." },
	{ type = "select", key = "border", label = "Icon border", values = { bossmod = "Boss mod", accent = "Accent", none = "None" },
		order = { "bossmod", "accent", "none" },
		desc = "Boss mod uses the color DBM or BigWigs gives the timer type. Accent uses your accent color. None keeps the plain border." },
	{ type = "range", key = "numbers", label = "Numbers from", min = 0, max = 30, step = 1,
		zeroText = "Off", desc = "Shows the seconds on each icon from this many seconds." },
	{ type = "toggle", key = "tenths", label = "Tenths in the last second", cog = true,
		desc = "Shows one decimal when less than a second is left." },
	{ type = "range", key = "stages.warn", label = "Warning at", min = 1, max = 10, step = 1,
		desc = "The number turns orange at this many seconds." },
	{ type = "range", key = "stages.bad", label = "Danger at", min = 1, max = 10, step = 1,
		desc = "The number turns red at this many seconds. At most the warning time." },
	{ type = "toggle", key = "lanes", label = "Two lanes",
		desc = "Icons that would touch split into an upper and a lower lane, so none hides another. Off keeps one line at full size. Either way, an icon with no room moves on a little and shows its seconds." },
	{ type = "select", key = "tooltip", label = "Tooltip", values = { off = "Off", anchor = "Above the icon", cursor = "At the cursor" },
		order = { "off", "anchor", "cursor" },
		desc = "Shows the spell's tooltip and the timer type on mouse over. Off keeps the bar click-through." },
	{ type = "select", key = "names", label = "Spell names", values = { off = "Off", side = "Beside the icons" },
		order = { "off", "side" },
		disabled = function() return not Vertical() and L["Vertical bar only"] end,
		desc = "Vertical bar only: the timer's name beside each icon." },
	{ type = "media", mediaKind = "font", key = "font", label = "Font", default = "THEME", defaultLabel = "Theme font", cog = true,
		desc = "Font of the numbers and names. Theme font follows General." },
	{ type = "range", key = "fontSize", label = "Text size", min = 9, max = 16, step = 1, cog = true,
		desc = "Size of the numbers and names." },

	{ type = "tab", label = "Soon" },
	{ type = "toggle", key = "bigIcon.enabled", label = "Big icon",
		desc = "In its last seconds the next event moves off the bar into a big icon at the bar's now end." },
	{ type = "range", unit = "s", key = "bigIcon.seconds", label = "Seconds before", min = 2, max = 10, step = 1, dependsOn = "bigIcon.enabled",
		desc = "How many seconds before the event the big icon appears." },
	{ type = "range", key = "bigIcon.size", label = "Size", min = 40, max = 64, step = 2, cog = true,
		desc = "Size of the big icon. 64 is the space the layouts keep for it." },
	{ type = "range", key = "bigIcon.max", label = "Side by side", min = 1, max = 3, step = 1, cog = true,
		desc = "Big icons shown at once. More than one makes the timeline longer, away from the bar, and may reach the frames next to it." },
	{ type = "toggle", key = "bigIcon.swipe", label = "Swipe", dependsOn = "bigIcon.enabled",
		desc = "A clock swipe over the big icon as the time runs out." },
	{ type = "toggle", key = "bigIcon.glow", label = "Glow", dependsOn = "bigIcon.enabled",
		desc = "A glow on the big icon from the danger time. Its look is on the Glows page (Encounter Timeline)." },
	{ type = "toggle", key = "bigIcon.name", label = "Name", cog = true,
		desc = "The timer's name under the big icon, below the timeline's box." },
	{ type = "header", label = "Countdown sound" },
	{ type = "toggle", key = "sound.countdown", label = "Enable",
		desc = "A tick each second for the soonest event and a final sound at zero. Off by default, because DBM and BigWigs can count down too." },
	{ type = "range", key = "sound.from", label = "Count from", min = 3, max = 10, step = 1, cog = true,
		desc = "Seconds left when the countdown starts." },
	{ type = "media", mediaKind = "sound", key = "sound.tick", channel = "sound.channel", label = "Tick sound", cog = true,
		desc = "Sound for each second. Blizzard's countdown tick by default." },
	{ type = "media", mediaKind = "sound", key = "sound.final", channel = "sound.channel", label = "Final sound", cog = true,
		desc = "Sound at zero. Blizzard's countdown end by default." },
	{ type = "select", key = "sound.channel", label = "Channel", values = CHANNELS, cog = true,
		desc = "Volume channel for the countdown. Default follows General > Sound channel." },
	{ type = "toggle", key = "sound.onlySoon", label = "Only the soonest event", cog = true,
		desc = "Only the next event counts down, so two countdowns never overlap. Off counts down every event." },

	{ type = "tab", label = "Events" },
	{ type = "toggle", key = "events.boss", label = "Boss abilities",
		desc = "Timers DBM or BigWigs shows for the encounter." },
	{ type = "toggle", key = "events.pull", label = "Pull countdown",
		desc = "The group pull countdown, as one icon." },
	{ type = "toggle", key = "events.breaks", label = "Breaks",
		desc = "Break timers started with DBM or BigWigs." },
	{ type = "toggle", key = "events.readyCheck", label = "Ready check",
		desc = "The ready check's time left." },
	{ type = "toggle", key = "events.other", label = "Other timers",
		desc = "Respawn, queue, your own and other addons' bars from the boss mod." },
	{ type = "range", unit = "s", key = "events.minDuration", label = "Hide timers shorter than", min = 0, max = 20, step = 1,
		zeroText = "All", desc = "Hides boss and other timers shorter than this many seconds. The pull and the ready check always show." },
	{ type = "header", label = "Boss mod bars" },
	{ type = "toggle", key = "fadeDBM", label = "Fade DBM's own bars",
		disabled = function() return not M:FadeAvailable() and L["Needs EldoUI's DBM profile (Deadly Boss Mods page)"] end,
		desc = "Makes DBM's bars see-through while the timeline is on, through EldoUI's DBM profile. DBM keeps them, so turning this off brings them back. Needs EldoUI's DBM profile." },
	{ type = "range", percent = true, key = "fadeDBMAlpha", label = "DBM bar opacity", min = 0, max = 0.8, step = 0.05, cog = true,
		zeroText = "Hidden", desc = "How visible DBM's bars stay." },
	{ type = "description", label = "BigWigs: hide its normal bars in BigWigs' own Bars options if you want only the timeline." },
}

table.insert(M.options, { type = "tab", label = "Visibility" })
for _, row in ipairs(E:VisibilityOptions("visibility", { db = function() return M.db end })) do
	table.insert(M.options, row)
end
