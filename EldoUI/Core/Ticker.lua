-- EldoUI shared ticker: one OnUpdate for the whole addon instead of one
-- per feature. A feature that needs to run every so often subscribes at a
-- period; the ticker calls it when that much time has passed. While
-- nothing is subscribed the ticker's OnUpdate is unhooked, so an idle
-- EldoUI does no work at all between frames.
--
--   local T = E.Ticker
--   T:Subscribe(key, period, fn[, owner])  fn(elapsed) about every `period`
--                                          seconds (0: every frame); one
--                                          subscription per key, a second
--                                          call with the same key replaces
--                                          it. Returns true.
--   T:Unsubscribe(key)                     ends it; true when there was one
--   T:UnsubscribeOwner(owner)              ends every subscription of owner
--                                          (a module switched off); returns
--                                          how many ended
--   T:IsSubscribed(key)                    true while key has a subscription
--   T:Count([owner])                       subscriptions, all or one owner's
--   T:IsRunning()                          true while the OnUpdate is hooked
--   T:Stats()                              frames handled and calls made
--
-- `elapsed` is the time since that subscriber was last called (or since it
-- subscribed). A call that fails is reported and the others still run.
-- Subscribing or unsubscribing from inside a call is safe: a new
-- subscription starts on the next frame, one ended is not called again.
-- Written from scratch for EldoUI.
local _, E = ...

local T = {}
E.Ticker = T

local frame = CreateFrame("Frame")
local list = {}  -- subscriptions in the order they were made
local byKey = {} -- key -> subscription
local walking = false -- a frame is being handled right now
local dirty = false -- a subscription ended while walking: compact afterwards
local frames, calls = 0, 0

local OnUpdate

local function Hook()
	if not frame:GetScript("OnUpdate") then frame:SetScript("OnUpdate", OnUpdate) end
end

local function Unhook()
	if frame:GetScript("OnUpdate") then frame:SetScript("OnUpdate", nil) end
end

local function Compact()
	if walking then
		dirty = true
		return
	end
	local kept = {}
	for _, sub in ipairs(list) do
		if not sub.ended then kept[#kept + 1] = sub end
	end
	list = kept
	dirty = false
	if #list == 0 then Unhook() end
end

OnUpdate = function(_, elapsed)
	frames = frames + 1
	elapsed = tonumber(elapsed) or 0
	-- Walk this frame's list as it stands now; a subscription made during
	-- the walk goes to the end and waits for the next frame.
	local current, count = list, #list
	walking = true
	for index = 1, count do
		local sub = current[index]
		if not sub.ended then
			sub.waited = sub.waited + elapsed
			if sub.waited >= sub.period then
				local waited = sub.waited
				sub.waited = 0
				calls = calls + 1
				local ok, err = pcall(sub.fn, waited)
				if not ok then geterrorhandler()(err) end
			end
		end
	end
	walking = false
	if dirty or #list == 0 then Compact() end
end

function T:Subscribe(key, period, fn, owner)
	assert(key ~= nil, "EldoUI.Ticker:Subscribe(key, period, fn): key is required")
	assert(type(fn) == "function", "EldoUI.Ticker:Subscribe(key, period, fn): fn must be a function")
	period = tonumber(period) or 0
	if period < 0 then period = 0 end
	local old = byKey[key]
	local sub = { key = key, period = period, fn = fn, owner = owner, waited = 0 }
	byKey[key] = sub
	list[#list + 1] = sub
	if old then
		old.ended = true
		Compact()
	end
	Hook()
	return true
end

function T:Unsubscribe(key)
	local sub = key ~= nil and byKey[key]
	if not sub then return false end
	byKey[key] = nil
	sub.ended = true
	Compact()
	return true
end

function T:UnsubscribeOwner(owner)
	if owner == nil then return 0 end
	local ended = 0
	for key, sub in pairs(byKey) do
		if sub.owner == owner then
			byKey[key] = nil
			sub.ended = true
			ended = ended + 1
		end
	end
	if ended > 0 then Compact() end
	return ended
end

function T:IsSubscribed(key)
	return key ~= nil and byKey[key] ~= nil
end

function T:Count(owner)
	local count = 0
	for _, sub in pairs(byKey) do
		if owner == nil or sub.owner == owner then count = count + 1 end
	end
	return count
end

function T:IsRunning()
	return frame:GetScript("OnUpdate") ~= nil
end

function T:Stats()
	return { frames = frames, calls = calls, subscriptions = self:Count() }
end
