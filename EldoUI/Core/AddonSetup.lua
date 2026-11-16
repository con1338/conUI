-- EldoUI Addon Setup: sets up other addons for EldoUI in one click, using
-- each addon's own official import function and profile strings the player
-- made and exported in game. EldoUI never copies another addon's code.
--
-- Flow:
--   1. Set an addon up the way you like in game.
--   2. /eui capture <addon> saves its export string into EldoUIDB.captures
--      (automatically where the addon has an export API, otherwise a paste box).
--   3. The captured strings are moved into Data/Profiles.lua and shipped.
--   4. The installer (one checkbox per installed addon) or /eui addonsetup
--      imports them.
--
-- Register a setup (plugins can too):
--   EldoUI:RegisterAddonSetup("Details", {
--       title = "Details! Damage Meter",
--       key = function() return "default" end,  -- which stored string to use
--       keyLabel = function() return text end,  -- optional: that key in the player's
--                                                 -- words (a class or spec name)
--       available = function() return Details ~= nil end,
--       import = function(str, done) return true end, -- false + message if it failed;
--                                                 -- "pending" when the addon asks the player
--                                                 -- first: call done(accepted) once answered
--       export = function() return str end,      -- optional automatic export
--       profile = function(key) return data end, -- optional: EldoUI builds the setup
--                                                 -- itself (no string to capture)
--       missingHint = function() return text end,-- optional line while the addon is
--                                                 -- missing (e.g. a recommendation)
--       preselect = false,                       -- the installer leaves it unticked
--       version = 2,                             -- optional: the version of EldoUI's
--                                                 -- profile (else E.profileVersions[name], 1)
--   })
--
-- Keys may name a layout: a setup whose key() returns the active layout's
-- key falls back to the "default" string when that layout has none.
--
-- Updates: the version of every profile the player imports is remembered
-- (EldoUIDB.addonProfiles). When EldoUI ships a newer one for the same key,
-- the player is asked once after login (out of combat) whether to update it;
-- "Not now" waits for the next version. Every import still goes through the
-- addon's own import function, on the player's click, out of combat.
local _, E = ...
local L = E.L

E.addonSetups = {}
E.addonSetupOrder = {}
E.profileStrings = E.profileStrings or {} -- filled by Data/Profiles.lua
E.profileVersions = E.profileVersions or {} -- filled by Data/Profiles.lua

function E:RegisterAddonSetup(name, setup)
	setup.name = name
	setup.title = setup.title or name
	-- The title is read in the language shown at the time.
	E:TranslateFields({ setup }, "title")
	setup.key = setup.key or function() return "default" end
	if not self.addonSetups[name] then table.insert(self.addonSetupOrder, name) end
	self.addonSetups[name] = setup
end

local function Captures()
	EldoUIDB.captures = EldoUIDB.captures or {}
	return EldoUIDB.captures
end

-- The string to import: a fresh capture on this account wins over the
-- shipped one, so a player can test a new setup before it is committed.
function E:GetAddonProfileString(setup)
	local key = setup.key()
	if setup.profile then return setup.profile(key), key end
	local captured = Captures()[setup.name]
	if captured and captured[key] then return captured[key].data, key end
	local shipped = self.profileStrings[setup.name]
	if shipped and shipped[key] then return shipped[key], key end
	-- A setup keyed by layout uses its "default" string where a layout has none.
	if setup.layoutKeyed then
		if captured and captured.default then return captured.default.data, key end
		if shipped and shipped.default then return shipped.default, key end
	end
	return nil, key
end

---------------------------------------------------------------------------
-- Profile versions and the update offer
---------------------------------------------------------------------------
local function Applied()
	EldoUIDB.addonProfiles = EldoUIDB.addonProfiles or {}
	return EldoUIDB.addonProfiles
end

-- The version of EldoUI's profile for a setup (setup.version, then
-- E.profileVersions[name], else 1).
function E:AddonProfileVersion(name)
	local setup = self.addonSetups[name]
	local version = setup and setup.version
	if type(version) == "function" then
		local ok, result = pcall(version)
		version = ok and result or nil
	end
	return tonumber(version) or tonumber(self.profileVersions[name]) or 1
end

-- What the player last imported for a setup: { version, key, date } or nil.
function E:GetAppliedAddonProfile(name)
	local record = Applied()[name]
	return type(record) == "table" and record or nil
end

local function RememberApplied(name, key)
	Applied()[name] = { version = E:AddonProfileVersion(name), key = key, date = date("%Y-%m-%d") }
end

-- True (and the version) when EldoUI has a newer profile than the one the
-- player imported, for the same key, and the player did not say "Not now"
-- to this version.
function E:AddonProfileUpdate(name)
	local record = self:GetAppliedAddonProfile(name)
	if not record then return false end
	local status, key = self:GetAddonSetupStatus(name)
	if status ~= "ready" or record.key ~= key then return false end
	local version = self:AddonProfileVersion(name)
	if (tonumber(record.version) or 0) >= version then return false end
	if (tonumber(record.declined) or 0) >= version then return false end
	return true, version
end

-- Ask once whether to update every profile with a newer version. Returns
-- true when it asked. In combat it waits for the fight to end.
function E:CheckAddonProfileUpdates()
	if InCombatLockdown() then
		self:RunOutOfCombat(function() E:CheckAddonProfileUpdates() end, "AddonSetup:updates")
		return false
	end
	local names, titles, versions = {}, {}, {}
	for _, name in ipairs(self.addonSetupOrder) do
		local newer, version = self:AddonProfileUpdate(name)
		if newer then
			names[name], versions[name] = true, version
			titles[#titles + 1] = self.addonSetups[name].title
		end
	end
	if #titles == 0 then return false end
	self:ShowConfirm({
		key = "ELDOUI_ADDON_PROFILE_UPDATE",
		title = L["Newer addon profiles"],
		text = L["EldoUI has a newer profile for %s. Update now? Changes you made inside that profile are replaced; your other profiles stay as they are."]:format(table.concat(titles, ", ")),
		accept = L["Update"],
		cancel = L["Not now"],
		onAccept = function() E:ApplyAddonSetups(names) end,
		onCancel = function()
			for name in pairs(names) do
				local record = E:GetAppliedAddonProfile(name)
				if record then record.declined = versions[name] end
			end
		end,
	})
	return true
end

---------------------------------------------------------------------------
-- Text box window, used to paste an export string in or copy one out.
---------------------------------------------------------------------------
local textWindow

-- On the shared tool window shell: movable, an X and Escape
-- close it, and the text sits in a boxed, scrolling edit area.
local function GetTextWindow()
	if textWindow then return textWindow end
	local Kit = E.UIKit
	local window = Kit.CreateToolWindow("EldoUITextWindow", { width = 620, height = 360, strata = "FULLSCREEN_DIALOG",
		footer = Kit.TOOL_FOOTER + 8 })
	window.closeX = window.close
	window.help = Kit.Text(window.content, E.tokens.size.body, "LEFT")
	window.help:SetPoint("TOPLEFT", 4, -4)
	window.help:SetPoint("TOPRIGHT", -4, -4)
	window.help:SetWordWrap(true)

	local holder = CreateFrame("Frame", nil, window.content)
	holder:SetPoint("TOPLEFT", 0, -40)
	holder:SetPoint("BOTTOMRIGHT", 0, 0)
	E:SetTemplate(holder, true)
	local area = Kit.ScrollArea(holder)
	area:SetPoint("TOPLEFT", 6, -6)
	area:SetPoint("BOTTOMRIGHT", -6, 6)
	window.area = area
	local box = CreateFrame("EditBox", nil, area.child)
	box:SetMultiLine(true)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetPoint("TOPLEFT")
	box:SetPoint("TOPRIGHT")
	E:SetFont(box, E.tokens.size.label)
	box:SetScript("OnEscapePressed", function() window:Hide() end)
	box:SetScript("OnTextChanged", function(self)
		area.child:SetHeight(math.max(self:GetHeight() or 0, area:GetHeight() or 0))
		area:Update()
	end)
	box:SetScript("OnCursorChanged", function(_, _, y, _, height)
		local top = -y
		local view = area.scroll:GetHeight() or 0
		local scroll = area.scroll:GetVerticalScroll() or 0
		if top < scroll then
			area:SetScroll(top)
		elseif top + height > scroll + view then
			area:SetScroll(top + height - view)
		end
	end)
	-- A click anywhere in the box puts the cursor in the text.
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() box:SetFocus() end)
	window.box = box

	window.ok = Kit.Button(window.footer, "", { width = 120, large = true, kind = "primary" })
	window.ok:SetPoint("RIGHT", -8, 0)
	-- `window.close` stays the footer's Close button (the X is window.closeX).
	window.close = Kit.Button(window.footer, L["Close"], { width = 120, large = true })
	window.close:SetPoint("RIGHT", window.ok, "LEFT", -8, 0)
	window.close:SetScript("OnClick", function() window:Close() end)

	textWindow = window
	return window
end

-- Show `text` selected, ready for Ctrl+C.
function E:ShowCopyBox(title, help, text)
	local window = GetTextWindow()
	window.title:SetText(title)
	window.help:SetText(help)
	window.box:SetText(text or "")
	window.ok:SetText(L["Select all"])
	window.ok:SetScript("OnClick", function() window.box:SetFocus(); window.box:HighlightText() end)
	window:Show()
	window.box:SetFocus()
	window.box:HighlightText()
end

-- Ask the player to paste a string; onSave(text) runs when they click Save.
function E:ShowPasteBox(title, help, onSave)
	local window = GetTextWindow()
	window.title:SetText(title)
	window.help:SetText(help)
	window.box:SetText("")
	window.ok:SetText(L["Save"])
	window.ok:SetScript("OnClick", function()
		local text = strtrim(window.box:GetText() or "")
		if text ~= "" then onSave(text) end
		window:Hide()
	end)
	window:Show()
	window.box:SetFocus()
end

---------------------------------------------------------------------------
-- Capture and apply
---------------------------------------------------------------------------
local function StoreCapture(setup, key, data)
	local captures = Captures()
	captures[setup.name] = captures[setup.name] or {}
	captures[setup.name][key] = { data = data, date = date("%Y-%m-%d %H:%M"), char = E.charKey }
	E:Print(L["Saved %s setup (%s)."]:format(setup.title, key))
	E:ShowReloadPrompt(L["The %s setup is written to disk with the next reload."]:format(setup.title))
end

function E:CaptureAddon(name)
	local setup = self.addonSetups[name]
	if not setup then
		self:Print(L["No setup for %q. Known: %s"]:format(name, table.concat(self.addonSetupOrder, ", ")))
		return
	end
	if not setup.available() then
		self:Print(L["%s isn't loaded, so there is nothing to capture."]:format(setup.title))
		return
	end
	if setup.profile then
		self:Print(L["%s is set up by EldoUI itself, so there is nothing to capture."]:format(setup.title))
		return
	end
	local key = setup.key()
	if setup.export then
		local ok, data = pcall(setup.export)
		if ok and type(data) == "string" and data ~= "" then
			StoreCapture(setup, key, data)
			return
		end
	end
	self:ShowPasteBox(L["Capture %s"]:format(setup.title),
		L["Export your %s setup with its own Export button, paste the string here and click Save. Saved as \"%s\"."]:format(setup.title, key),
		function(text) StoreCapture(setup, key, text) end)
end

-- How an addon setup stands right now:
--   "missing"   the addon isn't loaded
--   "noprofile" loaded, but there is no EldoUI profile string for it yet
--   "ready"     loaded, and a profile string is waiting
-- The second return value is the key of the string (see setup.key).
function E:GetAddonSetupStatus(name)
	local setup = self.addonSetups[name]
	if not setup then return "missing" end
	local ok, available = pcall(setup.available)
	if not ok or not available then return "missing" end
	local data, key = self:GetAddonProfileString(setup)
	if not data then return "noprofile", key end
	return "ready", key
end

-- What a setup's key means for the player (setup.keyLabel), or nil for a
-- setup with one string for everyone. The raw key is never shown.
function E:AddonSetupKeyLabel(name)
	local setup = self.addonSetups[name]
	if not (setup and setup.keyLabel) then return nil end
	local ok, label = pcall(setup.keyLabel)
	if ok and type(label) == "string" and label ~= "" then return label end
end

-- Import every available addon setup that has a string. `selected`
-- (optional) is a set of setup names, so the installer can offer one
-- checkbox per addon; without it every setup is imported. `onResult`
-- (optional) hears onResult(name, imported) once per setup tried, right
-- away or, for an addon that asks the player first, after the answer.
-- Returns the titles set up, not set up and still waiting for an answer.
-- /eui addonsetup: asks first, naming every addon whose profile would be
-- written, then sets them up. Nothing changes without the Yes.
function E:ConfirmAddonSetups()
	local names, titles = {}, {}
	for _, name in ipairs(self.addonSetupOrder) do
		local setup = self.addonSetups[name]
		local checked, available = pcall(setup.available)
		if checked and available then
			names[name] = true
			titles[#titles + 1] = setup.title
		end
	end
	if #titles == 0 then
		self:Print(L["None of the addons EldoUI has profiles for is loaded."])
		return
	end
	self:ShowConfirm({
		key = "ELDOUI_ADDON_SETUP",
		title = L["Set up other addons"],
		text = L["EldoUI writes its profile into %s and switches each to it. Your other profiles in those addons stay as they are."]:format(table.concat(titles, ", ")),
		accept = L["Set up"],
		cancel = L["Not now"],
		onAccept = function() E:ApplyAddonSetups(names) end,
	})
end

function E:ApplyAddonSetups(selected, onResult)
	local done, skipped, waiting = {}, {}, {}
	-- Other addons' profiles change out of combat only; a call in combat
	-- runs when the fight ends.
	if InCombatLockdown() then
		self:Print(L["Addon profiles are set up when combat ends."])
		self:RunOutOfCombat(function() E:ApplyAddonSetups(selected, onResult) end, "AddonSetup:apply")
		return done, skipped, waiting
	end
	local function Report(name, imported, key)
		if imported then RememberApplied(name, key) end
		if not onResult then return end
		local ok, err = pcall(onResult, name, imported and true or false)
		if not ok then geterrorhandler()(err) end
	end
	for _, name in ipairs(self.addonSetupOrder) do
		local setup = self.addonSetups[name]
		local checked, available = pcall(setup.available)
		if (not selected or selected[name]) and checked and available then
			local data, key = self:GetAddonProfileString(setup)
			if data then
				local answered = false
				local ok, result, message = pcall(setup.import, data, function(accepted)
					if answered then return end
					answered = true
					Report(name, accepted, key)
				end, key)
				if ok and result == "pending" then
					table.insert(waiting, setup.title)
				elseif ok and result ~= false then
					table.insert(done, setup.title)
					-- An import that already called done(...) was reported once.
					if not answered then
						answered = true
						Report(name, true, key)
					end
				else
					table.insert(skipped, ("%s (%s)"):format(setup.title, tostring(message or result)))
					if not answered then
						answered = true
						Report(name, false)
					end
				end
			else
				local label = self:AddonSetupKeyLabel(name)
				table.insert(skipped, label and L["%s (no profile for %s yet)"]:format(setup.title, label)
					or L["%s (no profile yet)"]:format(setup.title))
				Report(name, false)
			end
		elseif selected and selected[name] then
			Report(name, false) -- ticked, but the addon is gone
		end
	end
	if #done > 0 then self:Print(L["Set up: %s"]:format(table.concat(done, ", "))) end
	if #waiting > 0 then self:Print(L["Answer in the addon's own window to finish: %s"]:format(table.concat(waiting, ", "))) end
	if #skipped > 0 then self:Print(L["Not set up: %s"]:format(table.concat(skipped, ", "))) end
	return done, skipped, waiting
end

---------------------------------------------------------------------------
-- BigWigs: EldoUI builds the profile itself (Modules/Integrations.lua:
-- anchors on the EldoUI movers, the "EldoUI" bar style, role timing) and
-- imports it through BigWigs' public BigWigsAPI.RegisterProfile as
-- "EldoUI - <Layout>", which asks the player in BigWigs' own dialog before
-- anything changes. The profile in use before is remembered for "Restore
-- my previous BigWigs profile". With the BigWigs integration off there is
-- no profile, so the installer leaves BigWigs alone.
---------------------------------------------------------------------------
local function BigWigsAPI()
	local api = _G.BigWigsAPI -- optional addon, looked up when used
	if type(api) == "table" and type(api.RegisterProfile) == "function" then return api end
end

local function Integrations()
	local module = E.modules.Integrations
	if module and module.active and module.On and module:On("bigwigs") then return module end
end

E:RegisterAddonSetup("BigWigs", {
	title = "BigWigs Bossmods",
	available = function()
		return BigWigsAPI() ~= nil
	end,
	profile = function()
		local module = Integrations()
		return module and module:BigWigsAnchorString() or nil
	end,
	-- BigWigs asks in its own window; the answer comes later.
	import = function(data, done)
		local module = Integrations()
		if not module then return false, L["the BigWigs integration is off"] end
		local ok, message = module:SendBigWigsProfile(data, function(accepted)
			if not accepted then E:Print(L["BigWigs: the EldoUI profile was not imported."]) end
			if done then done(accepted) end
		end)
		if not ok then return false, message end
		return "pending"
	end,
})

-- After login: offer the newer profiles once, when no setup window is open.
E:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, _, isLogin)
	if not isLogin then return end
	C_Timer.After(12, function()
		local installer = _G.EldoUIInstaller
		if installer and installer:IsShown() then return end
		E:CheckAddonProfileUpdates()
	end)
end, "AddonSetup")
