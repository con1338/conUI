-- Offline run of the Group Board plugin with stand-ins for the game and
-- for the parts of EldoUI it calls. Run from the repository root:
--   lua5.1 tools/groupboard/test_board.lua
-- It loads the plugin's files in TOC order, feeds it chat lines, and walks
-- the window, the info bar block, the command and the notice. It checks
-- the plugin's own logic and that every call it makes lands somewhere; it
-- can't tell whether the game draws the window right (that needs the game).
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/groupboard/") or "./"

---------------------------------------------------------------------------
-- The game
---------------------------------------------------------------------------
local now = 1000
function GetTime() return now end
function strtrim(text) return (text:gsub("^%s+", ""):gsub("%s+$", "")) end
function GetLocale() return "enUS" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
	local list = timers
	timers = {}
	for _, fn in ipairs(list) do fn() end
end
local combat = false
function InCombatLockdown() return combat end
local level = 20
function UnitLevel() return level end
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
function issecretvalue(value) return value == SECRET end
function GetPlayerInfoByGUID(guid)
	if guid == "Player-1-PRIEST" then return "Priest", "PRIEST" end
	if guid == "Player-1-WARRIOR" then return "Warrior", "WARRIOR" end
end
function Ambiguate(name) return (name:gsub("%-.*$", "")) end
local invited, whispered = {}, {}
C_PartyInfo = { InviteUnit = function(name) invited[#invited + 1] = name end }
ChatFrameUtil = { SendTell = function(name) whispered[#whispered + 1] = name end }
CLASS_ICON_TCOORDS = { PRIEST = { 0, 0.25, 0, 0.25 }, WARRIOR = { 0.25, 0.5, 0, 0.25 } }

local tip = { lines = {} }
GameTooltip = tip
function tip:AddLine(text) self.lines[#self.lines + 1] = tostring(text) end
function tip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. " | " .. tostring(b) end
function tip:Show() end
function tip:Hide() end
function tip:SetOwner() end

-- The dungeon finder list: German client names, a Forever dungeon and one
-- this plugin doesn't know.
local LFG = {
	[18] = { "Die Todesminen", 1, 0, 18, 23, 5, 36 },
	[30] = { "Kloster: Bibliothek", 1, 0, 29, 39, 5, 189 },
	[31] = { "Stratholme - Haupttor", 1, 0, 58, 60, 5, 329 },
	[32] = { "Lower Blackrock Spire", 1, 0, 55, 60, 5, 229 },
	[33] = { "Obere Schwarzfelsspitze", 1, 0, 55, 60, 10, 229 },
	[900] = { "Schwarzschlundfeste", 1, 0, 30, 36, 5, 2974 },
	[902] = { "Schwarzschlundfeste", 1, 0, 58, 60, 5, 2974 },
	[901] = { "Das Grabmal der Sterne", 1, 0, 58, 60, 10, 4242 },
}
function GetLFDChoiceOrder() return { 18, 30, 31, 32, 33, 900, 902, 901 } end
function GetLFGDungeonInfo(id)
	local d = LFG[id]
	if not d then return nil end
	-- name, typeID, subtypeID, min, max, ..., maxPlayers (13), ..., mapID (22)
	local r = {}
	r[1], r[2], r[3], r[4], r[5] = d[1], d[2], d[3], d[4], d[5]
	r[13], r[22] = d[6], d[7]
	return unpack(r, 1, 22)
end

---------------------------------------------------------------------------
-- EldoUI (the parts the plugin calls)
---------------------------------------------------------------------------
local E = { apiVersion = 1, modules = {}, printed = {}, commands = {}, played = {} }
EldoUI = E
function E.RegisterEvent() end
function E.UnregisterEvent() end
assert(loadfile(ROOT .. "EldoUI/Core/Locale.lua"))("EldoUI", E) -- L, Key, FoldText, Plural, RegisterLocale
E.Secret = function(value) return issecretvalue(value) end
E.tokens = { text = { body = { 1, 1, 1 }, secondary = { 0.7, 0.7, 0.7 } } }

local function DeepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = DeepCopy(v) end
	return out
end

function E:NewModule(name, info)
	local module = { name = name, info = info, db = DeepCopy(info.defaults), events = {} }
	module.RegisterEvent = function(mod, event, fn) mod.events[event] = fn end
	self.modules[name] = module
	return module
end
function E:GetModule(name) return self.modules[name] end
function E:AddCommand(name, usage, fn) self.commands[name] = { usage = usage, fn = fn } end
function E:RegisterDataText(name, def) self.datatext = { name = name, def = def } end
function E:RegisterFinderProvider(kind, fn) self.finder = { kind = kind, fn = fn } end
function E:RegisterDiagnostics(_, fn) self.diag = fn end
function E:RegisterCompetitor(info) self.competitor = info end
function E:IsMe(name) return name == "Me" or name == "Me-Realm" end
local restricted = false
function E:CommRestricted() return restricted end
function E:Print(text) self.printed[#self.printed + 1] = text end
function E:PlayMedia(id) self.played[#self.played + 1] = id end
function E:TextHex() return "|cffaaaaaa" end
function E:TokenHex() return "|cffffffff" end
function E:WrapClassColor(class, text) return "|c" .. class .. text .. "|r" end
function E:TrimIcon() end
function E:OpenConfigFromLink(page) self.openedPage = page end
local ticks = {}
E.Ticker = { Subscribe = function(_, key, _, fn) ticks[key] = fn end, Unsubscribe = function(_, key) ticks[key] = nil end }

-- The UI kit: plain tables that remember what they were given.
local function Region()
	local r = { shown = false, points = {}, scripts = {} }
	function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
	function r:ClearAllPoints() self.points = {} end
	function r:SetText(text) self.text = text end
	function r:SetScript(name, fn) self.scripts[name] = fn end
	function r:HookScript(name, fn) self.scripts[name] = fn end
	function r:RegisterForClicks() end
	function r:IsShown() return self.shown end
	return r
end

local Kit, toasts = {}, {}
E.UIKit = Kit
Kit.TOOL_FOOTER, Kit.TOOL_PAD = 36, 8
function Kit.CreateToolWindow(name, opts)
	local win = Region()
	win.name, win.opts = name, opts
	win.content, win.footer, win.footerText = Region(), Region(), Region()
	function win:Open()
		self.shown = true
		if self.scripts.OnShow then self.scripts.OnShow(self) end
		return self
	end
	function win:Close() self.shown = false end
	return win
end
function Kit.ChipBar(_, opts)
	local bar = Region()
	bar.opts = opts
	function bar:SetSelected(selected) self.selected = selected end
	return bar
end
function Kit.Input(_, opts)
	local box = Region()
	box.opts = opts
	return box
end
function Kit.Button(_, opts)
	local button = Region()
	button.opts = opts
	return button
end
function Kit.Toast(_, text, opts) toasts[#toasts + 1] = { text = text, warn = opts and opts.warn } end
function Kit.ListRow2Template(opts) return opts end
function Kit.CreateList(_, opts)
	local list = Region()
	list.opts, list.rows, list.data = opts, {}, {}
	function list:SetData(items)
		self.data = items
		for index, item in ipairs(items) do
			local row = self.rows[index]
			if not row then
				row = Region()
				row.icon = { icon = { SetAtlas = function() end, GetAtlas = function() return nil end,
					SetTexture = function(t, path) t.path = path end, SetTexCoord = function() end },
					SetIcon = function(i, path) i.path = path end }
				row.SetRow = function(r, data) r.data = data end
				opts.create(row)
				self.rows[index] = row
			end
			row.item = item
			opts.update(row, item, index)
		end
	end
	return list
end
function Kit.AnchorTooltip() end
function Kit.TipTitle(t, text) t:AddLine(text) end
function Kit.TipText(t, text) t:AddLine(text) end
function Kit.TipPair(t, label, value) t:AddDoubleLine(label, value) end
function Kit.TooltipHint() end

---------------------------------------------------------------------------
-- Load the plugin in TOC order
---------------------------------------------------------------------------
local ns = {}
local toc = assert(io.open(ROOT .. "EldoUI_GroupBoard/EldoUI_GroupBoard.toc")):read("*a")
for line in toc:gmatch("[^\r\n]+") do
	if not line:match("^##") and line:match("%.lua$") then
		local path = ROOT .. "EldoUI_GroupBoard/" .. line:gsub("\\", "/")
		assert(loadfile(path))("EldoUI_GroupBoard", ns)
	end
end
local M, Board, Window, Catalog = ns.M, ns.Board, ns.Window, ns.Catalog
M.active = true
M:OnEnable()

---------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------
local failures, count = 0, 0
local function Check(ok, what)
	count = count + 1
	if not ok then
		failures = failures + 1
		print("FAIL  " .. what)
	end
end

local function Say(text, sender, zoneID, base, guid)
	M.events.CHAT_MSG_CHANNEL(M, "CHAT_MSG_CHANNEL", text, sender, "Common", "4. " .. tostring(base), "", "", zoneID, 4, base, 7, 1, guid)
	RunTimers()
end

-- The client list was read at OnEnable.
Check(Catalog:Get("deadmines").client == "Die Todesminen", "client name of the Deadmines from the dungeon finder")
Check(Catalog:Get("deadmines").min == 18, "client level range wins")
Check(Catalog:Get("f_blackmaw").client == "Schwarzschlundfeste", "Forever dungeon gets its client name")
Check(Catalog:Get("lfg:901") ~= nil and Catalog:Get("lfg:901").kind == "raid", "unknown dungeon finder entry added as a raid")
Check(Catalog:Get("sm_lib").client == "Kloster: Bibliothek", "a wing found by its name")
Check(Catalog:Get("lbrs").client == "Lower Blackrock Spire", "a wing found by its words")
Check(Catalog:Get("strat_live").client == nil and Catalog:Get("strat_ud").client == nil, "a wing the name doesn't tell gets nothing")
local extra = 0
for _, key in ipairs(Catalog.order) do if key:find("^lfg:") then extra = extra + 1 end end
Check(extra == 1, "only the unknown dungeon is added (got " .. extra .. ")")
Check(Catalog:Get("ubrs").kind == "dungeon", "UBRS stays a dungeon of ten")
Check(Catalog:Get("f_blackmaw").min == 30 and Catalog:Get("f_blackmaw").max == 60, "a second level band widens the range")

-- Channels
Say("LF2M DM need tank and heal", "Kalio-Realm", 26, "LookingForGroup", "Player-1-WARRIOR")
Say("LFM Schwarzschlundfeste need heal", "Brun-Realm", 1, "General")
Say("LFM BFD need tank", "Trader-Realm", 2, "Trade")                -- Trade is off by default
Say("Heiler sucht Gruppe für die Todesminen", "Lia-Realm", 0, "World", "Player-1-PRIEST")
Say("LFM SFK", "Elsewhere-Realm", 0, "SomeChannel")                  -- not a watched name
Say("LFM WC", "Me-Realm", 26, "LookingForGroup")                     -- your own post
Say(SECRET, "Hidden-Realm", 26, "LookingForGroup")                   -- a secret line
Say("WTS [Lionheart Helm]", "Seller-Realm", 26, "LookingForGroup")   -- no group post
Say("LFG Grabmal der Sterne", "Raider-Realm", 26, "LookingForGroup") -- unknown entry, found by its client name
Check(Board:Count() == 4, "four posts kept (got " .. Board:Count() .. ")")
Check(Board.posts["kalio-realm"] and Board.posts["kalio-realm"].class == "WARRIOR", "class from the sender's GUID")
Check(Board.posts["brun-realm"] and Board.posts["brun-realm"].places[1] == "f_blackmaw", "Forever dungeon found by its client name")
Check(Board.posts["raider-realm"] and Board.posts["raider-realm"].places[1] == "lfg:901", "unknown dungeon found by its client name")
Check(Board.posts["lia-realm"] and Board.posts["lia-realm"].kind == "lfg", "German LFG post from a custom channel")

-- Filters (level 20: the raid and the 30-36 dungeon don't fit)
local function Keys(list)
	local keys = {}
	for _, post in ipairs(list) do keys[#keys + 1] = post.key end
	table.sort(keys)
	return table.concat(keys, ",")
end
Check(Keys(Board:Matching()) == "kalio-realm,lia-realm", "level filter: " .. Keys(Board:Matching()))
M.db.filter.fit = false
Check(#Board:Matching() == 4, "without the level filter all four")
M.db.filter.lfg = false
Check(Keys(Board:Matching()) == "brun-realm,kalio-realm", "groups only: " .. Keys(Board:Matching()))
M.db.filter.lfg, M.db.filter.tank = true, true
Check(Keys(Board:Matching()) == "kalio-realm,raider-realm", "tank: needs a tank or names no role: " .. Keys(Board:Matching()))
M.db.filter.tank = false
Check(Keys(Board:Matching("todesminen")) == "kalio-realm,lia-realm", "search finds the German place name")
Check(Keys(Board:Matching("kalio")) == "kalio-realm", "search finds the sender")
M.db.filter.dungeon, M.db.filter.raid, M.db.filter.quest, M.db.filter.other = false, true, false, false
Check(Keys(Board:Matching()) == "raider-realm", "raids only: " .. Keys(Board:Matching()))
M.db.filter.dungeon, M.db.filter.quest, M.db.filter.other = true, true, true
M.db.filter.fit = true

-- A repeat is no news; another text is.
now = now + 30
Say("LF2M DM need tank and heal", "Kalio-Realm", 26, "LookingForGroup", "Player-1-WARRIOR")
Check(Board.posts["kalio-realm"].count == 2 and Board.posts["kalio-realm"].first == 1000, "a repeat counts, keeps its start")

-- Hide until the sender posts something else.
Board:Hide(Board.posts["kalio-realm"])
Check(Keys(Board:Matching()) == "lia-realm", "hidden post leaves the list")
Say("LF2M DM need tank and heal", "Kalio-Realm", 26, "LookingForGroup", "Player-1-WARRIOR")
Check(Keys(Board:Matching()) == "lia-realm", "a repeat stays hidden")
Say("LF1M DM need heal", "Kalio-Realm", 26, "LookingForGroup", "Player-1-WARRIOR")
Check(Keys(Board:Matching()) == "kalio-realm,lia-realm", "a new text shows again")

-- The notice: off by default; on, once per post, never in combat.
Check(#E.printed == 0, "no notice while it is off")
M.db.notify.on = true
Say("LFM RFC need dps", "Ora-Realm", 26, "LookingForGroup")
Check(#E.printed == 1 and #E.played == 1, "one notice for a new group")
Say("LFM RFC need dps", "Ora-Realm", 26, "LookingForGroup")
Check(#E.printed == 1, "no second notice for a repeat")
combat = true
Say("LFM WC need dps", "Ute-Realm", 26, "LookingForGroup")
Check(#E.printed == 1, "no notice in combat")
combat = false
Say("LFG WC", "Vik-Realm", 26, "LookingForGroup")
Check(#E.printed == 1, "no notice for players looking for a group")
level = 50
Say("LFM ZG need heal", "Wim-Realm", 26, "LookingForGroup")
Check(#E.printed == 1, "no notice for a group the filters leave out (raid at 50)")
level = 20
M.db.notify.on = false

-- A bare "DM": the Deadmines or Dire Maul, fits both level ranges.
level = 58
Say("LFM DM need heal", "Dmguy-Realm", 26, "LookingForGroup")
local dmPost = Board.posts["dmguy-realm"]
Check(dmPost and dmPost.maybe == "diremaul", "bare DM keeps Dire Maul as the other reading")
Check(Board.PlacesText(dmPost) == "The Deadmines or Dire Maul", "bare DM shows both: " .. tostring(Board.PlacesText(dmPost)))
local fitsAt58 = false
for _, post in ipairs(Board:Matching()) do if post.key == "dmguy-realm" then fitsAt58 = true end end
Check(fitsAt58, "bare DM passes the level filter at 58")
Check(#Board:Matching("dire maul") >= 1, "search finds Dire Maul for a bare DM")
Board:Remove("dmguy-realm")
level = 20

-- The window
E.commands.board.fn("")
local win = Window.frame
Check(win and win.shown, "/eui board opens the window")
RunTimers()
local list = win.list
Check(#list.data == #Board:Matching(), "the list shows what passes the filters")
local first = list.rows[1]
Check(first and first.data and first.data.name, "rows are filled")
Check(win.footerText.text and win.footerText.text:find("of"), "footer counts the posts: " .. tostring(win.footerText.text))
tip.lines = {}
first.scripts.OnEnter(first)
Check(#tip.lines >= 4, "the row tooltip has the line and details")
first.scripts.OnClick(first, "LeftButton")
Check(#whispered == 1, "a row click opens a whisper")
local lfgRow
for _, row in ipairs(list.rows) do if row.item and row.item.kind == "lfg" then lfgRow = row end end
Check(lfgRow and lfgRow.data.hide.invite == false, "players looking for a group can be invited")
Check(first.item.kind ~= "lfm" or first.data.hide.invite == true, "groups get no invite button")
combat = true
Window:Invite(lfgRow.item)
Check(#invited == 0 and #toasts == 1 and toasts[1].warn, "no invite in combat, a toast says so")
combat = false
Window:Invite(lfgRow.item)
Check(#invited == 1, "invite out of combat")
win.kinds.opts.onChange({ lfg = true })
Check(M.db.filter.lfm == false and M.db.filter.lfg == true, "chips store the filter")
win.kinds.opts.onChange({ lfm = true, lfg = true, fit = true })
win.search.opts.onChange("zz-nothing")
Check(#list.data == 0 and list.opts.empty and list.opts.empty[1] == "Nothing matches", "empty state for filtered out posts")
win.search.opts.onChange("")
restricted = true
Board:Clear()
RunTimers()
Check(list.opts.empty[1] == "Chat is held back", "empty state while the game holds chat back")
restricted = false

-- Expiry
Say("LFM SFK need tank", "Old-Realm", 26, "LookingForGroup")
now = now + 11 * 60
ticks.GroupBoardTick()
RunTimers()
Check(Board:Count() == 0, "posts go after the set time")

-- The info bar block, Finder and diagnostics
Say("LFM DM need tank", "Kalio-Realm", 26, "LookingForGroup")
local def = E.datatext.def
Check(def.text() == "1 group", "block text: " .. tostring(def.text()))
tip.lines = {}
def.tooltip(tip)
Check(#tip.lines == 1, "block tooltip lists the post")
Check(#E.finder.fn() == 1, "Finder entry")
Check(E.diag()[1]:find("1 posts"), "diagnostics line")
Check(E.competitor and E.competitor.addon == "GroupBulletinBoard", "LFG Bulletin Board declared")

-- Off: posts go, the window closes, the command says so.
M:OnDisable()
M.active = false
Check(Board:Count() == 0 and not win.shown, "turning it off clears the board and closes the window")
E.commands.board.fn("")
Check(E.printed[#E.printed]:find("off"), "the command says the board is off")

-- German
E:SetLanguage("deDE")
Check(E.L["Group board"] == "Gruppen-Pinnwand", "German texts registered")
Check(E:Plural(2, "%d group", "%d groups"):format(2) == "2 Gruppen", "German plural")
Check(Catalog:Name("deadmines") == "Die Todesminen", "German place name")

print(("%d of %d checks passed"):format(count - failures, count))
os.exit(failures == 0 and 0 or 1)
