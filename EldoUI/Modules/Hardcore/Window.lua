-- EldoUI Hardcore: the death log window. A UIKit window on its own
-- mover (EldoUI_DeathLog, top center): filter chips (all, guild, group,
-- you), a search box, Clear log, and one row per death (time, name, level,
-- zone, cause, where it came from). A row's tooltip shows the game's own
-- line; a click does nothing else.
local _, E = ...
local L = E.L
local Kit = E.UIKit
local M = E.Hardcore

local MOVER = "EldoUI_DeathLog"
local SIZE = { 520, 340 }
local POINT = { "TOP", "UIParent", "TOP", 0, -132 }

local function Grey(text) return E:TokenHex(Kit.SECONDARY) .. text .. "|r" end

local SOURCE_TEXT = { game = "Game", guild = "Guild note", both = "Game and note" }
local REL_TEXT = { self = "You", group = "Group", guild = "Guild", realm = "Realm" }

local function TimeText(t)
	if type(t) ~= "number" then return "" end
	return E:When(t)
end

local function NameText(entry)
	local name = entry.name or "?"
	if M.db.classColors and entry.class then return E:WrapClassColor(entry.class, name) end
	return name
end

function M:Columns()
	return {
		{ key = "t", title = L["Time"], width = 64, value = function(entry) return entry.t or 0 end,
			text = function(entry) return Grey(TimeText(entry.t)) end },
		{ key = "name", title = L["Name"], width = 110, value = function(entry) return entry.name or "" end, text = NameText },
		{ key = "level", title = L["Level"], width = 44, align = "RIGHT", value = function(entry) return entry.level or 0 end,
			text = function(entry) return entry.level and tostring(entry.level) or Grey("?") end },
		{ key = "zone", title = L["Zone"], width = 120, value = function(entry) return entry.zone or "" end,
			text = function(entry) return entry.zone or Grey(L["unknown"]) end },
		{ key = "cause", title = L["Cause"], value = function(entry) return M.CauseText(entry) end,
			text = function(entry)
				local cause = M.CauseText(entry)
				return cause ~= "" and cause or Grey(L["not given"])
			end },
		{ key = "rel", title = L["Who"], width = 58, value = function(entry) return entry.rel or "" end,
			text = function(entry) return L[REL_TEXT[entry.rel] or "Realm"] end,
			desc = L["You, a group member, a guild member, or anyone else on the realm."] },
	}
end

-- The rows the filter and search let through, newest first.
function M:FilteredLog()
	local filter, query = self.filter or "all", self.query
	query = query and E:FoldText(query) or ""
	if query == "" then query = nil end
	local rows = {}
	local list = self:Log()
	for index = #list, 1, -1 do
		local entry = list[index]
		local pass = filter == "all" or entry.rel == filter
			or (filter == "guild" and entry.source ~= "game" and entry.rel ~= "self")
		if pass and query then
			local hay = E:FoldText((entry.name or "") .. " " .. (entry.zone or "") .. " " .. M.CauseText(entry))
			pass = hay:find(query, 1, true) ~= nil
		end
		if pass then rows[#rows + 1] = entry end
	end
	return rows
end

local function Body(wrap)
	local c = E.tokens.text.body
	return c[1], c[2], c[3], wrap
end

local function RowTooltip(entry)
	GameTooltip:AddLine(NameText(entry))
	if entry.level then GameTooltip:AddLine(L["Level %d"]:format(entry.level), unpack(Kit.SECONDARY)) end
	local cause = M.CauseText(entry)
	if cause ~= "" then GameTooltip:AddLine(cause, Body(true)) end
	if entry.text and not entry.cause then GameTooltip:AddLine(entry.text, Body(true)) end
	GameTooltip:AddLine(L["From: %s"]:format(L[SOURCE_TEXT[entry.source] or "Game"]), unpack(Kit.SECONDARY))
	if type(entry.t) == "number" then GameTooltip:AddLine(E:ShortDate(entry.t), unpack(Kit.SECONDARY)) end
end

local function CreateTab(content)
	local frame = CreateFrame("Frame", nil, content)
	frame:SetAllPoints()
	frame.toolbar = CreateFrame("Frame", nil, frame)
	frame.toolbar:SetPoint("TOPLEFT")
	frame.toolbar:SetPoint("TOPRIGHT")
	frame.toolbar:SetHeight(E.tokens.height.button)
	frame.chips = Kit.ChipBar(frame.toolbar, {
		chips = {
			{ "all", L["All"], L["Every death in the log."] },
			{ "guild", L["Guild"], L["Guild members, also those who told the guild themselves."] },
			{ "group", L["Group"], L["Members of your party or raid."] },
			{ "self", L["You"], L["Your own deaths."] },
		},
		selected = M.filter or "all",
		onChange = function(selected)
			M.filter = next(selected) or "all"
			M:RefreshWindow()
		end,
	})
	frame.chips:SetPoint("LEFT", 0, 0)
	frame.clear = Kit.Button(frame.toolbar, L["Clear log"], 90, nil, function(button)
		if button.armed then
			button.armed = nil
			button:SetText(L["Clear log"])
			M:ClearLog()
		else
			button.armed = true
			button:SetText(L["Click again"])
			C_Timer.After(4, function()
				if button.armed then
					button.armed = nil
					button:SetText(L["Clear log"])
				end
			end)
		end
	end, L["Clear log"], L["Remove every entry from the death log. Click twice to confirm."])
	frame.clear:SetPoint("RIGHT", 0, 0)
	frame.status = Kit.Text(frame.toolbar, E.tokens.size.small, "RIGHT", "secondary")
	frame.status:SetPoint("RIGHT", frame.clear, "LEFT", -8, 0)
	frame.status:SetPoint("LEFT", frame.chips, "RIGHT", 8, 0)
	return frame
end

local function BuildTable(frame)
	if frame.tbl then
		frame.tbl:Hide()
		frame.tbl:SetParent(nil)
		frame.tbl = nil
	end
	local tbl = Kit.CreateTable(frame, M:Columns(), {
		sortKey = "t", sortDown = true, rowHeight = M.db.rowHeight,
		empty = { L["No deaths logged"], L["Deaths the game announces, and deaths guild members tell the guild about, show here."] },
		createRow = function(row)
			row:HookScript("OnEnter", function(own)
				if not own.item then return end
				GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
				RowTooltip(own.item)
				GameTooltip:Show()
			end)
			row:HookScript("OnLeave", GameTooltip_Hide)
		end,
	})
	tbl:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -8)
	tbl:SetPoint("BOTTOMRIGHT")
	frame.tbl = tbl
	frame.rowHeight = M.db.rowHeight
end

local function UpdateTab(frame)
	if not frame.tbl or frame.rowHeight ~= M.db.rowHeight then BuildTable(frame) end
	frame.chips:SetSelected(M.filter or "all")
	local rows = M:FilteredLog()
	frame.tbl:SetData(rows)
	frame.status:SetText(L["%d of %d"]:format(#rows, #M:Log()))
end

function M:BuildWindow()
	if self.window then return self.window end
	local win = Kit.CreateTabbedWindow({
		name = "EldoUI_DeathLogWindow",
		options = { page = "module:Hardcore" },
		title = L["Death Log"],
		width = SIZE[1], height = SIZE[2],
		transparent = function() return M.db.transparent end,
		search = { onSearch = function(text) M.query = text M:RefreshWindow() end,
			tip = L["Find a name, zone or cause. Press Enter; an empty search shows all."] },
		tabs = {
			{ key = "log", title = L["Deaths"], desc = L["Deaths announced on your realm and told by your guild."],
				create = CreateTab, show = UpdateTab, refresh = UpdateTab },
		},
		help = { text = L["The game announces Hardcore deaths as its own death alert setting allows (guild or all). Guild members who use EldoUI and click Tell the guild add their class and cause. Nothing here is sent anywhere."] },
		footer = function() return M.IsHardcore() and "" or L["Only on a Hardcore character."] end,
	})
	self.window = win
	-- The window sits on its mover; dragging the top bar moves the mover.
	function win.ApplyPosition(own)
		local frame = own.frame
		if not frame then return end
		if not own.mover then own.mover = E:CreateMover(frame, MOVER, L["Death Log"], POINT, { sample = false }) end
		frame:SetScale(own:Scale())
		frame:ClearAllPoints()
		frame:SetPoint("TOP", own.mover, "TOP")
	end
	function win.SavePosition(own)
		local frame, mover = own.frame, own.mover
		if not (frame and mover) then return end
		local left, top = frame:GetLeft(), frame:GetTop()
		if not (left and top) then return end
		local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
		E:SaveMoverFromRect(mover, left * scale, top * scale - mover:GetHeight())
	end
	function win.ResetPosition(own)
		E.db.movers[MOVER] = nil
		E:ApplyMover(MOVER)
		own:ResetSize()
		own:ApplyPosition()
	end
	win:Build()
	if win.mover then win.mover:SetSize(SIZE[1], SIZE[2]) end
	return win
end

function M:ApplyLook()
	local win = self.window
	if not (win and win.frame) then return end
	win:Restyle()
	if win:IsOpen() then win:Refresh() end
end

function M:RefreshWindow()
	local win = self.window
	if win and win:IsOpen() then win:Refresh() end
end

function M:IsOpen()
	return self.window ~= nil and self.window:IsOpen()
end

function M:Open()
	if not self.active or InCombatLockdown() then return false end
	return self:BuildWindow():Open("log")
end

function M:Close()
	if self.window then self.window:Close() end
end

function M:Toggle()
	if self:IsOpen() then self:Close() else self:Open() end
end
