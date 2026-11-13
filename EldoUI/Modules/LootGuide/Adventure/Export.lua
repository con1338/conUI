-- EldoUI My Adventure: one document model: Markdown, printable page, plain text, the !EUJ1! share kind, chat-box share.
--
-- The journal as a document to read anywhere: chapters by level with the
-- same moments the Journey page shows (and the same settings: detail,
-- finds from, armor types), then the goals, notes, quests and abandoned
-- quests. Three formats come from that one model: Markdown, a printable
-- web page (HTML, print it to PDF in a browser) and plain text. The
-- backup code ("!EUJ1!", Backup.lua) and the runs code ("!EUJR1!",
-- Runs.lua) show in the same copy box. The document lists your runs too.
-- Nothing is sent anywhere: every format goes to E:ShowCopyBox and the
-- player copies it out.
--
-- Companion names (the "met", "together" and "group quest" rows) are left
-- out unless the caller asks for them (opts.companions).
--
-- API (E.Adventure.Export):
--   X:Document([charKey, opts]) -> doc   { title, subtitle, sections =
--                                         { { title, lines = { { when,
--                                         text, sub } } } } }
--   X:Markdown([charKey, opts]), X:HTML([charKey, opts]), X:Text([charKey, opts])
--   X:Build(format[, charKey, opts]) -> text, err
--   X:Show(format[, charKey, opts])      "code", "runs", "markdown", "html" or "text"
--   X.Strip(text)                        links, colors and textures removed
--
-- Portions adapted from Forever Journal by Ugge Zen, MIT License (see
-- THIRD_PARTY_NOTICES.md): the document model (chapters by level, the
-- same moments as the journey, repeats in the same minute folded into one
-- line), the three formats and the printable page's layout.
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

local ipairs, pairs, type, tostring, tonumber = ipairs, pairs, type, tostring, tonumber

local X = {}
A.Export = X

X.FORMATS = { "code", "runs", "markdown", "html", "text" }
X.COMPANIONS = { met = true, together = true, groupquest = true }
X.FOOTER = "EldoUI Journal · WoW: Forever" -- no-L

---------------------------------------------------------------------------
-- Text helpers
---------------------------------------------------------------------------
-- Game text to plain text: links to their name, colors and textures gone.
function X.Strip(text)
	if type(text) ~= "string" or E:IsSecret(text) then return "" end
	text = text:gsub("|H.-|h%[?(.-)%]?|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
		:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|n", " ")
	return (text:gsub("%s+", " "):match("^%s*(.-)%s*$"))
end
local Strip = X.Strip

local function Day(t) return tonumber(t) and E:LongDay(t, nil, true) or "" end
local function Clock(t) return tonumber(t) and E:ShortDate(t) or "" end

---------------------------------------------------------------------------
-- The document
---------------------------------------------------------------------------
local function Subtitle(who, rec)
	local bits = {}
	if who.race or who.class then
		bits[#bits + 1] = table.concat({ Strip(who.race), Strip(who.class) }, " "):match("^%s*(.-)%s*$")
	end
	if who.level then bits[#bits + 1] = (L["level %d"]):format(who.level) end
	local line = table.concat(bits, ", ")
	if rec and tonumber(rec.started) then
		local since = (L["Kept since %s."]):format(Day(rec.started))
		line = line ~= "" and (line .. ". " .. since) or since
	elseif line ~= "" then
		line = line .. "."
	end
	return line
end

-- The zone of a chapter: where you spent the most of that level.
local function ChapterPlace(rec, level)
	local info = rec and type(rec.levels) == "table" and rec.levels[level]
	if type(info) ~= "table" or type(info.zones) ~= "table" then return nil end
	local best, most = nil, 0
	for zone, count in pairs(info.zones) do
		if type(zone) == "string" and (tonumber(count) or 0) > most then best, most = zone, tonumber(count) end
	end
	return best and Strip(best) or nil
end

-- Lines of one chapter, sorted, with the same thing in the same minute as
-- one line ("Looted Linen Cloth ×4"), and a place line the text names left out.
local function Fold(raw)
	table.sort(raw, function(a, b)
		if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
		return (a.seq or 0) < (b.seq or 0)
	end)
	local lines = {}
	for _, line in ipairs(raw) do
		line.when = Clock(line.t)
		local last = lines[#lines]
		if last and last.when == line.when and last.base == line.text and last.sub == line.sub then
			last.n = last.n + 1
			last.text = last.base .. " ×" .. last.n
		else
			line.base, line.n = line.text, 1
			if line.sub ~= "" and line.text:find(line.sub, 1, true) then line.sub = "" end
			lines[#lines + 1] = line
		end
	end
	for _, line in ipairs(lines) do line.base, line.n, line.t, line.seq = nil, nil, nil, nil end
	return lines
end

local function RowLine(row)
	local title, sub = A:LineText(row)
	local line = { t = row.t, seq = row.seq, text = Strip(title), sub = Strip(sub or "") }
	local note = A.KeepNote and A:KeepNote(row)
	if type(note) == "string" and note ~= "" then line.note = Strip(note) end
	return line
end

local function GoalLines(rec)
	local G = A.Goals
	local lines = {}
	for _, goal in ipairs(rec.goals or {}) do
		if type(goal) == "table" then
			local ok, text = false, nil
			if G and G.Describe then ok, text = pcall(G.Describe, G, goal) end
			if not ok or type(text) ~= "string" then text = tostring(goal.label or goal.name or goal.kind or "?") end
			local sub = goal.archived and L["archived"] or ""
			lines[#lines + 1] = { when = Day(goal.doneAt or goal.t), text = Strip(text), sub = sub }
		end
	end
	return lines
end

local function NoteLines(rec)
	local N = A.Notes
	local lines = {}
	for _, note in ipairs(rec.notes or {}) do
		if type(note) == "table" then
			local ok, text, where = false, nil, nil
			if N and N.Describe then ok, text, where = pcall(N.Describe, N, note) end
			if not ok or type(text) ~= "string" then text, where = note.text, nil end
			local sub = Strip(where or "")
			if note.archived then sub = sub ~= "" and (sub .. " · " .. L["archived"]) or L["archived"] end
			lines[#lines + 1] = { when = Clock(note.t), text = Strip(text), sub = sub }
		end
	end
	return lines
end

local function QuestLines(rec)
	local lines = {}
	for _, quest in ipairs(rec.quests or {}) do
		if type(quest) == "table" then
			local bits = {}
			if type(quest.z) == "string" then bits[#bits + 1] = Strip(quest.z) end
			if tonumber(quest.l) then bits[#bits + 1] = (L["level %d"]):format(quest.l) end
			if quest.archived then bits[#bits + 1] = L["archived"] end
			local title = Strip(quest.title or "")
			if title == "" then title = (L["Quest %d"]):format(tonumber(quest.id) or 0) end
			lines[#lines + 1] = { when = Clock(quest.t), text = title, sub = table.concat(bits, " · ") }
		end
	end
	return lines
end

-- Your runs, oldest first: where, when, the level, and how many were with
-- you (their names only with opts.companions).
local function RunLines(charKey, opts)
	local R = A.Runs
	local unit = R and R:Store(charKey)
	local lines = {}
	if not unit then return lines end
	for _, run in ipairs(unit.list) do
		local bits = {}
		local level = R.Facts(unit, run).level
		if level then bits[#bits + 1] = (L["level %d"]):format(level) end
		local with = R.MemberKeys(unit, run)
		if opts.companions then
			if with[1] then bits[#bits + 1] = table.concat(with, ", ") end
		elseif with[1] then
			bits[#bits + 1] = E:Plural(#with, "with %s other", "with %s others"):format(#with)
		end
		lines[#lines + 1] = { when = Clock(run.t), text = Strip(R.Str(unit, run.inst) or "?"), sub = table.concat(bits, " · ") }
	end
	return lines
end

local function AbandonedLines(rec)
	local lines = {}
	for _, quest in ipairs(type(rec.abandoned) == "table" and rec.abandoned or {}) do
		if type(quest) == "table" then
			local bits = {}
			if type(quest.z) == "string" then bits[#bits + 1] = Strip(quest.z) end
			if tonumber(quest.l) then bits[#bits + 1] = (L["level %d"]):format(quest.l) end
			local title = Strip(quest.title or "")
			if title == "" then title = (L["Quest %d"]):format(tonumber(quest.id) or 0) end
			lines[#lines + 1] = { when = Clock(quest.t), text = title, sub = table.concat(bits, " · ") }
		end
	end
	return lines
end

-- opts (all optional): companions (true keeps companion names), show (a
-- J:Shown ctx instead of the module's settings), now (a time to use
-- instead of the clock).
function X:Document(charKey, opts)
	charKey = charKey or E.charKey
	opts = opts or {}
	local rec = J:Char(charKey)
	local B = A.Backup
	local who = B and B.Who and B.Who(charKey) or {}
	local name = Strip(who.name or "")
	if name == "" then name = tostring(charKey or "?") end
	local doc = { title = (L["%s's journal"]):format(name), subtitle = Subtitle(who, rec), sections = {} }
	if type(rec) ~= "table" then return doc end

	local byLevel = {}
	local rows = J:Timeline(charKey, nil, nil, function(row)
		if not opts.companions and X.COMPANIONS[row.kind] then return false end
		return J:Shown(row, opts.show)
	end)
	for _, row in ipairs(rows or {}) do
		local level = tonumber(row.level) or 0
		byLevel[level] = byLevel[level] or {}
		local list = byLevel[level]
		list[#list + 1] = RowLine(row)
	end
	local levels = {}
	for level in pairs(byLevel) do levels[#levels + 1] = level end
	table.sort(levels)
	for _, level in ipairs(levels) do
		local title = level > 0 and (L["Chapter %d"]):format(level) or L["Before the first chapter"]
		local place = level > 0 and ChapterPlace(rec, level)
		if place and place ~= "" then title = title .. " · " .. place end
		doc.sections[#doc.sections + 1] = { title = title, lines = Fold(byLevel[level]) }
	end

	local goals = GoalLines(rec)
	if goals[1] then doc.sections[#doc.sections + 1] = { title = L["Goals"], lines = goals } end
	local notes = NoteLines(rec)
	if notes[1] then doc.sections[#doc.sections + 1] = { title = L["Notes"], lines = notes } end
	local quests = QuestLines(rec)
	if quests[1] then doc.sections[#doc.sections + 1] = { title = L["Quests"], lines = quests } end
	local runs = RunLines(charKey, opts)
	if runs[1] then doc.sections[#doc.sections + 1] = { title = L["Runs"], lines = runs } end
	local abandoned = AbandonedLines(rec)
	if abandoned[1] then doc.sections[#doc.sections + 1] = { title = L["Abandoned quests"], lines = abandoned } end
	doc.footer = (L["Written by %s on %s."]):format(X.FOOTER, Day(opts.now or time()))
	return doc
end

---------------------------------------------------------------------------
-- Formats
---------------------------------------------------------------------------
-- Markdown: a few characters would otherwise start a list or make text bold.
local function MdEscape(text)
	return (tostring(text or ""):gsub("([\\`*_%[%]#])", "\\%1"))
end

function X:Markdown(charKey, opts)
	local doc = self:Document(charKey, opts)
	local out = { "# " .. MdEscape(doc.title), "" }
	if doc.subtitle ~= "" then out[#out + 1] = "_" .. MdEscape(doc.subtitle) .. "_"; out[#out + 1] = "" end
	for _, section in ipairs(doc.sections) do
		out[#out + 1] = "## " .. MdEscape(section.title)
		out[#out + 1] = ""
		for _, line in ipairs(section.lines) do
			local text = "- " .. (line.when ~= "" and ("**" .. line.when .. "**  ") or "") .. MdEscape(line.text)
			if line.sub ~= "" then text = text .. "  _(" .. MdEscape(line.sub) .. ")_" end
			if line.note then text = text .. "  \n  > " .. MdEscape(line.note) end
			out[#out + 1] = text
		end
		out[#out + 1] = ""
	end
	if doc.footer then out[#out + 1] = "_" .. MdEscape(doc.footer) .. "_" end
	return table.concat(out, "\n")
end

function X:Text(charKey, opts)
	local doc = self:Document(charKey, opts)
	local out = { doc.title }
	if doc.subtitle ~= "" then out[#out + 1] = doc.subtitle end
	out[#out + 1] = ""
	for _, section in ipairs(doc.sections) do
		out[#out + 1] = section.title
		out[#out + 1] = ("-"):rep(math.min(60, #section.title))
		for _, line in ipairs(section.lines) do
			local text = (line.when ~= "" and (line.when .. "  ") or "") .. line.text
			if line.sub ~= "" then text = text .. " (" .. line.sub .. ")" end
			out[#out + 1] = text
			if line.note then out[#out + 1] = "    " .. line.note end
		end
		out[#out + 1] = ""
	end
	if doc.footer then out[#out + 1] = doc.footer end
	return table.concat(out, "\n")
end

local function Esc(text)
	return (tostring(text or ""):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub("\"", "&quot;"))
end

local function Css(color, alpha)
	if type(color) ~= "table" then return nil end
	local r, g, b = tonumber(color[1]) or 0, tonumber(color[2]) or 0, tonumber(color[3]) or 0
	if alpha then return ("rgba(%d,%d,%d,%.2f)"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5, alpha) end
	return ("#%02x%02x%02x"):format(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
end

-- The page takes its colors from the design tokens: the paper inks when
-- the theme has them, otherwise the browser's own black on white with the
-- accent color for headings and rules. The fonts are the computer's own
-- book serifs (the page asks nothing of the internet), the browser's serif
-- when none of them is there.
function X.Style()
	local paper = E.tokens and E.tokens.paper
	local accent = Css(E.media and E.media.accentColor) or "inherit"
	local rule = Css(E.media and E.media.accentColor, 0.35) or "currentColor"
	local page, body, dim, head = "", "", "", accent
	if type(paper) == "table" then
		if Css(paper.fill) then page = "background:" .. Css(paper.fill) .. ";" end
		if Css(paper.body) then body = "color:" .. Css(paper.body) .. ";" end
		if Css(paper.secondary) then dim = "color:" .. Css(paper.secondary) .. ";" end
		head = Css(paper.head) or head
		rule = Css(paper.rule, 0.5) or rule
	end
	return table.concat({
		"body{margin:0;font-family:'EB Garamond',Garamond,'Palatino Linotype',Palatino,'Book Antiqua',Georgia,serif;" .. body .. "}",
		".page{max-width:760px;margin:32px auto;padding:48px 56px;" .. page .. "}",
		"h1{font-family:Cinzel,'Trajan Pro','Palatino Linotype',Palatino,Georgia,serif;font-size:36px;margin:0 0 4px;color:" .. head .. "}",
		".sub{font-style:italic;margin:0 0 28px;" .. dim .. "}",
		"h2{font-family:Cinzel,'Trajan Pro','Palatino Linotype',Palatino,Georgia,serif;font-size:20px;margin:30px 0 10px;padding-bottom:4px;border-bottom:1px solid " .. rule .. ";color:" .. head .. "}",
		"ul{list-style:none;margin:0;padding:0}",
		"li{display:flex;gap:14px;padding:5px 0;border-bottom:1px dotted " .. rule .. ";break-inside:avoid}",
		".when{flex:0 0 120px;font-size:14px;padding-top:2px;" .. dim .. "}",
		".what{flex:1}.where{display:block;font-size:14px;font-style:italic;" .. dim .. "}",
		".note{display:block;font-size:14px;margin-top:2px}",
		".foot{margin-top:36px;font-size:13px;font-style:italic;text-align:center;" .. dim .. "}",
		"@media print{.page{margin:0;max-width:none}}",
	}, "\n")
end

function X:HTML(charKey, opts)
	local doc = self:Document(charKey, opts)
	local out = {
		"<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><title>" .. Esc(doc.title) .. "</title><style>"
			.. X.Style() .. "</style></head><body><div class=\"page\">",
		"<h1>" .. Esc(doc.title) .. "</h1>",
	}
	if doc.subtitle ~= "" then out[#out + 1] = "<p class=\"sub\">" .. Esc(doc.subtitle) .. "</p>" end
	for _, section in ipairs(doc.sections) do
		out[#out + 1] = "<h2>" .. Esc(section.title) .. "</h2><ul>"
		for _, line in ipairs(section.lines) do
			out[#out + 1] = "<li><span class=\"when\">" .. Esc(line.when) .. "</span><span class=\"what\">" .. Esc(line.text)
				.. (line.sub ~= "" and ("<span class=\"where\">" .. Esc(line.sub) .. "</span>") or "")
				.. (line.note and ("<span class=\"note\">" .. Esc(line.note) .. "</span>") or "") .. "</span></li>"
		end
		out[#out + 1] = "</ul>"
	end
	if doc.footer then out[#out + 1] = "<p class=\"foot\">" .. Esc(doc.footer) .. "</p>" end
	out[#out + 1] = "</div></body></html>"
	return table.concat(out, "\n")
end

---------------------------------------------------------------------------
-- The copy box
---------------------------------------------------------------------------
local TITLES = E:TranslateValues({
	code = Key("Journal backup code"), runs = Key("Runs code"), markdown = Key("Journal as Markdown"),
	html = Key("Journal as a printable page"), text = Key("Journal as plain text"),
})
local HELPS = E:TranslateValues({
	code = Key("Press Ctrl+C to copy the code. Use \"Paste a journal code\" on this PC or another to restore the journal. Nothing is sent anywhere."),
	runs = Key("Press Ctrl+C to copy the code. Use \"Paste a runs code\" on this PC or another to restore your runs. Nothing is sent anywhere."),
	markdown = Key("Press Ctrl+C to copy it, then paste it into any Markdown editor or note app."),
	html = Key("Press Ctrl+C to copy it, save it as a .html file and open it in a browser. Print it to PDF for a keepsake."),
	text = Key("Press Ctrl+C to copy it, then paste it anywhere."),
})

function X:Build(format, charKey, opts)
	if format == "code" then
		local B = A.Backup
		if not B then return nil, L["Backups are not loaded."] end
		return B:Code(charKey)
	end
	if format == "runs" then
		local R = A.Runs
		if not R then return nil, L["There are no runs to back up yet."] end
		return R:Code(charKey)
	end
	local rec = J:Char(charKey)
	if not (A.Backup and A.Backup.HasData(rec)) then return nil, L["There is no journal to export yet."] end
	if format == "markdown" then return self:Markdown(charKey, opts) end
	if format == "html" then return self:HTML(charKey, opts) end
	if format == "text" then return self:Text(charKey, opts) end
	return nil, L["Unknown export format."]
end

function X:Show(format, charKey, opts)
	format = TITLES[format] and format or "markdown"
	local ok, text, err = pcall(self.Build, self, format, charKey, opts)
	if not ok then
		err, text = text, nil
		geterrorhandler()(err)
		err = L["The export did not work. The error is in the error list."]
	end
	if type(text) ~= "string" then
		E:Print(err or L["There is no journal to export yet."])
		return false
	end
	E:ShowCopyBox(TITLES[format], HELPS[format], text)
	return true
end
