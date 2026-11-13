-- EldoUI My Adventure: notes, reminder triggers, the trigger suggested from the text, firing.
--
-- A note remembers where and when you wrote it (zone, subzone, map spot,
-- level). It can carry a reminder: "When you enter Goldshire", "At a
-- vendor", "When you reach level 30", "Next time you log in". A reminder
-- is a quiet card on screen with the note's text (and how many of each
-- linked item are in your bags); it never does anything in the game. Its
-- Done and Snooze buttons only change the note.
--
-- Saved in the journal (EldoUIDB.journal[charKey].notes, Store.lua):
--   { id, t, text, zone, subzone, level, map, x, y, pinned?, row?,
--     trigger? = { kind, target?, level? }, repeats?, armedAt?,
--     fired?, firedAt?, done?, snoozeUntil?, archived?, edited? }
--
-- Firing rules:
--   * State triggers (place, city, inn, rested, dungeon) fire on the edge:
--     from "not there" to "there". A reminder armed while you are already
--     there waits until you come back.
--   * Event triggers (vendor, mailbox, bank, auction house, flight master,
--     trainer, profession window) fire when the game opens that window.
--   * Level fires on the level-up that reaches it; login fires at the
--     next login after the note was armed.
--   * Nothing fires in the first 3 seconds after login; then places you
--     log in at count as arriving.
--   * Once: the reminder is done after it fires (and archived when
--     "Archive finished reminders" is on). Every time: it stays armed.
--   * Snooze: the reminder waits N:SNOOZE seconds, then fires again the
--     next time its trigger is true.
--   * Reminders show even while moments are off.
--
-- API (E.Adventure.Notes, also E.Journal.Notes):
--   N:Add(text, opts) -> note | nil, err   opts = { trigger, repeats, pinned, t }
--   N:Edit(id, text, opts) -> note | nil   empty text deletes it
--   N:Get(id), N:List()                    plain notes (newest first), waiting, archived
--   N:Waiting(), N:CountWaiting()          armed reminders (newest first)
--   N:Delete(id) -> trashID, N:Archive(id, on), N:SetPinned(id, on)
--   N:Done(id), N:RemindAgain(id), N:Snooze(id[, seconds])
--   N:Triggers()                           the trigger kinds, in menu order
--   N:TriggerLabel(trigger[, repeats])     "When you enter Goldshire · every time"
--   N:Suggest(text) -> trigger | nil       a trigger read from the text
--   N:Here()                               { zone, subzone, map, x, y, level }
--   N:WhereText(note[, coords]), N:Describe(note)
--   N:CheckState(), N:OnEvent(kind)        firing (on events)
--
-- Callbacks (J.RegisterCallback): "NoteSaved"(note), "ReminderFired"(note).
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the trigger kinds and their labels, the
-- suggestion order, edge firing with arming, and the "in your bags" line.
--
-- MIT License
--
-- Copyright (c) 2026 Ugge Zen
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
local _, E = ...
local L = E.L
local Key = E.Key
local A = E.Adventure
local J = E.Journal
local S = A.Store
local G = A.Goals

local Plain = A.Plain

local N = {}
A.Notes = N
J.Notes = N

N.MAX_LETTERS = 600
N.SNOOZE = 900            -- 15 minutes
N.READY_DELAY = 3         -- nothing fires this soon after login
N.ICON = "Interface/Icons/INV_Misc_Note_05"
N.ICON_REMINDER = "Interface/Icons/INV_Misc_PocketWatch_01"

local function Now()
	return time()
end

local function Rec()
	return J:Char()
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c, d, e, f, g = pcall(fn, ...)
	if not ok then return nil end
	return a, b, c, d, e, f, g
end

local function Fold(text)
	if type(text) ~= "string" or E:IsSecret(text) then return "" end
	return E:FoldText(strtrim(text))
end

local function Same(a, b)
	local x, y = Fold(a), Fold(b)
	return x ~= "" and x == y
end

local function Level()
	local level = Plain(UnitLevel("player"))
	return type(level) == "number" and level or 1
end

---------------------------------------------------------------------------
-- Where you are
---------------------------------------------------------------------------
function N:Here()
	local here = G.Here()
	local zone, sub = here[1], here[2]
	if type(zone) ~= "string" or zone == "" then zone = nil end
	if type(sub) ~= "string" or sub == "" or sub == zone then sub = nil end
	local out = { zone = zone, subzone = sub, level = Level() }
	local M = C_Map
	local map = M and Plain(Call(M.GetBestMapForUnit, "player"))
	if type(map) == "number" then
		out.map = map
		local pos = Call(M.GetPlayerMapPosition, map, "player")
		if type(pos) == "table" and pos.GetXY then
			local x, y = Call(pos.GetXY, pos)
			x, y = Plain(x), Plain(y)
			if type(x) == "number" and type(y) == "number" and (x > 0 or y > 0) then
				out.x, out.y = math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000
			end
		end
	end
	return out
end

-- "Goldshire, Elwynn Forest" (+ " (42.0, 65.0)" with coords).
function N:WhereText(note, coords)
	if type(note) ~= "table" then return "" end
	local parts = {}
	if note.subzone then parts[#parts + 1] = note.subzone end
	if note.zone then parts[#parts + 1] = note.zone end
	local text = table.concat(parts, ", ")
	if text == "" then text = L["Somewhere in Azeroth"] end
	if coords and note.x and note.y then text = ("%s (%.1f, %.1f)"):format(text, note.x * 100, note.y * 100) end
	return text
end

---------------------------------------------------------------------------
-- Trigger kinds. state = fn(trigger) -> bool (fires on the edge);
-- event = the game event that fires it; label = fn(trigger).
---------------------------------------------------------------------------
-- The capitals: the game gives zone names in the client's language, so
-- each name matches in English and in the language shown.
local CAPITALS = {
	Key("Orgrimmar"), Key("Undercity"), Key("Thunder Bluff"), Key("Silvermoon City"), Key("Stormwind City"), Key("Ironforge"),
	Key("Darnassus"), Key("The Exodar"), Key("Shattrath City"), Key("Dalaran"),
}
N.CAPITALS = CAPITALS

local function InCity()
	for _, name in ipairs(G.Here()) do
		for _, city in ipairs(CAPITALS) do
			if Same(name, city) or Same(name, L[city]) then return true end
		end
	end
	return false
end

local function Resting()
	return Plain(Call(rawget(_G, "IsResting"))) and true or false
end

local TRIGGERS, ORDER = {}, {}

local function Trigger(kind, def)
	def.kind = kind
	TRIGGERS[kind] = def
	ORDER[#ORDER + 1] = kind
end

Trigger("place", {
	label = function(trigger) return (L["When you enter %s"]):format(trigger.target or "") end,
	state = function(trigger)
		for _, name in ipairs(G.Here()) do
			if Same(name, trigger.target) then return true end
		end
		return false
	end,
	needsTarget = true,
})
Trigger("city", { label = function() return L["In any capital city"] end, state = InCity })
Trigger("inn", { label = function() return L["At an inn"] end, state = function() return Resting() and not InCity() end })
Trigger("rested", { label = function() return L["In a rested area (inn or city)"] end, state = Resting })
Trigger("dungeon", {
	label = function(trigger)
		if trigger.target then return (L["When you enter %s"]):format(trigger.target) end
		return L["In any dungeon"]
	end,
	state = function(trigger)
		local name = G.InstanceNow()
		if not name then return false end
		return trigger.target == nil or Same(name, trigger.target)
	end,
})
Trigger("merchant", { label = function() return L["At a vendor"] end, event = "MERCHANT_SHOW" })
Trigger("mail", { label = function() return L["At a mailbox"] end, event = "MAIL_SHOW" })
Trigger("bank", { label = function() return L["At the bank"] end, event = "BANKFRAME_OPENED" })
Trigger("auction", { label = function() return L["At the auction house"] end, event = "AUCTION_HOUSE_SHOW" })
Trigger("flight", { label = function() return L["At a flight master"] end, event = "TAXIMAP_OPENED" })
Trigger("trainer", { label = function() return L["At a trainer"] end, event = "TRAINER_SHOW" })
Trigger("profession", { label = function() return L["When you open a profession"] end, event = "TRADE_SKILL_SHOW" })
Trigger("level", {
	label = function(trigger) return (L["When you reach level %d"]):format(tonumber(trigger.level) or (Level() + 1)) end,
})
Trigger("login", { label = function() return L["Next time you log in"] end })

N.TRIGGERS, N.TRIGGER_ORDER = TRIGGERS, ORDER

local BY_EVENT = {}
for kind, def in pairs(TRIGGERS) do
	if def.event then BY_EVENT[def.event] = kind end
end
N.BY_EVENT = BY_EVENT

-- Menu order (the "place" kind comes only from a suggestion).
function N:Triggers()
	local list = {}
	for _, kind in ipairs(ORDER) do
		if kind ~= "place" then list[#list + 1] = TRIGGERS[kind] end
	end
	return list
end

function N:Trigger(kind)
	return TRIGGERS[kind]
end

-- A clean copy of a trigger, or nil when it is not a valid one.
local function CleanTrigger(trigger)
	if type(trigger) ~= "table" then return nil end
	local def = TRIGGERS[trigger.kind]
	if not def then return nil end
	local out = { kind = trigger.kind }
	if type(trigger.target) == "string" and strtrim(trigger.target) ~= "" then out.target = strtrim(trigger.target) end
	if def.needsTarget and not out.target then return nil end
	if trigger.kind == "level" then
		local level = math.floor(tonumber(trigger.level) or (Level() + 1))
		out.level = math.min(math.max(level, 2), 80)
	end
	return out
end
N.CleanTrigger = CleanTrigger

function N:TriggerLabel(trigger, repeats)
	local def = type(trigger) == "table" and TRIGGERS[trigger.kind]
	if not def then return L["No reminder"] end
	local text = def.label(trigger)
	if repeats then text = (L["%s · every time"]):format(text) end
	return text
end

-- "when you reach Westfall" for the saved line: the first letter lower case.
local function LowerFirst(text)
	return (text:gsub("^%u", string.lower))
end
N.LowerFirst = LowerFirst

---------------------------------------------------------------------------
-- The suggestion from the text: a place name you know (longest first, as
-- a whole word), "level N", then keywords (where-words before what-words).
---------------------------------------------------------------------------
local placeCache = { rev = -1, list = {} }

local function AddPlace(list, seen, name, kind)
	if type(name) ~= "string" or E:IsSecret(name) then return end
	name = strtrim(name)
	local key = Fold(name)
	if #name < 4 or seen[key] then return end
	seen[key] = true
	list[#list + 1] = { name = name, folded = key, kind = kind }
end

local function Places()
	local rec = Rec()
	local rev = rec and rec.rev or 0
	if placeCache.rev == rev and placeCache.list[1] then return placeCache.list end
	local list, seen = {}, {}
	for _, place in ipairs(J:Places()) do
		local fromRuns = place.sources and place.sources.instances
		AddPlace(list, seen, place.zone, fromRuns and "dungeon" or "place")
	end
	if rec then
		for zone, info in pairs(rec.zones) do
			AddPlace(list, seen, type(zone) == "string" and zone or S.String(rec, zone), "place")
			if type(info) == "table" and type(info.subs) == "table" then
				for sub in pairs(info.subs) do AddPlace(list, seen, type(sub) == "string" and sub or S.String(rec, sub), "place") end
			end
		end
	end
	for _, name in ipairs(G.Here()) do AddPlace(list, seen, name, "place") end
	local instance = G.InstanceNow()
	if instance then
		seen[Fold(instance)] = nil
		for position = #list, 1, -1 do
			if list[position].folded == Fold(instance) then table.remove(list, position) end
		end
		AddPlace(list, seen, instance, "dungeon")
	end
	table.sort(list, function(a, b) return #a.folded > #b.folded end)
	placeCache.rev, placeCache.list = rev, list
	return list
end
N.Places = Places

function N:ClearPlaceCache()
	placeCache.rev = -1
end

-- Keyword lists: one translated string each, in this order: words split
-- by spaces, or phrases split by semicolons.
local KEYWORDS = {
	{ "city", Key("city capital") },
	{ "inn", Key("inn") },
	{ "rested", Key("rested resting town") },
	{ "dungeon", Key("dungeon instance") },
	{ "auction", Key("auction ah") },
	{ "flight", Key("flight taxi") },
	{ "mail", Key("mailbox mail") },
	{ "bank", Key("bank") },
	{ "trainer", Key("trainer") },
	{ "merchant", Key("vendor merchant sell repair") },
	{ "profession", Key("smelt craft cook profession") },
	{ "login", Key("login; log in; next time i play") },
}
N.KEYWORDS = KEYWORDS

local Plainify = G.Plainify
N.Plainify = Plainify

local function HasWord(folded, word)
	word = Fold(word)
	if word == "" then return false end
	local start = 1
	while true do
		local first, last = folded:find(word, start, true)
		if not first then return false end
		local before = first > 1 and folded:sub(first - 1, first - 1) or " "
		local after = last < #folded and folded:sub(last + 1, last + 1) or " "
		if not before:match("[%w\128-\255]") and not after:match("[%w\128-\255]") then return true end
		start = first + 1
	end
end

function N:Suggest(text)
	if type(text) ~= "string" or E:IsSecret(text) then return nil end
	local folded = Fold(Plainify(text))
	if folded == "" then return nil end
	for _, place in ipairs(Places()) do
		if HasWord(folded, place.folded) then
			if place.kind == "dungeon" then return { kind = "dungeon", target = place.name } end
			return { kind = "place", target = place.name }
		end
	end
	local word = Fold(L["level"])
	local level = folded:match(word:gsub("%p", "%%%0") .. "%s+(%d+)")
	if level and tonumber(level) and tonumber(level) > 1 then return { kind = "level", level = tonumber(level) } end
	for _, entry in ipairs(KEYWORDS) do
		local list = L[entry[2]]
		local pattern = list:find(";", 1, true) and "[^;]+" or "%S+"
		for item in list:gmatch(pattern) do
			if HasWord(folded, strtrim(item)) then return { kind = entry[1] } end
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Reading notes
---------------------------------------------------------------------------
local function Notes()
	local rec = Rec()
	return rec and rec.notes or {}
end

function N:Get(id)
	id = tonumber(id)
	for position, note in ipairs(Notes()) do
		if type(note) == "table" and note.id == id then return note, position end
	end
	return nil
end

local function Waiting(note)
	return note.trigger ~= nil and not note.done and not note.archived
end
N.IsWaiting = Waiting

-- notes (newest first, not waiting, not archived), waiting (newest first),
-- archived (newest archived first).
function N:List()
	local notes, waiting, archived = {}, {}, {}
	for _, note in ipairs(Notes()) do
		if type(note) == "table" then
			if note.archived then
				archived[#archived + 1] = note
			elseif Waiting(note) then
				waiting[#waiting + 1] = note
			else
				notes[#notes + 1] = note
			end
		end
	end
	local function Newest(a, b) return (a.t or 0) > (b.t or 0) or ((a.t or 0) == (b.t or 0) and (a.id or 0) > (b.id or 0)) end
	table.sort(notes, Newest)
	table.sort(waiting, Newest)
	table.sort(archived, function(a, b) return (a.archived or 0) > (b.archived or 0) end)
	return notes, waiting, archived
end

function N:Waiting()
	local _, waiting = self:List()
	return waiting
end

function N:CountWaiting()
	local count = 0
	for _, note in ipairs(Notes()) do
		if type(note) == "table" and Waiting(note) then count = count + 1 end
	end
	return count
end

-- Pinned notes for the Journey (archived ones too: a pinned note stays on
-- your Journey until it is deleted).
function N:Pinned()
	local list = {}
	for _, note in ipairs(Notes()) do
		if type(note) == "table" and note.pinned then list[#list + 1] = note end
	end
	table.sort(list, function(a, b) return (a.t or 0) < (b.t or 0) end)
	return list
end

-- "(in your bags: 23 Copper Ore, 4 Linen Cloth)" for the items linked in a note.
function N:BagLine(text)
	if type(text) ~= "string" then return nil end
	local parts, seen = {}, {}
	for id, name in text:gmatch("|Hitem:(%d+)[^|]*|h%[(.-)%]|h") do
		id = tonumber(id)
		if id and not seen[id] then
			seen[id] = true
			local count = C_Item and Plain(Call(C_Item.GetItemCount, id, false)) or 0
			parts[#parts + 1] = ("%s %s"):format(BreakUpLargeNumbers(tonumber(count) or 0), name)
		end
	end
	if not parts[1] then return nil end
	return (L["(in your bags: %s)"]):format(table.concat(parts, ", "))
end

function N:Describe(note)
	local text = Plainify(note.text or "")
	local where = self:WhereText(note)
	local line = (L["%s, %s · level %d"]):format(G.DateText(note.t), where, note.level or 0)
	if note.trigger then line = line .. " · " .. self:TriggerLabel(note.trigger, note.repeats) end
	return text, line
end

---------------------------------------------------------------------------
-- Writing notes
---------------------------------------------------------------------------
local inside = {}         -- [note id] = state true/false this session
local ready = false
local sessionStart = Now()

local function Changed()
	local rec = Rec()
	if rec then S.Bump(rec) end
	A:MarkDirty("notes")
end

local function CleanText(text)
	if type(text) ~= "string" or E:IsSecret(text) then return "" end
	text = strtrim((text:gsub("\r", "")))
	text = E:Utf8Sub(text, N.MAX_LETTERS)
	return text
end

local function StateOf(note)
	local def = note.trigger and TRIGGERS[note.trigger.kind]
	if not (def and def.state) then return nil end
	local ok, on = pcall(def.state, note.trigger)
	return ok and on and true or false
end

-- A new or re-armed reminder notes the state it starts in: written in
-- Undercity, "when you reach Undercity" waits until you come back.
local function Arm(note)
	note.armedAt = Now()
	note.snoozeUntil = nil
	local on = StateOf(note)
	if on ~= nil then inside[note.id] = on end
end
N.Arm = Arm

-- The pinned row on the Journey (one "note" row per pinned note).
local function DropRow(rec, note)
	if not note.row then return end
	local _, position = J:Row(nil, note.row)
	if position then
		table.remove(rec.events, position)
		S.Bump(rec)
	end
	note.row = nil
end

local function PinRow(rec, note)
	if note.row and J:Row(nil, note.row) then return end
	local row = S.Write("note", { note = note.id, t = note.t, level = note.level, zone = note.zone or false,
		subzone = note.subzone, keep = true })
	note.row = row and row.seq or nil
end

function N:Add(text, opts)
	if not A:Running() then return nil, A:OffReason() or L["My Adventure is off."] end
	local rec = Rec()
	if not rec then return nil, L["The journal is not ready yet. Try again in a moment."] end
	text = CleanText(text)
	if text == "" then return nil, L["Write something first."] end
	opts = type(opts) == "table" and opts or {}
	local here = self:Here()
	local note = { id = S.NewId(rec), t = tonumber(opts.t) or Now(), text = text, zone = here.zone, subzone = here.subzone,
		level = here.level, map = here.map, x = here.x, y = here.y }
	local pinned = opts.pinned
	if pinned == nil then pinned = A.db and A.db.pinNewNotes end
	note.pinned = pinned and true or nil
	note.trigger = CleanTrigger(opts.trigger)
	note.repeats = note.trigger and opts.repeats and true or nil
	rec.notes[#rec.notes + 1] = note
	if note.trigger then Arm(note) end
	if note.pinned then PinRow(rec, note) end
	A:Fire("NoteSaved", note)
	Changed()
	return note
end

function N:Edit(id, text, opts)
	local rec = Rec()
	local note = self:Get(id)
	if not (rec and note) then return nil end
	text = CleanText(text)
	if text == "" then
		self:Delete(id)
		return nil, "deleted"
	end
	opts = type(opts) == "table" and opts or {}
	note.text = text
	note.edited = Now()
	if opts.trigger ~= nil then
		local trigger = opts.trigger ~= false and CleanTrigger(opts.trigger) or nil
		local changed = (trigger and trigger.kind) ~= (note.trigger and note.trigger.kind)
			or (trigger and trigger.target) ~= (note.trigger and note.trigger.target)
			or (trigger and trigger.level) ~= (note.trigger and note.trigger.level)
		note.trigger = trigger
		if changed and trigger then
			note.done, note.fired, note.firedAt = nil, nil, nil
			Arm(note)
		end
	end
	if opts.repeats ~= nil then note.repeats = note.trigger and opts.repeats and true or nil end
	if opts.pinned ~= nil then self:SetPinned(id, opts.pinned, true) end
	A:Fire("NoteSaved", note)
	Changed()
	return note
end

function N:SetPinned(id, on, quiet)
	local rec = Rec()
	local note = self:Get(id)
	if not (rec and note) then return false end
	note.pinned = on and true or nil
	if note.pinned then PinRow(rec, note) else DropRow(rec, note) end
	if not quiet then Changed() end
	return true
end

function N:Archive(id, on)
	return J:SetArchived("notes", tonumber(id), on)
end

function N:Delete(id)
	local rec = Rec()
	local note, position = self:Get(id)
	if not (rec and note) then return nil end
	table.remove(rec.notes, position)
	DropRow(rec, note)
	inside[note.id] = nil
	local trashID = S.TrashItem(rec, "note", note)
	Changed()
	return trashID
end

A:AddRestorer("note", function(rec, note)
	if type(note) ~= "table" then return end
	local at = #rec.notes + 1
	for position, other in ipairs(rec.notes) do
		if type(other) == "table" and (other.id or 0) > (note.id or 0) then
			at = position
			break
		end
	end
	table.insert(rec.notes, at, note)
	if note.pinned then PinRow(rec, note) end
	if note.trigger and not note.done then Arm(note) end
	A:MarkDirty("notes")
end)

-- Done: the reminder stops (a "every time" reminder too).
function N:Done(id)
	local note = self:Get(id)
	if not note then return false end
	note.done = true
	note.snoozeUntil = nil
	if A.db and A.db.archiveReminders and note.trigger then note.archived = note.archived or Now() end
	Changed()
	return true
end

-- Remind again: back to waiting, armed from where you are now.
function N:RemindAgain(id)
	local note = self:Get(id)
	if not (note and note.trigger) then return false end
	note.done, note.archived = nil, nil
	Arm(note)
	Changed()
	return true
end

-- Snooze: waits, then fires the next time its trigger is true.
function N:Snooze(id, seconds)
	local note = self:Get(id)
	if not (note and note.trigger) then return false end
	seconds = tonumber(seconds) or N.SNOOZE
	note.done, note.archived = nil, nil
	note.snoozeUntil = Now() + seconds
	inside[note.id] = false
	Changed()
	C_Timer.After(seconds + 0.1, function() N:CheckState() end)
	return true
end

---------------------------------------------------------------------------
-- Firing
---------------------------------------------------------------------------
local function Snoozed(note, now)
	return note.snoozeUntil and (now or Now()) < note.snoozeUntil
end

function N:Fire(note)
	if not (note and Waiting(note)) then return false end
	local db = A.db or {}
	local now = Now()
	note.firedAt = now
	note.fired = (tonumber(note.fired) or 0) + 1
	note.snoozeUntil = nil
	if not note.repeats then
		note.done = true
		if db.archiveReminders then note.archived = now end
	end
	Changed()
	A:Fire("ReminderFired", note)
	local text = note.text or ""
	local bags = self:BagLine(text)
	if bags then text = text .. "\n" .. bags end
	local id = note.id
	G.Announce({
		kind = "reminder", always = true, title = L["Reminder"], text = text, icon = N.ICON_REMINDER,
		seconds = db.reminderSeconds, sound = type(db.sounds) == "table" and db.sounds.reminder or nil,
		key = "journal-reminder-" .. tostring(id), note = id,
		actions = {
			{ label = L["Done"], tip = L["Stops this reminder."], func = function() N:Done(id) end },
			{ label = L["Snooze"], tip = L["Reminds you again in 15 minutes, the next time it applies."],
				func = function() N:Snooze(id) end },
		},
	})
	return true
end

-- State triggers: fire on the edge from false to true.
function N:CheckState()
	if not (ready and A:Running()) then return 0 end
	local fired, now = 0, Now()
	for _, note in ipairs(Notes()) do
		if type(note) == "table" and Waiting(note) then
			local on = StateOf(note)
			if on ~= nil then
				local was = inside[note.id]
				if on and not was and not Snoozed(note, now) then
					if self:Fire(note) then fired = fired + 1 end
				end
				if not Snoozed(note, now) or not on then inside[note.id] = on end
			elseif note.trigger.kind == "level" and note.snoozeUntil and not Snoozed(note, now)
				and Level() >= (note.trigger.level or 0) then
				if self:Fire(note) then fired = fired + 1 end
			end
		end
	end
	return fired
end

-- Event, level and login triggers.
function N:OnEvent(kind, value)
	if not (ready and A:Running()) then return 0 end
	local fired, now = 0, Now()
	for _, note in ipairs(Notes()) do
		if type(note) == "table" and Waiting(note) and note.trigger.kind == kind and not Snoozed(note, now) then
			local hit = true
			if kind == "level" then
				hit = (tonumber(value) or Level()) >= (note.trigger.level or 0)
			elseif kind == "login" then
				hit = (note.armedAt or 0) < sessionStart or note.snoozeUntil ~= nil
			end
			if hit and self:Fire(note) then fired = fired + 1 end
		end
	end
	return fired
end

local events = CreateFrame("Frame")
N.events = events
events:SetScript("OnEvent", function(_, event, ...)
	if BY_EVENT[event] then
		N:OnEvent(BY_EVENT[event])
	elseif event == "PLAYER_LEVEL_UP" then
		local level = Plain((...))
		N:OnEvent("level", type(level) == "number" and level or nil)
		N:CheckState()
	else
		if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then N:ClearPlaceCache() end
		N:CheckState()
	end
end)

N.EVENTS = { "MERCHANT_SHOW", "MAIL_SHOW", "BANKFRAME_OPENED", "AUCTION_HOUSE_SHOW", "TAXIMAP_OPENED", "TRAINER_SHOW",
	"TRADE_SKILL_SHOW", "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
	"ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING" }

-- After the first few seconds: places you log in at count as arriving,
-- then the login reminders.
function N:Ready()
	if ready then return end
	ready = true
	self:CheckState()
	self:OnEvent("login")
end

function N:IsReady()
	return ready
end

-- Start a fresh session.
function N:ResetSession(at)
	wipe(inside)
	ready = false
	sessionStart = at or Now()
end

A:AddPart("notes", {
	order = 31,
	start = function()
		for _, event in ipairs(N.EVENTS) do events:RegisterEvent(event) end
		C_Timer.After(N.READY_DELAY, function()
			if A:Running() then N:Ready() end
		end)
	end,
	stop = function()
		events:UnregisterAllEvents()
		ready = false
	end,
})
