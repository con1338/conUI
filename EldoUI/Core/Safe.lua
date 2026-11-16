-- Secret-safe helpers and small game-value guards.
--
-- In restricted content (instances, boss fights, PvP) many game values
-- are secret: EldoUI may pass them straight to a widget (SetText,
-- SetValue, SetVertexColor), but comparing one (even with nil), doing
-- arithmetic on it, joining it into a string or using it as a table key
-- errors in the client. Test for a secret FIRST, and test for nil with
-- type(x) == "nil".
--
--   E:IsSecret(value)              true for a secret value (false when the client has no secrets)
--   E:Readable(value)              value, or nil when it is secret
--   E:SafeEquals(a, b)             a == b, false when either is secret
--   E:SafeString(value, fallback)  a plain string to join or compare; secrets, nil and
--                                  tables give fallback ("" when none)
--   E.Secret(value)                as E:IsSecret, a plain function for a module local
--   E.Plain(value)                 as E:Readable, a plain function (local Plain = E.Plain)
--   E.PlainCall(fn, ...)           fn(...) in a pcall: its first result, or nil when fn is
--                                  missing, errors or returns a secret
--   E.PlainCallAll(fn, ...)        fn(...) in a pcall: every result, or nothing when fn is
--                                  missing, errors or any result is secret
--   E.PlainCallEach(fn, ...)       fn(...) in a pcall: every result, each secret one as nil;
--                                  nothing when fn is missing or errors
--   E.FrameCheck(frame, method)    frame:IsForbidden(), :IsProtected() or
--                                  :IsAnchoringRestricted() as plain true or false; a secret
--                                  or failed answer counts as true (the frame is left alone)
--   E.FrameMouse(frame, method)    frame:IsMouseEnabled(), :IsMouseClickEnabled(),
--                                  :IsMouseMotionEnabled() or :IsMouseWheelEnabled() as plain
--                                  true or false; nil when the answer is secret or the read
--                                  fails (leave the frame's mouse as it is)
--   E.PlainAtlas(region)           region:GetAtlas() as a plain string, or nil when there is
--                                  none, it is secret or the read fails
--   E.FrameStrata(frame, fallback) the frame's strata, or fallback when it is secret
--   E.FrameLevel(frame, fallback)  the frame's level, or fallback when it is secret
--   E.IdentitySecret(unit)         true when the game hides the unit's identity (an error
--                                  or a secret answer counts as hidden)
--   E.IsList(t)                    true for a list of plain values (replaced whole on merge)
--   E:AtMaxLevel()                 true when the player is at the level cap
--   E.DeepEqual(a, b)              nested equality of two values (in Core/Database.lua)
--   E.SkinGlobal(frame, suffix)    the global region named after a frame (in Core/Skin.lua)
--   E:BNetFriendCount()            Battle.net friends, 0 while Battle.net is offline
--   E:ClassColorObject(classFile)  the class color (custom ones from the Colors page)
--   E:ReactionColorObject(r)       as a color object (r, g, b, :WrapTextInColorCode,
--   E:PowerColorObject(token)      :GenerateHexColor), or nil
--   E:WrapClassColor(classFile, text)  text in the class color, or text as it was
--   E:UnitShowsClassColor(unit)    true for a player or an AI party follower (their
--                                  class colors them); false when the game hides it
--
-- The color getters themselves (E:GetClassColor, E:GetReactionColor,
-- E:GetPowerColor -> r, g, b) live in Core/Media.lua.
-- Written from scratch for EldoUI.
local _, E = ...

local issecret = issecretvalue or function() return false end

function E:IsSecret(value)
	return issecret(value) and true or false
end

function E:Readable(value)
	if issecret(value) then return nil end
	return value
end

function E:SafeEquals(a, b)
	if issecret(a) or issecret(b) then return false end
	return a == b
end

-- The plain-function forms: modules take these as a
-- local (local Secret = E.Secret) instead of writing their own copy.
function E.Secret(value)
	return issecret(value) and true or false
end

-- Battle.net real names reach addons as protected strings ("|K...|k")
-- that only mean something in this session. Text kept past it (saved
-- chat, copied lines) gets a neutral word in their place; they are never
-- decoded.
function E.MaskProtectedNames(text)
	if type(text) ~= "string" or issecret(text) or not text:find("|K", 1, true) then return text end
	return (text:gsub("|K.-|k", E.L["(Battle.net name)"]))
end

function E.Plain(value)
	if issecret(value) then return nil end
	return value
end

function E.PlainCall(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, value = pcall(fn, ...)
	if not ok or issecret(value) then return nil end
	return value
end

-- Several results at once. select("#") keeps nils in the middle and at
-- the end, so a caller reading the 3rd value gets the 3rd value.
local function Packed(ok, ...)
	return ok, select("#", ...), { ... }
end

local function CheckedAll(ok, ...)
	if not ok then return end
	for index = 1, select("#", ...) do
		if issecret((select(index, ...))) then return end
	end
	return ...
end

function E.PlainCallAll(fn, ...)
	if type(fn) ~= "function" then return end
	return CheckedAll(pcall(fn, ...))
end

function E.PlainCallEach(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, count, results = Packed(pcall(fn, ...))
	if not ok then return end
	for index = 1, count do
		if issecret(results[index]) then results[index] = nil end
	end
	return unpack(results, 1, count)
end

-- The master looter's unit token while the group uses master loot, else
-- nil (also for a secret answer).
function E.MasterLooterUnit()
	local party = C_PartyInfo
	if not (party and party.GetLootMethod) then return nil end
	local method, partyIndex, raidIndex = E.PlainCallEach(party.GetLootMethod)
	local master = Enum and Enum.LootMethod and Enum.LootMethod.Masterlooter or 2
	if method ~= master then return nil end
	if IsInRaid() then
		return type(raidIndex) == "number" and raidIndex > 0 and ("raid" .. raidIndex) or nil
	end
	if partyIndex == 0 then return "player" end
	return type(partyIndex) == "number" and partyIndex > 0 and ("party" .. partyIndex) or nil
end

-- Is this frame forbidden, protected or anchoring restricted? On a frame
-- EldoUI did not make, the game can keep the answer secret, and testing a
-- secret answer errors. A secret or failed answer counts as true, so such
-- a frame is left alone; a frame without the method answers false.
function E.FrameCheck(frame, method)
	if type(frame) ~= "table" then return false end
	local fn = frame[method]
	if type(fn) ~= "function" then return false end
	local ok, answer = pcall(fn, frame)
	if not ok or issecret(answer) then return true end
	return answer and true or false
end

-- A frame's mouse state as a plain boolean. A secret, unavailable or
-- unexpected answer stays unknown, so the caller leaves the frame alone.
function E.FrameMouse(frame, method)
	if type(frame) ~= "table" then return nil end
	local value = E.PlainCall(frame[method or "IsMouseEnabled"], frame)
	if type(value) == "boolean" then return value end
end

-- A missing atlas is a readable result. An unavailable read cannot tell
-- the caller whether replacing the region would discard its original art.
function E.FrameAtlas(region)
	if type(region) ~= "table" then return nil, false end
	local getAtlas = region.GetAtlas
	if type(getAtlas) ~= "function" then return nil, true end
	local ok, value = pcall(getAtlas, region)
	if not ok or issecret(value) then return nil, false end
	if type(value) ~= "nil" and type(value) ~= "string" then return nil, false end
	return value, true
end

-- The single-value form keeps absent and unavailable atlas answers empty.
function E.PlainAtlas(region)
	local atlas = E.FrameAtlas(region)
	if atlas ~= "" then return atlas end
end

-- A frame's strata or level as a plain value, or fallback when the game
-- keeps it secret (a Blizzard frame can carry a secret strata) or the read
-- fails. Never pass another frame's GetFrameStrata() straight on.
local STRATA = { BACKGROUND = true, LOW = true, MEDIUM = true, HIGH = true, DIALOG = true,
	FULLSCREEN = true, FULLSCREEN_DIALOG = true, TOOLTIP = true }

function E.FrameStrata(frame, fallback)
	local strata = type(frame) == "table" and E.PlainCall(frame.GetFrameStrata, frame)
	if type(strata) == "string" and STRATA[strata] then return strata end
	return fallback
end

function E.FrameLevel(frame, fallback)
	local level = type(frame) == "table" and E.PlainCall(frame.GetFrameLevel, frame)
	if type(level) == "number" then return level end
	return fallback
end

-- True when the game hides this unit's identity (instances, restricted
-- content): skip the unit before any name or GUID is read. A failed or
-- secret answer counts as hidden; with the check missing, all show.
function E.IdentitySecret(unit)
	local secrets = C_Secrets
	if not (secrets and secrets.ShouldUnitIdentityBeSecret) then return false end
	local ok, hidden = pcall(secrets.ShouldUnitIdentityBeSecret, unit)
	if not ok or issecret(hidden) then return true end
	return hidden and true or false
end

-- A list of plain values ({ "Friends", "Guild" }, datatext slots) is one
-- setting, replaced as a whole when settings are merged. A table of tables
-- (the action bars) is merged entry by entry. An empty table counts as a list.
function E.IsList(value)
	if next(value) == nil then return true end
	for _, item in pairs(value) do
		if type(item) == "table" then return false end
	end
	return #value > 0
end

-- True when the player is at the level cap: the game rule when the client
-- has it, the expansion's level cap otherwise.
function E:AtMaxLevel()
	if GameRulesUtil and GameRulesUtil.IsPlayerAtEffectiveMaxLevel then
		local ok, atMax = pcall(GameRulesUtil.IsPlayerAtEffectiveMaxLevel)
		if ok then return atMax end
	end
	local maxLevel = GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()
	return maxLevel and UnitLevel("player") >= maxLevel
end

function E:SafeString(value, fallback)
	if issecret(value) then return fallback or "" end
	local kind = type(value)
	if kind == "string" then return value end
	if kind == "number" or kind == "boolean" then return tostring(value) end
	return fallback or ""
end

---------------------------------------------------------------------------
-- Battle.net: BNGetNumFriends returns nothing while Battle.net is
-- offline, so `for i = 1, BNGetNumFriends()` errors. Count through this.
---------------------------------------------------------------------------
function E:BNetFriendCount()
	if type(BNGetNumFriends) ~= "function" then return 0 end
	if type(BNConnected) == "function" then
		local ok, connected = pcall(BNConnected)
		if ok and not issecret(connected) and connected == false then return 0 end
	end
	local ok, count = pcall(BNGetNumFriends)
	if not ok or issecret(count) then return 0 end
	return tonumber(count) or 0
end

---------------------------------------------------------------------------
-- Who gets a class color: players, and the AI followers that fill a party
-- in follower dungeons (UnitInPartyIsAI). Followers are not players, so a
-- plain UnitIsPlayer test gave them the friendly reaction color instead of
-- their class. A secret or failed answer counts as no.
---------------------------------------------------------------------------
local function Yes(fn, unit)
	if type(fn) ~= "function" then return false end
	local ok, value = pcall(fn, unit)
	if not ok or issecret(value) then return false end
	return value and true or false
end

function E:UnitShowsClassColor(unit)
	if issecret(unit) or type(unit) ~= "string" then return false end
	if Yes(UnitIsPlayer, unit) then return true end
	return Yes(UnitInPartyIsAI, unit)
end

---------------------------------------------------------------------------
-- Color objects. Modules that need a color object (to wrap text
-- or build a hex code) use these instead of C_ClassColor.GetClassColor,
-- RAID_CLASS_COLORS, FACTION_BAR_COLORS or PowerBarColor, so custom
-- colors from the Colors page reach them. One object per color,
-- refreshed on every call: use it right away, don't keep it.
---------------------------------------------------------------------------
local objects = {}

local function Hex(r, g, b)
	return ("ff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local ColorObject = {}
ColorObject.__index = ColorObject
function ColorObject:GetRGB() return self.r, self.g, self.b end
function ColorObject:GetRGBA() return self.r, self.g, self.b, self.a end
function ColorObject:GenerateHexColor() return Hex(self.r, self.g, self.b) end
function ColorObject:GenerateHexColorMarkup() return "|c" .. Hex(self.r, self.g, self.b) end
function ColorObject:WrapTextInColorCode(text)
	if issecret(text) or type(text) == "nil" then return text end
	return "|c" .. Hex(self.r, self.g, self.b) .. tostring(text) .. "|r"
end

local function Object(group, key, r, g, b)
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
	local list = objects[group]
	if not list then
		list = {}
		objects[group] = list
	end
	local color = list[key]
	if not color then
		color = setmetatable({ a = 1 }, ColorObject)
		list[key] = color
	end
	color.r, color.g, color.b = r, g, b
	color.colorStr = Hex(r, g, b)
	return color
end

function E:ClassColorObject(classFile)
	if type(classFile) ~= "string" or issecret(classFile) or classFile == "" or not self.GetClassColor then return nil end
	return Object("class", classFile, self:GetClassColor(classFile))
end

function E:ReactionColorObject(reaction)
	if issecret(reaction) or type(reaction) ~= "number" or not self.GetReactionColor then return nil end
	return Object("reaction", reaction, self:GetReactionColor(reaction))
end

function E:PowerColorObject(token)
	if issecret(token) or (type(token) ~= "string" and type(token) ~= "number") or not self.GetPowerColor then return nil end
	return Object("power", token, self:GetPowerColor(token))
end

function E:WrapClassColor(classFile, text)
	local color = self:ClassColorObject(classFile)
	if color then return color:WrapTextInColorCode(text) end
	return text
end
