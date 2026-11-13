-- EldoUI Streamer Mode: aliases in place of real character names
-- while you stream or record.
--
--   * One switch (options, /eui streamer, a click on the Streamer
--     datatext). While it is on, EldoUI draws "Player" (or your alias) for
--     you and "Party 1-4" / "Raid 1-40", the class or the role, or an alias
--     you set, for your group.
--   * Every name EldoUI draws goes through Core/Names.lua
--     (E:SetNameAliasProvider): unit and group frames, nameplates, the
--     [name] tags, tooltips and the Target / Targeted by lines.
--   * Chat: the shown sender name of a line becomes the alias. The player
--     link underneath stays whole, so whisper, Reply and the
--     right-click menu still work. Lines the game keeps secret are never
--     touched (a Chat line hook only runs on readable lines).
--   * Optional: hide overhead names through the game's own name CVars
--     (E:SetCVar), put back when Streamer Mode goes off.
-- Blizzard frames EldoUI does not draw keep the real names; the options
-- say so. Unit identity is read only when the game hands it out: a secret
-- GUID or name falls back to the unit token, and an unknown unit keeps its
-- name.
local _, E = ...
local L = E.L

local Key = E.Key
local M = E:NewModule("Streamer", {
	title = "Streamer Mode",
	category = "Chat & Social",
	desc = "Aliases in place of real character names on EldoUI's frames, tooltips and chat while you stream or record.",
	defaults = {
		streaming = false,      -- the Streamer Mode switch
		scheme = "number",      -- number | class | role | custom (group members)
		selfAlias = "",         -- empty: "Player"
		others = "keep",        -- keep | class | generic (players outside your group)
		aliases = {},           -- ["Name-Realm"] = "Alias", always first
		frames = true,          -- unit and group frames, nameplates, tags
		tooltips = true,
		chat = true,
		overhead = "keep",      -- keep | friendly | all (game name CVars)
	},
})
E.Streamer = M

local CVAR_OWNER = "streamer"
local MAX_ALIASES = 100

local function IsSecret(value) return issecretvalue and issecretvalue(value) or false end
local Readable = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return Readable(a), Readable(b), Readable(c) end
end

local function Streaming()
	return M.active and M.db and M.db.streaming and true or false
end
M.Streaming = Streaming

-- Text a player typed: no escape codes, at most `limit` characters.
local function Clean(text, limit)
	text = strtrim(tostring(text or "")):gsub("|", "")
	if E.Utf8Sub then return E:Utf8Sub(text, limit) end
	return text:sub(1, limit)
end

---------------------------------------------------------------------------
-- Names and keys
---------------------------------------------------------------------------
local function MyRealm()
	local realm = Try(GetNormalizedRealmName)
	return type(realm) == "string" and realm ~= "" and realm or nil
end

-- "Name" / "Name-Realm" -> "name-realm" (lower case), or nil.
function M.Key(name)
	name = Readable(name)
	if type(name) ~= "string" then return nil end
	name = strtrim(name)
	if name == "" then return nil end
	local short, realm = name:match("^([^%-]+)%-(.+)$")
	short = short or name
	realm = realm or MyRealm() or ""
	realm = realm:gsub("[%s%-]", "")
	return (short .. "-" .. realm):lower()
end

local function UnitKey(unit)
	if not Try(UnitIsPlayer, unit) then return nil end
	-- "Name-Realm" the way chat senders are keyed, never with the surname.
	return M.Key(E:UnitNameKey(unit, true))
end

-- The custom alias of a name key, or nil.
local aliasIndex, aliasSource = {}, nil
local function CustomAlias(key)
	if not key then return nil end
	local list = M.db.aliases
	if aliasSource ~= list then
		aliasSource = list
		wipe(aliasIndex)
		for name, alias in pairs(list) do
			local k = M.Key(name)
			if k and type(alias) == "string" and alias ~= "" then aliasIndex[k] = alias end
		end
	end
	return aliasIndex[key]
end

function M:SetAlias(name, alias)
	local key = M.Key(Clean(name, 60))
	if not key then return false, L["Type a character name first, for example Name-Realm."] end
	alias = Clean(alias, 24)
	local list = self.db.aliases
	-- One entry per character, however it was typed.
	for existing in pairs(list) do
		if M.Key(existing) == key then list[existing] = nil end
	end
	if alias == "" then
		aliasSource = nil
		self:Refresh()
		return true, L["Alias removed."]
	end
	local count = 0
	for _ in pairs(list) do count = count + 1 end
	if count >= MAX_ALIASES then return false, L["The list is full (%d aliases)."]:format(MAX_ALIASES) end
	list[Clean(name, 60)] = alias
	aliasSource = nil
	self:Refresh()
	return true, L["%s shows as %s."]:format(Clean(name, 60), alias)
end

function M:AliasRows()
	local rows = {}
	for name, alias in pairs(self.db.aliases) do rows[#rows + 1] = { name = name, alias = alias } end
	table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
	return rows
end

---------------------------------------------------------------------------
-- The group: GUID -> token, rebuilt on roster changes
---------------------------------------------------------------------------
local byGUID = {}      -- guid -> "player" | "partyN" | "raidN"
local tokenKey = {}    -- token -> name key (readable names only)

local function GroupTokens()
	local list = {}
	if Try(IsInRaid) then
		for index = 1, 40 do list[#list + 1] = "raid" .. index end
	elseif Try(IsInGroup) then
		for index = 1, 4 do list[#list + 1] = "party" .. index end
	end
	return list
end
M.GroupTokens = GroupTokens

function M:ScanGroup()
	wipe(byGUID)
	wipe(tokenKey)
	local guid = Try(UnitGUID, "player")
	if guid then byGUID[guid] = "player" end
	for _, token in ipairs(GroupTokens()) do
		-- In a raid, your own raidN is you: it keeps "player".
		if Try(UnitExists, token) and not Try(UnitIsUnit, token, "player") then
			local id = Try(UnitGUID, token)
			if type(id) == "string" then byGUID[id] = token end
			tokenKey[token] = UnitKey(token)
		end
	end
end

-- "player", "partyN", "raidN" for a unit of yours or your group, else nil.
local function GroupToken(unit)
	unit = unit:lower()
	if unit == "player" then return "player" end
	local raid = Try(IsInRaid)
	if (unit:match("^party%d+$") and not raid) or (unit:match("^raid%d+$") and raid) then
		if Try(UnitIsUnit, unit, "player") then return "player" end
		return unit
	end
	local guid = Try(UnitGUID, unit)
	if type(guid) == "string" then
		local token = byGUID[guid]
		if token then return token end
		-- A plain GUID that is not in the group: not one of yours.
		if not (unit:match("^party") or unit:match("^raid")) then return nil end
	end
	-- The GUID is secret (instances): ask the game unit by unit.
	if Try(UnitIsUnit, unit, "player") then return "player" end
	for _, token in ipairs(GroupTokens()) do
		if Try(UnitIsUnit, unit, token) then return token end
	end
	return nil
end
M.GroupToken = GroupToken

local ROLE_TEXT = { TANK = "Tank", HEALER = "Healer", DAMAGER = "Damage" }

-- How many group members before `token` share `value` (class or role):
-- "Priest", "Priest 2".
local function Numbered(text, token, valueOf)
	local mine = valueOf(token)
	local count = 0
	for _, other in ipairs(GroupTokens()) do
		if other == token then break end
		if Try(UnitExists, other) and not Try(UnitIsUnit, other, "player") and valueOf(other) == mine then count = count + 1 end
	end
	if count == 0 then return text end
	return ("%s %d"):format(text, count + 1)
end

local function ClassOf(token)
	local _, class = Try(UnitClass, token)
	return class
end

local function RoleOf(token)
	local role = Try(UnitGroupRolesAssigned, token)
	return ROLE_TEXT[role or ""] and role or nil
end

local function NumberAlias(token)
	local kind, index = token:match("^(%a+)(%d+)$")
	if kind == "raid" then return L["Raid %d"]:format(tonumber(index)) end
	return L["Party %d"]:format(tonumber(index) or 0)
end

function M:SelfAlias()
	local own = Clean(self.db.selfAlias, 24)
	return own ~= "" and own or L["Player"]
end

-- The alias of a group member's token under the chosen scheme.
function M:TokenAlias(token)
	if token == "player" then return CustomAlias(UnitKey("player")) or self:SelfAlias() end
	local custom = CustomAlias(tokenKey[token] or UnitKey(token))
	if custom then return custom end
	local scheme = self.db.scheme
	if scheme == "custom" then return nil end
	if scheme == "class" then
		local className = Try(UnitClass, token)
		if type(className) == "string" and className ~= "" then return Numbered(className, token, ClassOf) end
	elseif scheme == "role" then
		local role = RoleOf(token)
		if role then return Numbered(L[ROLE_TEXT[role]], token, RoleOf) end
	end
	return NumberAlias(token)
end

-- Players outside your group.
function M:OtherAlias(key, className)
	local custom = CustomAlias(key)
	if custom then return custom end
	local others = self.db.others
	if others == "class" and type(className) == "string" and className ~= "" then return className end
	if others == "generic" then return L["Adventurer"] end
	return nil
end

-- The alias for a unit while Streamer Mode is on, else nil.
function M:AliasFor(unit)
	if not Streaming() or type(unit) ~= "string" then return nil end
	local token = GroupToken(unit)
	if token then return self:TokenAlias(token) end
	if not Try(UnitIsPlayer, unit) then return nil end
	return self:OtherAlias(UnitKey(unit), (Try(UnitClass, unit)))
end

-- Names EldoUI draws: `key` is the name user drawing it (Core/Names.lua).
-- The Tooltip module's lines ("Tooltip") follow Tooltips, everything else
-- (frames, nameplates, tags) follows Frames and nameplates.
local function Provider(unit, key)
	if not Streaming() then return nil end
	if key == "Tooltip" then
		if not M.db.tooltips then return nil end
	elseif not M.db.frames then
		return nil
	end
	return M:AliasFor(unit)
end
M.Provider = Provider

---------------------------------------------------------------------------
-- Chat: the shown sender of a line
---------------------------------------------------------------------------
function M:SenderAlias(sender, guid)
	if not Streaming() then return nil end
	sender, guid = Readable(sender), Readable(guid)
	if type(guid) == "string" and guid ~= "" then
		local token = byGUID[guid]
		if token then return self:TokenAlias(token) end
	end
	local key = M.Key(sender)
	if key then
		local mine = UnitKey("player")
		if key == mine then return self:TokenAlias("player") end
		for token, k in pairs(tokenKey) do
			if k == key then return self:TokenAlias(token) end
		end
	end
	local className
	if type(guid) == "string" and guid:find("^Player") and GetPlayerInfoByGUID then
		className = Try(GetPlayerInfoByGUID, guid)
	end
	if not key and not className then return nil end
	return self:OtherAlias(key, className)
end

-- Replace the name inside a label ("[Name]", "[icons|cffxxxxxxName|r]",
-- or "Name" in emotes); nil when the label has markup it does not know.
local function SwapLabel(label, alias)
	local open, inner, close = label:match("^(%[)(.*)(%])$")
	if not open then open, inner, close = "", label, "" end
	local lead = ""
	while true do
		local icon = inner:match("^|A.-|a") or inner:match("^|T.-|t")
		if not icon then break end
		lead = lead .. icon
		inner = inner:sub(#icon + 1)
	end
	local color, name, reset = inner:match("^(|c%x%x%x%x%x%x%x%x)(.-)(|r)$")
	if not color then
		if inner:find("|", 1, true) then return nil end
		color, name, reset = "", inner, ""
	end
	if name == "" or name:find("|", 1, true) then return nil end
	return open .. lead .. color .. alias .. reset .. close
end
M.SwapLabel = SwapLabel

local PLAYER_LINK = "|Hplayer:.-|h.-|h"

function M:ChatLine(text, args)
	if not (Streaming() and self.db.chat) or IsSecret(text) or type(text) ~= "string" or type(args) ~= "table" then return nil end
	local alias = self:SenderAlias(args[2], args[12])
	if not alias then return nil end
	local first, last = text:find(PLAYER_LINK)
	if not first then return nil end
	local link = text:sub(first, last)
	local payload, label = link:match("^|Hplayer:(.-)|h(.*)|h$")
	if not label then return nil end
	local newLabel = SwapLabel(label, alias)
	if not newLabel or newLabel == label then return nil end
	return text:sub(1, first - 1) .. ("|Hplayer:%s|h%s|h"):format(payload, newLabel) .. text:sub(last + 1)
end

local chatHooked = false
local function HookChat()
	if chatHooked then return end
	local chat = E:GetModule("Chat")
	if not (chat and chat.AddLineHook) then return end
	chatHooked = true
	-- After the sender details (order 50): icons and the name format are
	-- already in the label, the alias replaces only the name.
	chat:AddLineHook(55, function(text, r, g, b, _, args)
		local result = M:ChatLine(text, args)
		if result then return result, r, g, b end
		return nil
	end)
end

---------------------------------------------------------------------------
-- Tooltips: the name line at the top
---------------------------------------------------------------------------
-- The unit of a unit tooltip: GetUnit where the tooltip has it, else the
-- GUID of the tooltip data, else the mouse-over unit. Secrets give nil.
local function TooltipUnit(tooltip, data)
	local unit
	if tooltip.GetUnit then
		local ok, _, token = pcall(tooltip.GetUnit, tooltip)
		unit = ok and Readable(token) or nil
	end
	if not unit and type(data) == "table" and UnitTokenFromGUID then
		local guid = Readable(data.guid)
		unit = guid and Try(UnitTokenFromGUID, guid) or nil
	end
	if not unit and Try(UnitExists, "mouseover") then unit = "mouseover" end
	return type(unit) == "string" and unit or nil
end

function M:StyleTooltip(tooltip, data, unit)
	if not (Streaming() and self.db.tooltips) or not tooltip or tooltip ~= GameTooltip then return end
	if E.FrameCheck(tooltip, "IsForbidden") then return end
	unit = unit or TooltipUnit(tooltip, data)
	if not unit then return end
	local alias = self:AliasFor(unit)
	if not alias then return end
	local line = _G[tooltip:GetName() .. "TextLeft1"]
	if not line then return end
	local text = Readable(line:GetText())
	local name = Try(UnitName, unit)
	if type(text) == "string" and type(name) == "string" and name ~= "" then
		local at, stop = text:find(name, 1, true)
		if at then
			line:SetText(text:sub(1, at - 1) .. alias .. text:sub(stop + 1))
			return
		end
	end
	-- A secret or reworded line: the whole line becomes the alias.
	line:SetText(alias)
end

local tooltipHooked = false
local function HookTooltip()
	if tooltipHooked then return end
	if not (TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType and Enum.TooltipDataType.Unit) then return end
	tooltipHooked = true
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
		local ok, err = pcall(M.StyleTooltip, M, tooltip, data)
		if not ok then geterrorhandler()(err) end
	end)
end

---------------------------------------------------------------------------
-- Overhead names: the game's own CVars, put back on exit
---------------------------------------------------------------------------
M.OVERHEAD_CVARS = {
	friendly = { "UnitNameOwn", "UnitNameFriendlyPlayerName", "UnitNamePlayerGuild", "UnitNameGuildTitle" },
	all = { "UnitNameOwn", "UnitNameFriendlyPlayerName", "UnitNamePlayerGuild", "UnitNameGuildTitle", "UnitNameEnemyPlayerName" },
}

function M:CVarState()
	local data = E:GetGlobal("Streamer")
	if type(data) ~= "table" then return {} end
	data.cvars = type(data.cvars) == "table" and data.cvars or {}
	return data.cvars
end

function M:ApplyOverhead()
	local wanted = {}
	if Streaming() then
		for _, name in ipairs(self.OVERHEAD_CVARS[self.db.overhead] or {}) do wanted[name] = true end
	end
	local state = self:CVarState()
	E:RunOutOfCombat(function()
		for name in pairs(wanted) do
			if state[name] == nil and C_CVar and C_CVar.GetCVar then state[name] = C_CVar.GetCVar(name) end
			E:SetCVar(name, "0", CVAR_OWNER)
		end
		for name, value in pairs(state) do
			if not wanted[name] then
				if E:CVarOwner(name) == CVAR_OWNER then
					E:RestoreCVar(name, CVAR_OWNER)
				elseif value ~= nil then
					-- Another part of EldoUI remembered the old value first:
					-- put back the one Streamer Mode found.
					E:SetCVar(name, value, CVAR_OWNER)
				end
				state[name] = nil
			end
		end
	end)
end

---------------------------------------------------------------------------
-- The switch
---------------------------------------------------------------------------
function M:Refresh()
	self:ScanGroup()
	E:RefreshNames()
	local infoBar = E:GetModule("InfoBar")
	if infoBar and infoBar.active and infoBar.RefreshDataText then infoBar:RefreshDataText("Streamer") end
end

function M:SetStreaming(on)
	if not self.db then return end
	self.db.streaming = on and true or false
	if not self.active and on then E:SetModuleEnabled("Streamer", true) end
	self:ApplyOverhead()
	self:Refresh()
end

function M:Toggle()
	self:SetStreaming(not Streaming())
end

E:AddCommand("streamer", "[on | off | toggle]  Streamer Mode: aliases in place of real names", function(arg)
	if not M.db then return end
	local word = strtrim(arg or ""):lower()
	if word == "on" then
		M:SetStreaming(true)
	elseif word == "off" then
		M:SetStreaming(false)
	elseif word == "" or word == "toggle" then
		M:Toggle()
	else
		-- A typo never flips Streamer Mode while live.
		E:Print(L["Usage: /eui streamer [on | off | toggle]"])
		return
	end
	E:Print(Streaming() and L["Streamer Mode is on."] or L["Streamer Mode is off."])
end)

E:RegisterDataText("Streamer", {
	title = "Streamer Mode",
	text = function()
		if Streaming() then return E:Highlight(L["STREAMER"]) end
		return E:TokenHex(E.tokens.text.secondary) .. L["Streamer off"] .. "|r"
	end,
	tooltip = function(tooltip)
		E.UIKit.TipTitle(tooltip, L["Streamer Mode"])
		local c = E.tokens.text.secondary
		tooltip:AddLine(Streaming() and L["On: EldoUI shows aliases in place of real names."] or L["Off: real names show."], c[1], c[2], c[3], true)
	end,
	hint = { Key("Click"), Key("turn Streamer Mode on or off") },
	onClick = function() M:Toggle() end,
})

---------------------------------------------------------------------------
-- Alias editor (the chat list editor's look)
---------------------------------------------------------------------------
function M:OpenAliasEditor()
	local chat = E:GetModule("Chat")
	if not (chat and chat.OpenListEditor) then return end
	return chat:OpenListEditor({
		key = "streamerAliases",
		title = L["Streamer aliases"],
		help = L["Your own alias for a character, used in every scheme. Leave the alias empty and click Set to remove one."],
		emptyText = L["No aliases yet."],
		items = function() return M:AliasRows() end,
		text = function(row) return row.alias, row.name end,
		controls = {
			{ kind = "button", label = L["Remove"], width = 60, click = function(row) M:SetAlias(row.name, "") end },
		},
		add = { hint = L["Character, e.g. Name-Realm"], hint2 = L["Alias, e.g. Healer friend"], button = L["Set"],
			func = function(name, alias) return M:SetAlias(name, alias) end },
		status = function()
			local count = 0
			for _ in pairs(M.db.aliases) do count = count + 1 end
			return ("%d / %d"):format(count, MAX_ALIASES)
		end,
	})
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function M:OnInitialize()
	E:RegisterGlobal("Streamer", { cvars = {} })
end

function M:OnEnable()
	E:SetNameAliasProvider(Provider)
	HookChat()
	HookTooltip()
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_NAME_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do
		self:RegisterEvent(event, function()
			if M.active then M:ScanGroup() end
		end)
	end
	self:ApplyOverhead()
	self:Refresh()
end

function M:OnDisable()
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_NAME_UPDATE", "PLAYER_ROLES_ASSIGNED" }) do
		self:UnregisterEvent(event)
	end
	E:SetNameAliasProvider(nil)
	self:ApplyOverhead()
	E:RefreshNames()
end

function M:OnProfileChanged()
	aliasSource = nil
	self:ApplyOverhead()
	self:Refresh()
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Hides names in what EldoUI draws: unit, group and nameplate texts, tooltips and chat senders. Other frames keep the real names." },
	{ type = "toggle", key = "streaming", label = "Streamer Mode", desc = "On: EldoUI shows aliases in place of real character names. Also /eui streamer, or a click on the Streamer datatext." },
	{ type = "header", label = "Aliases" },
	{ type = "select", key = "scheme", label = "Group members show as",
		values = { number = "Party 1-4, Raid 1-40", class = "Their class (Priest, Priest 2)", role = "Their role (Healer, Tank)", custom = "Only your own aliases" },
		order = { "number", "class", "role", "custom" },
		desc = "How party and raid members are named. A member without a role or class shown falls back to Party or Raid and a number. \"Only your own aliases\" renames only the characters on your alias list." },
	{ type = "input", key = "selfAlias", label = "Your alias", desc = "What EldoUI shows for you. Empty shows Player. At most 24 letters." },
	{ type = "select", key = "others", label = "Players outside your group",
		values = { keep = "Real name", class = "Their class", generic = "Adventurer" }, order = { "keep", "class", "generic" },
		desc = "Names of players who are not in your group: nameplates, target and tooltip, chat senders. Characters on your alias list always show their alias." },
	{ type = "execute", label = "Edit aliases", desc = "Your own alias per character (for example a guild friend), used before every scheme above.",
		func = function() M:OpenAliasEditor() end, keywords = "custom names" },
	{ type = "header", label = "Where" },
	{ type = "toggle", key = "frames", label = "Frames and nameplates", desc = "EldoUI's unit frames, group frames and nameplates, and every [name] text tag." },
	{ type = "toggle", key = "tooltips", label = "Tooltips", desc = "The name line of a player's tooltip and the Target and Targeted by lines." },
	{ type = "toggle", key = "chat", label = "Chat senders", desc = "The sender name of new chat lines. Needs the Chat module's message extras. Whisper, Reply and the right-click menu keep working." },
	{ type = "select", key = "overhead", label = "Overhead names",
		values = { keep = "Game setting", friendly = "Hide your own and friendly names", all = "Hide all player names" },
		order = { "keep", "friendly", "all" },
		desc = "Hides the names over characters in the world through the game's own name settings while Streamer Mode is on, and puts your settings back when it goes off. Off by default (Game setting)." },
}

E:RegisterStyles("Streamer", {
	{ key = "Anonymous", title = "Anonymous", desc = "Party and raid numbers, Adventurer for everyone else, on frames, tooltips and chat.",
		settings = { scheme = "number", others = "generic", frames = true, tooltips = true, chat = true, overhead = "keep" } },
	{ key = "ClassNames", title = "Class names", desc = "Group members and other players by their class.",
		settings = { scheme = "class", others = "class", frames = true, tooltips = true, chat = true, overhead = "keep" } },
	{ key = "CustomAliases", title = "Custom aliases", desc = "Only the characters on your alias list are renamed.",
		settings = { scheme = "custom", others = "keep", frames = true, tooltips = true, chat = true, overhead = "keep" } },
	{ key = "PartyNumbers", title = "Party numbers", desc = "Party and raid numbers for your group; other players keep their names.",
		settings = { scheme = "number", others = "keep", frames = true, tooltips = true, chat = true, overhead = "keep" } },
	{ key = "Hidden", title = "Everything hidden", acts = true,
		desc = "Numbers and Adventurer everywhere, and every player name over characters hidden through the game's settings (put back when Streamer Mode goes off).",
		settings = { scheme = "number", others = "generic", frames = true, tooltips = true, chat = true, overhead = "all" } },
})
