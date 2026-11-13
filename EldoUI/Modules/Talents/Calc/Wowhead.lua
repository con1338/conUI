-- EldoUI Talent Planner: Wowhead talent calculator links.
--
--   https://www.wowhead.com/forever/talent-calc/<class>/<tree1>-<tree2>-<tree3>[_<order>]
--   (also /classic/talent-calc/... and the older classic.wowhead.com/talent-calc/...)
--
-- One digit per talent of a tree (its rank), trailing zeros and trailing
-- trees left out. The part after "_" keeps the buying order; it isn't read,
-- the plan gets a legal leveling order instead.
--
-- Talent order: the planner's reading order of each tree (row by row from
-- the top, left to right in a row). If the WoW: Forever calculator orders
-- a class's talents differently (for example the talent at 16 points),
-- ORDER below maps it: ORDER[class][tree] = { planner position per digit }.
local _, E = ...
local L = E.L
local C = E.Talents.Calc

local ORDER = {}

C.Register({
	key = "wowhead", site = "Wowhead", version = 1, order = ORDER,
	find = function(text)
		local lower = text:lower()
		if not lower:find("wowhead%.com") then return nil end
		local slug, build = lower:match("talent%-calc/(%a+)/([%w%-_]*)")
		if not slug then
			return { error = L["This Wowhead link holds no talent build. Copy the link from the talent calculator after you pick your talents."] }
		end
		local game = lower:match("wowhead%.com/([%a%-]+)/talent%-calc") or lower:match("//(%a+)%.wowhead%.com")
		if game == "www" then game = nil end
		if game and game ~= "classic" and game ~= "forever" and game ~= "classic-forever" then
			return { error = L["This Wowhead link is for another game version, whose talent trees differ from WoW: Forever's."] }
		end
		local digits, rest = build:match("^([%d%-]*)(.*)$")
		if rest ~= "" and rest:sub(1, 1) ~= "_" then digits = nil end
		if not digits or (digits == "" and build ~= "") then
			return { error = L["The talent part of this Wowhead link isn't in a form EldoUI reads."] }
		end
		return { class = C.SLUGS[slug], slug = slug, trees = C.SplitTrees(digits), game = game and game:find("forever") and "forever" or "classic",
			ordered = #rest > 1 and true or nil }
	end,
})
