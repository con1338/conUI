-- EldoUI Talent Planner: a bare talent string, "05050005-3200-".
--
-- The same digits a calculator link holds, without the link. It is read
-- for the class shown in the planner.
local _, E = ...
local L = E.L
local Key = E.Key
local C = E.Talents.Calc

C.Register({
	key = "digits", site = Key("Talent string"), version = 1,
	find = function(text)
		if not text:match("^[%d%-]+$") or not text:find("-", 1, true) or not text:find("%d") then return nil end
		return { trees = C.SplitTrees(text) }
	end,
})
