-- Offline test for Combat Text's Punchy style and the leaner updater
-- (review verbesserungen.md, C5 and E3).
-- Run from the repository root:
--   lua5.1 tools/combattext/test_punchy.lua
-- The player found the combat text plain (15.11.2026) and picked the bold
-- draft: EldoUI's Anton font with a thick outline and a shadow, sticky
-- lines that flash white and punch out, plain hits ivory and critical hits
-- gold on the plates, a quiet "x3". E3: the updater used to set point,
-- scale, alpha and Show on every line every frame.
-- This loads EldoUI/Modules/CombatText/Animations.lua as it is and cuts the
-- other parts out of their files (between fixed markers, so a renamed part
-- makes the test fail instead of testing a stale copy): the defaults
-- (Core.lua), the line text, school colors, shadow, flash and updater
-- (Engine.lua), the plate colors (Plates.lua) and the style list
-- (Options.lua). Around them: frames and font strings that count calls.
-- Checked: the three new motions keep their shape (start size, overshoot,
-- settle, fade, travel), the old ones are still there; a still line costs
-- no widget call after its first frame and the updater never clears points;
-- flashing goes from white to the line's color and stops; the shadow; the
-- gray count; plate colors in the new mode and the old one; Punchy writes
-- only settings that exist, names motions of the right kind and a font
-- EldoUI ships, and every other style keeps the old look.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/combattext/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local DIR = "EldoUI/Modules/CombatText/"
local core = ReadFile(DIR .. "Core.lua")
local engine = ReadFile(DIR .. "Engine.lua")
local plates = ReadFile(DIR .. "Plates.lua")
local options = ReadFile(DIR .. "Options.lua")
local animations = ReadFile(DIR .. "Animations.lua")
local media = ReadFile("EldoUI/Core/Media.lua")

local failures, passed = 0, 0
local function Check(ok, message)
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		print("FAIL: " .. message)
	end
end
local function Near(a, b) return type(a) == "number" and math.abs(a - b) < 1e-6 end

local L = setmetatable({}, { __index = function(_, key) return key end })
local SECRET = {}
local function issecret(value) return value == SECRET end

-- One module table for every part, as in the game.
local M = { defaults = {} }
local E = { L = L, media = { accentColor = { 0.2, 0.6, 1 } } }
function E:GetModule() return M end
E.Key = function(text) return text end

---------------------------------------------------------------------------
-- Defaults (Core.lua)
---------------------------------------------------------------------------
assert(loadstring("local M, L, Key = ...\n" .. Between(core, "local function Area(enabled", "-- State helpers", "Core.lua defaults"),
	"=Core.lua defaults"))(M, L, E.Key)
local defaults = M.defaults
Check(defaults.scroll.shadow == false and defaults.scroll.flash == false and defaults.scroll.countGray == false,
	"the new scroll looks are off by default")
Check(defaults.plates.shadow == false and defaults.plates.flash == false and defaults.plates.outline == "OUTLINE"
	and defaults.plates.font == "THEME", "the new plate looks default to the old plate text")
Check(core:find('"Punchy" }', 1, true) ~= nil, "the module lists the Punchy preset")

---------------------------------------------------------------------------
-- Animations (Animations.lua as it is)
---------------------------------------------------------------------------
assert(loadstring(animations, "=Animations.lua"))("EldoUI", E)
for _, key in ipairs({ "straight", "arc", "angled", "fountain", "stack", "pop", "hold", "rise", "plateFountain", "platePop", "plateStack" }) do
	Check(M.animations[key] ~= nil, "the old motion " .. key .. " is still there")
end
local throw, punch, plateThrow = M.animations.throw, M.animations.punch, M.animations.plateThrow
Check(throw and throw.kind == "scroll", "throw is a scroll motion")
Check(punch and punch.kind == "sticky", "punch is a sticky motion")
Check(plateThrow and plateThrow.kind == "plate" and plateThrow.critDuration > plateThrow.duration,
	"plateThrow is a plate motion and gives critical hits more time")

Check(Near(M.EaseOut(0), 0) and Near(M.EaseOut(1), 1) and M.EaseOut(0.2) > 0.2, "EaseOut starts fast and ends at 1")
local peak = 0
for step = 0, 100 do peak = math.max(peak, M.Overshoot(step / 100)) end
Check(Near(M.Overshoot(0), 0) and Near(M.Overshoot(1), 1) and peak > 1.05 and peak < 1.2, "Overshoot goes a little past 1 and settles")
Check(Near(M.SoftFade(0), 0) and Near(M.SoftFade(0.5), 1) and Near(M.SoftFade(1), 0), "SoftFade fades in, holds, fades out")

do
	local line = { up = true, bend = -1, side = 1, slot = 0, lineHeight = 24, shake = true }
	local _, _, a0, s0 = punch.position(0, line, 160, 260)
	local _, y1, a1, s1 = punch.position(0.12, line, 160, 260)
	local smallest = 2
	for step = 0, 12 do
		local _, _, _, s = punch.position(step / 100, line, 160, 260)
		smallest = math.min(smallest, s)
	end
	Check(Near(s0, 2) and Near(s1, 1), "punch starts at twice the size and is back to normal at 12 %")
	Check(smallest < 1 and smallest > 0.8, "punch goes a little below normal size before it settles")
	Check(Near(a0, 0) and Near(a1, 1) and Near(y1, 130), "punch fades in and sits in the middle of the box")
	local shaken = punch.position(0.01, line, 160, 260)
	line.shake = false
	local still = punch.position(0.01, line, 160, 260)
	Check(shaken ~= 0 and still == 0, "punch shakes only when the area shakes")
	local _, _, aEnd = punch.position(1, line, 160, 260)
	Check(Near(aEnd, 0), "punch is gone at the end")
end

do
	local line = { up = true, bend = -1, side = 1, slot = 0, lineHeight = 24 }
	local x0, y0, _, s0 = throw.position(0, line, 160, 260)
	local _, y5 = throw.position(0.5, line, 160, 260)
	local x1, y1 = throw.position(1, line, 160, 260)
	local _, _, _, s1 = throw.position(0.1, line, 160, 260)
	Check(Near(x0, 0) and math.abs(x1) < 1e-6, "throw starts and ends on the middle line")
	Check(Near(y0, 12) and Near(y1, 248), "throw travels the whole box, edge to edge")
	Check(y5 - y0 > 0.8 * (y1 - y0), "throw covers most of the way in the first half (fast off the mark)")
	Check(Near(s0, 1.3) and Near(s1, 1), "throw starts a little bigger and is normal at 10 %")
	local xm = throw.position(0.3, line, 160, 260)
	Check(xm < 0, "throw bends to the area's side")
end

do
	local line = { side = -1, slot = 0, lineHeight = 22 }
	local top, last = 0, nil
	for step = 0, 100 do
		local _, y = plateThrow.position(step / 100, line, 30, 40)
		top = math.max(top, y)
		last = y
	end
	local x = plateThrow.position(0.5, line, 30, 40)
	Check(x < 0, "plateThrow throws to the line's side")
	Check(top > 30 and last < top, "plateThrow rises fast and sinks a little at the end")
	local _, _, _, s0 = plateThrow.position(0, line, 30, 40)
	Check(Near(s0, 1.25), "a plain plate hit starts a little bigger")
	line.crit, line.shake = true, true
	local cx, cy, _, cs = plateThrow.position(0, line, 30, 40)
	local _, _, _, cs1 = plateThrow.position(0.18, line, 30, 40)
	Check(Near(cs, 2.1) and Near(cs1, 1), "a critical plate hit punches out at 2.1 times the size and settles at 18 %")
	Check(cx ~= 0 and Near(cy, 12), "a critical plate hit shakes and starts above the plate")
end

---------------------------------------------------------------------------
-- Line text, colors, shadow, flash and the updater (Engine.lua)
---------------------------------------------------------------------------
local engineChunk = assert(loadstring(table.concat({
	"local M, E, issecret, active, holders, driver, Release = ...",
	Between(engine, "local CODES = ", "\n", "Engine.lua CODES"),
	Between(engine, "local compiled = {}", "M.RenderLine = Render", "Engine.lua Render"),
	Between(engine, "local SCHOOL_COLORS = {", "local function Outline()", "Engine.lua school colors"),
	Between(engine, "function M.SetTextShadow(text, on, size)", "-- Lay a line out inside its area box", "Engine.lua shadow and flash"),
	Between(engine, "local function Update()", "M.UpdateLines = Update", "Engine.lua updater"),
	"return Render, Update",
}, "\n"), "=Engine.lua parts"))

local function FontString()
	local text = { calls = 0 }
	function text:SetText(value) self.value = value end
	-- The game draws secret values itself; here the format and its values are kept.
	function text:SetFormattedText(fmt, ...) self.value, self.args = fmt, { ... } end
	function text:SetTextColor(r, g, b) self.calls = self.calls + 1; self.r, self.g, self.b = r, g, b end
	function text:SetShadowOffset(x, y) self.sx, self.sy = x, y end
	function text:SetShadowColor(r, g, b, a) self.sr, self.sg, self.sb, self.sa = r, g, b, a end
	return text
end

local function Frame()
	local frame = { calls = {}, shown = false }
	local function Count(name) frame.calls[name] = (frame.calls[name] or 0) + 1 end
	function frame:SetScale() Count("SetScale") end
	function frame:SetPoint() Count("SetPoint") end
	function frame:ClearAllPoints() Count("ClearAllPoints") end
	function frame:SetAlpha() Count("SetAlpha") end
	function frame:Show() Count("Show"); self.shown = true end
	function frame:Hide() Count("Hide"); self.shown = false end
	return frame
end
local function Calls(frame)
	local total = 0
	for _, count in pairs(frame.calls) do total = total + count end
	return total
end

local now = 100
function GetTime() return now end

local active, holders, released = {}, {}, {}
local driver = { Hide = function() end }
local function Release(index) released[#released + 1] = table.remove(active, index) end
M.db = { scroll = { mergeCount = true, countGray = false, numbers = "plain" }, plates = { colorMode = "school" } }
local Render, Update = engineChunk(M, E, issecret, active, holders, driver, Release)

do
	local text = FontString()
	M.SetTextShadow(text, true, 18)
	Check(text.sx == 2 and text.sy == -2 and Near(text.sa, 0.85), "the shadow sits 2 px down right for 18 px text")
	M.SetTextShadow(text, true, 28)
	Check(text.sx == 3 and text.sy == -3, "bigger text gets a deeper shadow")
	M.SetTextShadow(text, false, 28)
	Check(text.sx == 0 and text.sy == 0, "no shadow when it is off")
end

do
	local line = { template = "-{amount}", payload = { amount = 50 }, count = 3, text = FontString() }
	Render(line)
	Check(line.text.value == "-50 \195\1513", "the count reads as before when it is not gray (" .. tostring(line.text.value) .. ")")
	M.db.scroll.countGray = true
	Render(line)
	Check(line.text.value == "-50 |cff9a9a9a\195\1513|r", "the gray count (" .. tostring(line.text.value) .. ")")
	line.count = 1
	Render(line)
	Check(line.text.value == "-50", "a single hit has no count")
	line.payload.amount, line.count = SECRET, 2
	Render(line)
	Check(line.text.value == "-%s |cff9a9a9a\195\151%d|r" and line.text.args[1] == SECRET and line.text.args[2] == 2,
		"a secret amount goes to the game as it is, with the gray count")
end

do
	local holder = { GetSize = function() return 160, 260 end }
	holders.incoming = holder
	local still = { position = function() return 10, 50, 1, 1 end }
	local line = { area = "incoming", t0 = 100, duration = 2, anim = still, alpha = 1, frame = Frame(), text = FontString() }
	active[1] = line
	Update()
	Check(Calls(line.frame) == 4 and line.frame.shown, "the first frame sets scale, point and alpha and shows the line")
	for _ = 1, 10 do
		now = now + 0.016
		Update()
	end
	Check(Calls(line.frame) == 4, "a line that stands still costs no widget call after its first frame (" .. Calls(line.frame) .. ")")
	local moving = { position = function(p) return 0, 20 + p * 200, 1, 1 end }
	local line2 = { area = "incoming", t0 = now, duration = 2, anim = moving, alpha = 1, frame = Frame(), text = FontString() }
	active[2] = line2
	for _ = 1, 10 do
		now = now + 0.016
		Update()
	end
	Check(line2.frame.calls.SetPoint == 10 and line2.frame.calls.SetScale == 1 and line2.frame.calls.SetAlpha == 1,
		"a moving line moves every frame but keeps its scale and alpha")
	Check(not line.frame.calls.ClearAllPoints and not line2.frame.calls.ClearAllPoints, "the updater never clears points")
	local waiting = { area = "incoming", t0 = now + 1, duration = 2, anim = still, alpha = 1, frame = Frame(), text = FontString() }
	waiting.frame.shown = true
	active[3] = waiting
	for _ = 1, 5 do
		now = now + 0.016
		Update()
	end
	Check(waiting.frame.calls.Hide == 1 and not waiting.frame.shown, "a line waiting for its start is hidden once")
	for index = #active, 1, -1 do active[index] = nil end
end

do
	local gold = { 1, 0.82, 0.25 }
	local still = { position = function() return 0, 0, 1, 1 end }
	local line = { area = "incoming", t0 = now, duration = 2, anim = still, alpha = 1, frame = Frame(), text = FontString(),
		flash = true, color = gold }
	active[1] = line
	Update()
	Check(Near(line.text.r, 1) and Near(line.text.g, 1) and Near(line.text.b, 1), "a flashing line starts white")
	now = now + M.FLASH_TIME / 2
	Update()
	Check(line.text.b < 1 and line.text.b > gold[3], "halfway it is between white and its color")
	now = now + M.FLASH_TIME
	Update()
	Check(Near(line.text.r, gold[1]) and Near(line.text.g, gold[2]) and Near(line.text.b, gold[3]) and line.flash == false,
		"after the flash it has its own color and stops flashing")
	local calls = line.text.calls
	now = now + 0.1
	Update()
	Check(line.text.calls == calls, "no color call once the flash is over")
	active[1] = nil
end

---------------------------------------------------------------------------
-- Plate colors (Plates.lua)
---------------------------------------------------------------------------
local Color = assert(loadstring("local M, E = ...\n" .. Between(plates, "local GREEN, GREY = ", "-- One line on the plate of", "Plates.lua colors")
	.. "\nreturn Color", "=Plates.lua colors"))(M, E)
do
	local db = M.db.plates
	db.colorMode = "school"
	Check(Color("damage", { school = 1 }) == M.SCHOOL_COLORS[1], "school mode: a plain hit is still red")
	db.colorMode = "warm"
	local ivory, gold = Color("damage", { school = 1 }), Color("crit", { school = 1 })
	Check(Near(ivory[1], 1) and Near(ivory[2], 0.95) and Near(ivory[3], 0.86), "warm: a plain hit is ivory")
	Check(Near(gold[1], 1) and Near(gold[2], 0.82) and Near(gold[3], 0.25), "warm: a critical hit is gold")
	Check(Color("crit", { school = 4 }) == gold or Near(Color("crit", { school = 4 })[3], 0.25), "warm: a critical spell hit is gold too")
	Check(Color("damage", { school = 4 }) == M.SCHOOL_COLORS[4], "warm: a fire hit keeps the fire color")
	Check(Color("damage", { school = SECRET }) == ivory or Near(Color("damage", { school = SECRET })[3], 0.86),
		"warm: a hit whose school is secret is ivory")
	Check(Color("damage", {}) == ivory, "warm: a hit without a school is ivory")
	Check(Color("heal", {})[2] == 1 and Color("avoid", {})[1] == 0.8, "heals stay green and avoided hits gray")
end

---------------------------------------------------------------------------
-- The style list (Options.lua)
---------------------------------------------------------------------------
local styles
do
	local from = options:find('E:RegisterStyles("CombatText", {', 1, true)
	assert(from, "Options.lua: style list not found")
	local stub = { RegisterStyles = function(_, _, list) styles = list end }
	assert(loadstring("local E, L = ...\n" .. options:sub(from), "=Options.lua styles"))(stub, L)
end
local punchy
for _, style in ipairs(styles) do
	if style.key == "Punchy" then punchy = style end
end
Check(punchy ~= nil and punchy.title == "Punchy" and type(punchy.desc) == "string", "the Punchy style is in the list")

local function Walk(settings, prefix, fn)
	for key, value in pairs(settings) do
		local path = prefix and (prefix .. "." .. key) or key
		if type(value) == "table" then Walk(value, path, fn) else fn(path, value) end
	end
end
local function Get(root, path)
	for part in path:gmatch("[^%.]+") do
		if type(root) ~= "table" then return nil end
		root = root[part]
	end
	return root
end

if punchy then
	Walk(punchy.settings, nil, function(path, value)
		local default = Get(defaults, path)
		Check(default ~= nil and type(default) == type(value), "Punchy writes " .. path .. ", a setting with that type")
	end)
	local s = punchy.settings
	Check(M.animations[s.areas.incoming.animation].kind == "scroll" and M.animations[s.areas.target.animation].kind == "scroll",
		"Punchy's scroll motions are scroll motions")
	Check(M.animations[s.areas.incoming.sticky].kind == "sticky" and M.animations[s.areas.notify.sticky].kind == "sticky",
		"Punchy's sticky motions are sticky motions")
	Check(M.animations[s.plates.style].kind == "plate", "Punchy's plate motion is a plate motion")
	for _, font in ipairs({ s.scroll.font, s.scroll.critFont, s.plates.font }) do
		local file = media:match('%["' .. font .. '"%] = MEDIA %.%. "Fonts[^"]-([%w%-]+%.ttf)"')
		local handle = file and io.open(ROOT .. "EldoUI/Media/Fonts/" .. file, "rb")
		if handle then handle:close() end
		Check(handle ~= nil, "Punchy's font " .. font .. " is one EldoUI ships (" .. tostring(file) .. ")")
	end
	Check(s.plates.colorMode == "warm" and options:find('warm = L["Ivory, golden critical hits"]', 1, true) ~= nil,
		"Punchy's plate colors are offered on the Nameplates tab")
end

-- Every other style leaves the new looks alone, so applying it brings back
-- the defaults (off): the old look.
for _, style in ipairs(styles) do
	if style.key ~= "Punchy" then
		local scroll, plateSet = style.settings.scroll or {}, style.settings.plates or {}
		Check(scroll.shadow == nil and scroll.flash == nil and scroll.countGray == nil and plateSet.shadow == nil
			and plateSet.flash == nil and plateSet.font == nil and plateSet.outline == nil and plateSet.colorMode == nil,
			"the " .. style.key .. " style keeps the old look")
	end
end

print(("%d checks passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
