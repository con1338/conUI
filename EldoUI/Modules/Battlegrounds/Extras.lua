-- Battleground Timers: extras. Chat reports and Alterac Valley helpers,
-- within what the game allows.
--
-- Share (off by default): Shift-click a bar and its text ("Lumber Mill
-- (Horde) 0:41") goes into the chat box. The player sends it with Enter,
-- or edits it; EldoUI never sends a chat message. Bars only take the
-- mouse while this is on.
-- Turn-in reminder (Alterac Valley): how many hand-in items you carry
-- (C_Item.GetItemCount on BAG_UPDATE_DELAYED) and who takes them. It never
-- talks to an NPC, picks a gossip option or completes a quest.
-- Owners (Alterac Valley): a small chip per mine in its owner's color,
-- from the capture engine's settled POIs: the ones listed in
-- MapData.resources, or whose icon name marks a mine.
local _, E = ...
local L = E.L
local M = E:GetModule("Battlegrounds")
local Read, IsSecret = M.Read, M.IsSecret

local X = M:AddPart({ name = "extras" })
M.Extras = X

---------------------------------------------------------------------------
-- Share to the chat box
---------------------------------------------------------------------------
-- The text a bar puts in the chat box.
function M:ShareText(key, data)
	if type(data) ~= "table" or IsSecret(data.label) or type(data.label) ~= "string" then return nil end
	local text = data.label
	if data.side then text = ("%s (%s)"):format(text, self:SideName(data.side)) end
	local left = self:Remaining(key)
	if not IsSecret(data.frozenText) and data.frozenText and data.frozenText ~= "" then
		text = text .. " " .. data.frozenText
	elseif type(left) == "number" and left > 0 then
		text = text .. " " .. E.TimerBars.FormatTime(left)
	end
	return text
end

local function PutInChatBox(text)
	local util = ChatFrameUtil
	if util and util.InsertLink and util.InsertLink(text) then return true end
	if util and util.OpenChat then
		util.OpenChat(text)
		return true
	end
	return false
end

function M:ShareBar(key, data, button)
	if not self.db.share or button ~= "LeftButton" or not IsShiftKeyDown() then return end
	local text = self:ShareText(key, data)
	if text then PutInChatBox(text) end
end

---------------------------------------------------------------------------
-- Alterac Valley turn-ins
---------------------------------------------------------------------------
local function ItemName(itemID)
	local name = Read(C_Item.GetItemNameByID, itemID)
	if type(name) == "string" and name ~= "" then return name end
	return L["Item %d"]:format(itemID)
end

function X:UpdateTurnIns()
	local map = M.map
	local items = map and map.turnIns
	if not (items and M.db.turnIns) then
		M:StopPrefix("turnin:")
		return
	end
	for itemID, role in pairs(items) do
		local key = "turnin:" .. itemID
		local count = Read(C_Item.GetItemCount, itemID)
		if type(count) == "number" and count > 0 then
			local who = M.TURN_IN_ROLES[role] or role
			M:Freeze(key, {
				kind = "other",
				label = L["%s: %s"]:format(ItemName(itemID), who),
				icon = Read(C_Item.GetItemIconByID, itemID),
				tooltip = L["You carry these. Hand them in yourself; EldoUI never hands anything in."],
			}, tostring(count))
		else
			M:Stop(key)
		end
	end
end

---------------------------------------------------------------------------
-- Mine owners (called by the capture engine for every POI it reads)
---------------------------------------------------------------------------
function M:UpdateOwner(id, entry, map)
	local key = "owner:" .. id
	if not (map and self.db.owners and (entry.resource or (map.resources and map.resources[id]))) then
		self:Stop(key)
		return
	end
	if entry.side and entry.assault ~= true and not self:HasBar("poi:" .. id) then
		self:Freeze(key, { kind = entry.side, side = entry.side, label = entry.name,
			tooltip = L["Owned by %s."]:format(self:SideName(entry.side)) }, "")
	else
		self:Stop(key)
	end
end

function M:ForgetOwner(id)
	self:Stop("owner:" .. id)
end

---------------------------------------------------------------------------
-- Part hooks
---------------------------------------------------------------------------
function X:Enable()
	M:RegisterEvent("BAG_UPDATE_DELAYED", function() if M.map then X:UpdateTurnIns() end end)
end

function X:Disable()
	M:UnregisterEvent("BAG_UPDATE_DELAYED")
end

function X:Enter()
	self:UpdateTurnIns()
end

function X:Leave()
	M:StopPrefix("turnin:")
	M:StopPrefix("owner:")
end

function X:Refresh()
	self:UpdateTurnIns()
	if not M.db.owners then M:StopPrefix("owner:") end
end
