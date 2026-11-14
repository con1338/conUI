-- A stand-in for the game, enough to load EldoUI offline and run its start
-- (tools/harness/load_eldoui.lua). Returns Install(world), which fills the
-- global table:
--   * frames from CreateFrame keep their size, points, scripts, attributes,
--     texts and events (World.Fire sends an event to every frame that asked
--     for it);
--   * the API names the addon reads (tools/ci/globals.lua) answer: some by
--     hand (the player, the client, time, add-ons, CVars, timers, hooks,
--     colors, constants), the rest through a "mock" that can be called,
--     indexed and used as a frame or a namespace. A mock call answers by the
--     name: Is*/Has*/Can* false, anything with "Num" or ending in "Count" 0,
--     a few frame getters a number, else nil;
--   * any other global is nil, as for an add-on that isn't there.
-- It can't tell whether the game would draw anything right: it finds errors
-- in the Lua code and calls into names the game doesn't have.
local Install

local unpack = unpack or table.unpack

---------------------------------------------------------------------------
-- Mocks: callable, indexable, never failing on use as a frame or namespace
---------------------------------------------------------------------------
local mockNames = setmetatable({}, { __mode = "k" })
local Mock
local MOCK_META

local FRAME_GETTERS = {
	GetWidth = 100, GetHeight = 100, GetScale = 1, GetEffectiveScale = 1, GetAlpha = 1, GetEffectiveAlpha = 1,
	GetFrameLevel = 1, GetNumPoints = 0, GetFrameStrata = "MEDIUM", GetText = "", GetStringWidth = 10,
	GetStringHeight = 12, GetLeft = 0, GetBottom = 0, GetRight = 100, GetTop = 100, GetID = 0, GetValue = 0,
	GetVerticalScroll = 0, GetHorizontalScroll = 0, GetVerticalScrollRange = 0, GetNumLetters = 0,
	GetCursorPosition = 0, GetNumber = 0, GetLineHeight = 12, NumLines = 0, GetObjectType = "Frame",
}

-- What calling an unknown API or method returns, by its name.
local function Answer(name, self)
	if type(name) ~= "string" then return nil end
	local fixed = FRAME_GETTERS[name]
	if fixed ~= nil then return fixed end
	if name == "GetName" then return mockNames[self] end
	if name == "GetCenter" then return 50, 50 end
	if name == "GetSize" then return 100, 100 end
	if name == "GetRect" then return 0, 0, 100, 100 end
	if name == "GetMinMaxValues" then return 0, 1 end
	if name == "GetTexCoord" then return 0, 1, 0, 1 end
	if name == "GetVertexColor" or name == "GetBackdropColor" or name == "GetBackdropBorderColor" or name == "GetTextColor"
		or name == "GetStatusBarColor" or name == "GetShadowColor" then return 1, 1, 1, 1 end
	if name == "GetFont" then return "Fonts\\FRIZQT__.TTF", 12, "" end
	if name == "GetShadowOffset" then return 0, 0 end
	if name:find("Num%u") or name:find("Count$") then return 0 end
	for _, prefix in ipairs({ "^Is%u", "^Has%u", "^Can%u", "^In%u", "^UnitIs%u", "^UnitHas%u", "^UnitCan%u", "^UnitIn%u" }) do
		if name:find(prefix) then return false end
	end
	return nil
end

MOCK_META = {
	__index = function(self, key)
		local child = Mock(key)
		rawset(self, key, child)
		return child
	end,
	__call = function(self, first) return Answer(mockNames[self], first) end,
	__add = function() return 0 end, __sub = function() return 0 end, __mul = function() return 0 end,
	__div = function() return 0 end, __mod = function() return 0 end, __pow = function() return 0 end,
	__unm = function() return 0 end,
	__concat = function(a, b) return tostring(a) .. tostring(b) end,
	__tostring = function(self) return "mock:" .. tostring(mockNames[self]) end,
}

Mock = function(name)
	local mock = setmetatable({}, MOCK_META)
	mockNames[mock] = name
	return mock
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local World = { frames = {}, events = {}, timers = {}, errors = {}, chat = {}, clock = 1000, loggedIn = false }

-- A frame's own methods are below; any other method name (CamelCase, as
-- the game's are) answers like a mock. Other fields are nil until the code
-- sets them, as on a real frame.
local Frame = {}
local FRAME_META = {
	__index = function(self, key)
		local method = Frame[key]
		if method ~= nil then return method end
		if type(key) ~= "string" or not key:find("^%u") then return nil end
		local child = Mock(key)
		rawset(self, key, child)
		return child
	end,
	__tostring = function(self) return "frame:" .. tostring(rawget(self, "__name")) end,
}

local function NewObject(kind, name, parent)
	local object = setmetatable({ __kind = kind, __name = name, __parent = parent, __shown = kind ~= "GameTooltip",
		__scripts = {}, __attributes = {}, __points = 0, __width = 0, __height = 0, __children = {} }, FRAME_META)
	if type(parent) == "table" and rawget(parent, "__children") then table.insert(parent.__children, object) end
	if type(name) == "string" and name ~= "" then
		if type(parent) == "table" and name:find("$parent", 1, true) then
			name = name:gsub("%$parent", tostring(rawget(parent, "__name") or ""))
		end
		rawset(_G, name, object)
		object.__name = name
	end
	mockNames[object] = object.__name
	table.insert(World.frames, object)
	return object
end
World.NewObject = NewObject

-- Scripts and events
function Frame:SetScript(name, fn) self.__scripts[name] = fn end
function Frame:GetScript(name) return self.__scripts[name] end
function Frame:HasScript() return true end
function Frame:HookScript(name, fn)
	local old = self.__scripts[name]
	self.__scripts[name] = old and function(...) old(...) return fn(...) end or fn
	return true
end
function Frame:RegisterEvent(event)
	World.events[event] = World.events[event] or {}
	World.events[event][self] = true
	return true
end
Frame.RegisterUnitEvent = Frame.RegisterEvent
function Frame:UnregisterEvent(event)
	if World.events[event] then World.events[event][self] = nil end
end
function Frame:UnregisterAllEvents()
	for _, list in pairs(World.events) do list[self] = nil end
end
function Frame:IsEventRegistered(event) return World.events[event] and World.events[event][self] or false end
function Frame:RegisterAllEvents() end

-- Shown, size, place
function Frame:Show() self.__shown = true end
function Frame:Hide() self.__shown = false end
function Frame:SetShown(shown) self.__shown = shown and true or false end
function Frame:IsShown() return self.__shown end
function Frame:IsVisible() return self.__shown end
function Frame:SetSize(w, h) self.__width, self.__height = tonumber(w) or 0, tonumber(h) or tonumber(w) or 0 end
function Frame:SetWidth(w) self.__width = tonumber(w) or 0 end
function Frame:SetHeight(h) self.__height = tonumber(h) or 0 end
function Frame:GetWidth() return self.__width end
function Frame:GetHeight() return self.__height end
function Frame:GetSize() return self.__width, self.__height end
function Frame:SetPoint() self.__points = self.__points + 1 end
function Frame:SetAllPoints() self.__points = self.__points + 1 end
function Frame:ClearAllPoints() self.__points = 0 end
function Frame:GetNumPoints() return self.__points end
function Frame:GetPoint(index)
	if self.__points == 0 or (index and index > self.__points) then return nil end
	return "CENTER", _G.UIParent, "CENTER", 0, 0
end
function Frame:GetCenter() return 500, 400 end
function Frame:GetLeft() return 0 end
function Frame:GetBottom() return 0 end
function Frame:GetRight() return self.__width end
function Frame:GetTop() return self.__height end
function Frame:GetRect() return 0, 0, self.__width, self.__height end
function Frame:GetBoundsRect() return 0, 0, self.__width, self.__height end
function Frame:SetScale(scale) self.__scale = tonumber(scale) or 1 end
function Frame:GetScale() return self.__scale or 1 end
function Frame:GetEffectiveScale() return self.__scale or 1 end
function Frame:SetAlpha(alpha) self.__alpha = tonumber(alpha) or 1 end
function Frame:GetAlpha() return self.__alpha or 1 end
function Frame:GetEffectiveAlpha() return self.__alpha or 1 end
function Frame:SetFrameLevel(level) self.__level = tonumber(level) or 1 end
function Frame:GetFrameLevel() return self.__level or 1 end
function Frame:SetFrameStrata(strata) self.__strata = strata end
function Frame:GetFrameStrata() return self.__strata or "MEDIUM" end
function Frame:IsMouseOver() return false end
function Frame:IsForbidden() return false end
function Frame:IsProtected() return false, false end
function Frame:CanChangeProtectedState() return true end
function Frame:IsAnchoringRestricted() return false end

-- Family
function Frame:GetName() return self.__name end
function Frame:GetDebugName() return tostring(self.__name) end
function Frame:GetParent() return self.__parent end
function Frame:SetParent(parent) self.__parent = parent end
function Frame:GetChildren() return unpack(self.__children) end
function Frame:GetNumChildren() return #self.__children end
function Frame:GetRegions() end
function Frame:GetNumRegions() return 0 end
function Frame:GetObjectType() return self.__kind end
function Frame:IsObjectType(kind) return kind == self.__kind or kind == "Frame" or kind == "Region" end
function Frame:SetID(id) self.__id = id end
function Frame:GetID() return self.__id or 0 end

-- Attributes (secure frames)
function Frame:SetAttribute(name, value) self.__attributes[name] = value end
function Frame:GetAttribute(name) return self.__attributes[name] end
Frame.SetAttributeNoHandler = Frame.SetAttribute

-- Regions
local function Region(kind)
	return function(self, name) return NewObject(kind, name, self) end
end
Frame.CreateTexture = Region("Texture")
Frame.CreateMaskTexture = Region("MaskTexture")
Frame.CreateLine = Region("Line")
Frame.CreateFontString = Region("FontString")
Frame.CreateAnimationGroup = Region("AnimationGroup")
Frame.CreateAnimation = Region("Animation")
function Frame:SetTexture(texture) self.__texture = texture return true end
function Frame:GetTexture() return self.__texture end
function Frame:SetAtlas(atlas) self.__atlas = atlas return true end
function Frame:GetAtlas() return self.__atlas end
function Frame:SetTexCoord(...) self.__coords = { ... } end
function Frame:GetTexCoord() return 0, 1, 0, 1 end
function Frame:SetVertexColor(...) self.__vertex = { ... } end
function Frame:GetVertexColor() return 1, 1, 1, 1 end
function Frame:SetText(text) self.__text = text end
function Frame:SetFormattedText(fmt, ...) self.__text = tostring(fmt):format(...) end
function Frame:GetText() return self.__text or "" end
function Frame:GetStringWidth() return #tostring(self.__text or "") * 6 end
function Frame:GetUnboundedStringWidth() return #tostring(self.__text or "") * 6 end
function Frame:GetStringHeight() return 12 end
function Frame:SetFont(path, size, flags) self.__font = { path, size, flags } return true end
function Frame:GetFont()
	local font = self.__font
	if font then return font[1], font[2], font[3] end
	return "Fonts\\FRIZQT__.TTF", 12, ""
end
function Frame:SetFontObject(object) self.__fontObject = object end
function Frame:GetFontObject() return self.__fontObject end
function Frame:SetTextColor(...) self.__textColor = { ... } end
function Frame:GetTextColor() return 1, 1, 1, 1 end
function Frame:GetNormalTexture() self.__normal = self.__normal or NewObject("Texture", nil, self) return self.__normal end
function Frame:GetHighlightTexture() self.__highlight = self.__highlight or NewObject("Texture", nil, self) return self.__highlight end
function Frame:GetPushedTexture() self.__pushed = self.__pushed or NewObject("Texture", nil, self) return self.__pushed end
function Frame:GetCheckedTexture() self.__checked = self.__checked or NewObject("Texture", nil, self) return self.__checked end
function Frame:GetDisabledTexture() self.__disabled = self.__disabled or NewObject("Texture", nil, self) return self.__disabled end
function Frame:GetFontString() self.__fontString = self.__fontString or NewObject("FontString", nil, self) return self.__fontString end
function Frame:GetStatusBarTexture() self.__bar = self.__bar or NewObject("Texture", nil, self) return self.__bar end
function Frame:SetMinMaxValues(low, high) self.__min, self.__max = low, high end
function Frame:GetMinMaxValues() return self.__min or 0, self.__max or 1 end
function Frame:SetValue(value) self.__value = value end
function Frame:GetValue() return self.__value or 0 end
function Frame:SetChecked(checked) self.__isChecked = checked and true or false end
function Frame:GetChecked() return self.__isChecked or false end
function Frame:GetCooldownTimes() return 0, 0 end
function Frame:GetCooldownDuration() return 0 end
function Frame:IsPlaying() return false end
function Frame:GetNumber() return 0 end
function Frame:HasFocus() return false end
function Frame:GetCursorPosition() return 0 end
function Frame:GetNumLetters() return 0 end
function Frame:SetScrollChild(child) self.__scrollChild = child end
function Frame:GetScrollChild() return self.__scrollChild end
function Frame:IsEnabled() return true end
function Frame:GetButtonState() return "NORMAL" end
function Frame:GetOwner() return self.__owner end
function Frame:SetOwner(owner) self.__owner = owner end
function Frame:IsOwned(owner) return self.__owner == owner end
function Frame:NumLines() return 0 end
function Frame:GetUnit() return nil end
function Frame:GetItem() return nil end
function Frame:GetSpell() return nil end
function Frame:AddMessage(text) table.insert(World.chat, tostring(text)) end
function Frame:GetNumMessages() return 0 end
-- Backdrops (BackdropTemplate)
function Frame:SetBackdrop(info) self.__backdrop = info end
function Frame:GetBackdrop() return self.__backdrop end
function Frame:SetBackdropColor(...) self.__backdropColor = { ... } end
function Frame:GetBackdropColor() local c = self.__backdropColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
function Frame:SetBackdropBorderColor(...) self.__borderColor = { ... } end
function Frame:GetBackdropBorderColor() local c = self.__borderColor or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end

local BACKDROP_METHODS = { "SetBackdrop", "GetBackdrop", "SetBackdropColor", "GetBackdropColor", "SetBackdropBorderColor",
	"GetBackdropBorderColor" }

---------------------------------------------------------------------------
-- Answers by hand
---------------------------------------------------------------------------
local function Color(r, g, b, a)
	local color = { r = r or 1, g = g or 1, b = b or 1, a = a or 1 }
	function color:GetRGB() return self.r, self.g, self.b end
	function color:GetRGBA() return self.r, self.g, self.b, self.a end
	function color:GetRGBAsBytes() return self.r * 255, self.g * 255, self.b * 255 end
	function color:GenerateHexColor() return ("ff%02x%02x%02x"):format(self.r * 255, self.g * 255, self.b * 255) end
	function color:GenerateHexColorMarkup() return "|c" .. self:GenerateHexColor() end
	function color:WrapTextInColorCode(text) return "|c" .. self:GenerateHexColor() .. tostring(text) .. "|r" end
	function color:SetRGB(nr, ng, nb) self.r, self.g, self.b = nr, ng, nb end
	function color:SetRGBA(nr, ng, nb, na) self.r, self.g, self.b, self.a = nr, ng, nb, na end
	function color:IsEqualTo(other) return other and self.r == other.r and self.g == other.g and self.b == other.b end
	color.colorStr = color:GenerateHexColor()
	return color
end

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function ClassTable(value)
	local out = {}
	for _, class in ipairs(CLASSES) do out[class] = value(class) end
	return out
end

-- Numbers that never repeat, for Enum and SOUNDKIT fields.
local nextNumber = 1000
local function AutoNumbers()
	return setmetatable({}, { __index = function(self, key)
		nextNumber = nextNumber + 1
		rawset(self, key, nextNumber)
		return nextNumber
	end })
end

local INVSLOTS = { AMMO = 0, HEAD = 1, NECK = 2, SHOULDER = 3, BODY = 4, CHEST = 5, WAIST = 6, LEGS = 7, FEET = 8, WRIST = 9,
	HAND = 10, FINGER1 = 11, FINGER2 = 12, TRINKET1 = 13, TRINKET2 = 14, BACK = 15, MAINHAND = 16, OFFHAND = 17, RANGED = 18,
	TABARD = 19 }
local SLOT_NAMES = { AmmoSlot = 0, HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4, ChestSlot = 5, WaistSlot = 6,
	LegsSlot = 7, FeetSlot = 8, WristSlot = 9, HandsSlot = 10, Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13,
	Trinket1Slot = 14, BackSlot = 15, MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18, TabardSlot = 19,
	Bag0Slot = 20, Bag1Slot = 21, Bag2Slot = 22, Bag3Slot = 23 }

local CVARS = { uiScale = "1", useUiScale = "0", nameplateMaxDistance = "20" }

local function Namespace(name, fields)
	local namespace = Mock(name)
	for key, value in pairs(fields) do rawset(namespace, key, value) end
	return namespace
end

local function Fixed(...)
	local values = { n = select("#", ...), ... }
	return function() return unpack(values, 1, values.n) end
end

local function Byte(value) return value % 256 end
local bit = {
	band = function(a, b) local r, m = 0, 1 for _ = 1, 32 do if a % 2 == 1 and b % 2 == 1 then r = r + m end a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2 end return r end,
	bor = function(a, b) local r, m = 0, 1 for _ = 1, 32 do if a % 2 == 1 or b % 2 == 1 then r = r + m end a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2 end return r end,
	bxor = function(a, b) local r, m = 0, 1 for _ = 1, 32 do if a % 2 ~= b % 2 then r = r + m end a, b, m = math.floor(a / 2), math.floor(b / 2), m * 2 end return r end,
	lshift = function(a, n) return a * 2 ^ n end,
	rshift = function(a, n) return math.floor(a / 2 ^ n) end,
	bnot = function(a) return 4294967295 - a end,
}
bit.Byte = Byte

Install = function()
	local G = _G
	local function Set(name, value) rawset(G, name, value) end

	-- Lua helpers the game adds
	Set("bit", bit)
	Set("format", string.format)
	Set("strupper", string.upper)
	Set("strlower", string.lower)
	Set("strfind", string.find)
	Set("strmatch", string.match)
	Set("strsub", string.sub)
	Set("strlen", string.len)
	Set("strrep", string.rep)
	Set("gsub", string.gsub)
	Set("tinsert", table.insert)
	Set("tremove", table.remove)
	Set("date", os.date)
	Set("time", os.time)
	Set("strtrim", function(text, chars)
		if type(text) ~= "string" then return text end
		if chars then
			local set = "[" .. chars:gsub("[%]%[%^%-%%]", "%%%0") .. "]"
			return (text:gsub("^" .. set .. "+", ""):gsub(set .. "+$", ""))
		end
		return (text:gsub("^%s+", ""):gsub("%s+$", ""))
	end)
	Set("strsplit", function(delimiter, text, pieces)
		local out, start = {}, 1
		pieces = pieces or math.huge
		while #out < pieces - 1 do
			local from, to = text:find("[" .. delimiter:gsub("[%]%[%^%-%%]", "%%%0") .. "]", start)
			if not from then break end
			out[#out + 1] = text:sub(start, from - 1)
			start = to + 1
		end
		out[#out + 1] = text:sub(start)
		return unpack(out)
	end)
	Set("strjoin", function(delimiter, ...) return table.concat({ ... }, delimiter) end)
	Set("wipe", function(t) for k in pairs(t) do t[k] = nil end return t end)
	Set("tContains", function(t, value) for _, v in pairs(t) do if v == value then return true end end return false end)
	Set("tIndexOf", function(t, value) for i, v in ipairs(t) do if v == value then return i end end return nil end)
	Set("CopyTable", function(source, seen)
		local function Copy(t)
			local copy = {}
			for k, v in pairs(t) do copy[k] = type(v) == "table" and Copy(v) or v end
			return copy
		end
		return Copy(source)
	end)
	Set("Mixin", function(target, ...)
		for i = 1, select("#", ...) do
			local source = select(i, ...)
			if type(source) == "table" then for k, v in pairs(source) do target[k] = v end end
		end
		return target
	end)
	Set("CreateFromMixins", function(...) return G.Mixin({}, ...) end)
	Set("debugstack", function() return "harness" end)
	Set("debuglocals", function() return "" end)
	Set("debugprofilestop", function() return os.clock() * 1000 end)
	Set("issecretvalue", function() return false end)
	Set("issecurevariable", function() return true, nil end)
	Set("canaccessvalue", function() return true end)
	Set("canaccesstable", function() return true end)
	Set("securecallfunction", function(fn, ...) return fn(...) end)
	Set("geterrorhandler", function() return World.Record end)
	Set("seterrorhandler", function() end)
	Set("hooksecurefunc", function(a, b, c)
		local target, name, hook = G, a, b
		if type(a) == "table" then target, name, hook = a, b, c end
		local original = target[name]
		if original == nil then error("hooksecurefunc(): " .. tostring(name) .. " is not a function", 2) end
		target[name] = function(...)
			local results = { original(...) }
			hook(...)
			return unpack(results)
		end
	end)

	-- Frames
	Set("CreateFrame", function(kind, name, parent)
		return NewObject(kind or "Frame", name, parent)
	end)
	local backdrop = {}
	for _, method in ipairs(BACKDROP_METHODS) do backdrop[method] = Frame[method] end
	backdrop.OnBackdropSizeChanged = function() end
	backdrop.ApplyBackdrop = function() end
	backdrop.ClearBackdrop = function(self) self.__backdrop = nil end
	Set("BackdropTemplateMixin", backdrop)
	Set("UIParent", NewObject("Frame", "UIParent"))
	G.UIParent:SetSize(1920, 1080)
	Set("WorldFrame", NewObject("Frame", "WorldFrame"))
	G.WorldFrame:SetSize(1920, 1080)
	Set("Minimap", NewObject("Minimap", "Minimap", G.UIParent))
	Set("GameTooltip", NewObject("GameTooltip", "GameTooltip", G.UIParent))
	Set("ItemRefTooltip", NewObject("GameTooltip", "ItemRefTooltip", G.UIParent))
	Set("EmbeddedItemTooltip", NewObject("GameTooltip", "EmbeddedItemTooltip", G.UIParent))
	Set("ChatFrame1", NewObject("ScrollingMessageFrame", "ChatFrame1", G.UIParent))
	Set("ChatFrame1EditBox", NewObject("EditBox", "ChatFrame1EditBox", G.ChatFrame1))
	Set("DEFAULT_CHAT_FRAME", G.ChatFrame1)
	Set("UIErrorsFrame", NewObject("MessageFrame", "UIErrorsFrame", G.UIParent))
	Set("SlashCmdList", {})
	Set("StaticPopupDialogs", {})
	Set("UISpecialFrames", {})
	Set("CHAT_FRAMES", { "ChatFrame1" })
	local function Font(name)
		local font = NewObject("Font", name)
		font.__font = { "Fonts\\FRIZQT__.TTF", 12, "" }
		return font
	end
	Set("CreateFont", function(name) return Font(name) end)
	Set("CreateFontFamily", function(name) return Font(name) end)
	for _, name in ipairs({ "ChatFontNormal", "ChatBubbleFont", "CombatTextFont", "GameFontHighlightSmallOutline", "NumberFontNormal",
		"NumberFontNormalSmallGray" }) do
		Set(name, Font(name))
	end

	-- Time, client, player
	Set("GetTime", function() return World.clock end)
	Set("GetServerTime", function() return os.time() end)
	Set("GetGameTime", Fixed(12, 0))
	Set("GetLocale", Fixed("enUS"))
	Set("GetRealmName", Fixed("Realm"))
	Set("GetNormalizedRealmName", Fixed("Realm"))
	Set("GetBuildInfo", Fixed("1.60.1", "70938", "Nov 1 2026", 16001, "", "", 16001))
	Set("GetPhysicalScreenSize", Fixed(1920, 1080))
	Set("GetScreenWidth", Fixed(1920))
	Set("GetScreenHeight", Fixed(1080))
	Set("GetFramerate", Fixed(60))
	Set("GetNetStats", Fixed(0, 0, 30, 30))
	Set("GetCursorPosition", Fixed(0, 0))
	Set("GetMouseFoci", function() return {} end)
	Set("GetMoney", Fixed(0))
	Set("GetMaxPlayerLevel", Fixed(60))
	Set("GetMaxLevelForPlayerExpansion", Fixed(60))
	Set("GetActionBarPage", Fixed(1))
	Set("GetCurrentBindingSet", Fixed(1))
	Set("GetNumTotemSlots", Fixed(4))
	Set("GetInventorySlotInfo", function(name) return SLOT_NAMES[name] or 0, "", false end)
	Set("GetInstanceInfo", Fixed("Elwynn Forest", "none", 0, "", 0, 0, false, 0, 0, nil))
	Set("IsInInstance", Fixed(false, "none"))
	Set("GetZoneText", Fixed("Elwynn Forest"))
	Set("GetRealZoneText", Fixed("Elwynn Forest"))
	Set("GetMinimapZoneText", Fixed("Elwynn Forest"))
	Set("GetSubZoneText", Fixed(""))
	Set("GetCVar", function(name) return CVARS[name] or "0" end)
	Set("GetCVarBool", Fixed(false))
	Set("IsLoggedIn", function() return World.loggedIn end)
	Set("Ambiguate", function(name) return (tostring(name):gsub("%-.*$", "")) end)
	Set("BreakUpLargeNumbers", function(value) return tostring(value) end)
	Set("AbbreviateNumbers", function(value) return tostring(value) end)
	Set("GetCoinTextureString", function(value) return tostring(value) end)
	Set("GetMoneyString", function(value) return tostring(value) end)
	Set("CreateColor", Color)
	Set("CreateAtlasMarkup", Fixed(""))
	Set("CreateVector2D", function(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end)
	Set("GetClassAtlas", Fixed(""))
	Set("GetRaceAtlas", Fixed(""))

	local function Player(unit) return unit == "player" end
	Set("UnitName", function(unit) if Player(unit) then return "Tester", nil end end)
	Set("UnitFullName", function(unit) if Player(unit) then return "Tester", "Realm" end end)
	Set("UnitPVPName", function(unit) if Player(unit) then return "Tester" end end)
	Set("UnitNameUnmodified", function(unit) if Player(unit) then return "Tester", nil end end)
	Set("UnitClass", function(unit) if Player(unit) then return "Warrior", "WARRIOR", 1 end end)
	Set("UnitClassFromGUID", function() return "Warrior", "WARRIOR", 1 end)
	Set("UnitRace", function(unit) if Player(unit) then return "Human", "Human", 1 end end)
	Set("UnitFactionGroup", function(unit) if Player(unit) then return "Alliance", "Alliance" end end)
	Set("UnitGUID", function(unit) if Player(unit) then return "Player-1-00000001" end end)
	Set("UnitExists", function(unit) return Player(unit) end)
	Set("UnitIsUnit", function(a, b) return a == b end)
	Set("UnitIsPlayer", function(unit) return Player(unit) end)
	Set("UnitLevel", function(unit) return Player(unit) and 60 or 0 end)
	Set("UnitEffectiveLevel", function(unit) return Player(unit) and 60 or 0 end)
	Set("UnitSex", Fixed(2))
	Set("UnitHealth", Fixed(100))
	Set("UnitHealthMax", Fixed(100))
	Set("UnitPower", Fixed(100))
	Set("UnitPowerMax", Fixed(100))
	Set("UnitPowerType", Fixed(1, "RAGE"))
	Set("UnitXP", Fixed(0))
	Set("UnitXPMax", Fixed(100))
	Set("UnitStat", Fixed(10, 10, 0, 0))
	Set("UnitArmor", Fixed(0, 0, 0, 0, 0))
	Set("UnitAttackPower", Fixed(0, 0, 0))
	Set("UnitRangedAttackPower", Fixed(0, 0, 0))
	Set("UnitDamage", Fixed(1, 2, 1, 2, 0, 0, 1))
	Set("UnitRangedDamage", Fixed(2, 1, 2, 0, 0, 1))
	Set("UnitAttackSpeed", Fixed(2, 2))
	Set("UnitResistance", Fixed(0, 0, 0, 0))
	Set("UnitReaction", Fixed(4))
	Set("UnitClassification", Fixed("normal"))

	-- Namespaces with answers
	local loaded = { EldoUI = true }
	Set("C_AddOns", Namespace("C_AddOns", {
		IsAddOnLoaded = function(name) return loaded[name] or false, loaded[name] or false end,
		GetAddOnMetadata = function(addon, field)
			if addon ~= "EldoUI" then return nil end
			if field == "Version" then return "0.7.2001-p1" end
			if field == "Title" then return "EldoUI" end
			return nil
		end,
		GetNumAddOns = Fixed(0),
		GetAddOnInfo = function(name) return name, name, "", false, "MISSING", "INSECURE", false end,
		LoadAddOn = function() return false, "MISSING" end,
		DoesAddOnExist = Fixed(false),
		GetAddOnEnableState = Fixed(0),
		IsAddOnLoadOnDemand = Fixed(true),
	}))
	Set("C_CVar", Namespace("C_CVar", {
		GetCVar = function(name) return CVARS[name] or "0" end,
		GetCVarBool = Fixed(false),
		GetCVarDefault = Fixed("0"),
		SetCVar = Fixed(true),
	}))
	Set("C_Timer", Namespace("C_Timer", {
		After = function(_, fn) table.insert(World.timers, fn) end,
		NewTimer = function(_, fn)
			local timer = { Cancel = function(self) self.cancelled = true end, IsCancelled = function(self) return self.cancelled end }
			table.insert(World.timers, function() if not timer.cancelled then fn(timer) end end)
			return timer
		end,
		NewTicker = function(_, fn, times)
			local ticker = { Cancel = function(self) self.cancelled = true end, IsCancelled = function(self) return self.cancelled end }
			table.insert(World.timers, function() if not ticker.cancelled then fn(ticker) end end)
			return ticker
		end,
	}))

	-- Constants
	for key, value in pairs(INVSLOTS) do Set("INVSLOT_" .. key, value) end
	local numbers = { ATTACHMENTS_MAX_RECEIVE = 16, ATTACHMENTS_MAX_SEND = 12, ATTACK_BUTTON_FLASH_TIME = 0.4,
		BASE_MOVEMENT_SPEED = 7, COOLDOWN_TYPE_LOSS_OF_CONTROL = 1, COOLDOWN_TYPE_NORMAL = 0, INBOXITEMS_TO_DISPLAY = 7,
		LE_PARTY_CATEGORY_INSTANCE = 2, MAX_GUILDBANK_TABS = 6, MERCHANT_HIGH_PRICE_COST = 1500000, MERCHANT_ITEMS_PER_PAGE = 10,
		NUM_BAG_SLOTS = 4, NUM_BANKBAGSLOTS = 6, NUM_CHAT_WINDOWS = 10, NUM_CONTAINER_FRAMES = 13, NUM_TOTAL_BAG_FRAMES = 5,
		NUM_TOTAL_EQUIPPED_BAG_SLOTS = 4, TOOLTIP_UPDATE_TIME = 0.2, WOW_PROJECT_MAINLINE = 1, WOW_PROJECT_CLASSIC = 2,
		WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5, WOW_PROJECT_WRATH_CLASSIC = 11, WOW_PROJECT_CATACLYSM_CLASSIC = 14,
		WOW_PROJECT_MISTS_CLASSIC = 19, WOW_PROJECT_ID = 2 }
	for key, value in pairs(numbers) do Set(key, value) end
	Set("STANDARD_TEXT_FONT", "Fonts\\FRIZQT__.TTF")
	Set("RAID_CLASS_COLORS", ClassTable(function() return Color(0.8, 0.6, 0.4) end))
	Set("LOCALIZED_CLASS_NAMES_MALE", ClassTable(function(class) return class:sub(1, 1) .. class:sub(2):lower() end))
	Set("LOCALIZED_CLASS_NAMES_FEMALE", ClassTable(function(class) return class:sub(1, 1) .. class:sub(2):lower() end))
	Set("CLASS_ICON_TCOORDS", ClassTable(function() return { 0, 0.25, 0, 0.25 } end))
	Set("CLASS_SORT_ORDER", { unpack(CLASSES) })
	local qualities = {}
	for quality = 0, 8 do
		local color = Color(1, 1, 1)
		color.hex = "|cffffffff"
		qualities[quality] = color
	end
	Set("ITEM_QUALITY_COLORS", qualities)
	local factions = {}
	for standing = 1, 8 do factions[standing] = Color(0.5, 0.5, 0.5) end
	Set("FACTION_BAR_COLORS", factions)
	Set("TOOLTIP_DEFAULT_COLOR", Color(1, 1, 1))
	Set("WORLD_RAID_MARKER_ORDER", { 8, 4, 1, 7, 2, 3, 6, 5 })
	Set("ACTION_HIGHLIGHT_MARKS", {})
	Set("SOUNDKIT", AutoNumbers())
	Set("PowerBarColor", setmetatable({}, { __index = function(self, key)
		local color = Color(0, 0, 1)
		rawset(self, key, color)
		return color
	end }))
	Set("ChatTypeInfo", setmetatable({}, { __index = function(self, key)
		local info = { r = 1, g = 1, b = 1, id = 1, sticky = 0 }
		rawset(self, key, info)
		return info
	end }))
	Set("Enum", setmetatable({}, { __index = function(self, key)
		local values = AutoNumbers()
		rawset(self, key, values)
		return values
	end }))

	-- Everything else the code reads: names from tools/ci/globals.lua become
	-- mocks (ALL_CAPS ones texts), any other global stays nil.
	local listed = {}
	for _, name in ipairs(World.globalNames or {}) do listed[name] = true end
	local NIL = { LibStub = true }
	setmetatable(G, { __index = function(_, name)
		if NIL[name] or not listed[name] then return nil end
		local value
		if type(name) == "string" and name:find("^[A-Z0-9_]+$") then
			value = name
		else
			value = Mock(name)
		end
		rawset(G, name, value)
		return value
	end })
end

World.Mock = Mock
World.Install = Install

-- Every recorded error, with the phase it came in.
function World.Record(err)
	table.insert(World.errors, { phase = World.phase or "?", message = tostring(err) })
end

-- Send an event to every frame that registered it.
function World.Fire(event, ...)
	local list = {}
	for frame in pairs(World.events[event] or {}) do list[#list + 1] = frame end
	for _, frame in ipairs(list) do
		local script = frame.__scripts.OnEvent
		if script then
			local ok, err = pcall(script, frame, event, ...)
			if not ok then World.Record(err) end
		end
	end
end

-- Run the C_Timer callbacks, and the ones they start, a few rounds deep.
function World.RunTimers(rounds)
	for _ = 1, rounds or 5 do
		local list = World.timers
		if #list == 0 then return end
		World.timers = {}
		World.clock = World.clock + 1
		for _, fn in ipairs(list) do
			local ok, err = pcall(fn)
			if not ok then World.Record(err) end
		end
	end
end

return World
