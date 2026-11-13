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
