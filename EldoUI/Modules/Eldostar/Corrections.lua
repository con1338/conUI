-- Eldostar: corrections where WoW: Forever differs from a guide.
--
-- The guide data ships exactly as the community guides wrote it. Where the
-- game itself shows a guide is wrong or incomplete, the fix lives here and
-- applies to the loaded data, before Eldostar reads it:
--
--   tips      { find, text, current }: `find` becomes `text`; an empty text
--             takes it out. Current markers recognize text corrected upstream.
--   collects  item IDs added to the guide's collection list
--   notes     { step title, line }: a note goal added to that step, or to
--             the last step that buys when the title is nil
--
-- Each correction names the game data it rests on. Written from scratch for
-- EldoUI.
local _, E = ...
local M = E:GetModule("Eldostar")
local CORRECTED_SOURCES = {
	["89c62f73905df2f2218ff791bfe9b4671ab7ea29"] = true,
	["19bd636e7d6f33231770f6029c76d2d4dfc63798"] = true,
}

local RIDING_OTHER = "Your race's riding comes with it; another race's mounts need that race's riding, taught by its riding trainer once you are Exalted with that race."

-- Each racial mount item needs its race's riding spell (the item's
-- RequiredAbility); the other races of a side train it at that race's
-- riding trainer.
local function RacialMounts(side, riding, trainer, faction)
	return {
		tips = { { ("The Forever client lets every %s race ride these."):format(side),
			("Each mount needs %s: it comes with this race's riding, and other %s races learn it from %s once Exalted with %s (the trainer shows the price)."):format(riding, side, trainer, faction),
			{ riding, trainer, "Exalted with " .. faction } } },
	}
end

local function NewColors(collects, step, line)
	return { collects = collects, notes = { { step, line } } }
end

M.CORRECTIONS = {
	-- The Drakefire Amulet is the attunement for both factions; Blood of the
	-- Black Dragon Champion is the quest item that leads to it.
	["forever/legacy/legacy-challenges"] = {
		tips = { { "In Classic her lair needs an attunement: Drakefire Amulet for the Alliance, Blood of the Black Dragon Champion for the Horde.",
			"Each raider needs their own Drakefire Amulet in their bags to enter her lair: the Alliance chain ends with Haleh in Winterspring, the Horde chain with Rexxar in Desolace.",
			{ "Every raider needs the Drakefire Amulet", "Alliance chain", "Horde chain" } } },
	},
	-- Molten Core is not open on WoW: Forever.
	["forever/reputation/thorium-brotherhood"] = {
		tips = { { " Lothos Riftwaker at the Blackrock Mountain entrance offers attunement to the Molten Core.", "",
			{ "Molten Core", "not among the first raids", "until it opens, Dark Iron Ore is the way" } } },
	},
	["forever/alliance/40-50/01-stranglethorn-vale"] = {
		tips = {
			{ "Forever may let any race learn from any riding trainer (unconfirmed), such as Randal Hunter at Eastvale Logging Camp in Elwynn Forest.", RIDING_OTHER },
			{ "Forever may let any race learn from any riding trainer (unconfirmed).", RIDING_OTHER },
		},
	},
	["forever/horde/40-50/02-feralas"] = {
		tips = {
			{ "In Classic each race learns it from its own race's trainer: yours is ", "Your race's riding trainer teaches it: ",
				{ "Riding needs level 40", "Each race learns it from its own race's trainer:" } },
			{ "Forever may let any race learn from any riding trainer (not confirmed): try Kildar in Orgrimmar's Valley of Honor first, as he is the nearest, and skip this step if he teaches you.", RIDING_OTHER,
				{ "Riding needs level 40", "Each race learns it from its own race's trainer:" } },
		},
	},
	["forever/collectibles/mounts/alliance/horse"] = RacialMounts("Alliance", "Horse Riding", "Randal Hunter", "Stormwind"),
	["forever/collectibles/mounts/alliance/mechanostrider"] = RacialMounts("Alliance", "Mechanostrider Piloting", "Binjy Featherwhistle", "Gnomeregan Exiles"),
	["forever/collectibles/mounts/alliance/ram"] = RacialMounts("Alliance", "Ram Riding", "Ultham Ironhorn", "Ironforge"),
	["forever/collectibles/mounts/alliance/saber"] = {
		tips = RacialMounts("Alliance", "Tiger Riding", "Jartsam", "Darnassus").tips,
		collects = { 274706 },
	},
	["forever/collectibles/mounts/horde/kodo"] = {
		tips = RacialMounts("Horde", "Kodo Riding", "Kar Stormsinger", "Thunder Bluff").tips,
		collects = { 275993, 277960 },
		notes = { { nil, "White Kodo and Lavender Kodo are new Forever colors whose seller is not confirmed yet." } },
	},
	["forever/collectibles/mounts/horde/raptor"] = RacialMounts("Horde", "Raptor Riding", "Xar'Ti", "Darkspear Trolls"),
	["forever/collectibles/mounts/horde/skeletal-horse"] = {
		tips = RacialMounts("Horde", "Undead Horsemanship", "Velma Warnam", "Undercity").tips,
		collects = { 276063 },
		notes = { { nil, "The Black Skeletal Horse is a new Forever color whose seller is not confirmed yet." } },
	},
	["forever/collectibles/mounts/horde/wolf"] = RacialMounts("Horde", "Wolf Riding", "Kildar", "Orgrimmar"),
	["forever/collectibles/mounts/horde/skeletal-warhorse"] = NewColors({ 265838, 265839, 265840, 274799 }, nil,
		"The Green, Dark and Purple Skeletal Horses and the Ochre Skeletal Warhorse are new Forever colors (200g in the client) whose seller is not confirmed yet."),
	["forever/collectibles/mounts/neutral/galestrider"] = {
		tips = { { "Galestriders need level 40 and Riding (Galestrider Riding comes with it in the Forever client). Any riding trainer of your faction teaches it;",
			"Galestriders need level 40, Riding and Galestrider Riding: the Skyborne know it from the start, and every other race can train it. Any riding trainer of your faction teaches Riding;",
			{ "riding one also takes Galestrider Riding", "only the Skyborne get with Riding", "how is not known yet" } } },
		collects = { 269682 },
		notes = { { "Genn Fairweather", "Regal Galestrider (20g in the client) is a new Forever color whose seller is not confirmed yet." } },
	},
	["forever/collectibles/mounts/neutral/swift-galestrider"] = NewColors({ 269673 }, "Genn Fairweather",
		"Swift Regal Galestrider (200g in the client) is a new Forever color whose seller is not confirmed yet."),
}

-- Plain-text replace of every `find` in `text`.
local function Replace(text, find, by)
	local out, from = {}, 1
	while true do
		local at, stop = text:find(find, from, true)
		if not at then break end
		out[#out + 1] = text:sub(from, at - 1)
		out[#out + 1] = by
		from = stop + 1
	end
	out[#out + 1] = text:sub(from)
	return table.concat(out)
end

-- Applies M.CORRECTIONS to the loaded guide data (the raw table of
-- EldoUI_GuideData), once. Anything that does not fit is left alone and
-- listed in M.correctionMisses ("<guide id>: <what>"), so a new guide
-- release that already fixed or reworded a line shows up in the tests.
-- Current source markers retain upstream fixes without changing their text.
function M.ApplyCorrections(raw)
	if type(raw) ~= "table" or rawget(raw, "eldouiCorrected") then return end
	local list = rawget(raw, "guides")
	if type(list) ~= "table" then return end
	local source = rawget(raw, "source")
	local commit = type(source) == "table" and rawget(source, "commit")
	local reviewed = type(commit) == "string" and CORRECTED_SOURCES[commit] == true
	local misses, seen = {}, {}
	M.correctionMisses = misses
	for index = 1, #list do
		local guide = rawget(list, index)
		local id = type(guide) == "table" and rawget(guide, "id")
		local fix = id and M.CORRECTIONS[id]
		local steps = fix and rawget(guide, "steps")
		if fix then
			seen[id] = true
			if type(steps) == "table" then
				local hits = {}
				for _, step in ipairs(steps) do
					if type(step) == "table" and type(step.tip) == "string" then
						for number, pair in ipairs(fix.tips or {}) do
							if step.tip:find(pair[1], 1, true) then
								hits[number] = true
								step.tip = Replace(step.tip, pair[1], pair[2])
							elseif reviewed and pair[3] then
								local matches = true
								for _, marker in ipairs(pair[3]) do
									if not step.tip:find(marker, 1, true) then matches = false break end
								end
								if matches then hits[number] = true end
							end
						end
					end
				end
				for number, pair in ipairs(fix.tips or {}) do
					if not hits[number] then misses[#misses + 1] = id .. ": " .. pair[1] end
				end
				-- A note goes on the named step, or on the last one that buys.
				for _, note in ipairs(fix.notes or {}) do
					local target
					for _, step in ipairs(steps) do
						if type(step) == "table" and type(step.goals) == "table" then
							if note[1] and step.title == note[1] then target = step break end
							if not note[1] then
								for _, goal in ipairs(step.goals) do
									if type(goal) == "table" and goal.kind == "buy" then target = step end
								end
							end
						end
					end
					if target then
						target.goals[#target.goals + 1] = { kind = "note", text = note[2] }
					else
						misses[#misses + 1] = id .. ": no step for the note " .. note[2]
					end
				end
			end
			if fix.collects then
				local collects = type(guide.collects) == "table" and guide.collects or {}
				local have = {}
				for _, itemID in ipairs(collects) do have[itemID] = true end
				for _, itemID in ipairs(fix.collects) do
					if not have[itemID] then collects[#collects + 1] = itemID end
				end
				guide.collects = collects
			end
		end
	end
	for guideID in pairs(M.CORRECTIONS) do
		if not seen[guideID] then misses[#misses + 1] = guideID .. ": guide not in the data" end
	end
	rawset(raw, "eldouiCorrected", true)
end
