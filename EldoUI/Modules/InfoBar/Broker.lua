-- EldoUI Info Bar: blocks for other addons (LibDataBroker).
--
-- Titan Panel, ChocolateBar, Bazooka and other LibDataBroker displays show
-- the "data objects" addons publish. The player picks up to eight Info Bar
-- blocks (Datatexts tab, "Block 1 for other addons" and on); each becomes a
-- data source named "EldoUI: <block>" with the block's text, icon and
-- tooltip, and a click on it does what a click on the block does. Only
-- picked blocks are published: some displays put every new object on their
-- bar, and the player decides which blocks go there. The feeds of other
-- addons ("LDB: ..." blocks) are never handed back.
--
-- EldoUI does not ship LibDataBroker-1.1; every display brings it. Until an
-- addon has loaded it there is nothing to publish to, so this looks again
-- as addons load. The library can't take an object back: a block taken out
-- of the list (or the module switched off) stops updating and shows "Off"
-- until the next reload.
--
-- A display does not say which objects it shows, so a picked block is kept
-- current as on a bar: on its events, on its poll interval (1 s unless it
-- asks for another) and whenever the Info Bar refreshes it. A text the game
-- keeps secret (in combat) is not handed on, because the library compares
-- every new value with the old one; the object keeps its last readable
-- text. The mouse wheel has no LibDataBroker counterpart, and a block that
-- only works through a secure button on the bar (the Hearthstone) shows its
-- text there but does nothing on a click.
local _, E = ...
local L = E.L
local M = E.modules.InfoBar

local PREFIX = "EldoUI: "
local TICK_KEY = "InfoBar:broker"

local Broker = {
	objects = {},  -- block name -> data object (stays for the session)
	owned = {},    -- data object name -> block name
	live = {},     -- block name -> true while it is picked and kept current
	events = {},   -- event -> { block names }
	elapsed = {},  -- block name -> seconds since its last poll
}
M.broker = Broker

local function Library()
	local stub = _G.LibStub
	local ldb = stub and stub("LibDataBroker-1.1", true)
	if ldb and ldb.NewDataObject and ldb.GetDataObjectByName then return ldb end
end

-- Is this data object one of ours? (Info Bar's own LDB bridge skips them.)
function Broker.Owns(objectName)
	return Broker.owned[objectName] ~= nil
end

-- Can this block go to other addons? Everything but their own feeds.
function Broker.Offered(name)
	local definition = type(name) == "string" and name ~= "" and E.dataTexts[name]
	return type(definition) == "table" and not definition.broker and type(definition.text) == "function"
end

-- The picked blocks, each once, in slot order.
function Broker.Picked()
	local list, seen = {}, {}
	local slots = M.db and type(M.db.ldbBlocks) == "table" and M.db.ldbBlocks or {}
	for slot = 1, #M.defaults.ldbBlocks do
		local name = slots[slot]
		if Broker.Offered(name) and not seen[name] then
			seen[name] = true
			list[#list + 1] = name
		end
	end
	return list
end

-- A block's readable text, or nil (an error, nothing, or a secret value).
function Broker.Text(name)
	local definition = E.dataTexts[name]
	if not definition then return nil end
	local ok, text = pcall(definition.text)
	if not ok or text == nil or E.Secret(text) then return nil end
	if type(text) ~= "string" then text = tostring(text) end
	return text
end

local function OffText()
	return E:TextHex("secondary") .. L["Off"] .. "|r"
end

-- A click from the display: the block's own click, with the Info Bar's
-- combat rule (M.ClickBlock). The display's frame is the owner, so menus
-- open there.
local function Click(name, frame, mouseButton)
	local definition = E.dataTexts[name]
	if not (Broker.live[name] and definition and definition.onClick) then return end
	if definition.combatClick or not InCombatLockdown() then
		definition.onClick(frame, mouseButton)
		Broker.Refresh(name)
	elseif E.UIKit and E.UIKit.Toast then
		E.UIKit.Toast(frame, L["Not in combat."], { warn = true })
	end
end

local function TooltipShow(name, tooltip)
	local definition = E.dataTexts[name]
	if not (definition and definition.tooltip) then return end
	if Broker.live[name] then
		M.TooltipLines(tooltip, name, definition, false)
	else
		tooltip:AddLine(L[definition.title or name])
		tooltip:AddLine(OffText())
	end
end

local function Icon(definition)
	local icon = definition.icon
	if type(icon) == "string" or type(icon) == "number" then return icon end
end

-- Publish one block (once per session). False when the name is taken.
function Broker.Publish(ldb, name)
	if Broker.objects[name] then return true end
	local definition = E.dataTexts[name]
	local objectName = PREFIX .. name
	if ldb:GetDataObjectByName(objectName) then return false end
	-- Before NewDataObject: the Info Bar's own bridge hears of the object
	-- from inside that call and must already know it is ours.
	Broker.owned[objectName] = name
	local object = ldb:NewDataObject(objectName, {
		type = "data source",
		label = L[definition.title or name],
		text = Broker.Text(name) or "",
		icon = Icon(definition),
		tocname = "EldoUI",
		OnTooltipShow = definition.tooltip and function(tooltip) TooltipShow(name, tooltip) end or nil,
		OnClick = definition.onClick and function(frame, mouseButton) Click(name, frame, mouseButton) end or nil,
	})
	if not object then
		Broker.owned[objectName] = nil
		return false
	end
	Broker.objects[name] = object
	return true
end

-- Hand a picked block's current text to its object.
function Broker.Refresh(name)
	local object = Broker.live[name] and Broker.objects[name]
	if not object then return end
	local text = Broker.Text(name)
	if text and object.text ~= text then object.text = text end
end

function Broker.OnEvent(_, event)
	for _, name in ipairs(Broker.events[event] or {}) do Broker.Refresh(name) end
end

function Broker.Tick(elapsed)
	for name in pairs(Broker.live) do
		local definition = E.dataTexts[name]
		if definition and definition.poll then
			Broker.elapsed[name] = (Broker.elapsed[name] or 0) + elapsed
			if Broker.elapsed[name] >= (definition.interval or 1) and (not definition.pollWhen or definition.pollWhen()) then
				Broker.elapsed[name] = 0
				Broker.Refresh(name)
			end
		end
	end
end

-- Stop keeping blocks current; the ones published show "Off".
function Broker.Stop()
	if Broker.frame then Broker.frame:UnregisterAllEvents() end
	E.Ticker:Unsubscribe(TICK_KEY)
	for name in pairs(Broker.live) do
		local object = Broker.objects[name]
		if object then object.text = OffText() end
	end
	Broker.live, Broker.events, Broker.elapsed = {}, {}, {}
end

-- Look again for the library as addons load (a display may load after EldoUI).
local function Watch()
	if not Broker.watcher then
		Broker.watcher = CreateFrame("Frame")
		Broker.watcher:SetScript("OnEvent", function()
			if Library() then
				Broker.watcher:UnregisterAllEvents()
				Broker.Sync()
			end
		end)
	end
	Broker.watcher:RegisterEvent("ADDON_LOADED")
	Broker.watcher:RegisterEvent("PLAYER_LOGIN")
end

-- Publish the picked blocks and keep exactly those current. Runs with
-- every Info Bar rebuild (enable, profile, options, a new block).
function Broker.Sync()
	local picked = M.active and Broker.Picked() or {}
	if #picked == 0 then
		Broker.Stop()
		return
	end
	local ldb = Library()
	if not ldb then
		Broker.Stop()
		Watch()
		return
	end
	local live = {}
	for _, name in ipairs(picked) do
		if Broker.Publish(ldb, name) then live[name] = true end
	end
	-- Blocks taken out of the list show "Off" from now on.
	for name in pairs(Broker.live) do
		local object = Broker.objects[name]
		if not live[name] and object then object.text = OffText() end
	end
	Broker.live, Broker.events = live, {}
	if not Broker.frame then
		Broker.frame = CreateFrame("Frame")
		Broker.frame:SetScript("OnEvent", Broker.OnEvent)
	end
	Broker.frame:UnregisterAllEvents()
	local polls = false
	for name in pairs(live) do
		local definition = E.dataTexts[name]
		for _, event in ipairs(definition.events or {}) do
			if not Broker.events[event] then
				Broker.events[event] = {}
				-- As on the bars: UNIT_* events for the player only.
				if event:find("^UNIT_") then
					pcall(Broker.frame.RegisterUnitEvent, Broker.frame, event, "player")
				else
					pcall(Broker.frame.RegisterEvent, Broker.frame, event)
				end
			end
			table.insert(Broker.events[event], name)
		end
		if definition.poll then polls = true end
		Broker.Refresh(name)
	end
	if polls then
		E.Ticker:Subscribe(TICK_KEY, 0.25, Broker.Tick, M)
	else
		E.Ticker:Unsubscribe(TICK_KEY)
	end
end

hooksecurefunc(M, "Rebuild", function() Broker.Sync() end)
-- A block the Info Bar refreshes by name (mail, rolls and the like) is
-- handed on at the same time.
hooksecurefunc(M, "RefreshDataText", function(_, key) Broker.Refresh(key) end)
M:AddExtra({ Disable = function() Broker.Stop() end })
