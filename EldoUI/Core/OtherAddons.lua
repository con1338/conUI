-- The Other addons page (Settings > Modules > Other addons), /eui addons
-- and the notice at login: which addons EldoUI found that do the same
-- job as part of EldoUI, who handles each job now, and the player's pick.
--
--   Use EldoUI's  a whole module (or a part both can't run on): the other
--                 addon is turned off for this character, after a reload.
--                 A part both can run on: EldoUI's part turns on now.
--   Keep <Addon>  the other addon keeps the job and EldoUI stands back.
--                 An addon EldoUI turned off this session is turned back
--                 on, still on this click.
--   Turn off <Addon>  only for addons whose every job is a part both can
--                 run on: the one way to turn such an addon off. Also
--                 under "Also done by EldoUI", for an addon that runs
--                 alongside and whose whole job EldoUI does.
--
-- Nothing here acts without the player's click. The registry and the
-- choices live in Core/AddonConflicts.lua.
local _, E = ...
local L = E.L

local page
local proxy = {}
local sessionNotes = {} -- the "picked EldoUI, but it is still on" notice, once per session
local loggedIn = false

local function Store()
	return E:GetGlobal("competitors")
end

local function Tinted(token, text) return E:TokenHex(E.tokens.text[token]) .. tostring(text) .. "|r" end

local COMMAND = "/eui addons"

---------------------------------------------------------------------------
-- Texts
---------------------------------------------------------------------------
-- One line per job: who handles it now.
function E:CompetitorStateText(row)
	local job = self:CompetitorJobText(row)
	if row.state == "standing" then
		return L["%s: handled by %s"]:format(job, row.title)
	elseif row.state == "eldoui" then
		return Tinted("good", L["%s: handled by EldoUI"]:format(job))
	elseif row.state == "fallback" then
		return Tinted("warn", L["%s: you picked EldoUI, but %s is still on, so EldoUI stands back"]:format(job, row.title))
	elseif row.state == "reload" then
		return Tinted("warn", L["%s: EldoUI's after a reload (%s is off for this character)"]:format(job, row.title))
	end
	return Tinted("secondary", L["%s: %s loads later; EldoUI stands back once it does"]:format(job, row.title))
end

-- The rows of each addon, in the order DetectedAddons sorts them.
local function ByAddon(rows)
	local list, index = {}, {}
	for _, row in ipairs(rows) do
		local group = index[row.addon]
		if not group then
			group = { addon = row.addon, title = row.title, rows = {} }
			index[row.addon] = group
			list[#list + 1] = group
		end
		group.rows[#group.rows + 1] = row
	end
	table.sort(list, function(a, b) return a.title < b.title end)
	return list
end

-- Does every job of this addon run next to EldoUI's (no frame owner)?
local function AllShared(group)
	for _, row in ipairs(group.rows) do
		if E:CompetitorNeedsDisable(row) then return false end
	end
	return true
end

---------------------------------------------------------------------------
-- Clicks
---------------------------------------------------------------------------
local Rebuild

local function AfterUse(result, title)
	if result == "reload" then
		E:ShowReloadPrompt(L["%s is disabled for this character after a reload. Reload now?"]:format(title))
	end
end

function E:ChooseEldoUI(addon, job, disable)
	local result = self:UseEldoUIFor(addon, job, disable)
	AfterUse(result, self:AddonTitle(addon))
	return result
end

function E:ChooseCompetitor(addon, job)
	return self:KeepCompetitor(addon, job)
end

---------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------
local function JobRows(options, row)
	table.insert(options, { type = "description", label = E:CompetitorStateText(row) })
	local needsOff = E:CompetitorNeedsDisable(row)
	table.insert(options, { type = "execute", label = L["Use EldoUI's"],
		desc = needsOff and L["Turns %s off for this character, after a reload, so EldoUI's %s runs."]:format(row.title, E:CompetitorJobText(row))
			or L["EldoUI's %s runs next to %s from now on. %s stays on."]:format(E:CompetitorJobText(row), row.title, row.title),
		disabled = function()
			if row.state == "eldoui" or row.state == "reload" then return L["EldoUI handles this now."] end
			if row.state == "waiting" then return L["%s isn't loaded yet."]:format(row.title) end
		end,
		func = function() E:ChooseEldoUI(row.addon, row.job) end })
	table.insert(options, { type = "execute", label = L["Keep %s"]:format(row.title),
		desc = L["%s keeps doing this job and EldoUI stands back."]:format(row.title),
		disabled = function()
			if row.state == "standing" or row.state == "waiting" then return L["%s handles this now."]:format(row.title) end
		end,
		func = function() E:ChooseCompetitor(row.addon, row.job) end })
end

local function BuildOptions()
	local options = {
		{ type = "description", label = L["When another addon does a job EldoUI also does, EldoUI stands back. Pick who handles each job; EldoUI never turns an addon off for you."] },
		{ type = "header", label = L["Notices"] },
		{ type = "toggle", key = "loginNotes", label = L["Notice when an addon is found"],
			desc = L["One notice at login the first time EldoUI finds an addon that does the same job as part of EldoUI, with a button to choose who handles it."] },
	}
	local groups = ByAddon(E:DetectedAddons())
	local covered = E:CoveredAddons()
	if #groups == 0 and #covered == 0 then
		table.insert(options, { type = "header", label = L["Addons found"] })
		table.insert(options, { type = "description", label = L["No other addon does the same job as part of EldoUI right now."] })
	end
	for _, group in ipairs(groups) do
		table.insert(options, { type = "header", label = group.title })
		for _, row in ipairs(group.rows) do JobRows(options, row) end
		if AllShared(group) and not E:CompetitorDisabledNow(group.addon) then
			table.insert(options, { type = "execute", label = L["Turn off %s"]:format(group.title),
				desc = L["Turns %s off for this character, after a reload, and EldoUI does all of its jobs."]:format(group.title),
				func = function() E:ChooseEldoUI(group.addon, nil, true) end })
		end
	end
	-- Addons that run next to EldoUI's own module for the same job: no
	-- pick to make, only what EldoUI does too, and for an addon whose whole
	-- job EldoUI does, the click that turns it off.
	if #covered > 0 then
		table.insert(options, { type = "header", label = L["Also done by EldoUI"] })
		table.insert(options, { type = "description", label = L["These addons run next to EldoUI without drawing the same thing twice, so nothing stands back. EldoUI does their job too, in full or in part."] })
		for _, group in ipairs(covered) do
			local jobs = table.concat(group.jobs, ", ")
			if E:CompetitorDisabledNow(group.addon) then
				table.insert(options, { type = "description", label = L["%s is off for this character after a reload."]:format(group.title) })
			elseif group.covers == "full" then
				table.insert(options, { type = "description", label = L["%s: EldoUI does this job too (%s)."]:format(group.title, jobs) })
				table.insert(options, { type = "execute", label = L["Turn off %s"]:format(group.title),
					desc = L["Turns %s off for this character, after a reload, and EldoUI does all of its jobs."]:format(group.title),
					func = function() E:ChooseEldoUI(group.addon, nil, true) end })
			else
				table.insert(options, { type = "description", label = L["%s: EldoUI does part of this job (%s)."]:format(group.title, jobs) })
			end
		end
	end
	E:AddonFitOptions(options)
	table.insert(options, { type = "description", label = L["Setting up the profiles of addons EldoUI places (Details!, BigWigs and more) is the setup's Other addons step: %s."]:format("/eui install addons") })
	return options
end

---------------------------------------------------------------------------
-- Layout spots for other addons (the addon fit, Core/AddonFit.lua)
---------------------------------------------------------------------------
local function FitKey(id) return "fit_" .. id end

local function ChangeRows(options, Fit, adapter)
	local module = E.modules.Integrations
	for _, key in ipairs(Fit:ChangeKeys(adapter)) do
		local change = module.changes[key]
		table.insert(options, { type = "description", label = L[change.title] .. ": " .. module:ChangeStatus(key) })
		table.insert(options, { type = "execute", label = L["Save the spot in %s"]:format(adapter.title),
			desc = L["Writes the layout's spot into %s's own settings, so it stays there without EldoUI too. You see every value first; Undo puts them back."]:format(adapter.title),
			disabled = function()
				if not module:ChangeOffered(key) then return L["%s is set like this already."]:format(adapter.title) end
			end,
			func = function() module:AskApplyChange(key) end })
		table.insert(options, { type = "execute", label = L["Undo"],
			desc = L["Puts back every value EldoUI wrote into %s's settings, except ones you changed since."]:format(adapter.title),
			disabled = function()
				if not module:ChangeApplied(key) then return L["EldoUI has nothing to undo here."] end
			end,
			func = function() module:UndoChangeAndSay(key) end })
	end
end

function E:AddonFitOptions(options)
	local Fit = self.addonFit
	local detected = Fit and Fit:Detected() or {}
	if #detected == 0 then return end
	table.insert(options, { type = "header", label = L["Layout spots for other addons"] })
	table.insert(options, { type = "description", label = L["Your layout places and sizes these addons out of combat. Their frames follow when you change layouts."] })
	table.insert(options, { type = "toggle", key = "fitEnabled", label = L["Place other addons in the layout"],
		desc = L["Off: every addon stays where its own settings put it."] })
	for _, adapter in ipairs(detected) do
		table.insert(options, { type = "description", label = L["%s: %s"]:format(adapter.title, Fit:StateText(adapter)) })
		if not adapter.managed then
			table.insert(options, { type = "toggle", key = FitKey(adapter.id), label = L["Place %s"]:format(adapter.title),
				desc = L["Off: %s stays where its own settings put it."]:format(adapter.title),
				disabled = function() if not Fit:LayerOn() then return L["The layout spots for other addons are off."] end end })
			if E.modules.Integrations then ChangeRows(options, Fit, adapter) end
		end
	end
end

local function Target()
	local store = Store()
	proxy.loginNotes = not store or store.loginNotes ~= false
	local Fit = E.addonFit
	if Fit then
		proxy.fitEnabled = Fit:LayerOn()
		for _, adapter in ipairs(Fit:Detected()) do proxy[FitKey(adapter.id)] = Fit:AddonSwitch(adapter.id) end
	end
	return proxy
end

local function Apply()
	local store = Store()
	if store then store.loginNotes = proxy.loginNotes and true or false end
	local Fit = E.addonFit
	if not Fit then return end
	if proxy.fitEnabled ~= nil and (proxy.fitEnabled and true or false) ~= Fit:LayerOn() then Fit:SetLayerOn(proxy.fitEnabled) end
	for _, adapter in ipairs(Fit:Detected()) do
		local want = proxy[FitKey(adapter.id)]
		if want ~= nil and (want and true or false) ~= Fit:AddonSwitch(adapter.id) then Fit:SetAddonOn(adapter.id, want) end
	end
end

Rebuild = function()
	if not page then return end
	page.options = nil
	page.tabs = nil
	if E.RefreshConfig then E:RefreshConfig() end
end

local function RegisterPage()
	if page or not E.RegisterConfigPage then return end
	page = E:RegisterConfigPage("addons", "Other addons", nil, Target, Apply, 1.7)
	page.build = BuildOptions
	page.desc = L["Addons you use that do the same job as part of EldoUI, and who handles each job."]
	page.defaults = function() return { loginNotes = true } end
end

E:OnCompetitorsChanged(function() Rebuild() end)
E.competitors.FitChanged = function() Rebuild() end

---------------------------------------------------------------------------
-- Notices: an alert with a Choose button (DESIGN.md 1: a notice the
-- player can act on is an alert, not a chat line). Once per addon ever
-- (switchable), several addons at one login in one alert; and once per
-- session for a pick of EldoUI that waits for the addon to be turned off.
-- A chat line only when no alert could show.
---------------------------------------------------------------------------
-- Choose opens the Other addons page through the alert's own options
-- link (the page its Ctrl-click opens too, after combat when needed).
local function OpenPage(_, card)
	if not (card and E:OpenOptionsLink(card)) then
		E:Print(L["Type %s to choose."]:format(E:Highlight(COMMAND .. " page")))
	end
end

local function Notice(key, title, text, chat)
	local shown = E:PushAlert({ key = key, title = title, text = text, options = { page = "addons" },
		actions = {
			{ label = L["Choose"], tip = L["Opens the Other addons page, where you pick who handles each job."], func = OpenPage },
			{ label = L["OK"] },
		} })
	if not shown then E:Print(chat) end
end

local function Announce(only)
	local store = Store()
	if not store then return end
	store.announced = type(store.announced) == "table" and store.announced or {}
	local found, waiting = {}, {}
	for _, group in ipairs(ByAddon(E:DetectedAddons())) do
		if only == nil or group.addon == only then
			local jobs, fallback = {}, false
			for _, row in ipairs(group.rows) do
				if row.state == "standing" then jobs[#jobs + 1] = E:CompetitorJobText(row) end
				if row.state == "fallback" then fallback = true end
			end
			if #jobs > 0 and not store.announced[group.addon] then
				store.announced[group.addon] = true
				if store.loginNotes ~= false then
					found[#found + 1] = { title = group.title, jobs = table.concat(jobs, ", ") }
				end
			end
			if fallback and not sessionNotes[group.addon] then
				sessionNotes[group.addon] = true
				waiting[#waiting + 1] = group.title
			end
		end
	end
	local suffix = only and (":" .. only) or ""
	if #found == 1 then
		local one = found[1]
		Notice("EldoUI_OtherAddons" .. suffix, L["%s handles %s"]:format(one.title, one.jobs),
			L["EldoUI stands back so the two never draw the same thing twice. Choose who handles each job."],
			L["%s is loaded, so EldoUI leaves %s to it. Type %s to choose."]:format(one.title, one.jobs, E:Highlight(COMMAND)))
	elseif #found > 1 then
		local lines, titles = {}, {}
		for index, one in ipairs(found) do
			lines[index] = L["%s: %s"]:format(one.title, one.jobs)
			titles[index] = one.title
		end
		Notice("EldoUI_OtherAddons" .. suffix, E:Plural(#found, "%d addon does EldoUI jobs", "%d addons do EldoUI jobs"):format(#found),
			table.concat(lines, "\n") .. "\n" .. L["EldoUI stands back so they never draw the same thing twice. Choose who handles each job."],
			L["%s are loaded, so EldoUI stands back for their jobs. Type %s to choose."]:format(table.concat(titles, ", "), E:Highlight(COMMAND)))
	end
	if #waiting > 0 then
		local names = table.concat(waiting, ", ")
		Notice("EldoUI_StandsBack" .. suffix, L["EldoUI stands back"],
			L["You picked EldoUI over %s, but it is still on, so EldoUI stands back. Choose again, or turn it off in the addon list."]:format(names),
			L["You picked EldoUI over %s, but %s is still on, so EldoUI stands back. Type %s to choose."]:format(names, names, E:Highlight(COMMAND)))
	end
end
E.competitors.Announce = Announce
E.competitors.sessionNotes = sessionNotes
E.competitors.late.OnLoaded = function(name)
	if loggedIn then Announce(name) end
end

---------------------------------------------------------------------------
-- /eui addons
---------------------------------------------------------------------------
local function FindAddon(word)
	word = strtrim(word or ""):lower()
	if word == "" then return nil end
	for _, row in ipairs(E:DetectedAddons()) do
		if row.addon:lower() == word or row.title:lower() == word then return row.addon end
	end
	for _, row in ipairs(E:DetectedAddons()) do
		if row.title:lower():sub(1, #word) == word or row.addon:lower():sub(1, #word) == word then return row.addon end
	end
end

function E:PrintDetectedAddons()
	local groups = ByAddon(self:DetectedAddons())
	if #groups == 0 then
		self:Print(L["No other addon does the same job as part of EldoUI right now."])
		return
	end
	self:Print(L["Other addons:"])
	local frame = _G.DEFAULT_CHAT_FRAME
	for _, group in ipairs(groups) do
		for _, row in ipairs(group.rows) do
			if frame then frame:AddMessage("  " .. self:CompetitorStateText(row)) end
		end
	end
	if frame then
		frame:AddMessage("  " .. Tinted("secondary", L["%s or %s picks for one addon."]:format(E:Highlight("/eui addons use <addon>"), E:Highlight("/eui addons keep <addon>"))))
	end
end

E:AddCommand("addons", "[page | use <addon> | keep <addon> | fit [on | off] [addon]]  which other addons do an EldoUI job; page = the Other addons page; use = EldoUI does that addon's jobs; keep = the addon does; fit = the layout spots for other addons", function(arg)
	arg = strtrim(arg or "")
	local word, rest = arg:match("^(%S*)%s*(.-)$")
	word = (word or ""):lower()
	if word == "use" or word == "keep" then
		local addon = FindAddon(rest)
		if not addon then
			E:Print(L["No addon named %s does an EldoUI job. Type %s for the list."]:format(rest, E:Highlight(COMMAND)))
			return
		end
		if word == "use" then
			E:ChooseEldoUI(addon)
			E:Print(L["EldoUI does the jobs of %s now (some after a reload)."]:format(E:AddonTitle(addon)))
		else
			E:ChooseCompetitor(addon)
			E:Print(L["%s keeps its jobs and EldoUI stands back."]:format(E:AddonTitle(addon)))
		end
	elseif word == "fit" then
		E:AddonFitCommand(rest)
	elseif word == "page" then
		E:ToggleConfig("addons")
	else
		E:PrintDetectedAddons()
	end
end, "General")

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local owner = {}
E:RegisterEvent("PLAYER_LOGIN", function()
	loggedIn = true
	RegisterPage()
	Announce()
end, owner, "modules")
