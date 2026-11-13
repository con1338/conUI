-- EldoUI Blessing Plan: which blessing each paladin of the group keeps up
-- on each class, in one small window.
--
--   The plan   one row per paladin in your group (you first), one square
--              per class. Click a square to pick the blessing, right-click
--              to clear it. The plan is kept per paladin name.
--   Sending    "Send to group" sends the plan as one addon message, "Post
--              in chat" writes one line per paladin to party or raid chat.
--              Both only on your click and never in combat. A paladin with
--              EldoUI who gets a plan sees their part in one chat line and
--              on the blessing reminder's tooltip.
-- Nothing is cast, chosen or answered on its own: the plan is text for the
-- paladins to follow.
-- Written from scratch for EldoUI.
-- The spell IDs here are checked against the WoW: Forever client tables of
-- build 1.60.1.70862.
local _, E = ...
local L = E.L

local M = E:NewModule("BlessingPlan", {
	title = "Blessing Plan",
	category = "Group",
	conflicts = { "PallyPower" },
	desc = "Plan which blessing each paladin of your group keeps up on each class, then send the plan to the group or post it in chat with one click.",
	frames = {},
	movers = {},
	blizzard = {},
	savedKeys = { "profile.modules.BlessingPlan" },
	optionsPage = "module:BlessingPlan",
	presets = {},
	reload = false,
	defaults = {
		enabled = true,
		announce = true,   -- one chat line with your part when a plan arrives
		reminder = true,   -- your part on the blessing reminder's tooltip
		plan = {},         -- paladin name -> { CLASS = blessing key }
		window = {},
	},
})
E.BlessingPlan = M

local Plain = E.Plain
local Secret = E.Secret
local PREFIX = "EUI_BLS"
local FORMAT = "1"
M.PREFIX = PREFIX
local MAX_PALADINS = 8
local PLAN_KEEP = 40 -- names the saved plan holds before old groups' paladins go

-- The classes, in the order of the columns and of the payload.
M.CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-- The blessings: key, payload code, first rank (name and icon), title.
-- The blessings a WoW: Forever paladin can give a whole class: Light,
-- Salvation and Sanctuary are gone from the game. A plan cell from an older
-- version that names one of those reads as no blessing.
M.BLESSINGS = {
	{ key = "might", code = "M", spell = 19740, title = "Blessing of Might" },
	{ key = "wisdom", code = "W", spell = 19742, title = "Blessing of Wisdom" },
	{ key = "kings", code = "K", spell = 20217, title = "Blessing of Kings" },
}
-- L["Blessing of Might"], L["Blessing of Wisdom"], L["Blessing of Kings"]
local BY_KEY, BY_CODE = {}, {}
for _, blessing in ipairs(M.BLESSINGS) do
	BY_KEY[blessing.key], BY_CODE[blessing.code] = blessing, blessing
end

local function Try(fn, ...)
	if type(fn) ~= "function" then return nil end
	local ok, a, b = pcall(fn, ...)
	if ok then return Plain(a), Plain(b) end
end

function M.BlessingName(key)
	local blessing = BY_KEY[key]
	if not blessing then return nil end
	local name = Try(C_Spell and C_Spell.GetSpellName, blessing.spell)
	return type(name) == "string" and name ~= "" and name or L[blessing.title]
end

function M.BlessingIcon(key)
	local blessing = BY_KEY[key]
	local icon = blessing and Try(C_Spell and C_Spell.GetSpellTexture, blessing.spell)
	return icon
end

function M.ClassName(class)
	local names = rawget(_G, "LOCALIZED_CLASS_NAMES_MALE")
	return names and names[class] or class
end

local function Clean(name)
	if type(name) ~= "string" or Secret(name) then return nil end
	name = name:gsub("[;=|]", "")
	return name ~= "" and #name <= 48 and name or nil
end

---------------------------------------------------------------------------
-- The group's paladins
---------------------------------------------------------------------------
local function UnitIsPaladin(unit)
	local _, class = Try(UnitClass, unit)
	return class == "PALADIN"
end

function M.IsPaladin() return UnitIsPaladin("player") end

-- The paladins in your group (name keys), you first.
function M:Paladins()
	local list, seen = {}, {}
	local function Add(unit)
		if #list >= MAX_PALADINS or not UnitIsPaladin(unit) then return end
		local name = Clean(E:UnitNameKey(unit))
		if name and not seen[name] then
			seen[name] = true
			list[#list + 1] = name
		end
	end
	Add("player")
	local raid = Try(IsInRaid)
	local count = Try(GetNumGroupMembers) or 0
	if type(count) ~= "number" then count = 0 end
	for index = 1, math.min(count, 40) do
		Add(raid and ("raid" .. index) or ("party" .. index))
	end
	return list
end

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------
function M:Get(name, class)
	local row = self.db.plan[name]
	return type(row) == "table" and BY_KEY[row[class]] and row[class] or nil
end

function M:Set(name, class, key)
	name = Clean(name)
	if not name then return end
	local row = type(self.db.plan[name]) == "table" and self.db.plan[name] or {}
	row[class] = BY_KEY[key] and key or nil
	self.db.plan[name] = next(row) and row or nil
	self.from = nil
	self:Changed()
end

function M:Clear()
	for _, name in ipairs(self:Paladins()) do self.db.plan[name] = nil end
	self.from = nil
	self:Changed()
end

-- Has any paladin of the group a blessing planned?
function M:HasPlan()
	for _, name in ipairs(self:Paladins()) do
		for _, class in ipairs(self.CLASSES) do
			if self:Get(name, class) then return true end
		end
	end
	return false
end

-- B;1;<name>=<one code per class, "-" for none>;...
function M:Payload()
	local parts = { "B", FORMAT }
	for _, name in ipairs(self:Paladins()) do
		local codes = {}
		for index, class in ipairs(self.CLASSES) do
			local key = self:Get(name, class)
			codes[index] = key and BY_KEY[key].code or "-"
		end
		parts[#parts + 1] = name .. "=" .. table.concat(codes)
	end
	return table.concat(parts, ";")
end

-- One part of the plan as text: "Kings: Warrior, Rogue · Wisdom: Priest".
function M:PartText(name)
	local byBlessing, order = {}, {}
	for _, class in ipairs(self.CLASSES) do
		local key = self:Get(name, class)
		if key then
			if not byBlessing[key] then
				byBlessing[key] = {}
				order[#order + 1] = key
			end
			table.insert(byBlessing[key], M.ClassName(class))
		end
	end
	if #order == 0 then return nil end
	local parts = {}
	for _, key in ipairs(order) do
		parts[#parts + 1] = L["%s: %s"]:format(M.BlessingName(key), table.concat(byBlessing[key], ", "))
	end
	return table.concat(parts, " · ")
end

-- The chat lines, one per paladin with a part.
function M:ChatLines()
	local lines = {}
	for _, name in ipairs(self:Paladins()) do
		local text = self:PartText(name)
		if text then lines[#lines + 1] = L["Blessings for %s: %s"]:format(name, text):sub(1, 255) end
	end
	return lines
end

local function Say(text, warn)
	local win = M.window
	if win and win:IsShown() then
		E.UIKit.Toast(win, text, { warn = warn })
	else
		E:Print(text)
	end
end

local function GroupChannel()
	if Try(IsInRaid) then return "RAID" end
	if Try(IsInGroup) then return "PARTY" end
end

-- Send the plan to the group (the player's click). True when it went out.
function M:Send()
	if self.fighting or InCombatLockdown() then
		Say(L["The blessing plan can be sent out of combat."], true)
		return false
	end
	if not GroupChannel() then
		Say(L["You are not in a group."], true)
		return false
	end
	if not self:HasPlan() then
		Say(L["Pick a blessing for a class first."], true)
		return false
	end
	if not E:CommRestricted() and E:SendComm(PREFIX, self:Payload(), "GROUP") then
		Say(L["Blessing plan sent to the group."])
		return true
	end
	Say(L["Could not send the blessing plan: the game doesn't allow addon messages right now."], true)
	return false
end

-- Post the plan in party or raid chat (the player's click).
function M:Post()
	if self.fighting or InCombatLockdown() then
		Say(L["The blessing plan can be posted out of combat."], true)
		return false
	end
	local channel = GroupChannel()
	if not channel then
		Say(L["You are not in a group."], true)
		return false
	end
	local lines = self:ChatLines()
	if #lines == 0 then
		Say(L["Pick a blessing for a class first."], true)
		return false
	end
	for _, line in ipairs(lines) do
		if not E:TryChatPost(line, channel) then
			Say(L["Could not post the blessing plan: the game doesn't allow chat messages right now."], true)
			return false
		end
	end
	Say(L["Blessing plan posted in chat."])
	return true
end

-- Who sent a plan, as the group knows them: their name key and whether
-- they lead the group (or assist in a raid). nil when they are not in it.
function M:SenderInGroup(sender)
	if type(sender) ~= "string" or Secret(sender) then return nil end
	local short = sender:match("^([^%-]+)") or sender
	local raid = Try(IsInRaid)
	local count = Try(GetNumGroupMembers) or 0
	if type(count) ~= "number" then count = 0 end
	for index = 1, math.min(count, 40) do
		local unit = raid and ("raid" .. index) or ("party" .. index)
		local name = Try(UnitName, unit)
		if (name and (name == short or name == sender)) or Try(UnitIsUnit, unit, short) == true then
			local lead = Try(UnitIsGroupLeader, unit) == true or (raid and Try(UnitIsGroupAssistant, unit) == true)
			return Clean(E:UnitNameKey(unit)), lead and true or false
		end
	end
end

-- A plan from the group. A paladin may send its own row; only the group's
-- leader (or a raid assistant) sets the other paladins' rows.
function M:OnPlan(fields, sender)
	local senderKey, leads = self:SenderInGroup(sender)
	if not senderKey then return end
	-- Rows only for paladins in the group now: any other name would just
	-- pile up in the saved plan.
	local paladins = {}
	for _, name in ipairs(self:Paladins()) do paladins[name] = true end
	local rows, count = {}, 0
	for _, field in ipairs(fields) do
		if count >= MAX_PALADINS then break end
		local name, codes = tostring(field):match("^([^=]+)=([%-%u]+)$")
		name = Clean(name)
		if name and paladins[name] and #codes == #self.CLASSES and (leads or name == senderKey) then
			local row = {}
			for index, class in ipairs(self.CLASSES) do
				local blessing = BY_CODE[codes:sub(index, index)]
				if blessing then row[class] = blessing.key end
			end
			rows[name] = row
			count = count + 1
		end
	end
	if next(rows) == nil then return end
	for name, row in pairs(rows) do self.db.plan[name] = next(row) and row or nil end
	-- Plans of paladins from earlier groups stay for the next raid with
	-- them, up to PLAN_KEEP names; past that, those not in the group go.
	local kept = 0
	for _ in pairs(self.db.plan) do kept = kept + 1 end
	if kept > PLAN_KEEP then
		for name in pairs(self.db.plan) do
			if not paladins[name] then self.db.plan[name] = nil end
		end
	end
	self.from = Clean(sender and sender:gsub("%-.*$", "") or nil)
	self:Changed()
	if self.db.announce and M.IsPaladin() and rows[self:MyName()] then
		local text = self:PartText(self:MyName())
		if text then E:Print(L["Blessing plan from %s: %s"]:format(self.from or "?", text)) end
	end
end

function M:MyName()
	return Clean(E:UnitNameKey("player"))
end

-- Your part for the blessing reminder's tooltip, or nil.
function M:ReminderNote()
	if not (self.active and self.db.reminder) then return nil end
	local text = self:PartText(self:MyName())
	return text and L["Blessing plan: %s"]:format(text) or nil
end

function M.Receive(payload, sender)
	if not M.active or type(payload) ~= "string" or Secret(payload) or #payload > 800 then return end
	if type(sender) ~= "string" or E:IsMe(sender) then return end
	local fields = { strsplit(";", payload) }
	if fields[1] ~= "B" or fields[2] ~= FORMAT then return end
	table.remove(fields, 1)
	table.remove(fields, 1)
	M:OnPlan(fields, sender)
end
E:RegisterComm(PREFIX, function(...) return M.Receive(...) end, { trusted = "group" })

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local NAME_W, CELL, GAP, HEAD = 120, 28, 4, 24

local function ClassIcon(texture, class)
	local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	texture:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
	if coords then texture:SetTexCoord(unpack(coords)) end
end

local function OpenPicker(cell)
	local name, class = cell.paladin, cell.class
	if not name then return end
	local items = { { text = L["%s for %s"]:format(name, M.ClassName(class)), isTitle = true } }
	for _, blessing in ipairs(M.BLESSINGS) do
		local key = blessing.key
		items[#items + 1] = { text = M.BlessingName(key), radio = true,
			checked = function() return M:Get(name, class) == key end,
			func = function() M:Set(name, class, key) end }
	end
	items[#items + 1] = { divider = true }
	items[#items + 1] = { text = L["None"], func = function() M:Set(name, class, nil) end }
	E.UIKit.OpenMenu(cell, items, { at = "cursor" })
end

local function CreateCell(parent)
	local Kit = E.UIKit
	local cell = Kit.IconButton(parent, CELL, nil, function(self, mouse)
		if mouse == "RightButton" then
			M:Set(self.paladin, self.class, nil)
		else
			OpenPicker(self)
		end
	end, nil, nil, nil, { plain = true })
	cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	cell.empty = cell:CreateTexture(nil, "OVERLAY")
	cell.empty:SetSize(8, 8)
	cell.empty:SetPoint("CENTER")
	Kit.SetGlyph(cell.empty, "dot")
	cell.empty:SetVertexColor(unpack(Kit.SECONDARY))
	Kit.Tooltip(cell, "", function(tooltip)
		local key = M:Get(cell.paladin, cell.class)
		Kit.TipText(tooltip, key and M.BlessingName(key) or L["No blessing planned"])
		Kit.TooltipHint(tooltip, { L["Click"], L["pick the blessing"] }, key and { L["Right-click"], L["clear it"] } or nil)
	end)
	return cell
end

local function UpdateCell(cell)
	local key = M:Get(cell.paladin, cell.class)
	local icon = key and M.BlessingIcon(key)
	cell.key = key
	if key then
		cell.icon:SetTexture(icon or 134400)
		cell.icon:Show()
		cell.empty:Hide()
	else
		cell.icon:Hide()
		cell.empty:Show()
	end
	cell.kitTipTitle = L["%s for %s"]:format(cell.paladin or "", M.ClassName(cell.class))
end

function M:BuildWindow()
	if self.window then return self.window end
	local Kit = E.UIKit
	local width = NAME_W + #self.CLASSES * (CELL + GAP) + 2 * Kit.TOOL_PAD
	local win = Kit.CreateToolWindow("EldoUI_BlessingPlan", { title = L["Blessing plan"], width = width, height = 200,
		footer = Kit.TOOL_FOOTER, resizable = false,
		store = function() return M.db and M.db.window end })
	self.window = win
	local content = win.content
	win.heads, win.rows = {}, {}
	for index, class in ipairs(self.CLASSES) do
		local head = CreateFrame("Frame", nil, content)
		head:SetSize(CELL, HEAD)
		head:SetPoint("TOPLEFT", NAME_W + (index - 1) * (CELL + GAP), 0)
		head:EnableMouse(true)
		head.icon = head:CreateTexture(nil, "ARTWORK")
		head.icon:SetSize(18, 18)
		head.icon:SetPoint("CENTER")
		ClassIcon(head.icon, class)
		Kit.Tooltip(head, M.ClassName(class))
		win.heads[index] = head
	end
	for rowIndex = 1, MAX_PALADINS do
		local row = CreateFrame("Frame", nil, content)
		row:SetHeight(CELL)
		row:SetPoint("TOPLEFT", 0, -(HEAD + (rowIndex - 1) * (CELL + GAP)))
		row:SetPoint("TOPRIGHT", 0, -(HEAD + (rowIndex - 1) * (CELL + GAP)))
		row.name = Kit.Text(row, E.tokens.size.label, "LEFT")
		row.name:SetPoint("LEFT", 2, 0)
		row.name:SetWidth(NAME_W - 8)
		row.name:SetWordWrap(false)
		row.cells = {}
		for index, class in ipairs(self.CLASSES) do
			local cell = CreateCell(row)
			cell.class = class
			cell:SetPoint("LEFT", NAME_W + (index - 1) * (CELL + GAP), 0)
			row.cells[index] = cell
		end
		win.rows[rowIndex] = row
	end
	win.empty = Kit.Text(content, E.tokens.size.label, "LEFT", "secondary")
	win.empty:SetPoint("TOPLEFT", 2, -(HEAD + 6))
	win.empty:SetPoint("TOPRIGHT", -2, -(HEAD + 6))
	win.empty:SetWordWrap(true)
	win.empty:SetText(L["No paladins in your group. The plan lists every paladin of your party or raid."])

	win.send = Kit.Button(win.footer, { text = L["Send to group"], kind = "primary", onClick = function() M:Send() end,
		tip = { L["Send to group"], L["One addon message with the plan to your group, out of combat. Paladins with EldoUI see their part."] } })
	win.send:SetPoint("RIGHT", -Kit.TOOL_PAD, 0)
	win.post = Kit.Button(win.footer, { text = L["Post in chat"], onClick = function() M:Post() end,
		tip = { L["Post in chat"], L["One line per paladin in party or raid chat, out of combat."] } })
	win.post:SetPoint("RIGHT", win.send, "LEFT", -6, 0)
	win.clear = Kit.Button(win.footer, { text = L["Clear"], onClick = function() M:Clear() end,
		tip = { L["Clear"], L["Clears the plan of every paladin listed here."] } })
	win.clear:SetPoint("RIGHT", win.post, "LEFT", -6, 0)
	win.footerText:SetPoint("RIGHT", win.clear, "LEFT", -8, 0)
	win:HookScript("OnShow", function() M:Refresh() end)
	return win
end

function M:Refresh()
	local win = self.window
	if not (win and win:IsShown()) then return end
	local paladins = self:Paladins()
	for rowIndex, row in ipairs(win.rows) do
		local name = paladins[rowIndex]
		row:SetShown(name ~= nil)
		if name then
			local text = E:WrapClassColor("PALADIN", name)
			if E:IsMe(name) then text = L["%s (you)"]:format(text) end
			row.name:SetText(text)
			for _, cell in ipairs(row.cells) do
				cell.paladin = name
				UpdateCell(cell)
			end
		end
	end
	win.empty:SetShown(#paladins == 0)
	local rows = math.max(#paladins, 1)
	local Kit = E.UIKit
	win:SetHeight(Kit.TOOL_HEADER + 2 * Kit.TOOL_PAD + HEAD + rows * (CELL + GAP) + (#paladins == 0 and 24 or 0) + Kit.TOOL_FOOTER)
	local combat = self.fighting or InCombatLockdown()
	local grouped = GroupChannel() ~= nil
	win.send:SetEnabled(grouped and not combat)
	win.post:SetEnabled(grouped and not combat)
	win.clear:SetEnabled(#paladins > 0)
	if self.from then
		win.footerText:SetText(L["Plan from %s"]:format(self.from))
	elseif combat then
		win.footerText:SetText(L["Sending waits until combat ends."])
	else
		win.footerText:SetText(L["Click a square to pick a blessing."])
	end
end

function M:Changed()
	self:Refresh()
	local reminders = E.modules.Reminders
	if reminders and reminders.active and reminders.Update then pcall(reminders.Update, reminders) end
end

function M:Open()
	if not self.active then return false end
	self:BuildWindow():Open()
	self:Refresh()
	return true
end

function M:Toggle()
	if self.window and self.window:IsShown() then
		self.window:Close()
		return false
	end
	return self:Open()
end

E:AddCommand("blessings", "open or close the blessing plan window", function()
	if not M.active then
		E:Print(E:ModuleOffHint("BlessingPlan"))
		return
	end
	M:Toggle()
end, "Tools")

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function M:OnEnable()
	self:RegisterEvent("GROUP_ROSTER_UPDATE", function() M:Refresh() end)
	-- The game still says "not in combat" while this event runs.
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		M.fighting = true
		M:Refresh()
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		M.fighting = nil
		M:Refresh()
	end)
end

function M:OnDisable()
	for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		self:UnregisterEvent(event)
	end
	if self.window then self.window:Hide() end
end

function M:OnProfileChanged()
	self.from = nil
	self:Refresh()
end

M.options = {
	{ type = "description", label = "Plan which blessing each paladin keeps up on each class, and send it to the group or chat on your click. Nothing is cast for you." },
	{ type = "execute", label = "Open the blessing plan", noUndo = true, testSafe = true,
		desc = "Opens the plan window. Click a square to pick a blessing, right-click to clear it. Also /eui blessings.",
		func = function() M:Open() end },
	{ type = "header", label = "Your part" },
	{ type = "toggle", key = "announce", label = "Tell me my part",
		desc = "When a plan arrives from your group, one chat line names the blessings you keep up and on which classes. Paladins only." },
	{ type = "toggle", key = "reminder", label = "On the blessing reminder",
		desc = "The blessing reminder's tooltip names your part of the plan (Reminders, paladins only)." },
}

