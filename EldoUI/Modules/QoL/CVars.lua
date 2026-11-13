-- EldoUI Quality of Life: every game setting (CVar) in one browser, and
-- rows for useful settings the game's own menu does not show, on
-- the page's Sound and misc tab.
--
--   +--------------------------------------------------------------+
--   | Game Settings  All settings 1412  Set by EldoUI 3  [search] x |
--   |--------------------------------------------------------------|
--   | [Changed] [Advanced]                            [Restore all] |
--   | Name                    Value     Default   Help             |
--   | * cameraYawMoveSpeed    90        180       ...              |
--   |--------------------------------------------------------------|
--   | cameraYawMoveSpeed: help text                                |
--   | [ 90        ]  [Set] [Default] [Restore]                     |
--   |--------------------------------------------------------------|
--   | 1412 settings, 23 changed, 3 set by EldoUI                // |
--   +--------------------------------------------------------------+
--
-- The list comes from the client (ConsoleGetAllCommands, CVars only);
-- values from C_CVar.GetCVarInfo. Secure CVars are never listed, locked
-- and read-only ones only with "Advanced" and never editable. Every write
-- goes through E:SetCVar(name, value, "cvars"), which remembers the
-- player's own value the first time, so Restore puts it back. A CVar that
-- another part of EldoUI set (Chat, Combat Text, Quality of Life rows ...) is shown
-- with its owner and changed only on that page. The window closes when
-- combat starts and nothing is written in combat.
--
-- Hidden settings: labeled rows on the Quality of Life page (floating combat text
-- extras, chat, camera and graphics) in the "Game setting" pattern of the game
-- setting shortcuts above them: a row is never written until the player
-- picks a value, and "Game setting" or "Restore game settings" puts their
-- own value back. Rows whose CVar this client lacks are hidden.
-- Written from scratch for EldoUI.
local _, E = ...
local L = E.L
local Key = E.Key
local Kit = E.UIKit
local M = E:GetModule("QoL")

local OWNER = "cvars"       -- browser writes
local ROW_OWNER = "Tweaks"  -- hidden setting rows (same owner as the shortcuts, kept from before the merge)
local WIDTH, HEIGHT = 900, 580

M.defaults.cvarAdvanced = false
M.defaults.cvarOnlyChanged = false
M.defaults.cvarWindow = {}

---------------------------------------------------------------------------
-- Reading the client
---------------------------------------------------------------------------
-- What EldoUI remembers about the game settings it changed (E:SetCVar):
-- per setting { value = the player's own value, owner = the part of EldoUI
-- that changed it }. Only E:SetCVar, E:RestoreCVar and E:RestoreCVars
-- change it; everything else reads it through the two calls below.
local function Snapshot()
	return type(EldoUIDB) == "table" and type(EldoUIDB.cvarSnapshot) == "table" and EldoUIDB.cvarSnapshot or {}
end

-- The player's own value of a game setting EldoUI changed and the owner
-- that changed it, or nil when EldoUI did not change it.
function E:CVarSaved(name)
	local saved = Snapshot()[name]
	if type(saved) ~= "table" then return nil end
	return saved.value, saved.owner
end

-- The part of EldoUI that changed a game setting ("QoL", "cvars" ...), or nil.
function E:CVarOwner(name)
	local _, owner = self:CVarSaved(name)
	return owner
end

-- value, default, locked, secure, readOnly; nil when the client lacks it.
local function Info(name)
	if not (C_CVar and C_CVar.GetCVarInfo) then
		local value = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(name)
		if type(value) == "nil" then return nil end
		return value, C_CVar.GetCVarDefault and C_CVar.GetCVarDefault(name) or nil, false, false, false
	end
	local ok, value, default, _, _, locked, secure, readOnly = pcall(C_CVar.GetCVarInfo, name)
	if not ok or E:IsSecret(value) or E:IsSecret(default) or value == nil then return nil end
	return value, default, locked and true or false, secure and true or false, readOnly and true or false
end
M.CVarInfo = Info

local function Exists(name)
	local value, _, _, secure = Info(name)
	return value ~= nil and not secure
end

-- "1.000000" and "1" are the same setting.
local function Same(a, b)
	if a == b then return true end
	local x, y = tonumber(a), tonumber(b)
	return x ~= nil and y ~= nil and math.abs(x - y) < 1e-6
end
M.SameCVarValue = Same

-- Who in EldoUI holds the player's own value of a CVar, as a title.
local function OwnerTitle(owner)
	if owner == OWNER then return L["Settings browser"] end
	local module = E.modules[owner] or (E.ModuleByAlias and E:ModuleByAlias(owner))
	if module then return L[module.title] end
	local element = E.blizzardElements and E.blizzardElements[owner]
	if element and element.title then return L[element.title] end
	if owner == "installer" then return L["Installer"] end
	return tostring(owner)
end
M.CVarOwnerTitle = OwnerTitle

-- Console categories shown without "Advanced".
local HIDDEN_CATEGORIES = { [0] = true, [8] = true, [9] = true } -- Debug, Gm, Reveal

local function CommandList()
	-- Forever has it (ConsoleDocumentation); read through _G so a client
	-- without it shows the empty state instead of an error.
	local fn = _G.ConsoleGetAllCommands
	if type(fn) ~= "function" then return nil end
	local ok, list = pcall(fn)
	if not ok or type(list) ~= "table" then return nil end
	return list
end

-- Every CVar the client lists, as browser rows (secure ones left out).
function M:CVarRows()
	local list = CommandList()
	if not list then return nil end
	local cvarType = Enum and Enum.ConsoleCommandType and Enum.ConsoleCommandType.Cvar or 0
	local snapshot = Snapshot()
	local rows, seen = {}, {}
	for _, info in ipairs(list) do
		local name = type(info) == "table" and info.command
		if type(name) == "string" and name ~= "" and info.commandType == cvarType and not seen[name] then
			seen[name] = true
			local value, default, locked, secure, readOnly = Info(name)
			if value ~= nil and not secure then
				local saved = snapshot[name]
				rows[#rows + 1] = {
					name = name, lower = name:lower(),
					value = value, default = default,
					help = type(info.help) == "string" and info.help or "",
					category = info.category,
					locked = locked, readOnly = readOnly,
					changed = default ~= nil and not Same(value, default),
					owner = saved and saved.owner or nil,
					own = saved and saved.value or nil,
					experimental = name:find("^test_") ~= nil,
				}
			end
		end
	end
	return rows
end

-- The rows a tab shows, with the filters and the search.
function M:FilterCVarRows(rows, tab, search)
	local db = self.db
	local out = {}
	local needle = search and search ~= "" and search:lower() or nil
	for _, row in ipairs(rows or {}) do
		local keep = true
		if tab == "eldoui" then
			keep = row.owner ~= nil
		else
			if not db.cvarAdvanced and (row.locked or row.readOnly or HIDDEN_CATEGORIES[row.category]) then keep = false end
			if keep and db.cvarOnlyChanged and not (row.changed or row.owner) then keep = false end
		end
		if keep and needle then
			keep = row.lower:find(needle, 1, true) ~= nil or row.help:lower():find(needle, 1, true) ~= nil
		end
		if keep then out[#out + 1] = row end
	end
	return out
end

-- Why a row can't be edited here, or nil.
function M:CVarBlocked(row)
	if not row then return L["Pick a setting in the list first."] end
	if InCombatLockdown() then return L["Game settings change out of combat."] end
	if row.readOnly then return L["The game shows this setting but does not let it change."] end
	if row.locked then return L["The game locks this setting."] end
	if row.owner and row.owner ~= OWNER then
		return L["Set by %s: change it on that page."]:format(OwnerTitle(row.owner))
	end
end

---------------------------------------------------------------------------
-- Writing (through E:SetCVar, never in combat)
---------------------------------------------------------------------------
-- Returns true when the value took, or false and why not.
function M:SetBrowserCVar(name, value)
	local row
	for _, item in ipairs(self:CVarRows() or {}) do
		if item.name == name then row = item break end
	end
	local blocked = self:CVarBlocked(row)
	if blocked then return false, blocked end
	value = strtrim(tostring(value or ""))
	E:SetCVar(name, value, OWNER)
	local now = C_CVar.GetCVar(name)
	if not Same(now, value) then
		-- The game refused it: forget it again if nothing changed.
		local own, owner = E:CVarSaved(name)
		if owner == OWNER and Same(own, now) then E:RestoreCVar(name, OWNER) end
		return false, L["The game did not take that value."]
	end
	return true
end

-- Back to the player's own value from before EldoUI changed it.
function M:RestoreBrowserCVar(name)
	if InCombatLockdown() then return false, L["Game settings change out of combat."] end
	local saved = Snapshot()[name]
	if not saved or saved.owner ~= OWNER then return false, L["EldoUI did not change this setting."] end
	E:RestoreCVar(name, OWNER)
	return true
end

function M:RestoreAllBrowserCVars()
	if InCombatLockdown() then return false, L["Game settings change out of combat."] end
	E:RestoreCVars(OWNER)
	return true
end

function M:BrowserCVarCount()
	local count = 0
	for _, saved in pairs(Snapshot()) do
		if saved.owner == OWNER then count = count + 1 end
	end
	return count
end

---------------------------------------------------------------------------
-- Browser window
---------------------------------------------------------------------------
local win
local cache       -- rows from the last read
local search = ""
local selected    -- name of the selected CVar

local function Accent() return Kit.Accent() end

local function Rows(force)
	if force or not cache then cache = M:CVarRows() end
	return cache
end

local function FindRow(name)
	for _, row in ipairs(Rows() or {}) do
		if row.name == name then return row end
	end
end

local function StateText(row)
	if row.owner then return L["EldoUI: %s"]:format(OwnerTitle(row.owner)) end
	if row.readOnly then return L["read-only"] end
	if row.locked then return L["locked"] end
	if row.experimental then return L["experimental"] end
	if row.changed then return L["changed"] end
	return ""
end

local COLUMNS = {
	{ key = "name", title = L["Setting"], width = 270, desc = L["The game's name for the setting. A dot marks a value that differs from the game's default."],
		text = function(row) return (row.changed and "* " or "  ") .. row.name end,
		color = function(row)
			if row.locked or row.readOnly then return unpack(Kit.DIM) end
			if row.changed then return Accent() end
			return unpack(Kit.TEXT)
		end },
	{ key = "value", title = L["Value"], width = 110, desc = L["What the setting is now."] },
	{ key = "default", title = L["Default"], width = 110, desc = L["The game's default value."],
		color = function() return unpack(Kit.SECONDARY) end },
	{ key = "state", title = L["State"], width = 150, desc = L["Changed from the default, set by a part of EldoUI, locked or read-only."],
		value = function(row) return StateText(row) end,
		color = function(row)
			if row.owner then return Accent() end
			if row.experimental then return unpack(Kit.WARN) end
			return unpack(Kit.SECONDARY)
		end },
	{ key = "help", title = L["Help"], desc = L["The game's own short help text, where it has one."],
		color = function() return unpack(Kit.SECONDARY) end },
}

local function Toast(text, warn)
	if win and win.frame then Kit.Toast(win.frame, text, { anchor = win.frame.footer, point = "TOP", y = 4, warn = warn }) end
end

local function UpdateEditor(frame)
	local editor = frame.editor
	local row = selected and FindRow(selected)
	if not row then
		editor.title:SetText(L["Pick a setting in the list to change it."])
		editor.help:SetText("")
		editor.box:SetText("")
		editor.box:Disable()
		editor.set:Disable()
		editor.default:Disable()
		editor.restore:Disable()
		return
	end
	local blocked = M:CVarBlocked(row)
	editor.title:SetText(row.name)
	local help = row.help ~= "" and row.help or L["The game has no help text for this setting."]
	if row.experimental then help = help .. "  " .. E:TokenHex(Kit.WARN) .. L["Experimental: the game may change or drop it."] .. "|r" end
	if blocked then help = help .. "  " .. E:TokenHex(Kit.WARN) .. blocked .. "|r" end
	if row.owner == OWNER and row.own then help = help .. "  " .. L["Your own value: %s"]:format(row.own) end
	editor.help:SetText(help)
	if not editor.box:HasFocus() then editor.box:SetText(row.value or "") end
	if blocked then editor.box:Disable() else editor.box:Enable() end
	editor.set:SetEnabled(not blocked)
	editor.default:SetEnabled(not blocked and row.default ~= nil and row.changed)
	editor.restore:SetEnabled(not InCombatLockdown() and row.owner == OWNER)
end

local function Reload(frame)
	Rows(true)
	frame.table:SetData(M:FilterCVarRows(Rows(), frame.kind, search))
	UpdateEditor(frame)
	if win then win:LayoutTabs() win:UpdateFooter() win:UpdateEmpty(win:GetTab(frame.kind)) end
end

local function Apply(frame, value)
	local ok, why = M:SetBrowserCVar(selected, value)
	if ok then Toast(L["%s set to %s."]:format(selected, tostring(value))) else Toast(why, true) end
	Reload(frame)
end

local function CreateEditor(frame)
	local editor = CreateFrame("Frame", nil, frame)
	editor:SetPoint("BOTTOMLEFT")
	editor:SetPoint("BOTTOMRIGHT")
	editor:SetHeight(58)
	local line = Kit.Divider(editor)
	line:SetPoint("TOPLEFT")
	line:SetPoint("TOPRIGHT")
	editor.title = Kit.Text(editor, E.tokens.size.section, "LEFT", "header")
	editor.title:SetPoint("TOPLEFT", 4, -8)
	editor.help = Kit.Text(editor, E.tokens.size.small, "LEFT", "secondary")
	editor.help:SetPoint("LEFT", editor.title, "RIGHT", 10, 0)
	editor.help:SetPoint("RIGHT", editor, "RIGHT", -4, 0)
	editor.help:SetWordWrap(false)
	editor.box = CreateFrame("EditBox", nil, editor, "InputBoxTemplate")
	editor.box:SetSize(220, 20)
	editor.box:SetAutoFocus(false)
	editor.box:SetPoint("BOTTOMLEFT", 8, 6)
	E:SkinEditBox(editor.box)
	editor.box:SetScript("OnEnterPressed", function(box)
		box:ClearFocus()
		Apply(frame, box:GetText())
	end)
	editor.box:SetScript("OnEscapePressed", function(box)
		box:ClearFocus()
		UpdateEditor(frame)
	end)
	Kit.Tooltip(editor.box, L["New value"], L["Type a value and press Enter or Set. The game checks it; a value it refuses is not kept."])
	editor.set = Kit.Button(editor, L["Set"], 70, nil, function() Apply(frame, editor.box:GetText()) end,
		L["Set"], L["Writes the value. EldoUI remembers your own value the first time, so Restore can put it back."])
	editor.set:SetPoint("LEFT", editor.box, "RIGHT", 12, 0)
	editor.default = Kit.Button(editor, L["Default"], 80, nil, function()
		local row = FindRow(selected)
		if row and row.default then Apply(frame, row.default) end
	end, L["Default"], L["Sets the game's default value."])
	editor.default:SetPoint("LEFT", editor.set, "RIGHT", 6, 0)
	editor.restore = Kit.Button(editor, L["Restore"], 80, nil, function()
		local ok, why = M:RestoreBrowserCVar(selected)
		if ok then Toast(L["%s is back to your own value."]:format(selected)) else Toast(why, true) end
		Reload(frame)
	end, L["Restore"], L["Puts back your own value from before EldoUI changed this setting."])
	editor.restore:SetPoint("LEFT", editor.default, "RIGHT", 6, 0)
	for _, button in ipairs({ editor.set, editor.default, editor.restore }) do Kit.FitButton(button, 70) end
	frame.editor = editor
end

local function CreateTab(kind)
	return function(content)
		local frame = CreateFrame("Frame", nil, content)
		frame:SetAllPoints()
		frame.kind = kind
		if kind == "all" then
			frame.chips = Kit.ChipBar(frame, {
				multi = true,
				chips = {
					{ "changed", L["Changed"], L["Only settings that differ from the game's default or that EldoUI set."] },
					{ "advanced", L["Advanced"], L["Also debug and GM settings, and the ones the game locks or shows read-only."] },
				},
				selected = { changed = M.db.cvarOnlyChanged, advanced = M.db.cvarAdvanced },
				onChange = function(chosen)
					M.db.cvarOnlyChanged = chosen.changed and true or false
					M.db.cvarAdvanced = chosen.advanced and true or false
					Reload(frame)
				end,
			})
			frame.chips:SetPoint("TOPLEFT", 0, -2)
		end
		frame.restoreAll = Kit.Button(frame, L["Restore all"], 100, nil, function()
			local count = M:BrowserCVarCount()
			local ok, why = M:RestoreAllBrowserCVars()
			if ok then Toast(E:Plural(count, "%d setting is back to your own value.", "%d settings are back to your own values."):format(count))
			else Toast(why, true) end
			Reload(frame)
		end, L["Restore all"], L["Puts back your own value of every setting changed in this browser. Settings other EldoUI pages set stay."])
		Kit.FitButton(frame.restoreAll, 90)
		frame.restoreAll:SetPoint("TOPRIGHT", 0, 0)
		frame.table = Kit.CreateTable(frame, COLUMNS, {
			sortKey = "name",
			createRow = function(row)
				row.select = row:CreateTexture(nil, "BACKGROUND", nil, -5)
				row.select:SetAllPoints()
				row.select:Hide()
			end,
			updateRow = function(row, item)
				if item.name == selected then
					local r, g, b = Accent()
					row.select:SetColorTexture(r, g, b, E.tokens.pressed)
					row.select:Show()
				else
					row.select:Hide()
				end
			end,
			onClick = function(item)
				selected = item.name
				frame.editor.box:ClearFocus()
				frame.table:Refresh()
				UpdateEditor(frame)
			end,
		})
		frame.table:SetPoint("TOPLEFT", 0, -28)
		frame.table:SetPoint("BOTTOMRIGHT", 0, 62)
		CreateEditor(frame)
		return frame
	end
end

local function ShowTab(frame)
	if frame.chips then frame.chips:SetSelected({ changed = M.db.cvarOnlyChanged, advanced = M.db.cvarAdvanced }) end
	Reload(frame)
end

local function Empty(frame)
	if Rows() == nil then
		return L["No settings list"], L["This client does not list its game settings for addons."], "Interface\\Icons\\Trade_Engineering"
	end
	if #frame.table:Sorted() > 0 then return nil end
	if frame.kind == "eldoui" then
		return L["Nothing set by EldoUI"], L["Settings EldoUI changes for you show up here, with the page that changed them."], "Interface\\Icons\\Trade_Engineering"
	end
	return L["No settings match"], L["Change the search, or turn off Changed to see more."], "Interface\\Icons\\Trade_Engineering"
end

local function CreateWindow()
	if win then return win end
	win = Kit.CreateTabbedWindow({
		name = "EldoUICVarBrowser",
		options = { page = "module:QoL" },
		title = L["Game Settings"],
		width = WIDTH, height = HEIGHT,
		store = function() return M.db.cvarWindow end,
		tabs = {
			{ key = "all", title = L["All settings"], desc = L["Every game setting the client lists, with its value, default and help."],
				count = function() return #M:FilterCVarRows(Rows(), "all", search) end,
				create = CreateTab("all"), show = ShowTab, refresh = ShowTab, empty = Empty },
			{ key = "eldoui", title = L["Set by EldoUI"], desc = L["Settings EldoUI changed, and the page that changed them."],
				count = function() return #M:FilterCVarRows(Rows(), "eldoui", search) end,
				create = CreateTab("eldoui"), show = ShowTab, refresh = ShowTab, empty = Empty },
		},
		search = { tip = L["Type part of a name or help text and press Enter."], onSearch = function(text)
			search = text or ""
			win:Refresh("search")
		end },
		help = { text = function(tooltip)
			tooltip:AddLine(L["The same settings you could type with /console. EldoUI remembers your own value the first time it changes one, so Restore puts it back."], Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
			tooltip:AddLine(" ")
			tooltip:AddLine(L["Protected settings are not listed. The window closes in combat, and nothing changes in combat."], Kit.SECONDARY[1], Kit.SECONDARY[2], Kit.SECONDARY[3], true)
		end },
		footer = function()
			local rows = Rows() or {}
			local changed = 0
			for _, row in ipairs(rows) do if row.changed then changed = changed + 1 end end
			return L["%d settings, %d changed from the default, %d changed here"]:format(#rows, changed, M:BrowserCVarCount())
		end,
	})
	return win
end

function M:ShowCVarBrowser(tab, name)
	local window = CreateWindow()
	if name then
		selected = name
		search = name
	end
	Rows(true)
	if window:Open(tab) and name and window.frame.search then window.frame.search:SetText(name) end
	return window
end

function M:CVarBrowser()
	return win
end

E:AddCommand("cvars", "  [name] open the browser of every game setting (CVar), optionally at one setting", function(rest)
	local name = rest and strtrim(rest) or ""
	M:ShowCVarBrowser(nil, name ~= "" and name or nil)
end, "Tools")

---------------------------------------------------------------------------
-- Hidden settings: labeled rows on the Sound and misc tab
---------------------------------------------------------------------------
-- kind "switch": Game setting / On / Off. "choice": Game setting or one of
-- `values` (CVar value -> label). "range": a tick (set<key>, labeled
-- `ownLabel`) and a slider.
local HIDDEN = {
	{ group = "fct", key = "hidWorldTextScale", cvar = "WorldTextScale_v2", kind = "range", percent = true, min = 0.5, max = 2.5, step = 0.1, fallback = 1,
		label = "Combat text size", ownLabel = Key("Set my own combat text size"), desc = "Size of the damage and healing numbers over enemies and allies (game setting WorldTextScale)." },
	{ group = "fct", key = "hidWorldTextGravity", cvar = "WorldTextGravity_v2", kind = "range", min = 0, max = 2, step = 0.05, fallback = 0.5,
		label = "Combat text gravity", ownLabel = Key("Set my own combat text gravity"), desc = "How fast the numbers over targets fall after they appear. 0 lets them float (game setting WorldTextGravity)." },
	{ group = "fct", key = "hidDirectional", cvar = "floatingCombatTextCombatDamageDirectionalScale_v2", kind = "range", min = 0, max = 5, step = 0.25, fallback = 0,
		label = "Numbers fly sideways", ownLabel = Key("Set my own sideways flight"), desc = "Damage numbers move away from you in the direction of the hit. 0 is straight up, higher moves them farther." },
	{ group = "fct", key = "hidClassicText", cvar = "classicStyleWorldText", kind = "switch",
		label = "Classic style numbers", desc = "Floating combat text moves as it did in the original game instead of the modern way." },
	{ group = "fct", key = "hidAllAutos", cvar = "floatingCombatTextCombatDamageAllAutos_v2", kind = "switch",
		label = "Every auto-attack number", desc = "Shows a number for every auto-attack hit, not only for hits that do something special." },
	{ group = "fct", key = "hidPetSpell", cvar = "floatingCombatTextPetSpellDamage_v2", kind = "switch",
		label = "Pet spell damage numbers", desc = "Numbers over enemies for the damage your pet's spells do." },
	{ group = "chat", key = "hidChatScroll", cvar = "chatMouseScroll", kind = "switch",
		label = "Scroll chat with the mouse wheel", desc = "The mouse wheel scrolls chat windows up and down." },
	{ group = "chat", key = "hidChatStyle", cvar = "chatStyle", kind = "choice", values = { classic = "Classic: the box shows only while you type", im = "IM: the box stays under the chat" },
		label = "Chat input style", desc = "Where the chat input box sits: Classic shows it only while you type, IM keeps it under the chat window." },
	{ group = "chat", key = "hidProfanity", cvar = "profanityFilter", kind = "switch",
		label = "Mature language filter", desc = "The game replaces rude words in chat with symbols." },
	{ group = "chat", key = "hidGuildNotify", cvar = "guildMemberNotify", kind = "switch",
		label = "Guild members online", desc = "A chat line when a guild member comes online or goes offline." },
	{ group = "chat", key = "hidBlockInvites", cvar = "blockChannelInvites", kind = "switch",
		label = "Block channel invites", desc = "The game declines invites to chat channels for you, without asking." },
	{ group = "camera", key = "hidYawSpeed", cvar = "cameraYawMoveSpeed", kind = "range", min = 30, max = 360, step = 10, fallback = 180,
		label = "Camera turn speed", ownLabel = Key("Set my own camera turn speed"), desc = "How fast the camera turns left and right when you drag with the mouse (game setting cameraYawMoveSpeed)." },
	{ group = "camera", key = "hidPitchSpeed", cvar = "cameraPitchMoveSpeed", kind = "range", min = 30, max = 360, step = 10, fallback = 90,
		label = "Camera tilt speed", ownLabel = Key("Set my own camera tilt speed"), desc = "How fast the camera tilts up and down when you drag with the mouse (game setting cameraPitchMoveSpeed)." },
	{ group = "camera", key = "hidWaterCamera", cvar = "cameraWaterCollision", kind = "switch",
		label = "Camera stays above water", desc = "The camera stops at the water surface instead of going under it." },
	{ group = "camera", key = "hidTerrainTilt", cvar = "cameraTerrainTilt", kind = "switch",
		label = "Camera follows slopes", desc = "The camera tilts with the ground when you walk up or down a hill." },
	{ group = "camera", key = "hidDynamicPitch", cvar = "test_cameraDynamicPitch", kind = "switch", experimental = true,
		label = "Dynamic camera pitch (experimental)", desc = "The camera looks a little down when zoomed out, for a wider view. An experimental game setting: the game may change or drop it." },
	{ group = "graphics", key = "hidAlwaysSharpen", cvar = "ResampleAlwaysSharpen", kind = "switch",
		label = "Always sharpen", desc = "Runs the game's sharpening pass even when the picture is not upscaled, for crisper edges." },
	{ group = "graphics", key = "hidSoftInteractIcon", cvar = "SoftTargetIconInteract", kind = "switch",
		label = "Icons over things you can use", desc = "An icon over the object or character you would interact with next (game setting SoftTargetIconInteract)." },
	{ group = "graphics", key = "hidVolumeFog", cvar = "volumeFog", kind = "switch",
		label = "Volume fog", desc = "Fog with depth and light shafts outdoors. Off can help a slower computer." },
	{ group = "graphics", key = "hidVolumeFogInterior", cvar = "volumeFogInterior", kind = "switch",
		label = "Volume fog indoors", desc = "Fog with depth inside buildings and dungeons as well." },
	{ group = "graphics", key = "hidVolumeFogLevel", cvar = "volumeFogLevel", kind = "choice",
		values = { ["0"] = "Lowest", ["1"] = "Low", ["2"] = "Medium", ["3"] = "High" },
		label = "Volume fog quality", desc = "How detailed the volume fog is. Lower is faster." },
}
M.HIDDEN_CVARS = HIDDEN

for _, row in ipairs(HIDDEN) do
	if row.kind == "range" then
		M.defaults["set" .. row.key] = false
		M.defaults[row.key] = row.fallback
	else
		M.defaults[row.key] = "game"
	end
end

local function CurrentValue(cvar)
	return C_CVar and C_CVar.GetCVar and C_CVar.GetCVar(cvar)
end

local function OnOff(value)
	local number = tonumber(value)
	if number ~= nil then return number ~= 0 end
	return value == "true"
end

-- What a row wants written now, or nil for the game's own value.
local function Wanted(row, db)
	if row.kind == "range" then
		if not db["set" .. row.key] then return nil end
		local value = tonumber(db[row.key]) or row.fallback
		value = math.max(row.min, math.min(row.max, value))
		return tostring(value)
	end
	local value = db[row.key]
	if value == "game" or value == nil then return nil end
	if row.kind == "switch" then
		if value == "on" then return "1" elseif value == "off" then return "0" end
		return nil
	end
	if row.values and row.values[value] then return value end
	return nil
end
M.HiddenWanted = Wanted

-- Another part of EldoUI holds this CVar: its page decides.
local function HeldElsewhere(cvar)
	local saved = Snapshot()[cvar]
	return saved and saved.owner ~= ROW_OWNER and saved.owner or nil
end

function M:ApplyHiddenSettings()
	local db, on = self.db, self.active
	E:RunOutOfCombat(function()
		for _, row in ipairs(HIDDEN) do
			if not HeldElsewhere(row.cvar) and Exists(row.cvar) then
				local value = on and Wanted(row, db) or nil
				if value then
					E:SetCVar(row.cvar, value, ROW_OWNER)
				else
					E:RestoreCVar(row.cvar, ROW_OWNER)
				end
			end
		end
	end)
end

local function ResetHiddenRows(db)
	for _, row in ipairs(HIDDEN) do
		if row.kind == "range" then db["set" .. row.key] = false else db[row.key] = "game" end
	end
end

-- This part's place in the module's life cycle (Modules/QoL.lua, AddPart).
-- "Restore game settings" (Modules/QoL/Tweaks.lua) puts every row back to
-- "Game setting" after the shortcuts gave their values back.
M:AddPart("CVars", {
	enable = function(self) self:ApplyHiddenSettings() end,
	disable = function(self)
		self:ApplyHiddenSettings()
		if win then win:Close() end
	end,
	profile = function(self) self:ApplyHiddenSettings() end,
	restore = function(self)
		ResetHiddenRows(self.db)
		self:ApplyHiddenSettings()
	end,
})

local function Requires(cvar)
	return function() return Exists(cvar) end
end

local function Disabled(row)
	return function()
		local owner = HeldElsewhere(row.cvar)
		if owner then return L["Controlled by %s"]:format(OwnerTitle(owner)) end
		if InCombatLockdown() then return L["Game settings change out of combat."] end
		return false
	end
end

local function NowText(row)
	local value = CurrentValue(row.cvar)
	if row.kind == "switch" then
		if value == nil then return "?" end
		return OnOff(value) and L["on"] or L["off"]
	end
	if row.kind == "choice" and row.values and value and row.values[value] then return L[row.values[value]] end
	local number = tonumber(value)
	if number then return (("%.2f"):format(number):gsub("0+$", ""):gsub("%.$", "")) end
	return tostring(value or "?")
end

local function RowOptions(row)
	local desc = row.desc
	if row.kind == "range" then
		return {
			{ type = "toggle", key = "set" .. row.key, label = row.ownLabel, requires = Requires(row.cvar), disabled = Disabled(row),
				desc = function() return L[desc] .. " " .. L["Off keeps the game's value (now %s)."]:format(NowText(row)) end },
			{ type = "range", key = row.key, label = row.label, unit = row.unit, percent = row.percent, min = row.min, max = row.max, step = row.step,
				requires = Requires(row.cvar), dependsOn = "set" .. row.key, disabled = Disabled(row),
				desc = L["Only written while the box above is checked."] },
		}
	end
	local values
	if row.kind == "switch" then
		values = function() return { game = L["Game setting (now %s)"]:format(NowText(row)), on = L["On"], off = L["Off"] } end
	else
		values = function()
			local list = { game = L["Game setting (now %s)"]:format(NowText(row)) }
			for value, label in pairs(row.values) do list[value] = L[label] end
			return list
		end
	end
	return { { type = "select", key = row.key, label = row.label, desc = desc, values = values,
		requires = Requires(row.cvar), disabled = Disabled(row) } }
end

local GROUPS = {
	{ key = "fct", header = E.Key("Hidden settings: floating combat text"), -- no-L (option rows, Config.lua translates them)
		note = E.Key("Extras the game's menu does not show. The Combat Text page sets the text itself; a row it controls is grayed here."), -- no-L (option rows, Config.lua translates them)
		link = { label = "Open Combat Text", module = "CombatText", desc = "Opens the Combat Text page, where EldoUI's and Blizzard's combat text are set up." } },
	{ key = "chat", header = E.Key("Hidden settings: chat"), -- no-L (option rows, Config.lua translates them)
		note = E.Key("Chat bubbles, class colors and timestamps are on the Chat and Chat Bubbles pages."), -- no-L (option rows, Config.lua translates them)
		link = { label = "Open Chat", module = "Chat", desc = "Opens the Chat page, with timestamps and class colors." } },
	{ key = "camera", header = E.Key("Hidden settings: camera"), -- no-L (option rows, Config.lua translates them)
		note = E.Key("Camera speeds and behavior the game's menu does not show. The max camera distance is in Camera and screenshots above.") }, -- no-L (option rows, Config.lua translates them)
	{ key = "graphics", optional = true, header = E.Key("Hidden settings: graphics"), -- no-L (option rows, Config.lua translates them)
		note = E.Key("Picture settings the game's menu does not show. A row only appears when your game has that setting.") }, -- no-L (option rows, Config.lua translates them)
}

local rows = {
	{ type = "header", label = "All game settings" },
	{ type = "description", label = "Every setting you could type with /console: search, change and restore them in one window. Protected settings are not listed." },
	{ type = "execute", label = "Open the settings browser", desc = "Opens the window with every game setting, its value, default and help (also /eui cvars).",
		func = function() M:ShowCVarBrowser() end },
	{ type = "toggle", key = "cvarOnlyChanged", label = "Only changed settings", desc = "The browser lists only settings that differ from the game's default or that EldoUI set." },
	{ type = "toggle", key = "cvarAdvanced", label = "Advanced settings", desc = "The browser also lists debug and GM settings and the ones the game locks or shows read-only (those stay read-only)." },
	{ type = "execute", label = "Restore browser changes",
		desc = "Puts back your own value of every setting you changed in the browser. Rows on this page and other EldoUI pages keep theirs.",
		func = function()
			local count = M:BrowserCVarCount()
			local ok, why = M:RestoreAllBrowserCVars()
			if E.ConfigNotice then
				if ok then E:ConfigNotice(E:Plural(count, "%d setting is back to your own value.", "%d settings are back to your own values."):format(count))
				else E:ConfigNotice(why, true) end
			end
		end },
}
-- An optional group whose settings this client lacks is left out, header
-- and all.
local function GroupMissing(key)
	return function()
		for _, row in ipairs(HIDDEN) do
			if row.group == key and Exists(row.cvar) then return false end
		end
		return true
	end
end

for _, group in ipairs(GROUPS) do
	local missing = group.optional and GroupMissing(group.key) or nil
	rows[#rows + 1] = { type = "header", label = group.header, hidden = missing }
	rows[#rows + 1] = { type = "description", label = group.note, hidden = missing }
	if group.link then
		local link = group.link
		rows[#rows + 1] = { type = "execute", label = link.label, desc = link.desc,
			hidden = function() return not E.modules[link.module] end,
			func = function() E:ToggleConfig("module:" .. link.module) end }
	end
	for _, row in ipairs(HIDDEN) do
		if row.group == group.key then
			for _, option in ipairs(RowOptions(row)) do rows[#rows + 1] = option end
		end
	end
end
M:AddOptions(E.Key("Sound and misc"), rows)
