-- EldoUI Macros: macros that name a lower spell rank.
--
-- A macro can name a rank, such as "/cast Frostbolt(Rank 3)". After the
-- player learns Rank 4, that macro keeps casting Rank 3. EldoUI finds such
-- macros and offers "Update to Rank 4":
--   * the macro editor marks the line and shows the button;
--   * the spell rank check (/eui rankcheck) lists the macro in chat.
--
-- Only the rank number changes, and only on the player's click: the macro
-- text is the player's own, so nothing is ever rewritten on its own.
-- The update is written with EditMacro out of combat (the game refuses it
-- in combat), never past the game's 255 characters, and the old text is
-- kept until logout so Undo can put it back.
--
-- What counts as a rank: "Name(<word> <number>)" in a /cast, /use,
-- /castsequence, /castrandom or /userandom line, also behind [conditions]
-- and in ";" and "," lists. The word is read as any text before the
-- number, so the rank text of every client language works, and the word
-- the macro already uses stays. A spell without a rank is left alone (the
-- game casts its highest rank already), and so are:
--   * spells on the Action Bars exclude list ("Keep these at their rank");
--   * a rank in a macro that also names the same spell without a rank
--     (a lower rank next to the full spell is kept on purpose).
-- The highest known rank comes from the spellbook (Modules/ActionBars/
-- Ranks.lua), which works while the Action Bars module is off.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local M = E.Macros

local issecret = issecretvalue or function() return false end

---------------------------------------------------------------------------
-- Reading ranks out of a macro
---------------------------------------------------------------------------
-- Commands whose arguments name spells, and those whose names are a
-- comma list.
local SPELL_COMMANDS = { "CAST", "USE", "CASTSEQUENCE", "CASTRANDOM", "USERANDOM" }
local LISTS = { CASTSEQUENCE = true, CASTRANDOM = true, USERANDOM = true }

-- Every spelling of those commands the client knows (lower case, without
-- the slash) -> the command, so a macro written with a translated command
-- is read too.
local commandCache
local function SpellCommands()
	if commandCache then return commandCache end
	local known = {}
	for _, command in ipairs(SPELL_COMMANDS) do
		known[command:lower()] = command
		for n = 1, 12 do
			local value = rawget(_G, "SLASH_" .. command .. n)
			if type(value) == "string" and value:sub(1, 1) == "/" then known[value:sub(2):lower()] = command end
		end
	end
	commandCache = known
	return known
end

-- Splits `text` (starting at `offset` in the body) on `;` and, for lists,
-- on `,`, never inside [conditions]: { { from, to } } in body positions.
local function Segments(text, offset, list)
	local out, depth, start = {}, 0, 1
	for i = 1, #text do
		local char = text:sub(i, i)
		if char == "[" then
			depth = depth + 1
		elseif char == "]" then
			depth = math.max(0, depth - 1)
		elseif depth == 0 and (char == ";" or (list and char == ",")) then
			out[#out + 1] = { offset + start - 1, offset + i - 2 }
			start = i + 1
		end
	end
	out[#out + 1] = { offset + start - 1, offset + #text - 1 }
	return out
end

-- One spell name of a segment: the conditions, "reset=" and "!" in front
-- are skipped. Returns the name, its first position in the body, and the
-- rank word, number and number positions when it names a rank.
local function ReadSegment(body, from, to)
	local text = body:sub(from, to)
	local pos = 1
	while true do
		local skip = text:match("^%s*%b[]()", pos)
		if not skip then break end
		pos = skip
	end
	pos = text:match("^%s*()", pos)
	local reset = text:match("^reset=%S+%s*()", pos)
	if reset then pos = reset end
	if text:sub(pos, pos) == "!" then pos = pos + 1 end
	local rest = text:sub(pos)
	-- Name(<word> <number>), with only spaces after it.
	local name, open, word, numStart, number, numEnd = rest:match("^(.-)%s*()%(([^%d%(%)]-)()(%d+)()%s*%)%s*$")
	if name and strtrim(word or "") ~= "" and strtrim(name) ~= "" then
		local base = from + pos - 1
		return strtrim(name), base, {
			word = strtrim(word), rank = tonumber(number),
			startPos = base + numStart - 1, endPos = base + numEnd - 2, open = base + open - 1,
		}
	end
	name = strtrim(rest)
	if name ~= "" then return name, from + pos - 1, nil end
	return nil
end

-- Every "Name(Rank N)" in a macro body:
--   { { name, rank, word, startPos, endPos, line } }, in body order.
-- startPos and endPos are the rank number's first and last character in
-- `body`, so an update replaces only the number. The second result holds
-- the lower-case names the macro names without a rank.
function E:MacroRankRefs(body)
	local refs, plain = {}, {}
	if type(body) ~= "string" or issecret(body) or body == "" then return refs, plain end
	local commands = SpellCommands()
	local lineStart, lineNo = 1, 0
	while lineStart <= #body + 1 do
		lineNo = lineNo + 1
		local lineEnd = body:find("\n", lineStart, true) or (#body + 1)
		local line = body:sub(lineStart, lineEnd - 1)
		local command, argPos = line:match("^%s*/(%S+)%s*()")
		local which = command and commands[command:lower()]
		if which and argPos <= #line then
			local args = line:sub(argPos)
			local offset = lineStart + argPos - 1
			for _, segment in ipairs(Segments(args, offset, LISTS[which])) do
				local name, _, rank = ReadSegment(body, segment[1], segment[2])
				if name and rank then
					refs[#refs + 1] = { name = name, rank = rank.rank, word = rank.word, startPos = rank.startPos,
						endPos = rank.endPos, open = rank.open, line = lineNo, command = which }
				elseif name and not tonumber(name) then
					plain[name:lower()] = true
				end
			end
		end
		if lineEnd > #body then break end
		lineStart = lineEnd + 1
	end
	return refs, plain
end

---------------------------------------------------------------------------
-- Which ranks can move up
---------------------------------------------------------------------------
local function Bars()
	local module = E:GetModule("ActionBars")
	return module and module.RankScan and module or nil
end

-- The spellbook is read once and kept for a moment: the editor checks on
-- every key press. A change to the spellbook reads it again.
local scanCache, scanTime, lowerNames
local SCAN_SECONDS = 2

function E:ForgetMacroRankScan()
	scanCache, scanTime, lowerNames, commandCache = nil, nil, nil, nil
end

local function Scan()
	local bars = Bars()
	if not bars then return nil end
	local now = GetTime and GetTime() or 0
	if scanCache and scanTime and now - scanTime < SCAN_SECONDS then return scanCache, lowerNames end
	scanCache, scanTime = bars:RankScan(), now
	lowerNames = {}
	for name in pairs(scanCache.best) do lowerNames[name:lower()] = name end
	return scanCache, lowerNames
end

local owner = {}
for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE" }) do
	E:RegisterEvent(event, function() E:ForgetMacroRankScan() end, owner)
end

-- The ranks of a macro body that are below the highest rank the player
-- knows of that spell: { { name, rank, to, word, startPos, endPos, line,
-- spell } }, and the body with those numbers raised (nil when nothing
-- moves).
function E:MacroRankChanges(body)
	local changes = {}
	if type(body) ~= "string" or issecret(body) or not body:find("%(.-%d") then return changes, nil end
	local refs, plain = self:MacroRankRefs(body)
	if #refs == 0 then return changes, nil end
	local scan, names = Scan()
	if not scan then return changes, nil end
	local bars = Bars()
	for _, ref in ipairs(refs) do
		local lower = ref.name:lower()
		local name = names[lower]
		local top = name and scan.best[name]
		if top and not scan.excluded[lower] and not plain[lower] then
			local to = scan.rank[top] or bars.SpellRankNumber(top)
			if to and ref.rank < to then
				changes[#changes + 1] = { name = ref.name, rank = ref.rank, to = to, word = ref.word, startPos = ref.startPos,
					endPos = ref.endPos, open = ref.open, line = ref.line, spell = top }
			end
		end
	end
	if #changes == 0 then return changes, nil end
	-- Replace from the end, so earlier positions stay right.
	local new = body
	for i = #changes, 1, -1 do
		local change = changes[i]
		new = new:sub(1, change.startPos - 1) .. change.to .. new:sub(change.endPos + 1)
	end
	return changes, new
end

-- "Rank 4", in the macro's own word.
function E:MacroRankText(change, rank)
	return ("%s %d"):format(change.word, rank or change.to)
end

-- The button label for a list of changes: "Update to Rank 4" when every
-- change goes to the same rank, otherwise "Update spell ranks".
function E:MacroRankButtonText(changes)
	local first = changes and changes[1]
	if not first then return L["Update spell ranks"] end
	for _, change in ipairs(changes) do
		if change.to ~= first.to or change.word ~= first.word then return L["Update spell ranks"] end
	end
	return L["Update to %s"]:format(self:MacroRankText(first))
end

-- Every account and character macro with a rank that can move up:
-- { { index, name, character, body, changes, newBody } }.
function E:MacroRankUpdates()
	local list = {}
	if not (M and M.List) then return list end
	for _, macro in ipairs(M:List()) do
		local changes, newBody = self:MacroRankChanges(macro.body)
		if newBody then
			list[#list + 1] = { index = macro.index, name = macro.name, character = macro.character, body = macro.body,
				changes = changes, newBody = newBody }
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Updating, and Undo for this session
---------------------------------------------------------------------------
-- macro index -> { name, before, after }: the text before the last update.
local undo = {}

local function Say(text)
	E:Print(text)
	return text
end

-- What the update changes, in words: "Frostbolt(Rank 3) to Rank 4".
local function Changed(changes)
	local parts = {}
	for _, change in ipairs(changes) do
		parts[#parts + 1] = L["%s to %s"]:format(("%s(%s)"):format(change.name, E:MacroRankText(change, change.rank)),
			E:MacroRankText(change))
	end
	return table.concat(parts, ", ")
end

-- Write a new body into a macro, keeping its name and icon.
local function Write(index, body)
	if not EditMacro then return nil end
	local ok, newIndex = pcall(EditMacro, index, nil, nil, body)
	if not ok then return nil end
	if M.RefreshBlizzard then M:RefreshBlizzard() end
	return tonumber(newIndex) or index
end

-- Raise the lower ranks of macro `index` to the highest rank known.
-- Returns the macro's index (it can move when the game sorts the list) or
-- nil, and the line written in chat.
function E:UpdateMacroRanks(index)
	if InCombatLockdown() then return nil, Say(L["Macros change out of combat. Update the spell rank after combat."]) end
	local macro = M and M.Get and M:Get(index)
	if not macro then return nil, Say(L["That macro is gone. Pick it again."]) end
	local changes, newBody = self:MacroRankChanges(macro.body)
	if not newBody then return nil, Say(L["Macro %s already names the highest spell ranks you know."]:format(macro.name)) end
	if #newBody > M.MAX_LENGTH then
		return nil, Say(L["Macro %s stays as it is: with the new rank it would have %d characters, and a macro holds %d. Shorten it first."] -- no-plural: always over the macro limit
			:format(macro.name, #newBody, M.MAX_LENGTH))
	end
	local newIndex = Write(index, newBody)
	if not newIndex then return nil, Say(L["The game did not save the macro."]) end
	undo[newIndex] = { name = macro.name, before = macro.body, after = newBody }
	if newIndex ~= index then undo[index] = nil end
	return newIndex, Say(L["Macro %s updated: %s."]:format(macro.name, Changed(changes)))
end

-- Find the macro an undo record belongs to: the same index when it still
-- holds the updated text, otherwise a macro of that name with that text.
local function UndoTarget(index)
	local record = undo[index]
	if not record then return nil end
	local macro = M:Get(index)
	if macro and macro.name == record.name and macro.body == record.after then return index, record end
	for _, other in ipairs(M:List()) do
		if other.name == record.name and other.body == record.after then return other.index, record end
	end
	return nil, record
end

-- Can the last rank update of macro `index` be put back?
function E:HasMacroRankUndo(index)
	return index ~= nil and UndoTarget(index) ~= nil
end

-- Put back the text macro `index` had before its last rank update.
-- Returns the macro's index or nil, and the line written in chat.
function E:UndoMacroRanks(index)
	if not undo[index] then return nil, Say(L["There is no macro rank update to undo."]) end
	if InCombatLockdown() then return nil, Say(L["Macros change out of combat. Undo the spell rank update after combat."]) end
	local target, record = UndoTarget(index)
	if not target then
		undo[index] = nil
		return nil, Say(L["Macro %s changed since the update, so it stays as it is."]:format(record.name))
	end
	local newIndex = Write(target, record.before)
	if not newIndex then return nil, Say(L["The game did not save the macro."]) end
	undo[index] = nil
	return newIndex, Say(L["Macro %s is back as it was."]:format(record.name))
end
