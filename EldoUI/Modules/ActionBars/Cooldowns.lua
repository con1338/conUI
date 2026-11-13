-- EldoUI cooldown numbers: the countdown text on any Cooldown frame,
-- drawn by the game itself.
--
-- Cooldowns can be secret in combat on WoW: Forever, so EldoUI never reads
-- a cooldown's time. It hands the Cooldown frame a numeric rule formatter
-- (C_StringUtil.CreateNumericRuleFormatter) and the game formats the
-- remaining time with it: whole seconds, minutes, hours, tenths near the end,
-- and a color per band. Nothing here compares or calculates a time.
--
--   E:StyleCooldownText(cooldown, opts)
--     opts.mode           "eldoui" (EldoUI numbers), "blizzard" (the game's
--                         own setting) or "off"
--     opts.size           text size at the normal General size (16); the
--                         General > Fonts and Text "Cooldown numbers" size
--                         scales it
--     opts.expiring       seconds: below this the expiring color is used
--     opts.tenths         seconds: below this tenths show (0 = never)
--     opts.color, opts.secondsColor, opts.expiringColor   { r, g, b }
--     opts.swipeAlpha     0-100, darkness of the swipe
--     opts.bling          flash when the cooldown ends
--     opts.minDuration    seconds: cooldowns whose total length is shorter
--                         show no numbers (the game decides, from the
--                         cooldown's own total duration; the global cooldown
--                         stays quiet)
--     opts.edge           bright edge on the swipe
--     opts.keepShown      leave "show numbers" to the frame's owner (Blizzard
--                         buttons follow the game's countdown setting)
-- Other modules (aura icons, unit frames) can use the same call.
--
-- Font, size and outline: every cooldown styled here uses General >
-- Fonts and Text > Cooldown numbers. The font (the theme font unless one is
-- picked) and the outline apply as they are. The General size is the base:
-- 16 is normal, and a module's own size (Action Bars > Cooldowns "Number
-- size", the bag slot size, aura icon sizes) is scaled by General / 16, so
-- one row on the Fonts page grows or shrinks every cooldown number while
-- small buttons keep their smaller text.
local _, E = ...

local BASE_SIZE = 16

-- Path, size and outline of a cooldown number whose module asks for `size`.
function E:CooldownTextLook(size)
	local general = self.db and self.db.general or {}
	local path, base, outline
	if self.CooldownFont then path, base, outline = self:CooldownFont() end
	path = path or self.media.font
	base = tonumber(base) or BASE_SIZE
	-- No size of its own: the General size as it is.
	local final = math.max(6, math.floor((tonumber(size) or BASE_SIZE) * base / BASE_SIZE + 0.5))
	outline = outline or general.cooldownFontOutline
	return path, final, outline or ""
end

-- The one cooldown-number look: the thresholds and colors of
-- General > Fonts and Text > Cooldown numbers, used by every module that
-- shows countdown numbers (action bars, aura icons, group frames,
-- nameplates, bags, weapon enchants). `size` is the module's own size
-- (scaled by the General size). The game's countdown look ("blizzard")
-- follows the Action Bars choice; "off" there only hides the action bar
-- numbers, other modules keep their own switch. Action Bars can keep a
-- look of their own (Action Bars > Cooldowns > Own colors and thresholds).
-- Rows with their own time format (Combat HUD) keep their formatter.
function E:CooldownLook(size)
	local bars = self.GetModule and self:GetModule("ActionBars")
	local db = bars and bars.db
	local general = self.db and self.db.general or self.defaults.general
	return {
		mode = (db and db.cooldownText == "blizzard") and "blizzard" or "eldoui",
		size = size,
		expiring = general.cooldownExpiring,
		tenths = general.cooldownTenths,
		color = general.cooldownColor,
		secondsColor = general.cooldownSecondsColor,
		expiringColor = general.cooldownExpiringColor,
	}
end

local formatters = {}  -- key -> formatter

local function Hex(color, fallback)
	color = type(color) == "table" and color or fallback
	return ("|cff%02x%02x%02x"):format(
		math.floor((color[1] or 1) * 255 + 0.5),
		math.floor((color[2] or 1) * 255 + 0.5),
		math.floor((color[3] or 1) * 255 + 0.5))
end

-- True when the client can format cooldown numbers for us.
function E:CanFormatCooldowns()
	return C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum and Enum.NumericRuleFormatRounding and true or false
end

-- One shared formatter per look; the same object serves every cooldown.
function E:GetCooldownFormatter(opts)
	if not self:CanFormatCooldowns() then return nil end
	opts = opts or {}
	local expiring = math.max(0, math.min(60, tonumber(opts.expiring) or 5))
	local tenths = math.max(0, math.min(expiring > 0 and expiring or 10, tonumber(opts.tenths) or 0))
	local normal = Hex(opts.color, { 1, 1, 1 })
	local seconds = Hex(opts.secondsColor, { 1, 1, 1 })
	local soon = Hex(opts.expiringColor, { 1, 0.3, 0.3 })
	local key = table.concat({ expiring, tenths, normal, seconds, soon }, ":")
	if formatters[key] then return formatters[key] end

	local up = Enum.NumericRuleFormatRounding.Up
	local breakpoints = {}
	if tenths > 0 then
		breakpoints[#breakpoints + 1] = { threshold = 0, step = 0.1, rounding = up, format = soon .. "%.1f|r" }
	end
	if expiring > tenths then
		breakpoints[#breakpoints + 1] = { threshold = tenths, step = 1, rounding = up, format = soon .. "%.0f|r" }
	end
	breakpoints[#breakpoints + 1] = { threshold = expiring, step = 1, rounding = up, format = seconds .. "%.0f|r" }
	breakpoints[#breakpoints + 1] = { threshold = 60, format = normal .. "%.0fm|r",
		components = { { div = 60, step = 1, rounding = up } } }
	breakpoints[#breakpoints + 1] = { threshold = 3600, format = normal .. "%.0fh|r",
		components = { { div = 3600, step = 1, rounding = up } } }
	breakpoints[#breakpoints + 1] = { threshold = 86400, format = normal .. "%.0fd|r",
		components = { { div = 86400, step = 1, rounding = up } } }

	local ok, formatter = pcall(function()
		local f = C_StringUtil.CreateNumericRuleFormatter()
		f:SetBreakpoints(breakpoints)
		return f
	end)
	if not ok then
		E:Debug("Cooldown formatter not available:", formatter)
		return nil
	end
	formatters[key] = formatter
	return formatter
end

-- Style one Cooldown frame. Safe on any frame, including Blizzard's: it
-- only calls the frame's own setters, which take plain numbers.
function E:StyleCooldownText(cooldown, opts)
	if not cooldown or not cooldown.SetHideCountdownNumbers then return end
	if E.FrameCheck(cooldown, "IsForbidden") then return end
	opts = opts or {}
	local mode = opts.mode or "eldoui"
	if mode == "off" then
		if not opts.keepShown then cooldown:SetHideCountdownNumbers(true) end
	elseif mode == "blizzard" then
		if cooldown.SetCountdownFormatter then pcall(cooldown.SetCountdownFormatter, cooldown, nil) end
		if not opts.keepShown then cooldown:SetHideCountdownNumbers(not GetCVarBool("countdownForCooldowns")) end
	else
		if not opts.keepShown then cooldown:SetHideCountdownNumbers(false) end
		local formatter = self:GetCooldownFormatter(opts)
		if formatter and cooldown.SetCountdownFormatter then
			pcall(cooldown.SetCountdownFormatter, cooldown, formatter)
		elseif cooldown.SetCountdownMillisecondsThreshold then
			-- No formatter could be built: at least the tenths threshold.
			pcall(cooldown.SetCountdownMillisecondsThreshold, cooldown, tonumber(opts.tenths) or 0)
		end
		local text = cooldown.GetCountdownFontString and cooldown:GetCountdownFontString()
		if text then
			-- General > Fonts and Text > Cooldown numbers: font, outline and
			-- the base size, always.
			local path, size, outline = E:CooldownTextLook(opts.size)
			if not text:SetFont(path, size, outline) then E:SetFont(text, size, outline) end
			text:ClearAllPoints()
			text:SetPoint("CENTER", cooldown, "CENTER", 0, 0)
		end
	end
	if opts.swipeAlpha then cooldown:SetSwipeColor(0, 0, 0, math.max(0, math.min(1, opts.swipeAlpha / 100))) end
	if opts.bling ~= nil and cooldown.SetDrawBling then cooldown:SetDrawBling(opts.bling and true or false) end
	if opts.edge ~= nil and cooldown.SetDrawEdge then cooldown:SetDrawEdge(opts.edge and true or false) end
	if opts.minDuration and cooldown.SetMinimumCountdownDuration and mode == "eldoui" then
		local ms = math.floor(math.max(0, math.min(60, tonumber(opts.minDuration) or 0)) * 1000)
		pcall(cooldown.SetMinimumCountdownDuration, cooldown, ms)
	end
end
