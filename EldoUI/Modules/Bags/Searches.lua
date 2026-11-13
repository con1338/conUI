-- EldoUI Bags, part four: saved searches and the search help.
--
--   Searches   a rail button in the bag and bank windows, between View and
--              All characters. Its menu runs a saved search in that window
--              with one click, saves the search in the box under a name,
--              removes one, and opens the search help. Saved per profile
--              (at most 30, names up to 40 characters).
--   Search help
--              a small window beside the bag window with every word and
--              form the search understands, drawn from the search's own
--              word table (SEARCH_WORDS), so the two always agree. A click
--              on a line puts its example in the search box.
--
-- Only the search box changes: nothing is used or moved. Written from
-- scratch for EldoUI.
local _, E = ...
local L = E.L

local M = E:GetModule("Bags")
if not M then return end

local MAX_SAVED = 30
local MAX_NAME = 40

-- Search text shown as typed: a "|" (the search's "or") is not a text code.
local function Plain(text)
	return (tostring(text or ""):gsub("|", "||"))
end

function M:SavedSearches()
	local db = self.db
	if not db then return {} end
	if type(db.savedSearches) ~= "table" then db.savedSearches = {} end
	return db.savedSearches
end

-- Puts `text` in the window's search box; the box runs it.
function M:RunSearch(window, text)
	if not (window and window.search) then return end
	window.search:SetText(text or "")
	window.search:SetCursorPosition(#(text or ""))
end

-- Saves `text` as `name`. The same name again keeps its place and takes
-- the new text. Returns false when the list is full or the text is empty.
function M:SaveSearch(name, text)
	text = strtrim(text or "")
	if text == "" then return false end
	name = strtrim(name or "")
	if name == "" then name = text end
	name = name:sub(1, MAX_NAME)
	local list = self:SavedSearches()
	for _, saved in ipairs(list) do
		if saved.name == name then
			saved.text = text
			return true
		end
	end
	if #list >= MAX_SAVED then return false end
	list[#list + 1] = { name = name, text = text }
	return true
end

function M:RemoveSearch(index)
	local list = self:SavedSearches()
	if list[index] then table.remove(list, index) end
end

function M:AskSaveSearch(window)
	local text = strtrim(window and window.search and window.search:GetText() or "")
	if text == "" then return end
	E:ShowConfirm({
		title = L["Save this search"],
		text = L["A name for the search. The same name again replaces it."],
		edit = { text = text:sub(1, MAX_NAME), maxLetters = MAX_NAME },
		accept = L["Save"],
		onAccept = function(_, name) M:SaveSearch(name, text) end,
	})
end

function M:ShowSearchMenu(window, anchor)
	E.UIKit.ContextMenu(anchor, function(_, root)
		root:CreateTitle(L["Searches"])
		local list = M:SavedSearches()
		for _, saved in ipairs(list) do
			local entry = root:CreateButton(Plain(saved.name), function() M:RunSearch(window, saved.text) end)
			entry:SetTooltip(function(tooltip)
				E.UIKit.TipTitle(tooltip, Plain(saved.name))
				E.UIKit.TipText(tooltip, Plain(saved.text))
			end)
		end
		if #list == 0 then
			root:CreateButton(L["No saved searches yet"]):SetEnabled(false)
		end
		root:CreateDivider()
		local text = strtrim(window.search and window.search:GetText() or "")
		local save = root:CreateButton(L["Save this search"], function() M:AskSaveSearch(window) end)
		save:SetEnabled(text ~= "" and #list < MAX_SAVED)
		save:SetTooltip(function(tooltip)
			E.UIKit.TipTitle(tooltip, L["Save this search"])
			if text == "" then
				E.UIKit.TipText(tooltip, L["Type a search first."])
			elseif #list >= MAX_SAVED then
				E.UIKit.TipText(tooltip, L["The list is full. Remove one first."])
			else
				E.UIKit.TipText(tooltip, Plain(text))
			end
		end)
		if #list > 0 then
			local remove = root:CreateButton(L["Remove"])
			for index, saved in ipairs(list) do
				remove:CreateButton(Plain(saved.name), function() M:RemoveSearch(index) end)
			end
		end
		root:CreateDivider()
		root:CreateButton(L["Search help"], function() M:ShowSearchHelp(window) end)
	end, { at = "owner", align = "right" })
end

-- The rail button, before All characters in both windows.
local RailButtons = M.RailButtons
function M.RailButtons(window, isBank)
	local list = RailButtons(window, isBank)
	local button = { key = "searches", art = E:ClientIcon("Interface\\Icons\\INV_Misc_Spyglass_03"), mono = true,
		tipTitle = L["Searches"], tip = L["Saved searches and the search help."],
		onClick = function(own) M:ShowSearchMenu(window, own) end, options = { page = "module:Bags" } }
	local at = #list + 1
	for index, def in ipairs(list) do
		if def.key == "all" then at = index end
	end
	table.insert(list, at, button)
	return list
end

---------------------------------------------------------------------------
-- Search help
---------------------------------------------------------------------------
local help
local SYNTAX_WIDTH = 120
local ROW_PAD = 5

-- Beside the window, on the side towards the middle of the screen, its
-- top or bottom edge level with the window's like the screen half it is in.
local function PlaceHelp(window)
	help:ClearAllPoints()
	local x, y
	if window then x, y = window:GetCenter() end
	local width, height = UIParent:GetWidth(), UIParent:GetHeight()
	if not (x and y and width and height) then
		help:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		return
	end
	local edge = y < height / 2 and "BOTTOM" or "TOP"
	if x < width / 2 then
		help:SetPoint(edge .. "LEFT", window, edge .. "RIGHT", 6, 0)
	else
		help:SetPoint(edge .. "RIGHT", window, edge .. "LEFT", -6, 0)
	end
end

-- Rows top to bottom; each row's height follows its wrapped help text.
local function LayoutHelp()
	local Kit = E.UIKit
	help.area:Update()
	local width = math.max(help.area.scroll:GetWidth() or 0, 120)
	local textWidth = math.max(width - SYNTAX_WIDTH - 12, 60)
	local y = 0
	for _, row in ipairs(help.rows) do
		local helpHeight = Kit.TextHeight(row.help:GetText(), textWidth, E.tokens.size.body)
		local exampleHeight = Kit.TextHeight(row.example:GetText(), textWidth, E.tokens.size.small)
		local height = math.max(ROW_PAD * 2 + helpHeight + 2 + exampleHeight, E.tokens.height.row)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", help.area.child, "TOPLEFT", 0, -y)
		row:SetPoint("TOPRIGHT", help.area.child, "TOPRIGHT", 0, -y)
		row:SetHeight(height)
		row.help:SetWidth(textWidth)
		row.example:SetWidth(textWidth)
		y = y + height
	end
	help.area.child:SetHeight(math.max(y, 1))
	help.area:Update()
end

local function CreateHelp()
	local Kit = E.UIKit
	help = Kit.CreateToolWindow("EldoUI_BagSearchHelp", { title = L["Search help"], width = 380, height = 500,
		footer = Kit.TOOL_FOOTER, resizable = { minWidth = 320, minHeight = 260 } })
	help.footerText:SetText(L["Click a line to try it in the search box."])
	help.area = Kit.ScrollArea(help.content)
	help.area:SetPoint("TOPLEFT", 0, 0)
	help.area:SetPoint("BOTTOMRIGHT", 0, 0)
	help.rows = {}
	for index, entry in ipairs(M.SEARCH_WORDS) do
		local row = CreateFrame("Button", nil, help.area.child)
		local hover = E:SkinHoverPress(row)
		if hover then hover:SetColorTexture(1, 1, 1, E.tokens.hover.row) end
		row.entry = entry
		row.syntax = Kit.Text(row, E.tokens.size.body, "LEFT")
		row.syntax:SetPoint("TOPLEFT", 6, -ROW_PAD)
		row.syntax:SetWidth(SYNTAX_WIDTH - 6)
		row.syntax:SetWordWrap(true)
		row.syntax:SetJustifyV("TOP")
		row.syntax:SetText(Plain(entry.syntax))
		row.syntax:SetTextColor(Kit.Accent())
		row.help = Kit.Text(row, E.tokens.size.body, "LEFT")
		row.help:SetPoint("TOPLEFT", SYNTAX_WIDTH + 6, -ROW_PAD)
		row.help:SetWordWrap(true)
		row.help:SetJustifyV("TOP")
		row.help:SetText(entry.help)
		row.example = Kit.Text(row, E.tokens.size.small, "LEFT", "secondary")
		row.example:SetPoint("TOPLEFT", row.help, "BOTTOMLEFT", 0, -2)
		row.example:SetWordWrap(true)
		row.example:SetJustifyV("TOP")
		row.example:SetText(L["Try: %s"]:format(Plain(entry.example)))
		row:SetScript("OnClick", function(own)
			M:RunSearch(help.owner, own.entry.example)
		end)
		Kit.Tooltip(row, Plain(entry.syntax), L["Click to search for \"%s\"."]:format(Plain(entry.example)))
		help.rows[index] = row
	end
	help.area:HookScript("OnSizeChanged", LayoutHelp)
	-- The syntax is in the accent: repaint it on a theme change.
	E:RegisterThemed(help, function(own)
		for _, row in ipairs(own.rows) do row.syntax:SetTextColor(Kit.Accent()) end
		if own:IsShown() then LayoutHelp() end
	end)
end

-- Opens the help beside `window` (the bag or bank window), or closes it
-- when it is already open for that window.
function M:ShowSearchHelp(window)
	if not help then CreateHelp() end
	if help:IsShown() and help.owner == window then
		help:Close()
		return
	end
	help.owner = window
	-- The help closes with the window it belongs to.
	if window and not window.eldoHelpHooked then
		window.eldoHelpHooked = true
		window:HookScript("OnHide", function(own)
			if help and help.owner == own and help:IsShown() then help:Close() end
		end)
	end
	PlaceHelp(window)
	help:Open()
	LayoutHelp()
	help.area:ScrollToTop()
end

function M:SearchHelpWindow()
	return help
end
