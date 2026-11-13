-- EldoUI My Adventure: the journal in the Journal window's search.
--
-- The window's search box (and the Search page) gets one more kind, "Your
-- journal", through LG:RegisterSearchProvider. It finds, every word
-- matched:
--   hub sections by name ("keepsakes", "journey")
--   places you have been (the journal's zones and every source's places)
--   your goals and notes by their text
--   moments of the Journey by what they say ("VanCleef", "Frost Nova"),
--     newest first, only those the detail setting shows
--   rows a section adds through its def.search(text)
-- A click opens the section, the place, the goal or note, or the moment in
-- the Journey (navigation only). Nothing shows while the journal is off.
--
--   A:SearchJournal(text) -> entries   the same list without the window
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal
local LG = E.LootGuide

local KIND = "journal"
local CAP = 50
local MOMENT_CAP = 30

local function Text(value)
	if E:IsSecret(value) or type(value) ~= "string" or value == "" then return nil end
	return value
end

local function Hits(folded, words)
	for _, word in ipairs(words) do
		if not folded:find(word, 1, true) then return false end
	end
	return true
end

-- Moment texts folded once per timeline (the timeline list is cached and
-- replaced when the journal or a source changes).
-- A settings change changes the rows shown: the index is built again.
local index = { rows = nil, list = nil, settings = nil }
local settingsRev = 0
if J.RegisterCallback then
	J.RegisterCallback(index, "Redraw", function(_, what)
		if type(what) == "table" and (what.settings or what.all) then settingsRev = settingsRev + 1 end
	end)
end

local function MomentIndex()
	local rows = J:Timeline()
	local settings = settingsRev
	if index.rows == rows and index.settings == settings then return index.list end
	local list = {}
	for position = #rows, 1, -1 do
		local row = rows[position]
		if row.kind ~= "note" and row.kind ~= "goalset" and J:Shown(row) then
			local title, sub, icon = A:LineText(row)
			if title and title ~= "" then
				list[#list + 1] = { row = row, title = title, sub = sub, icon = icon,
					fold = E:FoldText(title .. " " .. (sub or "")) }
			end
		end
	end
	index.rows, index.list, index.settings = rows, list, settings
	return list
end

local function Short(text, max)
	text = tostring(text or ""):gsub("[\r\n]+", " ")
	if #text <= max then return text end
	return text:sub(1, max - 3):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "..."
end

local function Add(out, entry)
	if #out >= CAP then return false end
	entry.provider = KIND
	out[#out + 1] = entry
	return true
end

local function Sections(out, words)
	for _, def in ipairs(A.Sections and A:Sections() or {}) do
		if A:SectionShown(def.key) and not def.link then
			local fold = E:FoldText(E:Translate(def.title) or def.key)
			for _, word in ipairs(def.words or {}) do fold = fold .. " " .. E:FoldText(word) end
			if Hits(fold, words) then
				Add(out, { name = E:Translate(def.title), sub = L["A page of My Adventure"], icon = def.icon or A.HUB_ICON, section = def.key })
			end
		end
	end
end

local function Places(out, words)
	local rec = J:Char()
	local seen = {}
	local function Try(zone)
		zone = Text(zone)
		if not zone or seen[zone] then return end
		seen[zone] = true
		if Hits(E:FoldText(zone), words) then
			Add(out, { name = zone, sub = L["A place in your journal"], icon = J.ICON and J.ICON.zone, address = J:Address("place", zone) })
		end
	end
	for zone in pairs(rec and type(rec.zones) == "table" and rec.zones or {}) do Try(zone) end
	for _, place in ipairs(J.Places and J:Places() or {}) do Try(place.zone) end
end

local function Goals(out, words)
	local rec = J:Char()
	for _, goal in ipairs(rec and rec.goals or {}) do
		local name = type(goal) == "table" and not goal.archived and Text(goal.name or goal.title or goal.text)
		if name and Hits(E:FoldText(name), words) then
			Add(out, { name = Short(name, 60), sub = goal.done and L["Goal reached"] or L["Goal"],
				icon = J.ICON and J.ICON.goal, address = J:Address("goal", goal.id) })
		end
	end
end

local function Notes(out, words)
	local rec = J:Char()
	for position = #(rec and rec.notes or {}), 1, -1 do
		local note = rec.notes[position]
		local text = type(note) == "table" and not note.archived and Text(note.text)
		if text and Hits(E:FoldText(text), words) then
			Add(out, { name = Short(text, 60), sub = L["Note"], icon = J.ICON and J.ICON.note, address = J:Address("note", note.id) })
		end
	end
end

local function SectionRows(out, text)
	for _, def in ipairs(A.Sections and A:Sections() or {}) do
		if type(def.search) == "function" and A:SectionShown(def.key) then
			local ok, rows = pcall(def.search, text)
			if not ok then
				geterrorhandler()(rows)
			elseif type(rows) == "table" then
				for _, item in ipairs(rows) do
					if type(item) == "table" and type(item.title) == "string" then
						if not Add(out, { name = item.title, sub = item.sub or E:Translate(def.title), icon = item.icon or def.icon,
							section = def.key, arg = item.arg }) then return end
					end
				end
			end
		end
	end
end

local function Moments(out, words)
	local count = 0
	local journey = A:SectionShown("journey")
	for _, entry in ipairs(MomentIndex()) do
		if count >= MOMENT_CAP then break end
		if Hits(entry.fold, words) then
			local row = entry.row
			local when = A.Fmt and type(row.t) == "number" and A.Fmt.Short(row.t)
			local sub = entry.sub ~= "" and entry.sub or nil
			if when then sub = sub and (sub .. " · " .. when) or when end
			local item = { name = entry.title, sub = sub or L["A moment in your journal"], icon = entry.icon }
			if journey and row.src == "journal" and row.seq then
				item.section, item.arg = "journey", { seq = row.seq }
			else
				item.address = J:LinkFor(row)
				if not item.address and journey then item.section, item.arg = "journey", { search = entry.title } end
			end
			if not (item.section or item.address) then item = nil end
			if item then
				if not Add(out, item) then return end
				count = count + 1
			end
		end
	end
end

function A:SearchJournal(text, words)
	if not (self:Running() and self.Sections) then return {} end
	if not words then
		words = {}
		for word in E:FoldText(text or ""):gmatch("%S+") do words[#words + 1] = word end
	end
	if #words == 0 then return {} end
	local out = {}
	Sections(out, words)
	Places(out, words)
	Goals(out, words)
	Notes(out, words)
	SectionRows(out, text or "")
	Moments(out, words)
	return out
end

local function Open(entry)
	if entry.section then return A:OpenSection(entry.section, entry.arg) end
	if entry.address then return J:Open(entry.address) end
	return false
end

LG:RegisterSearchProvider(KIND, {
	title = "Your journal",
	order = 10,
	search = function(words, _, text) return A:SearchJournal(text, words) end,
	open = Open,
})
