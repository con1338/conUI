-- EldoUI Gathering: export, import and send nodes through the share kit
-- (Core/Share.lua, share kind "gathernodes", prefix "!EUG1!").
--
--   /eui gather export [all]             copy box with this zone's (or every) node
--   /eui gather import                   paste box; shows what it holds first
--   /eui gather send <party|guild|name> [all]   needs "Allow sending nodes" on
--
-- A string holds only nodes: map id, position, name, kind, count, last time.
-- No character name is added. Imported nodes are added to yours: a node you
-- already have keeps its place and takes the higher count; nothing is
-- removed. Imported nodes say "From an import" until you gather them.
-- Sending is opt-in (shareSend, default off), one click per send, and the
-- receiver must accept (the share kit only listens to group, guild and
-- friends).
local _, E = ...
local L = E.L
local M = E.Gathering
local WP = E.Waypoints

local floor = math.floor
local KIND = "gathernodes"
local MAX_IMPORT = 50000
local MAX_NAME = 100

local function Round4(value) return floor(value * 10000 + 0.5) / 10000 end

-- The data a string carries: { maps = { [mapID] = { { x, y, n, k, c, t } } } }.
-- scope: "all", a map id, or nil (nothing).
function M:ShareData(scope)
	local maps = self:Store().maps
	local picked = {}
	if scope == "all" then
		picked = maps
	else
		local mapID = tonumber(scope)
		if mapID and maps[mapID] then picked = { [mapID] = maps[mapID] } end
	end
	local out, count = {}, 0
	for mapID, list in pairs(picked) do
		local rows = {}
		for _, node in ipairs(list) do
			if type(node.n) == "string" and self.kindByKey[node.k] then
				rows[#rows + 1] = { Round4(node.x), Round4(node.y), node.n, node.k, node.c or 1, node.t }
			end
		end
		if #rows > 0 then
			out[mapID] = rows
			count = count + #rows
		end
	end
	if count == 0 then return nil end
	return { maps = out }
end

-- Checks a decoded string and returns { [mapID] = { node, ... } } with only
-- sane rows, plus the number of rows kept.
function M:ReadShareData(data)
	local result, kept = {}, 0
	local maps = type(data) == "table" and data.maps
	if type(maps) ~= "table" then return result, 0 end
	for mapID, rows in pairs(maps) do
		mapID = tonumber(mapID)
		if mapID and mapID > 0 and mapID == floor(mapID) and type(rows) == "table" then
			for _, row in ipairs(rows) do
				if kept >= MAX_IMPORT then return result, kept end
				local x, y, name, kind, count, when
				if type(row) == "table" then x, y, name, kind, count, when = row[1], row[2], row[3], row[4], row[5], row[6] end
				if type(x) == "number" and type(y) == "number" and x >= 0 and x <= 1 and y >= 0 and y <= 1
					and type(name) == "string" and self.kindByKey[kind] then
					name = name:gsub("|", ""):sub(1, MAX_NAME)
					if name ~= "" then
						count = type(count) == "number" and count >= 1 and floor(count) or 1
						result[mapID] = result[mapID] or {}
						table.insert(result[mapID], { x = x, y = y, n = name, k = kind, c = math.min(count, 9999),
							t = type(when) == "number" and when > 0 and floor(when) or nil })
						kept = kept + 1
					end
				end
			end
		end
	end
	return result, kept
end

-- Add the nodes of a string to yours. Returns added, matched.
function M:ImportNodes(data)
	local rows = self:ReadShareData(data)
	local added, matched = 0, 0
	for mapID, list in pairs(rows) do
		-- One lookup per map, so a large import stays quick.
		local index = self:NearIndex(mapID)
		for _, row in ipairs(list) do
			local node, point = index:Find(row.x, row.y, row.n)
			if node then
				node.c = math.max(node.c or 1, row.c)
				if row.t and (not node.t or row.t > node.t) then node.t = row.t end
				matched = matched + 1
			else
				local nodes = self:Nodes(mapID)
				node = { x = row.x, y = row.y, n = row.n, k = row.k, c = row.c, t = row.t, s = true }
				nodes[#nodes + 1] = node
				index:Add(node, point)
				added = added + 1
			end
		end
	end
	self:RefreshPins()
	return added, matched
end

-- Lines for the import confirmation.
function M:DescribeShareData(data)
	local rows, total = self:ReadShareData(data)
	local maps = {}
	for mapID, list in pairs(rows) do
		local byKind = {}
		for _, row in ipairs(list) do byKind[row.k] = (byKind[row.k] or 0) + 1 end
		local parts = {}
		for _, kind in ipairs(self.KINDS) do
			if byKind[kind.key] then parts[#parts + 1] = ("%d %s"):format(byKind[kind.key], L[kind.label]:lower()) end
		end
		maps[#maps + 1] = { name = WP.MapName(mapID), text = table.concat(parts, ", ") }
	end
	table.sort(maps, function(a, b) return a.name < b.name end)
	local lines = { L["%d nodes on %d maps."]:format(total, #maps) }
	for i, map in ipairs(maps) do
		if i > 8 then
			lines[#lines + 1] = L["...and %d more maps."]:format(#maps - 8)
			break
		end
		lines[#lines + 1] = ("%s: %s"):format(map.name, map.text)
	end
	lines[#lines + 1] = L["They are added to your nodes. Nothing you have is removed."]
	return lines
end

if E.RegisterShareKind then
	E:RegisterShareKind(KIND, {
		prefix = "!EUG1!",
		version = 1,
		title = function() return L["Gathering nodes"] end,
		build = function(scope) return M:ShareData(scope) end,
		describe = function(data) return M:DescribeShareData(data) end,
		apply = function(data)
			local added, matched = M:ImportNodes(data)
			E:Print(L["Gathering: %d nodes added, %d matched nodes you have."]:format(added, matched))
		end,
	})
end

local function ScopeArg(scope)
	if scope == "all" then return "all" end
	return tonumber(scope) and tostring(scope) or nil
end

function M:Export(scope)
	local arg = ScopeArg(scope)
	if not (arg and self:ShareData(arg)) then
		E:Print(arg == "all" and L["No gathering nodes to export yet."] or L["No gathering nodes on this map yet."])
		return
	end
	E:ShowExport("share:" .. KIND .. ":" .. arg)
end

function M:ShowImport()
	if E.ShowPasteBox then
		E:ShowPasteBox(L["Import gathering nodes"], L["Paste a node string (Ctrl+V) and click Save. You see what it holds before anything is added."],
			function(text) E:ImportString(text) end)
	elseif E.ShowImport then
		E:ShowImport()
	end
end

-- The share kit's target for the "Send to" option, or for a typed word.
function M:SendTarget(word)
	word = strtrim(word or "")
	if word == "" then
		local to = self.db.shareTo
		if to == "guild" then return "GUILD" end
		if to == "player" then return strtrim(self.db.sharePlayer or "") end
		return IsInRaid() and "RAID" or "PARTY"
	end
	local upper = word:upper()
	if upper == "GROUP" or upper == "PARTY" or upper == "RAID" then return IsInRaid() and "RAID" or "PARTY" end
	if upper == "GUILD" then return "GUILD" end
	return word
end

function M:Send(scope, word)
	if not self.db.shareSend then
		E:Print(L["Sending nodes is off. Turn on \"Allow sending nodes\" under /eui > Gathering."])
		return false
	end
	local arg = ScopeArg(scope)
	if not (arg and self:ShareData(arg)) then
		E:Print(arg == "all" and L["No gathering nodes to send yet."] or L["No gathering nodes on this map yet."])
		return false
	end
	return E:SendShare("share:" .. KIND .. ":" .. arg, self:SendTarget(word))
end
