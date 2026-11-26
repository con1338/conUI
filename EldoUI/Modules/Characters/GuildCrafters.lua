-- EldoUI Characters: the guild crafter directory.
--
-- Who in your guild can craft something, from recipe lists guild members
-- share on purpose:
--   * "Share your recipes with the guild" (off by default) adds two buttons
--     to the Crafters tab: "Send my recipes" sends the known recipes of
--     your characters on this realm (the packed recipe IDs your own
--     profession windows saved), and "Ask the guild" asks members who use
--     EldoUI for theirs. Nothing goes out without one of those clicks; an
--     incoming request is only shown, never answered by itself. Messages
--     go through E:SendComm (addon message limits, held back during chat
--     lockdown), and only from guild members are read (trusted = "guild").
--   * The Crafters tab: search a recipe (or what it makes) and see the
--     guild members who know it, online first, with skill and alt name.
--     Right-click forgets one member's list; Whisper opens a whisper to
--     the crafter with the recipe link in the edit box. You press Enter.
--   * The "Guild crafters" tooltip section on crafted items and recipes
--     ("Guild crafters: Mira (online), Joe"), and a line in the Loot
--     Guide's Crafting detail.
-- What an item is made by comes from the client (the recipe schematic, the
-- Loot Guide's craft data with EldoUI_LootData, or a recipe item's name);
-- an item it cannot tie to a recipe shows no line. Never a guess.
-- The Retail guild-recipe API (QueryGuildRecipes, GetGuildMemberRecipes,
-- C_GuildInfo.QueryGuildMembersForRecipe) is only probed (/eui diag): it
-- asks the server for each recipe, and Forever's guild window has no
-- professions list, so it is not used as a source.
local _, E = ...
local L = E.L
local Kit = E.UIKit
local M = E.modules.Characters
if not M then return end

local function Store() return E.Characters end
local function Grey(text) return M.Grey(text) end

local COMM = "EUI_GC"
local MAX_PEERS = 200
local MAX_CHARS = 20
local MAX_PROFS = 12

M.defaults.crafterShare = false       -- sends for you: off by default
M.defaults.crafterLine = "names"      -- names / count / online / compact / off
M.defaults.crafterOffline = true      -- offline crafters in the tooltip line and the list
M.defaults.crafterDays = 60           -- lists older than this are dropped

local function IsSecret(value) return issecretvalue and issecretvalue(value) or false end
local Readable = E.Plain

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return Readable(a), Readable(b), Readable(c) end
end

---------------------------------------------------------------------------
-- Saved lists (account-wide, next to the alt lists)
---------------------------------------------------------------------------
local version = 0 -- bumps when a list arrives or leaves

local function Prune(peers)
	local now = Store().Now()
	local days = math.max(1, tonumber(M.db and M.db.crafterDays) or 60)
	local list = {}
	for owner, peer in pairs(peers) do
		if type(peer) ~= "table" or type(peer.at) ~= "number" or type(peer.chars) ~= "table" or now - peer.at > days * 86400 then
			peers[owner] = nil
		else
			list[#list + 1] = { owner = owner, at = peer.at }
		end
	end
	if #list > MAX_PEERS then
		table.sort(list, function(a, b) return a.at > b.at end)
		for index = MAX_PEERS + 1, #list do peers[list[index].owner] = nil end
	end
end

local function Peers()
	local data = E:GetGlobal("characters")
	if type(data) ~= "table" then return {} end
	data.guildCrafters = type(data.guildCrafters) == "table" and data.guildCrafters or {}
	if not M.craftersPruned then
		M.craftersPruned = true
		Prune(data.guildCrafters)
	end
	return data.guildCrafters
end
M.GuildCrafterPeers = Peers

function M:ForgetCrafter(owner)
	Peers()[owner] = nil
	if self.craftAsked then self.craftAsked[owner] = nil end
	version = version + 1
	self:Refresh({ section = "guildCrafters" })
end

---------------------------------------------------------------------------
-- The wire format: one line per character and profession
--   C <tab> name <tab> CLASS
--   P <tab> profession <tab> rank <tab> packed recipe IDs
-- On Forever a whisper needs the first name and the surname, so the name
-- is the full one (Store().FullName: the store's record keeps the first
-- name only, its key both). Lists from an older EldoUI name the first name
-- alone; the online mark and the whisper look those up in the roster.
---------------------------------------------------------------------------
local function Field(text)
	return (tostring(text or ""):gsub("[\t\n|]", ""))
end

function M:MyRecipeList()
	local chars = {}
	for _, key in ipairs(Store():Keys("realm")) do
		local record = Store():Get(key)
		local profs = {}
		local any = false
		for name, entry in pairs(type(record.profs) == "table" and record.profs or {}) do
			if type(entry) == "table" and type(entry.recipes) == "string" and entry.recipes ~= "" then
				profs[name] = { rank = tonumber(entry.rank) or 0, recipes = entry.recipes }
				any = true
			end
		end
		if any and #chars < MAX_CHARS then
			chars[#chars + 1] = { name = Store().FullName(key, record) or record.name, class = record.class, profs = profs }
		end
	end
	return chars
end

local function Encode(chars)
	local lines = {}
	for _, char in ipairs(chars) do
		lines[#lines + 1] = ("C\t%s\t%s"):format(Field(char.name), Field(char.class))
		local names = {}
		for name in pairs(char.profs) do names[#names + 1] = name end
		table.sort(names)
		for _, name in ipairs(names) do
			local prof = char.profs[name]
			lines[#lines + 1] = ("P\t%s\t%d\t%s"):format(Field(name), tonumber(prof.rank) or 0, Field(prof.recipes))
		end
	end
	return table.concat(lines, "\n")
end

local function Decode(text)
	local chars = {}
	if type(text) ~= "string" then return chars end
	local current, profCount
	for line in text:gmatch("[^\n]+") do
		local kind = line:sub(1, 1)
		if kind == "C" then
			local name, class = line:match("^C\t([^\t]+)\t([%u]*)$")
			if name and #chars < MAX_CHARS then
				current = { name = name:sub(1, 48), class = class ~= "" and class or nil, profs = {} }
				chars[#chars + 1] = current
				profCount = 0
			else
				current = nil
			end
		elseif kind == "P" and current then
			local prof, rank, recipes = line:match("^P\t([^\t]+)\t(%d+)\t([%w,]*)$")
			if prof and profCount < MAX_PROFS and #recipes <= 20000 then
				current.profs[prof:sub(1, 40)] = { rank = tonumber(rank) or 0, recipes = recipes }
				profCount = profCount + 1
			end
		end
	end
	for index = #chars, 1, -1 do
		if next(chars[index].profs) == nil then table.remove(chars, index) end
	end
	return chars
end
M.EncodeCrafters, M.DecodeCrafters = Encode, Decode

---------------------------------------------------------------------------
-- Sending and receiving (opt-in, click only)
---------------------------------------------------------------------------
local function CanSend()
	if not M.db.crafterShare then
		M:Say(L["Turn on \"Share your recipes with the guild\" in /eui > Alts first."], true)
		return false
	end
	if not IsInGuild() then
		M:Say(L["You are not in a guild."], true)
		return false
	end
	if E.CommRestricted and E:CommRestricted() then
		M:Say(L["The game holds addon messages back right now. Try again later."], true)
		return false
	end
	return true
end

function M:SendRecipes()
	if not CanSend() then return false end
	local chars = self:MyRecipeList()
	if #chars == 0 then
		M:Say(L["No recipes saved yet: open each profession window once on your characters."], true)
		return false
	end
	local ok, why = E:SendComm(COMM, "R" .. Encode(chars), "GUILD")
	if ok then
		M:Say(L["Your recipe list went to your guild."])
	elseif why == "payload" then
		M:Say(L["Your recipe list is too long for one addon message."], true)
	else
		M:Say(L["The game holds addon messages back right now. Try again later."], true)
	end
	return ok and true or false
end

function M:AskCrafters()
	if not CanSend() then return false end
	local ok = E:SendComm(COMM, "Q", "GUILD")
	if ok then M:Say(L["Asked your guild for their recipe lists. Answers show in the Crafters tab."]) end
	return ok and true or false
end

local function OwnerName(sender)
	local name = Ambiguate and Readable(Ambiguate(sender, "none"))
	return type(name) == "string" and name ~= "" and name or sender
end

local function OnMessage(payload, sender)
	if not (M.active and M.db.crafterShare) or IsSecret(payload) or IsSecret(sender) then return end
	if type(payload) ~= "string" or type(sender) ~= "string" then return end
	local kind, body = payload:sub(1, 1), payload:sub(2)
	if kind == "R" then
		local chars = Decode(body)
		if #chars == 0 then return end
		local peers = Peers()
		peers[OwnerName(sender)] = { at = Store().Now(), chars = chars }
		Prune(peers)
		version = version + 1
		M:Refresh({ section = "guildCrafters" })
	elseif kind == "Q" then
		-- Shown in the tab; never answered by itself.
		M.craftAsked = M.craftAsked or {}
		M.craftAsked[OwnerName(sender)] = Store().Now()
		M:Refresh({ section = "guildCrafters" })
	end
end
M.OnCrafterMessage = OnMessage

local function Listen()
	if M.craftersListening or not E.RegisterComm then return end
	-- Registering the prefix sends nothing; messages are ignored while
	-- sharing is off.
	M.craftersListening = E:RegisterComm(COMM, OnMessage, { trusted = "guild" }) and true or false
end

---------------------------------------------------------------------------
-- Online members (from the guild roster the game already has)
---------------------------------------------------------------------------
local online = {}
-- First name -> the online member's full name, or false when two online
-- members share it (first names are not unique on Forever).
local onlineFirst = {}
local onlineDirty = true

-- A name's first name and surname (nil without one), split at the game's
-- surname separator or a space.
local function SplitName(name)
	local separator = Store().SurnameSeparator()
	local at = name:find(separator, 1, true)
	if not at and separator ~= " " then
		separator = " "
		at = name:find(separator, 1, true)
	end
	if not at then return name, nil end
	local surname = name:sub(at + #separator)
	return name:sub(1, at - 1), surname ~= "" and surname or nil
end

-- The roster changes often in a big guild: the online set is only marked
-- out of date, and read again when something asks who is online.
function M:MarkGuildOnline()
	onlineDirty = true
end

function M:ScanGuildOnline()
	wipe(online)
	wipe(onlineFirst)
	onlineDirty = false
	if not (Try(IsInGuild) and GetNumGuildMembers and GetGuildRosterInfo) then return end
	local count = Try(GetNumGuildMembers) or 0
	for index = 1, math.min(count, 1000) do
		local ok, name, _, _, _, _, _, _, _, isOnline = pcall(GetGuildRosterInfo, index)
		name, isOnline = Readable(name), Readable(isOnline)
		if ok and type(name) == "string" and isOnline then
			local full = OwnerName(name)
			online[full:lower()] = true
			local first, surname = SplitName(full)
			if surname then
				local key = first:lower()
				onlineFirst[key] = onlineFirst[key] == nil and full or false
			end
		end
	end
end

function M:CrafterOnline(name)
	if type(name) ~= "string" then return false end
	-- Without a shared list nobody asks; with one, the roster is read once.
	if onlineDirty and next(Peers()) ~= nil then self:ScanGuildOnline() end
	if online[name:lower()] == true then return true end
	local first, surname = SplitName(name)
	-- A first name alone (a list from an older EldoUI): someone online by it.
	if not surname then return onlineFirst[name:lower()] ~= nil end
	-- A full name, and a roster that names members without their surname.
	return online[first:lower()] == true
end

-- The name a whisper to a crafter goes to: a first name alone becomes the
-- full name of the one online member who has it; otherwise as it is.
function M:CrafterWhisperName(name)
	if type(name) ~= "string" or select(2, SplitName(name)) then return name end
	if onlineDirty then self:ScanGuildOnline() end
	local full = onlineFirst[name:lower()]
	return type(full) == "string" and full or name
end

---------------------------------------------------------------------------
-- Indexes: recipe -> crafters, recipe name, what a recipe makes
---------------------------------------------------------------------------
local byRecipe, builtAt = {}, -1

local function Index()
	if builtAt == version then return byRecipe end
	builtAt = version
	wipe(byRecipe)
	for owner, peer in pairs(Peers()) do
		for _, char in ipairs(peer.chars) do
			for prof, entry in pairs(char.profs) do
				for id in pairs(Store().UnpackIDs(entry.recipes)) do
					local list = byRecipe[id]
					if not list then
						list = {}
						byRecipe[id] = list
					end
					list[#list + 1] = { owner = owner, name = char.name, class = char.class, prof = prof, rank = entry.rank, at = peer.at }
				end
			end
		end
	end
	return byRecipe
end
M.CrafterIndex = Index

local recipeNames = {}
local function RecipeName(id)
	local name = recipeNames[id]
	if name == nil then
		name = C_Spell and C_Spell.GetSpellName and Try(C_Spell.GetSpellName, id)
		name = type(name) == "string" and name or false
		recipeNames[id] = name
	end
	return name or nil
end
M.CrafterRecipeName = RecipeName

-- What a recipe makes: the client's schematic, cached (false = unknown).
local outputs = {}
local function OutputOf(id)
	local out = outputs[id]
	if out == nil then
		out = false
		local util = C_TradeSkillUI
		if util and util.GetRecipeSchematic then
			local ok, schematic = pcall(util.GetRecipeSchematic, id, false)
			if ok and type(schematic) == "table" then out = tonumber(Readable(schematic.outputItemID)) or false end
		end
		outputs[id] = out
	end
	return out or nil
end

-- Recipe IDs that make (or a recipe item that teaches) an item.
function M:RecipesForItem(item)
	if IsSecret(item) or item == nil then return {} end
	local itemID, _, _, _, _, classID = C_Item.GetItemInfoInstant(item)
	itemID = Readable(itemID)
	if not itemID then return {} end
	local found, seen = {}, {}
	local function Add(id)
		if id and not seen[id] then
			seen[id] = true
			found[#found + 1] = id
		end
	end
	local index = Index()
	-- A recipe item: what it teaches, by name ("Pattern: Linen Bag").
	if classID == (Enum.ItemClass and Enum.ItemClass.Recipe or 9) then
		local name = Readable(C_Item.GetItemInfo(item))
		local taught = type(name) == "string" and (name:match("^[^:]+:%s*(.+)$") or name):lower()
		if taught then
			for id in pairs(index) do
				local recipe = RecipeName(id)
				if recipe and recipe:lower() == taught then Add(id) end
			end
		end
		return found
	end
	-- A crafted item: the Loot Guide's craft data, then the schematics.
	local LG = E.LootGuide
	if LG and LG.CraftOf then
		local ok, craft = pcall(LG.CraftOf, LG, itemID)
		if ok and type(craft) == "table" and index[craft.id] then Add(craft.id) end
	end
	for id in pairs(index) do
		if OutputOf(id) == itemID then Add(id) end
	end
	return found
end

-- Crafters of a set of recipes: one row per character, online first.
function M:CraftersOf(recipeIDs)
	local index, rows, seen = Index(), {}, {}
	for _, id in ipairs(recipeIDs) do
		for _, crafter in ipairs(index[id] or {}) do
			local key = crafter.name:lower()
			if not seen[key] then
				seen[key] = true
				local isOnline = self:CrafterOnline(crafter.name)
				if isOnline or self.db.crafterOffline then
					rows[#rows + 1] = { name = crafter.name, owner = crafter.owner, class = crafter.class, prof = crafter.prof, rank = crafter.rank, online = isOnline, recipe = id }
				end
			end
		end
	end
	table.sort(rows, function(a, b)
		if a.online ~= b.online then return a.online end
		return a.name < b.name
	end)
	return rows
end

---------------------------------------------------------------------------
-- The tooltip line and the Loot Guide line
---------------------------------------------------------------------------
local function CrafterName(row)
	local r, g, b = M.ClassColor(row.class)
	return Kit.Hex(r, g, b) .. row.name .. "|r"
end

-- The text after "Guild crafters:" in the chosen form, or nil.
function M:CrafterLineText(rows, form)
	form = form or self.db.crafterLine
	if form == "off" or #rows == 0 then return nil end
	local onlineCount = 0
	for _, row in ipairs(rows) do if row.online then onlineCount = onlineCount + 1 end end
	if form == "count" then
		local text = E:Plural(#rows, "%d crafter", "%d crafters"):format(#rows)
		if onlineCount > 0 then text = text .. " " .. M.Good(L["(%d online)"]:format(onlineCount)) end
		return text
	end
	local parts = {}
	for _, row in ipairs(rows) do
		if form ~= "online" or row.online then
			local text = CrafterName(row)
			if form == "names" and row.online then text = text .. " " .. M.Good(L["(online)"]) end
			parts[#parts + 1] = text
		end
	end
	if #parts == 0 then return nil end
	if form == "compact" and #parts > 2 then
		return table.concat(parts, ", ", 1, 2) .. Grey((" +%d"):format(#parts - 2))
	end
	if #parts > 6 then return table.concat(parts, ", ", 1, 6) .. Grey((" +%d"):format(#parts - 6)) end
	return table.concat(parts, ", ")
end

function M:CrafterLineForItem(item)
	if not (self.active and self.db.crafterShare) then return nil end
	local recipes = self:RecipesForItem(item)
	if #recipes == 0 then return nil end
	return self:CrafterLineText(self:CraftersOf(recipes))
end

-- The Loot Guide's Crafting detail asks with a recipe (spell) ID.
function E:GuildCraftersLine(recipeID)
	if not (M.active and M.db.crafterShare) or type(recipeID) ~= "number" then return nil end
	local text = M:CrafterLineText(M:CraftersOf({ recipeID }))
	return text and (L["Guild crafters: %s"]):format(text) or nil
end

local function HookTooltip()
	if M.crafterTooltipHooked then return end
	M.crafterTooltipHooked = true
	local tooltipModule = E.modules.Tooltip
	if E.RegisterTooltipSection and tooltipModule and tooltipModule:IsEnabled() then
		E:RegisterTooltipSection("guildCrafters", { order = 42, title = "Guild crafters", default = "always",
			desc = "On crafted items and recipes: the guild members who know the recipe, from the lists they shared (Alts module, Crafters tab).",
			item = function(_, link, itemID, add)
				local text = M:CrafterLineForItem(link or itemID)
				if text then add(L["Guild crafters"], text) end
			end })
	elseif TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
			if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
			local id = data and Readable(data.id)
			if not id then return end
			local text = M:CrafterLineForItem(id)
			if text then
				local c = Kit.SECONDARY
				tooltip:AddDoubleLine(L["Guild crafters"], text, c[1], c[2], c[3], 1, 1, 1)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- The Crafters tab
---------------------------------------------------------------------------
local function SearchRows(filter)
	filter = strtrim(tostring(filter or "")):lower()
	local rows = {}
	local index = Index()
	for id, crafters in pairs(index) do
		local name = RecipeName(id) or ("#" .. id)
		local match = filter == "" or name:lower():find(filter, 1, true) ~= nil
		if not match then
			local out = OutputOf(id)
			local itemName = out and Readable(C_Item.GetItemInfo(out))
			match = type(itemName) == "string" and itemName:lower():find(filter, 1, true) ~= nil
		end
		if match then
			for _, crafter in ipairs(crafters) do
				local isOnline = M:CrafterOnline(crafter.name)
				if isOnline or M.db.crafterOffline then
					rows[#rows + 1] = { id = id, recipe = name, name = crafter.name, owner = crafter.owner, class = crafter.class,
						prof = crafter.prof, rank = crafter.rank, online = isOnline, at = crafter.at }
				end
			end
		end
	end
	for owner, at in pairs(M.craftAsked or {}) do
		if filter == "" then rows[#rows + 1] = { asked = at, owner = owner, name = owner, recipe = "", online = M:CrafterOnline(owner) } end
	end
	return rows
end
M.CrafterSearchRows = SearchRows

function M:WhisperCrafter(row)
	if type(row) ~= "table" or row.asked or type(row.name) ~= "string" then return false end
	local function Text(value) return type(value) == "string" and value ~= "" and value or nil end
	local link = row.id and (Text(C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink and Try(C_TradeSkillUI.GetRecipeLink, row.id))
		or Text(C_Spell and C_Spell.GetSpellLink and Try(C_Spell.GetSpellLink, row.id))) or Text(row.recipe) or ""
	-- Only a prefilled edit box: the player presses Enter.
	if ChatFrameUtil and ChatFrameUtil.SendTellWithMessage then
		ChatFrameUtil.SendTellWithMessage(M:CrafterWhisperName(row.name), link)
		return true
	end
	return false
end

local function Age(at)
	if not at then return "" end
	local seconds = Store().Now() - at
	return seconds < 3600 and L["now"] or (seconds < 86400 and L["%dh"]:format(seconds / 3600) or L["%dd"]:format(seconds / 86400))
end

local COLUMNS = {
	{ key = "recipe", title = "Recipe", value = function(row) return row.recipe end,
		text = function(row) return row.asked and Grey(L["asked for your recipe list"]) or row.recipe end },
	{ key = "name", title = "Crafter", width = 170, value = function(row) return row.name end,
		text = function(row)
			local text = CrafterName(row)
			if row.owner and row.owner:lower() ~= row.name:lower() then text = text .. Grey(" (" .. row.owner .. ")") end
			return text
		end },
	{ key = "prof", title = "Profession", width = 120, value = function(row) return row.prof or "" end,
		text = function(row) return row.prof and (row.prof .. Grey((" %d"):format(row.rank or 0))) or "" end },
	{ key = "status", title = "Status", width = 70, value = function(row) return row.online and 0 or 1 end,
		text = function(row) return row.online and M.Good(L["online"]) or Grey(L["offline"]) end },
	{ key = "at", title = "Received", width = 80, align = "RIGHT", value = function(row) return -(row.at or row.asked or 0) end,
		text = function(row) return Age(row.at or row.asked) end },
}

local function Update(frame)
	frame.send:SetShown(M.db.crafterShare)
	frame.ask:SetShown(M.db.crafterShare)
	frame.rows = M.db.crafterShare and SearchRows(frame.search:GetText()) or {}
	frame.list:SetData(frame.rows)
	local who = frame.selected and frame.selected.name
	frame.whisper:SetText(who and L["Whisper %s"]:format(who) or L["Whisper"])
	Kit.FitButton(frame.whisper, 90)
	frame.whisper:SetEnabled(who ~= nil)
	frame.note:SetText(M.db.crafterShare and "" or L["Sharing recipes with the guild is off (/eui > Alts)."])
end
M.UpdateCrafters = Update

M:AddTab({
	key = "crafters", order = 85, title = "Crafters",
	desc = "Guild members who know a recipe, from the recipe lists they shared.",
	create = function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.toolbar = CreateFrame("Frame", nil, frame)
		frame.toolbar:SetPoint("TOPLEFT")
		frame.toolbar:SetPoint("TOPRIGHT")
		frame.toolbar:SetHeight(22)
		local search = CreateFrame("EditBox", nil, frame.toolbar, "SearchBoxTemplate")
		E:SearchHint(search)
		search:SetSize(200, 20)
		search:SetAutoFocus(false)
		search:SetPoint("LEFT", 4, 0)
		E:SkinEditBox(search)
		search:HookScript("OnTextChanged", function() Update(frame) end)
		Kit.Tooltip(search, L["Search recipes"], L["A recipe, or the item it makes. Empty shows every shared recipe."])
		frame.search = search
		frame.whisper = Kit.Button(frame.toolbar, L["Whisper"], 90, 20, function() M:WhisperCrafter(frame.selected) end,
			L["Whisper"], L["Opens a whisper to the crafter you clicked, with the recipe link in the edit box. You press Enter."])
		frame.whisper:SetPoint("LEFT", search, "RIGHT", 8, 0)
		frame.ask = Kit.Button(frame.toolbar, L["Ask the guild"], 100, 20, function() M:AskCrafters() end,
			L["Ask the guild"], L["Asks guild members who use EldoUI and share their recipes to send you their list. Their answer needs their click too."])
		frame.ask:SetPoint("RIGHT", -2, 0)
		frame.send = Kit.Button(frame.toolbar, L["Send my recipes"], 110, 20, function() M:SendRecipes() end,
			L["Send my recipes"], L["Sends the known recipes of your characters on this realm (what each profession window saved) to guild members who use EldoUI and share theirs."])
		frame.send:SetPoint("RIGHT", frame.ask, "LEFT", -4, 0)
		frame.note = Kit.Text(frame.toolbar, 11, "RIGHT", "dim")
		frame.note:SetPoint("LEFT", frame.whisper, "RIGHT", 10, 0)
		frame.note:SetPoint("RIGHT", frame.send, "LEFT", -8, 0)
		frame.list = Kit.CreateTable(frame, COLUMNS, {
			sortKey = "status", rowHeight = 18,
			onClick = function(row, button, widget)
				if button == "RightButton" then
					E.UIKit.ContextMenu(widget, function(_, root)
						if not row.asked then
							root:CreateButton(L["Whisper %s"]:format(row.name), function() M:WhisperCrafter(row) end)
						end
						root:CreateButton(L["Forget %s's list"]:format(row.owner), function() M:ForgetCrafter(row.owner) end)
					end)
				elseif row.id and IsModifiedClick("CHATLINK") and C_Spell and C_Spell.GetSpellLink then
					E:InsertLink(C_Spell.GetSpellLink(row.id))
				else
					frame.selected = not row.asked and row or nil
					Update(frame)
				end
			end,
			createRow = function(widget)
				widget:HookScript("OnEnter", function(own)
					local row = own.item
					if not (row and row.id) then return end
					GameTooltip:SetOwner(own, "ANCHOR_RIGHT")
					GameTooltip:SetSpellByID(row.id)
					GameTooltip:Show()
				end)
				widget:HookScript("OnLeave", function() GameTooltip:Hide() end)
			end,
			empty = { L["No recipe lists yet"], L["Turn on \"Share your recipes with the guild\" in /eui > Alts, then click Ask the guild. Lists guild members send show here."] },
		})
		frame.list:SetPoint("TOPLEFT", frame.toolbar, "BOTTOMLEFT", 0, -6)
		frame.list:SetPoint("BOTTOMRIGHT")
		return frame
	end,
	show = function(frame)
		M:ScanGuildOnline()
		Update(frame)
	end,
	refresh = function(frame) Update(frame) end,
	enable = function()
		Listen()
		HookTooltip()
		E:RegisterEvent("GUILD_ROSTER_UPDATE", function() M:MarkGuildOnline() end, "CharactersGuildCrafters")
		M:MarkGuildOnline()
	end,
	disable = function()
		E:UnregisterEvent("GUILD_ROSTER_UPDATE", "CharactersGuildCrafters")
		wipe(online)
		onlineDirty = true
	end,
})

---------------------------------------------------------------------------
-- /eui diag: the Retail guild-recipe API, probed only
---------------------------------------------------------------------------
E:RegisterDiagnostics("Guild crafters", function()
	local function Has(name)
		local ns, fn = name:match("^(.-)%.(.+)$")
		if ns then return type(_G[ns]) == "table" and type(_G[ns][fn]) == "function" end
		return type(_G[name]) == "function"
	end
	local found = {}
	for _, name in ipairs({ "QueryGuildRecipes", "GetGuildMemberRecipes", "GetGuildRecipeMember", "C_GuildInfo.QueryGuildMembersForRecipe" }) do
		found[#found + 1] = ("%s %s"):format(name, Has(name) and "yes" or "no")
	end
	local count = 0
	for _ in pairs(Peers()) do count = count + 1 end
	return { ("   shared lists: %d (sharing %s)"):format(count, M.db and M.db.crafterShare and "on" or "off"),
		"   guild recipe API (not used): " .. table.concat(found, ", ") }
end)

---------------------------------------------------------------------------
-- Options: under the Guild header on the Alts page
---------------------------------------------------------------------------
local ROWS = {
	{ type = "toggle", key = "crafterShare", label = "Share your recipes with the guild", desc = "Adds Send my recipes and Ask the guild buttons to the Crafters tab, to swap known recipes with guild members who use EldoUI. Nothing is sent without your click. Off by default." },
	{ type = "select", key = "crafterLine", label = "Guild crafters on tooltips", dependsOn = "crafterShare",
		values = { names = "Names (online marked)", count = "Count only", online = "Online only", compact = "Two names and a count", off = "Off" },
		order = { "names", "count", "online", "compact", "off" },
		desc = "How a crafted item's or recipe's tooltip lists the guild members who know it. The Loot Guide's Crafting page uses the same form." },
	{ type = "toggle", key = "crafterOffline", label = "Include offline crafters", dependsOn = "crafterShare", desc = "Offline guild members show in the tooltip line and the Crafters tab too, after the ones who are online." },
	{ type = "range", key = "crafterDays", label = "Forget lists after (days)", min = 7, max = 180, step = 1, dependsOn = "crafterShare",
		desc = "Recipe lists older than this leave the Crafters tab, so a member who left or stopped sharing drops out." },
}

local function InsertRows()
	local options = M.options
	if type(options) ~= "table" then return end
	local at
	for index, row in ipairs(options) do
		if row.key == "guildShare" then at = index + 1 end
	end
	at = at or #options + 1
	for offset, row in ipairs(ROWS) do table.insert(options, at + offset - 1, row) end
end
InsertRows()
