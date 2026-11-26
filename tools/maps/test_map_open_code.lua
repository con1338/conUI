-- Offline test: EldoUI never opens the world map or the quest log with the
-- game's own map code (F29, EldoUI issue #5).
-- Run from the repository root:
--   lua5.1 tools/maps/test_map_open_code.lua
-- Seen in the game (EldoUI 0.7.3005 to 0.7.4000, reported upstream as
-- Eldodeldo/EldoUI issue #5): "Blocked: EldoUI tried to call the protected
-- function Button:SetPassThroughButtons()", 46 times from Escape
-- (ToggleGameMenu > CloseAllWindows > HideUIPanel > the map's
-- ClearFocusedQuestID > QuestDataProvider:RefreshAllData > AcquirePin), and
-- "Frame:SetPassThroughButtons()" from L (ToggleQuestLog > ShowUIPanel >
-- RefreshAllDataProviders > WaypointLocationDataProvider > AcquirePin).
-- SetPassThroughButtons is protected (its API documentation says so), and
-- every map pin calls it when acquired, so any pin the map makes in a
-- tainted run is blocked. Both stacks start at the game's own keys: the
-- map's state was already tainted. A map opened from addon code leaves it
-- so (EldoUI's own notes in Core/UIKit.lua and Modules/InfoBar.lua), and
-- EldoUI still did that on three paths:
--   * the Finder's "Quest log" entry called the game's ToggleQuestLog;
--   * the Info Bar's Menu block clicked QuestLogMicroButton from its code;
--   * EldoUI's message windows handed every link to SetItemRef, and the
--     game's handlers for map pin, world quest and event links call
--     OpenWorldMap / OpenMapToUserWaypoint / OpenMapToEventPoi.
-- This runs the real Finder entries (PANELS, PanelCall), the Menu block's
-- OpenFromMenu and E:FollowLink (Core/ChatLinks.lua) against stubs, and a
-- text check makes sure no Lua file the TOCs load (and no key binding)
-- uses the game's map openers, called, handed on as a value or by name in
-- quotes, and that only Core/ChatLinks.lua hands links to SetItemRef.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/maps/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local failures, passed = 0, 0
local function Check(ok, message)
	if ok then
		passed = passed + 1
	else
		failures = failures + 1
		print("FAIL: " .. message)
	end
end

---------------------------------------------------------------------------
-- What the game would do: every call of its map code is counted
---------------------------------------------------------------------------
local calls
local function Reset() calls = {} end
local function Called(name)
	for _, entry in ipairs(calls) do
		if entry.name == name then return entry end
	end
end

local E = {}
function E:IsSecret() return false end
function E:OpenWorldMapAt(uiMapID)
	calls[#calls + 1] = { name = "OpenWorldMapAt", mapID = uiMapID }
	return true
end

-- The game's own map openers: any of them called is the bug.
local GAME_OPENERS = { "ToggleQuestLog", "ToggleWorldMap", "OpenWorldMap", "OpenQuestLog", "OpenMapToUserWaypoint",
	"OpenMapToEventPoi" }
for _, name in ipairs(GAME_OPENERS) do
	_G[name] = function() calls[#calls + 1] = { name = name } end
end
local function NoGameOpener()
	for _, entry in ipairs(calls) do
		for _, name in ipairs(GAME_OPENERS) do
			if entry.name == name then return false end
		end
	end
	return true
end

---------------------------------------------------------------------------
-- The Finder's Quest log and World map entries (/eui find)
---------------------------------------------------------------------------
do
	local finder = ReadFile("EldoUI/Modules/Finder/Finder.lua")
	local panelsText = Between(finder, "local PANELS = {", "\nM.PANELS = PANELS", "Finder.lua PANELS")
	local panels = assert(loadstring("return " .. panelsText:sub(#"local PANELS = " + 1), "=Finder.lua PANELS"))()
	local PanelCall = assert(loadstring("local E, Global = ...\n"
		.. Between(finder, "local function PanelCall(panel)", "-- The config window opens only from /eui", "Finder.lua PanelCall")
		.. "\nreturn PanelCall", "=Finder.lua PanelCall"))(E, function(name) return rawget(_G, name) end)
	C_Map = { OpenWorldMap = function() end }
	for _, text in ipairs({ "Quest log", "World map" }) do
		local panel
		for _, entry in ipairs(panels) do
			if entry.text == text then panel = entry end
		end
		Check(panel ~= nil, "the Finder has its " .. text .. " entry")
		if panel then
			Reset()
			local open = PanelCall(panel)
			Check(type(open) == "function", "the Finder offers its " .. text .. " entry")
			if open then open() end
			Check(Called("OpenWorldMapAt") ~= nil, "the Finder's " .. text .. " entry asks the game to open the map")
			Check(NoGameOpener(), "the Finder's " .. text .. " entry runs none of the game's map code")
			Check(panel.combat == false, "the Finder's " .. text .. " entry waits for the end of combat, like the map")
		end
	end
	C_Map = nil
end

---------------------------------------------------------------------------
-- The Info Bar's Menu block (Modules/MicroMenu.lua)
---------------------------------------------------------------------------
do
	local micro = ReadFile("EldoUI/Modules/MicroMenu.lua")
	local chunk = Between(micro, "local GAME_REQUESTS = {", "\nE:RegisterDataText(\"Menu\", {", "MicroMenu.lua OpenFromMenu")
	local M = {}
	local combat = false
	local env = setmetatable({ E = E, M = M, InCombatLockdown = function() return combat end }, { __index = _G })
	local fn = assert(loadstring(chunk .. "\nreturn OpenFromMenu", "=MicroMenu.lua OpenFromMenu"))
	setfenv(fn, env)
	local OpenFromMenu = fn()
	local function Button(name)
		return { name = name, Click = function(self) calls[#calls + 1] = { name = "Click", button = self.name } end }
	end

	Reset()
	OpenFromMenu("QuestLogMicroButton", Button("QuestLogMicroButton"))
	Check(Called("OpenWorldMapAt") ~= nil, "the Menu block's Quest log asks the game to open the map")
	Check(Called("Click") == nil, "the Menu block never clicks the game's quest log button from its code")

	Reset()
	OpenFromMenu("CharacterMicroButton", Button("CharacterMicroButton"))
	local click = Called("Click")
	Check(click ~= nil and click.button == "CharacterMicroButton", "the Menu block's other entries still click their game button")

	Reset()
	combat = true
	OpenFromMenu("QuestLogMicroButton", Button("QuestLogMicroButton"))
	OpenFromMenu("CharacterMicroButton", Button("CharacterMicroButton"))
	Check(#calls == 0, "the Menu block opens nothing in combat")
	combat = false

	-- The entry goes through OpenFromMenu, not through its own Click().
	local menu = Between(micro, "E:RegisterDataText(\"Menu\", {", "\n})", "MicroMenu.lua Menu block")
	Check(menu:find("OpenFromMenu(info[1], button)", 1, true) ~= nil, "the Menu block's entries use OpenFromMenu")
	Check(not menu:find(":Click()", 1, true), "the Menu block clicks no game button itself")
end

---------------------------------------------------------------------------
-- Links in EldoUI's message windows (E:FollowLink, Core/ChatLinks.lua)
---------------------------------------------------------------------------
local modified = false
do
	local links = ReadFile("EldoUI/Core/ChatLinks.lua")
	local chunk = Between(links, "local function PlainMapID(value)", "\n---------------------------------------------------------------------------\n-- Item, spell",
		"ChatLinks.lua FollowLink")
	local waypoint = { uiMapID = 1429, position = { x = 0.4, y = 0.6 } }
	local tooltip = { shown = false }
	function tooltip:IsShown() return self.shown end
	function tooltip:SetOwner() calls[#calls + 1] = { name = "SetOwner" } end
	function tooltip:ItemRefSetHyperlink(link) calls[#calls + 1] = { name = "ItemRefSetHyperlink", link = link } end
	local env = setmetatable({
		E = E,
		C_Map = {
			GetUserWaypointFromHyperlink = function(link)
				calls[#calls + 1] = { name = "GetUserWaypointFromHyperlink", link = link }
				return waypoint
			end,
			SetUserWaypoint = function(point)
				calls[#calls + 1] = { name = "SetUserWaypoint", point = point }
				return true
			end,
		},
		C_EventScheduler = { GetEventUiMapID = function(id) return id == 77 and 1453 or nil end },
		SetItemRef = function(link, text, button, frame)
			calls[#calls + 1] = { name = "SetItemRef", link = link, text = text, button = button, frame = frame }
		end,
		IsModifiedClick = function() return modified end,
		GetFixedLink = function(text) return "fixed:" .. text end,
		HandleModifiedItemClick = function(link) calls[#calls + 1] = { name = "HandleModifiedItemClick", link = link } end,
		ItemRefTooltip = tooltip,
		ShowUIPanel = function(frame) if frame == tooltip then tooltip.shown = true end end,
		UIParent = {},
	}, { __index = _G })
	env._G = env -- rawget(_G, "C_EventScheduler") reads the stub
	local fn = assert(loadstring(chunk, "=ChatLinks.lua FollowLink"))
	setfenv(fn, env)
	fn()
	Check(type(E.FollowLink) == "function", "Core/ChatLinks.lua defines E:FollowLink")

	Reset()
	E:FollowLink("worldmap:1429:4000:6000", "|Hworldmap:1429:4000:6000|h[Map Pin Location]|h", "LeftButton")
	local set, open = Called("SetUserWaypoint"), Called("OpenWorldMapAt")
	Check(set ~= nil and set.point == waypoint, "a map pin link sets the game's waypoint")
	Check(open ~= nil and open.mapID == 1429, "a map pin link opens the map on the pin's map through the game's request")
	Check(Called("SetItemRef") == nil and NoGameOpener(), "a map pin link runs none of the game's map code")

	Reset()
	E:FollowLink("worldquest:123", "|Hworldquest:123|h[A quest]|h", "LeftButton")
	open = Called("OpenWorldMapAt")
	Check(open ~= nil and open.mapID == nil, "a world quest link opens the map through the game's request")
	Check(Called("SetItemRef") == nil and NoGameOpener(), "a world quest link runs none of the game's map code")

	Reset()
	E:FollowLink("eventpoi:77", "|Heventpoi:77|h[An event]|h", "LeftButton")
	open = Called("OpenWorldMapAt")
	Check(open ~= nil and open.mapID == 1453, "an event link opens the map on the event's map through the game's request")
	Check(Called("SetItemRef") == nil and NoGameOpener(), "an event link runs none of the game's map code")
	local tip = Called("ItemRefSetHyperlink")
	Check(tip ~= nil and tip.link == "eventpoi:77", "an event link still shows its tooltip, as SetItemRef did after the game's handler")

	Reset()
	modified = true
	E:FollowLink("eventpoi:78", "|Heventpoi:78|h[Another event]|h", "LeftButton")
	modified = false
	local insert = Called("HandleModifiedItemClick")
	Check(insert ~= nil and insert.link == "fixed:|Heventpoi:78|h[Another event]|h", "a Shift-click on an event link still puts it in chat")
	Check(Called("ItemRefSetHyperlink") == nil and Called("OpenWorldMapAt") == nil and NoGameOpener(),
		"an event without a map opens no map, and a modified click shows no tooltip")

	Reset()
	local chat = {}
	E:FollowLink("item:6948", "|Hitem:6948|h[Hearthstone]|h", "RightButton", chat)
	local ref = Called("SetItemRef")
	Check(ref ~= nil and ref.link == "item:6948" and ref.button == "RightButton" and ref.frame == chat,
		"every other link goes to the game's SetItemRef unchanged")
	Reset()
	E:FollowLink("player:Name", "|Hplayer:Name|h[Name]|h", "LeftButton")
	Check(Called("SetItemRef") ~= nil, "a player link goes to the game's SetItemRef")
	E.FollowLink = nil
end

---------------------------------------------------------------------------
-- No Lua file calls the game's map openers
---------------------------------------------------------------------------
local OPENERS = { "ToggleQuestLog", "ToggleWorldMap", "OpenWorldMap", "OpenQuestLog", "OpenMapToUserWaypoint",
	"OpenMapToEventPoi", "QuestMapFrame_OpenToQuestDetails" }

-- Lines that use one as code: a call, or the function handed on as a value
-- (pcall(ToggleWorldMap), C_Timer.After(0, ToggleQuestLog), _G.OpenWorldMap()).
-- Not C_Map.OpenWorldMap and not a method of EldoUI's own (E:OpenWorldMapAt);
-- outside comments.
local function DirectCalls(text)
	local found = {}
	for line in text:gmatch("[^\n]+") do
		local code = " " .. line:gsub("%-%-.*$", "") .. " "
		local hit = false
		for _, name in ipairs(OPENERS) do
			if code:find("[^%w_.:\"']" .. name .. "[^%w_\"']") or code:find("_G%." .. name .. "[^%w_]") then hit = true end
		end
		if code:find("QuestLogMicroButton:Click%(") or code:find("ZoneTextButton:Click%(") then hit = true end
		if hit then found[#found + 1] = line end
	end
	return found
end

-- Lines that name one in quotes (a global looked up by name, as the
-- Finder's panel list did), outside comments and post-hooks.
local function NamedCalls(text)
	local found = {}
	for line in text:gmatch("[^\n]+") do
		local code = line:gsub("%-%-.*$", "")
		if not code:find("hooksecurefunc%(") then
			for _, name in ipairs(OPENERS) do
				if code:find('"' .. name .. '"', 1, true) or code:find("'" .. name .. "'", 1, true) then found[#found + 1] = line end
			end
		end
	end
	return found
end

-- Lines that hand a link to SetItemRef, or hand SetItemRef on as a value
-- (pcall(SetItemRef, ...), local ref = SetItemRef). A post-hook only follows
-- the game, and a type(SetItemRef) check calls nothing.
local function ItemRefCalls(text)
	local found = {}
	for line in text:gmatch("[^\n]+") do
		local code = (line:gsub("%-%-.*$", ""):gsub("type%(%s*SetItemRef%s*%)", ""))
		if not code:find("hooksecurefunc%(") and (code:find("SetItemRef%s*%(") or code:find("SetItemRef%s*,")
			or code:find("=%s*SetItemRef%s*$") or code:find("=%s*SetItemRef[%s;]") or code:find("%(%s*SetItemRef%s*%)")) then
			found[#found + 1] = line
		end
	end
	return found
end

-- The Lua files a TOC loads, in its order.
local function TocFiles(toc)
	local dir = toc:match("^(.*/)")
	local list = {}
	for line in ReadFile(toc):gmatch("[^\n]+") do
		line = line:gsub("%s+$", "")
		if not line:find("^#") and line:find("%.lua$") then list[#list + 1] = dir .. line:gsub("\\", "/") end
	end
	return list
end

do
	local files, bad, refs = 0, {}, {}
	for _, toc in ipairs({ "EldoUI/EldoUI.toc", "EldoUI_GroupBoard/EldoUI_GroupBoard.toc", "EldoUI_LootSim/EldoUI_LootSim.toc" }) do
		for _, path in ipairs(TocFiles(toc)) do
			files = files + 1
			local text = ReadFile(path)
			local list = DirectCalls(text)
			for _, line in ipairs(NamedCalls(text)) do list[#list + 1] = line end
			for _, line in ipairs(list) do bad[#bad + 1] = path .. ": " .. line:gsub("^%s+", "") end
			if path ~= "EldoUI/Core/ChatLinks.lua" then
				for _, line in ipairs(ItemRefCalls(text)) do refs[#refs + 1] = path .. ": " .. line:gsub("^%s+", "") end
			end
		end
	end
	-- Key bindings run their Lua as EldoUI's too.
	local bindings = ReadFile("EldoUI/Bindings.xml")
	for _, line in ipairs(DirectCalls(bindings)) do bad[#bad + 1] = "EldoUI/Bindings.xml: " .. line:gsub("^%s+", "") end
	for _, line in ipairs(ItemRefCalls(bindings)) do refs[#refs + 1] = "EldoUI/Bindings.xml: " .. line:gsub("^%s+", "") end
	Check(files > 500, ("the TOCs list the addon's Lua files (%d found)"):format(files))
	Check(#bad == 0, "no Lua file opens the map or the quest log with the game's code: " .. table.concat(bad, " | "))
	Check(#refs == 0, "only Core/ChatLinks.lua hands links to SetItemRef: " .. table.concat(refs, " | "))
	-- Counter-checks: the checks find what they look for, and leave the
	-- game's own request and post-hooks alone.
	Check(#DirectCalls("\tif x then ToggleQuestLog() end\n") == 1, "counter-check: a direct ToggleQuestLog() is found")
	Check(#DirectCalls("\tbutton = QuestLogMicroButton:Click()\n") == 1, "counter-check: a click on the quest log button is found")
	Check(#DirectCalls("\tpcall(ToggleWorldMap)\n\tC_Timer.After(0, ToggleQuestLog)\n\tclose:SetScript(\"OnClick\", OpenQuestLog)\n") == 3,
		"counter-check: a map opener handed on as a value is found")
	Check(#DirectCalls("\t_G.ToggleWorldMap()\n") == 1, "counter-check: a map opener through _G is found")
	Check(#DirectCalls("\tfunction M:ToggleWorldMap() end\n\tlocal function OpenWorldMapAt() end\n") == 0,
		"counter-check: EldoUI's own names that only look alike are no call")
	Check(#DirectCalls("\tlocal open = C_Map and C_Map.OpenWorldMap\n\tpcall(C_Map.OpenWorldMap, id)\n") == 0,
		"counter-check: the game's own request C_Map.OpenWorldMap is no call")
	Check(#DirectCalls("\tE:OpenWorldMapAt()\n\tLG:OpenWorldMapAt(id)\n") == 0, "counter-check: EldoUI's own OpenWorldMapAt is no call")
	Check(#NamedCalls('\t{ text = "Quest log", fn = "ToggleQuestLog" },\n') == 1, "counter-check: a map opener named in quotes is found")
	Check(#NamedCalls('\thooksecurefunc("ToggleWorldMap", function() end)\n') == 0, "counter-check: a post-hook is no call")
	Check(#ItemRefCalls("\tview:SetScript(\"OnHyperlinkClick\", function(_, l, t, b) SetItemRef(l, t, b) end)\n") == 1,
		"counter-check: a link handed to SetItemRef is found")
	Check(#ItemRefCalls("\tpcall(SetItemRef, link, text)\n") == 1, "counter-check: SetItemRef through pcall is found")
	Check(#ItemRefCalls('\thooksecurefunc("SetItemRef", OnItemRef)\n') == 0, "counter-check: a SetItemRef post-hook is no call")
	Check(#ItemRefCalls("\tlocal ref = SetItemRef\n\tC_Timer.After(0, function() end) run(SetItemRef)\n") == 2,
		"counter-check: SetItemRef handed on as a value is found")
	Check(#ItemRefCalls('\tif type(SetItemRef) == "function" then\n\tif x and SetItemRef then\n') == 0,
		"counter-check: a check that SetItemRef exists is no call")
end

print(("%d checks passed, %d failed"):format(passed, failures))
os.exit(failures == 0 and 0 or 1)
