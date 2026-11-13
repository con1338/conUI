-- EldoUI Info Bar: the Mail block, for every character on the account.
--
-- The block says "New mail" when this character has new mail, as the game
-- shows it on the minimap, "Mail: N" when N of your characters have mail
-- waiting, and "No mail" in gray when there is none anywhere. Its tooltip
-- keeps the latest senders and lists each character with saved mail: the
-- letters, items and money, and the time until its first letter runs out.
-- A letter that runs out within the warning days turns the block yellow
-- (red under a day), and one local line in the chat frame at log-in says
-- where. A click opens nothing: mail opens only at a mailbox.
--
-- The letters come from the character store (Core/CharacterStore.lua),
-- which reads each character's inbox while its mailbox is open: the sender,
-- money, COD and the time each letter runs out, never the letter itself.
-- The end times are kept as time stamps, so the days left count down from
-- when they were read. Rules (Forever): read only; nothing opens, takes or
-- returns mail, and the log-in line is local, never sent.
local _, E = ...
local L = E.L
local M = E.modules.InfoBar

local DAY = 86400

M.defaults.mailWarnDays = 5  -- a letter that runs out within this many days warns
M.defaults.mailLogin = true  -- one local chat line at log-in about mail that runs out soon

local MailText = {}
M.mailText = MailText

local function Store() return E.Characters end
local function Now() return Store() and Store().Now() or time() end
local function Grey(text) return E:TextHex("secondary") .. text .. "|r" end

-- "3d 4h", "5h 12m", "42m".
function MailText.Duration(seconds)
	seconds = math.max(math.floor(seconds or 0), 0)
	local days, hours, minutes = math.floor(seconds / DAY), math.floor(seconds % DAY / 3600), math.floor(seconds % 3600 / 60)
	if days > 0 then return L["%dd %dh"]:format(days, hours) end
	if hours > 0 then return L["%dh %dm"]:format(hours, minutes) end
	return L["%dm"]:format(minutes)
end

-- The status of a letter that runs out in `left` seconds: "bad" under a
-- day, "warn" within the warning days, else nil.
function MailText.Status(left)
	if left < DAY then return "bad" end
	if left < (tonumber(M.db and M.db.mailWarnDays) or 5) * DAY then return "warn" end
	return nil
end

-- Every character with saved mail, soonest first:
-- { record, current, letters, items, money, cod, left (seconds to the first
-- letter's end), read (seconds since the mailbox was read) }.
function MailText.Characters()
	local store, rows = Store(), {}
	if not store then return rows end
	local now = Now()
	for _, key in ipairs(store:Keys("account")) do
		local record = store:Get(key)
		local meta = record and type(record.mailMeta) == "table" and record.mailMeta
		if meta then
			local row = { record = record, current = key == E.charKey, letters = 0, items = 0, money = 0, cod = 0 }
			for _, letter in ipairs(meta) do
				local ends = type(letter) == "table" and tonumber(letter.expires)
				if ends and ends > now then
					row.letters = row.letters + 1
					row.items = row.items + (tonumber(letter.items) or 0)
					row.money = row.money + (tonumber(letter.money) or 0)
					if (tonumber(letter.cod) or 0) > 0 then row.cod = row.cod + 1 end
					row.left = math.min(row.left or math.huge, ends - now)
				end
			end
			if record.mailUpdated then row.read = math.max(now - record.mailUpdated, 0) end
			if row.letters > 0 then rows[#rows + 1] = row end
		end
	end
	table.sort(rows, function(a, b) return a.left < b.left end)
	return rows
end

-- The worst status over every character's letters, and the rows.
function MailText.Worst(rows)
	local worst
	for _, row in ipairs(rows) do
		local status = MailText.Status(row.left)
		if status == "bad" then return "bad" end
		worst = worst or status
	end
	return worst
end

local function HasNew() return HasNewMail and HasNewMail() and true or false end

local function NameText(row)
	local record = row.record
	local name = record.name or "?"
	if record.realmKey and E.RealmKey and record.realmKey ~= E:RealmKey() then name = name .. " - " .. record.realmKey end
	name = E:WrapClassColor(record.class, name)
	if row.current then name = name .. " *" end
	-- What the character saw is as old as its last mailbox visit.
	if row.read and row.read >= DAY then name = name .. "  " .. Grey(L["read %s ago"]:format(MailText.Duration(row.read))) end
	return name
end

local function RowText(row)
	local parts = { E:Plural(row.letters, "%d letter", "%d letters"):format(row.letters) }
	if row.items > 0 then parts[#parts + 1] = E:Plural(row.items, "%d item", "%d items"):format(row.items) end
	if row.money > 0 then parts[#parts + 1] = E:FormatMoney(row.money) end
	if row.cod > 0 then parts[#parts + 1] = E:StatusText("warn", L["COD"]) end
	local left = MailText.Duration(row.left)
	local status = MailText.Status(row.left)
	parts[#parts + 1] = status and E:StatusText(status, left) or left
	return table.concat(parts, Grey(" · "))
end

E:RegisterDataText("Mail", {
	events = { "UPDATE_PENDING_MAIL", "MAIL_INBOX_UPDATE", "MAIL_CLOSED" },
	poll = true,
	interval = 60, -- the days left count down
	text = function()
		local rows = MailText.Characters()
		local status = MailText.Worst(rows)
		local text
		if HasNew() then
			text = L["New mail"]
		elseif #rows > 0 then
			text = L["Mail: %d"]:format(#rows)
		else
			return Grey(L["No mail"])
		end
		if status then return E:StatusText(status, text) end
		return HasNew() and (E:TextHex("good") .. text .. "|r") or M.Value(text)
	end,
	tooltip = function(tooltip)
		local Kit = E.UIKit
		if HasNew() then
			-- All three: `f and f()` would keep only the first.
			local senders = GetLatestThreeSenders and { GetLatestThreeSenders() } or {}
			if #senders == 0 then
				Kit.TipTitle(tooltip, L["You have mail waiting."])
			else
				Kit.TipText(tooltip, L["New mail from:"])
				for _, sender in ipairs(senders) do Kit.TipTitle(tooltip, sender) end
			end
		end
		local rows = MailText.Characters()
		if #rows == 0 then
			if not HasNew() then Kit.TipText(tooltip, L["No mail on any of your characters."]) end
		else
			if HasNew() then tooltip:AddLine(" ") end
			Kit.TipText(tooltip, L["Saved mail, as each character last saw its mailbox:"])
			for _, row in ipairs(rows) do tooltip:AddDoubleLine(NameText(row), RowText(row), 1, 1, 1, 1, 1, 1) end
			if MailText.Worst(rows) then
				tooltip:AddLine(" ")
				Kit.TipText(tooltip, L["Letters that run out go back to the sender or are deleted. Log in on that character and empty its mailbox."])
			end
		end
		tooltip:AddLine(" ")
		Kit.TipText(tooltip, L["Mail opens at a mailbox; the game has no remote mailbox."])
	end,
})

---------------------------------------------------------------------------
-- The log-in line
---------------------------------------------------------------------------
-- The characters whose mail runs out within the warning days, as one line,
-- or nil.
function MailText.LoginLine()
	local soon = {}
	for _, row in ipairs(MailText.Characters()) do
		if MailText.Status(row.left) then
			local record = row.record
			soon[#soon + 1] = ("%s (%s)"):format(E:WrapClassColor(record.class, record.name or "?"), MailText.Duration(row.left))
		end
	end
	if #soon == 0 then return nil end
	return L["Mail runs out soon on %s."]:format(table.concat(soon, ", "))
end

-- Whether the line is due: the setting is on, the Mail block is placed, and
-- the Characters module's own mail reminder (which says the same) is off.
function MailText.LoginWanted()
	if not (M.db and M.db.mailLogin and M.UsesDataText and M.UsesDataText("Mail")) then return false end
	local characters = E.modules and E.modules.Characters
	if characters and characters.active and characters.db and characters.db.warnMail then return false end
	return true
end

function MailText:Enable()
	if self.loginDone then return end
	self.loginDone = true
	-- Once per session, after the log-in messages.
	C_Timer.After(10, function()
		if not (M.active and MailText.LoginWanted()) then return end
		local line = MailText.LoginLine()
		if line then E:Print(line) end
	end)
end

M:AddExtra(MailText)

M.InsertOptions({
	{ type = "header", label = "Mail" },
	{ type = "range", key = "mailWarnDays", label = "Mail warning: days before", min = 1, max = 29, step = 1,
		desc = "The Mail block turns yellow when a letter on any of your characters runs out within this many days, and red under a day." },
	{ type = "toggle", key = "mailLogin", label = "Mail warning at log-in",
		desc = "One chat line at log-in when a letter on any of your characters runs out soon. Only while the Mail block is on a bar or panel, and not when the Characters module's mail reminder says it." },
})
