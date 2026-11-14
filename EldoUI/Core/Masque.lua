-- EldoUI and Masque outside the action bars.
--
-- Masque (an optional addon) skins buttons through its public API: a group
-- per set of buttons (Masque:Group, shown under "EldoUI" in Masque's own
-- options) and group:AddButton with the button's parts. The action bars have
-- their own switch (LibActionButton adds itself, Modules/ActionBars). The
-- Consumable Bar, the shaman totem and cooldown bars and Quickdraw hand their
-- buttons over here when their "Use Masque" switch is on (off by default; it
-- takes effect after a reload) and Masque is loaded:
--
--   E:Masque()                                 Masque, or nil
--   E:MasqueButton(group, button, parts, kind) true when Masque took the button
--   E:MasqueReSkin(group)                      after the module sized its buttons
--   E:Masqued(button)                          true for a button Masque draws
--
-- A button Masque takes loses EldoUI's E:SetTemplate box for good
-- (E:DropTemplate, Core/Media.lua), so a module's later repaint or a new UI
-- scale doesn't draw it over the skin. Masque sizes a skin from the button's
-- size when it skins it, so a module calls E:MasqueReSkin once its buttons
-- have their size. A failing Masque call leaves the button in EldoUI's look.
local _, E = ...

-- The description of every module's "Use Masque" switch.
E.MASQUE_OPTION_DESC = "When the Masque addon is loaded, let it skin these buttons (Masque lists them under EldoUI). EldoUI's own button art steps aside." -- no-L (translated where shown)

local groups = {}                                    -- group name -> Masque group
local skinned = setmetatable({}, { __mode = "k" })  -- button -> its group

function E:Masque()
	local stub = _G.LibStub
	return stub and stub("Masque", true) or nil
end

-- The Masque group "EldoUI" > name, made once; nil without Masque.
function E:MasqueGroup(name)
	if groups[name] then return groups[name] end
	local masque = self:Masque()
	if not (masque and masque.Group) then return nil end
	local ok, group = pcall(masque.Group, masque, "EldoUI", name)
	if not ok or type(group) ~= "table" then return nil end
	groups[name] = group
	return group
end

-- Hand a button to Masque. parts: Masque's region names, e.g.
-- { Icon = texture, Cooldown = cooldown, Count = fontString, HotKey = ...,
-- Highlight = texture }; kind: Masque's button type ("Action", "Item").
function E:MasqueButton(name, button, parts, kind)
	if skinned[button] then return true end
	local group = self:MasqueGroup(name)
	if not (group and group.AddButton) then return false end
	if not pcall(group.AddButton, group, button, parts, kind) then return false end
	skinned[button] = group
	self:DropTemplate(button)
	return true
end

function E:MasqueReSkin(name)
	local group = groups[name]
	if group and group.ReSkin then pcall(group.ReSkin, group) end
end

function E:Masqued(button)
	return skinned[button] ~= nil
end
