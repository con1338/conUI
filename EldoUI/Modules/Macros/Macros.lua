-- EldoUI Macros: a wider macro editor with a live syntax check, a
-- condition builder and an icon search by spell or item name.
--
-- The checker reads the game's own command names (every SLASH_<NAME><n>
-- and EMOTE<n>_CMD<n> global the client defines, so secure commands such
-- as /cast count too), spell names through C_Spell.GetSpellInfo and item
-- names through C_Item. Unknown words are only warned about, never
-- blocked: a macro can name a spell you learn later. Two things are
-- errors: unbalanced brackets and more than 255 characters (the game cuts
-- a longer macro). A spell named at a lower rank than the player knows
-- ("Frostbolt(Rank 3)" after Rank 4) gets its own mark and an Update
-- button (Ranks.lua).
--
-- Macros are read with GetMacroInfo and written with EditMacro and
-- CreateMacro, out of combat only (the game refuses them in combat; the
-- editor says so instead of queuing a save). Running a macro stays the
-- player's own key press: EldoUI never runs one.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:NewModule("Macros", {
	title = "Macro Editor",
	category = "Interface",
	desc = "A wider macro editor next to Blizzard's macro window: a syntax check with hints, a condition builder and an icon search by spell or item name. Saving happens out of combat.",
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.Macros" },
	optionsPage = "module:Macros",
	presets = { "Code", "Compact", "Large", "Plain", "Theme" },
	reload = false,
	defaults = {
		autoOpen = false,      -- open the EldoUI editor with Blizzard's macro window
		colors = true,         -- colored commands, conditions and names in the check view
		warnings = "all",      -- all | errors
		font = "THEME",
		fontSize = 13,
		lineNumbers = true,
		chips = true,          -- the condition builder row
		transparent = false,
		window = {},
	},
})
E.Macros = M

M.MAX_LENGTH = 255
M.NAME_LENGTH = 16
M.AUTO_ICON = 134400 -- INV_Misc_QuestionMark: the game picks the icon from the macro's spell

---------------------------------------------------------------------------
-- Words the checker knows
---------------------------------------------------------------------------
-- Macro conditions (the part before ":" without "no"), hand-checked from
-- the game's macro documentation. Anything else is a warning, not an
-- error: the client decides.
M.CONDITIONS = {}
for _, word in ipairs({ "actionbar", "bar", "bonusbar", "btn", "button", "canexitvehicle", "channeling", "combat",
	"cursor", "dead", "equipped", "worn", "exists", "extrabar", "flyable", "flying", "form", "stance", "group",
	"harm", "help", "indoors", "known", "mod", "modifier", "mounted", "outdoors", "overridebar", "party", "pet",
	"petbattle", "possessbar", "raid", "resting", "shapeshift", "spec", "stealth", "swimming", "talent",
	"unithasvehicleui", "vehicleui", "target", "advflyable" }) do
	M.CONDITIONS[word] = true
end

M.METACOMMANDS = { show = true, showtooltip = true }

-- Commands whose arguments name spells or items.
local NAMED = { cast = true, use = true, castsequence = true, castrandom = true, userandom = true, equip = true }

-- Builder chips: one condition each, inserted at the cursor.
M.CHIPS = {
	{ "@mouseover", "Cast on the unit under the mouse." },
	{ "@target", "Cast on your target." },
	{ "@focus", "Cast on your focus." },
	{ "@player", "Cast on yourself." },
	{ "harm", "Only when the unit is hostile." },
	{ "help", "Only when the unit is friendly." },
	{ "exists", "Only when the unit exists." },
	{ "nodead", "Only when the unit is alive." },
	{ "combat", "Only in combat." },
	{ "nocombat", "Only out of combat." },
	{ "mod:shift", "Only while Shift is held." },
	{ "mod:ctrl", "Only while Ctrl is held." },
	{ "mod:alt", "Only while Alt is held." },
	{ "stance:1", "Only in the first stance or form." },
	{ "mounted", "Only while mounted." },
	{ "nomounted", "Only while not mounted." },
}

-- Every command the client defines, lower case without the slash.
local commandCache
function M:KnownCommands(force)
	if commandCache and not force then return commandCache end
	local known = {}
	for name, value in pairs(_G) do
		if type(name) == "string" and type(value) == "string" and value:sub(1, 1) == "/" then
			if name:match("^SLASH_.-%d+$") or name:match("^EMOTE%d+_CMD%d+$") then
				known[value:sub(2):lower()] = true
			end
		end
	end
	commandCache = known
	return known
end

function M:ForgetCommands()
	commandCache = nil
end

-- Does the game know this spell or item by name? nil when it can't tell.
function M:KnownName(name)
	if type(name) ~= "string" or name == "" then return nil end
	if tonumber(name) then return true end -- an item slot or bag and slot
	if C_Spell and C_Spell.GetSpellInfo then
		local ok, info = pcall(C_Spell.GetSpellInfo, name)
		if ok and info then return true end
	end
	if C_Item and C_Item.GetItemInfoInstant then
		local ok, id = pcall(C_Item.GetItemInfoInstant, name)
		if ok and id then return true end
	end
	-- "Frostbolt(Rank 3)": the spell's own name decides.
	local base = name:match("^(.-)%s*%([^%d%(%)]-%d+%s*%)$")
	if base and base ~= "" then return self:KnownName(base) end
	return false
end

---------------------------------------------------------------------------
-- The checker
---------------------------------------------------------------------------
local function Hex(kind)
	return E:TokenHex(E.tokens.text[kind])
end

local function Accent()
	return E.UIKit.AccentHex()
end

-- Splits "[cond][cond] arg; [cond] arg" into options: { conds = { "..." }, arg = "..." }.
local function Options(text)
	local options = {}
	for part in (text .. ";"):gmatch("(.-);") do
		local option = { conds = {}, raw = part }
		local rest = part:gsub("%[(.-)%]", function(inside)
			option.conds[#option.conds + 1] = inside
			return ""
		end)
		option.arg = strtrim(rest)
		options[#options + 1] = option
	end
	return options
end

local function CheckCondition(word)
	word = strtrim(word)
	if word == "" then return true end
	if word:sub(1, 1) == "@" then return true end
	local name = word:match("^([^:=]+)") or word
	name = strtrim(name):lower()
	if name:sub(1, 2) == "no" and M.CONDITIONS[name:sub(3)] then return true end
	return M.CONDITIONS[name] == true
end

-- Names a spell command line uses ("reset=" and "!" removed).
local function NamesOf(command, arg)
	local names = {}
	if arg == "" then return names end
	if command == "castsequence" then
		arg = arg:gsub("^reset=%S+%s*", "")
		for name in (arg .. ","):gmatch("(.-),") do names[#names + 1] = strtrim(name) end
	elseif command == "castrandom" or command == "userandom" then
		for name in (arg .. ","):gmatch("(.-),") do names[#names + 1] = strtrim(name) end
	else
		names[1] = arg
	end
	for i, name in ipairs(names) do
		name = name:gsub("^!", "")
		-- "/use 0 1" (bag and slot) and "/use 13" (slot) are numbers.
		if name:match("^%d+%s+%d+$") then name = "0" end
		names[i] = name
	end
	return names
end

-- Check a macro body. Returns { problems = { { line, kind, text } },
-- errors = n, warnings = n, ranks = n, length = n, colored = { line
-- texts }, rankChanges = { ... }, rankBody = the body with the ranks
-- raised or nil }. kind: "error", "warn" or "rank" (a lower spell rank).
function M:Check(body)
	body = type(body) == "string" and body or ""
	local result = { problems = {}, errors = 0, warnings = 0, ranks = 0, length = #body, colored = {} }
	local level = self.db and self.db.warnings or "all"
	local function Problem(line, kind, text)
		if kind == "warn" and level ~= "all" then return end
		result.problems[#result.problems + 1] = { line = line, kind = kind, text = text }
		if kind == "error" then
			result.errors = result.errors + 1
		elseif kind == "rank" then
			result.ranks = result.ranks + 1
		else
			result.warnings = result.warnings + 1
		end
	end
	-- Lower spell ranks, by line.
	local rankChanges, rankBody = {}, nil
	if E.MacroRankChanges then rankChanges, rankBody = E:MacroRankChanges(body) end
	result.rankChanges, result.rankBody = rankChanges, rankBody
	local ranksByLine = {}
	for _, change in ipairs(rankChanges) do
		ranksByLine[change.line] = ranksByLine[change.line] or {}
		table.insert(ranksByLine[change.line], change)
	end
	if #body > self.MAX_LENGTH then
		Problem(0, "error", L["%d characters: a macro holds %d, the game cuts the rest."]:format(#body, self.MAX_LENGTH))
	end
	local known = self:KnownCommands()
	local colors = not self.db or self.db.colors
	local lineNo = 0
	for line in (body .. "\n"):gmatch("(.-)\n") do
		lineNo = lineNo + 1
		local shown = line
		local trimmed = strtrim(line)
		if trimmed == "" then -- luacheck: ignore 542 (empty lines are fine)
		elseif trimmed:sub(1, 1) == "#" then
			local meta = trimmed:match("^#(%S+)")
			if not (meta and self.METACOMMANDS[meta:lower()]) then
				Problem(lineNo, "warn", L["Unknown line #%s: only #show and #showtooltip are read."]:format(meta or ""))
			end
			if colors then shown = Hex("secondary") .. line .. "|r" end
		elseif trimmed:sub(1, 1) ~= "/" then
			Problem(lineNo, "warn", L["This line has no /command, so it is said in chat."])
		else
			local opens, closes = select(2, trimmed:gsub("%[", "")), select(2, trimmed:gsub("%]", ""))
			local nested = trimmed:find("%[[^%]]*%[") ~= nil
			local command, rest = trimmed:match("^/(%S+)%s*(.-)$")
			command = (command or ""):lower()
			if opens ~= closes or nested then
				Problem(lineNo, "error", L["Brackets do not match: every [ needs its own ]."])
			end
			if not known[command] then
				Problem(lineNo, "warn", L["Unknown command /%s."]:format(command))
			end
			local badConds, badNames = {}, {}
			if opens == closes and not nested then
				for _, option in ipairs(Options(rest or "")) do
					for _, conds in ipairs(option.conds) do
						for word in (conds .. ","):gmatch("(.-),") do
							if not CheckCondition(word) then
								badConds[#badConds + 1] = strtrim(word)
								Problem(lineNo, "warn", L["Unknown condition %s."]:format(strtrim(word)))
							end
						end
					end
					if NAMED[command] then
						for _, name in ipairs(NamesOf(command, option.arg)) do
							if name ~= "" and self:KnownName(name) == false then
								badNames[#badNames + 1] = name
								Problem(lineNo, "warn", L["%s is not in your spellbook or bags (yet)."]:format(name))
							end
						end
					end
				end
			end
			local rankTexts = {}
			for _, change in ipairs(ranksByLine[lineNo] or {}) do
				local close = body:find(")", change.endPos, true) or change.endPos
				rankTexts[#rankTexts + 1] = body:sub(change.open, close)
				Problem(lineNo, "rank", L["%s is a lower rank: you know %s."]:format(
					("%s(%s)"):format(change.name, E:MacroRankText(change, change.rank)), E:MacroRankText(change)))
			end
			if colors then
				local cmdColor = known[command] and Accent() or Hex("warn")
				local head = "/" .. (trimmed:match("^/(%S+)") or "")
				local tail = trimmed:sub(#head + 1)
				tail = tail:gsub("%[(.-)%]", function(inside) return Hex("secondary") .. "[" .. inside .. "]|r" end)
				for _, name in ipairs(badNames) do
					local plain = name:gsub("%p", "%%%0")
					tail = tail:gsub(plain, Hex("warn") .. name .. "|r", 1)
				end
				for _, text in ipairs(rankTexts) do
					local plain = text:gsub("%p", "%%%0")
					tail = tail:gsub(plain, Hex("warn") .. text .. "|r", 1)
				end
				if opens ~= closes or nested then
					shown = Hex("bad") .. trimmed .. "|r"
				else
					shown = cmdColor .. head .. "|r" .. tail
				end
			end
		end
		result.colored[lineNo] = shown
	end
	-- A body ending in a newline has no extra empty line.
	if body ~= "" and body:sub(-1) == "\n" then result.colored[#result.colored] = nil end
	return result
end

---------------------------------------------------------------------------
-- Reading and writing macros
---------------------------------------------------------------------------
function M:FirstCharacterIndex()
	local consts = Constants and Constants.MacroConsts
	return (consts and consts.MAX_ACCOUNT_MACROS or rawget(_G, "MAX_ACCOUNT_MACROS") or 120) + 1
end

function M:Limits()
	local consts = Constants and Constants.MacroConsts
	return consts and consts.MAX_ACCOUNT_MACROS or rawget(_G, "MAX_ACCOUNT_MACROS") or 120,
		consts and consts.MAX_CHARACTER_MACROS or rawget(_G, "MAX_CHARACTER_MACROS") or 30
end

-- Every macro: { index, name, icon, body, character }.
function M:List()
	local list = {}
	if not (GetNumMacros and GetMacroInfo) then return list end
	local account, character = GetNumMacros()
	local first = self:FirstCharacterIndex()
	local function Add(index, perCharacter)
		local name, icon, body = GetMacroInfo(index)
		if type(name) == "string" then
			list[#list + 1] = { index = index, name = name, icon = icon, body = body or "", character = perCharacter }
		end
	end
	for index = 1, account or 0 do Add(index, false) end
	for index = first, first + (character or 0) - 1 do Add(index, true) end
	return list
end

function M:Get(index)
	if not (index and GetMacroInfo) then return nil end
	local name, icon, body = GetMacroInfo(index)
	if type(name) ~= "string" then return nil end
	return { index = index, name = name, icon = icon, body = body or "", character = index >= self:FirstCharacterIndex() }
end

-- Why a macro can't be saved now, or nil.
function M:SaveBlocked(name, body)
	if InCombatLockdown() then return L["Macros save out of combat. Your text stays in the editor."] end
	if type(name) ~= "string" or strtrim(name) == "" then return L["The macro needs a name."] end
	if #(body or "") > self.MAX_LENGTH then return L["%d characters: a macro holds %d."]:format(#body, self.MAX_LENGTH) end
	if self:Check(body).errors > 0 and #(body or "") <= self.MAX_LENGTH then
		-- Unbalanced brackets: the game saves it, but it would not work.
		return L["Fix the red lines first: the macro would not work."]
	end
end

-- Save into an existing macro. Returns the (maybe new) index, or nil and why.
function M:Save(index, name, icon, body)
	name = strtrim(name or ""):sub(1, self.NAME_LENGTH)
	local blocked = self:SaveBlocked(name, body)
	if blocked then return nil, blocked end
	if not (EditMacro and index and self:Get(index)) then return nil, L["That macro is gone. Pick it again."] end
	local ok, newIndex = pcall(EditMacro, index, name, icon, body)
	if not ok then return nil, L["The game did not save the macro."] end
	self:RefreshBlizzard()
	return tonumber(newIndex) or index
end

-- A copy in the same list (account or character). Returns the new index.
function M:Duplicate(index)
	if InCombatLockdown() then return nil, L["Macros save out of combat. Your text stays in the editor."] end
	local macro = self:Get(index)
	if not (macro and CreateMacro and GetNumMacros) then return nil, L["That macro is gone. Pick it again."] end
	local account, character = GetNumMacros()
	local maxAccount, maxCharacter = self:Limits()
	if (macro.character and (character or 0) >= maxCharacter) or (not macro.character and (account or 0) >= maxAccount) then
		return nil, L["That macro list is full."]
	end
	local name = (macro.name .. " 2"):sub(1, self.NAME_LENGTH)
	local ok, newIndex = pcall(CreateMacro, name, macro.icon or self.AUTO_ICON, macro.body, macro.character)
	if not ok or not newIndex then return nil, L["The game did not save the macro."] end
	self:RefreshBlizzard()
	return newIndex
end

-- Blizzard's macro window shows the new text too.
function M:RefreshBlizzard()
	local frame = rawget(_G, "MacroFrame")
	if frame and frame:IsShown() and frame.Update then
		pcall(frame.Update, frame)
		if frame.SelectMacro and frame.GetSelectedIndex then pcall(frame.SelectMacro, frame, frame:GetSelectedIndex()) end
	end
end

-- The macro Blizzard's window has selected, as a real index.
function M:BlizzardSelection()
	local frame = rawget(_G, "MacroFrame")
	if not (frame and frame.GetSelectedIndex and frame.GetMacroDataIndex) then return nil end
	local ok, selected = pcall(frame.GetSelectedIndex, frame)
	if not ok or not selected then return nil end
	local ok2, index = pcall(frame.GetMacroDataIndex, frame, selected)
	return ok2 and index or nil
end

---------------------------------------------------------------------------
-- Icon search: spellbook spells, bag items and the game's macro icons.
---------------------------------------------------------------------------
function M:IconSources()
	local list, seen = {}, {}
	local function Add(name, icon, kind)
		if not E:IsSecret(icon) and icon and not seen[icon] then
			seen[icon] = true
			list[#list + 1] = { name = name, icon = icon, kind = kind, folded = name and E:FoldText(name) or "" }
		end
	end
	local book = C_SpellBook
	if book and book.GetNumSpellBookSkillLines and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemInfo then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		for line = 1, book.GetNumSpellBookSkillLines() or 0 do
			local info = book.GetSpellBookSkillLineInfo(line)
			if type(info) == "table" and not info.shouldHide then
				for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local item = book.GetSpellBookItemInfo(slot, bank)
					if type(item) == "table" and type(item.name) == "string" and not item.isPassive then
						Add(item.name, item.iconID, "spell")
					end
				end
			end
		end
	end
	do
		local bags = E.BagCache
		for _, bag in ipairs(bags:BagIDs({ equipped = true })) do
			for slot = 1, bags:NumSlots(bag) do
				local info = bags:Info(bag, slot)
				if type(info) == "table" and info.iconFileID then
					local name = type(info.hyperlink) == "string" and info.hyperlink:match("%[(.-)%]") or nil
					if not name and info.itemID and C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(info.itemID) end
					Add(name, info.iconFileID, "item")
				end
			end
		end
	end
	-- The game's own macro icons have no names: they show when the search is empty.
	for _, getter in ipairs({ rawget(_G, "GetMacroIcons"), rawget(_G, "GetMacroItemIcons") }) do
		if type(getter) == "function" then
			-- The client fills the table it is given (GetMacroIcons(t));
			-- a returned table counts too.
			local filled = {}
			local ok, icons = pcall(getter, filled)
			if ok and type(icons) ~= "table" then icons = filled end
			if ok and type(icons) == "table" then
				for _, icon in ipairs(icons) do Add(nil, icon, "game") end
			end
		end
	end
	return list
end

-- Icons for a search text: named ones that match, or everything for "".
function M:SearchIcons(text, sources)
	sources = sources or self:IconSources()
	local query = E:FoldText(text or "")
	local out = { { name = L["Auto: the icon of the macro's spell"], icon = self.AUTO_ICON, kind = "auto" } }
	for _, source in ipairs(sources) do
		if query == "" or (source.folded ~= "" and source.folded:find(query, 1, true)) then out[#out + 1] = source end
	end
	return out
end
