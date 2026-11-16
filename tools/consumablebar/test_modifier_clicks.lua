-- Offline test: the Consumable Bar's buttons use their item with Shift, Ctrl or Alt held.
-- Run from the repository root:
--   lua5.1 tools/consumablebar/test_modifier_clicks.lua
-- The game looks a secure attribute up as modifier-name-button, *name-button, modifier-name*, *name* and name
-- (Blizzard_FrameXML/SecureTemplates.lua, comment at the top: "action1" is the unmodified left click only). A key
-- bound with a modifier presses the button with that modifier held: the key sets put the bar's buttons on bar 3's
-- Ctrl keys (Core/KeybindPresets.lua, E.keybindConsumableKeys), and a macro's /click runs with whatever modifier
-- the player holds. A plain "type1" found no action then, and the key did nothing.
-- It cuts the real CreateButton and ApplySecure out of EldoUI/Modules/ConsumableBar.lua (between fixed markers,
-- so a renamed part makes the test fail instead of testing a stale copy) and runs them with stand-in frames.
-- Checked: after CreateButton and after ApplySecure (items and a mount spell) the left button finds its action and
-- its item or spell with no modifier, Shift, Ctrl, Alt and all three; the right button finds none (it opens the
-- picker); no plain "type1" is left that would win over "*type1" without a modifier.
local ROOT = (arg and arg[0] or ""):match("^(.-)tools/consumablebar/") or "./"

local function ReadFile(path)
	local file = assert(io.open(ROOT .. path, "rb"), "can't open " .. path)
	local text = file:read("*a")
	file:close()
	return (text:gsub("\r\n", "\n"))
end

-- The text from `first` up to (not including) `last`.
local function Between(text, first, last, where)
	local from = text:find(first, 1, true)
	assert(from, where .. ": marker not found: " .. first)
	local to = text:find(last, from + #first, true)
	assert(to, where .. ": end marker not found after " .. first .. ": " .. last)
	return text:sub(from, to - 1)
end

local passed, failed = 0, 0
local function Check(ok, what)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		print("FAIL: " .. what)
	end
end

---------------------------------------------------------------------------
-- Stand-ins
---------------------------------------------------------------------------
local Frame = {}
local meta = { __index = function(_, key)
	if Frame[key] then return Frame[key] end
	if type(key) == "string" and key:match("^%u") then return function() end end -- other widget methods do nothing
end }
local function NewFrame(kind, name)
	return setmetatable({ kind = kind, name = name, attributes = {}, shown = true }, meta)
end
function Frame:SetAttribute(name, value) self.attributes[name] = value end
function Frame:GetAttribute(name) return self.attributes[name] end
function Frame:RegisterForClicks(...) self.clicks = { ... } end
function Frame:CreateTexture() return NewFrame("Texture") end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:SetShown(on) self.shown = on and true or false end
local function CreateFrame(kind, name) return NewFrame(kind, name) end

local E = {
	pixel = 1, tokens = { size = { small = 10 } }, media = { accentColor = { 1, 0.8, 0.3 } }, movers = {}, db = {}, profileName = "Default",
}
function E:SetTemplate() end
function E:TrimIcon() end
function E:CreateText() return NewFrame("FontString") end
function E:IsSecret() return false end
function E:MasqueButton() end
function E:MasqueReSkin() end
function E:ApplyMover() end

local consumable = ReadFile("EldoUI/Modules/ConsumableBar.lua")
local chunk = assert(loadstring(table.concat({
	"local E, M, CreateFrame, GameTooltip_Hide = ...",
	"local ShowTooltip = function() end",
	"local MASQUE_GROUP = 'Consumable Bar'",
	"local max = math.max",
	"local function Signature() return 'applied' end",
	Between(consumable, "function M:CreateButton(category, index)", "function M:BuildBar()", "ConsumableBar.lua"),
	Between(consumable, "local shapeRequest = 0", "-- Events and lifecycle", "ConsumableBar.lua"),
}, "\n"), "=ConsumableBar.lua parts"))

local CATEGORIES = {
	{ key = "food", index = 1 }, { key = "drink", index = 2 }, { key = "healthPotion", index = 3 },
	{ key = "healthstone", index = 6 }, { key = "mount", index = 8 },
}
local M = {
	db = { food = true, drink = true, healthPotion = true, healthstone = true, mount = true, hideEmpty = true, buttonSize = 32,
		spacing = 4, vertical = false, masque = false },
	bar = NewFrame("Frame", "EldoUI_ConsumableBar"), categoryByKey = {}, buttons = {}, active = true,
}
function M.ForClass() return true end
function M:OrderedButtons() return self.buttons end
chunk(E, M, CreateFrame, function() end)

-- What the game would do for this click: the action and the value of `what` (item or spell), or nil.
local function Resolve(button, name, prefix, suffix)
	local a = button.attributes
	for _, key in ipairs({ prefix .. name .. suffix, "*" .. name .. suffix, prefix .. name .. "*", "*" .. name .. "*", name }) do
		if a[key] ~= nil and a[key] ~= "" then return a[key] end
	end
end
local MODIFIERS = { "", "shift-", "ctrl-", "alt-", "alt-ctrl-shift-" }

---------------------------------------------------------------------------
-- After CreateButton
---------------------------------------------------------------------------
for _, category in ipairs(CATEGORIES) do
	local button = M:CreateButton(category, category.index)
	M.buttons[#M.buttons + 1] = button
	M.categoryByKey[category.key] = category
end
for _, button in ipairs(M.buttons) do
	for _, prefix in ipairs(MODIFIERS) do
		Check(Resolve(button, "type", prefix, "1") == "item", button.key .. ": a new button's left click with '" .. prefix .. "' has the item action")
		Check(Resolve(button, "type", prefix, "2") == nil, button.key .. ": a new button's right click with '" .. prefix .. "' uses nothing")
	end
	Check(button.attributes.type1 == nil, button.key .. ": no plain type1 (it would hide the action from modified clicks)")
end

---------------------------------------------------------------------------
-- After ApplySecure: items and a mount spell
---------------------------------------------------------------------------
M.chosen = { food = { id = 117 }, drink = { id = 159 }, healthPotion = { id = 118 }, mount = { spell = 458 } }
M:ApplySecure()
local expect = { food = { "item", "item", "item:117" }, drink = { "item", "item", "item:159" }, healthPotion = { "item", "item", "item:118" },
	mount = { "spell", "spell", 458 } }
for _, button in ipairs(M.buttons) do
	local e = expect[button.key]
	for _, prefix in ipairs(MODIFIERS) do
		if e then
			Check(Resolve(button, "type", prefix, "1") == e[1], button.key .. ": left click with '" .. prefix .. "' has the " .. e[1] .. " action")
			Check(Resolve(button, e[2], prefix, "1") == e[3], button.key .. ": left click with '" .. prefix .. "' finds " .. tostring(e[3]))
		end
		Check(Resolve(button, "type", prefix, "2") == nil, button.key .. ": right click with '" .. prefix .. "' uses nothing")
	end
	Check(button.attributes.type1 == nil, button.key .. ": ApplySecure leaves no plain type1")
end
local healthstone
for _, button in ipairs(M.buttons) do if button.key == "healthstone" then healthstone = button end end
Check(healthstone and not healthstone.shown and Resolve(healthstone, "item", "ctrl-", "1") == nil,
	"a button with nothing to use is hidden and has no item, also with a modifier")

print(("%d checks passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
