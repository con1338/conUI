-- Combat Text options page and style presets.
-- Tabs: General, Scroll areas, Events, Loot and Info, Nameplates, Warnings,
-- Blizzard combat text, Frame feedback (the Presets tab is added by the
-- config window). Rows edit whichever area or event category is picked at
-- the top of their tab (key functions). Rare settings sit behind cogs.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local K = E.CombatKit
local M = E:GetModule("CombatText")

local ID = M.BLIZZARD_ID

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function DB() return M.db end

-- Why EldoUI's scrolling text and plate numbers are off, or nil.
local function ConflictReason()
	local addon, title = M:Conflict()
	if addon then return L["%s is loaded, so EldoUI's scrolling text stays off."]:format(title) end
end

local function EditArea()
	local db = DB()
	local key = db and db.editArea
	if key and db.areas[key] then return key end
	if db then db.editArea = "incoming" end
	return "incoming"
end

local function AreaKey(field)
	return function() return ("areas.%s.%s"):format(EditArea(), field) end
end

local function AreaValues()
	local values = {}
	for _, key in ipairs(M:AreaKeys()) do
		local area = DB().areas[key]
		values[key] = M:AreaTitle(key) .. (area.enabled and "" or (" " .. E:TextHex("secondary") .. L["(off)"] .. "|r"))
	end
	return values
end

local function AreaPathValues()
	local values = {}
	for _, key in ipairs(M:AreaKeys()) do values["areas." .. key] = M:AreaTitle(key) end
	return values
end

local function AreaAnimation()
	local area = DB() and DB().areas[EditArea()]
	return area and area.animation
end

local function ScrollOff()
	return not (DB() and DB().scroll.enabled)
end

local function PlatesOff()
	return not (DB() and DB().plates.enabled)
end

local NUMBERS = { short = L["Short (12.3K)"], grouped = L["Grouped (12,345)"], plain = L["Plain (12345)"] }
local OUTLINES = { NONE = L["None"], OUTLINE = L["Outline"], THICKOUTLINE = L["Thick outline"] }
local ALIGN = { LEFT = L["Left"], CENTER = L["Center"], RIGHT = L["Right"] }
local SIDES = { LEFT = L["Left"], RIGHT = L["Right"] }
local DIRECTIONS = { up = L["Up"], down = L["Down"] }
local CURVES = { left = L["Left"], right = L["Right"] }

local QUALITIES = { [0] = L["Poor"], [1] = L["Common"], [2] = L["Uncommon"], [3] = L["Rare"], [4] = L["Epic"], [5] = L["Legendary"] }
local function QualityValues()
	local values = {}
	for quality = 0, 5 do
		local r, g, b = C_Item.GetItemQualityColor(quality)
		if type(r) == "number" then
			values[quality] = ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, QUALITIES[quality])
		else
			values[quality] = QUALITIES[quality]
		end
	end
	return values
end

---------------------------------------------------------------------------
-- Scroll area preview: three sample lines moving with the picked area's
-- style, sped up to fit the box.
---------------------------------------------------------------------------
local function CreatePreview(canvas)
	if not canvas then return end
	canvas.lines = {}
	for index = 1, 3 do
		local text = canvas:CreateFontString(nil, "OVERLAY")
		E:SetFont(text, E.tokens.size.body)
		canvas.lines[index] = text
	end
	canvas.lines[1]:SetText("-1,234")
	canvas.lines[2]:SetText("+2,468")
	canvas.lines[3]:SetText(L["Parry"])
	-- The colors the player set for damage taken, healing taken and
	-- avoided attacks (Events tab), read again while the preview runs.
	local SAMPLES = { "inDamage", "inHeal", "inAvoid" }
	local function Paint(self)
		local events = M.db and M.db.events
		for index, key in ipairs(SAMPLES) do
			local color = events and events[key] and events[key].color
			if type(color) == "table" and color[1] then
				self.lines[index]:SetTextColor(color[1], color[2], color[3])
			else
				self.lines[index]:SetTextColor(unpack(E.media.text.body))
			end
		end
	end
	canvas.PaintPreview = Paint
	Paint(canvas)
	canvas:HookScript("OnShow", Paint)
	canvas.clock = 0
	canvas.sincePaint = 0
	canvas:SetScript("OnUpdate", function(self, elapsed)
		self.clock = self.clock + (elapsed or 0)
		self.sincePaint = self.sincePaint + (elapsed or 0)
		if self.sincePaint >= 0.25 then
			self.sincePaint = 0
			Paint(self)
		end
		local area = M.db and M.db.areas[EditArea()]
		if not area then return end
		local anim = M.animations[area.animation] or M.animations.straight
		local width, height = self:GetSize()
		if not (width and height) or width <= 0 or height <= 0 then return end
		local fake = { up = area.direction == "up", bend = area.curve == "right" and 1 or -1, lineHeight = 18, shake = false }
		for index, text in ipairs(self.lines) do
			local p = ((self.clock / 2) + (index - 1) / 3) % 1
			fake.slot, fake.side = index - 1, index % 2 == 0 and 1 or -1
			local x, y, alpha = anim.position(p, fake, width, height)
			local point = area.align
			local baseX = point == "LEFT" and 0 or point == "RIGHT" and width or width / 2
			text:ClearAllPoints()
			text:SetPoint(point, self, "BOTTOMLEFT", baseX + (x or 0), y or 0)
			text:SetAlpha(alpha or 1)
		end
	end)
end

---------------------------------------------------------------------------
-- Events tab
---------------------------------------------------------------------------
local EVENT_CATEGORIES = {}
for _, category in ipairs(M.CATEGORIES) do
	if category.key ~= "warn" then EVENT_CATEGORIES[category.key] = category.title end
end

local function Category()
	local db = DB()
	local key = db and db.editCategory
	if key and EVENT_CATEGORIES[key] then return key end
	return "incoming"
end

local function SetCategory(on)
	for key, info in pairs(M.eventInfo) do
		if info.category == Category() then DB().events[key].on = on end
	end
	E:RunOutOfCombat(function() M:OnProfileChanged() end)
	E:RefreshConfig()
end

-- Which client feature an event needs (rows of features the client or
-- your class can't use are never built).
local function Requires(info)
	if info.combo then return function() return M:HasComboPoints() end end
	if info.ready then return function() return M:ReadyServiceAvailable() end end
	if info.warn == "mana" then return function() local kind = UnitPowerType("player") return kind == 0 end end
	if info.warn == "pet" then
		return function() local _, class = UnitClass("player") return class == "HUNTER" or class == "WARLOCK" end
	end
end

local function GameFeedReason(info)
	if not info.ctu then return nil end
	return function()
		if M:GameTextFeedOn() then return nil end
		return L["The game sends these only while Blizzard's own floating combat text is on."]
	end
end

local CODES_HELP = L["How the line reads. Codes filled in by the game: {amount} {name} {spell} {type} {count} {item} {total} {text}."]

local function EventCog(key, info)
	local base = "events." .. key .. "."
	return {
		{ type = "color", key = base .. "color", label = L["Color"], desc = L["Text color of this event."] },
		{ type = "toggle", key = base .. "sticky", label = L["Always sticky"], desc = L["Pops out like a critical hit instead of scrolling."] },
		{ type = "media", mediaKind = "sound", key = base .. "sound", label = L["Sound"], none = true,
			desc = L["Sound played when this event shows (when sounds are on, General tab)."] },
		{ type = "range", key = base .. "fontSize", label = L["Text size"], min = 0, max = 48, step = 1,
			zeroText = "Area", desc = L["Size of this event's text. Area uses the area's size."] },
		{ type = "input", key = base .. "text", label = L["Text"], desc = CODES_HELP },
	}
end

local function EventRows(options)
	for _, key in ipairs(M.eventOrder) do
		local info = M.eventInfo[key]
		if info.category ~= "warn" then
			local hidden = function() return Category() ~= info.category end
			local disabled = function() return ConflictReason() or (GameFeedReason(info) and GameFeedReason(info)()) end
			table.insert(options, { type = "toggle", key = "events." .. key .. ".on", label = info.label, desc = info.desc,
				hidden = hidden, requires = Requires(info), disabled = disabled, cog = EventCog(key, info) })
			table.insert(options, { type = "select", key = "events." .. key .. ".area", label = L["Area"], values = AreaValues,
				hidden = hidden, requires = Requires(info), disabled = disabled, dependsOn = "events." .. key .. ".on",
				desc = L["Scroll area this event shows in."] })
		end
	end
end

---------------------------------------------------------------------------
-- The page
---------------------------------------------------------------------------
local function Build()
	local o = {}
	local function Add(row) o[#o + 1] = row return row end

	-- General ---------------------------------------------------------------
	Add({ type = "tab", label = L["General"] })
	-- The reason is read on every refresh, so it is never empty.
	Add({ type = "description", hidden = function() return not ConflictReason() end, tone = "warning",
		label = function() return (ConflictReason() or "") .. " " .. L["Frame feedback still works."] end })
	Add({ type = "header", label = L["Scrolling text"] })
	Add({ type = "toggle", key = "scroll.enabled", label = L["Scrolling combat text"], disabled = ConflictReason,
		desc = L["EldoUI's own scrolling combat text in the scroll areas: damage and healing you take, notifications, loot and gains."],
		cog = {
			{ type = "range", key = "scroll.speed", label = L["Speed"], min = 40, max = 250, step = 5,
				desc = L["How fast every scroll area plays, in percent. Each area can override it."] },
			{ type = "range", key = "scroll.alpha", label = L["Opacity"], unit = "%", min = 20, max = 100, step = 5,
				desc = L["Opacity of every line, in percent."] },
		} })
	Add({ type = "select", key = "scroll.numbers", label = L["Numbers"], values = NUMBERS, dependsOn = "scroll.enabled",
		desc = L["How numbers are written. Works for numbers the game keeps hidden in a fight too."] })
	Add({ type = "toggle", key = "scroll.icons", label = L["Icons"], dependsOn = "scroll.enabled",
		desc = L["Shows the spell or item icon next to the line when the game names it."] })
	Add({ type = "toggle", key = "scroll.stickyCrits", label = L["Sticky critical hits"], dependsOn = "scroll.enabled",
		desc = L["Critical hits and heals pop out in the middle of their area instead of scrolling."] })
	Add({ type = "toggle", key = "scroll.sounds", label = L["Sounds"], dependsOn = "scroll.enabled",
		desc = L["Plays the sounds you picked for single events (Events tab, the cog of an event)."] })
	Add({ type = "toggle", key = "scroll.schoolColors", label = L["Magic school colors"], dependsOn = "scroll.enabled",
		desc = L["Colors damage by its magic school when the game says which school it was."] })
	Add({ type = "toggle", key = "scroll.merge", label = L["Join similar hits"], dependsOn = "scroll.enabled",
		desc = L["Joins hits of the same kind that land within a moment into one line."],
		cog = {
			{ type = "range", unit = "s", key = "scroll.mergeWindow", label = L["Join window"], min = 0.1, max = 1.5, step = 0.05,
				desc = L["Seconds hits are collected before the joined line shows."] },
			{ type = "toggle", key = "scroll.mergeCount", label = L["Show the count"],
				desc = L["Adds \"\195\1513\" to joined lines. When the game keeps the numbers hidden, the newest number shows with the count."] },
			{ type = "toggle", key = "scroll.countGray", label = L["Gray count"],
				desc = L["Writes the count of joined lines in gray, so the number stands out."] },
			{ type = "range", key = "scroll.minAmount", label = L["Hide small numbers"], min = 0, max = 5000, step = 10,
				zeroText = "All", desc = L["Hides numbers below this. Numbers the game keeps hidden in a fight always show."] },
		} })
	Add({ type = "header", label = L["Text"] })
	Add({ type = "media", mediaKind = "font", key = "scroll.font", label = L["Font"], default = "THEME", defaultLabel = L["Theme font"], dependsOn = "scroll.enabled",
		desc = L["Font of normal lines. Default: the UI font."] })
	Add({ type = "range", key = "scroll.fontSize", label = L["Size"], min = 8, max = 40, step = 1, dependsOn = "scroll.enabled",
		desc = L["Size of normal lines."] })
	Add({ type = "media", mediaKind = "font", key = "scroll.critFont", label = L["Sticky font"], default = "THEME", defaultLabel = L["Theme font"], dependsOn = "scroll.enabled",
		desc = L["Font of critical hits and other sticky lines. Default: the UI font."] })
	Add({ type = "range", key = "scroll.critFontSize", label = L["Sticky size"], min = 10, max = 60, step = 1, dependsOn = "scroll.enabled",
		desc = L["Size of critical hits and other sticky lines."] })
	Add({ type = "select", key = "scroll.outline", label = L["Outline"], values = OUTLINES, dependsOn = "scroll.enabled",
		desc = L["Outline of the text. An outline keeps it readable over the world."] })
	Add({ type = "toggle", key = "scroll.shadow", label = L["Text shadow"], dependsOn = "scroll.enabled",
		desc = L["A soft shadow under every line, on top of the outline."] })
	Add({ type = "toggle", key = "scroll.flash", label = L["Flash big lines"], dependsOn = "scroll.enabled",
		desc = L["Critical hits and other sticky lines start white and turn to their color."] })
	Add({ type = "header", label = L["Try it"] })
	Add({ type = "execute", label = L["Test"], disabled = function() return ConflictReason() or (InCombatLockdown() and L["Out of combat only."]) end,
		desc = L["Shows a sample line in every scroll area and on your target's nameplate. Out of combat only."],
		func = function() M:Test() end })
	Add({ type = "execute", label = L["Move areas"], disabled = function() return ConflictReason() or (InCombatLockdown() and L["Out of combat only."]) end,
		desc = L["Unlocks only the scroll areas, each with sample lines in its own look and a bar where new lines start. Drag a box to move it, its corner to resize it; right-click turns it on or off."],
		func = function() M:MoveAreas() end })

	-- Scroll areas ------------------------------------------------------------
	Add({ type = "tab", label = L["Scroll areas"] })
	Add({ type = "preview", label = L["Preview"], height = 120, create = CreatePreview, update = function() end,
		desc = L["The picked area's style, played in a loop."] })
	Add({ type = "select", key = "editArea", label = L["Area"], values = AreaValues,
		desc = L["The scroll area the rows below change."] })
	Add({ type = "execute", label = L["Move this area"], disabled = function() return ConflictReason() or (InCombatLockdown() and L["Out of combat only."]) end,
		desc = L["Unlocks only this area, with sample lines and its start edge marked, so you can drag or resize it."],
		func = function() M:MoveAreas(EditArea()) end })
	Add({ type = "execute", label = L["Reset every area"], disabled = function() return InCombatLockdown() and L["Out of combat only."] end,
		desc = L["Puts every scroll area back where your layout places it. Sizes and looks stay."],
		func = function() M:ResetAreaPositions() end })
	for _, row in ipairs(E:CopySettingsOptions({ path = function() return "areas." .. EditArea() end,
		values = AreaPathValues, keep = { "enabled", "title" },
		desc = L["Copies another area's look onto this one, with a preview of what changes first. Its name, on/off switch and position stay."] })) do Add(row) end
	Add({ type = "toggle", key = AreaKey("enabled"), label = L["Show this area"], desc = L["Shows this scroll area. Its events show nowhere while it is off."] })
	Add({ type = "input", key = AreaKey("title"), label = L["Name"], desc = L["Name of the area in lists and on its mover."] })
	Add({ type = "range", key = AreaKey("width"), label = L["Width"], min = 60, max = 800, step = 2, desc = L["Width of the area box. Lines move inside it."] })
	Add({ type = "range", key = AreaKey("height"), label = L["Height"], min = 30, max = 600, step = 2, desc = L["Height of the area box. Lines move inside it."] })
	Add({ type = "select", key = AreaKey("animation"), label = L["Animation"], values = function() return M:AnimationValues("scroll") end,
		desc = L["How normal lines move: straight, arc, angled, fountain, or stacked in place."] })
	Add({ type = "select", key = AreaKey("direction"), label = L["Direction"], values = DIRECTIONS,
		desc = L["Which way lines move, or grow when stacked. Down starts new lines at the top of the box and up at the bottom, so this moves where text appears; Move this area shows the edge."] })
	Add({ type = "select", key = AreaKey("curve"), label = L["Bend"], values = CURVES,
		hidden = function() local anim = AreaAnimation() return anim ~= "arc" and anim ~= "angled" end,
		desc = L["Arc and angled styles: which side lines bend to."] })
	Add({ type = "select", key = AreaKey("sticky"), label = L["Sticky lines"], values = function() return M:AnimationValues("sticky") end,
		desc = L["How critical hits and other sticky lines appear."],
		cog = { { type = "toggle", key = AreaKey("shake"), label = L["Shake"], desc = L["Sticky lines shake briefly when they pop."] } } })
	Add({ type = "select", key = AreaKey("align"), label = L["Text align"], values = ALIGN, desc = L["Which side of the area the text lines up on."] })
	Add({ type = "select", key = AreaKey("iconSide"), label = L["Icon side"], values = SIDES, desc = L["Where the icon sits next to the text."] })
	Add({ type = "toggle", key = AreaKey("hideInGroup"), label = L["Hide in groups"], desc = L["Hides this area while you are in a party or raid."] })
	Add({ type = "cog", label = L["More area settings"], desc = L["Speed, line limits and fonts of this area."], options = {
		{ type = "range", key = AreaKey("speed"), label = L["Speed"], min = 0, max = 250, step = 5,
			zeroText = "General", desc = L["Speed of this area in percent. General uses the general speed."] },
		{ type = "range", key = AreaKey("maxLines"), label = L["Most lines"], min = 1, max = 30, step = 1,
			desc = L["Most lines on screen at once; the oldest goes first."] },
		{ type = "range", key = AreaKey("rate"), label = L["Lines per second"], min = 1, max = 30, step = 1,
			desc = L["Most new lines a second. Extra lines of the same kind are joined into the newest one."] },
		{ type = "media", mediaKind = "font", key = AreaKey("font"), label = L["Font"],
			desc = L["Font of this area. Default: the general font."] },
		{ type = "range", key = AreaKey("fontSize"), label = L["Size"], min = 0, max = 40, step = 1,
			zeroText = "General", desc = L["Size of normal lines in this area. General uses the general size."] },
		{ type = "range", key = AreaKey("critFontSize"), label = L["Sticky size"], min = 0, max = 60, step = 1,
			zeroText = "General", desc = L["Size of sticky lines in this area. General uses the general size."] },
	} })
	Add({ type = "execute", label = L["Add area"], hidden = function() return #M:AreaKeys() >= #M.AREA_KEYS + M.CUSTOM_MAX end,
		desc = L["Adds a scroll area of your own (up to four), with its own mover. Send events to it on the Events tab."],
		func = function()
			if M:AddCustomArea() then
				E:RunOutOfCombat(function() M:OnProfileChanged() end)
				E:RefreshConfig()
			end
		end })
	Add({ type = "execute", label = L["Delete area"], hidden = function() return not EditArea():match("^custom") end,
		desc = L["Deletes this area of your own. Its events go back to their usual area."],
		func = function()
			E:ShowConfirm({ key = "ELDOUI_SCT_DELETE_AREA", title = L["Combat Text"],
				text = L["Delete the scroll area %s? Its events go back to their usual area."]:format(M:AreaTitle(EditArea())),
				accept = YES or L["Yes"], cancel = NO or L["No"], danger = true, onAccept = function()
					M:DeleteCustomArea(EditArea())
					E:RunOutOfCombat(function() M:OnProfileChanged() end)
					E:RefreshConfig()
				end })
		end })

	-- Events --------------------------------------------------------------------
	Add({ type = "tab", label = L["Events"] })
	Add({ type = "select", key = "editCategory", label = L["Show events of"], values = EVENT_CATEGORIES,
		desc = L["The group of events listed below."] })
	Add({ type = "execute", label = L["All on"], desc = L["Switches every event of this group on."], func = function() SetCategory(true) end })
	Add({ type = "execute", label = L["All off"], desc = L["Switches every event of this group off."], func = function() SetCategory(false) end })
	Add({ type = "select", key = "moveAllTo", label = L["Move all to"], values = AreaValues,
		desc = L["Sends every event of this group to the picked area."] })
	Add({ type = "header", label = L["Events"] })
	EventRows(o)

	-- Loot and Info ---------------------------------------------------------------
	Add({ type = "tab", label = L["Loot and info"] })
	Add({ type = "description", label = L["Items, money and currencies show only while EldoUI's loot toasts are off, so nothing shows twice. XP, honor and reputation always can."] })
	Add({ type = "toggle", key = "loot.withToasts", label = L["Also with loot toasts"],
		desc = L["Shows loot, money and currency lines even while EldoUI's loot toasts show them too."] })
	Add({ type = "select", key = "loot.minQuality", label = L["Lowest quality"], values = QualityValues,
		desc = L["Lowest item quality that shows."] })
	Add({ type = "toggle", key = "loot.questItems", label = L["Quest items always"], desc = L["Always shows quest items, whatever their quality."] })
	Add({ type = "toggle", key = "loot.bagTotal", label = L["Bag total"], desc = L["Adds how many of the item you now carry."] })
	Add({ type = "cog", label = L["Item lists"], desc = L["Items that always or never show."], options = {
		{ type = "input", key = "loot.allow", label = L["Always show"],
			desc = L["Item names or IDs, separated by commas, that always show."] },
		{ type = "input", key = "loot.exclude", label = L["Never show"],
			desc = L["Item names or IDs, separated by commas, that never show."] },
	} })

	-- Nameplates ------------------------------------------------------------------
	Add({ type = "tab", label = L["Nameplates"] })
	Add({ type = "description", label = L["Numbers rise off an enemy's nameplate when it is hit, by you or anyone else: the game doesn't say who hit."] })
	Add({ type = "description", hidden = function() local np = E:GetModule("Nameplates") return np and np.active end,
		label = L["EldoUI's Nameplates module is off: the numbers hang on Blizzard's plates."] })
	Add({ type = "toggle", key = "plates.enabled", label = L["Hits on enemy plates"], disabled = ConflictReason,
		desc = L["Numbers on the enemy's nameplate when it is hit. Every hit the enemy takes, not only yours."],
		cog = {
			{ type = "range", key = "plates.critScale", label = L["Critical size"], unit = "%", min = 100, max = 250, step = 5,
				desc = L["Size of critical hits, in percent of normal."] },
			{ type = "range", key = "plates.offsetY", label = L["Gap"], min = -20, max = 60, step = 1,
				desc = L["Gap between the plate and its numbers."] },
			{ type = "range", key = "plates.maxPerPlate", label = L["Most lines per plate"], min = 1, max = 10, step = 1,
				desc = L["Most numbers on one plate at once; the oldest goes first."] },
			{ type = "toggle", key = "plates.followPlate", label = L["Follow the plate"],
				desc = L["Numbers fade and scale with EldoUI's plate (non-target fade, target scale)."] },
		} })
	Add({ type = "select", key = "plates.units", label = L["Which plates"], dependsOn = "plates.enabled",
		values = { target = L["Your target only"], all = L["Every enemy plate"] },
		desc = L["Numbers on your target's plate only, or on every enemy plate."] })
	Add({ type = "toggle", key = "plates.inGroup", label = L["In groups too"], dependsOn = "plates.enabled",
		desc = L["Also shows plate numbers in a party or raid, where they include your group's hits."] })
	Add({ type = "select", key = "plates.style", label = L["Animation"], dependsOn = "plates.enabled",
		values = function() return M:AnimationValues("plate") end, desc = L["How plate numbers move."] })
	Add({ type = "range", key = "plates.fontSize", label = L["Size"], min = 8, max = 40, step = 1, dependsOn = "plates.enabled",
		desc = L["Size of plate numbers."] })
	Add({ type = "media", mediaKind = "font", key = "plates.font", label = L["Font"], default = "THEME", defaultLabel = L["Theme font"], dependsOn = "plates.enabled",
		desc = L["Font of plate numbers. Default: the UI font."] })
	Add({ type = "select", key = "plates.outline", label = L["Outline"], values = OUTLINES, dependsOn = "plates.enabled",
		desc = L["Outline of the text. An outline keeps it readable over the world."] })
	Add({ type = "toggle", key = "plates.shadow", label = L["Text shadow"], dependsOn = "plates.enabled",
		desc = L["A soft shadow under every number, on top of the outline."] })
	Add({ type = "toggle", key = "plates.flash", label = L["Flash critical hits"], dependsOn = "plates.enabled",
		desc = L["Critical hits start white and turn to their color."] })
	Add({ type = "toggle", key = "plates.words", label = L["Dodge, parry, miss"], dependsOn = "plates.enabled",
		desc = L["Shows Dodge, Parry, Miss and similar words on the plate."] })
	Add({ type = "toggle", key = "plates.heals", label = L["Heals"], dependsOn = "plates.enabled",
		desc = L["Shows heals the enemy receives."] })
	Add({ type = "select", key = "plates.colorMode", label = L["Color by"], dependsOn = "plates.enabled",
		values = { school = L["By magic school"], warm = L["Ivory, golden critical hits"], white = L["All white"], accent = L["Accent color"] },
		desc = L["How plate numbers are colored. School colors need the game to say the school."] })
	Add({ type = "header", label = L["Blizzard's numbers over enemies"] })
	Add({ type = "description", label = L["Blizzard's own damage and healing numbers over targets: your own hits, from the game."] })
	-- One owner for the numbers over enemies: what happens now, in one line.
	Add({ type = "description", hidden = function() return not M:PlatesOwnWorldNumbers() end,
		label = L["Hit numbers on plates are on, so Blizzard's damage numbers left at \"Blizzard setting\" stay off: one number per hit."] })
	Add({ type = "description", tone = "warning", hidden = function() return not M:WorldNumbersTwice() or E:BlizzardAllowed(ID) end,
		label = L["Blizzard's damage numbers are on too, so each hit shows twice. Turn on \"Let EldoUI change this\" on the Blizzard combat text tab."] })
	for _, message in ipairs(M.BLIZZARD_MESSAGES) do
		if message.world then
			local desc = E.Key("Blizzard's option %s. \"Blizzard setting\" leaves it as you set it in the game's options.")
			if message.plateOwned then
				desc = E.Key("Blizzard's option %s. \"Blizzard setting\" follows the game's options, but hides it while hit numbers on plates are on, so a hit shows once.")
			end
			Add({ type = "select", key = "blizzard.messages." .. message.cvar, label = message.label,
				values = { blizzard = L["Blizzard setting"], on = L["Show"], off = L["Hide"] },
				requires = function() return M.KnownCVar(message.cvar) end,
				disabled = function()
					if M:Conflict() then return ConflictReason() end
					if not E:BlizzardAllowed(ID) then return L["Turn on \"Let EldoUI change this\" on the Blizzard combat text tab first."] end
					if E:BlizzardState(ID).hide then return L["Blizzard's floating combat text is hidden (Blizzard combat text tab)."] end
				end,
				desc = desc, descFill = message.cvar })
		end
	end

	-- Warnings --------------------------------------------------------------------
	Add({ type = "tab", label = L["Warnings"] })
	Add({ type = "description", label = L["A line that shows while a value is low. The game works out when; EldoUI only draws the line. No sound. Off by default."] })
	local WARN = { { "lowHealth", "health" }, { "lowMana", "mana" }, { "lowPet", "pet" } }
	for _, entry in ipairs(WARN) do
		local key, field = entry[1], entry[2]
		local info = M.eventInfo[key]
		Add({ type = "toggle", key = "events." .. key .. ".on", label = info.label, desc = info.desc, requires = Requires(info),
			disabled = ConflictReason, cog = EventCog(key, info) })
		Add({ type = "range", key = "warn." .. field, label = L["Below"], unit = "%", min = 5, max = 80, step = 1,
			requires = Requires(info), dependsOn = "events." .. key .. ".on", desc = L["The percent the line shows below."] })
	end

	-- Blizzard combat text (moved from Combat HUD) ----------------------------------
	Add({ type = "tab", label = L["Blizzard combat text"] })
	K.SwitchOptions(o, ID, {
		skin = L["Combat text in the theme font (or the font below)."],
		move = L["Scroll direction of your own combat text."],
		hide = L["Switch Blizzard's floating combat text off: the text around your character and the numbers over enemies."],
		replace = L["EldoUI's scrolling text instead of Blizzard's text around your character, while EldoUI's is on. Your damage numbers over enemies stay."],
	})
	for _, row in ipairs(o) do
		if type(row.key) == "string" and row.key:find("^blizz%.") then row.disabled = function() return M:Conflict() and ConflictReason() end end
	end
	Add({ type = "description", hidden = function() return not M:Conflict() end, tone = "warning",
		label = function() return L["%s sets Blizzard's combat text options itself, so EldoUI leaves them alone."]:format(select(2, M:Conflict()) or "") end })
	Add({ type = "description", label = L["Blizzard's own combat text options. \"Blizzard setting\" keeps your value from Blizzard's options; Blizzard default puts your values back."] })
	local function NotSkin() return not E:BlizzardAllowed(ID, "skin") end
	local function NotMove() return not E:BlizzardAllowed(ID, "move") end
	local function Off() return not E:BlizzardAllowed(ID) or E:BlizzardState(ID).hide end
	Add({ type = "header", label = L["Text"], hidden = NotSkin })
	Add({ type = "media", mediaKind = "font", default = "THEME", defaultLabel = L["Theme font"], key = "blizzard.font", label = L["Font"], hidden = NotSkin,
		desc = L["Font of Blizzard's combat text around your character."] })
	Add({ type = "range", key = "blizzard.fontSize", label = L["Size"], min = 0, max = 40, step = 1, hidden = NotSkin,
		zeroText = "Game", desc = L["Font size of Blizzard's combat text. Game keeps Blizzard's size."] })
	Add({ type = "select", key = "blizzard.outline", label = L["Outline"], values = OUTLINES, hidden = NotSkin,
		desc = L["Outline of Blizzard's combat text."] })
	Add({ type = "toggle", key = "blizzard.worldFont", label = L["Numbers over targets too"], hidden = NotSkin, reload = true,
		desc = L["Uses the same font for the damage and healing numbers over targets. The game reads it when you log in, so it shows after a relog."] })
	Add({ type = "header", label = L["Direction"], hidden = NotMove })
	Add({ type = "select", key = "blizzard.direction", label = L["Scroll direction"], hidden = NotMove,
		values = { blizzard = L["Blizzard setting"], ["1"] = L["Up"], ["2"] = L["Down"], ["3"] = L["Arc"] },
		desc = L["How Blizzard's combat text around your character moves (Blizzard's option floatingCombatTextFloatMode)."] })
	Add({ type = "header", label = L["Messages"], hidden = Off })
	for _, message in ipairs(M.BLIZZARD_MESSAGES) do
		if not message.world then
			Add({ type = "select", key = "blizzard.messages." .. message.cvar, label = message.label,
				values = { blizzard = L["Blizzard setting"], on = L["Show"], off = L["Hide"] },
				hidden = Off, disabled = function() return M:Conflict() and ConflictReason() end,
				requires = message.optional and function() return M.KnownCVar(message.cvar) end or nil,
				desc = "Blizzard's option %s. \"Blizzard setting\" leaves it as you set it in the game's options.", descFill = message.cvar })
		end
	end

	-- Frame feedback (moved from Combat HUD) -----------------------------------------
	Add({ type = "tab", label = L["Frame feedback"] })
	local function FeedbackOff() return not (M.db and M.db.feedback and M.db.feedback.enabled) end
	local function NotCustom() return FeedbackOff() or M.db.feedback.colorMode ~= "custom" end
	Add({ type = "description", label = L["Numbers and words over EldoUI's unit frames when the unit is hit, healed, dodges, parries, misses or is immune."] })
	Add({ type = "toggle", key = "feedback.enabled", label = L["Frame feedback"], desc = L["Short-lived combat text over EldoUI's player, target, pet and focus frames."] })
	Add({ type = "header", label = L["Show on"], hidden = FeedbackOff })
	Add({ type = "toggle", key = "feedback.units.player", label = L["Player"], hidden = FeedbackOff, desc = L["Text over your own frame. Your scrolling combat text already shows these hits."] })
	Add({ type = "toggle", key = "feedback.units.target", label = L["Target"], hidden = FeedbackOff, desc = L["Text over your target's frame."] })
	Add({ type = "toggle", key = "feedback.units.pet", label = L["Pet"], hidden = FeedbackOff, desc = L["Text over your pet's frame."] })
	Add({ type = "toggle", key = "feedback.units.focus", label = L["Focus"], hidden = FeedbackOff, desc = L["Text over your focus's frame."] })
	Add({ type = "toggle", key = "feedback.energize", label = L["Resource gains"], hidden = FeedbackOff,
		desc = L["Also show mana, rage and energy gains, in the mana color."] })
	Add({ type = "header", label = L["Look"], hidden = FeedbackOff })
	Add({ type = "range", key = "feedback.fontSize", label = L["Text size"], min = 10, max = 32, step = 1, hidden = FeedbackOff,
		desc = L["Size of the feedback text."] })
	Add({ type = "media", mediaKind = "font", default = "THEME", defaultLabel = L["Theme font"], key = "feedback.font", label = L["Font"], hidden = FeedbackOff, desc = L["Font of the feedback text."] })
	Add({ type = "select", key = "feedback.position", label = L["Position"], hidden = FeedbackOff,
		values = { center = L["Center of the frame"], portrait = L["Portrait"], health = L["Health bar"] },
		desc = L["Where on the frame the text shows. Portrait falls back to the center when the frame has no portrait."] })
	Add({ type = "range", unit = "s", key = "feedback.hold", label = L["Hold time"], min = 0.5, max = 3, step = 0.1, hidden = FeedbackOff,
		desc = L["Seconds the text stays fully visible before it fades."] })
	Add({ type = "select", key = "feedback.colorMode", label = L["Color by"], hidden = FeedbackOff,
		values = { type = L["By type"], white = L["All white"], custom = L["Custom"] },
		desc = L["How the text is colored. By type: damage red, healing green, misses white."] })
	Add({ type = "color", key = "feedback.damageColor", label = L["Damage"], hidden = NotCustom, desc = L["Color of damage numbers."] })
	Add({ type = "color", key = "feedback.healColor", label = L["Healing"], hidden = NotCustom, desc = L["Color of healing numbers."] })
	Add({ type = "color", key = "feedback.missColor", label = L["Words"], hidden = NotCustom, desc = L["Color of dodge, parry, miss and other words."] })
	return o
end

M.options = Build

-- "Move all to": the picked area takes every event of the listed group.
M.defaults.moveAllTo = ""
function M:ApplyMoveAll()
	local target = self.db.moveAllTo
	if target == "" or not self.db.areas[target] then return end
	self.db.moveAllTo = ""
	for key, info in pairs(self.eventInfo) do
		if info.category == Category() and info.category ~= "warn" then self.db.events[key].area = target end
	end
end

---------------------------------------------------------------------------
-- Style presets: looks only (fonts, sizes, animations, which areas show).
-- Layouts own the positions, and the direction lines travel in belongs to
-- the position: it decides which edge of the box new lines start from, so
-- a style that turned it would move the text by the box's height.
---------------------------------------------------------------------------
E:RegisterStyles("CombatText", {
	{ key = "Clean", title = L["Clean"], desc = L["Theme font, straight lines, quiet notifications."],
		settings = {
			scroll = { font = "THEME", critFont = "THEME", fontSize = 16, critFontSize = 22, icons = true, merge = true, schoolColors = true },
			areas = {
				incoming = { animation = "straight", sticky = "pop", shake = false },
				target = { enabled = false, animation = "straight" },
				notify = { animation = "straight" },
				static = { animation = "stack" },
			},
			events = { buff = { on = false }, debuff = { on = false }, fade = { on = false }, energize = { on = false },
				resource = { on = false }, proc = { on = true }, combatIn = { on = true }, combatOut = { on = true }, killingBlow = { on = true } },
		} },
	{ key = "ClassicSCT", title = L["Classic SCT"], desc = L["Big arcing numbers on both sides of your character, the classic scrolling look."],
		settings = {
			scroll = { fontSize = 18, critFontSize = 26, stickyCrits = true },
			areas = {
				incoming = { enabled = true, animation = "arc", curve = "left", sticky = "pop", shake = true },
				target = { enabled = true, animation = "arc", curve = "right", sticky = "pop", shake = true },
			},
		} },
	{ key = "Minimal", title = L["Minimal"], desc = L["Only damage and healing you take, small and fast."],
		settings = {
			scroll = { fontSize = 14, critFontSize = 18, icons = false, speed = 130 },
			areas = {
				incoming = { enabled = true, animation = "straight" },
				target = { enabled = false },
				notify = { enabled = false },
				static = { enabled = false },
			},
		} },
	{ key = "Large", title = L["Large"], desc = L["Bigger text for big screens or sitting back."],
		settings = {
			scroll = { fontSize = 24, critFontSize = 34 },
			plates = { fontSize = 20 },
			areas = { incoming = { height = 325 }, target = { height = 325 }, notify = { height = 125 }, static = { height = 140 } },
		} },
	{ key = "Plates", title = L["Plate focus"], desc = L["Numbers on the enemy's nameplate, a slim incoming lane, no target area."],
		settings = {
			plates = { enabled = true, style = "plateFountain" },
			areas = { target = { enabled = false }, incoming = { width = 140, height = 220 } },
		} },
	-- A look of this fork (review verbesserungen.md, C5): EldoUI's own Anton
	-- font with a thick outline and a shadow, sticky lines that flash and
	-- punch, plain hits ivory and critical hits gold on the plates.
	{ key = "Punchy", title = L["Punchy"], desc = L["Tall bold numbers with a thick outline and a shadow. Critical hits flash white, turn gold and punch out; hits are thrown off the enemy's nameplate."],
		settings = {
			scroll = { font = "Anton", critFont = "Anton", fontSize = 18, critFontSize = 28, outline = "THICKOUTLINE",
				shadow = true, flash = true, countGray = true, schoolColors = true, stickyCrits = true },
			areas = {
				incoming = { animation = "throw", sticky = "punch", shake = true },
				target = { animation = "throw", sticky = "punch", shake = true },
				notify = { animation = "straight", sticky = "punch" },
			},
			plates = { enabled = true, style = "plateThrow", font = "Anton", fontSize = 20, critScale = 155,
				outline = "THICKOUTLINE", shadow = true, flash = true, colorMode = "warm" },
		} },
	{ key = "Blizzlike", title = L["Blizzard-like"], desc = L["Game font and plain colors, straight lines centered over the character."],
		settings = {
			scroll = { font = "Friz Quadrata (Blizzard)", critFont = "Friz Quadrata (Blizzard)", schoolColors = false },
			areas = {
				incoming = { animation = "straight", align = "CENTER" },
				notify = { animation = "stack" },
			},
		} },
})
