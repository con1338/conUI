-- EldoUI Characters: mail and auctions of every character.
--
-- The "Mail and AH" tab lists every saved mail (sender, subject, items, gold,
-- days left), every running auction and every bid, as each character saw
-- them on its last visit. At login, two optional chat reminders: mail that
-- runs out soon, and characters with auctions who have not visited the
-- auction house for a while. Reminders are local chat lines only.
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit
local M = E.modules.Characters

local function Store() return E.Characters end

local function Grey(text) return M.Grey(text) end

local function Short(link, id)
	local short = Store().ShortItem(link)
	return short or (id and "item:" .. id)
end

-- Days-left color: red under a day, yellow under the warning time.
local function LeftText(at)
	if not at then return "" end
	local left = at - Store().Now()
	if left <= 0 then return M.Bad(L["ended"]) end
	local text = M.Duration(left)
	if left < 86400 then return M.Bad(text) end
	if left < (M.db.warnMailDays or 5) * 86400 then return M.Warn(text) end
	return text
end

local function ItemText(short, count)
	if not short then return "" end
	local id = Store().ItemIDOf(short)
	local name, _, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(short)
	if not name and id and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	local text = name or ("item:" .. tostring(id))
	if color and color.hex then text = color.hex .. text .. "|r" end
	icon = icon or (id and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
	return (icon and ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(icon) or "") .. text .. ((count or 1) > 1 and Grey(" x" .. count) or "")
end

-- Rows for one view: "mail", "auctions" or "bids".
function M:MailRows(view)
	local rows = {}
	for _, key in ipairs(self:Keys()) do
		local record = Store():Get(key)
		if view == "mail" then
			for _, mail in ipairs(type(record.mailMeta) == "table" and record.mailMeta or {}) do
				rows[#rows + 1] = { key = key, record = record, mail = mail, at = mail.expires }
			end
		else
			local auctions = type(record.auctions) == "table" and record.auctions or {}
			for _, auction in ipairs(type(auctions[view == "bids" and "bids" or "list"]) == "table" and auctions[view == "bids" and "bids" or "list"] or {}) do
				rows[#rows + 1] = { key = key, record = record, auction = auction, short = Short(auction.link, auction.id), at = auction.endsAt }
			end
		end
	end
	return rows
end

local function NameColumn()
	return { key = "name", title = L["Character"], width = 150, value = function(row) return row.record.name or "" end,
		text = function(row) return M.ClassIcon(row.record.class, 14) .. M.ClassName(row.record) end }
end

local COLUMNS = {
	mail = {
		NameColumn(),
		{ key = "sender", title = "From", width = 130, value = function(row) return row.mail.sender or "" end },
		{ key = "subject", title = "Subject", value = function(row) return row.mail.subject or "" end,
			text = function(row) return (row.mail.subject or "") .. (row.mail.returned and Grey(" " .. L["(returned)"]) or "") end },
		{ key = "items", title = "Items", width = 60, align = "RIGHT", value = function(row) return row.mail.items or 0 end },
		{ key = "money", title = "Gold", width = 110, align = "RIGHT", value = function(row) return (row.mail.money or 0) - (row.mail.cod or 0) end,
			text = function(row)
				if (row.mail.cod or 0) > 0 then return M.Bad(L["COD"]) .. " " .. M.Money(row.mail.cod) end
				return (row.mail.money or 0) > 0 and M.Money(row.mail.money) or ""
			end },
		{ key = "left", title = "Runs out in", width = 100, align = "RIGHT", value = function(row) return row.at or 0 end,
			text = function(row) return LeftText(row.at) end },
	},
	auctions = {
		NameColumn(),
		{ key = "item", title = "Item", value = function(row) return row.short or "" end, text = function(row) return ItemText(row.short, row.auction.count) end },
		{ key = "bid", title = "Bid", width = 110, align = "RIGHT", value = function(row) return row.auction.bid or 0 end,
			text = function(row) return (row.auction.bid or 0) > 0 and M.Money(row.auction.bid) or "" end },
		{ key = "buyout", title = "Buyout", width = 110, align = "RIGHT", value = function(row) return row.auction.buyout or 0 end,
			text = function(row) return (row.auction.buyout or 0) > 0 and M.Money(row.auction.buyout) or "" end },
		{ key = "left", title = "Ends in", width = 100, align = "RIGHT", value = function(row) return row.at or 0 end,
			text = function(row) return row.at and LeftText(row.at) or Grey("?") end },
	},
	bids = {
		NameColumn(),
		{ key = "item", title = "Item", value = function(row) return row.short or "" end, text = function(row) return ItemText(row.short, row.auction.count) end },
		{ key = "bid", title = "Your bid", width = 110, align = "RIGHT", value = function(row) return row.auction.bid or 0 end,
			text = function(row) return (row.auction.bid or 0) > 0 and M.Money(row.auction.bid) or "" end },
		{ key = "buyout", title = "Buyout", width = 110, align = "RIGHT", value = function(row) return row.auction.buyout or 0 end,
			text = function(row) return (row.auction.buyout or 0) > 0 and M.Money(row.auction.buyout) or "" end },
	},
}

local EMPTY = {
	mail = { Key("No mail"), Key("None of these characters had mail at their last mailbox visit. Mail you send to your own characters shows up at once.") },
	auctions = { Key("No auctions"), Key("None of these characters had auctions running at their last auction house visit.") },
	bids = { Key("No bids"), Key("None of these characters had bids at their last auction house visit.") },
}

local function Build(frame, view)
	for _, tbl in pairs(frame.tables) do tbl:Hide() end
	local tbl = frame.tables[view]
	if not tbl then
		tbl = Kit.CreateTable(frame, COLUMNS[view], {
			sortKey = view == "bids" and "name" or "left", rowHeight = 18,
			onClick = function(row, button, widget)
				if button == "RightButton" then
					M:ShowCharacterMenu(widget, row.key)
				elseif row.short and IsModifiedClick() and HandleModifiedItemClick then
					local _, link = C_Item.GetItemInfo(row.short)
					HandleModifiedItemClick(link or row.short)
				end
			end,
			createRow = function(widget)
				widget:HookScript("OnEnter", function(own)
					local row = own.item
					if not row then return end
					GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
					if row.short then
						GameTooltip:SetHyperlink(row.short)
					else
						M:CharacterTooltip(GameTooltip, row.key)
					end
					GameTooltip:Show()
				end)
				widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
			end,
			empty = { L[EMPTY[view][1]], L[EMPTY[view][2]] },
		})
		tbl:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -6)
		tbl:SetPoint("BOTTOMRIGHT")
		frame.tables[view] = tbl
	end
	tbl:Show()
	return tbl
end

local function VisitText(view)
	if view == "mail" then return L["Gold and items as of each character's last mailbox visit."] end
	return L["As of each character's last auction house visit."]
end

local function Update(frame)
	local view = next(frame.view:GetSelected()) or "mail"
	local tbl = Build(frame, view)
	local rows = M:MailRows(view)
	frame.rows = rows
	tbl:SetData(rows)
	frame.note:SetText(VisitText(view))
end
M.UpdateMail = Update

M:AddTab({
	key = "mail", order = 40, title = "Mail and AH",
	desc = "Every character's mail with the days left, running auctions and bids.",
	count = function()
		local soon = 0
		for _, key in ipairs(M:Keys()) do
			local _, count = M.MailInfo(Store():Get(key), M.db.warnMailDays)
			soon = soon + count
		end
		return soon > 0 and soon or nil
	end,
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.tables = {}
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(20)
		frame.view = Kit.ChipBar(frame.toolbar, {
			selected = "mail",
			chips = {
				{ "mail", L["Mail"], L["Every saved mail with sender, items, gold and the time until it is returned or deleted."] },
				{ "auctions", L["Auctions"], L["Every running auction with its bid, buyout and time left."] },
				{ "bids", L["Bids"], L["Auctions your characters have bid on."] },
			},
			onChange = function(selected, key)
				if not next(selected) then frame.view:SetSelected(key) end
				Update(frame)
			end,
		})
		frame.view:SetPoint("LEFT", 2, 0)
		frame.note = Kit.Text(frame.toolbar, 11, "RIGHT", "dim")
		frame.note:SetPoint("RIGHT", -4, 0)
		frame.note:SetPoint("LEFT", frame.view, "RIGHT", 10, 0)
		return frame
	end,
	show = function(frame, arg)
		if arg == "mail" or arg == "auctions" or arg == "bids" then frame.view:SetSelected(arg) end
		Update(frame)
	end,
	refresh = function(frame) Update(frame) end,
	-- Once per session, a few seconds after login.
	enable = function()
		if M.remindersDone then return end
		M.remindersDone = true
		C_Timer.After(10, function() M:PrintReminders() end)
	end,
})

---------------------------------------------------------------------------
-- Login reminders (local chat lines; all characters on the account)
---------------------------------------------------------------------------
function M:Reminders()
	local lines = {}
	local now = Store().Now()
	for _, key in ipairs(Store():Keys("account")) do
		local record = Store():Get(key)
		if self.db.warnMail then
			local count, soonest = 0
			for _, mail in ipairs(type(record.mailMeta) == "table" and record.mailMeta or {}) do
				local left = (mail.expires or 0) - now
				if left > -86400 and left < self.db.warnMailDays * 86400 then
					count = count + 1
					soonest = math.min(soonest or left, left)
				end
			end
			if count > 0 then
				lines[#lines + 1] = L["%s: %d mail runs out soon (first in %s). Log in and empty the mailbox."]:format(
					M.ClassName(record, true), count, soonest > 0 and M.Duration(soonest) or L["now"])
			end
		end
		local auctions = type(record.auctions) == "table" and record.auctions
		if self.db.warnAuction and auctions and type(auctions.list) == "table" and #auctions.list > 0 then
			local visited = auctions.visited or auctions.at
			if visited and now - visited > self.db.warnAuctionDays * 86400 then
				lines[#lines + 1] = L["%s: %d auctions, last auction house visit %d days ago."]:format(
					M.ClassName(record, true), #auctions.list, math.floor((now - visited) / 86400))
			end
		end
	end
	return lines
end

function M:PrintReminders()
	if not self.active then return end
	for _, line in ipairs(self:Reminders()) do E:Print(line) end
end

