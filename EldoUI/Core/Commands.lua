-- EldoUI slash commands: everything starts with /eui (or /eldoui).
--
--   /eui                      open the options
--   /eui help [command]       the full command list in a window, or one command's usage
--   /eui <module> on|off      switch any module on or off ("toggle" flips it);
--                             /eui <module> alone opens its settings page
--   /eui search <words>       the config window with every matching setting
--   /eui whatsnew             what changed in this version
--   /eui thanks               the people who made EldoUI possible
--   /eui <command> ...        the commands below
--
-- Names ignore case, spaces and symbols, and a unique start is enough:
-- "/eui na off" switches Nameplates off. Modules add commands with
-- E:AddCommand(name, usage, fn, group, fill); the help list is built from
-- them. The usage text is translated when shown (L[usage]), so pass it in
-- English. A usage with a %s takes fill: an English text, translated when
-- shown too, or a function that returns the text.
local _, E = ...
local L = E.L

local Key = E.Key
local commands = {}
local helpList = {} -- { name, usage, group }
local helpByName = {} -- name -> its helpList entry
local GROUPS = { "General", "Layout & frames", "Keys and spells", "Profiles & sharing", "Tools", "Troubleshooting" }
-- The group names are keys modules pass to E:AddCommand; the help shows
-- these titles, which spell out "and" (DESIGN.md §4).
-- Token colors for the help and the module list.
local function Tinted(kind, text) return E:TokenHex(E.tokens.text[kind]) .. tostring(text) .. "|r" end
local GROUP_TITLES = { ["Layout & frames"] = "Layout and frames", ["Profiles & sharing"] = "Profiles and sharing" }
-- Shown translated: L["General"], L["Layout & frames"], L["Keys and spells"],
-- L["Profiles & sharing"], L["Tools"], L["Troubleshooting"]

-- Usage texts with a list that grows at runtime: the list fills the %s.
local USAGE_FILL = {
	capture = function() return table.concat(E.addonSetupOrder, ", ") end,
}
local function Usage(entry)
	local text = L[entry.usage]
	local fill = entry.fill or USAGE_FILL[entry.name]
	if type(fill) == "function" then fill = fill() end
	if fill then text = text:format(L[fill]) end
	-- Syntax first, then two spaces and the text: a usage without syntax
	-- starts with the text.
	return (text:gsub("^%s+", ""))
end

-- Other words players type for a command.
local COMMAND_WORDS = { keybind = "kb", keybinds = "kb", bind = "kb", binds = "kb" }

local function Add(name, usage, fn, group, fill)
	if not commands[name] then
		local entry = { name = name, usage = usage, group = group or "Tools", fill = fill }
		table.insert(helpList, entry)
		helpByName[name] = entry
	end
	commands[name] = fn
end

function E:AddCommand(name, usage, fn, group, fill)
	Add(name, usage, fn, group, fill)
end

local function Accent()
	local r, g, b = unpack(E.media.accentText)
	return ("|cff%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- true, false, "toggle" or nil from a word.
local function Switch(word)
	word = (word or ""):lower()
	if word == "on" or word == "enable" or word == "1" then return true end
	if word == "off" or word == "disable" or word == "0" then return false end
	if word == "toggle" then return "toggle" end
end

local function Simplify(text)
	return (text or ""):lower():gsub("[^%w]", "")
end

-- The words that switch a module when they end the line, as on, off or
-- toggle. Numbers stay with commands ("/eui scale 1").
local SWITCH_WORDS = { on = "on", off = "off", toggle = "toggle", enable = "on", disable = "off" }

-- True when a command's own syntax (the usage before its description,
-- "[on | off | toggle]") takes the switch word itself (Streamer Mode,
-- Alts): then "/eui <command> off" stays the command's.
local function CommandTakesSwitch(name, word)
	local entry = helpByName[name]
	local usage = entry and tostring(entry.usage or "") or ""
	local syntax = usage:match("^(.-)%s%s") or usage:match("^([%[<].-[%]>])") or ""
	return syntax:lower():find("%f[%a]" .. word .. "%f[%A]") ~= nil
end

-- The one "module is off" line, for every module: where the switch really
-- is and the command that turns it on. reason (optional) is one sentence
-- on what needs the module ("Importing a wishlist needs it."). A module
-- another addon holds back names that addon instead. In chat the command
-- is a link: a click puts it in the chat box, and the player's Enter runs
-- it (the config window opens only from /eui itself). Without the link the
-- text has no colors, as option rows want.
local function ModuleOffText(name, reason, link)
	local module = E.modules and E.modules[name]
	local title = module and L[module.title] or name
	local _, conflict
	if module then _, conflict = E:GetModuleConflict(module) end
	local line = conflict and L["%s stays off while %s is loaded."]:format(title, conflict) or L["%s is off."]:format(title)
	if type(reason) == "string" and reason ~= "" then line = line .. " " .. reason end
	if conflict then return line end
	local command = ("enable %s"):format(name:lower())
	if not link then return line .. " " .. L["Turn it on on the Modules page (%s), or type %s."]:format("/eui", "/eui " .. command) end
	return line .. " " .. L["Turn it on on the Modules page (%s), or type %s."]:format(E:Highlight("/eui"), E:ChatLink("eui", command, "/eui " .. command))
end

-- For chat lines.
function E:ModuleOffHint(name, reason)
	return ModuleOffText(name, reason, true)
end

-- The same text without the link or colors, for tooltips and option rows.
function E:ModuleOffNote(name, reason)
	return ModuleOffText(name, reason, false)
end

-- The link's click: only "/eui enable <module>" goes into the chat box.
local function OpenSlashLink(data)
	if not (data or ""):match("^enable [%w_]+$") then return end
	local text = "/eui " .. data -- no-L: a slash command
	local util = rawget(_G, "ChatFrameUtil")
	local open = type(util) == "table" and util.OpenChat or rawget(_G, "ChatFrame_OpenChat")
	if type(open) == "function" then open(text) else E:Print(E:Highlight(text)) end
end

-- The chat link helper loads after this file: hook the link in at login.
local slashLinkOwner = {}
E:RegisterEvent("PLAYER_LOGIN", function()
	E:RegisterChatLink("eui", OpenSlashLink)
	E:UnregisterEvent("PLAYER_LOGIN", slashLinkOwner)
end, slashLinkOwner, "engines")

-- The module a name means exactly. A module's own name wins over another
-- module's title ("messages" is the Messages module even though "Messages"
-- is an earlier title of Notifications), then titles, then `aliases`.
local function ExactModule(word)
	local wanted = Simplify(word)
	if wanted == "" then return nil end
	for name, module in E:IterateModules() do
		if Simplify(name) == wanted then return module end
	end
	for _, module in E:IterateModules() do
		if Simplify(module.title) == wanted then return module end
	end
	for _, module in E:IterateModules() do
		for _, alias in ipairs(module.aliases or {}) do
			if Simplify(alias) == wanted then return module end
		end
	end
end

-- A module by its name or title, ignoring case, spaces and symbols, or by a
-- unique start: "groupframes", "partyandraid", "party" all find GroupFrames.
function E:FindModule(word)
	local wanted = Simplify(word)
	if wanted == "" then return nil end
	local exact = ExactModule(wanted)
	if exact then return exact end
	local partial, count = nil, 0
	for name, module in self:IterateModules() do
		local a, b = Simplify(name), Simplify(module.title)
		if a:sub(1, #wanted) == wanted or b:sub(1, #wanted) == wanted then
			partial, count = module, count + 1
		end
	end
	if count == 1 then return partial end
end

-- A command by full name, or by a unique start.
local function FindCommand(word)
	if commands[word] then return word end
	local found, count = nil, 0
	for name in pairs(commands) do
		if name:sub(1, #word) == word then found, count = name, count + 1 end
	end
	if count == 1 then return found end
end

-- Letters to change, add or drop to turn one word into another.
local function Distance(a, b)
	if a == b then return 0 end
	local previous = {}
	for j = 0, #b do previous[j] = j end
	for i = 1, #a do
		local current = { [0] = i }
		local ca = a:byte(i)
		for j = 1, #b do
			local cost = ca == b:byte(j) and 0 or 1
			current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
		end
		previous = current
	end
	return previous[#b]
end

-- Closest command or module for "did you mean": commands, module
-- names, titles and aliases, ranked by how few letters differ. Without a
-- close one, a candidate the word is the start of (a word cut short).
local function Suggest(word)
	word = Simplify(word)
	if word == "" then return nil end
	local best, bestDistance
	local cuts, cut, cutCount = {}, nil, 0
	local function Try(candidate, answer)
		candidate = Simplify(candidate)
		if candidate == "" then return end
		local distance = Distance(word, candidate)
		if not bestDistance or distance < bestDistance then best, bestDistance = answer, distance end
		if #word >= 3 and candidate:sub(1, #word) == word and not cuts[answer] then
			cuts[answer] = true
			cut, cutCount = answer, cutCount + 1
		end
	end
	local names = {}
	for name in pairs(commands) do names[#names + 1] = name end
	table.sort(names)
	for _, name in ipairs(names) do Try(name, name) end
	for name, module in E:IterateModules() do
		local answer = name:lower()
		Try(name, answer)
		Try(module.title, answer)
		for _, alias in ipairs(module.aliases or {}) do Try(alias, answer) end
	end
	if best and bestDistance <= math.max(2, math.floor(#word / 3)) then return best end
	if cutCount == 1 then return cut end
end

---------------------------------------------------------------------------
-- Help window
---------------------------------------------------------------------------
local help

-- Usage texts are plain words: a bar between choices is doubled so the
-- window shows it instead of reading it as a text code.
local function Plain(text)
	return (tostring(text):gsub("|", "||"))
end

-- Does a help row match the filter? The command word, its usage and its
-- group title all count, in the language shown.
local function Matches(filter, ...)
	if filter == "" then return true end
	for i = 1, select("#", ...) do
		local text = select(i, ...)
		if text and tostring(text):lower():find(filter, 1, true) then return true end
	end
	return false
end

local function BuildHelpText(filter)
	filter = strtrim(filter or ""):lower()
	local accent = Accent()
	local lines = {}
	for _, group in ipairs(GROUPS) do
		local first = true
		local title = L[GROUP_TITLES[group] or group]
		for _, entry in ipairs(helpList) do
			local usage = entry.group == group and Usage(entry)
			if usage and Matches(filter, entry.name, usage, title) then
				if first then
					table.insert(lines, (#lines > 0 and "\n" or "") .. "|cffffffff" .. E:CaptionText(title) .. "|r")
					first = false
				end
				table.insert(lines, ("%s/eui %s|r  %s"):format(accent, entry.name, Tinted("secondary", Plain(usage))))
			end
		end
	end
	local names = {}
	for name in E:IterateModules() do
		if Matches(filter, name, L[E.modules[name].title], L["Modules"]) then table.insert(names, name) end
	end
	table.sort(names)
	if #names > 0 then
		table.insert(lines, (#lines > 0 and "\n" or "") .. "|cffffffff" .. E:CaptionText(L["Modules"]) .. "|r  "
			.. Tinted("secondary", Plain(L["/eui <module> on | off | toggle, or /eui <module> for its settings"])))
	end
	for _, name in ipairs(names) do
		local module = E.modules[name]
		local _, conflict = E:GetModuleConflict(module)
		local state = conflict and Tinted("warn", L["off while %s is loaded"]:format(conflict))
			or (module:IsEnabled() and Tinted("good", L["on"]) or Tinted("bad", L["off"]))
		table.insert(lines, ("%s/eui %s on||off|r  %s  %s"):format(accent, name:lower(), Plain(L[module.title]), state))
	end
	if #lines == 0 then return Tinted("secondary", L["No command matches the filter."]) end
	return table.concat(lines, "\n")
end

-- The command list on the shared tool window shell: header-font
-- title, accent line, a scroll bar and a grip to make it taller.
function E:ShowHelp()
	local Kit = E.UIKit
	if not help then
		help = Kit.CreateToolWindow("EldoUIHelp", { title = L["EldoUI commands"], width = 640, height = 500,
			strata = "DIALOG", resizable = { minWidth = 480, minHeight = 300 } })
		local function Refresh()
			help.text:SetText(BuildHelpText(help.filter:GetText()))
			help.area:Update()
			help.child:SetHeight(help.text:GetStringHeight() + 8)
			help.area:ScrollToTop()
		end
		help.hint = Kit.Text(help.content, E.tokens.size.small, "LEFT", "secondary")
		help.hint:SetPoint("TOPLEFT", 4, -2)
		help.hint:SetPoint("TOPRIGHT", -4, -2)
		help.hint:SetText(L["Type these in chat. Words in <> are yours to fill in. /eui help <command> shows one."])
		-- A filter over the command words, their usage and the group titles.
		help.filter = Kit.Input(help.content, { width = 220, hint = L["Filter commands"], onChange = Refresh, onEnter = Refresh })
		help.filter:SetPoint("TOPLEFT", help.hint, "BOTTOMLEFT", 0, -6)
		Kit.SearchEscape(help.filter)
		help.filter:HookScript("OnEscapePressed", Refresh)
		help.area = Kit.ScrollArea(help.content)
		help.area:SetPoint("TOP", help.filter, "BOTTOM", 0, -6)
		help.area:SetPoint("LEFT", 4, 0)
		help.area:SetPoint("BOTTOMRIGHT", -4, 12)
		help.child = help.area.child
		help.text = Kit.Text(help.child, E.tokens.size.body, "LEFT")
		help.text:SetPoint("TOPLEFT")
		help.text:SetPoint("TOPRIGHT")
		help.text:SetWordWrap(true)
		help.text:SetSpacing(4)
		help.area:HookScript("OnSizeChanged", function()
			help.child:SetHeight(help.text:GetStringHeight() + 8)
		end)
		-- The command words are in the accent: rebuild on a theme change.
		E:RegisterThemed(help, function(window) if window:IsShown() then window.text:SetText(BuildHelpText(window.filter:GetText())) end end)
	end
	help.filter:SetText("")
	help.text:SetText(BuildHelpText())
	help:Show()
	help:Raise()
	help.area:Update()
	help.child:SetHeight(help.text:GetStringHeight() + 8)
	help.area:ScrollToTop()
end

Add("help", Key("[command]  this list, or how to use one command"), function(arg)
	arg = (arg or ""):lower()
	if arg == "" then
		E:ShowHelp()
		return
	end
	local name = FindCommand(arg)
	for _, entry in ipairs(helpList) do
		if entry.name == name then
			E:Print(("%s/eui %s|r  %s"):format(Accent(), entry.name, Usage(entry))) -- no-L: command syntax only
			return
		end
	end
	local module = E:FindModule(arg)
	if module then
		E:Print(("%s/eui %s on|r | off | toggle  %s"):format(Accent(), module.name:lower(), -- no-L: command syntax
			L["%s. Without a word it opens the settings."]:format(L[module.title])))
		return
	end
	E:Print(L["No command %q. Type %s for the full list."]:format(arg, E:Highlight("/eui help")))
end, "General")

---------------------------------------------------------------------------
-- General
---------------------------------------------------------------------------
Add("options", Key("open the options (same as plain /eui)"), function()
	E:OpenOptions()
end, "General")

Add("search", Key("<words>  open the options with every setting that matches"), function(arg)
	E:SearchConfig(arg)
end, "General")

Add("whatsnew", Key("what changed in this EldoUI version"), function()
	E:ToggleConfig("whatsnew")
end, "General")

Add("thanks", Key("the people who made EldoUI possible"), function()
	E:ToggleConfig("thanks")
end, "General")

Add("modules", Key("list modules and whether they are on"), function()
	E:ShowHelp()
	-- The module list ends the help: scroll to the bottom.
	if help then
		help.area:Update()
		help.area:SetScroll(help.area:Range())
	end
end, "General")

-- Switch a module on or off: the same checks and reload question as
-- /eui <module> on|off (conflicts, Blizzard's version after a reload).
-- The one on/off line: "<name> on." or "<name> off.", the name in the
-- accent, on and off in the good and bad colors. Modules and commands that
-- switch something print through it, so every switch reads the same.
function E:SwitchText(name, enabled)
	return ("%s%s|r %s."):format(Accent(), tostring(name), enabled and Tinted("good", L["on"]) or Tinted("bad", L["off"]))
end

function E:PrintSwitch(name, enabled)
	self:Print(self:SwitchText(name, enabled))
end

local function SetModule(module, enabled)
	local _, conflict = E:GetModuleConflict(module)
	if enabled and conflict then
		E:Print(L["%s is handled by %s. Type %s to choose."]:format(L[module.title], conflict, E:Highlight("/eui addons")))
		return
	end
	E:SetModuleEnabled(module.name, enabled)
	E:PrintSwitch(L[module.title], enabled)
	-- Asks only when switching this module off needs a reload.
	if not enabled then E:ShowReloadPrompt(module) end
	E:RefreshConfig()
end

-- The same for a module's own command ("/eui training on"): one message
-- and the reload question for every module.
function E:SetModuleFromCommand(name, enabled)
	local module = self.modules[name]
	if module then SetModule(module, enabled and true or false) end
end

local function Toggle(arg, enabled)
	local module = E:FindModule(arg)
	if not arg or arg == "" then
		E:Print(L["Give a module name. See %s."]:format(E:Highlight("/eui help")))
	elseif module then
		SetModule(module, enabled)
	else
		E:Print(L["No module named %q."]:format(arg))
	end
end
Add("enable", Key("<module>  same as /eui <module> on"), function(arg) Toggle(arg, true) end, "General")
Add("disable", Key("<module>  same as /eui <module> off"), function(arg) Toggle(arg, false) end, "General")

Add("install", Key("[<step> | undo]  run the EldoUI setup again, open one step (layout, role, modules ...) or undo the last setup"), function(arg)
	E:ShowInstaller(arg)
end, "General")

Add("attach", Key("[<profile>]  put this character on a profile you already set up, as it is, with its own chat tabs, game settings and class spells"), function(arg)
	arg = strtrim(arg or "")
	local Alt = E.InstallerAlt
	if not (Alt and E.Installer and E.Installer.ShowAlt) then return end
	if arg ~= "" then
		-- The name as the profile list has it, in any case.
		local found
		for _, name in ipairs(E:GetProfileList()) do
			if name == arg or (not found and name:lower() == arg:lower()) then found = name end
		end
		if not found then
			E:Print(L["There is no profile %q. /eui profile list shows them."]:format(arg))
			return
		end
		if not Alt.IsSetUp(found) then
			E:Print(L["Profile %s is not set up yet. Run %s on a character that uses it first."]:format(E:Highlight(found), E:Highlight("/eui install")))
			return
		end
		arg = found
	end
	E.Installer.ShowAlt(arg)
end, "General")

Add("version", Key("show the EldoUI version"), function()
	E:Print(L["Version %s, game version %s (Interface %s)."]:format(E.version, (GetBuildInfo()), select(4, GetBuildInfo())))
end, "General")

---------------------------------------------------------------------------
-- Layout & frames
---------------------------------------------------------------------------
Add("move", Key("on | off  drag frames around (no word flips it)"), function(arg)
	local switch = Switch(arg)
	if switch == nil or switch == "toggle" then E:ToggleMoveMode() else E:ToggleMoveMode(switch) end
end, "Layout & frames")

-- Slash-command words for a key set, read before the set ids and the saved
-- choices' older names: "classic" is the recommended Classic movement.
local KB_WORDS = { classic = "movement" }
Add("kb", Key("[movement | strafe | numbers | mouse | esdf | restore]  keybind mode, or the preview of a key set (its id or its name)"), function(arg)
	arg = strtrim(arg or ""):lower()
	arg = KB_WORDS[arg] or arg
	if arg == "" then
		E:ToggleKeybindMode()
	elseif arg == "restore" then
		E:RestoreKeybinds()
	elseif E:KeybindPresetKey(arg) then
		E:OpenKeybindPreview(arg)
	else
		local names = {}
		for _, id in ipairs(E.keybindPresetOrder) do names[#names + 1] = E:Highlight("/eui kb " .. id) end
		E:Print(L["No key set %q. Use %s, %s, or %s alone for keybind mode."]:format(arg,
			table.concat(names, ", "), E:Highlight("/eui kb restore"), E:Highlight("/eui kb")))
	end
end, "Keys and spells")

-- The game keys card in the chat; "check" compares your keys with your
-- key set, "keyboard" opens Check my keyboard, "hidden" shows or sets how
-- buttons out of sight are kept (E:HiddenButtonsMode).
local HIDDEN_MODES = { hide = Key("hidden, the normal way"), invisible = Key("invisible, with no mouse clicks") }
Add("keys", Key("[check | keyboard | hidden]  where bags, map and the other game keys are; check your keys or your keyboard"), function(arg)
	arg = strtrim(arg or ""):lower()
	local hidden, mode = arg:match("^(hidden)%s*(%a*)$")
	if hidden and E.HiddenButtonsMode then
		if mode ~= "" and E:SetHiddenButtonsMode(mode) then
			E:Print(L["Buttons out of sight are now %s. Their keys work either way."]:format(L[HIDDEN_MODES[mode]]))
		else
			E:Print(L["Buttons out of sight are %s. %s or %s switches it."]:format(L[HIDDEN_MODES[E:HiddenButtonsMode()]],
				E:Highlight("/eui keys hidden hide"), E:Highlight("/eui keys hidden invisible")))
		end
	elseif arg == "check" then
		if E.KeymapCheck then
			E:KeymapCheck("manual")
		else
			E:Print(L["There is nothing to check yet: choose a key set first."])
		end
	elseif arg == "keyboard" then
		E:OpenKeyboardCheck()
	else
		E:PrintGameKeys()
	end
end, "Keys and spells")

-- The same question and the same setup change as the Layouts page
-- (E:ConfirmApplyLayout). "undo" puts back the last setup change.
Add("layout", Key("<name> | undo  apply a layout preset, or undo the last setup change (no name lists them)"), function(arg)
	arg = strtrim(arg or "")
	if arg:lower() == "undo" then
		E:UndoSetup()
		return
	end
	if arg ~= "" then
		local key = E:ResolveLayoutKey(arg)
		if not key then
			for _, name in ipairs(E:AllLayoutKeys()) do
				if Simplify(arg) == Simplify(name) or Simplify(arg) == Simplify(E:LayoutTitle(name)) then key = name break end
			end
		end
		if not key then
			for alias in pairs(E.layoutAliases) do
				if Simplify(arg) == Simplify(alias) then key = E:ResolveLayoutKey(alias) break end
			end
		end
		-- A layout family's name picks its current version, as the picker does.
		if key and E.FamilyLayoutKey then key = E:FamilyLayoutKey(key) or key end
		if key then
			E:ConfirmApplyLayout(key, { source = "command" })
			return
		end
		E:Print(L["No layout named %q."]:format(arg))
	end
	E:Print(L["Layouts:"])
	for _, key in ipairs(E:AllLayoutKeys()) do
		local current = key == E.db.general.layout and " " .. Tinted("good", L["(current)"]) or ""
		print(("  " .. E:TextHex("accent") .. "%s|r  %s%s"):format(key, L[E.layouts[key].desc or ""], current))
	end
end, "Layout & frames")

Add("resetlayout", Key("put every frame back to its layout position"), function()
	E:ConfirmResetMovers()
end, "Layout & frames")

Add("scale", Key("auto | pixel | <number>  set the UI scale (auto = the 1440p canvas EldoUI is made for)"), function(arg)
	arg = strtrim(arg or ""):lower()
	local value = tonumber(arg)
	if arg == "auto" or arg == "pixel" then
		E.db.general.uiScale = arg
	elseif value and value >= 0.4 and value <= 1.2 then
		E.db.general.uiScale = value
	else
		E:Print(L["UI scale is %s (%.4f). Use %s (1440p), %s or a number from 0.4 to 1.2."]:format(tostring(E.db.general.uiScale), E:GetTargetScale(), E:Highlight("/eui scale auto"), E:Highlight("/eui scale pixel")))
		return
	end
	E:ApplyScale()
	E:Print(L["UI scale set to %.4f."]:format(E:GetTargetScale()))
	-- How the new scale suits the layouts (recommended, supported or not).
	local _, advice = E:ScaleAdvice(E.db.general.uiScale)
	if advice then E:Print(advice) end
end, "Layout & frames")

---------------------------------------------------------------------------
-- Profiles & sharing
---------------------------------------------------------------------------
-- The same Accept / Cancel question the Profiles page asks, on the shared
-- dialog shell (E:ShowConfirm).
local function ConfirmSlash(text, func)
	E:ShowConfirm({ title = L["Profiles"], text = text, accept = ACCEPT, onAccept = func })
end

-- A copy or a reset replaces the profile's settings and then switches to
-- it again: in combat both wait for the end of the fight, like a plain
-- switch (E:SetProfile).
local function OutOfCombat(fn)
	if InCombatLockdown() then E:Print(L["The profile changes after combat."]) end
	E:RunOutOfCombat(fn)
end


Add("profile", Key("list | use <name> | new <name> | copy <from> | reset | delete <name>"), function(arg)
	local action, name = (arg or ""):match("^(%S*)%s*(.-)$")
	action = action:lower()
	name = strtrim(name or "")
	if action == "" or action == "list" then
		E:Print(L["Profiles:"])
		for _, profile in ipairs(E:GetProfileList()) do
			print(("  %s%s"):format(profile, profile == E.profileName and " " .. Tinted("good", L["(current)"]) or ""))
		end
	elseif action == "use" and name ~= "" then
		-- Only existing profiles: a typo must not switch to a new, empty one.
		local profile = E:FindProfileName(name)
		if not profile then
			E:Print(L["No profile named %q. %s shows them; %s makes a new one."]:format(name, E:Highlight("/eui profile list"), E:Highlight(("/eui profile new %s"):format(name))))
		elseif profile == E.profileName then
			E:Print(L["You already use %s."]:format(profile))
		else
			E:SetProfile(profile)
		end
	elseif action == "new" and name ~= "" then
		local checked, reason = E:CheckProfileName(name)
		if not checked then
			E:Print(reason)
		else
			E:CreateProfile(checked, function(existing)
				E:Print(L["A profile named %s already exists. Use %s."]:format(existing, E:Highlight(("/eui profile use %s"):format(existing))))
			end)
		end
	elseif action == "copy" and name ~= "" then
		local profile = E:FindProfileName(name)
		if not profile then
			E:Print(L["No profile named %q."]:format(name))
		elseif profile == E.profileName then
			E:Print(L["That is the profile you use now; pick another one to copy from."])
		else
			local current = E.profileName
			ConfirmSlash(E:ProfileConfirmText(L["Replace every setting of %s with a copy of %s?"]:format(E:Highlight(current), E:Highlight(profile)), current, "copy"), function()
				OutOfCombat(function()
					if E.profileName ~= current then return end
					E:ChangeProfileWithUndo(current, "copy", function()
						local ok = E:CopyProfile(profile)
						if ok then E:Print(L["Copied %s into %s."]:format(profile, current)) end
						return ok
					end)
				end)
			end)
		end
	elseif action == "reset" then
		local current = E.profileName
		ConfirmSlash(E:ProfileConfirmText(L["Reset the profile %s to defaults?"]:format(E:Highlight(current)), current, "reset"), function()
			if E.profileName ~= current then return end -- switched meanwhile
			OutOfCombat(function()
				if E.profileName ~= current then return end
				E:ChangeProfileWithUndo(current, "reset", function()
					local ok = E:ResetProfile()
					if ok then E:Print(L["Profile %s reset to defaults."]:format(current)) end
					return ok
				end)
			end)
		end)
	elseif action == "delete" and name ~= "" then
		local profile = E:FindProfileName(name)
		if not profile or profile == E.profileName then
			E:Print(L["Can't delete that profile (it doesn't exist, or it's the one you're using)."])
		else
			ConfirmSlash(E:ProfileConfirmText(L["Delete the profile %s?"]:format(E:Highlight(profile)), profile, "delete"), function()
				E:ChangeProfileWithUndo(profile, "delete", function()
					local ok = E:DeleteProfile(profile)
					if ok then E:Print(L["Deleted profile %s."]:format(profile)) end
					return ok
				end)
			end)
		end
	else
		E:Print(L["Usage: /eui profile list | use <name> | new <name> | copy <from> | reset | delete <name>"])
	end
end, "Profiles & sharing")

Add("capture", Key("<addon>  save another addon's setup into EldoUI (%s)"), function(arg)
	if arg == "" then
		E:Print(L["Addon setups: %s"]:format(table.concat(E.addonSetupOrder, ", ")))
		return
	end
	for _, name in ipairs(E.addonSetupOrder) do
		if name:lower() == arg:lower() then
			E:CaptureAddon(name)
			return
		end
	end
	E:CaptureAddon(arg)
end, "Profiles & sharing")

-- "setup" is the EldoUI setup everywhere else, so it opens it too.
Add("setup", Key("[<step>]  same as /eui install: run the EldoUI setup again"), function(arg)
	E:ShowInstaller(arg)
end, "General")

Add("addonsetup", Key("set up the supported addons from EldoUI's profiles (asks first)"), function()
	E:ConfirmAddonSetups()
end, "Profiles & sharing")

-- Saved data (Core/SavedData.lua): the copies kept before an update and
-- the values set aside.
local function DataHelp()
	E:Print(L["Usage: /eui data [list | restore <part> [<name>] | follow <part> [<name>]]"])
	for _, line in ipairs({
		{ "/eui data", L["Opens the Saved data page and sums up what it holds."] },
		{ "/eui data list", L["Lists the copies kept before an update and the parts held as you put them back, each with its command."] },
		{ "/eui data restore <part> [<name>]", L["Puts a copy back after you confirm, out of combat. Without a name, the newest copy of that part is used. Example: /eui data restore profile Default"] },
		{ "/eui data follow <part> [<name>]", L["Lets a part you restored follow updates again."] },
	}) do
		print(("  %s  %s"):format(E:Highlight(line[1]), line[2]))
	end
	print("  " .. L["Nothing here deletes your data. Restoring keeps what it replaces."])
end
Add("data", Key("[list | restore <part> [<name>] | follow <part> [<name>]]  your saved data's safety net: open the Saved data page, list the copies kept before updates, put one back, or let a restored part follow updates again"), function(arg)
	local SD = E.SavedData
	if not SD then return end
	local action, kind, name = (arg or ""):match("^(%S*)%s*(%S*)%s*(.-)$")
	action = action:lower()
	if action == "" then
		SD.PrintSummary()
		E:ToggleConfig("saveddata", true)
	elseif action == "list" then
		SD.PrintBackups()
	elseif action == "restore" and kind ~= "" then
		local entry = SD.FindBackup(kind, name)
		if not entry then
			E:Print(L["No copy of that. Type %s to see the copies."]:format(E:Highlight("/eui data list")))
		else
			E:ShowConfirm({ title = L["Saved data"], text = SD.ConfirmText(entry), accept = L["Restore"], onAccept = function()
				if InCombatLockdown() then E:Print(L["Backups can be put back out of combat only."]) return end
				SD.Restore(entry)
			end })
		end
	elseif action == "follow" and kind ~= "" then
		local entry = SD.FindHold(kind, name)
		if not entry then
			E:Print(L["Nothing like that is held. The Saved data page lists what is held."])
		else
			SD.Release(entry)
		end
	else
		DataHelp()
	end
end, "Profiles & sharing")

---------------------------------------------------------------------------
-- Tools
---------------------------------------------------------------------------
Add("debug", Key("on | off  debug messages in chat"), function(arg)
	local switch = Switch(arg)
	if switch == nil or switch == "toggle" then E.debug = not E.debug else E.debug = switch end
	E:Print(E.debug and L["Debug on."] or L["Debug off."])
end, "Troubleshooting")

---------------------------------------------------------------------------
-- Dispatch
---------------------------------------------------------------------------
local function RunModule(module, arg, word)
	local switch = Switch(arg)
	if switch == "toggle" then switch = not module:IsEnabled() end
	if switch == nil then
		if arg ~= "" then
			E:Print(L["Use %s/eui %s on|r, %soff|r or %stoggle|r."]:format(Accent(), word, Accent(), Accent()))
		else
			E:ToggleConfig("module:" .. module.name)
		end
		return
	end
	SetModule(module, switch)
end

-- /eui with no command opens the full EldoUI config window.
function E:OpenOptions()
	self:ToggleConfig()
end

SLASH_ELDOUI1 = "/eldoui"
SLASH_ELDOUI2 = "/eui"
local function Dispatch(msg)
	msg = strtrim(msg or "")
	local cmd, arg = msg:match("^(%S*)%s*(.-)$")
	cmd = cmd:lower()
	-- Punctuation typed after a command ("/eui errors.") is not part of
	-- it; an exact command with that punctuation (a plugin's) still wins.
	if not commands[cmd] then
		local clean = cmd:gsub("[%.,;:!%?]+$", "")
		if clean ~= "" then cmd = clean end
	end
	if cmd == "" then
		E:OpenOptions()
		return
	end
	-- "/eui <module> on|off|toggle" with the module's name, title or alias
	-- in any number of words ("party and raid off"). An exact module
	-- name with a switch word wins over a command of the same word
	-- ("/eui chat off"), unless that command takes the word itself
	-- ("/eui streamer off" ends Streamer Mode). A name of more than one
	-- word alone opens the module's settings.
	local words = {}
	for word in msg:gmatch("%S+") do words[#words + 1] = word end
	local last = words[#words]:lower():gsub("[%.,;:!%?]+$", "")
	local switch = SWITCH_WORDS[last]
	local nameWords = switch and #words - 1 or #words
	if nameWords >= 1 and (switch or nameWords > 1) then
		local head = table.concat(words, " ", 1, nameWords)
		local module = ExactModule(head)
		if module then
			local command = commands[Simplify(head)] and Simplify(head)
			if switch and command and CommandTakesSwitch(command, switch) then return commands[command](switch) end
			if switch or not command then return RunModule(module, switch and last or "", module.name:lower()) end
		end
	end
	-- Exact command, then exact module, then a unique start of either.
	if commands[cmd] then return commands[cmd](arg) end
	if COMMAND_WORDS[cmd] and commands[COMMAND_WORDS[cmd]] then return commands[COMMAND_WORDS[cmd]](arg) end
	local module = E:FindModule(cmd)
	if module and Simplify(module.name) == Simplify(cmd) then return RunModule(module, arg, cmd) end
	local name = FindCommand(cmd)
	if name then return commands[name](arg) end
	if module then return RunModule(module, arg, cmd) end
	local guess = Suggest(cmd)
	if guess then
		E:Print(L["Unknown command %q. Did you mean %s/eui %s|r? %s lists everything."]:format(cmd, Accent(), guess, E:Highlight("/eui help")))
	else
		E:Print(L["Unknown command %q. Type %s for the full list."]:format(cmd, E:Highlight("/eui help")))
	end
end

-- /eui is the one way into the config window (E:RunFromSlash, Core/Config.lua).
SlashCmdList.ELDOUI = function(msg)
	E:RunFromSlash(Dispatch, msg)
end

-- Addon compartment (the minimap's addon drop-down): the TOC names these
-- globals, and the entry shows the troll icon from ## IconTexture.
-- The config window opens only from /eui (design decision), so a click
-- does what the EldoUI data text does: move mode, or keybind mode on a
-- right-click. The tooltip says how to open the options.
function EldoUI_OnAddonCompartmentClick(_, mouseButton)
	if mouseButton == "RightButton" then E:ToggleKeybindMode() else E:ToggleMoveMode() end
end

function EldoUI_OnAddonCompartmentEnter(_, button)
	local body, secondary = E.tokens.text.body, E.tokens.text.secondary
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:AddLine("EldoUI " .. E.version, E:TokenColor("accent")) -- no-L: addon name and version
	E:TooltipHint(GameTooltip, { L["Click"], L["move frames"] })
	E:TooltipHint(GameTooltip, { L["Right-click"], L["keybind mode"] })
	GameTooltip:AddLine(L["Type %s in chat or use the EldoUI button in the Game Menu to open the EldoUI options."]:format(E:Highlight("/eui")), secondary[1], secondary[2], secondary[3], true)
	GameTooltip:Show()
end

function EldoUI_OnAddonCompartmentLeave()
	GameTooltip:Hide()
end
