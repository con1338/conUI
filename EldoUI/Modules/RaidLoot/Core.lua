-- EldoUI Raid Loot: soft reserves and TMB lists, shown where you
-- look at loot, and a GDKP ledger.
--
--   * Import a softres.it CSV (or JSON) export and a That's My BiS (TMB)
--     CSV (or JSON) export from a paste box. The readers below are EldoUI's
--     own: they find their columns by the header names, so a reordered or
--     extended export still reads. Bad strings get a message that says what
--     is missing.
--   * Item tooltips show "SR: Mira, Joe (+2)" and "TMB: Mira (prio 1)";
--     the group loot roll window (EldoUI's roll bars and Blizzard's roll
--     frames) shows the same line under the item; Loot Guide lists mark the
--     items you reserved.
--   * "Post reservations" sends one line to your group: one click, one
--     line, only with "Allow posting" on.
--   * The GDKP ledger (Ledger.lua): sales you add by hand, the pot, cuts and
--     the payout per player, exported as text.
--
-- Never built (they act for the player): loot distribution by rule,
-- auto-roll or auto-pass, bid handling, gold trades.
-- EldoUI never rolls: the roll buttons stay the player's own clicks.
local _, E = ...
local L = E.L

local MAX_TEXT = 1024 * 1024

local M = E:NewModule("RaidLoot", {
	title = "Raid Loot",
	category = "Group",
	desc = "Soft reserves and TMB lists on tooltips and roll windows, and a GDKP ledger for the pot and the split.",
	conflicts = { "Gargul", "SoftRes", "RCLootCouncil_Classic" },
	defaults = {
		enabled = true,
		tooltip = true,
		showSR = true,
		showTMB = true,
		rollLine = true,
		lootGuideMark = true,
		onlyGroup = false,
		maxNames = 5,
		highlightMe = true,
		allowPosting = false,
		organizerCut = 10,
		roundGold = true,
		transparent = false,
		rowHeight = 18,
		lineSize = 11,
		rollBackdrop = true,
	},
})
E.RaidLoot = M

local Clean = E.Plain
M.Clean = Clean

---------------------------------------------------------------------------
-- Saved lists (account-wide): soft reserves, TMB, ledgers
---------------------------------------------------------------------------
function M:Data()
	local data = E:GetGlobal("RaidLoot")
	if type(data) ~= "table" then return { sr = {}, tmb = {}, ledgers = {} } end
	for _, key in ipairs({ "sr", "tmb" }) do
		data[key] = type(data[key]) == "table" and data[key] or {}
		data[key].items = type(data[key].items) == "table" and data[key].items or {}
	end
	data.ledgers = type(data.ledgers) == "table" and data.ledgers or {}
	return data
end

---------------------------------------------------------------------------
-- Readers: CSV and JSON (EldoUI's own, data only)
---------------------------------------------------------------------------
-- The field separator: the one the first line uses most (comma, semicolon
-- or tab).
local function Separator(text)
	local first = text:match("^[^\r\n]*") or ""
	local best, most = ",", 0
	for _, sep in ipairs({ ",", ";", "\t" }) do
		local _, n = first:gsub(sep, "")
		if n > most then best, most = sep, n end
	end
	return best
end

-- CSV with quoted fields ("a, b" and "" for a quote) into rows of fields.
function M.ParseCSV(text)
	local sep = Separator(text)
	local rows, row, field = {}, {}, {}
	local i, n, quoted = 1, #text, false
	while i <= n do
		local c = text:sub(i, i)
		if quoted then
			if c == '"' then
				if text:sub(i + 1, i + 1) == '"' then
					field[#field + 1] = '"'
					i = i + 1
				else
					quoted = false
				end
			else
				field[#field + 1] = c
			end
		elseif c == '"' then
			quoted = true
		elseif c == sep then
			row[#row + 1] = table.concat(field)
			field = {}
		elseif c == "\n" or c == "\r" then
			if c == "\r" and text:sub(i + 1, i + 1) == "\n" then i = i + 1 end
			row[#row + 1] = table.concat(field)
			field = {}
			rows[#rows + 1] = row
			row = {}
		else
			field[#field + 1] = c
		end
		i = i + 1
	end
	if #field > 0 or #row > 0 then
		row[#row + 1] = table.concat(field)
		rows[#rows + 1] = row
	end
	-- Drop empty lines.
	local out = {}
	for _, r in ipairs(rows) do
		if #r > 1 or (r[1] and strtrim(r[1]) ~= "") then out[#out + 1] = r end
	end
	return out
end

-- A Unicode code point as UTF-8 bytes.
local function UTF8(code)
	local floor = math.floor
	if code < 0x80 then return string.char(code) end
	if code < 0x800 then return string.char(0xC0 + floor(code / 0x40), 0x80 + code % 0x40) end
	if code < 0x10000 then
		return string.char(0xE0 + floor(code / 0x1000), 0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
	end
	return string.char(0xF0 + floor(code / 0x40000), 0x80 + floor(code / 0x1000) % 0x40,
		0x80 + floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

-- A small JSON reader (objects, arrays, strings, numbers, true/false/null).
-- \u escapes become UTF-8, surrogate pairs included. Returns value or nil, error.
function M.ParseJSON(text)
	local pos = 1
	local Value
	local function Skip()
		pos = text:find("[^ \t\r\n]", pos) or (#text + 1)
	end
	local function Fail(what)
		error({ json = (L["bad JSON near character %d (%s)"]):format(pos, what) }, 0)
	end
	local ESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
	local function String()
		pos = pos + 1
		local out = {}
		while true do
			local c = text:sub(pos, pos)
			if c == "" then Fail(L["unfinished text"]) end
			if c == '"' then
				pos = pos + 1
				return table.concat(out)
			elseif c == "\\" then
				local e = text:sub(pos + 1, pos + 1)
				if e == "u" then
					local hex = text:sub(pos + 2, pos + 5)
					if not hex:match("^%x%x%x%x$") then Fail(L["bad escape"]) end
					local code = tonumber(hex, 16)
					pos = pos + 6
					if code >= 0xD800 and code <= 0xDBFF then
						-- A high surrogate: joined with the low one that follows.
						local low = text:match("^\\u(%x%x%x%x)", pos)
						low = low and tonumber(low, 16)
						if low and low >= 0xDC00 and low <= 0xDFFF then
							code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
							pos = pos + 6
						else
							code = 0xFFFD
						end
					elseif code >= 0xDC00 and code <= 0xDFFF then
						code = 0xFFFD -- a lone low surrogate
					end
					out[#out + 1] = UTF8(code)
				elseif ESC[e] then
					out[#out + 1] = ESC[e]
					pos = pos + 2
				else
					Fail(L["bad escape"])
				end
			else
				out[#out + 1] = c
				pos = pos + 1
			end
		end
	end
	local depth = 0
	function Value()
		Skip()
		local c = text:sub(pos, pos)
		if c == "{" then
			depth = depth + 1
			if depth > 40 then Fail(L["too deep"]) end
			pos = pos + 1
			local obj = {}
			Skip()
			if text:sub(pos, pos) == "}" then
				pos = pos + 1
				depth = depth - 1
				return obj
			end
			while true do
				Skip()
				if text:sub(pos, pos) ~= '"' then Fail(L["a name was expected"]) end
				local key = String()
				Skip()
				if text:sub(pos, pos) ~= ":" then Fail(L["':' was expected"]) end
				pos = pos + 1
				obj[key] = Value()
				Skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "}" then break end
				if d ~= "," then Fail(L["',' or '}' was expected"]) end
			end
			depth = depth - 1
			return obj
		elseif c == "[" then
			depth = depth + 1
			if depth > 40 then Fail(L["too deep"]) end
			pos = pos + 1
			local arr = {}
			Skip()
			if text:sub(pos, pos) == "]" then
				pos = pos + 1
				depth = depth - 1
				return arr
			end
			while true do
				arr[#arr + 1] = Value()
				Skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "]" then break end
				if d ~= "," then Fail(L["',' or ']' was expected"]) end
			end
			depth = depth - 1
			return arr
		elseif c == '"' then
			return String()
		elseif text:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif text:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif text:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		else
			local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
			if not num or num == "" then Fail(L["a value was expected"]) end
			pos = pos + #num
			return tonumber(num)
		end
	end
	local ok, result = pcall(function()
		local v = Value()
		Skip()
		if pos <= #text then Fail(L["text after the end"]) end
		return v
	end)
	if ok then return result end
	if type(result) == "table" and result.json then return nil, result.json end
	return nil, tostring(result)
end

---------------------------------------------------------------------------
-- Imports
---------------------------------------------------------------------------
local function Key(text)
	return (tostring(text or "")):lower():gsub("[%s_%-%.]", "")
end

-- The first header name of `aliases` found in the header row: its index.
local function Column(header, aliases)
	for _, alias in ipairs(aliases) do
		for index, name in ipairs(header) do
			if Key(name) == alias then return index end
		end
	end
end

local function PlayerName(text)
	text = strtrim(tostring(text or ""))
	if text == "" then return nil end
	return (text:gsub("%-.*$", ""))
end

local function ItemID(value)
	if type(value) == "number" then return value > 0 and math.floor(value) or nil end
	if type(value) ~= "string" then return nil end
	local id = tonumber(value:match("item:(%d+)") or value:match("^%s*(%d+)%s*$"))
	return id and id > 0 and id or nil
end
M.ItemID = ItemID

-- Columns by their header names (both exports, any order). Gaps: the
-- names come from the exports' public descriptions, see the report.
local SR_COLUMNS = {
	item = { "itemid", "id", "item" },
	name = { "name", "player", "character", "charactername" },
	plus = { "plus", "sr+", "srplus", "bonus" },
	note = { "note", "notes", "comment" },
}
local TMB_COLUMNS = {
	item = { "itemid", "item" },
	name = { "charactername", "character", "name", "player" },
	prio = { "sortorder", "order", "prio", "priority", "rank" },
	kind = { "type", "list" },
	received = { "receivedat", "received" },
}

-- Rows as objects: { [field] = value } from a CSV header or JSON objects.
local function Records(text, columns)
	local first = text:match("^%s*(.)")
	if first == "{" or first == "[" then
		local data, err = M.ParseJSON(text)
		if data == nil then return nil, err end
		local list = data
		if type(data) == "table" and #data == 0 then
			-- An object: the first array inside it (e.g. "reserved", "wishlist").
			list = nil
			for _, value in pairs(data) do
				if type(value) == "table" and #value > 0 then list = value break end
			end
		end
		if type(list) ~= "table" then return nil, L["no list of entries in this JSON"] end
		local out = {}
		for _, entry in ipairs(list) do
			if type(entry) == "table" then
				local record = {}
				local keys = {}
				for name in pairs(entry) do keys[#keys + 1] = name end
				for field, aliases in pairs(columns) do
					local index = Column(keys, aliases)
					if index then record[field] = entry[keys[index]] end
				end
				-- {"name": "Mira", "items": [12345, ...]}: one record per item.
				if type(entry.items) == "table" and record.item == nil then
					for _, item in ipairs(entry.items) do
						local copy = {}
						for k, v in pairs(record) do copy[k] = v end
						copy.item = type(item) == "table" and (item.id or item.itemId or item.item_id) or item
						out[#out + 1] = copy
					end
				else
					out[#out + 1] = record
				end
			end
		end
		return out
	end
	local rows = M.ParseCSV(text)
	if #rows < 2 then return nil, L["no header line and entries (an export has a first line with the column names)"] end
	local header = rows[1]
	local index, missing = {}, {}
	for field, aliases in pairs(columns) do index[field] = Column(header, aliases) end
	if not index.item then missing[#missing + 1] = L["item ID"] end
	if not index.name then missing[#missing + 1] = L["character name"] end
	if #missing > 0 then
		return nil, (L["the header has no column for %s"]):format(table.concat(missing, L[" and "]))
	end
	local out = {}
	for r = 2, #rows do
		local row, record = rows[r], {}
		for field, i in pairs(index) do record[field] = row[i] and strtrim(row[i]) or nil end
		out[#out + 1] = record
	end
	return out
end

-- Import a soft-reserve export. Returns count or nil, error.
function M:ImportSR(text)
	text = type(text) == "string" and strtrim(text) or ""
	if text == "" then return nil, L["the box is empty"] end
	if #text > MAX_TEXT then return nil, L["the text is too long"] end
	if not text:find("[,;\t{%[]") then
		return nil, L["this is not a CSV or JSON export (a compressed addon string can't be read: use the CSV export)"]
	end
	local records, err = Records(text, SR_COLUMNS)
	if not records then return nil, err end
	local items, count, skipped = {}, 0, 0
	for _, record in ipairs(records) do
		local id, name = ItemID(record.item), PlayerName(record.name)
		if id and name then
			items[id] = items[id] or {}
			table.insert(items[id], { name = name, plus = tonumber(record.plus) or 0, note = record.note ~= "" and record.note or nil })
			count = count + 1
		else
			skipped = skipped + 1
		end
	end
	if count == 0 then return nil, L["no entry has both an item ID and a name"] end
	local data = self:Data()
	data.sr = { items = items, importedAt = time(), count = count }
	self:Changed()
	return count, skipped
end

-- Import a TMB export (prio and wishlist rows; received rows are skipped).
function M:ImportTMB(text)
	text = type(text) == "string" and strtrim(text) or ""
	if text == "" then return nil, L["the box is empty"] end
	if #text > MAX_TEXT then return nil, L["the text is too long"] end
	if not text:find("[,;\t{%[]") then
		return nil, L["this is not a CSV or JSON export (a compressed addon string can't be read: use the CSV export)"]
	end
	local records, err = Records(text, TMB_COLUMNS)
	if not records then return nil, err end
	local items, count, skipped = {}, 0, 0
	for _, record in ipairs(records) do
		local id, name = ItemID(record.item), PlayerName(record.name)
		local kind = Key(record.kind)
		local received = kind == "received" or (record.received and record.received ~= "" and record.received ~= false)
		if id and name and not received then
			items[id] = items[id] or {}
			table.insert(items[id], { name = name, prio = tonumber(record.prio), wish = kind == "wishlist" or nil })
			count = count + 1
		else
			skipped = skipped + 1
		end
	end
	if count == 0 then return nil, L["no entry has an item ID and a character name (rows of received loot are left out)"] end
	for _, list in pairs(items) do
		table.sort(list, function(a, b)
			if (a.wish or false) ~= (b.wish or false) then return not a.wish end
			return (a.prio or 99) < (b.prio or 99)
		end)
	end
	local data = self:Data()
	data.tmb = { items = items, importedAt = time(), count = count }
	self:Changed()
	return count, skipped
end

function M:Clear(which)
	local data = self:Data()
	if which == "sr" or not which then data.sr = { items = {} } end
	if which == "tmb" or not which then data.tmb = { items = {} } end
	self:Changed()
end

function M:Count(which)
	local list = self:Data()[which]
	return list and list.count or 0
end

-- What "clear" asks and answers, per list (both = nil): whole sentences,
-- so every language can word them its own way.
local CLEAR_TEXTS = {
	sr = { ask = E.Key("Remove the soft reserves? This can't be undone. The TMB list and the ledger stay."), done = E.Key("Soft reserves cleared.") },
	tmb = { ask = E.Key("Remove the TMB list? This can't be undone. The soft reserves and the ledger stay."), done = E.Key("TMB list cleared.") },
	both = { ask = E.Key("Remove the soft reserves and the TMB list? This can't be undone. The ledger stays."), done = E.Key("Reserve lists cleared.") },
}

-- Asks, then clears the soft reserves, the TMB list or both (which = nil).
-- done(text) gets the line to show. Nothing to clear answers at once.
function M:ConfirmClear(which, done)
	local count = which and self:Count(which) or (self:Count("sr") + self:Count("tmb"))
	local texts = CLEAR_TEXTS[which or "both"]
	local ask, answer = L[texts.ask], L[texts.done]
	if count == 0 then
		done(L["There is nothing to clear."])
		return
	end
	E:ShowConfirm({ key = "ELDOUI_RAIDLOOT_CLEAR", title = L["Raid Loot"], text = ask,
		accept = L["Clear"], danger = true,
		onAccept = function()
			M:Clear(which)
			done(answer)
		end })
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
-- Your name as group members and senders carry it, without the surname
-- the display name may hold.
local function Me()
	return Clean(E:PlayerName())
end

-- Names in your group now: lower case -> the name as shown.
function M:GroupNames()
	local names = {}
	local me = Me()
	if me then names[me:lower()] = me end
	local prefix, count = "party", 4
	if IsInRaid and IsInRaid() then prefix, count = "raid", 40 end
	for i = 1, count do
		local name = Clean(UnitName(prefix .. i))
		if type(name) == "string" and name ~= "" then names[name:lower()] = name end
	end
	return names
end

-- The entries of `which` ("sr" or "tmb") for an item, after the filter.
function M:Entries(which, itemID)
	if not itemID then return {} end
	local list = self:Data()[which].items[itemID]
	if not list then return {} end
	if not self.db.onlyGroup then return list end
	local group, out = self:GroupNames(), {}
	for _, entry in ipairs(list) do
		if group[entry.name:lower()] then out[#out + 1] = entry end
	end
	return out
end

function M:ReservedByMe(itemID)
	local me = Me()
	if not (me and itemID) then return false end
	me = me:lower()
	for _, which in ipairs({ "sr", "tmb" }) do
		for _, entry in ipairs(self:Data()[which].items[itemID] or {}) do
			if entry.name:lower() == me then return which, entry end
		end
	end
	return false
end

-- points: add the player's DKP or EPGP standing (Points.lua). Only for
-- what EldoUI shows, never for the chat post: officer notes are private.
local function NameText(entry, which, me, points)
	local text = entry.name
	if which == "sr" and (entry.plus or 0) > 0 then
		text = ("%s (+%d)"):format(text, entry.plus)
	elseif which == "tmb" then
		if entry.wish then
			text = ("%s (%s)"):format(text, L["wish"])
		elseif entry.prio then
			text = ("%s (%s)"):format(text, (L["prio %d"]):format(entry.prio))
		end
	end
	if me and entry.name:lower() == me then
		text = E:TokenHex(E.media.accentText) .. text .. "|r"
	end
	local standing = points and M.PointsText and M.PointsText(entry.name)
	if standing then text = ("%s %s[%s]|r"):format(text, E:TextHex("secondary"), standing) end
	return text
end

-- "Mira, Joe (+2)" with at most maxNames names; nil when nobody.
function M:Line(which, itemID)
	local entries = self:Entries(which, itemID)
	if #entries == 0 then return nil end
	local me = self.db.highlightMe and Me()
	me = me and me:lower()
	local parts, max = {}, self.db.maxNames
	for i, entry in ipairs(entries) do
		if i > max then
			parts[#parts + 1] = (L["+%d more"]):format(#entries - max)
			break
		end
		parts[#parts + 1] = NameText(entry, which, me, true)
	end
	return table.concat(parts, ", "), #entries
end

-- Both lines for an item: { { label, text }, ... }
function M:Lines(itemID)
	local out = {}
	if self.db.showSR then
		local text = self:Line("sr", itemID)
		if text then out[#out + 1] = { L["SR"], text } end
	end
	if self.db.showTMB then
		local text = self:Line("tmb", itemID)
		if text then out[#out + 1] = { L["TMB"], text } end
	end
	return out
end

-- The one-line chat post (plain text, no colors).
function M:PostText(itemID, link)
	local parts = {}
	for _, which in ipairs({ "sr", "tmb" }) do
		local entries = self:Entries(which, itemID)
		if #entries > 0 then
			local names = {}
			for _, entry in ipairs(entries) do names[#names + 1] = NameText(entry, which, nil) end
			parts[#parts + 1] = (which == "sr" and L["SR"] or L["TMB"]) .. ": " .. table.concat(names, ", ")
		end
	end
	if #parts == 0 then return nil end
	local item = type(link) == "string" and link or (C_Item.GetItemNameByID and Clean(C_Item.GetItemNameByID(itemID))) or ("#" .. itemID)
	return item .. " - " .. table.concat(parts, " | ")
end

---------------------------------------------------------------------------
-- Posting: one click, one line
---------------------------------------------------------------------------
function M:GroupChannel()
	if IsInRaid and IsInRaid() then return "RAID" end
	if IsInGroup and IsInGroup() then return "PARTY" end
end

function M:Say(text)
	if not self.db.allowPosting then
		E:Print(L["Posting is off. Turn on \"Allow posting\" under Raid Loot first."])
		return false
	end
	local channel = self:GroupChannel()
	if not channel then
		E:Print(L["You are not in a group."])
		return false
	end
	if not text then return false end
	if not E:TryChatPost(text, channel) then
		E:Print(E:ChatRefusedText())
		return false
	end
	return true
end

function M:PostItem(itemID, link)
	local text = self:PostText(itemID, link)
	if not text then
		E:Print(L["Nobody reserved this item."])
		return false
	end
	return self:Say(text)
end

---------------------------------------------------------------------------
-- Tooltip section
---------------------------------------------------------------------------
local function TooltipLines(_, _, itemID, add)
	if not (M.active and M.db.tooltip) then return end
	itemID = Clean(itemID)
	if type(itemID) ~= "number" then return end
	local s, b = E.tokens.text.secondary, E.tokens.text.body
	for _, line in ipairs(M:Lines(itemID)) do
		add(line[1], line[2], s[1], s[2], s[3], b[1], b[2], b[3])
	end
end

M.TooltipLines = TooltipLines

---------------------------------------------------------------------------
-- Changes
---------------------------------------------------------------------------
function M:Changed()
	if self.RefreshRollLines then self:RefreshRollLines() end
	if self.RefreshWindow then self:RefreshWindow() end
	if self.RefreshLootGuide then self:RefreshLootGuide() end
end

function M:OnInitialize()
	E:RegisterGlobal("RaidLoot", { sr = { items = {} }, tmb = { items = {} }, ledgers = {} })
	if E.RegisterTooltipSection then
		E:RegisterTooltipSection("raidLoot", { order = 47, title = "Soft reserves and TMB", default = "always",
			desc = "Who soft-reserved an item (SR) and who has it on That's My BiS (TMB), from the lists you imported under Raid Loot.",
			item = TooltipLines })
	end
	if self.InitPoints then self:InitPoints() end
end

function M:OnEnable()
	if self.InstallHooks then self:InstallHooks() end
	if self.EnablePoints then self:EnablePoints() end
	self:Changed()
end

function M:OnDisable()
	if self.UnregisterEvents then self:UnregisterEvents() end
	if self.DisablePoints then self:DisablePoints() end
	if self.RefreshRollLines then self:RefreshRollLines() end
	if self.window and self.window:IsOpen() then self.window:Close() end
	if self.RefreshLootGuide then self:RefreshLootGuide() end
end

function M:OnProfileChanged()
	if not self.active then return end
	if self.window then
		self.window:ApplyPosition()
		-- "See-through window" and the style presets change the panel at once.
		self.window:Restyle()
	end
	-- The guild points settings may have changed (RefreshPoints redraws on a change).
	if self.RefreshPoints then self:RefreshPoints() end
	self:Changed()
end

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------
function M:Command(arg)
	arg = strtrim(arg or "")
	local word, rest = arg:match("^(%S*)%s*(.-)$")
	word = word:lower()
	if word == "" or word == "show" then
		self:OpenWindow("reserves")
	elseif word == "ledger" or word == "gdkp" then
		self:OpenWindow("ledger")
	elseif word == "sr" then
		self:ShowImport("sr")
	elseif word == "tmb" then
		self:ShowImport("tmb")
	elseif word == "clear" then
		local which = rest:lower()
		if which ~= "sr" and which ~= "tmb" and which ~= "" then
			E:Print(L["Usage: /eui raidloot clear [sr | tmb]"])
			return
		end
		self:ConfirmClear(which ~= "" and which or nil, function(text) E:Print(text) end)
	elseif word == "post" then
		local id = ItemID(rest)
		if not id then
			E:Print(L["Usage: /eui raidloot post <item link or ID>"])
			return
		end
		self:PostItem(id, rest:find("|H") and rest or nil)
	else
		E:Print(L["/eui raidloot [ledger | sr | tmb | clear [sr | tmb] | post <item>]"])
	end
end

E:AddCommand("raidloot", "[ledger | sr | tmb | clear | post <item>]  soft reserves, TMB and the GDKP ledger", function(arg)
	if not M.active then
		E:Print(E:ModuleOffHint("RaidLoot"))
		return
	end
	M:Command(arg)
end)

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Shows imported soft reserves and That's My BiS lists on item tooltips and loot rolls, and keeps a GDKP ledger. You roll and trade yourself." },
	{ type = "execute", label = "Open Raid Loot", testSafe = true, desc = "Opens the window with the reserve lists and the GDKP ledger (also /eui raidloot).",
		func = function() M:OpenWindow("reserves") end },
	{ type = "execute", label = "Import soft reserves", desc = "Paste a softres.it CSV or JSON export. It replaces the soft reserves you imported before.",
		func = function() M:ShowImport("sr") end },
	{ type = "execute", label = "Import TMB", desc = "Paste a That's My BiS CSV or JSON export. Prio and wishlist rows are kept, received loot is left out.",
		func = function() M:ShowImport("tmb") end },
	{ type = "execute", label = "Clear the lists", desc = "Removes the imported soft reserves and TMB lists. The ledger stays.", confirm = true,
		func = function() M:Clear() end },
	{ type = "header", label = "Where they show" },
	{ type = "toggle", key = "tooltip", label = "On item tooltips", desc = "Adds the SR and TMB lines to item tooltips. The Tooltip module's section list can also turn them off." },
	{ type = "toggle", key = "rollLine", label = "Under loot rolls", desc = "Adds the line under each group loot roll, on EldoUI's roll bars and on Blizzard's roll frames." },
	{ type = "toggle", key = "lootGuideMark", label = "Mark in the Loot Guide", desc = "Marks the items you reserved or have on TMB in Loot Guide lists (SR or TMB next to the item)." },
	{ type = "toggle", key = "showSR", label = "Soft reserves", desc = "Shows the soft-reserve line (SR: names, with +N for a bonus)." },
	{ type = "toggle", key = "showTMB", label = "TMB", desc = "Shows the That's My BiS line (TMB: names with their prio, or wish for a wishlist entry)." },
	{ type = "toggle", key = "onlyGroup", label = "Only your group", desc = "Lists only the players who are in your party or raid now." },
	{ type = "toggle", key = "highlightMe", label = "Highlight your name", desc = "Your own name shows in the accent color." },
	{ type = "range", key = "maxNames", label = "Names per line", min = 1, max = 10, step = 1, desc = "How many names a line lists before \"+N more\"." },
	{ type = "header", label = "Posting" },
	{ type = "toggle", key = "allowPosting", label = "Allow posting", desc = "Lets the Post buttons send one line to your raid or party: the reservations for an item, or the ledger totals. Each click sends one line." },
	{ type = "header", label = "GDKP ledger" },
	{ type = "range", key = "organizerCut", label = "Organizer cut", unit = "%", min = 0, max = 50, step = 1, desc = "The organizer's share of the pot for new ledgers. Each ledger keeps its own cuts." },
	{ type = "toggle", key = "roundGold", label = "Round payouts to gold", desc = "Shows payouts in whole gold, rounded down. The rest stays with the organizer." },
	{ type = "tab", label = "Look" },
	{ type = "range", key = "lineSize", label = "Roll line text size", min = 9, max = 14, step = 1, desc = "Text size of the SR and TMB line under each roll." },
	{ type = "toggle", key = "rollBackdrop", label = "Roll line background", desc = "A see-through background in your art style behind the line under each roll." },
	{ type = "range", key = "rowHeight", label = "Window row height", min = 16, max = 24, step = 1, desc = "Height of the rows in the reserve lists and the ledger." },
	{ type = "toggle", key = "transparent", label = "See-through window", desc = "The Raid Loot window lets the game show through a little. How much: General > Panel opacity." },
}

-- The window switch used to be "Solid window" (on by default); it is now
-- "See-through window", so a saved solid-off becomes see-through on.
function M.MigrateTransparent(profile)
	local modules = type(profile) == "table" and type(profile.modules) == "table" and profile.modules
	local own = modules and type(modules.RaidLoot) == "table" and modules.RaidLoot
	if not own then return end
	if own.solidWindow == false and own.transparent == nil then own.transparent = true end
	own.solidWindow = nil
end
E:RegisterProfileMigration(M.MigrateTransparent, "RaidLoot:transparent", 1)

E:RegisterStyles("RaidLoot", {
	{ key = "TooltipCompact", title = "Tooltip compact", desc = "Three names per line, your group only.",
		settings = { maxNames = 3, onlyGroup = true, lineSize = 10, rowHeight = 16 } },
	{ key = "TooltipDetailed", title = "Tooltip detailed", desc = "Ten names per line, everyone on the lists.",
		settings = { maxNames = 10, onlyGroup = false, lineSize = 12, rowHeight = 20 } },
	{ key = "LedgerDark", title = "Ledger dark", desc = "Tall rows on a solid window for the ledger.",
		settings = { rowHeight = 22, transparent = false, lineSize = 11, rollBackdrop = true } },
	{ key = "ForeverBronze", title = "Forever bronze", desc = "The roll line on a panel in your art style, bronze under WoW Forever.",
		settings = { rollBackdrop = true, lineSize = 12, rowHeight = 18, transparent = false } },
	{ key = "Minimal", title = "Minimal", desc = "Small text, no background, three names.",
		settings = { rollBackdrop = false, lineSize = 10, maxNames = 3, rowHeight = 16, transparent = true } },
})
