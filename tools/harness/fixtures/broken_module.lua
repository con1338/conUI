-- A module that fails when it starts, for tools/harness/test_harness.lua:
-- the offline start must name it and fail.
local _, E = ...
local M = E:NewModule("HarnessBroken", { title = "Harness broken", defaults = { enabled = true } })

function M:OnEnable()
	local missing
	return missing.field -- harness-fixture-error
end
