-- EldoUI chat links (E:ChatLink / E:RegisterChatLink).
--
-- A clickable word in EldoUI's own chat lines ("[Open the run log]",
-- "[Apply talents]"):
--
--   E:RegisterChatLink("instances", function(data, button, text, chatFrame)
--       Instances:OpenLog(data)
--   end)
--   E:Print(("Too many instances. %s"):format(E:ChatLink("instances", "log", "Open the run log")))
--
-- The link is |Haddon:EldoUI:<kind>:<data>|h[label]|h in the accent color
-- (or the color passed). Clicks reach the handler through the game's
-- SetItemRef. Links only work in the player's own chat window: they are
-- for lines EldoUI prints, never for messages sent to other players.
-- kind: letters, digits and "_"; data: any text without "|" (it is cut
-- at 200 characters).
local _, E = ...

local PREFIX = "addon:EldoUI:"
local handlers = {}

local function Hex(r, g, b)
	return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function E:RegisterChatLink(kind, handler)
	if type(kind) ~= "string" or not kind:match("^[%w_]+$") or type(handler) ~= "function" then return false end
	handlers[kind] = handler
	return true
end

function E:UnregisterChatLink(kind)
	handlers[kind] = nil
end

-- The link text. color: { r, g, b } (default the accent).
function E:ChatLink(kind, data, label, color)
	if type(kind) ~= "string" or not kind:match("^[%w_]+$") then return label or "" end
	data = E:Utf8Clip((tostring(data or ""):gsub("|", "")), 200)
	label = tostring(label or kind):gsub("|", "")
	local r, g, b
	if type(color) == "table" then
		r, g, b = color[1] or color.r, color[2] or color.g, color[3] or color.b
	end
	if not r then r, g, b = unpack(self.media.accentColor) end
	return ("|cff%s|H%s%s:%s|h[%s]|h|r"):format(Hex(r, g, b), PREFIX, kind, data, label)
end

-- kind, data of an EldoUI link, or nil.
function E:ParseChatLink(link)
	if type(link) ~= "string" or link:sub(1, #PREFIX) ~= PREFIX then return nil end
	local kind, data = link:sub(#PREFIX + 1):match("^([%w_]+):?(.*)$")
	return kind, data
end

local function OnItemRef(link, text, button, chatFrame)
	local kind, data = E:ParseChatLink(link)
	local handler = kind and handlers[kind]
	if not handler then return end
	local ok, err = pcall(handler, data, button, text, chatFrame)
	if not ok then geterrorhandler()(err) end
end

if type(SetItemRef) == "function" then hooksecurefunc("SetItemRef", OnItemRef) end

---------------------------------------------------------------------------
-- A link clicked in one of EldoUI's own message windows
---------------------------------------------------------------------------
-- E:FollowLink(link, text, button, frame) hands the click to the game's
-- SetItemRef, as a chat window does. Except the links that open the world
-- map (a map pin, a world quest, an event spot): the game's handlers for
-- them run the map's own code (OpenWorldMap), and called from an EldoUI
-- window that code runs as EldoUI's. The map's state then stays tainted,
-- and the game's later opens of it (L, M, Escape) get their map pins
-- blocked: "Blocked: EldoUI tried to call the protected function
-- SetPassThroughButtons()" (review/fehler.md F29). Those links set the
-- waypoint as the game does and open the map through the game's own
-- request (E:OpenWorldMapAt), without the game's ping on the pin; an event
-- link keeps its tooltip and Shift-click, as with SetItemRef.
local function PlainMapID(value)
	if E:IsSecret(value) or type(value) ~= "number" then return nil end
	return value
end

local MAP_LINKS = {
	worldmap = function(link)
		local map = C_Map
		if not (map and type(map.GetUserWaypointFromHyperlink) == "function" and type(map.SetUserWaypoint) == "function") then return end
		local ok, waypoint = pcall(map.GetUserWaypointFromHyperlink, link)
		if not ok or E:IsSecret(waypoint) or type(waypoint) ~= "table" then return end
		local done, set = pcall(map.SetUserWaypoint, waypoint)
		if done and set and not E:IsSecret(set) then E:OpenWorldMapAt(PlainMapID(waypoint.uiMapID)) end
	end,
	eventpoi = function(link, text)
		local scheduler = rawget(_G, "C_EventScheduler")
		local areaPoiID = tonumber((link:match("^eventpoi:(%d+)")))
		local mapID
		if areaPoiID and scheduler and type(scheduler.GetEventUiMapID) == "function" then
			local ok, id = pcall(scheduler.GetEventUiMapID, areaPoiID)
			mapID = ok and PlainMapID(id) or nil
		end
		if mapID then E:OpenWorldMapAt(mapID) end
		-- The game's handler leaves the rest to SetItemRef ("Unhandled"): a
		-- modified click puts the link in chat, a click shows its tooltip.
		-- The same steps here, without the handler's map code.
		if IsModifiedClick() then
			local fix = rawget(_G, "GetFixedLink")
			local fixed = type(fix) == "function" and type(text) == "string" and fix(text) or text
			if type(HandleModifiedItemClick) == "function" then HandleModifiedItemClick(fixed) end
		else
			local tip = rawget(_G, "ItemRefTooltip")
			if not (tip and type(tip.ItemRefSetHyperlink) == "function") then return end
			ShowUIPanel(tip)
			if not tip:IsShown() then tip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
			tip:ItemRefSetHyperlink(link)
		end
	end,
	worldquest = function() E:OpenWorldMapAt() end,
}
E.MAP_LINKS = MAP_LINKS -- exposed for inspection

function E:FollowLink(link, text, button, frame)
	local kind = type(link) == "string" and not E:IsSecret(link) and link:match("^([%w_]+):")
	local open = kind and MAP_LINKS[kind]
	if open then return open(link, text) end
	return SetItemRef(link, text, button, frame)
end

---------------------------------------------------------------------------
-- Item, spell and quest links into the chat box (or a focused EldoUI box)
---------------------------------------------------------------------------
-- Blizzard's own code puts a shift-clicked link in with
-- ChatFrameUtil.InsertLink; ChatEdit_InsertLink is only a deprecated alias
-- that will go away. Both helpers use the new name and keep the old one as
-- the fallback.

-- Put `link` in the active chat box (or the box that takes links). True
-- when something took it.
function E:InsertLink(link)
	if type(link) ~= "string" or link == "" then return false end
	local util = rawget(_G, "ChatFrameUtil")
	local insert = type(util) == "table" and util.InsertLink or rawget(_G, "ChatEdit_InsertLink")
	if type(insert) ~= "function" then return false end
	return insert(link) and true or false
end

-- Run fn(link) after every link insert, however Blizzard or an addon calls
-- it. One insert that goes through both names runs fn once.
function E:HookLinkInsert(fn)
	local lastLink, lastTime
	local function Hook(link)
		local now = GetTime()
		if link == lastLink and now == lastTime then return end
		lastLink, lastTime = link, now
		fn(link)
	end
	local util = rawget(_G, "ChatFrameUtil")
	if type(util) == "table" and type(util.InsertLink) == "function" then hooksecurefunc(util, "InsertLink", Hook) end
	if type(rawget(_G, "ChatEdit_InsertLink")) == "function" then hooksecurefunc("ChatEdit_InsertLink", Hook) end
end
