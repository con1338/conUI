-- EldoUI Flight Games: Which Spell? A class spell's icon and four names:
-- click the one that belongs to the icon, or press 1 to 4. A right answer
-- scores 100 points and up to 50 more for a quick one. Ten icons a round;
-- the hard level takes all four names from the same class.
-- The names and icons come from the game's own spell book, in the game's
-- language. Written from scratch for EldoUI.
local _, E = ...
local M = E.FlightGames
local Key = E.Key
local L = E.L
local B = M.Board

local WIDTH, HEIGHT = 560, 380
local LIMIT = 12              -- seconds per icon at normal pace
local RIGHT_WAIT, WRONG_WAIT = 1.0, 2.0
local ICON = 92
local BOX_W, BOX_H, GAP = 268, 60, 12
local BOX_TOP = 190
local ROUNDS = 10
local MODES = {
	{ key = "mixed", title = "All classes" },
	{ key = "class", title = "One class", same = true },
}
local KEYS = { ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4 }

-- Spells every class learns early, by spell id, with the English name for
-- a client that gives none.
local CLASSES = {
	{ class = "MAGE", name = "Mage", spells = {
		133, "Fireball",
		116, "Frostbolt",
		5143, "Arcane Missiles",
		118, "Polymorph",
		1953, "Blink",
		122, "Frost Nova",
		1459, "Arcane Intellect",
		2136, "Fire Blast",
		2139, "Counterspell",
		11958, "Ice Block",
		12051, "Evocation",
	} },
	{ class = "WARRIOR", name = "Warrior", spells = {
		78, "Heroic Strike",
		100, "Charge",
		772, "Rend",
		6343, "Thunder Clap",
		6673, "Battle Shout",
		7386, "Sunder Armor",
		5308, "Execute",
		12294, "Mortal Strike",
		2565, "Shield Block",
		355, "Taunt",
		1680, "Whirlwind",
		20252, "Intercept",
		7384, "Overpower",
		1715, "Hamstring",
		871, "Shield Wall",
	} },
	{ class = "PRIEST", name = "Priest", spells = {
		585, "Smite",
		2050, "Lesser Heal",
		1243, "Power Word: Fortitude",
		17, "Power Word: Shield",
		139, "Renew",
		589, "Shadow Word: Pain",
		8092, "Mind Blast",
		8122, "Psychic Scream",
		586, "Fade",
		14914, "Holy Fire",
		605, "Mind Control",
		588, "Inner Fire",
	} },
	{ class = "ROGUE", name = "Rogue", spells = {
		1752, "Sinister Strike",
		2098, "Eviscerate",
		53, "Backstab",
		1784, "Stealth",
		1776, "Gouge",
		2983, "Sprint",
		1766, "Kick",
		6770, "Sap",
		1856, "Vanish",
		408, "Kidney Shot",
		5277, "Evasion",
		1833, "Cheap Shot",
		2094, "Blind",
	} },
	{ class = "HUNTER", name = "Hunter", spells = {
		3044, "Arcane Shot",
		1978, "Serpent Sting",
		1130, "Hunter's Mark",
		13165, "Aspect of the Hawk",
		13163, "Aspect of the Monkey",
		5118, "Aspect of the Cheetah",
		2643, "Multi-Shot",
		5384, "Feign Death",
		1499, "Freezing Trap",
		5116, "Concussive Shot",
		2973, "Raptor Strike",
		136, "Mend Pet",
		1515, "Tame Beast",
	} },
	{ class = "WARLOCK", name = "Warlock", spells = {
		686, "Shadow Bolt",
		348, "Immolate",
		172, "Corruption",
		5782, "Fear",
		1454, "Life Tap",
		689, "Drain Life",
		688, "Summon Imp",
		697, "Summon Voidwalker",
		687, "Demon Skin",
		6789, "Death Coil",
		5676, "Searing Pain",
		755, "Health Funnel",
	} },
	{ class = "DRUID", name = "Druid", spells = {
		5176, "Wrath",
		5185, "Healing Touch",
		1126, "Mark of the Wild",
		774, "Rejuvenation",
		8921, "Moonfire",
		5487, "Bear Form",
		768, "Cat Form",
		339, "Entangling Roots",
		467, "Thorns",
		8936, "Regrowth",
		783, "Travel Form",
		2912, "Starfire",
		2637, "Hibernate",
		20484, "Rebirth",
	} },
	{ class = "PALADIN", name = "Paladin", spells = {
		635, "Holy Light",
		20154, "Seal of Righteousness",
		465, "Devotion Aura",
		19740, "Blessing of Might",
		498, "Divine Protection",
		853, "Hammer of Justice",
		633, "Lay on Hands",
		20271, "Judgement",
		19750, "Flash of Light",
		1022, "Blessing of Protection",
		26573, "Consecration",
		7294, "Retribution Aura",
		1152, "Purify",
	} },
	{ class = "SHAMAN", name = "Shaman", spells = {
		403, "Lightning Bolt",
		8042, "Earth Shock",
		331, "Healing Wave",
		8017, "Rockbiter Weapon",
		324, "Lightning Shield",
		8050, "Flame Shock",
		8056, "Frost Shock",
		8071, "Stoneskin Totem",
		3599, "Searing Totem",
		2645, "Ghost Wolf",
		421, "Chain Lightning",
		370, "Purge",
		8004, "Lesser Healing Wave",
		8075, "Strength of Earth Totem",
	} },
}

local Icons = {}
Icons.__index = Icons
-- What a saved game keeps (the board, the score and the timers).
Icons.saveKeys = { "round", "score", "right", "spell", "choices", "at", "phase", "picked", "left", "gain", "wait", "used" }

local function ModeOf(mode)
	return mode and mode.key and mode or MODES[1]
end

-- The game's own name and icon of a spell, or nil.
local function Info(id, english)
	local spell = C_Spell
	if spell and spell.GetSpellInfo then
		local ok, info = pcall(spell.GetSpellInfo, id)
		if ok and type(info) == "table" and info.iconID then
			return (type(info.name) == "string" and info.name ~= "") and info.name or english, info.iconID
		end
	end
	local legacy = rawget(_G, "GetSpellInfo")
	if legacy then
		local ok, name, _, icon = pcall(legacy, id)
		if ok and icon then return name or english, icon end
	end
end

-- Every spell the client knows: { id, name, icon, class }, built once.
local pool
local function Pool()
	if pool then return pool end
	pool = {}
	for c, class in ipairs(CLASSES) do
		for k = 1, #class.spells, 2 do
			local id, english = class.spells[k], class.spells[k + 1]
			local name, icon = Info(id, english)
			if name and icon then pool[#pool + 1] = { id = id, name = name, icon = icon, class = c } end
		end
	end
	return pool
end
Icons.Pool = function() pool = nil return Pool() end

local function Find(id)
	for _, entry in ipairs(Pool()) do
		if entry.id == id then return entry end
	end
end

local function ClassName(c)
	local class = CLASSES[c]
	local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	return names and names[class.class] or class.name
end

local function New(host, mode)
	local game = setmetatable({ host = host, mode = ModeOf(mode) }, Icons)
	local area = host.area
	game.progress = B.Label(area, E.tokens.size.small, "secondary", "LEFT")
	game.progress:SetPoint("TOPLEFT", area, "TOPLEFT", 12, -8)
	game.track = B.Sprite(area, WIDTH - 24, 4, "BORDER")
	B.Place(game.track, 12, 26, area)
	game.bar = B.Sprite(area, WIDTH - 24, 4, "ARTWORK")
	B.Place(game.bar, 12, 26, area)
	local ix, iy = (WIDTH - ICON) / 2, 46
	game.glow = B.Sprite(area, ICON + 40, ICON + 40, "BACKGROUND")
	B.Place(game.glow, ix - 20, iy - 20, area)
	game.icon = B.Sprite(area, ICON, ICON, "ARTWORK")
	B.Place(game.icon, ix, iy, area)
	game.ring = B.Sprite(area, ICON + 14, ICON + 14, "OVERLAY")
	B.Place(game.ring, ix - 7, iy - 7, area)
	game.class = B.Label(area, E.tokens.size.small, "secondary")
	game.class:SetPoint("TOP", area, "TOPLEFT", WIDTH / 2, -(iy + ICON + 14))
	game.boxes = {}
	for i = 1, 4 do
		local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
		local x = (WIDTH - BOX_W * 2 - GAP) / 2 + col * (BOX_W + GAP)
		local y = BOX_TOP + row * (BOX_H + GAP)
		local box = { x = x, y = y }
		box.fill = B.Slab(area, BOX_W, BOX_H, "BORDER")
		box.fill:Place(x, y)
		box.number = B.Label(area, E.tokens.size.small, "dim", "LEFT")
		box.number:SetPoint("TOPLEFT", area, "TOPLEFT", x + 8, -(y + 6))
		box.number:SetText(i)
		box.text = B.Label(area, E.tokens.size.body, "body")
		box.text:SetWidth(BOX_W - 36)
		box.text:SetPoint("CENTER", area, "TOPLEFT", x + BOX_W / 2 + 6, -(y + BOX_H / 2))
		game.boxes[i] = box
	end
	game.note = B.Label(area, E.tokens.size.body, "body")
	game.note:SetWidth(WIDTH - 24)
	game.note:SetPoint("BOTTOM", area, "TOPLEFT", WIDTH / 2, -(HEIGHT - 8))
	game.fx = B.Effects(area)
	return game
end

function Icons:Limit()
	return LIMIT / math.max(0.5, self.host.Pace())
end

function Icons:Start()
	self.round, self.score, self.right, self.used = 0, 0, 0, {}
	self.spell, self.choices = nil, nil
	self.host.Score(0)
	self.fx:Clear()
	if #Pool() < 8 then
		self.phase = "none"
		self:Draw()
		return
	end
	self:Next()
end

-- Four names: the icon's own and three others with names of their own
-- (from the same class on the hard level).
function Icons:Next()
	local random, all = self.host.Random, Pool()
	self.round = self.round + 1
	local open = {}
	for _, entry in ipairs(all) do
		if not self.used[entry.id] then open[#open + 1] = entry end
	end
	if #open == 0 then
		self.used, open = {}, all
	end
	local spell = open[random(#open)]
	self.used[spell.id] = true
	local others, names = {}, { [spell.name] = true }
	for _, entry in ipairs(all) do
		if not names[entry.name] and (not self.mode.same or entry.class == spell.class) then others[#others + 1] = entry end
	end
	if #others < 3 then
		others = {}
		for _, entry in ipairs(all) do
			if not names[entry.name] then others[#others + 1] = entry end
		end
	end
	local choices = { spell.id }
	while #choices < 4 and #others > 0 do
		local k = random(#others)
		local entry = table.remove(others, k)
		if not names[entry.name] then
			names[entry.name] = true
			choices[#choices + 1] = entry.id
		end
	end
	for i = #choices, 2, -1 do
		local j = random(i)
		choices[i], choices[j] = choices[j], choices[i]
	end
	self.spell, self.choices = spell.id, choices
	for i, id in ipairs(choices) do
		if id == spell.id then self.at = i end
	end
	self.picked, self.gain, self.phase = nil, nil, "ask"
	self.left = self:Limit()
	self:Draw()
end

function Icons:Answer(choice)
	if self.phase ~= "ask" then return end
	self.picked = choice or 0
	self.phase = "show"
	local cx, cy = WIDTH / 2, 46 + ICON / 2
	if choice == self.at then
		self.right = self.right + 1
		self.gain = 100 + math.floor(50 * math.max(0, self.left) / self:Limit() + 0.5)
		self.score = self.score + self.gain
		self.host.Score(self.score)
		self.host.Sound("point")
		self.fx:Burst(cx, cy, self.host.Color("good"), ICON * 1.6, 0.5)
		self.fx:Sparks(cx, cy, self.host.Color("gold"), 14, 160)
		self.fx:Float(cx, cy - ICON / 2, "+" .. self.gain, self.host.Color("gold"), E.tokens.size.cardTitle)
		self.wait = RIGHT_WAIT
	else
		self.host.Sound("turn")
		self.fx:Burst(cx, cy, self.host.Color("bad"), ICON * 1.3, 0.4)
		self.wait = WRONG_WAIT
	end
	self:Draw()
end

function Icons:Advance()
	if self.phase ~= "show" then return end
	if self.round >= ROUNDS then
		self.phase = "done"
		self:Draw()
		self.host.Over(true)
		return
	end
	self:Next()
end

function Icons:Loaded()
	local spell = self.spell and Find(self.spell)
	local fine = spell and type(self.choices) == "table" and #self.choices >= 2
	if fine then
		for _, id in ipairs(self.choices) do
			if not Find(id) then fine = false end
		end
	end
	if not fine then
		-- The spell book changed since the save: a new icon, same round.
		self.round = math.max(0, (tonumber(self.round) or 1) - 1)
		self.used = type(self.used) == "table" and self.used or {}
		if #Pool() < 8 then self.phase = "none" return end
		self:Next()
	end
end

function Icons:Update(dt)
	self.fx:Update(dt)
	if self.phase == "ask" then
		self.left = self.left - dt
		if self.left <= 0 then
			self.left = 0
			self:Answer(nil)
		else
			self:DrawTimer()
		end
	elseif self.phase == "show" then
		self.wait = self.wait - dt
		if self.wait <= 0 then self:Advance() end
	end
end

function Icons:Key(key)
	local choice = KEYS[key]
	if choice then
		self:Answer(choice)
		return true
	end
	if (key == "SPACE" or key == "ENTER") and self.phase == "show" then
		self:Advance()
		return true
	end
	return false
end

function Icons:Press(button, x, y)
	if button ~= "LeftButton" then return end
	if self.phase == "show" then
		self:Advance()
		return
	end
	if not (x and y) then return end
	for i, box in ipairs(self.boxes) do
		if x >= box.x and x <= box.x + BOX_W and y >= box.y and y <= box.y + BOX_H then
			self:Answer(i)
			return
		end
	end
end

function Icons:Summary()
	if not self.round or self.round == 0 then return nil end
	return L["%d of %d right"]:format(self.right or 0, self.round)
end

function Icons:DrawTimer()
	local share = self.phase == "ask" and math.max(0, math.min(1, (self.left or 0) / self:Limit())) or 0
	self.bar:SetWidth(math.max(1, (WIDTH - 24) * share))
	local color = share > 0.5 and self.host.Color("accent") or (share > 0.2 and self.host.Color("warn") or self.host.Color("bad"))
	B.Fill(self.bar, color, 0.9)
end

function Icons:Draw()
	local color = self.host.Color
	B.Fill(self.track, color("dim"), 0.25)
	local spell = self.spell and Find(self.spell)
	if self.phase == "none" or not spell then
		self.progress:SetText("")
		self.icon:Hide()
		self.ring:Hide()
		self.glow:Hide()
		self.class:SetText("")
		for _, box in ipairs(self.boxes) do
			box.text:SetText("")
			box.fill:Paint(color("secondary"), 0.2)
		end
		self.note:SetText(self.phase == "none" and L["The spell book is not available here."] or "")
		self.note:SetTextColor(unpack(color("secondary")))
		self:DrawTimer()
		return
	end
	self.progress:SetText(L["Spell %d of %d"]:format(self.round, ROUNDS))
	self.icon:SetTexture(spell.icon)
	E:TrimIcon(self.icon)
	self.icon:Show()
	local showing = self.phase ~= "ask"
	local right = showing and self.picked == self.at
	B.Art(self.ring, "Ring", showing and (right and color("good") or color("bad")) or color("gold"), 0.9)
	self.ring:Show()
	B.Art(self.glow, "Ring", color("accent"), 0.18)
	self.glow:Show()
	self.class:SetText(showing and ClassName(spell.class) or "")
	for i, box in ipairs(self.boxes) do
		local entry = self.choices[i] and Find(self.choices[i])
		box.text:SetText(entry and entry.name or "")
		box.fill:SetShown(entry ~= nil)
		local c, alpha = color("secondary"), 0.3
		if showing and i == self.at then
			c, alpha = color("good"), 0.55
		elseif showing and i == self.picked then
			c, alpha = color("bad"), 0.55
		end
		box.fill:Paint(c, alpha)
	end
	if not showing then
		self.note:SetText("")
	elseif right then
		self.note:SetText(L["Right! +%d"]:format(self.gain or 0))
		self.note:SetTextColor(unpack(color("good")))
	else
		local text = self.picked == 0 and L["Time is up. The answer was %s."] or L["Not quite. The answer was %s."]
		self.note:SetText(text:format(spell.name))
		self.note:SetTextColor(unpack(color("bad")))
	end
	self:DrawTimer()
end

M:RegisterGame({
	key = "icons", order = 220, group = "quiz",
	title = "Which Spell?", desc = "A class spell's icon and four names: which one is it?",
	controls = Key("Click a name or press 1 to 4. P: pause."),
	icon = "Interface\\Icons\\INV_Misc_Book_09",
	modes = MODES,
	width = WIDTH, height = HEIGHT,
	New = New,
})
