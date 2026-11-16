-- EldoUI Notifications: a profession at its rank cap.
--
-- At 75/75, 150/150 or 225/225 a profession gains no skill until the next
-- rank is trained, and the game does not say so. One chat line, and a card
-- in the EldoUI alert lane when that lane is on, says which rank to train.
-- Once per profession and cap for each character; a cap of 300 has no next
-- rank and says nothing. With the early notice on, the line also comes five
-- points before the cap. The rank and cap are the game's own (the
-- profession list), so no table ships. A reminder only: nothing trains.
--
-- Written from scratch for EldoUI; no code, strings or data from other addons.
local _, E = ...
local L = E.L
local M = E:GetModule("Notifications")
local U = M.util

E:RegisterPrivate("professionCap", { told = {} })

local TOP_CAP, EARLY = 300, 5
-- The rank that lifts each cap, by the game's own rank name (the client
-- has no Danish names for them, like the profession names).
local NEXT_RANK = { [75] = "Journeyman", [150] = "Expert", [225] = "Artisan" }

local function Plain(value)
	if U.Secret(value) then return nil end
	return value
end

-- The character's professions as { name, rank, max, icon }, from the
-- game's profession list (primary, then Cooking, First Aid and Fishing).
function M.ProfessionRanks()
	local list = {}
	if not (GetProfessions and GetProfessionInfo) then return list end
	local indexes = { pcall(GetProfessions) }
	if not table.remove(indexes, 1) then return list end
	for slot = 1, 6 do
		local index = indexes[slot]
		if type(index) == "number" then
			local ok, name, icon, rank, max = pcall(GetProfessionInfo, index)
			name, rank, max = ok and Plain(name), ok and tonumber(Plain(rank)), ok and tonumber(Plain(max))
			if type(name) == "string" and name ~= "" and rank and max and max > 0 then
				list[#list + 1] = { name = name, rank = rank, max = max, icon = icon }
			end
		end
	end
	return list
end

-- The line for one profession, or nil: at its cap with a next rank, or
-- (early notice on) within five points of it.
function M.ProfessionCapText(entry)
	local nextRank = NEXT_RANK[entry.max]
	if entry.max >= TOP_CAP or not nextRank then return nil end
	if entry.rank >= entry.max then
		return L["%s is at %d/%d. Train %s %s to keep gaining skill."]:format(entry.name, entry.rank, entry.max, nextRank, entry.name), "cap"
	end
	if M.db.professionCap.early and entry.rank >= entry.max - EARLY then
		return L["%s is at %d/%d: train %s %s soon."]:format(entry.name, entry.rank, entry.max, nextRank, entry.name), "early"
	end
end

-- Says what changed since the last reading; returns the lines said.
function M:CheckProfessionCaps()
	if not (self.active and self.db.professionCap.enabled and not InCombatLockdown()) then return {} end
	local store = E:GetPrivate("professionCap")
	if not store then return {} end
	store.told = type(store.told) == "table" and store.told or {}
	local said = {}
	for _, entry in ipairs(M.ProfessionRanks()) do
		local text, kind = M.ProfessionCapText(entry)
		local key = kind and (entry.max .. ":" .. kind)
		if not text then
			-- Below the warning line or past the cap: the next cap tells again.
			if store.told[entry.name] and not tostring(store.told[entry.name]):find("^" .. entry.max .. ":") then store.told[entry.name] = nil end
		elseif store.told[entry.name] ~= key and not (kind == "early" and store.told[entry.name] == entry.max .. ":cap") then
			store.told[entry.name] = key
			said[#said + 1] = text
			E:Print(text)
			if U.Allowed("alert-toasts", "replace") then
				self:PushToast({ title = L["Train the next rank"], text = entry.name, sub = ("%d/%d"):format(entry.rank, entry.max), icon = entry.icon or E.media.icon })
			end
		end
	end
	return said
end

U.On("SKILL_LINES_CHANGED", function()
	E:Debounce("notifications-profession-cap", 1, function() M:CheckProfessionCaps() end)
end)
U.On("PLAYER_ENTERING_WORLD", function(_, login, reload)
	if login or reload then E:Debounce("notifications-profession-cap", 5, function() M:CheckProfessionCaps() end) end
end)
