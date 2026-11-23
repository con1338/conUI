-- EldoUI tour helps (E.Tour, also EldoUI.Tour for plugins).
--
-- One engine for every "first time here" help in EldoUI, so they all look
-- and behave alike (DESIGN.md: one accent ring, one callout, the kit's
-- buttons). Two forms:
--
--   Tour:Run(key, steps[, opts])   the spotlight tour: the screen dims
--       except for a hole around the part being explained, an accent ring
--       marks it, and a callout beside it has the text with Back, Next and
--       Skip. steps = { { target = frame or fn, title = "...", text = "...",
--       before = fn, action = { label, fn, tip } or fn returning one } }
--   Tour:Spot(key, opts)   one small callout beside a frame, no dimming:
--       opts = { target = frame or fn (none: the middle of the screen),
--       title, text, buttons = { { label, fn, tip }, ... } (up to two, a
--       "Got it" closes it), side = "TOP" or "BOTTOM", onClose = fn(how),
--       follow = fn (called while it shows, e.g. to move a drawn copy) }
--
-- Both take opts.scope (the layout, style or pack the help belongs to),
-- opts.force (the player asked: shows again, even with tour helps off),
-- opts.seen (a table, or a function returning one, that keeps the seen
-- flags instead of the shared one: the Journal keeps its own), opts.title
-- and opts.skipTip (the tour's step line and Skip tooltip).
--
-- Once: a help shows once per key and scope, account-wide
-- (E.global.tourHelps.seen), so a new character, an alt or a copied profile
-- does not show a help the player already saw. One switch, Tour helps on
-- the General options page (E.global.tourHelps), turns every help off.
--
-- Calm: a help never starts in combat, in an instance, during a cinematic
-- or while the setup window is open, and only one shows at a time. A spot
-- help that can't show yet waits in a queue and shows when it can (its
-- frame on screen, combat over, the setup closed). Combat ends a help at
-- once: callouts and drawn copies are plain frames, but the screen is the
-- player's again.
--
--   Tour:Register(key, def)   a named help: def = { form = "spot" or
--       "tour", title, text, scope = fn, offer = fn(scope) that shows it,
--       replay = fn that shows it again for /eui tour, page and pageKey =
--       the options page (and row) /eui tour opens first }
--   Tour:Offer(key, ...)      runs a registered help's offer
--   Tour:Enabled(), Tour:SetEnabled(on), Tour:Seen(key[, scope]),
--   Tour:Reset() (every help shows again), Tour:Running(), Tour:End()
--   Tour:OnEnd(fn)            fn(form, key, how) after any help ends (a
--                             part whose own help waited can start it then)
--   /eui tour                 lists the helps; /eui tour <name> shows one
--                             again; /eui tour reset shows them all again
local _, E = ...
local L = E.L

local Tour = {}
E.Tour = Tour

local PAD = 4
local DIM = 0.55
local CALLOUT_W = 280
local QUEUE_TICK = 1

-- enabled: the Tour helps switch; seen: the helps already shown, by name
-- and scope.
local SETTINGS = { enabled = true, seen = {} }
E:RegisterGlobal("tourHelps", SETTINGS, { title = "Tour helps", desc = "The Tour helps switch and the tour helps already shown." })

local overlay      -- the spotlight tour (dims the screen)
local spotFrame    -- the spot help (a ring and a callout)
local current      -- { form, key, id, steps, index, target, opts }
local queue = {}   -- spot helps waiting to show, in order
local queueTicker
local registry, registryOrder = {}, {}
local replays, replayOrder = {}, {}

---------------------------------------------------------------------------
-- The switch and the seen flags
---------------------------------------------------------------------------
local function Settings()
	return E:GetGlobal("tourHelps") or SETTINGS
end

function Tour:Enabled()
	return E.global ~= nil and Settings().enabled ~= false
end

function Tour:SetEnabled(on)
	Settings().enabled = on and true or false
	if not on then
		wipe(queue)
		if current and not (current.opts and current.opts.force) then self:End("off") end
	end
end

local function SharedSeen()
	local settings = E:GetGlobal("tourHelps")
	if not settings then return {} end
	if type(settings.seen) ~= "table" then settings.seen = {} end
	return settings.seen
end

local function SeenStore(opts)
	local seen = opts and opts.seen
	if type(seen) == "function" then seen = seen() end
	return type(seen) == "table" and seen or SharedSeen()
end

-- The flag's name: the key, and its scope when it has one.
local function SeenID(key, scope)
	if scope ~= nil and scope ~= "" then return key .. "@" .. tostring(scope) end
	return key
end
Tour.SeenID = function(_, key, scope) return SeenID(key, scope) end

function Tour:Seen(key, scope, store)
	return SeenStore(store and { seen = store })[SeenID(key, scope)] == true
end

function Tour:MarkSeen(key, scope, store)
	SeenStore(store and { seen = store })[SeenID(key, scope)] = true
end

local resetHooks = {}
-- fn runs on Tour:Reset (a part that keeps its own seen flags clears them).
function Tour:OnReset(fn)
	resetHooks[#resetHooks + 1] = fn
end

function Tour:Reset()
	wipe(SharedSeen())
	for _, fn in ipairs(resetHooks) do
		local ok, err = pcall(fn)
		if not ok then geterrorhandler()(err) end
	end
end

---------------------------------------------------------------------------
-- When a help may start
---------------------------------------------------------------------------
local function InInstance()
	local inside = IsInInstance and IsInInstance()
	if E:IsSecret(inside) then return true end
	return inside and true or false
end

local function InCinematicNow()
	return (InCinematic and InCinematic()) or (IsInCinematicScene and IsInCinematicScene()) or false
end

local function SetupOpen()
	local window = E.Installer and E.Installer.GetWindow and E.Installer.GetWindow()
	return window ~= nil and window:IsShown() and true or false
end

-- Why no help may start now, or nil. A help the player asked for (force)
-- only waits for combat.
function Tour:Blocked(force)
	if InCombatLockdown() then return "combat" end
	if force then return nil end
	if InInstance() then return "instance" end
	if InCinematicNow() then return "cinematic" end
	if SetupOpen() then return "setup" end
	return nil
end

---------------------------------------------------------------------------
-- The frames: a ring around the part and a callout beside it
---------------------------------------------------------------------------
local function Accent()
	return unpack(E.media.accentColor)
end

local function Dim(parent)
	local texture = parent:CreateTexture(nil, "BACKGROUND")
	texture:SetColorTexture(0, 0, 0, DIM)
	return texture
end

local function Ring(parent)
	local ring = CreateFrame("Frame", nil, parent)
	E:SetTemplate(ring)
	ring:SetBackdropColor(0, 0, 0, 0)
	ring:EnableMouse(false)
	return ring
end

local function Callout(parent)
	local Kit = E.UIKit
	local size = E.tokens.size
	local callout = CreateFrame("Frame", nil, parent)
	callout:SetWidth(CALLOUT_W)
	callout:SetFrameLevel(parent:GetFrameLevel() + 10)
	callout:SetClampedToScreen(true)
	callout:EnableMouse(true)
	E:SetTemplate(callout)
	callout.step = Kit.Text(callout, size.tiny, "LEFT", "header")
	callout.step:SetPoint("TOPLEFT", 12, -10)
	callout.title = Kit.Text(callout, size.cardTitle, "LEFT")
	callout.title:SetWidth(CALLOUT_W - 24)
	callout.text = Kit.Text(callout, size.label, "LEFT", "secondary")
	callout.text:SetWidth(CALLOUT_W - 24)
	callout.text:SetSpacing(2)
	callout.text:SetWordWrap(true)
	return callout
end

-- Fit the title and text under the step line (or the top) and return the
-- height they take.
local function LayoutText(callout, title, text, hasStep)
	callout.step:SetShown(hasStep)
	callout.title:ClearAllPoints()
	if hasStep then
		callout.title:SetPoint("TOPLEFT", callout.step, "BOTTOMLEFT", 0, -4)
	else
		callout.title:SetPoint("TOPLEFT", 12, -10)
	end
	callout.title:SetText(title or "")
	callout.title:SetShown(title ~= nil)
	callout.text:ClearAllPoints()
	if title then
		callout.text:SetPoint("TOPLEFT", callout.title, "BOTTOMLEFT", 0, -6)
	elseif hasStep then
		callout.text:SetPoint("TOPLEFT", callout.step, "BOTTOMLEFT", 0, -6)
	else
		callout.text:SetPoint("TOPLEFT", 12, -10)
	end
	callout.text:SetText(text or "")
	local height = math.ceil(callout.text:GetStringHeight() or 30)
	if title then height = height + math.ceil(callout.title:GetStringHeight() or 16) + 6 end
	if hasStep then height = height + math.ceil(callout.step:GetStringHeight() or 12) + 4 end
	return height
end

-- The target's box on `frame`'s scale, padded and kept on screen.
local function TargetBox(target, frame)
	local scale = target:GetEffectiveScale() / frame:GetEffectiveScale()
	local left, right = target:GetLeft() * scale - PAD, target:GetRight() * scale + PAD
	local bottom, top = target:GetBottom() * scale - PAD, target:GetTop() * scale + PAD
	local width, height = frame:GetWidth(), frame:GetHeight()
	return math.max(0, left), math.min(width, right), math.max(0, bottom), math.min(height, top), width, height
end

-- The callout below the part when it fits there, else above (or the
-- other way round with side = "TOP"); centered on the part, on screen.
local function PlaceCallout(callout, frame, left, right, bottom, top, width, height, side)
	callout:ClearAllPoints()
	local calloutHeight = callout:GetHeight() or 120
	local x = math.max(CALLOUT_W / 2 + 8, math.min(width - CALLOUT_W / 2 - 8, (left + right) / 2))
	local below = bottom - calloutHeight - 12 > 0
	local above = top + calloutHeight + 12 < height
	if (side == "TOP" and above) or not below then
		callout:SetPoint("BOTTOM", frame, "BOTTOMLEFT", x, math.min(top + 10, height - calloutHeight))
	else
		callout:SetPoint("TOP", frame, "BOTTOMLEFT", x, bottom - 10)
	end
end

local function Visible(frame)
	return type(frame) == "table" and frame.IsVisible and frame:IsVisible() and frame:GetLeft() ~= nil
end

local function Resolve(target)
	if type(target) == "function" then
		local ok, frame = pcall(target)
		target = ok and frame or nil
	end
	if Visible(target) then return target end
end

local function Call(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- The spotlight tour
---------------------------------------------------------------------------
local function BuildOverlay()
	if overlay then return overlay end
	local Kit = E.UIKit
	overlay = CreateFrame("Frame", "EldoUITourOverlay", UIParent)
	overlay:SetAllPoints(UIParent)
	overlay:SetFrameStrata("FULLSCREEN_DIALOG")
	overlay:SetFrameLevel(100)
	overlay:EnableMouse(false)
	overlay:Hide()
	overlay.top, overlay.bottom, overlay.left, overlay.right = Dim(overlay), Dim(overlay), Dim(overlay), Dim(overlay)
	overlay.ring = Ring(overlay)
	local callout = Callout(overlay)
	callout.next = Kit.Button(callout, L["Next"], 70, 20, function() Tour:Step(1) end, L["Next"], L["The next part of the tour."])
	callout.next:SetPoint("BOTTOMRIGHT", -10, 10)
	callout.back = Kit.Button(callout, L["Back"], 60, 20, function() Tour:Step(-1) end, L["Back"], L["The part before."])
	callout.back:SetPoint("RIGHT", callout.next, "LEFT", -6, 0)
	callout.skip = Kit.Button(callout, L["Skip"], 60, 20, function() Tour:End("skip") end, L["Skip"],
		L["Ends the tour. /eui tour shows it again."])
	callout.skip:SetPoint("BOTTOMLEFT", 10, 10)
	callout.action = Kit.Button(callout, " ", 120, 20)
	callout.action:SetPoint("BOTTOMLEFT", callout.skip, "TOPLEFT", 0, 8)
	overlay.callout = callout

	-- Follow the part when its window moves or resizes; the tour ends
	-- when the part goes away (the window closed) instead of opening
	-- things again.
	overlay.elapsed = 0
	overlay:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + elapsed
		if self.elapsed < 0.1 then return end
		self.elapsed = 0
		if current and current.form == "tour" and current.target then
			if not current.target:IsVisible() then
				Tour:End("gone")
			else
				Tour:Place()
			end
		end
	end)
	return overlay
end

-- Hole, ring and callout around the current tour step's part.
function Tour:Place()
	if not (current and current.target) then return end
	if current.form == "spot" then
		self:PlaceSpot()
		return
	end
	local o = overlay
	local left, right, bottom, top, width, height = TargetBox(current.target, o)
	o.top:ClearAllPoints()
	o.top:SetPoint("TOPLEFT")
	o.top:SetPoint("BOTTOMRIGHT", o, "TOPRIGHT", 0, -(height - top))
	o.bottom:ClearAllPoints()
	o.bottom:SetPoint("BOTTOMLEFT")
	o.bottom:SetPoint("TOPRIGHT", o, "BOTTOMRIGHT", 0, bottom)
	o.left:ClearAllPoints()
	o.left:SetPoint("TOPLEFT", o, "BOTTOMLEFT", 0, top)
	o.left:SetPoint("BOTTOMRIGHT", o, "BOTTOMLEFT", left, bottom)
	o.right:ClearAllPoints()
	o.right:SetPoint("TOPLEFT", o, "BOTTOMLEFT", right, top)
	o.right:SetPoint("BOTTOMRIGHT", o, "BOTTOMRIGHT", 0, bottom)
	o.ring:ClearAllPoints()
	o.ring:SetPoint("BOTTOMLEFT", o, "BOTTOMLEFT", left, bottom)
	o.ring:SetPoint("TOPRIGHT", o, "BOTTOMLEFT", right, top)
	o.ring:SetBackdropBorderColor(Accent())
	PlaceCallout(o.callout, o, left, right, bottom, top, width, height)
	o.callout:SetBackdropBorderColor(Accent())
end

-- Show step `index`, or the next one on screen in `direction`.
local function ShowStep(index, direction)
	direction = direction or 1
	local steps = current.steps
	local opts = current.opts
	local Kit = E.UIKit
	while index >= 1 and index <= #steps do
		local step = steps[index]
		Call(step.before)
		local target = Resolve(step.target)
		if target then
			current.index, current.target = index, target
			local callout = overlay.callout
			callout.step:SetText(opts.title and (opts.title .. "  \194\183  " .. (L["%d of %d"]):format(index, #steps)) or (L["Tour %d/%d"]):format(index, #steps))
			local textHeight = LayoutText(callout, step.title, step.text, true)
			Kit.Tooltip(callout.skip, L["Skip"], opts.skipTip or L["Ends the tour. /eui tour shows it again."])
			callout.next:SetText(index < #steps and L["Next"] or L["Got it"])
			callout.back:SetShown(index > 1)
			local action = step.action
			if type(action) == "function" then action = action() end
			if type(action) == "table" then
				callout.action:SetText(action[1])
				callout.action:SetWidth(math.max(100, math.ceil((callout.action:GetFontString():GetStringWidth() or 80) + 20)))
				callout.action:SetScript("OnClick", function() Call(action[2]) end)
				Kit.Tooltip(callout.action, action[1], action[3])
				callout.action:Show()
			else
				callout.action:Hide()
			end
			callout:SetHeight(textHeight + 48 + (callout.action:IsShown() and 28 or 0))
			overlay:Show()
			Tour:Place()
			return true
		end
		index = index + direction
	end
	Tour:End("done")
	return false
end

function Tour:Step(direction)
	if not (current and current.form == "tour") then return end
	if direction > 0 and current.index >= #current.steps then
		self:End("done")
		return
	end
	ShowStep(current.index + direction, direction)
end

-- Start a tour. Returns true when its first step shows.
function Tour:Run(key, steps, opts)
	opts = type(opts) == "table" and opts or {}
	if type(key) ~= "string" or type(steps) ~= "table" or #steps == 0 then return false end
	if not opts.force then
		if not self:Enabled() or SeenStore(opts)[SeenID(key, opts.scope)] then return false end
		if current then return false end
	end
	if self:Blocked(opts.force) then return false end
	if current then self:End("replaced") end
	SeenStore(opts)[SeenID(key, opts.scope)] = true
	BuildOverlay()
	current = { form = "tour", key = key, id = SeenID(key, opts.scope), steps = steps, index = 0, opts = opts }
	return ShowStep(1, 1)
end

---------------------------------------------------------------------------
-- The spot help
---------------------------------------------------------------------------
local MAX_BUTTONS = 2

local function BuildSpot()
	if spotFrame then return spotFrame end
	local Kit = E.UIKit
	spotFrame = CreateFrame("Frame", "EldoUITourSpot", UIParent)
	spotFrame:SetAllPoints(UIParent)
	spotFrame:SetFrameStrata("FULLSCREEN_DIALOG")
	spotFrame:SetFrameLevel(100)
	spotFrame:EnableMouse(false)
	spotFrame:Hide()
	spotFrame.ring = Ring(spotFrame)
	local callout = Callout(spotFrame)
	callout.gotIt = Kit.Button(callout, L["Got it"], 80, 20, function() Tour:End("gotit") end)
	callout.gotIt:SetPoint("BOTTOMRIGHT", -10, 10)
	Kit.SetButtonKind(callout.gotIt, "primary")
	callout.buttons = {}
	for index = 1, MAX_BUTTONS do
		local button = Kit.Button(callout, " ", 100, 20)
		button:Hide()
		callout.buttons[index] = button
	end
	spotFrame.callout = callout
	spotFrame.elapsed = 0
	spotFrame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + elapsed
		if self.elapsed < 0.1 then return end
		self.elapsed = 0
		if not (current and current.form == "spot") then return end
		if current.target and not current.target:IsVisible() then
			Tour:End("gone")
			return
		end
		Call(current.opts.follow)
		Tour:PlaceSpot()
	end)
	return spotFrame
end

function Tour:PlaceSpot()
	if not (current and current.form == "spot" and spotFrame) then return end
	local f = spotFrame
	local callout = f.callout
	callout:SetBackdropBorderColor(Accent())
	if not current.target then
		f.ring:Hide()
		callout:ClearAllPoints()
		callout:SetPoint("CENTER", f, "CENTER", 0, f:GetHeight() / 6)
		return
	end
	local left, right, bottom, top, width, height = TargetBox(current.target, f)
	f.ring:ClearAllPoints()
	f.ring:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", left, bottom)
	f.ring:SetPoint("TOPRIGHT", f, "BOTTOMLEFT", right, top)
	f.ring:SetBackdropBorderColor(Accent())
	f.ring:Show()
	PlaceCallout(callout, f, left, right, bottom, top, width, height, current.opts.side)
end

-- The buttons of a spot help: beside Got it when they fit on its row,
-- else each on a row of its own above it. Each click closes the help and
-- runs its action. Returns the number of button rows.
local function LayoutButtons(callout, defs)
	local Kit = E.UIKit
	local shown, total = {}, callout.gotIt:GetWidth()
	for index, button in ipairs(callout.buttons) do
		local def = defs[index]
		button:ClearAllPoints()
		if def then
			local label = def[1] or def.label
			local fn, tip = def[2] or def.fn, def[3] or def.tip
			button:SetText(label)
			Kit.FitButton(button, 80)
			button:SetScript("OnClick", function()
				Tour:End("button")
				Call(fn)
			end)
			Kit.Tooltip(button, label, tip)
			button:Show()
			shown[#shown + 1] = button
			total = total + button:GetWidth() + 6
		else
			button:SetScript("OnClick", nil)
			button:Hide()
		end
	end
	local stacked = total > CALLOUT_W - 20
	local anchor = callout.gotIt
	for _, button in ipairs(shown) do
		if stacked then
			button:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 6)
		else
			button:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
		end
		anchor = button
	end
	return stacked and (#shown + 1) or 1
end

local function ShowSpot(key, opts, target)
	BuildSpot()
	current = { form = "spot", key = key, id = SeenID(key, opts.scope), target = target, opts = opts }
	SeenStore(opts)[current.id] = true
	local callout = spotFrame.callout
	local textHeight = LayoutText(callout, opts.title, opts.text, false)
	local defs = {}
	for index, def in ipairs(type(opts.buttons) == "table" and opts.buttons or {}) do
		if index <= MAX_BUTTONS then defs[index] = def end
	end
	callout.gotIt:SetText(L["Got it"])
	local rows = LayoutButtons(callout, defs)
	callout:SetHeight(textHeight + 24 + rows * 26)
	spotFrame:Show()
	Call(opts.onShow)
	Tour:PlaceSpot()
	return true
end

-- Show a spot help now, or queue it until it can show. Returns true when
-- it shows now.
function Tour:Spot(key, opts)
	opts = type(opts) == "table" and opts or {}
	if type(key) ~= "string" then return false end
	if not opts.force and (not self:Enabled() or SeenStore(opts)[SeenID(key, opts.scope)]) then return false end
	-- The target is looked up only when nothing else holds the help back:
	-- a target function may draw something (a copy of a hidden bar).
	local held = self:Blocked(opts.force) or (current and not opts.force)
	local target = not held and opts.target and Resolve(opts.target) or nil
	local ready = not held and (opts.target == nil or target ~= nil)
	if not ready then
		if not opts.force and not opts.now then self:Queue(key, opts) end
		return false
	end
	if current then self:End("replaced") end
	return ShowSpot(key, opts, target)
end

---------------------------------------------------------------------------
-- The queue: spot helps that wait for a calm moment or their frame
---------------------------------------------------------------------------
local function Pump()
	if current or #queue == 0 or Tour:Blocked() then return end
	for index, entry in ipairs(queue) do
		local seen = SeenStore(entry.opts)[SeenID(entry.key, entry.opts.scope)]
		if seen or not Tour:Enabled() then
			table.remove(queue, index)
			return Pump()
		end
		local target = entry.opts.target and Resolve(entry.opts.target)
		if entry.opts.target == nil or target then
			table.remove(queue, index)
			ShowSpot(entry.key, entry.opts, target)
			return
		end
	end
end
Tour.Pump = function() Pump() end

local function StopTicker()
	if queueTicker then
		queueTicker:Cancel()
		queueTicker = nil
	end
end

function Tour:Queue(key, opts)
	local id = SeenID(key, opts.scope)
	for _, entry in ipairs(queue) do
		if SeenID(entry.key, entry.opts.scope) == id then
			entry.opts = opts
			return
		end
	end
	queue[#queue + 1] = { key = key, opts = opts }
	-- A light check once a second while something waits; it stops when
	-- the queue is empty.
	if not queueTicker and C_Timer and C_Timer.NewTicker then
		queueTicker = C_Timer.NewTicker(QUEUE_TICK, function()
			if #queue == 0 then
				StopTicker()
				return
			end
			Pump()
		end)
	end
end

function Tour:Queued()
	local list = {}
	for _, entry in ipairs(queue) do list[#list + 1] = SeenID(entry.key, entry.opts.scope) end
	return list
end

-- Forget the waiting helps that match a key prefix (a layout switched
-- away before its help could show).
function Tour:Unqueue(prefix)
	for index = #queue, 1, -1 do
		if queue[index].key:sub(1, #prefix) == prefix then table.remove(queue, index) end
	end
end

---------------------------------------------------------------------------
-- Ending, and what is showing
---------------------------------------------------------------------------
local endHooks = {}
function Tour:OnEnd(fn)
	if type(fn) == "function" then endHooks[#endHooks + 1] = fn end
end

-- how: "done", "skip", "gotit", "button", "combat", "gone", "off", "replaced"
function Tour:End(how)
	local ending = current
	current = nil
	if overlay then overlay:Hide() end
	if spotFrame then spotFrame:Hide() end
	if ending then
		Call(ending.opts and ending.opts.onClose, how or "done")
		for _, fn in ipairs(endHooks) do Call(fn, ending.form, ending.key, how or "done") end
	end
	-- The next help waits a moment, so two never flash one after the other.
	if #queue > 0 and C_Timer then C_Timer.After(0.5, Pump) end
end

-- form ("tour" or "spot"), key, step index; nil when nothing shows.
function Tour:Running()
	if not current then return nil end
	return current.form, current.key, current.index
end

function Tour:Owner()
	return current and current.opts and current.opts.owner
end

-- The shown callout.
function Tour:Callout(form)
	if (form or "tour") == "tour" then return overlay and overlay.callout end
	return spotFrame and spotFrame.callout
end

E:RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if current then Tour:End("combat") end
end, Tour)
E:RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if #queue > 0 and C_Timer then C_Timer.After(1, Pump) end
end, Tour)

---------------------------------------------------------------------------
-- Named helps and /eui tour
---------------------------------------------------------------------------
function Tour:Register(key, def)
	assert(type(key) == "string" and type(def) == "table", "EldoUI.Tour:Register(key, def)")
	if not registry[key] then registryOrder[#registryOrder + 1] = key end
	registry[key] = def
	return def
end

function Tour:Get(key)
	return registry[key]
end

function Tour:List()
	return registryOrder
end

-- Run a named help's offer (the place it belongs to calls this).
function Tour:Offer(key, ...)
	local def = registry[key]
	if not def or type(def.offer) ~= "function" then return false end
	local ok, shown = pcall(def.offer, def, ...)
	if not ok then
		geterrorhandler()(shown)
		return false
	end
	return shown
end

-- A word for /eui tour that shows a tour again (the Journal adds its own).
function Tour:RegisterReplay(word, label, fn)
	if not replays[word] then replayOrder[#replayOrder + 1] = word end
	replays[word] = { label = label, fn = fn }
end

local function ReplayDef(word)
	for _, key in ipairs(registryOrder) do
		local def = registry[key]
		if (def.word == word or key == word) and def.replay then return def end
	end
end

local function Replay(word)
	local entry = replays[word]
	if entry then
		entry.fn()
		return true
	end
	for _, key in ipairs(registryOrder) do
		local def = registry[key]
		if (def.word == word or key == word) and def.replay then
			if InCombatLockdown() then
				E:Print(L["The tour runs out of combat."])
			else
				def.replay(def)
			end
			return true
		end
	end
	return false
end

E:AddCommand("tour", E.Key("[name | reset]  list the tour helps, show one again, or show them all again"), function(arg)
	local word = strtrim(arg or ""):lower()
	if word == "reset" then
		Tour:Reset()
		E:Print(L["Every tour help shows again, once, the next time its place comes up."])
		return
	end
	if word ~= "" then
		-- A help that lives on an options page opens that page first, here
		-- in the /eui command.
		local def = ReplayDef(word)
		if def and def.page and not InCombatLockdown() then E:ToggleConfig(def.page, true, def.pageKey) end
		if Replay(word) then return end
	end
	local words = {}
	for _, w in ipairs(replayOrder) do words[#words + 1] = w end
	for _, key in ipairs(registryOrder) do
		local def = registry[key]
		if def.replay and def.word then words[#words + 1] = def.word end
	end
	table.sort(words)
	E:Print(L["Tour helps: /eui tour %s, or /eui tour reset to see them all again."]:format(table.concat(words, " | ")))
end, "Tools")
