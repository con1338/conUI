-- EldoUI Loot Guide: the Catalog page host and the section
-- host widget it is built from (LG.Kit.SectionHost).
--
--   +-------------+------------------------------------------------+
--   | Crafting    |                                                |
--   | Reputation  |        the selected section                    |
--   | PvP         |                                                |
--   | ...         |                                                |
--   +-------------+------------------------------------------------+
--
-- The sections (Crafting, Reputation, PvP, Sets & collections and World
-- events) each register:
--
--   LG:RegisterCatalogueSection(key, {
--       title  = "Crafting",
--       icon   = <texture>,
--       desc   = "One line for the tooltip.",
--       order  = 10,
--       build  = function(parent) return frame end,  -- once, on first show
--       show   = function(frame, arg) end,            -- optional
--       hide   = function(frame) end,                 -- optional
--       search = function(text) return { { title, itemID?, arg }, ... } end,  -- optional
--       command = "crafting", usage = "...",           -- optional: /eui crafting [word]
--       argument = function(word) return arg end,      -- optional: the word as the show arg
--   })
--
-- LG:OpenSection(key, arg) opens the Catalog on a section.
--
-- The Catalog tab, its "Pages" switch and its "Open on" choice exist only
-- while at least one section is registered: with none built there is no
-- page at all (no placeholder). /lg <section title> opens a section.
--
-- The page is built from LG.Kit.SectionHost, the one rail-and-page widget
-- of the Loot Guide window (the My Adventure hub uses it too):
--
--   local host = Kit.SectionHost(parent, {
--       railWidth = 180,                        -- optional
--       groups = { { key, title }, ... },      -- optional, the rail groups in order
--       selected = function() return savedKey end,
--       onSelect = function(key) savedKey = key end,
--       footer = function(frame, host) end, footerHeight = 74,  -- optional rail footer
--       empty = { title, text, icon },          -- shown while no section is there
--   })
--   host:SetSections(defs)  ordered defs, each { key, title, icon, desc, order,
--                           group, count = fn() -> n or text, hidden = fn() -> bool,
--                           build = fn(parent, host) -> frame (once), show = fn(frame, arg),
--                           hide = fn(frame), link = fn() (a rail row that opens
--                           something else, such as another tab; no page) }
--   host:Open([key[, arg]]) -> frame   host:Current()   host:Selected()
--   host:HideCurrent()   host:Refresh() (rail texts and counts)
--   host.rail (a variable-height E.UIKit list), host.content, host.footer
-- A section's frame is kept on its def (def.frame) once built.
local _, E = ...
local LG = E.LootGuide
local Kit = LG.Kit
local L = E.L

local NAV_WIDTH = 180
local NAV_ROW = 26
local NAV_GAP = 2
local GROUP_ROW = 26        -- a group caption with room above it
local GROUP_FIRST = 18      -- the first caption sits at the top
local RAIL_PAD = 14         -- rail to page

---------------------------------------------------------------------------
-- Kit.SectionHost
---------------------------------------------------------------------------
local function Visible(def)
	if not def.hidden then return true end
	local ok, hidden = pcall(def.hidden)
	return not (ok and hidden)
end

local function CountText(def)
	if not def.count then return nil end
	local ok, value = pcall(def.count)
	if not ok then
		geterrorhandler()(value)
		return nil
	end
	if type(value) == "number" then return value > 0 and tostring(value) or nil end
	if type(value) == "string" and value ~= "" then return value end
end

local function RailHeight(item)
	if item.group then return item.first and GROUP_FIRST or GROUP_ROW end
	return NAV_ROW
end

local function RailKind(item)
	return item.group and "group" or "section"
end

local function CreateRailRow(row, kind)
	if kind == "group" then
		row:EnableMouse(false)
		row.caption = Kit.Text(row, E.tokens.size.small, "LEFT", "secondary")
		row.caption:SetPoint("BOTTOMLEFT", 8, 5)
		row.caption:SetPoint("BOTTOMRIGHT", -4, 5)
		row.caption:SetWordWrap(false)
		return
	end
	E:SkinRow(row)
	row:RegisterForClicks("LeftButtonUp")
	row.mark = row:CreateTexture(nil, "OVERLAY")
	row.mark:SetPoint("TOPLEFT")
	row.mark:SetPoint("BOTTOMLEFT")
	E:Hairline(row.mark, "w", 2)
	E:AccentTexture(row.mark, 1)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(16, 16)
	row.icon:SetPoint("LEFT", 8, 0)
	E:TrimIcon(row.icon)
	row.count = Kit.Text(row, E.tokens.size.small, "RIGHT", "secondary")
	row.count:SetPoint("RIGHT", -8, 0)
	row.arrow = row:CreateTexture(nil, "ARTWORK")
	row.arrow:SetSize(10, 10)
	row.arrow:SetPoint("RIGHT", -8, 0)
	row.arrow:SetTexture(E.media.chevron)
	row.arrow:SetRotation(math.pi / 2)
	local c = E.tokens.text.secondary
	row.arrow:SetVertexColor(c[1], c[2], c[3])
	row.label = Kit.Text(row, E.tokens.size.label, "LEFT")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", row.count, "LEFT", -4, 0)
	row.label:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		local host, item = self.list and self.list.host, self.item
		if host and item and item.def then host:Pick(item.def.key) end
	end)
end

local function UpdateRailRow(row, item, _, kind)
	local host = row.list.host
	if kind == "group" then
		row.caption:SetText(E:CaptionText(item.group.title or item.group.key or ""))
		return
	end
	local def = item.def
	local selected = def.key == host.current
	row.icon:SetTexture(E:ClientIcon(def.icon or LG.ICON))
	row.label:SetText(E:Translate(def.title) or def.key)
	if selected then row.label:SetTextColor(E:TokenColor("accent")) else Kit.Paint(row.label) end
	row.mark:SetShown(selected)
	E:SetRowSelected(row, selected)
	local count = (not def.link) and CountText(def) or nil
	row.count:SetText(count or "")
	row.count:SetShown(count ~= nil)
	row.arrow:SetShown(def.link ~= nil)
	Kit.Tooltip(row, def.title or def.key, def.desc)
end

local Host = {}

function Host:Section(key)
	return key and self.byKey[key]
end

function Host:Sections()
	return self.defs
end

-- The section that opens: the remembered one while it is there, else the
-- first page in the rail (links never open a page).
function Host:Selected()
	local key = self.opts.selected and self.opts.selected()
	local def = self:Section(key)
	if def and not def.link and Visible(def) then return key end
	for _, other in ipairs(self.defs) do
		if not other.link and Visible(other) then return other.key end
	end
end

function Host:Current()
	return self.current
end

-- The rail's rows and counts. While the host cannot be seen, it waits for
-- the next show: a count may read a whole Journal, and nobody sees it.
function Host:BuildRail()
	if not self:IsVisible() then
		self.railDirty = true
		return
	end
	self.railDirty = nil
	local items, groups, byGroup, loose = {}, self.opts.groups, {}, {}
	local known = {}
	for _, group in ipairs(groups or {}) do known[group.key] = true end
	for _, def in ipairs(self.defs) do
		if Visible(def) then
			if def.group and known[def.group] then
				byGroup[def.group] = byGroup[def.group] or {}
				table.insert(byGroup[def.group], def)
			else
				loose[#loose + 1] = def
			end
		end
	end
	for _, def in ipairs(loose) do items[#items + 1] = { def = def } end
	for _, group in ipairs(groups or {}) do
		local list = byGroup[group.key]
		if list and #list > 0 then
			items[#items + 1] = { group = group, first = #items == 0 }
			for _, def in ipairs(list) do items[#items + 1] = { def = def } end
		end
	end
	self.items = items
	self.rail:SetData(items, true)
end

function Host:SetSections(defs)
	self.defs = {}
	self.byKey = {}
	for _, def in ipairs(defs or {}) do
		if type(def) == "table" and def.key then
			self.defs[#self.defs + 1] = def
			self.byKey[def.key] = def
		end
	end
	if self.current and not self.byKey[self.current] then self.current = nil end
	self:BuildRail()
end

function Host:HideCurrent()
	local def = self:Section(self.current)
	if def and def.frame and def.frame:IsShown() then
		if def.hide then
			local ok, err = pcall(def.hide, def.frame)
			if not ok then geterrorhandler()(err) end
		end
		def.frame:Hide()
	end
end

-- A rail click: a link runs, a section opens.
function Host:Pick(key)
	local def = self:Section(key)
	if not def then return end
	if def.link then
		local ok, err = pcall(def.link, def)
		if not ok then geterrorhandler()(err) end
		return
	end
	self:Open(key)
end

function Host:Open(key, arg)
	local def = self:Section(key)
	if not (def and not def.link and Visible(def)) then
		def = self:Section(self:Selected())
	end
	for _, other in ipairs(self.defs) do
		if other ~= def and other.frame and other.frame:IsShown() then
			if other.hide then pcall(other.hide, other.frame) end
			other.frame:Hide()
		end
	end
	if not def then
		self.current = nil
		self:ShowEmpty(true)
		self.rail:Refresh()
		return nil
	end
	self:ShowEmpty(false)
	self.current = def.key
	if self.opts.onSelect then
		local ok, err = pcall(self.opts.onSelect, def.key)
		if not ok then geterrorhandler()(err) end
	end
	if not def.frame then
		local ok, frame = pcall(def.build, self.content, self)
		if not ok or type(frame) ~= "table" then
			geterrorhandler()(("EldoUI Loot Guide section %s failed to build: %s"):format(def.key, tostring(frame)))
			self.rail:Refresh()
			return nil
		end
		def.frame = frame
		if frame:GetNumPoints() == 0 then frame:SetAllPoints(self.content) end
	end
	def.frame:Show()
	if def.show then
		local ok, err = pcall(def.show, def.frame, arg)
		if not ok then geterrorhandler()(err) end
	end
	self.rail:Refresh()
	return def.frame
end

function Host:ShowEmpty(show)
	local empty = self.opts.empty
	if not empty then return end
	if show and not self.emptyState then
		self.emptyState = Kit.EmptyState(self.content)
	end
	if self.emptyState then
		if show then self.emptyState:Set(empty[1] or empty.title, empty[2] or empty.text, empty[3] or empty.icon) end
		self.emptyState:SetShown(show)
	end
end

-- Rail texts and counts again (a count changed, a section was hidden).
function Host:Refresh()
	self:BuildRail()
end

function Kit.SectionHost(parent, opts)
	opts = opts or {}
	local host = CreateFrame("Frame", nil, parent)
	host:SetAllPoints()
	for name, fn in pairs(Host) do host[name] = fn end
	host.opts = opts
	host.defs, host.byKey, host.items = {}, {}, {}
	local width = opts.railWidth or NAV_WIDTH

	host.rail = E.UIKit.CreateList(host, {
		height = RailHeight, kind = RailKind, gap = NAV_GAP,
		create = CreateRailRow, update = UpdateRailRow,
	})
	host.rail.host = host
	host.rail:SetPoint("TOPLEFT", 0, 0)
	host.rail:SetWidth(width)
	if opts.footer then
		host.footer = CreateFrame("Frame", nil, host)
		host.footer:SetPoint("BOTTOMLEFT")
		host.footer:SetSize(width, opts.footerHeight or 74)
		host.footer.line = Kit.Divider(host.footer)
		host.footer.line:SetPoint("TOPLEFT")
		host.footer.line:SetPoint("TOPRIGHT")
		host.rail:SetPoint("BOTTOMLEFT", host.footer, "TOPLEFT", 0, 8)
		local ok, err = pcall(opts.footer, host.footer, host)
		if not ok then geterrorhandler()(err) end
	else
		host.rail:SetPoint("BOTTOMLEFT", 0, 0)
	end
	host.line = host:CreateTexture(nil, "ARTWORK")
	E:Hairline(host.line, "w", 1)
	host.line:SetColorTexture(unpack(E.tokens.edge.divider))
	host.line:SetPoint("TOPLEFT", host, "TOPLEFT", width + RAIL_PAD / 2 - 1, 0)
	host.line:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", width + RAIL_PAD / 2 - 1, 0)
	host.content = CreateFrame("Frame", nil, host)
	host.content:SetPoint("TOPLEFT", host, "TOPLEFT", width + RAIL_PAD, 0)
	host.content:SetPoint("BOTTOMRIGHT")
	host:HookScript("OnShow", function(self)
		if self.railDirty then self:BuildRail() end
	end)
	return host
end

---------------------------------------------------------------------------
-- The Catalog page
---------------------------------------------------------------------------
local sections, sectionOrder = {}, {}
local page      -- the page frame once built

local function SortSections()
	table.sort(sectionOrder, function(a, b)
		local sa, sb = sections[a], sections[b]
		if (sa.order or 50) ~= (sb.order or 50) then return (sa.order or 50) < (sb.order or 50) end
		return a < b
	end)
end

local function OrderedDefs()
	local list = {}
	for _, key in ipairs(sectionOrder) do list[#list + 1] = sections[key] end
	return list
end

local function Selected()
	local key = LG:UI().catalogueSection
	if key and sections[key] then return key end
	return sectionOrder[1]
end

local function Create(content)
	local frame = Kit.SectionHost(content, {
		selected = Selected,
		onSelect = function(key) LG:UI().catalogueSection = key end,
	})
	-- Older code and plugins know the rail as `nav`.
	frame.nav = frame.rail
	page = frame
	return frame
end

-- arg: a section key, or { section = key, arg = value } to open a section on
-- one entry (a set, a faction, a recipe).
local function Show(frame, arg)
	frame:SetSections(OrderedDefs())
	if type(arg) == "table" then
		frame:Open(arg.section, arg.arg)
	else
		frame:Open(arg)
	end
end

local function Hide(frame)
	frame = frame or page
	if frame then frame:HideCurrent() end
end

-- "/lg crafting" -> the section whose key or title starts with the text.
local function Alias(text)
	if type(text) ~= "string" then return end
	text = LG:Fold(text)
	if text == "" then return end
	for _, key in ipairs(sectionOrder) do
		local title = LG:Fold(sections[key].title or key)
		if key == text or title == text then return key end
	end
	for _, key in ipairs(sectionOrder) do
		local title = LG:Fold(sections[key].title or key)
		if #text >= 3 and (key:sub(1, #text) == text or title:sub(1, #text) == text) then return key end
	end
end

local PAGE = {
	title = "Catalog",
	desc = "Crafting, reputation and PvP rewards, sets and world events: one list on the left, the section on the right.",
	order = 55,
	create = Create,
	show = Show,
	hide = Hide,
	alias = Alias,
	refresh = function(frame)
		frame:SetSections(OrderedDefs())
	end,
}

local function Sync()
	if #sectionOrder > 0 then
		if LG:GetPage("catalogue") ~= PAGE then LG:RegisterPage("catalogue", PAGE) end
	elseif LG:GetPage("catalogue") then
		LG:UnregisterPage("catalogue")
	end
	if page and page:IsShown() then Show(page) end
end

-- Open the Catalog on a section (arg: what its show takes).
function LG:OpenSection(key, arg)
	self:Open("catalogue", { section = key, arg = arg })
end

-- /eui <section command> [word]: the same checks as a page's command.
function LG:SectionCommand(key, word)
	local def = sections[key]
	if not def then return end
	local arg
	if word and word ~= "" and def.argument then
		local ok, value = pcall(def.argument, word)
		if ok then arg = value end
	end
	self:Command("catalogue", { section = key, arg = arg })
end

function LG:RegisterCatalogueSection(key, def)
	assert(type(key) == "string" and type(def) == "table" and type(def.build) == "function",
		"LootGuide:RegisterCatalogueSection(key, { title, build = function(parent) ... end })")
	def.key = key
	if def.command and E.AddCommand and not (sections[key] and sections[key].command == def.command) then
		E:AddCommand(def.command, def.usage or def.title, function(word) LG:SectionCommand(key, word) end, "Tools")
	end
	if not sections[key] then table.insert(sectionOrder, key) end
	sections[key] = def
	SortSections()
	Sync()
end

-- Plugins that go away (and tests) take their section out again; the last
-- one out takes the Catalog tab with it.
function LG:UnregisterCatalogueSection(key)
	local def = sections[key]
	if not def then return end
	if def.frame then
		if def.hide then pcall(def.hide, def.frame) end
		def.frame:Hide()
	end
	sections[key] = nil
	for index, other in ipairs(sectionOrder) do
		if other == key then table.remove(sectionOrder, index) break end
	end
	Sync()
end

-- One registered section (nil when none has that key).
function LG:CatalogueSection(key)
	return sections[key]
end

function LG:CatalogueSections()
	local list = {}
	for _, key in ipairs(sectionOrder) do list[#list + 1] = sections[key] end
	return list
end

-- Results from every section that can search: { { section, title, itemID, arg }, ... }
function LG:SearchCatalogue(text)
	local results = {}
	if type(text) ~= "string" or text == "" then return results end
	for _, key in ipairs(sectionOrder) do
		local def = sections[key]
		if def.search then
			local ok, found = pcall(def.search, text)
			if ok and type(found) == "table" then
				for _, entry in ipairs(found) do
					entry.section = key
					results[#results + 1] = entry
				end
			elseif not ok then
				geterrorhandler()(found)
			end
		end
	end
	return results
end
