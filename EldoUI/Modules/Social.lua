-- EldoUI Social: the social and group windows in the EldoUI look.
--
-- One module for five Blizzard elements, each behind its own "Let EldoUI
-- change this" switch on the Blizzard UI page (Core/Blizzard.lua):
--   friends-frame       friends list, raid tab, quick join, ignore list (this file)
--   communities-guild   guild and communities window   (Modules/Social/Guild.lua)
--   calendar            calendar and its event dialogs (Modules/Social/Calendar.lua)
--   group-finder        LFGParentFrame: browse, listing, who list (Modules/Social/GroupFinder.lua)
--   pvp-match           scoreboard, results, battleground popup (Modules/Social/PvP.lua)
-- With an element's master switch off EldoUI leaves it exactly as Blizzard
-- made it. "Skin" puts it in the EldoUI look, "Move and scale" lets the
-- window mover (Core/WindowMover.lua) drag and scale it, "Improve" adds the
-- extra information (class colors, search box, ...). The look is recorded
-- (E:SkinRecord in Core/Skin.lua), so Skin off puts Blizzard's window back
-- at once, without a reload.
--
-- This file holds the module, the shared kit the other files use (dialog
-- and side-tab skins, element parts) and the friends window.
--
-- Presentation only. Rows are restyled after Blizzard fills them
-- (hooksecurefunc and ScrollBox callbacks); every frame and function name is
-- checked before use, Blizzard art is made invisible with SetAlpha(0), and
-- per-frame state lives in local weak tables. Nothing is ever accepted,
-- invited, queued or sent for the player.
-- Written from scratch for EldoUI; no code or media from other addons.
local _, E = ...
local L = E.L

local Key = E.Key
local M = E:NewModule("Social", {
	title = "Friends and Social",
	category = "Chat & Social",
	desc = "Friends, guild, calendar, group finder and PvP windows in the EldoUI look, with class colors, a friends search and movable windows.",
	conflicts = { "ElvUI", "EllesmereUIFriends" },
	defaults = {
		skin = true,            -- v0.5.0 switch, read once for the update (see legacy below)
		transparent = false,
		-- Friends window
		searchBox = true,
		classColors = true,
		showCharacter = true,   -- "Account (Character)" for Battle.net friends in WoW
		showRealm = false,      -- realm after names from other realms
		showNotes = false,
		editNotes = true,       -- click a friend's note to edit it in place
		groupedTab = true,      -- "Recently grouped" tab from Player Notes
		showZone = true,        -- zone or "last online" line
		classIcons = true,
		statusDot = true,
		dimOffline = true,
		compactRows = false,    -- v0.5.0 option, turned into the two sizes below
		nameSize = 13,
		infoSize = 11,
		raidSkin = true,
		quickJoinSkin = true,
		ignoreTab = false,
		-- Guild and communities
		guild = { classColors = true, offlineClassColors = true, rowSize = 12, flatRows = true, chatSize = 13 },
		-- Calendar
		calendar = { flatDays = true, dateSize = 13, weekdaySize = 12, dialogs = true },
		-- Group finder
		lfg = { whoSkin = true, whoClassColors = true, whoLevelColors = true, rowSize = 12, sideTabs = true },
		-- PvP
		pvp = { classColors = true, rowSize = 12, highlightSelf = true },
	},
})

---------------------------------------------------------------------------
-- Shared kit (used by the files in Modules/Social/)
---------------------------------------------------------------------------
local K = {}
M.kit = K

local function Usable(frame)
	return type(frame) == "table" and type(frame.GetObjectType) == "function"
		and not E.FrameCheck(frame, "IsForbidden")
end
K.Usable = Usable

local function Try(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
	return ok
end
K.Try = Try

local Secret = E.Secret
K.Secret = Secret

-- Fade a Blizzard region (or bring it back) and remember that we did.
local hiddenRegions = setmetatable({}, { __mode = "k" }) -- region -> owner key
local function Fade(region, faded, owner)
	if not (type(region) == "table" and region.SetAlpha) then return end
	if faded then
		E:SkinCapture(region)
		region:SetAlpha(0)
		hiddenRegions[region] = owner or true
	elseif hiddenRegions[region] then
		region:SetAlpha(1)
		hiddenRegions[region] = nil
	end
end
K.Fade = Fade

-- Bring back every region one owner faded (all of them without an owner).
function K.Unfade(owner)
	for region, key in pairs(hiddenRegions) do
		if not owner or key == owner then
			region:SetAlpha(1)
			hiddenRegions[region] = nil
		end
	end
end

-- Class token from a GUID, a class ID, or the localized class name.
local classByName
function K.ClassToken(localized, guid, classID)
	if type(guid) == "string" and not Secret(guid) and guid ~= "" and GetPlayerInfoByGUID then
		local ok, _, token = pcall(GetPlayerInfoByGUID, guid)
		if ok and type(token) == "string" and not Secret(token) and token ~= "" then return token end
	end
	if type(classID) == "number" and not Secret(classID) and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
		local info = C_CreatureInfo.GetClassInfo(classID)
		if info and info.classFile then return info.classFile end
	end
	if type(localized) ~= "string" or Secret(localized) or localized == "" then return end
	if not classByName then
		classByName = {}
		for _, list in ipairs({ _G.LOCALIZED_CLASS_NAMES_MALE, _G.LOCALIZED_CLASS_NAMES_FEMALE }) do
			if type(list) == "table" then
				for token, name in pairs(list) do classByName[name] = token end
			end
		end
	end
	return classByName[localized]
end

function K.ClassRGB(token)
	if type(token) ~= "string" or Secret(token) then return end
	local color = E:ClassColorObject(token)
	if color then return color.r, color.g, color.b end
end

-- Fonts for a list of FontStrings, skipping missing ones.
function K.Fonts(size, ...)
	for i = 1, select("#", ...) do
		local fs = select(i, ...)
		if type(fs) == "table" and fs.SetFont then
			E:SkinCapture(fs)
			E:SetFont(fs, size)
		end
	end
end

-- The same for texts that show a character's name or what another player
-- wrote (names, guild ranks and notes, group titles): the name font, so
-- every alphabet keeps its letters.
function K.NameFonts(size, ...)
	for i = 1, select("#", ...) do
		local fs = select(i, ...)
		if type(fs) == "table" and fs.SetFont then
			E:SkinCapture(fs)
			E:SetNameTextFont(fs, size)
		end
	end
end

-- A piece of a window's look with a switch of its own, recorded under
-- "<element>:<name>": built inside its record the first time, then
-- switched off and on with its option.
function K.Want(part, name, roots, want, build, ...)
	local key = part.id .. ":" .. name
	part.records = part.records or {}
	part.records[key] = true
	if not want then
		E:SkinRecordOff(key)
		return false
	end
	E:SkinRecordOn(key)
	E:SkinRecord(key, roots, build, ...)
	return true
end

-- Every record of a part off (Skin off, the element off or the module off).
local function RecordsOff(part)
	E:SkinRecordOff(part.id)
	for key in pairs(part.records or {}) do E:SkinRecordOff(key) end
end

-- Dialog-style frames (DialogBorderTemplate + DialogHeaderTemplate): the
-- border and header art go invisible, an art-style panel goes behind.
function K.SkinDialog(frame, opts)
	if not Usable(frame) then return end
	opts = opts or {}
	E:SkinAlphaZero(frame.Border, frame.NineSlice, frame.Bg, frame.Background, frame.background)
	local header = frame.Header
	if Usable(header) then
		E:StripTextures(header)
		local text = header.Text or header.text
		if text and text.SetFont then
			E:SetFont(text, E.tokens.size.cardTitle)
			text:SetTextColor(1, 1, 1)
		end
	end
	return E:SkinPanel(frame, { strip = opts.strip or false, accentLine = opts.accentLine or false, insets = false,
		close = opts.close, title = false, transparent = M.db and M.db.transparent, keep = opts.keep })
end

-- Icon tabs on the side of a window (Communities, Group Finder): a flat
-- box behind the icon; Blizzard's own selected texture is tinted with the
-- accent, so Blizzard keeps deciding which tab is selected.
local sideTabs = setmetatable({}, { __mode = "k" })
function K.SkinSideTab(tab)
	if not Usable(tab) or sideTabs[tab] then return end
	local keep = {}
	for _, key in ipairs({ "Icon", "IconOverlay", "Mask", "CircleMask" }) do
		if type(tab[key]) == "table" then keep[tab[key]] = true end
	end
	local selected = tab.SelectedTexture or (tab.GetCheckedTexture and tab:GetCheckedTexture())
	if selected then keep[selected] = true end
	E:StripTextures(tab, keep)
	local bd = CreateFrame("Frame", nil, tab)
	bd:SetPoint("TOPLEFT", 0, 0)
	bd:SetPoint("BOTTOMRIGHT", 0, 0)
	bd:SetFrameLevel(math.max(tab:GetFrameLevel() - 1, 0))
	E:SetTemplate(bd)
	if selected and selected.SetColorTexture then
		selected:ClearAllPoints()
		selected:SetAllPoints(bd)
		E:AccentTexture(selected, 0.3)
	end
	if tab.Icon and tab.Icon.SetTexCoord then E:TrimIcon(tab.Icon) end
	sideTabs[tab] = bd
end

---------------------------------------------------------------------------
-- Moving and scaling: the window mover (Core/WindowMover.lua) does it for
-- every social window. The parts below only ask it to re-check a window
-- after their element switch changed.
---------------------------------------------------------------------------
function M.ApplyWindow(_, key)
	E:WindowMoverApply(key)
end
M.RestoreWindow = M.ApplyWindow

---------------------------------------------------------------------------
-- Element parts: each Blizzard element registers a part. A part runs
-- part.setup() once when its Blizzard addon is loaded, and part.apply()
-- after every change; both run out of combat. Its look is recorded under
-- the element id: with Skin off the record is off before part.apply()
-- runs. part.undo() puts back the extras.
---------------------------------------------------------------------------
local parts = {}
M.parts = parts

local function RunPart(part)
	if not M.active or not E:BlizzardAllowed(part.id) then return end
	if not part.ready then
		if part.setup then
			local ok = Try(part.setup, part)
			if not ok then return end
		end
		part.ready = true
	end
	if E:BlizzardAllowed(part.id, "skin") then
		E:SkinRecordOn(part.id)
	else
		RecordsOff(part)
	end
	if part.apply then Try(part.apply, part) end
end

function M:ApplyPart(part)
	if not self.active then return end
	if part.addon and not C_AddOns.IsAddOnLoaded(part.addon) then
		if part.waiting then return end
		part.waiting = true
		E:OnBlizzardAddOn(part.addon, function()
			part.waiting = false
			E:RunOutOfCombat(function() RunPart(part) end)
		end)
		return
	end
	E:RunOutOfCombat(function() RunPart(part) end)
end

function M.UndoPart(_, part)
	RecordsOff(part)
	if part.ready and part.undo then
		E:RunOutOfCombat(function() Try(part.undo, part) end)
	end
end

-- part: { id = element id, addon = Blizzard addon (nil = always loaded),
-- setup, apply, undo, install = { ... }, legacy = function }
function M.AddPart(_, part)
	table.insert(parts, part)
	E:RegisterBlizzardHandler(part.id, {
		owner = "Social",
		apply = function() M:ApplyPart(part) end,
		undo = function() M:UndoPart(part) end,
		-- The look is recorded, so Skin off needs no reload.
		restore = { skin = true },
		install = part.install,
		legacy = part.legacy,
	})
	return part
end

-- Options shared by every tab: a pointer to the switches and the window scale.
function M.SwitchOptions(_, id, windowKeys)
	local data = E.blizzardElements and E.blizzardElements[id]
	local title = data and data.title or id
	local list = {
		{ type = "description", label = "These work while \"%s\" is on in Blizzard UI; each one names the switch it needs there.", labelFill = title },
		{ type = "execute", label = "Open Blizzard UI switches", desc = "Open the Blizzard UI page, where you choose what EldoUI may change.",
			func = function() E:ToggleConfig("blizzard") end },
	}
	if windowKeys and #windowKeys > 0 then
		table.insert(list, { type = "execute", label = "Open Windows",
			desc = "Dragging, the mouse wheel scale and the reset of this window are on the Move windows page, with every other Blizzard window.",
			func = function() E:ToggleConfig("windows") end })
	end
	return list
end

-- Sub-files add their tab with this.
function M:AddOptions(list)
	for _, option in ipairs(list) do table.insert(self.options, option) end
end

---------------------------------------------------------------------------
-- Friends window (friends-frame)
---------------------------------------------------------------------------
local FRIENDS = "friends-frame"
local rowParts = setmetatable({}, { __mode = "k" })   -- row -> { dot, classIcon }
local rowAlpha = setmetatable({}, { __mode = "k" })   -- row -> true while we changed its alpha
local infoText = setmetatable({}, { __mode = "k" })   -- info line -> { set = our text, base = Blizzard's }
local own = {}                                         -- our frames: search box, ignore tab

local BUTTON_BNET = _G.FRIENDS_BUTTON_TYPE_BNET or 2
local BUTTON_WOW = _G.FRIENDS_BUTTON_TYPE_WOW or 3

-- Status meaning, not decoration (DESIGN.md: green / yellow / red / gray).
-- Each status is a text token, so the color-blind palette applies; with
-- shape marks on, the mark carries a shape too.
local STATUS_KINDS = { online = "good", away = "warn", busy = "bad", offline = "dim" }

local function Skin() return M.active and E:BlizzardAllowed(FRIENDS, "skin") end
local function Improve() return M.active and E:BlizzardAllowed(FRIENDS, "improve") end

local function ClassWrap(text, token)
	if not M.db.classColors or not token then return text end
	local color = E:ClassColorObject(token)
	return color and color:WrapTextInColorCode(text) or text
end

local function SetClassIcon(texture, token)
	if not token then return false end
	local ok = pcall(texture.SetAtlas, texture, "classicon-" .. token:lower())
	if ok and texture:GetAtlas() then
		texture:SetTexCoord(0, 1, 0, 1)
		return true
	end
	local coords = _G.CLASS_ICON_TCOORDS and _G.CLASS_ICON_TCOORDS[token]
	if not coords then return false end
	texture:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
	texture:SetTexCoord(coords[1] + 0.015, coords[2] - 0.015, coords[3] + 0.015, coords[4] - 0.015)
	return true
end

-- Friend list names follow this override.
E:RegisterNameFormatUser("Social", { title = "Friends list", order = 50,
	desc = "Name format of character names in the friends list (WoW friends, and the character after a Battle.net friend). Needs Improve for the friends window on the Blizzard UI page.",
	refresh = function() if M.active then M:QueueRows() end end })

local function CharacterName(name, realm)
	if type(name) ~= "string" or name == "" then return end
	if M.db.showRealm then
		if realm and realm ~= "" and realm ~= GetRealmName() and not name:find("-", 1, true) then
			name = name .. "-" .. realm
		end
	elseif Ambiguate then
		name = Ambiguate(name, "short")
	end
	return E:FormatNameString(name, "Social")
end

-- What a row shows, read from the game's own friend data.
local function FriendData(buttonType, id)
	if buttonType == BUTTON_BNET and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
		local info = C_BattleNet.GetFriendAccountInfo(id)
		if not info then return end
		local game = info.gameAccountInfo or {}
		local inWoW = game.isOnline and game.clientProgram == (_G.BNET_CLIENT_WOW or "WoW") and game.characterName
		local status = "offline"
		if game.isOnline or info.isOnline then
			status = "online"
			if info.isDND or game.isGameBusy then status = "busy"
			elseif info.isAFK or game.isGameAFK then status = "away" end
		end
		return {
			bnet = true,
			accountName = info.accountName,
			character = inWoW and CharacterName(game.characterName, game.realmName) or nil,
			class = inWoW and K.ClassToken(game.className, game.playerGuid) or nil,
			note = info.note,
			bnetID = info.bnetAccountID,
			status = status,
			online = status ~= "offline",
		}
	elseif buttonType == BUTTON_WOW and C_FriendList and C_FriendList.GetFriendInfoByIndex then
		local info = C_FriendList.GetFriendInfoByIndex(id)
		if not info then return end
		local status = "offline"
		if info.connected then
			status = "online"
			if info.dnd then status = "busy" elseif info.afk then status = "away" end
		end
		return {
			character = CharacterName(info.name),
			name = info.name,
			class = info.connected and K.ClassToken(info.className, info.guid) or nil,
			note = info.notes,
			status = status,
			online = info.connected and true or false,
		}
	end
end

local function Parts(row)
	local parts_ = rowParts[row]
	if parts_ then return parts_ end
	parts_ = {}
	parts_.dot = row:CreateTexture(nil, "OVERLAY")
	parts_.dot:SetTexture(E.media.dot)
	parts_.dot:SetSize(8, 8)
	parts_.dot:Hide()
	parts_.mark = row:CreateFontString(nil, "OVERLAY")
	E:SetFont(parts_.mark, E.tokens.size.label)
	parts_.mark:Hide()
	parts_.classIcon = row:CreateTexture(nil, "ARTWORK", nil, 2)
	parts_.classIcon:Hide()
	rowParts[row] = parts_
	return parts_
end

local function SearchText()
	local box = own.search
	if not (box and box:IsShown()) then return "" end
	return (box:GetText() or ""):lower()
end

local function Matches(row, query)
	if query == "" then return true end
	for _, fs in ipairs({ row.name, row.info }) do
		if fs and fs.GetText then
			local ok, text = pcall(fs.GetText, fs)
			if ok and type(text) == "string" and text:lower():find(query, 1, true) then return true end
		end
	end
	return false
end

local function RowAlpha(row, alpha)
	if alpha < 1 then
		row:SetAlpha(alpha)
		rowAlpha[row] = true
	elseif rowAlpha[row] then
		row:SetAlpha(1)
		rowAlpha[row] = nil
	end
end

local function Sizes()
	local db = M.db
	return db.nameSize or 13, db.infoSize or 11
end

-- Put a row back the way Blizzard drew it (our extras off).
local function PlainRow(row)
	local parts_ = rowParts[row]
	if parts_ then
		parts_.dot:Hide()
		parts_.mark:Hide()
		parts_.classIcon:Hide()
		if parts_.noteHit then parts_.noteHit:Hide() end
	end
	RowAlpha(row, 1)
	for _, region in ipairs({ row.status, row.gameIcon, row.info }) do Fade(region, false) end
	local info = row.info
	local last = info and infoText[info]
	if last then
		if info:GetText() == last.set then info:SetText(last.base) end
		infoText[info] = nil
	end
end

function M:StyleFriendRow(row, elementData)
	if not Usable(row) or not self.active then return end
	local skin, improve = Skin(), Improve()
	if not skin and not improve then return end
	local db = self.db
	local buttonType = (type(elementData) == "table" and elementData.buttonType) or row.buttonType
	local id = (type(elementData) == "table" and elementData.id) or row.id
	local nameSize, infoSize = Sizes()
	local friend = buttonType == BUTTON_BNET or buttonType == BUTTON_WOW
	if skin then E:SkinRecord(FRIENDS, row, M.SkinFriendRow, row, friend, nameSize, infoSize) end

	if not friend then
		-- Dividers and invite headers: fonts only.
		PlainRow(row)
		return
	end

	local name, info = row.name, row.info
	if not improve then
		PlainRow(row)
		return
	end
	local ok, data = pcall(FriendData, buttonType, id)
	if not ok or not data then return end
	local parts_ = Parts(row)

	-- Name: account name, then the character in brackets in class color.
	if name and name.SetText then
		local text
		if data.bnet then
			if data.character and db.showCharacter then
				text = ("%s " .. E:TextHex("secondary") .. "(|r%s" .. E:TextHex("secondary") .. ")|r"):format(data.accountName or "", ClassWrap(data.character, data.class))
			end
		elseif data.character then
			text = ClassWrap(data.character, data.class)
		end
		if text then Try(name.SetText, name, text) end
		if not data.online then name:SetTextColor(unpack(E.media.text.secondary)) end
	end

	-- Zone / last online line, with the note after it.
	local zone
	if info and info.SetText then
		Fade(info, not db.showZone and not (db.showNotes and data.note and data.note ~= ""), FRIENDS)
		-- Blizzard's own text, even when we appended to it on an earlier pass.
		local current = info:GetText() or ""
		local last = infoText[info]
		local base = (last and current == last.set) and last.base or current
		zone = base
		if db.showNotes and type(data.note) == "string" and data.note ~= "" then
			local note = data.note:gsub("|", "||")
			local where = db.showZone and base or ""
			local text = where ~= "" and (where .. "  " .. E:TextHex("secondary") .. note .. "|r") or (E:TextHex("secondary") .. note .. "|r")
			info:SetText(text)
			infoText[info] = { set = text, base = base }
		elseif last then
			if current == last.set then info:SetText(base) end
			infoText[info] = nil
		end
	end

	-- A click on the note edits it in place.
	M.UpdateNoteHit(row, parts_, data, zone)

	-- Status mark after the name, instead of Blizzard's status icon: the
	-- shape mark (+ ! x) in the status color, or a dot in that color while
	-- shape marks are off (offline is always the gray dot).
	Fade(row.status, db.statusDot, FRIENDS)
	if db.statusDot and name then
		local kind = STATUS_KINDS[data.status] or "dim"
		local color = E.tokens.text[kind] or E.tokens.text.dim
		local mark = E:StatusMark(kind)
		local width = math.min(name:GetStringWidth() or 0, name:GetWidth() or 0)
		parts_.dot:ClearAllPoints()
		parts_.mark:ClearAllPoints()
		if mark ~= "" then
			E:SetFont(parts_.mark, nameSize)
			parts_.mark:SetText(mark)
			parts_.mark:SetTextColor(color[1], color[2], color[3])
			parts_.mark:SetPoint("LEFT", name, "LEFT", width + 4, 0)
			parts_.mark:Show()
			parts_.dot:Hide()
		else
			parts_.dot:SetVertexColor(color[1], color[2], color[3])
			parts_.dot:SetPoint("LEFT", name, "LEFT", width + 4, 0)
			parts_.dot:Show()
			parts_.mark:Hide()
		end
	else
		parts_.dot:Hide()
		parts_.mark:Hide()
	end

	-- Class icon over the game icon while the friend plays a WoW character.
	local icon = row.gameIcon
	local showClass = db.classIcons and data.class and icon and icon:IsShown()
	if showClass then
		parts_.classIcon:ClearAllPoints()
		parts_.classIcon:SetAllPoints(icon)
		showClass = SetClassIcon(parts_.classIcon, data.class)
	end
	parts_.classIcon:SetShown(showClass and true or false)
	Fade(icon, showClass and true or false, FRIENDS)

	-- Offline rows dimmed; rows that don't match the search fade further.
	local alpha = (db.dimOffline and not data.online) and E.tokens.disabledAlpha or 1
	if not Matches(row, SearchText()) then alpha = 0.2 end
	RowAlpha(row, alpha)
end

-- The look of one row (inside the friends window's record).
function M.SkinFriendRow(row, friend, nameSize, infoSize)
	E:SkinRow(row)
	if not friend then
		K.NameFonts(infoSize + 1, row.name, row.Text, row.Name, row.info)
		return
	end
	K.NameFonts(nameSize, row.name)
	local info = row.info
	if info and info.SetFont then
		K.NameFonts(infoSize, info)
		info:SetTextColor(unpack(E.media.text.secondary))
	end
end

local function FriendsBox()
	local list = _G.FriendsListFrame
	return list and Usable(list.ScrollBox) and list.ScrollBox
end

function M.RefreshRows(_)
	local box = FriendsBox()
	if box and box.ForEachFrame then
		pcall(box.ForEachFrame, box, function(row, data)
			Try(M.StyleFriendRow, M, row, type(data) == "table" and data or nil)
		end)
	end
end

local refreshQueued = false
function M.QueueRows(_)
	if refreshQueued then return end
	refreshQueued = true
	C_Timer.After(0, function()
		refreshQueued = false
		if M.active then
			M:RefreshRows()
			M:RefreshSocialCards()
		end
	end)
end

local function Tabs(prefix, count)
	local list = {}
	for i = 1, count do
		local tab = _G[prefix .. i]
		if Usable(tab) then list[#list + 1] = tab end
	end
	return list
end

local function SubTabs()
	local header = _G.FriendsTabHeader
	local system = header and header.TabSystem
	local list = {}
	if system and type(system.tabs) == "table" then
		for _, tab in ipairs(system.tabs) do
			if Usable(tab) then list[#list + 1] = tab end
		end
	end
	return list
end

local function IgnoreWindow()
	local friends = _G.FriendsFrame
	local window = friends and friends.IgnoreListWindow
	return Usable(window) and window or nil
end

-- A flat "Ignore" tab next to the sub-tabs opens Blizzard's ignore list
-- (the same as Contacts > Ignore list). Only on a click, out of combat.
function M.CreateIgnoreTab(_)
	local subTabs = SubTabs()
	local last = subTabs[#subTabs]
	if own.ignore or not IgnoreWindow() or not last then return end
	local tab = CreateFrame("Button", "EldoUI_SocialIgnoreTab", last:GetParent())
	tab:SetSize(70, last:GetHeight() > 0 and last:GetHeight() or 24)
	tab:SetPoint("LEFT", last, "RIGHT", 2, 0)
	tab:SetScript("OnClick", function()
		local window = IgnoreWindow()
		if not window or InCombatLockdown() then return end
		if type(window.ToggleFrame) == "function" then Try(window.ToggleFrame, window) end
		C_Timer.After(0, function() E:UpdateTabs() end)
	end)
	E:SkinTabs({ tab }, { plain = true, isSelected = function() local w = IgnoreWindow(); return w and w:IsShown() or false end })
	tab:SetText(_G.IGNORE or L["Ignore"])
	local window = IgnoreWindow()
	window:HookScript("OnShow", function() E:UpdateTabs() end)
	window:HookScript("OnHide", function() E:UpdateTabs() end)
	own.ignore = tab
	E:UpdateTabs()
end

function M.CreateSearch(_)
	local box = FriendsBox()
	if own.search or not box then return end
	local search = CreateFrame("EditBox", "EldoUI_SocialSearch", _G.FriendsListFrame, "SearchBoxTemplate")
	search:SetHeight(20)
	search:SetPoint("BOTTOMLEFT", box, "TOPLEFT", 6, 4)
	search:SetPoint("BOTTOMRIGHT", box, "TOPRIGHT", -6, 4)
	search:SetAutoFocus(false)
	if search.Instructions then search.Instructions:SetText(L["Search friends"]) end
	search:HookScript("OnTextChanged", function() M:QueueRows() end)
	search:SetScript("OnEscapePressed", function(edit) edit:ClearFocus() end)
	search:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
	E:SkinEditBox(search, { left = 2, right = 0 })
	search:Hide()
	own.search = search
end

---------------------------------------------------------------------------
-- Friend notes in place: with "Show notes" on, a click on the note
-- part of a friend's second line opens a box on that line. Enter saves it
-- through the game's own call (C_FriendList.SetFriendNotes for a WoW
-- friend, BNSetFriendNote for a Battle.net friend), Escape cancels.
---------------------------------------------------------------------------
local noteEditor -- one box, moved to the row being edited

-- target: { name = WoW friend's name } or { bnetID = bnetAccountID }.
function M.SaveFriendNote(target, text)
	if type(target) ~= "table" then return false end
	text = type(text) == "string" and strtrim(text) or ""
	if target.bnetID and type(rawget(_G, "BNSetFriendNote")) == "function" then
		return (pcall(BNSetFriendNote, target.bnetID, text))
	elseif target.name and C_FriendList and C_FriendList.SetFriendNotes then
		local ok, found = pcall(C_FriendList.SetFriendNotes, target.name, text)
		return ok and found ~= false
	end
	return false
end

local function SameTarget(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then return false end
	if a.bnetID or b.bnetID then return a.bnetID == b.bnetID end
	return a.name == b.name
end

function M.NoteEditor(_)
	if noteEditor then return noteEditor end
	local box = CreateFrame("EditBox", "EldoUI_SocialNoteEditor", _G.FriendsFrame)
	box:SetAutoFocus(false)
	box:SetTextInsets(4, 4, 0, 0)
	E:SetFont(box, M.db.infoSize or E.tokens.size.small)
	E:SkinEditBox(box)
	-- A note can hold names: the name font keeps every alphabet.
	E:UseNameFont(box)
	box:SetScript("OnEnterPressed", function(self)
		local target = self.target
		self.target = nil
		local text = self:GetText()
		self:Hide()
		if target then M.SaveFriendNote(target, text) end
		M:QueueRows()
	end)
	box:SetScript("OnEscapePressed", function(self)
		self.target = nil
		self:Hide()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self.target = nil
		self:Hide()
	end)
	box:Hide()
	noteEditor = box
	return box
end

function M:EditFriendNote(row, target)
	local info = row and row.info
	if not (info and type(target) == "table") then return end
	local box = self:NoteEditor()
	box:SetParent(row)
	box:SetFrameLevel(row:GetFrameLevel() + 5)
	box:ClearAllPoints()
	box:SetPoint("LEFT", info, "LEFT", -2, 0)
	box:SetPoint("RIGHT", row, "RIGHT", -6, 0)
	box:SetHeight(E.tokens.height.row)
	box:SetMaxLetters(target.bnetID and 127 or 48)
	box.target, box.row = target, row
	box:SetText(target.note or "")
	box:Show()
	box:SetFocus()
	box:HighlightText()
end

-- The click area over the note part of a friend row's second line.
local function NoteHit(row, parts_)
	local hit = CreateFrame("Button", nil, row)
	hit:SetFrameLevel(row:GetFrameLevel() + 3)
	local hover = hit:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	-- Left-click edits; a right-click still opens the friend's menu (the
	-- row's own click).
	hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	hit:SetScript("OnClick", function(self, button)
		if E:IsOptionsLinkClick(self, button) then return end
		if button == "RightButton" then
			local onClick = row:GetScript("OnClick")
			if onClick then Try(onClick, row, button) end
			return
		end
		M:EditFriendNote(row, self.target)
	end)
	E.UIKit.Tooltip(hit, L["Your note"], function(tooltip)
		local target = hit.target
		local has = target and type(target.note) == "string" and target.note ~= ""
		E:TooltipHint(tooltip, { L["Click"], has and L["edit the note"] or L["add a note"] })
		E.UIKit.TipText(tooltip, L["Enter saves, Escape cancels."])
	end)
	parts_.measure = row:CreateFontString(nil, "OVERLAY")
	parts_.measure:SetAlpha(0)
	E:BindOptionsLink(hit, { page = "module:Social", key = "editNotes" })
	parts_.noteHit = hit
	return hit
end

-- How wide `text` is in the font of `fontString`.
local function TextWidth(parts_, fontString, text)
	local measure = parts_.measure
	local font, size, flags = fontString:GetFont()
	if not (measure and font) then return 0 end
	measure:SetFont(font, size, flags)
	measure:SetText(text)
	return measure:GetStringWidth() or 0
end

-- Show or hide the note click area of a row (from StyleFriendRow).
function M.UpdateNoteHit(row, parts_, data, zone)
	local db = M.db
	local info = row.info
	local target = (data.name or data.bnetID) and { name = data.name, bnetID = data.bnetID, note = data.note } or nil
	if noteEditor and noteEditor.row == row and noteEditor:IsShown() and not SameTarget(noteEditor.target, target) then
		noteEditor.target = nil
		noteEditor:Hide()
	end
	if not (db.showNotes and db.editNotes and info and target) then
		if parts_.noteHit then parts_.noteHit:Hide() end
		return
	end
	local hit = parts_.noteHit or NoteHit(row, parts_)
	local left = 0
	if db.showZone and type(zone) == "string" and not Secret(zone) and zone ~= "" then
		left = math.min(TextWidth(parts_, info, zone .. "  "), math.max((info:GetWidth() or 0) - 24, 0))
	end
	hit:ClearAllPoints()
	hit:SetPoint("TOPLEFT", info, "TOPLEFT", left, 2)
	hit:SetPoint("BOTTOMRIGHT", info, "BOTTOMRIGHT", 0, -2)
	hit.target = target
	hit:Show()
end

---------------------------------------------------------------------------
-- Recently grouped: a tab next to the friends sub-tabs with the
-- last 50 players from Player Notes' group journal, as two-line rows: the
-- class icon, the name in class color with your mark, then when and where
-- and your note on a muted line. Boxed buttons on the right: Whisper,
-- Invite and Add friend (your clicks: the game's whisper box,
-- C_PartyInfo.InviteUnit and C_FriendList.AddFriend, out of combat). A row
-- click edits your Player Notes note.
---------------------------------------------------------------------------
local function Notes()
	local notes = E.PlayerNotes
	return notes and notes.active and notes or nil
end

local function MyRealm()
	local realm = GetNormalizedRealmName and GetNormalizedRealmName()
	return type(realm) == "string" and not Secret(realm) and realm or nil
end

-- The name to show and to add: "Name" on your realm, else "Name-Realm".
function M.GroupedName(entry)
	if type(entry) ~= "table" or type(entry.name) ~= "string" then return nil end
	local realm = MyRealm()
	if entry.realm and entry.realm ~= "?" and entry.realm ~= realm then return entry.name .. "-" .. entry.realm end
	return entry.name
end

function M.IsWoWFriend(name)
	if type(name) ~= "string" or not (C_FriendList and C_FriendList.GetFriendInfo) then return false end
	local ok, info = pcall(C_FriendList.GetFriendInfo, name)
	return ok and type(info) == "table" and info.name ~= nil
end

function M:AddGroupedFriend(entry)
	local name = M.GroupedName(entry)
	local panel = own.grouped
	if not name or not (C_FriendList and C_FriendList.AddFriend) then return false end
	if InCombatLockdown() then
		if panel then E.UIKit.Toast(panel, L["Add friends after combat."], { warn = true }) end
		return false
	end
	local ok = pcall(C_FriendList.AddFriend, name)
	if panel then
		E.UIKit.Toast(panel, ok and L["%s is on your friends list now."]:format(name) or L["The game did not add %s."]:format(name),
			{ warn = not ok })
	end
	self:RefreshGrouped()
	return ok
end

-- Open a whisper to a player in the chat box (the game's own tell).
function K.Whisper(name)
	if type(name) ~= "string" or name == "" then return false end
	local util = rawget(_G, "ChatFrameUtil")
	local tell = util and util.SendTell or rawget(_G, "ChatFrame_SendTell")
	if not tell then return false end
	return Try(tell, name)
end

function M.InviteGrouped(_, entry)
	local name = M.GroupedName(entry)
	if not name or not (C_PartyInfo and C_PartyInfo.InviteUnit) then return false end
	return Try(C_PartyInfo.InviteUnit, name)
end

local MARK_TOKENS = { good = "good", avoid = "bad" }

local function GroupedInfo(entry, friend)
	local notes = Notes()
	local parts_ = {}
	if friend then parts_[#parts_ + 1] = L["Friend"] end
	local when = notes and notes.Ago and notes.Ago(entry.last) or ""
	local grouped = E:Plural(entry.grouped or 1, L["grouped %d time"], L["grouped %d times"]):format(entry.grouped or 1)
	parts_[#parts_ + 1] = grouped .. ", " .. when .. (entry.zone and (", " .. entry.zone) or "")
	if type(entry.note) == "string" and entry.note ~= "" then
		parts_[#parts_ + 1] = E:TokenHex(E.tokens.text.body) .. entry.note:gsub("|", "||") .. "|r"
	end
	return table.concat(parts_, "  ·  ")
end

local GROUPED_ACTIONS = {
	{ key = "whisper", art = "Interface\\ChatFrame\\UI-ChatWhisperIcon", mono = true, tipTitle = Key("Whisper"),
		tip = Key("Opens a whisper to this player in the chat box."),
		onClick = function(item) if item then K.Whisper(M.GroupedName(item)) end end },
	{ key = "invite", art = "profile", tipTitle = Key("Invite"), tip = Key("Invites this player to your group."),
		onClick = function(item) if item then M:InviteGrouped(item) end end },
	{ key = "add", art = "Interface\\Buttons\\UI-PlusButton-Up", mono = true, tipTitle = Key("Add friend"),
		tip = Key("Adds this player to your WoW friends list."),
		onClick = function(item) if item then M:AddGroupedFriend(item) end end },
}

local function GroupedRowCreate(row)
	row.add = row.actionByKey.add
	row:SetScript("OnClick", function(self, button)
		if E:IsOptionsLinkClick(self, button) then return end
		local notes = Notes()
		if notes and self.item then notes:EditNote(self.item.key) end
	end)
	E.UIKit.Tooltip(row, L["Recently grouped"], nil, { { L["Click"], L["write your Player Notes note on this player"] } })
	E:BindOptionsLink(row, { page = "module:Social", key = "groupedTab" })
end

local function GroupedRowUpdate(row, item)
	local name = M.GroupedName(item) or item.key
	local friend = M.IsWoWFriend(name)
	local notes = Notes()
	local mark = item.mark and notes and notes.MARKS[item.mark]
	local sub = GroupedInfo(item, friend)
	row:SetRow({
		name = name,
		class = M.db.classColors and item.class or nil,
		status = mark and MARK_TOKENS[item.mark] or nil,
		statusText = mark and mark.label or nil,
		sub = sub,
		hide = { add = friend },
	})
	-- The whole second line on hover, for when the row cuts it short.
	row.kitTipTitle, row.kitTipText = name, sub
	if not SetClassIcon(row.icon.icon, item.class) then
		row.icon:SetIcon("Interface\\Icons\\INV_Misc_GroupNeedMore")
		E:TrimIcon(row.icon.icon)
	end
end

function M:RefreshGrouped()
	for _, panel in pairs({ friends = own.grouped, social = own.socialGrouped }) do
		if panel:IsShown() then self:FillGrouped(panel) end
	end
end

function M.FillGrouped(_, panel)
	local notes = Notes()
	local items = notes and notes:RecentlyGrouped() or {}
	local off = notes and notes.db and notes.db.journal == false
	panel.list:SetEmpty(L["Nobody yet"],
		off and L["Player Notes' group journal is off. Turn on Group journal under Player Notes to fill this list."]
			or L["Players you group with show up here, the last one first, with your notes and marks."],
		"Interface\\Icons\\INV_Misc_GroupNeedMore")
	panel.list:SetData(items)
end

-- While the Recently grouped page shows, Blizzard's open sub-tab must not
-- look selected. Skinned tabs ask own.grouped (see SkinFriends); Blizzard's
-- own tab art only gets SetAlpha on its "active" textures and a text color,
-- both widget calls that Blizzard's next tab update puts back. Nothing is
-- written into Blizzard's tables and no Blizzard tab code is called.
local ACTIVE_ART = { "LeftActive", "MiddleActive", "RightActive" }
function M.MarkSubTabs(_)
	local showing = own.grouped and own.grouped:IsShown() and true or false
	for _, tab in ipairs(SubTabs()) do
		if not E:GetSkin(tab, "tab") then
			for _, key in ipairs(ACTIVE_ART) do
				local art = tab[key]
				if Usable(art) and art.SetAlpha then art:SetAlpha(showing and 0 or 1) end
			end
			local text = tab.GetFontString and tab:GetFontString()
			local ok, selected = pcall(function() return tab.IsSelected and tab:IsSelected() end)
			if text and text.SetTextColor and ok and selected then
				local color = showing and rawget(_G, "NORMAL_FONT_COLOR") or rawget(_G, "HIGHLIGHT_FONT_COLOR")
				if type(color) == "table" and color.r then text:SetTextColor(color.r, color.g, color.b) end
			end
		end
	end
	E:UpdateTabs()
end

-- Any Blizzard tab (bottom or sub-tab) brings Blizzard's page back; tabs
-- the tab system makes later are hooked when the page opens.
local hookedTabs = setmetatable({}, { __mode = "k" })
function M.HookBlizzardTabs(_)
	local tabs = SubTabs()
	for _, other in ipairs(Tabs("FriendsFrameTab", 4)) do tabs[#tabs + 1] = other end
	for _, other in ipairs(tabs) do
		if not hookedTabs[other] then
			hookedTabs[other] = true
			other:HookScript("OnClick", function()
				if own.grouped and own.grouped:IsShown() then M:ShowGrouped(false) end
			end)
		end
	end
end

function M:ShowGrouped(show)
	local panel = own.grouped
	if not panel then return end
	panel:SetShown(show and true or false)
	if panel:IsShown() then
		self:HookBlizzardTabs()
		self:RefreshGrouped()
	end
	self:MarkSubTabs()
end

local function GroupedArea()
	local inset = _G.FriendsFrameInset
	if Usable(inset) then return inset end
	local box = FriendsBox()
	return box
end

-- The Recently grouped page: a title, a line on where it comes from and
-- the list. The friends window and the social window each get one.
local function GroupedPanel(name, parent)
	local panel = CreateFrame("Frame", name, parent)
	panel:EnableMouse(true)
	E:SetTemplate(panel)
	panel.title = E.UIKit.Text(panel, E.tokens.size.section, "LEFT", "header")
	panel.title:SetPoint("TOPLEFT", 10, -8)
	panel.title:SetPoint("TOPRIGHT", -10, -8)
	panel.title:SetText(L["Recently grouped"])
	panel.sub = E.UIKit.Text(panel, E.tokens.size.small, "LEFT", "secondary")
	panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -3)
	panel.sub:SetPoint("TOPRIGHT", panel.title, "BOTTOMRIGHT", 0, -3)
	panel.sub:SetText(L["The last 50 players from your group journal."])
	panel.list = E.UIKit.CreateList(panel, E.UIKit.ListRow2Template({ gap = 1,
		create = GroupedRowCreate, update = GroupedRowUpdate, row = { actions = GROUPED_ACTIONS } }))
	panel.list:SetPoint("TOPLEFT", 4, -42)
	panel.list:SetPoint("BOTTOMRIGHT", -4, 4)
	panel:Hide()
	return panel
end

function M.CreateGroupedTab(_)
	local area = GroupedArea()
	local last = SubTabs()
	last = last[#last]
	if own.groupedTab or not area or not last then return end
	local panel = GroupedPanel("EldoUI_SocialGrouped", _G.FriendsFrame)
	panel:SetPoint("TOPLEFT", area, "TOPLEFT", 2, -2)
	panel:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -2, 2)
	panel:SetFrameLevel(area:GetFrameLevel() + 20)
	own.grouped = panel

	local tab = CreateFrame("Button", "EldoUI_SocialGroupedTab", last:GetParent())
	tab:SetSize(118, last:GetHeight() > 0 and last:GetHeight() or E.tokens.height.tab)
	tab:SetScript("OnClick", function() M:ShowGrouped(not panel:IsShown()) end)
	E:SkinTabs({ tab }, { plain = true, isSelected = function() return panel:IsShown() end })
	tab:SetText(L["Recently grouped"])
	own.groupedTab = tab

	M:HookBlizzardTabs()
	_G.FriendsFrame:HookScript("OnHide", function()
		panel:Hide()
		M:MarkSubTabs()
	end)
	-- Player Notes may have been turned on or off since the last apply.
	_G.FriendsFrame:HookScript("OnShow", function() if M.active then M:UpdateGroupedTab() end end)
	local notes = E.PlayerNotes
	if notes and notes.OnChanged then notes:OnChanged(function() M:RefreshGrouped() end) end
	M:PlaceGroupedTab()
end

-- The tab shows with Improve, its option and Player Notes on.
function M.UpdateGroupedTab(_)
	local tab = own.groupedTab
	if not tab then return end
	local shown = Improve() and M.db.groupedTab and Notes() ~= nil
	tab:SetShown(shown and true or false)
	if not shown and own.grouped:IsShown() then
		own.grouped:Hide()
		M:MarkSubTabs()
	end
	M:PlaceGroupedTab()
	M:RefreshGrouped()
end

-- After the last sub-tab, or after the Ignore tab when it shows.
function M.PlaceGroupedTab(_)
	local tab = own.groupedTab
	if not tab then return end
	local anchor = own.ignore and own.ignore:IsShown() and own.ignore
	if not anchor then
		local tabs = SubTabs()
		anchor = tabs[#tabs]
	end
	if not anchor then return end
	tab:ClearAllPoints()
	tab:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
end

---------------------------------------------------------------------------
-- The social window (SocialUIFrame). Forever can show the friends list
-- there instead of the friends window. That window brings its own search
-- bar (skinned with the window) and keeps its ignore list in a menu, so
-- EldoUI adds the Ignore and Recently grouped tabs under its bottom edge,
-- flat like the friends window's own tabs. Ignore opens Blizzard's ignore
-- list through Blizzard's own call, on a click and out of combat only.
---------------------------------------------------------------------------
local function SocialWindow()
	local social = _G.SocialUIFrame
	return Usable(social) and social or nil
end

local function SocialIgnoreWindow()
	local social = SocialWindow()
	local window = social and social.IgnoreListFrame
	return Usable(window) and window or nil
end

-- Blizzard's own call that opens the ignore list beside the friends list.
local function ToggleSocialIgnore()
	local control, tabs, sides = _G.SocialUIControl, _G.SocialUITabType, _G.SocialUISideWindowType
	if type(control) ~= "table" or type(control.ToggleToTabAndSideWindow) ~= "function" then return false end
	if type(tabs) ~= "table" or type(sides) ~= "table" or tabs.Friends == nil or sides.IgnoreListFrame == nil then return false end
	return Try(control.ToggleToTabAndSideWindow, tabs.Friends, sides.IgnoreListFrame)
end

-- The friends list's own search bar in the social window, or nil.
local function SocialSearchBar()
	local social = SocialWindow()
	local list = social and social.FriendsList
	local bar = list and list.FilterBar and list.FilterBar.SearchBar
	return Usable(bar) and bar or nil
end

-- Friend cards in the social window: the class-colored character name and
-- your note are EldoUI's own text over the card (Blizzard measures its own
-- strings to lay the card out, so they are never written to), and offline
-- cards are dimmed. Read from the card's own friend data.
local cardParts = setmetatable({}, { __mode = "k" }) -- card -> { name, note }

local function CardParts(card)
	local parts_ = cardParts[card]
	if parts_ then return parts_ end
	parts_ = {}
	parts_.name = card:CreateFontString(nil, "OVERLAY")
	parts_.name:SetJustifyH("LEFT")
	parts_.name:SetWordWrap(false)
	parts_.name:Hide()
	parts_.note = card:CreateFontString(nil, "OVERLAY")
	parts_.note:SetJustifyH("LEFT")
	parts_.note:SetWordWrap(false)
	parts_.note:Hide()
	cardParts[card] = parts_
	return parts_
end

local function PlainCard(card)
	local parts_ = cardParts[card]
	if parts_ then
		parts_.name:Hide()
		parts_.note:Hide()
	end
	Fade(card.Name, false)
	RowAlpha(card, 1)
end

function M:StyleSocialCard(card)
	if not Usable(card) then return end
	local data = card.elementData
	local info = type(data) == "table" and data.accountInfo
	if not (self.active and Improve() and type(info) == "table" and card.Name and card.Location) then
		PlainCard(card)
		return
	end
	local db, parts_ = self.db, CardParts(card)
	local game = type(info.gameAccountInfo) == "table" and info.gameAccountInfo or {}
	local online = (game.isOnline or info.isOnline) and true or false
	local inWoW = game.isOnline and game.clientProgram == (_G.BNET_CLIENT_WOW or "WoW") and game.characterName
	local class = inWoW and K.ClassToken(game.className, game.playerGuid) or nil
	local _, infoSize = Sizes()

	-- The character name in its class color, drawn where Blizzard's is.
	local character = db.classColors and class and card.Name:IsShown() and CharacterName(game.characterName, game.realmName)
	if character then
		local font, size, flags = card.Name:GetFont()
		if not (font and E:SetNameFont(parts_.name, font, size, flags)) then E:SetNameTextFont(parts_.name, infoSize + 1) end
		parts_.name:ClearAllPoints()
		parts_.name:SetAllPoints(card.Name)
		parts_.name:SetText(ClassWrap(character, class))
		parts_.name:Show()
	else
		parts_.name:Hide()
	end
	Fade(card.Name, character and true or false, FRIENDS)

	-- Your note on a line of its own under the location.
	local note = db.showNotes and type(info.note) == "string" and info.note ~= "" and info.note
	if note then
		E:SetNameTextFont(parts_.note, infoSize)
		parts_.note:SetTextColor(unpack(E.media.text.secondary))
		parts_.note:ClearAllPoints()
		parts_.note:SetPoint("TOPLEFT", card.Location, "BOTTOMLEFT", 0, -2)
		parts_.note:SetPoint("TOPRIGHT", card.Location, "BOTTOMRIGHT", 0, -2)
		parts_.note:SetText((note:gsub("|", "||")))
		parts_.note:Show()
	else
		parts_.note:Hide()
	end

	RowAlpha(card, (db.dimOffline and not online) and E.tokens.disabledAlpha or 1)
end

local socialCardsHooked
local cardHooked = setmetatable({}, { __mode = "k" }) -- card -> true once its Initialize is hooked
local function HookSocialCards()
	local social = SocialWindow()
	local list = social and social.FriendsList
	local box = list and list.ScrollBox
	if socialCardsHooked == box or not Usable(box) then return end
	socialCardsHooked = box
	E:HookScrollBoxRows(box, function(card)
		-- A card gets its friend when Blizzard initializes it, after it is acquired.
		if not cardHooked[card] and type(card.Initialize) == "function" then
			cardHooked[card] = true
			hooksecurefunc(card, "Initialize", function(self) Try(M.StyleSocialCard, M, self) end)
		end
		M:StyleSocialCard(card)
	end)
	pcall(box.RegisterCallback, box, "OnDataRangeChanged", function() M:QueueRows() end, cardParts)
end

function M.RefreshSocialCards(_)
	local social = SocialWindow()
	local box = social and social.FriendsList and social.FriendsList.ScrollBox
	if not (Usable(box) and box.ForEachFrame) then return end
	pcall(box.ForEachFrame, box, function(card) Try(M.StyleSocialCard, M, card) end)
end

function M:ShowSocialGrouped(show)
	local panel = own.socialGrouped
	if not panel then return end
	panel:SetShown(show and true or false)
	if panel:IsShown() then self:FillGrouped(panel) end
	E:UpdateTabs()
end

function M.CreateSocialTabs(_)
	local social = SocialWindow()
	if not social or own.socialFor == social then return end
	own.socialFor = social
	if own.socialGrouped then
		own.socialGrouped:Hide()
		own.socialGroupedTab:Hide()
		own.socialIgnore:Hide()
	end
	local panel = GroupedPanel("EldoUI_SocialUIGrouped", social)
	-- Where the window draws its pages: under the Battle.net bar.
	local bar = social.BattleNetBar
	if Usable(bar) then
		panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 2, 3)
	else
		panel:SetPoint("TOPLEFT", social, "TOPLEFT", 4, -60)
	end
	panel:SetPoint("BOTTOMRIGHT", social, "BOTTOMRIGHT", -4, 4)
	panel:SetFrameLevel(social:GetFrameLevel() + 20)
	own.socialGrouped = panel

	local height = E.tokens.height.tab
	local grouped = CreateFrame("Button", "EldoUI_SocialUIGroupedTab", social)
	grouped:SetSize(118, height)
	grouped:SetScript("OnClick", function() M:ShowSocialGrouped(not panel:IsShown()) end)
	E:SkinTabs({ grouped }, { plain = true, isSelected = function() return panel:IsShown() end })
	grouped:SetText(L["Recently grouped"])
	own.socialGroupedTab = grouped

	local ignore = CreateFrame("Button", "EldoUI_SocialUIIgnoreTab", social)
	ignore:SetSize(70, height)
	ignore:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		M:ShowSocialGrouped(false)
		ToggleSocialIgnore()
		C_Timer.After(0, function() E:UpdateTabs() end)
	end)
	E:SkinTabs({ ignore }, { plain = true, isSelected = function() local w = SocialIgnoreWindow(); return w and w:IsShown() or false end })
	ignore:SetText(_G.IGNORE or L["Ignore"])
	own.socialIgnore = ignore
	local window = SocialIgnoreWindow()
	if window then
		window:HookScript("OnShow", function() E:UpdateTabs() end)
		window:HookScript("OnHide", function() E:UpdateTabs() end)
	end

	-- Blizzard's own tabs bring Blizzard's page back.
	if type(social.SelectTab) == "function" then
		hooksecurefunc(social, "SelectTab", function() if panel:IsShown() then M:ShowSocialGrouped(false) end end)
	end
	social:HookScript("OnHide", function() panel:Hide() end)
	social:HookScript("OnShow", function() if M.active then M:UpdateSocialTabs() end end)
	M:UpdateSocialTabs()
end

-- Each tab shows with Improve and its option (Recently grouped also needs
-- Player Notes); the shown ones line up from the window's bottom left.
function M.UpdateSocialTabs(_)
	local social = SocialWindow()
	local grouped, ignore = own.socialGroupedTab, own.socialIgnore
	if not (social and grouped and ignore and own.socialFor == social) then return end
	local groupedOn = Improve() and M.db.groupedTab and Notes() ~= nil and true or false
	local ignoreOn = Improve() and M.db.ignoreTab and SocialIgnoreWindow() ~= nil and true or false
	grouped:SetShown(groupedOn)
	ignore:SetShown(ignoreOn)
	if not groupedOn and own.socialGrouped:IsShown() then M:ShowSocialGrouped(false) end
	local anchor
	for _, tab in ipairs({ grouped, ignore }) do
		if tab:IsShown() then
			tab:ClearAllPoints()
			if anchor then
				tab:SetPoint("LEFT", anchor, "RIGHT", 2, 0)
			else
				tab:SetPoint("TOPLEFT", social, "BOTTOMLEFT", 0, -2)
			end
			anchor = tab
		end
	end
	if own.socialGrouped:IsShown() then M:FillGrouped(own.socialGrouped) end
end

local function SkinRaidTab()
	for _, name in ipairs({ "RaidFrameConvertToRaidButton", "RaidFrameRaidInfoButton", "RaidInfoExtendButton", "RaidInfoCancelButton" }) do
		E:SkinButton(_G[name])
	end
	E:SkinCheckBox(_G.RaidFrameAllAssistCheckButton)
	local notInRaid = _G.RaidFrameNotInRaid
	if Usable(notInRaid) then E:SkinScrollBar(notInRaid.ScrollingDescriptionScrollBar) end
	-- The raid group slots are secure unit buttons (Blizzard_RaidUI) and stay Blizzard's.
	local info = _G.RaidInfoFrame
	if Usable(info) then
		K.SkinDialog(info, { close = true })
		E:SkinAlphaZero(_G.RaidInfoDetailHeader, _G.RaidInfoDetailFooter)
		for _, label in ipairs({ _G.RaidInfoInstanceLabel, _G.RaidInfoIDLabel }) do
			if Usable(label) then
				E:StripTextures(label)
				if label.text then
					E:SetFont(label.text, E.tokens.size.label)
					label.text:SetTextColor(unpack(E.media.text.secondary))
				end
			end
		end
		E:SkinScrollBar(info.ScrollBar)
		if Usable(info.ScrollBox) then
			E:HookScrollBoxRows(info.ScrollBox, function(row)
				E:SkinRow(row)
				K.Fonts(12, row.name, row.difficulty, row.reset, row.extended)
			end)
		end
	end
end

local function SkinQuickJoin()
	local quickJoin = _G.QuickJoinFrame
	if not Usable(quickJoin) then return end
	E:SkinButton(quickJoin.JoinQueueButton)
	E:SkinScrollBar(quickJoin.ScrollBar)
	if Usable(quickJoin.ScrollBox) then E:HookScrollBoxRows(quickJoin.ScrollBox, function(row) E:SkinRow(row) end) end
end

local function SkinFriends()
	local friends = _G.FriendsFrame
	Try(E.SkinPanel, E, friends, { transparent = M.db.transparent })
	E:SkinInset(_G.FriendsFrameInset)

	-- BattleTag header, broadcast and status dropdown.
	local bnet = _G.FriendsFrameBattlenetFrame
	if Usable(bnet) then
		E:StripTextures(bnet)
		if bnet.Tag and bnet.Tag.SetFont then
			E:SetNameTextFont(bnet.Tag, E.tokens.size.cardTitle)
			bnet.Tag:SetTextColor(1, 1, 1)
		end
		local broadcast = bnet.BroadcastFrame
		if Usable(broadcast) then
			K.SkinDialog(broadcast)
			E:SkinButton(broadcast.UpdateButton)
			E:SkinButton(broadcast.CancelButton)
		end
	end
	E:SkinDropdown(_G.FriendsFrameStatusDropdown)

	-- Bottom tabs (Contacts / Raid / Quick Join) and the sub-tabs.
	E:SkinTabs(Tabs("FriendsFrameTab", 4), { owner = friends })
	-- A sub-tab is not "selected" while the Recently grouped page shows.
	E:SkinTabs(SubTabs(), { plain = true, isSelected = function()
		if own.grouped and own.grouped:IsShown() then return false end
	end })

	for _, name in ipairs({ "FriendsFrameAddFriendButton", "FriendsFrameSendMessageButton" }) do
		E:SkinButton(_G[name])
	end
	local list = _G.FriendsListFrame
	if Usable(list) then E:SkinScrollBar(list.ScrollBar) end

	-- Recent allies and the ignore list.
	local recent = _G.RecentAlliesFrame
	local recentList = recent and recent.List
	if Usable(recentList) then
		E:SkinScrollBar(recentList.ScrollBar)
		if Usable(recentList.ScrollBox) then E:HookScrollBoxRows(recentList.ScrollBox, function(row) E:SkinRow(row) end) end
	end
	local ignore = IgnoreWindow()
	if ignore then
		Try(E.SkinPanel, E, ignore, { transparent = M.db.transparent })
		E:SkinButton(ignore.UnignorePlayerButton)
		E:SkinScrollBar(ignore.ScrollBar)
		if Usable(ignore.ScrollBox) then E:HookScrollBoxRows(ignore.ScrollBox, function(row) E:SkinRow(row) end) end
	end
end

local friendsHooked = false
local function HookFriends()
	if friendsHooked then return end
	friendsHooked = true
	local box = FriendsBox()
	if box then
		E:HookScrollBoxRows(box, function(row) M:StyleFriendRow(row) end)
		pcall(box.RegisterCallback, box, "OnDataRangeChanged", function() M:QueueRows() end, own)
	end
	if type(_G.FriendsFrame_UpdateFriendButton) == "function" then
		hooksecurefunc("FriendsFrame_UpdateFriendButton", function(row, elementData)
			if M.active then Try(M.StyleFriendRow, M, row, elementData) end
		end)
	end
	if type(_G.FriendsList_Update) == "function" then
		hooksecurefunc("FriendsList_Update", function() if M.active then M:QueueRows() end end)
	end
	if type(_G.FriendsFrame_Update) == "function" then
		hooksecurefunc("FriendsFrame_Update", function() if M.active and Skin() then E:UpdateTabs() end end)
	end
	_G.FriendsFrame:HookScript("OnShow", function() if M.active then M:QueueRows() end end)
end

local friendsPart = M:AddPart({
	id = FRIENDS,
	install = { skin = true, improve = true },
	-- v0.5.0 skinned the friends window whenever the module was on.
	legacy = function() return M.db.enabled ~= false and M.db.skin ~= false end,
	setup = function()
		if not Usable(_G.FriendsFrame) then error("EldoUI Social: FriendsFrame is missing") end
		HookFriends()
	end,
	apply = function(part)
		local db = M.db
		if Skin() then
			E:SkinRecord(FRIENDS, { _G.FriendsFrame, IgnoreWindow(), _G.SocialUIFrame, SocialIgnoreWindow() }, function()
				if not part.skinned then
					part.skinned = true
					SkinFriends()
				end
				-- Forever can show the friends list inside the social window
				-- (SocialUIFrame) instead of the friends window; its outer frame
				-- gets the same panel look when the client has it.
				local social = _G.SocialUIFrame
				if Usable(social) then
					if not part.social then
						part.social = true
						Try(E.SkinPanel, E, social, { transparent = db.transparent })
						local search = SocialSearchBar()
						if search then Try(E.SkinEditBox, E, search) end
					end
					-- The social window's own ignore list, like the friends window's.
					local socialIgnore = SocialIgnoreWindow()
					if socialIgnore and part.socialIgnore ~= socialIgnore then
						part.socialIgnore = socialIgnore
						Try(E.SkinPanel, E, socialIgnore, { transparent = db.transparent })
						E:SkinButton(socialIgnore.BlockButton)
						E:SkinButton(socialIgnore.UnblockButton)
						E:SkinScrollBar(socialIgnore.ScrollBar)
						if Usable(socialIgnore.ScrollBox) then E:HookScrollBoxRows(socialIgnore.ScrollBox, function(row) E:SkinRow(row) end) end
					end
					if socialIgnore then E:SetPanelTransparent(socialIgnore, db.transparent) end
					E:SetPanelTransparent(social, db.transparent)
				end
				E:SetPanelTransparent(_G.FriendsFrame, db.transparent)
				local ignore = IgnoreWindow()
				if ignore then E:SetPanelTransparent(ignore, db.transparent) end
			end)
			K.Want(part, "raid", { _G.RaidFrame, _G.RaidInfoFrame }, db.raidSkin, function()
				if part.raid then return end
				part.raid = true
				Try(SkinRaidTab)
			end)
			K.Want(part, "quickJoin", _G.QuickJoinFrame, db.quickJoinSkin, function()
				if part.quickJoin then return end
				part.quickJoin = true
				Try(SkinQuickJoin)
			end)
		end
		if Improve() then
			Try(M.CreateSearch, M)
			if db.ignoreTab then Try(M.CreateIgnoreTab, M) end
			if db.groupedTab and E.PlayerNotes then Try(M.CreateGroupedTab, M) end
			if (db.ignoreTab or (db.groupedTab and E.PlayerNotes)) then Try(M.CreateSocialTabs, M) end
		end
		if own.search then
			own.search:SetShown(Improve() and db.searchBox)
			if not own.search:IsShown() then own.search:SetText("") end
		end
		if own.ignore then own.ignore:SetShown(Improve() and db.ignoreTab) end
		M:UpdateGroupedTab()
		M:UpdateSocialTabs()
		if Improve() then HookSocialCards() end
		if not Improve() then
			for row in pairs(rowParts) do PlainRow(row) end
			for card in pairs(cardParts) do PlainCard(card) end
			K.Unfade(FRIENDS)
		end
		M:ApplyWindow("friends")
		E:UpdateTabs()
		M:RefreshRows()
		M:RefreshSocialCards()
	end,
	undo = function()
		if own.search then
			own.search:SetText("")
			own.search:Hide()
		end
		if own.ignore then own.ignore:Hide() end
		if own.groupedTab then
			own.groupedTab:Hide()
			own.grouped:Hide()
			M:MarkSubTabs()
		end
		if own.socialGroupedTab then
			own.socialGroupedTab:Hide()
			own.socialIgnore:Hide()
			own.socialGrouped:Hide()
		end
		for row in pairs(rowParts) do PlainRow(row) end
		for card in pairs(cardParts) do PlainCard(card) end
		for row in pairs(rowAlpha) do row:SetAlpha(1) end
		wipe(rowAlpha)
		K.Unfade(FRIENDS)
		M:RestoreWindow("friends")
	end,
})
M.friendsPart = friendsPart

---------------------------------------------------------------------------
-- Module life cycle
---------------------------------------------------------------------------
function M:OnInitialize()
	-- v0.5.0 "Compact text" becomes the two text sizes.
	if self.db.compactRows and not self.db.sizesMigrated then
		self.db.nameSize, self.db.infoSize = 12, 10
	end
	self.db.sizesMigrated = true
end

function M:ApplyAll()
	for _, part in ipairs(parts) do
		if E:BlizzardAllowed(part.id) then
			self:ApplyPart(part)
		elseif part.ready then
			self:UndoPart(part)
		end
	end
end

function M:OnEnable()
	self:ApplyAll()
	self:RegisterEvent("FRIENDLIST_UPDATE", function() M:QueueRows() end)
	self:RegisterEvent("BN_FRIEND_INFO_CHANGED", function() M:QueueRows() end)
end

function M:OnDisable()
	self:UnregisterEvent("FRIENDLIST_UPDATE")
	self:UnregisterEvent("BN_FRIEND_INFO_CHANGED")
	for _, part in ipairs(parts) do self:UndoPart(part) end
end

function M:OnProfileChanged()
	if not self.active then return end
	self:ApplyAll()
end

---------------------------------------------------------------------------
-- Options (the other files add their tabs after these)
---------------------------------------------------------------------------
-- The windows the see-through switch styles: it is usable while EldoUI
-- skins any of them (the group finder's filter bar counts too).
local SEE_THROUGH = { { FRIENDS, "skin" }, { "communities-guild", "skin" }, { "calendar", "skin" },
	{ "group-finder", "skin" }, { "group-finder", "improve" }, { "pvp-match", "skin" } }

local function NoSeeThroughWindow()
	for _, entry in ipairs(SEE_THROUGH) do
		if E:BlizzardAllowed(entry[1], entry[2]) then return false end
	end
	return L["Turn on Skin for the friends, guild, calendar, group finder or PvP window under Blizzard UI first."]
end

M.options = {
	{ type = "tab", label = "General" },
	{ type = "header", label = "All social windows" },
	{ type = "description", label = "Each window has its own switch on the Blizzard UI page. With it off, EldoUI leaves Blizzard's window untouched." },
	{ type = "execute", label = "Open Blizzard UI switches", desc = "Open the Blizzard UI page, where you choose what EldoUI may change.",
		func = function() E:ToggleConfig("blizzard") end },
	{ type = "toggle", disabled = NoSeeThroughWindow, key = "transparent", label = "See-through windows",
		desc = "The friends, guild, calendar, group finder and PvP windows let the game show through a little. How much: General > Panel opacity." },

	{ type = "tab", label = "Friends" },
}
M:AddOptions(M:SwitchOptions(FRIENDS, { { "friends", "Friends window" } }))
M:AddOptions({
	{ type = "header", label = "Window" },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "searchBox", label = "Search box",
		desc = "A box above the friends list. Rows that don't match what you type fade out; nothing is filtered away. The social window keeps its own search bar." },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "ignoreTab", label = "Ignore tab",
		desc = "A flat Ignore tab next to Friends / Recent Allies (under the social window) that opens Blizzard's ignore list (also in the Contacts menu)." },
	{ type = "toggle", key = "groupedTab", label = "Recently grouped tab",
		desc = "A tab next to the friends tabs with the last 50 players you grouped with, your Player Notes mark and note on each, and an Add friend button. Needs the Player Notes module. On by default.",
		disabled = E:BlizzardNeeds(FRIENDS, "improve", function() return not (E.PlayerNotes and E.PlayerNotes.active) and L["Turn on the Player Notes module to use this."] end) },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "skin"), key = "raidSkin", label = "Raid tab skin",
		desc = "Flat buttons on the Raid tab and the raid info window. The raid group slots stay Blizzard's (they are secure)." },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "skin"), key = "quickJoinSkin", label = "Quick Join skin", desc = "Flat rows and button on the Quick Join tab." },
	{ type = "header", label = "Friend rows" },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "classColors", label = "Class colors", desc = "Character names in their class color." },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "classIcons", label = "Class icons", desc = "The class icon in place of the game icon while a friend plays a WoW character." },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "showCharacter", label = "Character name in brackets",
		desc = "Battle.net friends playing WoW show as Account (Character)." },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "showRealm", label = "Show realm", desc = "Adds the realm after characters from another realm." },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "showZone", label = "Zone or last online", desc = "The second line: where the friend is, or when they were last online." },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "showNotes", label = "Show notes", desc = "Your note for the friend, after the zone line (in the social window, on a line under the location)." },
	{ type = "toggle", key = "editNotes", label = "Edit notes in place", dependsOn = "showNotes", disabled = E:BlizzardNeeds(FRIENDS, "improve"),
		desc = "Click a friend's note (or the empty end of the zone line) to edit it right in the list. Enter saves, Escape cancels. On by default." },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "statusDot", label = "Status mark",
		desc = "A status mark after the name in place of Blizzard's icon: green online, yellow away, red busy, gray offline. With shape marks on, it also has a shape." },
	{ type = "toggle", disabled = E:BlizzardNeeds(FRIENDS, "improve"), key = "dimOffline", label = "Dim offline friends", desc = "Offline rows are drawn fainter." },
	{ type = "range", disabled = E:BlizzardNeeds(FRIENDS, "skin"), key = "nameSize", label = "Name text size", min = 9, max = 18, step = 1, desc = "Size of the name line in each row." },
	{ type = "range", disabled = E:BlizzardNeeds(FRIENDS, "skin"), key = "infoSize", label = "Zone text size", min = 8, max = 16, step = 1, desc = "Size of the zone / last online line." },
})

---------------------------------------------------------------------------
-- Style presets (all five windows)
---------------------------------------------------------------------------
local function Friends(t)
	local base = { searchBox = true, classColors = true, showCharacter = true, showRealm = false, showZone = true,
		showNotes = false, classIcons = true, statusDot = true, dimOffline = true, nameSize = 13, infoSize = 11,
		raidSkin = true, quickJoinSkin = true, ignoreTab = false, transparent = false, editNotes = true, groupedTab = true }
	for key, value in pairs(t or {}) do base[key] = value end
	return base
end

E:RegisterStyles("Social", {
	{ key = "EldoUI", title = "EldoUI", desc = "Class icons and colors, status dots, zone line, search box, dimmed offline friends; class-colored guild, who list and scoreboard.",
		settings = Friends({
			guild = { classColors = true, offlineClassColors = true, rowSize = 12, flatRows = true, chatSize = 13 },
			calendar = { flatDays = true, dateSize = 13, weekdaySize = 12, dialogs = true },
			lfg = { whoSkin = true, whoClassColors = true, whoLevelColors = true, rowSize = 12, sideTabs = true },
			pvp = { classColors = true, rowSize = 12, highlightSelf = true },
		}) },
	{ key = "Compact", title = "Compact", desc = "Smaller text everywhere, no notes.",
		settings = Friends({ nameSize = 12, infoSize = 10,
			guild = { classColors = true, offlineClassColors = true, rowSize = 11, flatRows = true, chatSize = 12 },
			calendar = { flatDays = true, dateSize = 11, weekdaySize = 11, dialogs = true },
			lfg = { whoSkin = true, whoClassColors = true, whoLevelColors = true, rowSize = 11, sideTabs = true },
			pvp = { classColors = true, rowSize = 11, highlightSelf = true },
		}) },
	{ key = "Detailed", title = "Detailed", desc = "Realms and your notes on every friend, larger text, ignore tab.",
		settings = Friends({ showRealm = true, showNotes = true, ignoreTab = true, nameSize = 14, infoSize = 12,
			guild = { classColors = true, offlineClassColors = true, rowSize = 13, flatRows = true, chatSize = 14 },
			calendar = { flatDays = true, dateSize = 14, weekdaySize = 13, dialogs = true },
			lfg = { whoSkin = true, whoClassColors = true, whoLevelColors = true, rowSize = 13, sideTabs = true },
			pvp = { classColors = true, rowSize = 13, highlightSelf = true },
		}) },
	{ key = "Minimal", title = "Minimal", desc = "See-through panels, names and dots only, no extra colors on the level columns.",
		settings = Friends({ transparent = true, searchBox = false, showCharacter = false, showZone = false, classIcons = false,
			nameSize = 12, infoSize = 10,
			guild = { classColors = true, offlineClassColors = false, rowSize = 11, flatRows = true, chatSize = 12 },
			calendar = { flatDays = true, dateSize = 12, weekdaySize = 11, dialogs = true },
			lfg = { whoSkin = true, whoClassColors = true, whoLevelColors = false, rowSize = 11, sideTabs = true },
			pvp = { classColors = true, rowSize = 11, highlightSelf = false },
		}) },
	{ key = "Glass", title = "Glass", desc = "See-through panels with every extra on: for a UI that shows the world behind its windows.",
		settings = Friends({ transparent = true,
			guild = { classColors = true, offlineClassColors = true, rowSize = 12, flatRows = true, chatSize = 13 },
			calendar = { flatDays = true, dateSize = 13, weekdaySize = 12, dialogs = true },
			lfg = { whoSkin = true, whoClassColors = true, whoLevelColors = true, rowSize = 12, sideTabs = true },
			pvp = { classColors = true, rowSize = 12, highlightSelf = true },
		}) },
	{ key = "Blizzard", title = "Blizzard rows", desc = "EldoUI windows with Blizzard's own row colors, status icons and calendar day art.",
		settings = Friends({ searchBox = false, classColors = false, classIcons = false, statusDot = false, dimOffline = false,
			guild = { classColors = false, offlineClassColors = false, rowSize = 12, flatRows = false, chatSize = 13 },
			calendar = { flatDays = false, dateSize = 13, weekdaySize = 12, dialogs = true },
			lfg = { whoSkin = true, whoClassColors = false, whoLevelColors = false, rowSize = 12, sideTabs = false },
			pvp = { classColors = false, rowSize = 12, highlightSelf = false },
		}) },
})
