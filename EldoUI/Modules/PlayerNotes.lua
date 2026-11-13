-- EldoUI Player Notes: your own notes on other players and a journal of who
-- you have grouped with.
--
--   * A note and a mark (good / avoid) per player, set from the unit's
--     right-click menu or /eui note.
--   * Their tooltip shows the note, the mark and how often and when you last
--     grouped with them.
--   * A short warning when a player you marked "avoid" joins your group.
--   * With My Adventure on: a "Journal" tooltip line (time together, when
--     you met), "Open in your journal" in the right-click menu, and
--     M:OnJoined(fn) so the journal's Fellowship can link its companion to
--     the note (fn(key, unit) when someone joins your group).
--
-- Written from scratch for EldoUI. Everything stays on your computer;
-- nothing is sent, and no one is kicked, ignored or invited for you.
local _, E = ...
local L = E.L


local M = E:NewModule("PlayerNotes", {
	title = "Player Notes",
	category = "Chat & Social",
	desc = "Your own notes and good/avoid marks on players, shown on their tooltip, and a journal of who you have grouped with.",
	savedKeys = { "profile.modules.PlayerNotes", "global.PlayerNotes" },
	optionsPage = "module:PlayerNotes",
	presets = { "Standard", "NotesOnly", "Quiet", "Journal", "OffTooltip" },
	reload = false,
	defaults = {
		tooltip = true,
		journal = true,       -- remember who you grouped with
		showGrouped = true,   -- "Grouped 3 times, last 2 days ago" on the tooltip
		warnAvoid = true,     -- a note when someone you marked "avoid" joins
		menu = true,          -- entries in the unit right-click menu
		showJournal = true,   -- "Journal: 3h 10m together, met Sep 20" on the tooltip
	},
})
E.PlayerNotes = M

local MARKS = E:TranslateFields({
	good = { label = "Good", color = E:TextHex("good") },
	avoid = { label = "Avoid", color = E:TextHex("bad") },
}, "label")
M.MARKS = MARKS

local Clean = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

---------------------------------------------------------------------------
-- Store: account-wide, by "Name-Realm"
---------------------------------------------------------------------------
function M:Store()
	local store = E:GetGlobal("PlayerNotes") or { players = {} }
	store.players = store.players or {}
	return store.players
end

local function MyRealm()
	local realm = GetNormalizedRealmName and Clean(GetNormalizedRealmName())
	return type(realm) == "string" and realm ~= "" and realm or "?"
end

-- "Name" or "Name-Realm" -> "Name-Realm" (first letter capitalized).
function M.Key(name)
	if type(name) ~= "string" then return nil end
	name = name:match("^%s*(.-)%s*$")
	if name == "" then return nil end
	local short, realm = name:match("^([^%-]+)%-(.+)$")
	short = short or name
	realm = realm or MyRealm()
	short = short:sub(1, 1):upper() .. short:sub(2)
	return short .. "-" .. realm:gsub("[%s%-]", "")
end

function M:UnitKey(unit)
	if not (unit and UnitIsPlayer and Clean(UnitIsPlayer(unit))) then return nil end
	if UnitIsUnit and Clean(UnitIsUnit(unit, "player")) then return nil end
	-- "Name-Realm" the way chat senders are keyed, never with the surname.
	local key = self.Key(E:UnitNameKey(unit, true))
	if not key then return nil end
	-- A note kept under "Name-Surname" by an earlier version moves to the
	-- right key the first time the player is seen again.
	if UnitFullName then
		local ok, name, second = pcall(UnitFullName, unit)
		name, second = ok and Clean(name), ok and Clean(second)
		if type(name) == "string" and name ~= "" and type(second) == "string" and second ~= "" then
			local old = self.Key(name .. "-" .. second)
			local players = self:Store()
			if old and old ~= key and players[old] and not players[key] then
				players[key], players[old] = players[old], nil
			end
		end
	end
	return key
end

function M:Get(key)
	return key and self:Store()[key]
end

local function Record(key)
	local players = M:Store()
	players[key] = players[key] or {}
	return players[key]
end

local function Tidy(key)
	local record = M:Store()[key]
	if record and not record.note and not record.mark and not record.grouped then M:Store()[key] = nil end
end

-- The journal reads notes and marks through its "playernotes" source.
local function Changed()
	local journal = E.Journal
	if journal and journal.Changed then journal:Changed("playernotes") end
	if M.NotifyChanged then M.NotifyChanged() end
end

function M:SetNote(key, text)
	if not key then return false end
	text = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
	Record(key).note = text ~= "" and text:sub(1, 200) or nil
	Tidy(key)
	Changed()
	return true
end

function M:SetMark(key, mark)
	if not key or (mark and not MARKS[mark]) then return false end
	Record(key).mark = mark
	Tidy(key)
	Changed()
	return true
end

---------------------------------------------------------------------------
-- The journal bridge: joins, and the journal's key of a player
---------------------------------------------------------------------------
local joined = {}   -- fn(key, unit) when someone joins your group
local links = {}    -- journal key -> note key (this session)

function M:OnJoined(fn)
	if type(fn) == "function" then joined[#joined + 1] = fn end
end

-- The journal names a player by its own key (E.Journal:Key); remember which
-- note key it belongs to. Kept on the player's record when there is one.
function M:LinkJournal(key, journalKey)
	if type(key) ~= "string" or type(journalKey) ~= "string" then return end
	links[journalKey] = key
	local record = self:Get(key)
	if record then record.journal = journalKey end
end

function M:FindByJournal(journalKey)
	if type(journalKey) ~= "string" then return nil end
	if links[journalKey] then return links[journalKey] end
	for key, record in pairs(self:Store()) do
		if type(record) == "table" and record.journal == journalKey then return key end
	end
	return nil
end

-- The journal's companion record of a unit, when My Adventure runs.
local function Companion(unit)
	local adventure, journal = E.Adventure, E.Journal
	if not (adventure and journal and adventure.Running and journal.Key and journal.Char) then return nil end
	local ok, running = pcall(adventure.Running, adventure)
	if not (ok and running) then return nil end
	local okKey, key = pcall(journal.Key, journal, unit)
	if not (okKey and type(key) == "string") then return nil end
	local rec = journal:Char()
	local fellow = rec and type(rec.fellows) == "table" and rec.fellows[key]
	if type(fellow) ~= "table" then return nil end
	return fellow, key
end
M.Companion = Companion

---------------------------------------------------------------------------
-- Journal: who you grouped with
---------------------------------------------------------------------------
local inGroup = {} -- keys already counted in this group

local function ZoneName()
	local zone = GetRealZoneText and Clean(GetRealZoneText())
	return type(zone) == "string" and zone ~= "" and zone or nil
end

local function GroupUnits()
	local units = {}
	if IsInRaid and IsInRaid() then
		for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do units[#units + 1] = "raid" .. i end
	elseif IsInGroup and IsInGroup() then
		for i = 1, 4 do units[#units + 1] = "party" .. i end
	end
	return units
end

function M:ScanGroup()
	local units = GroupUnits()
	if #units == 0 then
		wipe(inGroup)
		return
	end
	local present = {}
	for _, unit in ipairs(units) do
		local key = UnitExists and UnitExists(unit) and self:UnitKey(unit)
		if key then
			present[key] = true
			if not inGroup[key] then
				inGroup[key] = true
				local record = self:Get(key)
				if self.db.journal then
					record = Record(key)
					record.grouped = (record.grouped or 0) + 1
					record.last = time()
					record.zone = ZoneName()
					local _, class = UnitClass(unit)
					record.class = Clean(class) or record.class
					if M.NotifyChanged then M.NotifyChanged() end
				end
				for _, fn in ipairs(joined) do
					local ok, err = pcall(fn, key, unit)
					if not ok then geterrorhandler()(err) end
				end
				if self.db.warnAvoid and record and record.mark == "avoid" then
					M:PushAlert({ key = "note-avoid-" .. key, title = "Player Notes",
						text = (L["%s joined your group. You marked them Avoid%s"]):format(key, record.note and (": " .. record.note) or "."),
						icon = 132331, duration = 12 })
				end
			end
		end
	end
	for key in pairs(inGroup) do
		if not present[key] then inGroup[key] = nil end
	end
end

-- The players you grouped with, the last one first (the friends
-- window's "Recently grouped" tab). Each entry: { key, name, realm,
-- class, grouped, last, zone, note, mark }. At most `limit` (default 50).
M.RECENT_LIMIT = 50
function M:RecentlyGrouped(limit)
	limit = tonumber(limit) or self.RECENT_LIMIT
	local list = {}
	for key, record in pairs(self:Store()) do
		if type(key) == "string" and type(record) == "table" and record.grouped and record.last then
			local name, realm = key:match("^([^%-]+)%-(.+)$")
			list[#list + 1] = {
				key = key, name = name or key, realm = realm, class = record.class,
				grouped = record.grouped, last = record.last, zone = record.zone,
				note = record.note, mark = record.mark,
			}
		end
	end
	table.sort(list, function(a, b)
		if a.last ~= b.last then return a.last > b.last end
		return a.key < b.key
	end)
	for index = #list, limit + 1, -1 do list[index] = nil end
	return list
end

-- Something changed that the friends window's list shows.
local listeners = {}
function M:OnChanged(fn)
	if type(fn) == "function" then listeners[#listeners + 1] = fn end
end
function M.NotifyChanged()
	for _, fn in ipairs(listeners) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function Ago(when)
	if not when then return "" end
	local seconds = time() - when
	if seconds < 3600 then return "just now" end
	if seconds < 86400 then return ("%d h ago"):format(seconds / 3600) end
	local days = math.floor(seconds / 86400)
	return days == 1 and "yesterday" or ("%d days ago"):format(days)
end
M.Ago = Ago

local function JournalLine(unit, add)
	local fellow = Companion(unit)
	local spent = fellow and tonumber(fellow.time) or 0
	local fmt = E.Adventure and E.Adventure.Fmt
	if not (fellow and fmt) or spent <= 0 then return end
	local met = tonumber(fellow.met)
	if met then
		add(L["Journal"], (L["%s together, met %s"]):format(fmt.Span(spent), fmt.Short(met)))
	else
		add(L["Journal"], (L["%s together"]):format(fmt.Span(spent)))
	end
end

function M:TooltipUnit(unit, add)
	if not (self.active and self.db.tooltip) then return end
	local record = self:Get(self:UnitKey(unit))
	if record then
		local mark = record.mark and MARKS[record.mark]
		if mark or record.note then
			add((mark and (mark.color .. mark.label .. "|r") or L["Note"]) .. (record.note and (": |cffffffff" .. record.note .. "|r") or ""))
		end
		if self.db.showGrouped and record.grouped then
			add(L["Grouped"], L["%d×, %s"]:format(record.grouped, Ago(record.last)))
		end
	end
	if self.db.showJournal then JournalLine(unit, add) end
end

function M:RegisterTooltip()
	if self.tooltipRegistered or not E.RegisterTooltipSection then return end
	self.tooltipRegistered = true
	E:RegisterTooltipSection("playernotes", {
		order = 25,
		title = "Player notes",
		desc = "Your note, your good/avoid mark, how often you grouped with the player and your time together from My Adventure.",
		unit = function(_, unit, add) M:TooltipUnit(unit, add) end,
		module = "PlayerNotes",
		option = "tooltip",
	})
end

---------------------------------------------------------------------------
-- Editing: a text box, the unit menu and /eui note
---------------------------------------------------------------------------
function M:EditNote(key)
	if not key then return end
	local record = self:Get(key)
	E:ShowConfirm({ key = "ELDOUI_PLAYER_NOTE", title = L["Player Notes"], text = L["Note on %s"]:format(key), accept = ACCEPT,
		edit = { text = record and record.note or "", maxLetters = 200 }, data = key,
		onAccept = function(own, typed) M:SetNote(own, typed) end })
end

local function MenuKey(context)
	if type(context) ~= "table" then return nil end
	if context.unit then
		local key = M:UnitKey(context.unit)
		if key then return key end
	end
	local name = Clean(context.name)
	if type(name) ~= "string" then return nil end
	local server = Clean(context.server)
	return M.Key(server and server ~= "" and (name .. "-" .. server) or name)
end

local MENUS = { "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_TARGET" }

function M:AddMenus()
	local menu = _G.Menu
	if self.menusAdded or not (type(menu) == "table" and menu.ModifyMenu) then return end
	self.menusAdded = true
	for _, tag in ipairs(MENUS) do
		menu.ModifyMenu(tag, function(_, root, context)
			if not (M.active and M.db.menu and root) then return end
			local key = MenuKey(context)
			if not key then return end
			local record = M:Get(key)
			root:CreateDivider()
			root:CreateTitle(L["EldoUI note"])
			root:CreateButton(record and record.note and L["Edit note"] or L["Add note"], function() M:EditNote(key) end)
			for mark, info in pairs(MARKS) do
				if not (record and record.mark == mark) then
					root:CreateButton(L["Mark %s"]:format(info.color .. info.label .. "|r"), function() M:SetMark(key, mark) end)
				end
			end
			if record and record.mark then root:CreateButton(L["Clear mark"], function() M:SetMark(key, nil) end) end
			local who = context.unit or (type(context.name) == "string" and (type(context.server) == "string" and context.server ~= ""
				and (context.name .. "-" .. context.server) or context.name)) or ""
			local _, journalKey = Companion(who)
			local adventure = E.Adventure
			if journalKey and adventure and adventure.SectionShown and adventure:SectionShown("fellowship") then
				root:CreateButton(L["Open in your journal"], function() adventure:OpenSection("fellowship", { fellow = journalKey }) end)
			end
		end)
	end
end

function M:Command(arg)
	arg = (arg or ""):match("^%s*(.-)%s*$")
	local word, rest = arg:match("^(%S*)%s*(.-)$")
	local lower = (word or ""):lower()
	if lower == "" or lower == "list" then
		local rows = {}
		for key, record in pairs(self:Store()) do
			if record.note or record.mark then rows[#rows + 1] = { key, record } end
		end
		table.sort(rows, function(a, b) return a[1] < b[1] end)
		if #rows == 0 then E:Print(L["No player notes yet. Right-click a player, or /eui note Name text."]) return end
		for _, row in ipairs(rows) do
			local mark = row[2].mark and MARKS[row[2].mark]
			E:Print(("%s %s%s"):format(row[1], mark and (mark.color .. mark.label .. "|r ") or "", row[2].note or ""))
		end
	elseif lower == "good" or lower == "avoid" or lower == "clear" then
		local key = M.Key(rest)
		if not key then E:Print(L["/eui note "] .. lower .. " Name") return end
		self:SetMark(key, lower ~= "clear" and lower or nil)
		E:Print(lower == "clear" and L["%s: mark cleared."]:format(key) or L["%s: marked %s."]:format(key, MARKS[lower].label))
	else
		local key = M.Key(word)
		if rest == "" then
			local record = self:Get(key)
			E:Print((record and record.note) and ("%s: %s"):format(key, record.note) or L["%s: no note."]:format(key))
		else
			self:SetNote(key, rest)
			E:Print((L["Note on %s saved."]):format(key))
		end
	end
end

E:AddCommand("note", "[Name [text] | good Name | avoid Name | clear Name | list]  your notes on players", function(arg)
	if M.active then M:Command(arg) else E:Print(E:ModuleOffHint("PlayerNotes")) end
end)

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
	if M.active then M:ScanGroup() end
end)

function M:OnInitialize()
	E:RegisterGlobal("PlayerNotes", { players = {} })
	-- The tooltip row is listed on the Tooltip page while this module is off too.
	self:RegisterTooltip()
end

function M:OnEnable()
	self:AddMenus()
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		pcall(events.RegisterEvent, events, event)
	end
	self:ScanGroup()
	E:RefreshTooltipSections()
end

function M:OnDisable()
	events:UnregisterAllEvents()
	E:RefreshTooltipSections()
end

-- Every setting is read when it is used, so a new profile only needs the
-- tooltip under the cursor redrawn (its note rows may now be on or off).
function M:OnProfileChanged()
	E:RefreshTooltipSections()
end

---------------------------------------------------------------------------
-- Options and styles
---------------------------------------------------------------------------
M.options = {
	{ type = "description", label = "Right-click a player to add a note or mark them Good or Avoid. Notes stay on your computer. Also: /eui note Name text, /eui note list." },
	{ type = "toggle", key = "menu", label = "Right-click menu", desc = "Add note and mark entries to a player's right-click menu." },
	{ type = "toggle", key = "tooltip", label = "Show on tooltips", desc = "Show your note and mark on the player's tooltip." },
	{ type = "toggle", key = "journal", label = "Group journal", desc = "Remember who you grouped with, how often and when." },
	{ type = "toggle", key = "showGrouped", label = "Grouped line on tooltips", desc = "Show how often and when you last grouped with the player, from the group journal.", dependsOn = "tooltip" },
	{ type = "toggle", key = "showJournal", label = "Journal line on tooltips", desc = "With My Adventure on, show how long you have grouped with the player and when you met, from the journal's Fellowship.", dependsOn = "tooltip" },
	{ type = "toggle", key = "warnAvoid", label = "Warn about Avoid players", desc = "A short note when someone you marked Avoid joins your group." },
	{ type = "execute", confirm = true, label = "Forget the group journal", desc = "Remove the grouped counts; your notes and marks stay.", func = function()
		for key, record in pairs(M:Store()) do
			record.grouped, record.last, record.zone = nil, nil, nil
			Tidy(key)
		end
		M.NotifyChanged()
	end },
}

E:RegisterStyles("PlayerNotes", {
	{ key = "Standard", title = "Standard", desc = "Notes, marks, the group journal and Avoid warnings.",
		settings = { menu = true, tooltip = true, journal = true, showGrouped = true, warnAvoid = true } },
	{ key = "NotesOnly", title = "Notes only", desc = "Your notes and marks; no group journal.",
		settings = { menu = true, tooltip = true, journal = false, showGrouped = false, warnAvoid = true } },
	{ key = "Quiet", title = "Quiet", desc = "Everything on the tooltip, no warnings.",
		settings = { menu = true, tooltip = true, journal = true, showGrouped = true, warnAvoid = false } },
	{ key = "Journal", title = "Journal", desc = "The group journal on tooltips, no menu entries.",
		settings = { menu = false, tooltip = true, journal = true, showGrouped = true, warnAvoid = true } },
	{ key = "OffTooltip", title = "Off the tooltip", desc = "Notes and marks in the right-click menu only, nothing on tooltips; Avoid warnings stay on.",
		settings = { menu = true, tooltip = false, journal = true, showGrouped = false, warnAvoid = true } },
})
-- Every preset sets all five switches, so the result never depends on the
-- preset picked before.
