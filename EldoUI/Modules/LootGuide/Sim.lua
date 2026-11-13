-- EldoUI Loot Guide: the bridge to the simulator.
--
-- The simulator itself lives in the load-on-demand folder EldoUI_LootSim
-- (engine, class models, reader, jobs, window). This file stays in EldoUI so
-- that everything that only shows results works without loading it:
--   * the "sim" rating mode on E.ItemScore (per character, "Rate items by"):
--     an item rates by the DPS the simulator found for it with the gear,
--     talents, level and fight settings you have now; items it has not run
--     yet, or whose run is outdated, keep the stat-weights gain
--   * Best in Slot in Sim mode: the simulated set (when it is up to date)
--   * the saved results in EldoUIDB.lootGuide[character].sim
--   * LG:RunSim(kind, arg): loads EldoUI_LootSim (out of combat, only when
--     the player clicks a sim button) and starts a job
--   * progress for the window footers, the For You header, the datatext
--     ("Sim 42 %") and a lane toast when a run is done
--   * /eui sim, "Simulate" in the item menu and a Sim button on the item
--     check card
--
-- Rules: the simulator never runs in combat and only the player starts it.
-- It reads the player's own character sheet and uses public Classic combat
-- formulas; results are estimates and are labeled so.
local _, E = ...
local LG = E.LootGuide
local L = E.L

local Key = E.Key
local ADDON = "EldoUI_LootSim"
local GAIN_FLOOR = 0.5      -- DPS a gain must reach on top of twice its error
local BIS_LENGTH = 60       -- Best in Slot runs use one-minute fights

local Secret = E.Secret

local Plain = E.Plain

---------------------------------------------------------------------------
-- The folder
---------------------------------------------------------------------------
function LG:SimLoaded()
	return E.LootSim ~= nil and E.LootSim.Jobs ~= nil
end

-- Is the simulator folder installed and allowed to load?
function LG:SimAvailable()
	if self:SimLoaded() then return true end
	if not (C_AddOns and C_AddOns.GetAddOnInfo) then return false end
	local ok, name, _, _, _, reason = pcall(C_AddOns.GetAddOnInfo, ADDON)
	if not ok or not name then return false end
	if reason == "DISABLED" or reason == "DEP_DISABLED" then return false end
	return true
end

-- Load EldoUI_LootSim. true, or false and a reason.
function LG:LoadSim()
	if self:SimLoaded() then return true end
	if InCombatLockdown() then return false, "combat" end
	if not (C_AddOns and C_AddOns.GetAddOnInfo and C_AddOns.LoadAddOn) then return false, "missing" end
	local name, _, _, _, reason = C_AddOns.GetAddOnInfo(ADDON)
	if not name then return false, "missing" end
	if reason == "DISABLED" or reason == "DEP_DISABLED" then return false, "disabled" end
	local loaded, why = C_AddOns.LoadAddOn(ADDON)
	if loaded and self:SimLoaded() then return true end
	return false, "failed", why
end

-- Why a run cannot start, in words.
local REASONS = E:TranslateValues({
	combat = Key("The simulator runs out of combat. Try again when the fight is over."),
	missing = Key("The simulator folder EldoUI_LootSim is not installed. It comes with EldoUI: put it next to the EldoUI folder in Interface\\AddOns."),
	disabled = Key("EldoUI_LootSim is switched off in the addon list."),
	failed = Key("EldoUI_LootSim could not load. Check that it is in Interface\\AddOns next to EldoUI."),
	class = Key("The simulator has no model for your class."),
	noPet = Key("Call your pet first: the simulator counts its damage."),
	noRanged = Key("Equip a ranged weapon first."),
	catForm = Key("Shift into Cat Form first, so the simulator can read your cat's attack power."),
	bearForm = Key("Shift into Bear Form first, so the simulator can read your bear's attack power."),
	variant = Key("The simulator found no damage spells it can use yet."),
	nogear = Key("That item does not go in an equipment slot."),
	nosets = Key("Your plan sets are empty. Pick items for them on the Best in Slot page or in the Planner tab."),
})
LG.SIM_REASONS = REASONS

function LG:SimReasonText(reason)
	return REASONS[reason or ""] or L["The simulator could not start."]
end

-- Why the simulator can't be opened now (folder missing or switched off),
-- without loading it; nil when it can. Grays the "Open the simulator" row.
function LG:SimUnavailable()
	if self:SimLoaded() then return nil end
	if not (C_AddOns and C_AddOns.GetAddOnInfo) then return REASONS.missing end
	local name, _, _, _, reason = C_AddOns.GetAddOnInfo(ADDON)
	if not name then return REASONS.missing end
	if reason == "DISABLED" or reason == "DEP_DISABLED" then return REASONS.disabled end
	return nil
end

---------------------------------------------------------------------------
-- Saved results and the setup they belong to
---------------------------------------------------------------------------
function LG:SimStore()
	local data = self:Char()
	if not data then return { items = {}, bis = {} } end
	local store = data.sim
	if type(store) ~= "table" then
		store = {}
		data.sim = store
	end
	if type(store.items) ~= "table" then store.items = {} end
	if type(store.bis) ~= "table" then store.bis = {} end
	return store
end

local TARGET_PLUS = { same = 0, plus1 = 1, plus2 = 2, boss = 3 }
LG.SIM_TARGETS = { "same", "plus1", "plus2", "boss" }
LG.SIM_LENGTHS = { 60, 180, 300 }

-- Fight settings from the simulator window's choices.
function LG:SimSettings(length)
	local ui = self:UI()
	local level = tonumber(Plain(UnitLevel("player"))) or 60
	local plus = TARGET_PLUS[ui.simTarget or "boss"] or 3
	return { targetLevel = math.min(63, level + plus), length = length or tonumber(ui.simLength) or 180 }
end

local setupCache -- level, gear and talents (cleared by events)

local function GearSignature()
	local parts = {}
	for slot = 1, 18 do
		local id = Plain(GetInventoryItemID("player", slot))
		parts[#parts + 1] = tostring(id or 0)
	end
	return table.concat(parts, ".")
end

local function TalentSignature()
	local talents = LG:TalentRanks()
	return talents and talents.key or ""
end

local function Setup()
	if not setupCache then
		local level = tonumber(Plain(UnitLevel("player"))) or 0
		setupCache = ("%d|%s|%s"):format(level, GearSignature(), TalentSignature())
	end
	return setupCache
end

-- The key results are saved with; a different key means outdated.
function LG:SimSetupKey(settings)
	settings = settings or self:SimSettings()
	return ("%s|%d|%d"):format(Setup(), settings.targetLevel or 0, settings.length or 0)
end

local function Changed()
	setupCache = nil
	LG:Fire("sim")
end

LG:Listen("PLAYER_EQUIPMENT_CHANGED", "sim", Changed)
LG:Listen("PLAYER_LEVEL_UP", "sim", Changed)
LG:Listen("CHARACTER_POINTS_CHANGED", "sim", Changed)
LG:Listen("PLAYER_TALENT_UPDATE", "sim", Changed)
LG:Listen("TRAIT_CONFIG_UPDATED", "sim", Changed)

-- The Best in Slot record for your spec, or nil.
function LG:SimBiS()
	local data = self:Char()
	local store = data and data.sim
	if type(store) ~= "table" or type(store.bis) ~= "table" then return end
	local spec = E.ItemScore and E.ItemScore:PlayerSpec() or "none"
	return store.bis[spec or "none"]
end

function LG:SimJob()
	local sim = E.LootSim
	return sim and sim.Scheduler and sim.Scheduler.Current()
end

-- "none", "running", "paused", "ready" or "outdated" (the Best in Slot run).
function LG:SimStatus()
	local job = self:SimJob()
	if job then return E.LootSim.Scheduler.IsPaused() and "paused" or "running", job end
	local record = self:SimBiS()
	if not record then return "none" end
	if record.key ~= self:SimSetupKey(self:SimSettings(BIS_LENGTH)) or record.listKey ~= self:ListKey() then return "outdated", record end
	return "ready", record
end

-- Progress 0..1 of the running job and its kind.
function LG:SimProgress()
	local job = self:SimJob()
	if not job then return end
	return job.progress or 0, job.kind
end

-- "smooth", "fast" or "turbo": how much of each frame a run may use.
function LG:SimSpeed()
	local speed = self.db and self.db.simSpeed
	if speed == "smooth" or speed == "turbo" then return speed end
	return "fast"
end

function LG:SimMode()
	return E.ItemScore ~= nil and E.ItemScore:GetRating() == "sim"
end

-- Is a simulated gain worth calling an upgrade? (twice its error and a floor)
function LG:SimIsGain(dps, err)
	dps, err = tonumber(dps), tonumber(err) or 0
	return dps ~= nil and dps > math.max(2 * err, GAIN_FLOOR)
end

-- An item's record when it is up to date.
function LG:SimItem(itemID)
	itemID = tonumber(itemID)
	local data = self:Char()
	local store = data and data.sim
	local record = itemID and type(store) == "table" and type(store.items) == "table" and store.items[itemID]
	if type(record) ~= "table" then return end
	if record.key ~= self:SimSetupKey(self:SimSettings(BIS_LENGTH)) then return nil, record end
	return record
end

-- "+12.4 DPS" for the Best in Slot set when its run is up to date.
function LG:SimSetGainText()
	local status, record = self:SimStatus()
	if status ~= "ready" or not record then return end
	if not self:SimIsGain(record.setGain, record.setErr) then return L["no gain"] end
	return ("+%.1f %s"):format(record.setGain, L["DPS"])
end

---------------------------------------------------------------------------
-- Watching progress (window footers, For You, the datatext)
---------------------------------------------------------------------------
local watchers = {}
local lastNotice = 0

function LG:SimWatch(key, fn)
	watchers[key] = fn
end

local function Notify(force)
	local now = GetTime()
	if not force and now - lastNotice < 0.25 then return end
	lastNotice = now
	for key, fn in pairs(watchers) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(("EldoUI Loot Guide sim watcher %s: %s"):format(tostring(key), tostring(err))) end
	end
	local bar = E.modules and E.modules.InfoBar
	if bar and bar.active and bar.RefreshDataText then pcall(bar.RefreshDataText, bar, "LootGuide") end
end
LG.SimNotify = Notify

-- The datatext's text while a run is going.
function LG:SimDataText()
	local progress = self:SimProgress()
	if not progress then return end
	local paused = E.LootSim.Scheduler.IsPaused()
	return ("%s %d %%%s"):format(L["Sim"], math.floor(progress * 100), paused and (" " .. L["(paused)"]) or "")
end

-- One line for the datatext tooltip (nil when there is nothing to say).
function LG:SimSummary()
	local status = self:SimStatus()
	if status == "running" or status == "paused" then return self:SimDataText() end
	if status == "ready" then return (L["Best in Slot %s"]):format(self:SimSetGainText() or "") end
	if status == "outdated" then return L["Best in Slot run is outdated"] end
end

---------------------------------------------------------------------------
-- Running
---------------------------------------------------------------------------
local KIND_TITLES = { bis = Key("Best in Slot run"), char = Key("Character run"), item = Key("Item run"), sets = Key("Sets run") }

local function Lane()
	local notifications = E.modules and E.modules.Notifications
	if not (notifications and notifications.active and notifications.PushToast) then return end
	if E.BlizzardAllowed and not E:BlizzardAllowed("alert-toasts", "replace") then return end
	return notifications
end

local function ItemName(itemID)
	local name = C_Item.GetItemInfo(itemID)
	if Secret(name) or not name then
		local record = LG:ItemRecord(itemID)
		name = record and record.name
	end
	return name or ("item:" .. tostring(itemID))
end

-- What a finished run says.
local function DoneText(kind, result)
	if kind == "bis" and result then
		if LG:SimIsGain(result.setGain, result.setErr) then
			return (L["Best in Slot set: +%.1f DPS (estimate)"]):format(result.setGain)
		end
		return L["Best in Slot: nothing on your list beats what you wear."]
	elseif kind == "char" and result then
		return (L["Your DPS: %.1f ± %.1f (estimate)"]):format(result.dps, result.err)
	elseif kind == "item" then
		if result then
			return L["%s: %+.1f DPS ± %.1f"]:format(ItemName(result.itemID), result.dps, result.err)
		end
		return L["The simulator has no numbers for this item yet."]
	elseif kind == "sets" then
		return L["Your sets are simulated. Open the Sets tab to compare them."]
	end
	return L["The simulation is done."]
end

function LG:OnSimDone(kind, result)
	setupCache = nil
	if self.ClearTooltipCache then self:ClearTooltipCache() end
	if E.ItemScore then E.ItemScore:Bump() end
	self.simLast = { kind = kind, at = GetTime() }
	self:Fire("sim")
	self:Fire("rank")
	Notify(true)
	local title = KIND_TITLES[kind] and L[KIND_TITLES[kind]] or L["Simulator"]
	local text = DoneText(kind, result)
	local lane = Lane()
	if lane then
		local r, g, b = LG.Kit.Accent()
		lane:PushToast({ title = L["Simulator"] .. " · " .. title, text = text, sub = L["estimate"], icon = LG.ICON,
			color = { r, g, b }, border = { r, g, b }, onClick = function() LG:OpenSim(kind == "sets" and "sets" or "char") end })
	else
		E:Print(L["Simulator"] .. ": " .. text)
	end
end

-- Start a run. kind: "bis" (default), "char", "item" (arg = itemID),
-- "sets" (arg = the sets to compare). Returns true, or false and a reason
-- (also said in chat unless quiet).
function LG:RunSim(kind, arg, quiet)
	kind = kind or "bis"
	local function Fail(reason)
		self.simMessage = reason
		if not quiet then E:Print(self:SimReasonText(reason)) end
		Notify(true)
		return false, reason
	end
	if InCombatLockdown() then return Fail("combat") end
	local ok, reason = self:LoadSim()
	if not ok then return Fail(reason) end
	local S = E.LootSim
	local prepared, why = S.Jobs.Prepare()
	if not prepared then return Fail(why or "class") end
	local job
	if kind == "char" then
		job = S.Jobs.Character(prepared)
	elseif kind == "item" then
		local itemID = tonumber(arg)
		if not (itemID and self:ItemSlots(itemID)) then return Fail("nogear") end
		job = S.Jobs.Item(prepared, itemID)
	elseif kind == "sets" then
		local sets = type(arg) == "table" and arg or self:SimSetList()
		if #sets == 0 then return Fail("nosets") end
		job = S.Jobs.Sets(prepared, sets)
	else
		job = S.Jobs.BiS(prepared)
	end
	self.simMessage = nil
	self.simReport = prepared.report
	job.onUpdate = function() Notify() end
	job.onStop = function() Notify(true) end
	job.onError = function() Notify(true) end
	local started, startWhy = S.Scheduler.Start(job)
	if not started then return Fail(startWhy or "combat") end
	Notify(true)
	return true
end

function LG:StopSim()
	local sim = E.LootSim
	if sim and sim.Scheduler then
		local stopped = sim.Scheduler.Stop()
		Notify(true)
		return stopped
	end
	return false
end

-- Worn, Best in Slot and the two plan sets as changes against what you
-- wear, for the Sets run.
function LG:SimSetList()
	local list = {}
	local data = self:Char()
	list[#list + 1] = { key = "worn", title = L["What I wear"], changes = {} }
	local bis = self:SimBiS()
	if bis and type(bis.changes) == "table" and next(bis.changes) then
		list[#list + 1] = { key = "bis", title = L["Best in Slot"], changes = CopyTable(bis.changes) }
	end
	for index = 1, 2 do
		local slots = data and data.sets[index] and data.sets[index].slots
		if type(slots) == "table" and next(slots) then
			list[#list + 1] = { key = "set" .. index, title = self:SetName(index), changes = CopyTable(slots) }
		end
	end
	return list
end

-- Open the simulator window (loads the folder). tab: char, planner, sets.
function LG:OpenSim(tab)
	if not self.active then return end
	if InCombatLockdown() then
		E:Print(self:SimReasonText("combat"))
		return
	end
	local ok, reason = self:LoadSim()
	if not ok then
		E:Print(self:SimReasonText(reason))
		return
	end
	if E.LootSim.Window then E.LootSim.Window.Open(tab) end
end

function LG:ToggleSim()
	local sim = E.LootSim
	local window = sim and sim.Window and sim.Window.Frame()
	if window and window:IsShown() then window:Hide() else self:OpenSim() end
end

---------------------------------------------------------------------------
-- The "sim" rating mode
---------------------------------------------------------------------------
local function ItemIDOf(link)
	if type(link) ~= "string" or Secret(link) then return end
	return tonumber(link:match("item:(%d+)"))
end

local function RegisterRater()
	if not (E.ItemScore and E.ItemScore.RegisterRater) then return end
	E.ItemScore:RegisterRater("sim", {
		title = L["Simulator (DPS estimate)"],
		desc = L["Fights against a target dummy with your own character sheet. Slower, but counts how your talents and spells use each stat. Items not simulated yet keep the weights gain."],
		rate = function(_, link)
			local record = LG:SimItem(ItemIDOf(link))
			if not record then return end
			return { dps = record.dps, simErr = record.err, upgrade = LG:SimIsGain(record.dps, record.err) }
		end,
	})
end
RegisterRater()

---------------------------------------------------------------------------
-- Best in Slot in Sim mode
---------------------------------------------------------------------------
local baseBiSSet = LG.BiSSet
if baseBiSSet then
	function LG:BiSSet(phase)
		if self:SimMode() then
			local status, record = self:SimStatus()
			if (status == "ready" or status == "running" or status == "paused") and record and type(record.set) == "table" then
				return record.set, record.setDps or 0, self:RankAll(nil, { phase = phase or self:PlanPhase() })
			end
		end
		return baseBiSSet(self, phase)
	end
end

---------------------------------------------------------------------------
-- Commands, item menu, item check card
---------------------------------------------------------------------------
E:AddCommand("sim", "[bis | char | stop]  the Loot Guide simulator: open its window, or start or stop a run", function(arg)
	if not LG.active then
		E:Print(E:ModuleOffHint("LootGuide"))
		return
	end
	local word = strtrim(arg or ""):lower()
	if word == "stop" then
		if not LG:StopSim() then E:Print(L["No simulation is running."]) end
	elseif word == "bis" or word == "char" then
		LG:RunSim(word)
	else
		LG:ToggleSim()
	end
end, "Tools")

LG:RegisterItemMenu("sim", function(root, itemID)
	if not (LG:BiSOn() and LG:ItemSlots(itemID) and LG:SimAvailable()) then return end
	root:CreateButton(L["Simulate"], function() LG:RunSim("item", itemID) end)
end)

-- Item check card: a Sim button beside the verdict, and the sim number in
-- the verdict tooltip.
local function DressCheckCard()
	local checkCard = LG.CheckCard
	if Secret(checkCard) or type(checkCard) ~= "function" then return end
	local card = checkCard(LG)
	if Secret(card) or type(card) == "nil" then return end
	if type(card) ~= "table" and type(card) ~= "userdata" then return end
	local existing = card.simButton
	if Secret(existing) or type(existing) ~= "nil" then return end
	local Kit = LG.Kit
	if Secret(LG.CheckCard) or LG.CheckCard ~= checkCard then return end
	card.simButton = Kit.Button(card, L["Sim"], 44, 18, function()
		if card.itemID then LG:RunSim("item", card.itemID) end
	end, L["Simulate"], L["Fights against a target dummy with this item instead of what you wear in its slot (about a second, out of combat). The result shows here, in the tooltip and as a toast."])
	-- Beside the verdict line (icon 12 + 36 + 8 px down), anchored to the card
	-- so nothing points back at itself.
	card.simButton:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -54)
	card.simText = Kit.Text(card, 11, "RIGHT", "secondary")
	local button, verdict, source, number = card.simButton, card.verdictText, card.source, card.simText
	local function Current()
		if Secret(LG.CheckCard) or LG.CheckCard ~= checkCard then return false end
		local current = checkCard(LG)
		if Secret(current) or current ~= card or Secret(LG.CheckCard) or LG.CheckCard ~= checkCard
			or Secret(card.simButton) or Secret(card.verdictText) or Secret(card.source) or Secret(card.simText)
			or card.simButton ~= button or card.verdictText ~= verdict or card.source ~= source or card.simText ~= number then return false end
		for _, frame in ipairs({ button, verdict, number }) do
			local parent = frame:GetParent()
			if Secret(parent) or parent ~= card then return false end
		end
		if source then
			local parent = source:GetParent()
			if Secret(parent) or parent ~= card then return false end
		end
		return true
	end
	local function Known(value)
		return not Secret(value) and type(value) == "number" and value == value and math.abs(value) < math.huge and value >= 0
	end
	local request = 0
	local function Layout()
		request = request + 1
		local own = request
		local function Live() return own == request and Current() and own == request end
		if not Live() then return end
		local width, height = button:GetSize()
		local textHeight = verdict:GetHeight()
		if not Live() or not Known(width) or not Known(height) or not Known(textHeight) or width == 0 or height == 0 then return end
		-- The existing verdict top is two units below the button's top.
		-- Both source texts share a row four units below the lower body.
		local gap = 4 + math.max(height - textHeight - 2, 0)
		verdict:SetPoint("TOPRIGHT", button, "TOPLEFT", -6, -2)
		if not Live() then return end
		number:SetPoint("TOPRIGHT", verdict, "BOTTOMRIGHT", width + 6, -gap)
		if not Live() then return end
		if source then
			source:SetPoint("TOPLEFT", verdict, "BOTTOMLEFT", 0, -gap)
			if not Live() then return end
			source:SetPoint("TOPRIGHT", number, "TOPLEFT", -6, 0)
		end
	end
	local function Update()
		local show = card:IsShown() and card.itemID and LG:BiSOn() and LG:ItemSlots(card.itemID) and LG:SimAvailable()
		card.simButton:SetShown(show and true or false)
		local record = show and LG:SimItem(card.itemID)
		card.simText:SetText(record and L["%+.1f DPS ± %.1f"]:format(record.dps, record.err) or "")
		Layout()
	end
	button:HookScript("OnSizeChanged", Layout)
	E:OnThemeChanged("lootguide:sim-check", Layout)
	card:HookScript("OnShow", Update)
	card.UpdateSim = Update
	LG:SimWatch("checkcard", function() if card:IsShown() then Update() end end)
	Update()
end

LG:On("sim-check", function(changed)
	DressCheckCard()
	local card = LG.CheckCard and LG:CheckCard()
	if card and card.UpdateSim and card:IsShown() and (changed.sim or changed.gear or changed.items) then card.UpdateSim() end
end)

if LG.OpenCheck then
	local baseOpenCheck = LG.OpenCheck
	function LG:OpenCheck(link)
		baseOpenCheck(self, link)
		DressCheckCard()
		local card = self:CheckCard()
		if card and card.UpdateSim then card.UpdateSim() end
	end
end

-- The Loot Guide window's footer: progress and Stop while a run goes on.
local function DressWindowFooter()
	local window = LG.WindowFrame and LG:WindowFrame()
	if not window or not window.footer then return end
	local footer = window.footer
	if not footer.simStop then
		local Kit = LG.Kit
		footer.simStop = Kit.Button(footer, L["Stop"], 52, 18, function() LG:StopSim() end, L["Stop"],
			L["Stops the simulator run. Results saved so far stay."])
		footer.simStop:SetPoint("RIGHT", -28, 0)
		footer.simText = Kit.Text(footer, 11, "RIGHT", "secondary")
		footer.simText:SetPoint("RIGHT", footer.simStop, "LEFT", -8, 0)
		footer.simBar = E:CreateStatusBar(footer)
		footer.simBar:SetSize(80, 4)
		footer.simBar:SetMinMaxValues(0, 1)
		footer.simBar:SetPoint("RIGHT", footer.simText, "LEFT", -8, 0)
	end
	local progress = LG:SimProgress()
	local running = progress ~= nil
	footer.simStop:SetShown(running)
	footer.simText:SetShown(running)
	footer.simBar:SetShown(running)
	if running then
		footer.simText:SetText(LG:SimDataText() or "")
		footer.simBar:SetValue(progress)
		footer.simBar:SetStatusBarColor(LG.Kit.Accent())
	end
	if window.footerText then
		window.footerText:ClearAllPoints()
		window.footerText:SetPoint("LEFT", 12, 0)
		if running then
			window.footerText:SetPoint("RIGHT", footer.simBar, "LEFT", -10, 0)
		else
			window.footerText:SetPoint("RIGHT", -28, 0)
		end
	end
end
LG.DressSimFooter = DressWindowFooter
LG:SimWatch("lgfooter", function() if LG:IsOpen() then DressWindowFooter() end end)

local baseOpen = LG.Open
function LG:Open(key, arg)
	baseOpen(self, key, arg)
	if self:IsOpen() then DressWindowFooter() end
end

-- Combat pauses a run: tell the watchers at once.
LG:Listen("PLAYER_REGEN_DISABLED", "sim", function() if LG:SimJob() then Notify(true) end end)
LG:Listen("PLAYER_REGEN_ENABLED", "sim", function() if LG:SimJob() then Notify(true) end end)
