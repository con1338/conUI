-- Battleground Timers: /eui probe bg, a dump of what the game reports in
-- a battleground, for the in-game checks: every top-center widget
-- (ID, type, text and values) and every map POI (name, atlas, texture
-- index, faction, game time). Read-only, prints to the chat frame only
-- when the player types the command; works with the module on or off.
-- The last 20 dumps are also kept in EldoUIDB.bgProbe (plain values, secret
-- ones as "<secret>"), so one SavedVariables file after a few matches holds
-- them all.
-- `/eui probe bg clear` removes them.
--
-- /eui probe is shared: probes register with E:RegisterProbe (Core/Probes.lua).
local _, E = ...
local L = E.L
local Key = E.Key
local M = E:GetModule("Battlegrounds")
local IsSecret = M.IsSecret

local function Show(value)
	if IsSecret(value) then return "<secret>" end
	if value == nil then return "-" end
	return tostring(value)
end

local function Line(text) E:Print(text) end

M.PROBE_KEEP = 20

E:RegisterStore("bgProbe", { owner = "Battlegrounds", version = 1, versionKey = "version",
	shape = "dumps: the last probe dumps, oldest first; only the clear command removes them all" })

-- A value as plain saved data.
local function Plain(value)
	if IsSecret(value) then return "<secret>" end
	local kind = type(value)
	if kind == "number" or kind == "string" or kind == "boolean" then return value end
	if value ~= nil then return tostring(value) end
end

-- Enum.UIWidgetVisualizationType number -> name.
local function WidgetTypeNames()
	local names = {}
	local enum = Enum and Enum.UIWidgetVisualizationType
	if type(enum) == "table" then
		for name, value in pairs(enum) do names[value] = name end
	end
	return names
end

-- The visualization info getter for a widget type name.
local function Getter(typeName)
	local api = C_UIWidgetManager
	if not (api and typeName) then return nil end
	return api["Get" .. typeName .. "WidgetVisualizationInfo"] or api["Get" .. typeName .. "VisualizationInfo"]
end

local WIDGET_FIELDS = { "text", "leftBarValue", "leftBarMax", "rightBarValue", "rightBarMax", "barValue", "barMax",
	"state", "shownState", "hasTimer", "orderIndex" }

function M:ProbeWidgets(record)
	local api = C_UIWidgetManager
	local setID = M.Read(api and api.GetTopCenterWidgetSetID)
	Line(L["Top-center widget set: %s"]:format(Show(setID)))
	if record then record.widgetSet, record.widgets = Plain(setID), {} end
	local list = setID and M.Read(api.GetAllWidgetsBySetID, setID)
	if type(list) ~= "table" or #list == 0 then
		Line(L["  no widgets"])
		return
	end
	local names = WidgetTypeNames()
	for _, widget in ipairs(list) do
		local id, kind = widget.widgetID, widget.widgetType
		local typeName = (not IsSecret(kind)) and names[kind] or nil
		local parts = { ("  #%s %s (%s)"):format(Show(id), Show(typeName), Show(kind)) }
		local kept = record and { widgetID = Plain(id), type = typeName, widgetType = Plain(kind) }
		local getter = Getter(typeName)
		local info = getter and not IsSecret(id) and M.Read(getter, id)
		if type(info) == "table" then
			for _, field in ipairs(WIDGET_FIELDS) do
				if info[field] ~= nil then
					parts[#parts + 1] = ("%s=%s"):format(field, Show(info[field]))
					if kept then kept[field] = Plain(info[field]) end
				end
			end
		end
		if kept then record.widgets[#record.widgets + 1] = kept end
		Line(table.concat(parts, "  "))
	end
end

function M:ProbePOIs(record)
	local mapID = M.Read(C_Map.GetBestMapForUnit, "player")
	Line(L["Map %s points of interest:"]:format(Show(mapID)))
	if record then record.mapID, record.pois = Plain(mapID), {} end
	local ids = type(mapID) == "number" and M.Read(C_AreaPoiInfo.GetAreaPOIForMap, mapID)
	if type(ids) ~= "table" or #ids == 0 then
		Line(L["  no points of interest"])
		return
	end
	for _, id in ipairs(ids) do
		local info = not IsSecret(id) and M.Read(C_AreaPoiInfo.GetAreaPOIInfo, mapID, id)
		if type(info) == "table" then
			local timed = M.Read(C_AreaPoiInfo.IsAreaPOITimed, id)
			local left = timed and M.Read(C_AreaPoiInfo.GetAreaPOISecondsLeft, id) or nil
			Line(("  #%s %s  atlas=%s  textureIndex=%s  factionID=%s  timed=%s  secondsLeft=%s"):format(
				Show(id), Show(info.name), Show(info.atlasName), Show(info.textureIndex), Show(info.factionID),
				Show(timed), Show(left)))
			if record then
				record.pois[#record.pois + 1] = { poiID = Plain(id), name = Plain(info.name), atlas = Plain(info.atlasName),
					textureIndex = Plain(info.textureIndex), factionID = Plain(info.factionID), timed = Plain(timed),
					secondsLeft = Plain(left) }
			end
		end
	end
end

-- Adds one dump to EldoUIDB.bgProbe, the newest last, keeping PROBE_KEEP.
function M:KeepProbe(record)
	if type(EldoUIDB) ~= "table" then return end
	local store = type(EldoUIDB.bgProbe) == "table" and EldoUIDB.bgProbe or {}
	store.version = 1
	store.dumps = type(store.dumps) == "table" and store.dumps or {}
	store.dumps[#store.dumps + 1] = record
	while #store.dumps > M.PROBE_KEEP do table.remove(store.dumps, 1) end
	EldoUIDB.bgProbe = store
end

function M:Probe()
	local inInstance, kind = IsInInstance()
	local name, _, _, _, _, _, _, instanceID = GetInstanceInfo()
	Line(L["Battleground probe: %s (instance %s, type %s)"]:format(Show(name), Show(instanceID), Show(kind)))
	local version, build = GetBuildInfo()
	local record = {
		time = time and time() or nil, gameVersion = Plain(version), build = Plain(build),
		locale = GetLocale and GetLocale() or nil, instance = Plain(name), instanceID = Plain(instanceID),
		instanceType = Plain(kind), inBattleground = (inInstance and kind == "pvp") and true or false,
	}
	if not inInstance or kind ~= "pvp" then Line(L["  not in a battleground: widgets and points below may be empty"]) end
	local info = (not IsSecret(instanceID)) and M.MAPS[instanceID]
	Line(L["  EldoUI map data: %s"]:format(info and info.key or L["none (generic engines)"]))
	record.map = info and info.key or nil
	if info and M.AssaultTime then
		local known = self:MapInfo(instanceID)
		local assault = self:AssaultTime(known)
		Line(L["  assault time: %s s (public value %s s)"]:format(Show(assault), Show(info.assault)))
		record.assaultTime = Plain(assault)
	end
	self:ProbeWidgets(record)
	self:ProbePOIs(record)
	M:KeepProbe(record)
	Line(E:Plural(M.PROBE_KEEP, "Kept in the SavedVariables file after /reload (the last %d dump).", "Kept in the SavedVariables file after /reload (the last %d dumps)."):format(M.PROBE_KEEP))
	return record
end

---------------------------------------------------------------------------
-- /eui probe <what>
---------------------------------------------------------------------------
E:RegisterProbe("bg", Key("[clear]  battleground widgets and map points (the last 20 kept until /reload writes them)"), function(rest)
	if tostring(rest or ""):lower() == "clear" then
		if type(EldoUIDB) == "table" then EldoUIDB.bgProbe = nil end
		Line(L["Battleground probe dumps removed."])
		return
	end
	M:Probe()
end)
