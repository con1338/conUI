-- EldoUI Skin: one shared kit for putting any Blizzard window in the
-- EldoUI look. Every module that skins a game window uses these helpers,
-- so all windows share one style that follows the art style and accent.
--
--   E:SkinPanel(frame, opts)       window art invisible, art-style panel behind
--   E:SkinTabs(tabs, opts)         flat tabs, accent underline on the selected one
--   E:SkinButton(button, opts)     flat text button with accent hover
--   E:SkinEditBox(box, opts)       flat input box, accent border while typing
--   E:SkinCheckBox(check, opts)    flat square with an accent fill when checked
--   E:SkinScrollBar(bar, opts)     thin track and thumb (modern and old scroll bars)
--   E:SkinCloseButton(button)      a drawn X that turns accent on hover
--   E:SkinDropdown(dropdown, opts) flat box with the EldoUI chevron
--   E:SkinBlizzardMenus()          MenuUtil menus on the EldoUI small-box look
--   E:SkinRow(row, opts)           list row: flat stripe, divider, hover
--   E:SkinSlider(slider, opts)     flat track, accent thumb, hit rect as tall as the thumb
--   E:PixelFor(frame), E:Hairline(region, kind, n), E:SnapBorders(root)
--                                  1-pixel edges that stay 1 screen pixel in scaled windows
--   E:HookScrollBoxRows(box, fn)   run fn on every row a ScrollBox shows
--   E:EachScrollBoxRow(box, fn)    run fn on every row a ScrollBox shows now
--
-- Rules every helper keeps (taint safety):
--   * Blizzard art is made invisible with SetAlpha(0); Blizzard frames are
--     never hidden, reparented or given new fields.
--   * Per-frame state lives in local weak tables, read with E:GetSkin(frame, kind).
--   * Every helper checks the frame exists and is not forbidden, and is
--     safe to call twice.
-- Written from scratch for EldoUI; no code or media from other addons.
local addonName, E = ...
local L = E.L

local MEDIA = "Interface\\AddOns\\EldoUI\\Media\\Textures\\"
E.media.chevron = MEDIA .. "EldoChevron.tga"
E.media.dot = MEDIA .. "EldoDot.tga"
E.media.eye = MEDIA .. "EldoEye.tga"

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local skins = setmetatable({}, { __mode = "k" })       -- frame -> { [kind] = parts }
local accented = setmetatable({}, { __mode = "k" })    -- texture -> alpha (follows the accent)
local tabs = setmetatable({}, { __mode = "k" })        -- tab -> parts
local edits = setmetatable({}, { __mode = "k" })       -- edit box -> backdrop
local boxHooks = setmetatable({}, { __mode = "k" })    -- ScrollBox -> { [fn] = true }
local owner = {}                                       -- callback owner token
local fonts = {}                                       -- key -> { font, size, color }

local function UsableRaw(frame)
	if type(frame) ~= "table" or type(frame.GetObjectType) ~= "function" then return false end
	if E.FrameCheck(frame, "IsForbidden") then return false end
	return true
end

---------------------------------------------------------------------------
-- Recorded skins: what a skin changed on a game window, so switching the
-- skin off puts the window back the way the game drew it, without a reload.
--
--   E:SkinRecord(key, roots, fn, ...)  runs fn(...) and records every change
--        it makes on the frames under `roots` (a frame or a list of frames)
--        and on every frame a helper of this kit touches meanwhile: alpha,
--        shown, texture, texture coordinates, vertex color, draw layer,
--        points, fonts, text and shadow colors, hit rect, font objects and
--        backdrop. Frames and textures the skin adds are noted as its own.
--        The same key adds to one record; while it is off nothing runs.
--   E:SkinRecordOff(key)    every recorded value back, every added piece hidden
--   E:SkinRecordOn(key)     the recorded look again (after Off)
--   E:SkinRecordState(key)  nil (nothing recorded yet), "on" or "off"
--   E:SkinRecordReport(key) { on, objects, values, added } for diagnostics
--   E:SkinRecordIsOff(obj)  the object belongs to a record that is off
--   E:SkinRecordKey()       the key of the pass running now (for hooks)
--   E:SkinCapture(...)      note objects before changing them (inside a
--                           record pass; nothing happens outside one)
--   E:SkinColorTexture(texture, r, g, b, a)  SetColorTexture that a record
--                           can paint again (the game cannot read it back)
-- A value goes back only while it still shows what the skin set, so a
-- change the game made since stays. A frame of a record that is off is
-- left alone by every helper here, so hooks that run later paint nothing.
-- Protected frames change out of combat only.
---------------------------------------------------------------------------
local records = {}                                       -- key -> record
local recordOwner = setmetatable({}, { __mode = "k" })   -- object -> record that changed or added it
local passes = {}                                        -- open record passes, innermost last
local CAPTURE_DEPTH, CAPTURE_LIMIT = 10, 6000

local function RecordOff(object)
	local rec = recordOwner[object]
	return rec ~= nil and not rec.on
end

local function Usable(frame)
	return UsableRaw(frame) and not RecordOff(frame)
end
E.SkinUsable = function(_, frame) return Usable(frame) end

local function Pack(...) return { n = select("#", ...), ... } end

local function Same(a, b)
	if a == b then return true end
	local ta, tb = type(a), type(b)
	if ta == "number" and tb == "number" then return math.abs(a - b) < 0.001 end
	if ta ~= "table" or tb ~= "table" then return false end
	if type(a.GetObjectType) == "function" or type(b.GetObjectType) == "function" then return false end
	for k, v in pairs(a) do
		if k ~= "color" and not Same(v, b[k]) then return false end
	end
	for k in pairs(b) do
		if k ~= "color" and a[k] == nil then return false end
	end
	return true
end

local function IsTexture(o) return o.IsObjectType and o:IsObjectType("Texture") end
local function HasFont(o)
	return type(o.GetFont) == "function" and type(o.SetFont) == "function" and type(o.GetTextColor) == "function"
end
local function IsRegionKind(o) return IsTexture(o) or (o.IsObjectType and o:IsObjectType("FontString")) end

local function Points(o)
	local list = {}
	for i = 1, o:GetNumPoints() do list[i] = Pack(o:GetPoint(i)) end
	return list
end

local function SetPoints(o, list)
	o:ClearAllPoints()
	for _, p in ipairs(list) do
		o:SetPoint(p[1], p[2] or o:GetParent(), p[3], p[4], p[5])
	end
end

-- The values a record keeps, in the order they go back. `test` says
-- whether an object has the value, `get` reads it and `set` writes it.
local PROPS = {
	{ key = "texture", test = IsTexture,
		get = function(o) return { atlas = (o.GetAtlas and o:GetAtlas()) or false, file = o:GetTexture() or false } end,
		set = function(o, v)
			if v.color and v.color.accent then
				E:AccentTexture(o, v.color.accent)
			elseif v.color then
				o:SetColorTexture(v.color[1], v.color[2], v.color[3], v.color[4])
			elseif v.atlas then
				o:SetAtlas(v.atlas)
			else
				o:SetTexture(v.file or nil)
			end
		end },
	{ key = "texCoord", test = function(o) return IsTexture(o) and o.GetTexCoord end,
		get = function(o) return Pack(o:GetTexCoord()) end,
		set = function(o, v) o:SetTexCoord(unpack(v, 1, v.n)) end },
	{ key = "vertex", test = function(o) return IsTexture(o) and o.GetVertexColor end,
		get = function(o) return Pack(o:GetVertexColor()) end,
		set = function(o, v) o:SetVertexColor(v[1], v[2], v[3], v[4]) end },
	{ key = "desaturated", test = function(o) return IsTexture(o) and o.IsDesaturated end,
		get = function(o) return o:IsDesaturated() and true or false end,
		set = function(o, v) o:SetDesaturated(v) end },
	{ key = "layer", test = function(o) return IsRegionKind(o) and o.GetDrawLayer end,
		get = function(o) return Pack(o:GetDrawLayer()) end,
		set = function(o, v) o:SetDrawLayer(v[1], v[2]) end },
	-- Sizes only for textures with one anchor or none: a size that comes
	-- from two anchors is not a size of its own.
	{ key = "size", test = IsTexture,
		get = function(o)
			if o:GetNumPoints() >= 2 then return false end
			return Pack(o:GetSize())
		end,
		set = function(o, v) if v then o:SetSize(v[1], v[2]) end end },
	{ key = "points", test = function(o) return o.GetNumPoints and o.GetPoint end,
		get = Points, set = SetPoints },
	-- The font object first: setting one also sets the face, which follows.
	{ key = "fontObject", test = function(o) return HasFont(o) and o.GetFontObject and o.SetFontObject end,
		get = function(o) return o:GetFontObject() or false end,
		set = function(o, v) if v then o:SetFontObject(v) end end },
	{ key = "font", test = HasFont,
		get = function(o) return Pack(o:GetFont()) end,
		set = function(o, v) if v[1] then o:SetFont(v[1], v[2], v[3]) end end },
	{ key = "textColor", test = HasFont,
		get = function(o) return Pack(o:GetTextColor()) end,
		set = function(o, v) o:SetTextColor(v[1], v[2], v[3], v[4]) end },
	{ key = "shadow", test = function(o) return HasFont(o) and o.GetShadowOffset and o.GetShadowColor end,
		get = function(o) return { offset = Pack(o:GetShadowOffset()), color = Pack(o:GetShadowColor()) } end,
		set = function(o, v)
			o:SetShadowOffset(v.offset[1] or 0, v.offset[2] or 0)
			o:SetShadowColor(v.color[1] or 0, v.color[2] or 0, v.color[3] or 0, v.color[4])
		end },
	{ key = "fontObjects", test = function(o) return o.GetNormalFontObject and o.SetNormalFontObject end,
		get = function(o)
			return { normal = o:GetNormalFontObject() or false,
				highlight = (o.GetHighlightFontObject and o:GetHighlightFontObject()) or false,
				disabled = (o.GetDisabledFontObject and o:GetDisabledFontObject()) or false }
		end,
		set = function(o, v)
			if v.normal then o:SetNormalFontObject(v.normal) end
			if v.highlight and o.SetHighlightFontObject then o:SetHighlightFontObject(v.highlight) end
			if v.disabled and o.SetDisabledFontObject then o:SetDisabledFontObject(v.disabled) end
		end },
	{ key = "hitRect", test = function(o) return o.GetHitRectInsets and o.SetHitRectInsets end,
		get = function(o) return Pack(o:GetHitRectInsets()) end,
		set = function(o, v) o:SetHitRectInsets(v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0) end },
	{ key = "backdrop", test = function(o) return type(o.SetBackdrop) == "function" and o.GetBackdropColor end,
		get = function(o)
			local info = o.backdropInfo
			if not info then return { info = false } end
			return { info = info, bg = Pack(o:GetBackdropColor()), border = Pack(o:GetBackdropBorderColor()) }
		end,
		set = function(o, v)
			o:SetBackdrop(v.info or nil)
			if v.info then
				o:SetBackdropColor(v.bg[1], v.bg[2], v.bg[3], v.bg[4])
				o:SetBackdropBorderColor(v.border[1], v.border[2], v.border[3], v.border[4])
			end
		end },
	{ key = "alpha", test = function(o) return o.GetAlpha and o.SetAlpha end,
		get = function(o) return o:GetAlpha() end,
		set = function(o, v) o:SetAlpha(v) end },
	{ key = "shown", test = function(o) return o.IsShown and o.SetShown end,
		get = function(o) return o:IsShown() and true or false end,
		set = function(o, v) o:SetShown(v) end },
}

-- Every value of one object as it is now (values the game keeps secret
-- are left out).
local function ReadState(o)
	local state = {}
	for _, prop in ipairs(PROPS) do
		local okTest, has = pcall(prop.test, o)
		if okTest and has then
			local ok, value = pcall(prop.get, o)
			if ok and value ~= nil and pcall(Same, value, value) then state[prop.key] = value end
		end
	end
	return state
end

local function Kids(o)
	local kids = {}
	if o.GetRegions then
		for _, region in ipairs({ o:GetRegions() }) do kids[region] = true end
	end
	if o.GetChildren then
		for _, child in ipairs({ o:GetChildren() }) do kids[child] = true end
	end
	return kids
end

-- Note one object, its regions and `depth` levels of child frames, before a change.
local function CaptureIn(pass, o, depth)
	if not UsableRaw(o) or pass.rec.added[o] then return end
	if not pass.before[o] then
		if pass.count >= CAPTURE_LIMIT then return end
		pass.count = pass.count + 1
		pass.before[o] = ReadState(o)
		if o.GetRegions then pass.kids[o] = Kids(o) end
	end
	if not o.GetRegions then return end
	for _, region in ipairs({ o:GetRegions() }) do
		if not pass.before[region] and not pass.rec.added[region] and pass.count < CAPTURE_LIMIT and UsableRaw(region) then
			pass.count = pass.count + 1
			pass.before[region] = ReadState(region)
		end
	end
	if (depth or 0) > 0 and o.GetChildren then
		for _, child in ipairs({ o:GetChildren() }) do CaptureIn(pass, child, depth - 1) end
	end
end

local function Capture(o, depth)
	local pass = passes[#passes]
	if pass and o then CaptureIn(pass, o, depth or 0) end
end

-- A piece made later for a frame a record changed belongs to that record.
local function Adopt(piece, frame)
	local rec = recordOwner[frame]
	if rec and piece then
		rec.added[piece] = true
		recordOwner[piece] = rec
	end
end
E.SkinAdopt = function(_, piece, frame) Adopt(piece, frame) end

function E:SkinCapture(...)
	for i = 1, select("#", ...) do Capture((select(i, ...))) end
end

-- What a pass changed goes into its record: pieces that appeared under a
-- noted frame are the skin's own, the rest is a value with its old and new.
local function ClosePass(pass)
	local rec = pass.rec
	for o, kids in pairs(pass.kids) do
		for kid in pairs(Kids(o)) do
			if not kids[kid] and not (recordOwner[kid] and recordOwner[kid] ~= rec) then
				rec.added[kid] = true
				rec.values[kid] = nil
				recordOwner[kid] = rec
			end
		end
	end
	for o, before in pairs(pass.before) do
		if not rec.added[o] then
			local after = ReadState(o)
			local colors = pass.colors[o]
			for key, old in pairs(before) do
				local new = after[key]
				local ok, same = pcall(Same, old, new)
				if new ~= nil and ok and not same then
					if key == "texture" and colors then new.color = colors end
					local values = rec.values[o]
					if not values then
						values = {}
						rec.values[o] = values
					end
					if values[key] then
						values[key].new = new
					else
						values[key] = { old = old, new = new }
					end
					recordOwner[o] = rec
				elseif key == "texture" and colors and rec.values[o] and rec.values[o].texture then
					rec.values[o].texture.new.color = colors
				end
			end
		end
	end
end

local function Record(key)
	local rec = records[key]
	if not rec then
		rec = { key = key, on = true,
			values = setmetatable({}, { __mode = "k" }),   -- object -> { [prop] = { old, new } }
			added = setmetatable({}, { __mode = "k" }),    -- pieces the skin made
			hidden = setmetatable({}, { __mode = "k" }),   -- piece -> it was hidden already when the record went off
			deep = setmetatable({}, { __mode = "k" }) }    -- roots walked deep already
		records[key] = rec
	end
	return rec
end

function E:SkinRecord(key, roots, fn, ...)
	if type(key) ~= "string" or type(fn) ~= "function" then return false end
	local rec = Record(key)
	if not rec.on then return false end
	local outer = passes[#passes]
	local pass = outer
	if not (outer and outer.rec == rec) then
		pass = { rec = rec, before = {}, kids = {}, colors = {}, count = 0 }
		passes[#passes + 1] = pass
	end
	if UsableRaw(roots) then roots = { roots } end
	for _, root in ipairs(type(roots) == "table" and roots or {}) do
		if UsableRaw(root) then
			-- A root is walked deep once; later passes note what the helpers touch.
			CaptureIn(pass, root, rec.deep[root] and 0 or CAPTURE_DEPTH)
			rec.deep[root] = true
		end
	end
	local ok, err = pcall(fn, ...)
	if pass ~= outer then
		table.remove(passes)
		ClosePass(pass)
	end
	if not ok then geterrorhandler()(err) end
	return ok
end

local function Put(rec, from, to)
	for o, values in pairs(rec.values) do
		for _, prop in ipairs(PROPS) do
			local entry = values[prop.key]
			if entry then
				local okNow, now = pcall(prop.get, o)
				local okSame, same = pcall(Same, now, entry[from])
				if okNow and okSame and same then
					local ok, err = pcall(prop.set, o, entry[to])
					if not ok and E.errors and E.errors.Add then E.errors:Add("warning", "EldoUI skin record: " .. tostring(err)) end
				end
			end
		end
	end
end

local function TurnOff(rec)
	Put(rec, "new", "old")
	for o in pairs(rec.added) do
		rec.hidden[o] = not o:IsShown() or nil
		o:Hide()
	end
end

local function TurnOn(rec)
	for o in pairs(rec.added) do
		if not rec.hidden[o] then o:Show() end
	end
	Put(rec, "old", "new")
	E:UpdateTabs()
end

function E:SkinRecordOff(key)
	local rec = records[key]
	if not rec or not rec.on then return false end
	rec.on = false
	self:RunOutOfCombat(function()
		if not rec.on then TurnOff(rec) end
	end, "skinRecord:" .. key)
	return true
end

function E:SkinRecordOn(key)
	local rec = records[key]
	if not rec or rec.on then return false end
	rec.on = true
	self:RunOutOfCombat(function()
		if rec.on then TurnOn(rec) end
	end, "skinRecord:" .. key)
	return true
end

-- The key of the record pass running now, or nil. A hook a skin installs
-- keeps it, so what the hook paints later joins the same record.
function E:SkinRecordKey()
	local pass = passes[#passes]
	return pass and pass.rec.key or nil
end

function E:SkinRecordState(key)
	local rec = records[key]
	if not rec then return nil end
	return rec.on and "on" or "off"
end

function E:SkinRecordIsOff(object)
	return RecordOff(object)
end

function E:SkinRecordReport(key)
	local rec = records[key]
	if not rec then return nil end
	local report = { on = rec.on, objects = 0, values = 0, added = 0 }
	for _, values in pairs(rec.values) do
		report.objects = report.objects + 1
		for _ in pairs(values) do report.values = report.values + 1 end
	end
	for _ in pairs(rec.added) do report.added = report.added + 1 end
	return report
end

function E:SkinRecordKeys()
	local keys = {}
	for key in pairs(records) do keys[#keys + 1] = key end
	table.sort(keys)
	return keys
end

-- A color texture a record can paint again.
local function ColorTexture(texture, r, g, b, a)
	local pass = passes[#passes]
	if pass then pass.colors[texture] = { r, g, b, a } end
	texture:SetColorTexture(r, g, b, a)
end
function E:SkinColorTexture(texture, r, g, b, a)
	if UsableRaw(texture) and texture.SetColorTexture then ColorTexture(texture, r, g, b, a) end
end

local function GetParts(frame, kind)
	local entry = skins[frame]
	return entry and entry[kind]
end

local function SetParts(frame, kind, parts)
	skins[frame] = skins[frame] or {}
	skins[frame][kind] = parts
	return parts
end

-- Read-only access for modules, e.g. to recolor a row's stripe.
function E:GetSkin(frame, kind)
	return GetParts(frame, kind)
end

local function Accent()
	local c = E.media.accentColor
	return c[1], c[2], c[3]
end

-- A texture tinted with the accent; recolored when the theme changes.
local function AccentTexture(texture, alpha)
	accented[texture] = alpha or 1
	local pass = passes[#passes]
	if pass then pass.colors[texture] = { accent = alpha or 1 } end
	local r, g, b = Accent()
	texture:SetColorTexture(r, g, b, alpha or 1)
	return texture
end
function E:AccentTexture(texture, alpha) return AccentTexture(texture, alpha) end
-- The texture stops following the accent (it shows art of its own now).
function E:ReleaseAccentTexture(texture) if texture then accented[texture] = nil end end

---------------------------------------------------------------------------
-- Pixel-true borders in scaled windows (DESIGN.md 3a). E.pixel is one
-- screen pixel in UIParent units; inside a frame with SetScale(s) the same
-- number is s screen pixels and reads blurry. E:PixelFor(frame) gives one
-- screen pixel in that frame's units, E:Hairline remembers a line or inset
-- drawn in pixels, and E:SnapBorders(root) re-sizes the 1-pixel flat edges
-- and hairlines under `root` after its scale changed.
---------------------------------------------------------------------------
local hairlines = setmetatable({}, { __mode = "k" })  -- region -> { kind, n, rel }
local snapped = setmetatable({}, { __mode = "k" })    -- frame -> true once its edge was snapped
local snapRoots = setmetatable({}, { __mode = "k" })  -- roots E:SnapBorders walked

local REGION_TYPES = { Texture = true, FontString = true, Line = true, MaskTexture = true }

function E:PixelFor(frame)
	local px = self.pixel or 1
	local obj = frame
	if type(obj) == "table" and obj.GetObjectType and REGION_TYPES[obj:GetObjectType()] and obj.GetParent then
		obj = obj:GetParent()
	end
	if type(obj) ~= "table" or not obj.GetEffectiveScale or not UIParent then return px end
	local own, base = obj:GetEffectiveScale(), UIParent:GetEffectiveScale()
	if type(own) ~= "number" or type(base) ~= "number" or own <= 0 then return px end
	return px * base / own
end

local function ApplyHairline(region, info)
	local p = E:PixelFor(region) * info[2]
	local kind = info[1]
	if kind == "h" then
		region:SetHeight(p)
	elseif kind == "w" then
		region:SetWidth(p)
	elseif kind == "inset" then
		local rel = info[3] or region:GetParent()
		region:SetPoint("TOPLEFT", rel, "TOPLEFT", p, -p)
		region:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", -p, p)
	end
end

-- kind: "h" (height n pixels), "w" (width n pixels) or "inset" (fill
-- `rel`, default the parent, n pixels inside its border).
function E:Hairline(region, kind, n, rel)
	local info = { kind, n or 1, rel }
	hairlines[region] = info
	ApplyHairline(region, info)
	return region
end

-- A flat 1-pixel edge (E:SetTemplate) re-sized to one screen pixel of the
-- frame. Colors are kept.
local function SnapEdge(frame)
	local info = frame.backdropInfo or (frame.GetBackdrop and frame:GetBackdrop())
	if type(info) ~= "table" or info.edgeFile ~= E.media.flat or type(info.edgeSize) ~= "number" then return end
	if not snapped[frame] and math.abs(info.edgeSize - (E.pixel or 1)) > 0.001 then return end
	-- Applying a backdrop measures the frame: never while its size is secret.
	if E:SizeIsSecret(frame) then return end
	local px = E:PixelFor(frame)
	snapped[frame] = true
	if math.abs(info.edgeSize - px) < 0.0005 then return end
	local r, g, b, a = frame:GetBackdropColor()
	local br, bg, bb, ba = frame:GetBackdropBorderColor()
	local copy = {}
	for key, value in pairs(info) do copy[key] = value end
	copy.edgeSize = px
	frame:SetBackdrop(copy)
	if r then frame:SetBackdropColor(r, g, b, a) end
	if br then frame:SetBackdropBorderColor(br, bg, bb, ba) end
end

local function Walk(frame, depth)
	SnapEdge(frame)
	if depth > 40 or not frame.GetChildren then return end
	for _, child in ipairs({ frame:GetChildren() }) do
		if type(child) == "table" and not E.FrameCheck(child, "IsForbidden") then Walk(child, depth + 1) end
	end
end

-- Snap every flat edge under `root` (and every hairline) to the screen
-- pixel. Cheap enough to run when a window's scale changes or a page of it
-- is built; the root is remembered so E:RefreshPixel re-snaps it.
-- only = true walks `root` alone: for a part built after its window was
-- snapped (a new row), without re-doing every hairline.
function E:SnapBorders(root, only)
	if only then
		if Usable(root) then Walk(root, 0) end
		return
	end
	if Usable(root) then
		snapRoots[root] = true
		Walk(root, 0)
	end
	for region, info in pairs(hairlines) do
		if region.GetParent then ApplyHairline(region, info) end
	end
end

-- Another part of the core may reset every edge to E.pixel when the UI
-- scale changes (E:RefreshPixel): scaled windows snap again after it.
local function SnapAll()
	for root in pairs(snapRoots) do
		if Usable(root) then Walk(root, 0) end
	end
	for region, info in pairs(hairlines) do
		if region.GetParent then ApplyHairline(region, info) end
	end
end
E.SnapAllBorders = function() SnapAll() end

-- Hover fades: the overlay fades in over E.tokens.motion.hover
-- when the mouse comes, and fades out the same way when it leaves (for
-- that it is drawn on the overlay layer until the fade ends, then goes
-- back to the highlight layer). With General > Animations off it changes
-- at once, as before.
local function Animate()
	return E.db and E.db.general and E.db.general.animations ~= false
end

local function FadeGroup(texture, from, to)
	if not texture.CreateAnimationGroup then return nil end
	local group = texture:CreateAnimationGroup()
	group.alpha = group:CreateAnimation("Alpha")
	group.alpha:SetFromAlpha(from)
	group.alpha:SetToAlpha(to)
	group.alpha:SetSmoothing("OUT")
	group:SetToFinalAlpha(true)
	return group
end

local function HoverRest(hover)
	if hover.kitFadeOut then hover.kitFadeOut:Stop() end
	hover:SetDrawLayer("HIGHLIGHT")
	hover:SetAlpha(1)
end

local function AddHoverFade(button, hover)
	hover.kitFadeIn = FadeGroup(hover, 0, 1)
	hover.kitFadeOut = FadeGroup(hover, 1, 0)
	if not (hover.kitFadeIn and hover.kitFadeOut) then return end
	hover.kitFadeOut:SetScript("OnFinished", function() HoverRest(hover) end)
	button:HookScript("OnEnter", function(self)
		HoverRest(hover)
		if not Animate() or (self.IsEnabled and not self:IsEnabled()) then return end
		hover.kitFadeIn.alpha:SetDuration(E.tokens.motion.hover)
		hover.kitFadeIn:Stop()
		hover.kitFadeIn:Play()
	end)
	button:HookScript("OnLeave", function(self)
		hover.kitFadeIn:Stop()
		HoverRest(hover)
		if not Animate() or not hover:IsShown() or not self:IsVisible() or (self.IsEnabled and not self:IsEnabled()) then return end
		hover:SetDrawLayer("OVERLAY", 5)
		hover.kitFadeOut.alpha:SetDuration(E.tokens.motion.hover)
		hover.kitFadeOut:Play()
	end)
	button:HookScript("OnHide", function() hover.kitFadeIn:Stop() HoverRest(hover) end)
end

-- The hover and pressed look every control shares (DESIGN.md 3a): a white
-- overlay `hover.control` while the mouse is over it, fading in and out,
-- and an accent `pressed` tint while the button is held. `area` is the
-- frame the overlay covers (default the button itself); `border`
-- (optional) is a backdrop frame whose edge turns accent on hover.
local function AddHoverPress(button, area, border)
	area = area or button
	local hover = button:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints(area)
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.control)
	AddHoverFade(button, hover)
	local pressed = button:CreateTexture(nil, "OVERLAY", nil, 6)
	pressed:SetAllPoints(area)
	AccentTexture(pressed, E.tokens.pressed)
	pressed:Hide()
	button:HookScript("OnMouseDown", function(self, mouse)
		if mouse == "LeftButton" and (not self.IsEnabled or self:IsEnabled()) and not RecordOff(pressed) then pressed:Show() end
	end)
	button:HookScript("OnMouseUp", function() pressed:Hide() end)
	button:HookScript("OnHide", function() pressed:Hide() end)
	if border and border.SetBackdropBorderColor then
		button:HookScript("OnEnter", function(self)
			if not self.IsEnabled or self:IsEnabled() then border:SetBackdropBorderColor(Accent()) end
		end)
		button:HookScript("OnLeave", function()
			pressed:Hide()
			border:SetBackdropBorderColor(unpack(E.media.borderColor))
		end)
	else
		button:HookScript("OnLeave", function() pressed:Hide() end)
	end
	return hover, pressed
end
E.SkinHoverPress = function(_, button, area, border) return AddHoverPress(button, area, border) end

-- Small controls (< 20 px) get a hit rect a few pixels larger than what
-- they draw, never larger than `limit` (the row they sit in). Only frames
-- that are not protected and still have the default (zero) insets change.
local function PadHitRect(frame, pad, limit)
	if not (frame.SetHitRectInsets and frame.GetHitRectInsets) then return end
	if E.FrameCheck(frame, "IsProtected") then return end
	local l, r, t, b = frame:GetHitRectInsets()
	if (l or 0) ~= 0 or (r or 0) ~= 0 or (t or 0) ~= 0 or (b or 0) ~= 0 then return end
	local w, h = frame:GetSize()
	local padX = (w or 0) < 20 and pad or 0
	local padY = (h or 0) < 20 and pad or 0
	if limit and h then padY = math.max(0, math.min(padY, (limit - h) / 2)) end
	if padX > 0 or padY > 0 then pcall(frame.SetHitRectInsets, frame, -padX, -padX, -padY, -padY) end
end
E.PadHitRect = function(_, frame, pad, limit) PadHitRect(frame, pad or 4, limit) end

local function Name(frame)
	return frame.GetName and frame:GetName()
end

-- The global region named after a frame (FrameName .. suffix), or nil.
local function Global(frame, suffix)
	local name = Name(frame)
	return name and _G[name .. suffix]
end
E.SkinGlobal = Global

local function AlphaZero(...)
	for i = 1, select("#", ...) do
		local region = select(i, ...)
		if type(region) == "table" and region.SetAlpha and not E.FrameCheck(region, "IsForbidden") then
			Capture(region)
			region:SetAlpha(0)
		end
	end
end
E.SkinAlphaZero = function(_, ...) AlphaZero(...) end

-- Regions a frame keeps under keys with Icon in their name are content
-- (search glass, class icon) and stay visible.
local function KeepIcons(frame, keep)
	keep = keep or {}
	for key, value in pairs(frame) do
		if type(key) == "string" and type(value) == "table" and (key:find("Icon") or key:find("icon")) then
			keep[value] = true
		end
	end
	return keep
end

-- Make a frame's own textures invisible. The regions in `keep` stay, and
-- so do HIGHLIGHT-layer textures unless `all` is set.
function E:StripTextures(frame, keep, all)
	if not Usable(frame) then return end
	Capture(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") and not (keep and keep[region]) and (all or region:GetDrawLayer() ~= "HIGHLIGHT") then
			region:SetAlpha(0)
		end
	end
	if frame.NineSlice then AlphaZero(frame.NineSlice) end
end

-- A child frame behind `frame` carrying a flat or art-style backdrop.
local function Backdrop(frame, panel, transparent)
	Capture(frame)
	local bd = CreateFrame("Frame", nil, frame)
	bd:SetAllPoints()
	bd:SetFrameLevel(math.max(frame:GetFrameLevel() - 1, 0))
	if panel then E:SetPanelTemplate(bd, transparent) else E:SetTemplate(bd, transparent) end
	return bd
end

---------------------------------------------------------------------------
-- Font objects: buttons and tabs get them as their normal / highlight /
-- disabled fonts, so the game's state changes keep the EldoUI font.
---------------------------------------------------------------------------
-- "accent" is read when the font is applied, so a theme change recolors it.
local FONT_COLORS = {
	tabNormal = E.tokens.text.secondary,
	tabHighlight = { 1, 1, 1 },
	tabSelected = "accent",
	buttonNormal = E.tokens.text.body,
	buttonHighlight = { 1, 1, 1 },
	buttonDisabled = E.tokens.text.dim,
	-- EldoUI's own buttons (the kit's): the same colors, and they follow
	-- Large text. Blizzard buttons EldoUI skins keep the plain ones, so
	-- the game's frames keep their layout.
	ownButtonNormal = E.tokens.text.body,
	ownButtonHighlight = { 1, 1, 1 },
	ownButtonDisabled = E.tokens.text.dim,
}

local function ApplyFont(info)
	local outline = E.db and E.db.general.fontOutline or ""
	-- Tabs and EldoUI's own buttons follow Large text (General >
	-- Accessibility) like every EldoUI text.
	local size = info.size
	if (info.kind:find("^tab") or info.kind:find("^own")) and E.TextScale then size = size * E:TextScale() end
	info.font:SetFont(E.media.font, size, outline)
	info.font:SetShadowOffset(0, 0)
	local c = FONT_COLORS[info.kind] or FONT_COLORS.buttonNormal
	if c == "accent" then
		info.font:SetTextColor(E:TokenColor("accent"))
	else
		info.font:SetTextColor(c[1], c[2], c[3])
	end
end

local function FontObject(kind, size)
	size = size or E.tokens.size.body
	local key = kind .. size
	local info = fonts[key]
	if not info then
		info = { font = CreateFont("EldoUISkinFont_" .. key), size = size, kind = kind }
		fonts[key] = info
		ApplyFont(info)
	end
	return info.font
end

local function SetFontObjects(button, normal, highlight, disabled, size)
	if not button.SetNormalFontObject then return end
	pcall(button.SetNormalFontObject, button, FontObject(normal, size))
	pcall(button.SetHighlightFontObject, button, FontObject(highlight, size))
	if disabled then pcall(button.SetDisabledFontObject, button, FontObject(disabled, size)) end
end

---------------------------------------------------------------------------
-- Panels (windows)
---------------------------------------------------------------------------
local PANEL_ART = { "NineSlice", "Bg", "Background", "TitleBg", "TopTileStreaks", "PortraitContainer",
	"portrait", "Portrait", "PortraitFrame", "PortraitButton", "TopLeftCorner", "TopRightCorner",
	"BotLeftCorner", "BotRightCorner", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder", "Shadows" }
local PANEL_GLOBALS = { "Bg", "TitleBg", "Portrait", "PortraitFrame", "TopTileStreaks", "TopLeftCorner",
	"TopRightCorner", "BotLeftCorner", "BotRightCorner", "TopBorder", "BtnCornerLeft", "BtnCornerRight", "ButtonBottomBorder" }

local function TitleText(frame)
	local container = frame.TitleContainer
	return (container and container.TitleText) or frame.TitleText or Global(frame, "TitleText")
end

-- Inset areas lose their art and get a faint flat box so the layout stays readable.
function E:SkinInset(inset, opts)
	if not Usable(inset) then return end
	local parts = GetParts(inset, "inset")
	if parts then return parts.bd end
	opts = opts or {}
	Capture(inset)
	self:StripTextures(inset)
	AlphaZero(inset.NineSlice, inset.Bg, Global(inset, "Bg"))
	parts = {}
	if opts.backdrop ~= false then
		parts.bd = Backdrop(inset, false, true)
		parts.bd:SetBackdropColor(0, 0, 0, 0.25)
	end
	SetParts(inset, "inset", parts)
	return parts.bd
end

-- opts: transparent, accentLine (default true), accentOffset (24), strip
-- (default true), keep (regions to leave visible), insets (default true),
-- close (default true), title (default true).
function E:SkinPanel(frame, opts)
	if not Usable(frame) then return end
	local parts = GetParts(frame, "panel")
	if parts then return parts.bd end
	opts = opts or {}
	Capture(frame)
	Capture(frame.TitleContainer)
	for _, key in ipairs(PANEL_ART) do AlphaZero(frame[key]) end
	for _, suffix in ipairs(PANEL_GLOBALS) do AlphaZero(Global(frame, suffix)) end
	if opts.strip ~= false then self:StripTextures(frame, opts.keep) end
	if frame.TitleContainer then self:StripTextures(frame.TitleContainer) end

	parts = {}
	parts.bd = Backdrop(frame, true, opts.transparent)
	-- A window: the light window edge under Modern (DESIGN.md §0a rule 1).
	E:SetWindowEdge(parts.bd)
	if opts.accentLine ~= false then
		local line = parts.bd:CreateTexture(nil, "ARTWORK")
		line:SetPoint("TOPLEFT", E.pixel, -(opts.accentOffset or 24))
		line:SetPoint("TOPRIGHT", -E.pixel, -(opts.accentOffset or 24))
		line:SetHeight(E.pixel * 2)
		AccentTexture(line, 1)
		parts.line = line
	end
	if opts.insets ~= false then
		for _, inset in ipairs({ frame.Inset, Global(frame, "Inset"), frame.LeftInset, frame.RightInset }) do
			self:SkinInset(inset)
		end
	end
	if opts.close ~= false then
		self:SkinCloseButton(frame.CloseButton or Global(frame, "CloseButton"))
	end
	local title = TitleText(frame)
	if opts.title ~= false and title and title.SetFont then
		E:SetHeaderFont(title, E.tokens.size.dialogTitle)
		title:SetTextColor(1, 1, 1)
	end
	SetParts(frame, "panel", parts)
	return parts.bd
end

-- Change a skinned panel's see-through setting later.
function E:SetPanelTransparent(frame, transparent)
	local parts = GetParts(frame, "panel")
	if parts then E:SetPanelTemplate(parts.bd, transparent) end
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local function TabText(tab)
	return tab.Text or (tab.GetFontString and tab:GetFontString()) or Global(tab, "Text")
end

local function IsSelected(tab, parts)
	if parts.isSelected then
		local ok, selected = pcall(parts.isSelected, tab)
		if ok and selected ~= nil then return selected and true or false end
	end
	if type(tab.isSelected) == "boolean" then return tab.isSelected end
	local tabOwner = parts.owner
	local id = tab.GetID and tab:GetID() or 0
	if tabOwner and type(tabOwner.selectedTab) == "number" and id > 0 then
		return tabOwner.selectedTab == id
	end
	if tab.GetChecked then
		local ok, checked = pcall(tab.GetChecked, tab)
		if ok and checked ~= nil then return checked and true or false end
	end
	return tab.IsEnabled and not tab:IsEnabled() or false
end

-- The open tab's text color and underline ease in and out
-- (E.UIKit.SoftSelect and FadeTextColor, over motion.hover; at once with
-- Animations off, on the first paint or while the tab is hidden). The
-- running fades are kept by the kit, never as fields on the tab.
local function TabTextColor(tab, selected)
	if selected then return E:TokenColor("accent") end
	if tab.IsEnabled and not tab:IsEnabled() then return unpack(E.media.text.dim) end
	local c = FONT_COLORS.tabNormal
	return c[1], c[2], c[3]
end

local function UpdateTab(tab, parts)
	local selected = IsSelected(tab, parts)
	local was = parts.tabSelected
	parts.tabSelected = selected
	local Kit = E.UIKit
	if Kit and Kit.SoftSelect then
		Kit.SoftSelect(parts, selected, function(_, on) parts.line:SetShown(on) end, { parts.line })
	else
		parts.line:SetShown(selected)
	end
	if parts.bg.SetBackdropColor then
		if selected then
			-- Accent-tinted dark, or warm bronze under the WoW Forever art style.
			parts.bg:SetBackdropColor(E:SelectedTabColor())
		else
			-- Boxed tabs stay solid like a kit button; flat ones are muted.
			local r, g, b, a = unpack(E.media.backdropColor)
			parts.bg:SetBackdropColor(r, g, b, parts.boxed and a or a * 0.6)
		end
		-- WoW Forever frames the open tab in the thin bronze line.
		E:SetStyleEdge(parts.bg, selected)
	end
	local text = TabText(tab)
	if text and text.SetTextColor then
		local r, g, b = TabTextColor(tab, selected)
		if Kit and Kit.FadeTextColor and was ~= nil and was ~= selected then
			Kit.FadeTextColor(text, r, g, b)
		elseif not (Kit and Kit.Easing and Kit.Easing(text, "textColor")) then
			text:SetTextColor(r, g, b)
		end
	end
end

function E:UpdateTabs()
	for tab, parts in pairs(tabs) do
		if Usable(tab) then UpdateTab(tab, parts) end
	end
end

local tabQueued = false
local function QueueTabs()
	if tabQueued then return end
	tabQueued = true
	C_Timer.After(0, function()
		tabQueued = false
		E:UpdateTabs()
	end)
end

local tabsHooked = false
local function HookTabUpdates()
	if tabsHooked then return end
	tabsHooked = true
	for _, name in ipairs({ "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab", "PanelTemplates_SetTab",
		"PanelTemplates_UpdateTabs", "PanelTemplates_EnableTab", "PanelTemplates_DisableTab" }) do
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function() E:UpdateTabs() end)
		end
	end
end

-- tabs: a list of tab buttons (or one tab). opts: owner (the frame whose
-- selectedTab field says which tab is open; default the tab's parent),
-- isSelected (function(tab) for tabs that track selection their own way),
-- edge ("BOTTOM" or "TOP" for the accent line), size (font size),
-- inset (hover area inset, default 2), boxed (a box behind each tab and a
-- tinted selected box; the default is flat).
-- Tabs are flat everywhere (DESIGN.md 3): gray text, the open tab in
-- accent text with a 2 px accent underline, the hover overlay on hover.
-- Bottom navigation that hangs below a window (the auction house) uses the
-- boxed tab on an opaque rail in the panel's base color, so the world never
-- shows through: a solid box with the accent edge on hover, like a kit
-- button. `plain` is still read: plain = false asks for the box like boxed.
function E:SkinTabs(list, opts)
	opts = opts or {}
	if Usable(list) then list = { list } end
	if type(list) ~= "table" then return end
	for _, tab in ipairs(list) do
		if Usable(tab) and not tabs[tab] and tab.IsObjectType and tab:IsObjectType("Button") then
			Capture(tab)
			local keep = KeepIcons(tab)
			self:StripTextures(tab, keep, true)
			AlphaZero(tab.GetHighlightTexture and tab:GetHighlightTexture())
			local inset = opts.inset or 2
			local boxed = opts.boxed or opts.plain == false
			local parts = { owner = opts.owner or tab:GetParent(), isSelected = opts.isSelected, boxed = boxed or nil }
			local bg = CreateFrame("Frame", nil, tab)
			bg:SetPoint("TOPLEFT", inset, -inset)
			bg:SetPoint("BOTTOMRIGHT", -inset, inset)
			bg:SetFrameLevel(math.max(tab:GetFrameLevel() - 1, 0))
			if boxed then E:SetTemplate(bg, true) end
			parts.bg = bg
			local edge = opts.edge == "TOP" and "TOP" or "BOTTOM"
			parts.line = bg:CreateTexture(nil, "OVERLAY")
			parts.line:SetPoint(edge .. "LEFT", E.pixel, edge == "TOP" and -E.pixel or E.pixel)
			parts.line:SetPoint(edge .. "RIGHT", -E.pixel, edge == "TOP" and -E.pixel or E.pixel)
			parts.line:SetHeight(E.pixel * 2)
			AccentTexture(parts.line, 1)
			-- Hover and pressed cover the drawn box, and the box is the hit
			-- rect: no dead border around it that still clicks (DESIGN.md 3a).
			parts.hover, parts.pressed = AddHoverPress(tab, bg, boxed and bg or nil)
			if inset > 0 then
				local l, r, t, b = tab:GetHitRectInsets()
				if (l or 0) == 0 and (r or 0) == 0 and (t or 0) == 0 and (b or 0) == 0
					and not E.FrameCheck(tab, "IsProtected") then
					pcall(tab.SetHitRectInsets, tab, inset, inset, inset, inset)
				end
			end
			SetFontObjects(tab, "tabNormal", "tabHighlight", "tabSelected", opts.size)
			tab:HookScript("OnClick", QueueTabs)
			tab:HookScript("OnShow", QueueTabs)
			tabs[tab] = parts
			SetParts(tab, "tab", parts)
		end
	end
	HookTabUpdates()
	self:UpdateTabs()
	QueueTabs()
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local BUTTON_ART = { "Left", "Middle", "Right", "Center", "LeftSeparator", "RightSeparator", "Background", "Border" }

-- opts: size (font size), keepTextures (leave the button's textures, only
-- add the box), transparent, own (an EldoUI button: its label follows
-- Large text).
function E:SkinButton(button, opts)
	if not Usable(button) then return end
	local parts = GetParts(button, "button")
	if parts then return parts end
	opts = opts or {}
	Capture(button)
	if not opts.keepTextures then
		for _, key in ipairs(BUTTON_ART) do AlphaZero(button[key], Global(button, key)) end
		self:StripTextures(button, KeepIcons(button), true)
		AlphaZero(button.GetNormalTexture and button:GetNormalTexture(),
			button.GetPushedTexture and button:GetPushedTexture(),
			button.GetDisabledTexture and button:GetDisabledTexture(),
			button.GetHighlightTexture and button:GetHighlightTexture())
	end
	parts = {}
	-- The box covers the whole button (its hit rect); hover lights the
	-- edge in the accent with a white overlay, a press tints it.
	parts.bd = Backdrop(button, false, opts.transparent)
	parts.hover, parts.pressed = AddHoverPress(button, nil, parts.bd)
	E:Hairline(parts.hover, "inset", 1, button)
	E:Hairline(parts.pressed, "inset", 1, button)
	-- Disabled: the text dims through the disabled font, the
	-- hover overlay and the accent edge go away until it is enabled again.
	if button.HookScript then
		button:HookScript("OnDisable", function()
			parts.hover:Hide()
			parts.pressed:Hide()
			parts.bd:SetBackdropBorderColor(unpack(E.media.borderColor))
		end)
		button:HookScript("OnEnable", function() if not RecordOff(parts.hover) then parts.hover:Show() end end)
	end
	if button.GetFontString and button:GetFontString() then
		if opts.own then
			SetFontObjects(button, "ownButtonNormal", "ownButtonHighlight", "ownButtonDisabled", opts.size)
		else
			SetFontObjects(button, "buttonNormal", "buttonHighlight", "buttonDisabled", opts.size)
		end
	end
	return SetParts(button, "button", parts)
end

---------------------------------------------------------------------------
-- Edit boxes
---------------------------------------------------------------------------
-- opts: left, right, top, bottom (backdrop offsets around the box), size.
function E:SkinEditBox(box, opts)
	if not Usable(box) then return end
	local parts = GetParts(box, "edit")
	if parts then return parts end
	opts = opts or {}
	Capture(box)
	for _, key in ipairs({ "Left", "Middle", "Mid", "Right", "Center" }) do AlphaZero(box[key], Global(box, key)) end
	self:StripTextures(box, KeepIcons(box))
	parts = {}
	local bd = CreateFrame("Frame", nil, box)
	bd:SetPoint("TOPLEFT", -(opts.left or 4), opts.top or 1)
	bd:SetPoint("BOTTOMRIGHT", opts.right or 2, -(opts.bottom or 1))
	bd:SetFrameLevel(math.max(box:GetFrameLevel() - 1, 0))
	E:SetTemplate(bd, true)
	parts.bd = bd
	edits[box] = bd
	-- The box draws a little wider than the edit box itself: the hit rect
	-- grows to match, so a click on the drawn edge focuses it.
	if opts.matchHit ~= false and box.SetHitRectInsets and not E.FrameCheck(box, "IsProtected") then
		pcall(box.SetHitRectInsets, box, -(opts.left or 4), -(opts.right or 2), -(opts.top or 1), -(opts.bottom or 1))
	end
	box:HookScript("OnEnter", function(own)
		local b = edits[own]
		if b and not own:HasFocus() then b:SetBackdropBorderColor(Accent()) end
	end)
	box:HookScript("OnLeave", function(own)
		local b = edits[own]
		if b and not own:HasFocus() then b:SetBackdropBorderColor(unpack(E.media.borderColor)) end
	end)
	if box.SetFont then
		pcall(E.SetFont, E, box, opts.size or E.tokens.size.body)
	end
	local instructions = box.Instructions or Global(box, "Instructions")
	if instructions and instructions.SetFont then
		E:SetFont(instructions, opts.size or E.tokens.size.body)
		instructions:SetTextColor(unpack(E.media.text.secondary))
	end
	box:HookScript("OnEditFocusGained", function(own)
		local b = edits[own]
		if b then b:SetBackdropBorderColor(Accent()) end
	end)
	box:HookScript("OnEditFocusLost", function(own)
		local b = edits[own]
		if b then b:SetBackdropBorderColor(unpack(E.media.borderColor)) end
	end)
	return SetParts(box, "edit", parts)
end

---------------------------------------------------------------------------
-- Check boxes
---------------------------------------------------------------------------
-- opts: inset (space between the button edge and the box, default 4).
function E:SkinCheckBox(check, opts)
	if not Usable(check) or not check.GetCheckedTexture then return end
	local parts = GetParts(check, "check")
	if parts then return parts end
	opts = opts or {}
	Capture(check)
	local inset = opts.inset or 4
	AlphaZero(check:GetNormalTexture(), check:GetPushedTexture())
	if check.GetDisabledTexture then AlphaZero(check:GetDisabledTexture()) end
	for _, key in ipairs({ "Left", "Middle", "Right", "Background", "Border" }) do AlphaZero(check[key]) end
	parts = {}
	local bd = CreateFrame("Frame", nil, check)
	bd:SetPoint("TOPLEFT", inset, -inset)
	bd:SetPoint("BOTTOMRIGHT", -inset, inset)
	bd:SetFrameLevel(math.max(check:GetFrameLevel() - 1, 0))
	E:SetTemplate(bd)
	parts.bd = bd
	-- The resting edge stands out from the panel (tokens.edge.control) and
	-- follows a new art style.
	local function Rest() bd:SetBackdropBorderColor(unpack(E:ControlEdgeColor())) end
	Rest()
	E:RegisterThemed(bd, function() if not check:IsMouseOver() then Rest() end end)
	local checked = check:GetCheckedTexture()
	if checked then
		checked:SetTexture(E.media.flat)
		checked:ClearAllPoints()
		checked:SetPoint("TOPLEFT", bd, "TOPLEFT", 3, -3)
		checked:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -3, 3)
		AccentTexture(checked, 1)
	end
	local disabledChecked = check.GetDisabledCheckedTexture and check:GetDisabledCheckedTexture()
	if disabledChecked then
		local dim = E.tokens.text.dim
		ColorTexture(disabledChecked, dim[1], dim[2], dim[3], 0.8)
		disabledChecked:ClearAllPoints()
		disabledChecked:SetPoint("TOPLEFT", bd, "TOPLEFT", 3, -3)
		disabledChecked:SetPoint("BOTTOMRIGHT", bd, "BOTTOMRIGHT", -3, 3)
	end
	local highlight = check:GetHighlightTexture()
	if highlight then
		ColorTexture(highlight, 1, 1, 1, E.tokens.hover.control)
		highlight:ClearAllPoints()
		highlight:SetAllPoints(bd)
	end
	-- Hover: the accent edge on the drawn box; a press tints it. The hit
	-- rect is the button (inset px larger than the box on each side, the
	-- small-control margin), never the whole row.
	parts.pressed = check:CreateTexture(nil, "OVERLAY", nil, 6)
	parts.pressed:SetAllPoints(bd)
	AccentTexture(parts.pressed, E.tokens.pressed)
	parts.pressed:Hide()
	check:HookScript("OnEnter", function(own)
		if own:IsEnabled() then bd:SetBackdropBorderColor(Accent()) end
	end)
	check:HookScript("OnLeave", function()
		parts.pressed:Hide()
		Rest()
	end)
	check:HookScript("OnMouseDown", function(own, mouse)
		if mouse == "LeftButton" and own:IsEnabled() and not RecordOff(parts.pressed) then parts.pressed:Show() end
	end)
	check:HookScript("OnMouseUp", function() parts.pressed:Hide() end)
	if inset < 3 then PadHitRect(check, 3 - inset) end
	return SetParts(check, "check", parts)
end

---------------------------------------------------------------------------
-- Sliders
---------------------------------------------------------------------------
-- A flat horizontal slider: thin track box, accent fill left of the thumb
-- and an accent thumb that is taller than the track. The hit rect grows to
-- the thumb's height (plus the small-control margin, never more than
-- `rowHeight`), so the whole visible thumb and track take the click.
-- opts: thumbWidth (8), thumbHeight (16), rowHeight (limit, default 28).
-- Returns parts { track, thumb, fill }; parts.Paint() re-reads the accent.
function E:SkinSlider(slider, opts)
	if not Usable(slider) or not slider.SetThumbTexture then return end
	local parts = GetParts(slider, "slider")
	if parts then return parts end
	opts = opts or {}
	Capture(slider)
	self:StripTextures(slider, nil, true)
	AlphaZero(slider.Left, slider.Middle, slider.Right, slider.NineSlice)
	parts = {}
	E:SetTemplate(slider, true)
	slider:SetThumbTexture(E.media.flat)
	local thumb = slider:GetThumbTexture()
	local thumbHeight = opts.thumbHeight or 16
	thumb:SetSize(opts.thumbWidth or 8, thumbHeight)
	parts.thumb = thumb
	local fill = slider:CreateTexture(nil, "ARTWORK")
	fill:SetTexture(E.media.flat)
	local p = E:PixelFor(slider)
	fill:SetPoint("TOPLEFT", p, -p)
	fill:SetPoint("BOTTOMLEFT", p, p)
	fill:SetPoint("RIGHT", thumb, "CENTER")
	parts.fill = fill
	local limit = opts.rowHeight or 28
	local _, h = slider:GetSize()
	local padY = math.max(0, math.min((thumbHeight - (h or 0)) / 2 + 4, (limit - (h or 0)) / 2))
	if not E.FrameCheck(slider, "IsProtected") then
		pcall(slider.SetHitRectInsets, slider, -4, -4, -padY, -padY)
	end
	parts.Paint = function()
		if RecordOff(slider) then return end
		local r, g, b = Accent()
		if parts.hover or parts.dragging then
			local lift = E.tokens.slider.hoverLighten
			thumb:SetVertexColor(math.min(1, r + lift), math.min(1, g + lift), math.min(1, b + lift))
			slider:SetBackdropBorderColor(r, g, b)
		else
			thumb:SetVertexColor(r, g, b)
			slider:SetBackdropBorderColor(unpack(E.media.borderColor))
		end
		fill:SetVertexColor(r, g, b, E.tokens.slider.fill)
	end
	slider:HookScript("OnEnter", function() parts.hover = true parts.Paint() end)
	slider:HookScript("OnLeave", function() parts.hover = false parts.Paint() end)
	slider:HookScript("OnMouseDown", function() parts.dragging = true parts.Paint() end)
	slider:HookScript("OnMouseUp", function() parts.dragging = false parts.Paint() end)
	parts.Paint()
	return SetParts(slider, "slider", parts)
end

---------------------------------------------------------------------------
-- Scroll bars
---------------------------------------------------------------------------
-- The thumb every EldoUI scroll bar shares with the kit lists (E.UIKit),
-- in the look of E.tokens.scrollThumb: its color at
-- rest, the accent on hover or drag.
local function PaintThumb(tex, hover)
	if RecordOff(tex) then return end
	local token = E.tokens.scrollThumb
	if hover then
		local r, g, b = Accent()
		ColorTexture(tex, r, g, b, token.hover)
	else
		ColorTexture(tex, unpack(token.color))
	end
end
E.PaintScrollThumb = function(_, tex, hover) PaintThumb(tex, hover) end

local function ThumbVisual(thumb, parts, width)
	local tex = thumb:CreateTexture(nil, "OVERLAY")
	tex:SetPoint("TOP", 0, -1)
	tex:SetPoint("BOTTOM", 0, 1)
	tex:SetWidth(width)
	PaintThumb(tex)
	parts.thumbTex = tex
	if thumb.HookScript then
		thumb:HookScript("OnEnter", function() PaintThumb(tex, true) end)
		thumb:HookScript("OnLeave", function() PaintThumb(tex) end)
	end
end

-- Blizzard's arrow steppers become the EldoUI chevron: the
-- game's art goes invisible, a gray chevron turns accent on hover.
local function SkinStepper(stepper, dir)
	if not Usable(stepper) or GetParts(stepper, "stepper") then return end
	Capture(stepper)
	E:StripTextures(stepper, nil, true)
	AlphaZero(stepper.GetNormalTexture and stepper:GetNormalTexture(),
		stepper.GetPushedTexture and stepper:GetPushedTexture(),
		stepper.GetDisabledTexture and stepper:GetDisabledTexture(),
		stepper.GetHighlightTexture and stepper:GetHighlightTexture(), stepper.Texture, stepper.Overlay)
	local arrow = stepper:CreateTexture(nil, "OVERLAY")
	arrow:SetSize(8, 8)
	arrow:SetPoint("CENTER")
	arrow:SetTexture(E.media.chevron)
	arrow:SetRotation(dir == "up" and math.pi or 0)
	local c = E.tokens.text.secondary
	arrow:SetVertexColor(c[1], c[2], c[3])
	if stepper.HookScript then
		stepper:HookScript("OnEnter", function() arrow:SetVertexColor(Accent()) end)
		stepper:HookScript("OnLeave", function() arrow:SetVertexColor(c[1], c[2], c[3]) end)
	end
	stepper:SetAlpha(1)
	SetParts(stepper, "stepper", { arrow = arrow })
end

-- Handles the modern ScrollBar / MinimalScrollBar (Track + Thumb + Back /
-- Forward) and the old UIPanelScrollBar Slider. opts: width (thumb width).
function E:SkinScrollBar(bar, opts)
	if not Usable(bar) then return end
	local parts = GetParts(bar, "scroll")
	if parts then return parts end
	opts = opts or {}
	Capture(bar)
	local width = opts.width or E.tokens.scrollThumb.width
	parts = {}

	if bar:IsObjectType("Slider") then
		-- Old UIPanelScrollBar: the thumb is a texture of the slider itself.
		local thumb = bar.GetThumbTexture and bar:GetThumbTexture()
		self:StripTextures(bar, thumb and { [thumb] = true } or nil)
		AlphaZero(bar.Background, bar.Track, bar.trackBG, Global(bar, "Track"), Global(bar, "BG"),
			Global(bar, "Top"), Global(bar, "Bottom"), Global(bar, "Middle"))
		if thumb then
			PaintThumb(thumb)
			thumb:SetWidth(width)
			parts.thumbTex = thumb
			if bar.HookScript then
				bar:HookScript("OnEnter", function() PaintThumb(thumb, true) end)
				bar:HookScript("OnLeave", function() PaintThumb(thumb) end)
			end
		end
		SkinStepper(bar.ScrollUpButton or Global(bar, "ScrollUpButton"), "up")
		SkinStepper(bar.ScrollDownButton or Global(bar, "ScrollDownButton"), "down")
		local track = bar:CreateTexture(nil, "BACKGROUND")
		track:SetPoint("TOP", 0, 0)
		track:SetPoint("BOTTOM", 0, 0)
		E:Hairline(track, "w", 2)
		track:SetColorTexture(unpack(E.tokens.track))
		parts.track = track
		local scrollFrame = bar:GetParent()
		if Usable(scrollFrame) and scrollFrame:IsObjectType("ScrollFrame") then
			AlphaZero(Global(scrollFrame, "Top"), Global(scrollFrame, "Bottom"), Global(scrollFrame, "Middle"),
				scrollFrame.ScrollBarTop, scrollFrame.ScrollBarBottom, scrollFrame.ScrollBarMiddle)
		end
		return SetParts(bar, "scroll", parts)
	end

	-- Modern scroll bar.
	local track = (bar.GetTrack and bar:GetTrack()) or bar.Track
	local thumb = (bar.GetThumb and bar:GetThumb()) or (track and track.Thumb)
	self:StripTextures(bar)
	AlphaZero(bar.Background, bar.Backplate)
	if Usable(track) then
		Capture(track)
		self:StripTextures(track)
		local line = track:CreateTexture(nil, "BACKGROUND")
		line:SetPoint("TOP", 0, 0)
		line:SetPoint("BOTTOM", 0, 0)
		E:Hairline(line, "w", 2)
		line:SetColorTexture(unpack(E.tokens.track))
		parts.track = line
	end
	if Usable(thumb) then
		self:StripTextures(thumb)
		AlphaZero(thumb.Begin, thumb.Middle, thumb.End)
		ThumbVisual(thumb, parts, width)
	end
	SkinStepper(bar.Back, "up")
	SkinStepper(bar.Forward, "down")
	return SetParts(bar, "scroll", parts)
end

---------------------------------------------------------------------------
-- Close button
---------------------------------------------------------------------------
function E:SkinCloseButton(button, opts)
	if not Usable(button) then return end
	local parts = GetParts(button, "close")
	if parts then return parts end
	opts = opts or {}
	Capture(button)
	self:StripTextures(button, nil, true)
	AlphaZero(button.GetNormalTexture and button:GetNormalTexture(),
		button.GetPushedTexture and button:GetPushedTexture(),
		button.GetDisabledTexture and button:GetDisabledTexture(),
		button.GetHighlightTexture and button:GetHighlightTexture(), button.Border)
	parts = { lines = {} }
	local size = opts.size or 11
	-- The hover square is the hit rect: a large close button (32 px
	-- templates) clicks only on a 22 px square around the X; a small one
	-- gets a few pixels more (DESIGN.md 3a).
	local w, h = button:GetSize()
	local target = 22
	if not E.FrameCheck(button, "IsProtected") and (w or 0) > 0 then
		local padX, padY = ((w or target) - target) / 2, ((h or target) - target) / 2
		pcall(button.SetHitRectInsets, button, padX, padX, padY, padY)
	end
	parts.area = CreateFrame("Frame", nil, button)
	parts.area:SetSize(target, target)
	parts.area:SetPoint("CENTER")
	parts.area:EnableMouse(false)
	parts.hover, parts.pressed = AddHoverPress(button, parts.area)
	for i, angle in ipairs({ math.rad(45), math.rad(-45) }) do
		local line = button:CreateTexture(nil, "OVERLAY")
		line:SetSize(size, E.pixel * 2)
		line:SetPoint("CENTER", 0, 0)
		line:SetColorTexture(unpack(E.tokens.text.body))
		line:SetRotation(angle)
		parts.lines[i] = line
	end
	button:HookScript("OnEnter", function()
		local r, g, b = Accent()
		for _, line in ipairs(parts.lines) do line:SetColorTexture(r, g, b, 1) end
	end)
	button:HookScript("OnLeave", function()
		for _, line in ipairs(parts.lines) do line:SetColorTexture(unpack(E.tokens.text.body)) end
	end)
	return SetParts(button, "close", parts)
end

---------------------------------------------------------------------------
-- Dropdowns
---------------------------------------------------------------------------
-- Modern DropdownButton (WowStyle1DropdownTemplate) and the old
-- UIDropDownMenuTemplate. opts: size (font size).
function E:SkinDropdown(dropdown, opts)
	if not Usable(dropdown) then return end
	local parts = GetParts(dropdown, "dropdown")
	if parts then return parts end
	opts = opts or {}
	Capture(dropdown, 1)
	parts = {}
	local oldButton = dropdown.Button or Global(dropdown, "Button")
	local isOld = Global(dropdown, "Left") ~= nil or (dropdown.Left ~= nil and oldButton ~= nil)
	local bd = CreateFrame("Frame", nil, dropdown)
	if isOld then
		AlphaZero(dropdown.Left, dropdown.Middle, dropdown.Right,
			Global(dropdown, "Left"), Global(dropdown, "Middle"), Global(dropdown, "Right"))
		bd:SetPoint("TOPLEFT", 18, -3)
		bd:SetPoint("BOTTOMRIGHT", -18, 7)
		-- The old arrow button stays (it opens the list) but draws nothing.
		if Usable(oldButton) then
			AlphaZero(oldButton.GetNormalTexture and oldButton:GetNormalTexture(),
				oldButton.GetPushedTexture and oldButton:GetPushedTexture(),
				oldButton.GetDisabledTexture and oldButton:GetDisabledTexture(),
				oldButton.GetHighlightTexture and oldButton:GetHighlightTexture())
		end
	else
		self:StripTextures(dropdown, KeepIcons(dropdown))
		AlphaZero(dropdown.Background, dropdown.Arrow)
		bd:SetAllPoints()
	end
	bd:SetFrameLevel(math.max(dropdown:GetFrameLevel() - 1, 0))
	E:SetTemplate(bd, true)
	parts.bd = bd
	-- EldoUI's own chevron, 4 px from the right edge.
	parts.arrow = bd:CreateTexture(nil, "OVERLAY")
	parts.arrow:SetSize(10, 10)
	parts.arrow:SetPoint("RIGHT", -6, 0)
	parts.arrow:SetTexture(E.media.chevron)
	parts.arrow:SetVertexColor(unpack(E.tokens.text.secondary))
	local text = dropdown.Text or Global(dropdown, "Text")
	if text and text.SetFont then
		E:SetFont(text, opts.size or E.tokens.size.body)
	end
	parts.hover = bd:CreateTexture(nil, "ARTWORK")
	E:Hairline(parts.hover, "inset", 1, bd)
	parts.hover:SetColorTexture(1, 1, 1, E.tokens.hover.control)
	parts.hover:Hide()
	if dropdown.HookScript then
		dropdown:HookScript("OnEnter", function() if not RecordOff(bd) then parts.hover:Show() end end)
		dropdown:HookScript("OnLeave", function() parts.hover:Hide() end)
		dropdown:HookScript("OnEnter", function()
			bd:SetBackdropBorderColor(Accent())
			parts.arrow:SetVertexColor(Accent())
		end)
		dropdown:HookScript("OnLeave", function()
			bd:SetBackdropBorderColor(unpack(E.media.borderColor))
			parts.arrow:SetVertexColor(unpack(E.tokens.text.secondary))
		end)
	end
	return SetParts(dropdown, "dropdown", parts)
end

---------------------------------------------------------------------------
-- Blizzard menus: the menus MenuUtil opens (value
-- lists, right-click menus) draw on the EldoUI small-box look instead of
-- the game's rounded art, so a list opened from an EldoUI window matches
-- it. Visual only: the style frame's own textures go invisible and a
-- backdrop child sits behind the entries; nothing in the menu changes.
-- Skipped when another UI addon skins the menus. A Blizzard element of its
-- own (Blizzard UI > Right-click and dropdown menus): with its switch off
-- every menu keeps the game's look. Menus are made again each time one
-- opens, so the switch takes effect on the next menu, with no reload.
---------------------------------------------------------------------------
local MENU_STYLES = { "MenuStyle1Mixin", "MenuStyle2Mixin" }
local menuHooked = false

local function SkinMenuStyle(frame)
	if not Usable(frame) then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") then region:SetAlpha(0) end
	end
	local parts = GetParts(frame, "menu")
	if not parts then
		parts = { bd = Backdrop(frame, false) }
		SetParts(frame, "menu", parts)
	end
	parts.bd:Show()
	return parts
end
E.SkinMenuStyle = function(_, frame) return SkinMenuStyle(frame) end

local function OtherMenuSkin()
	local loaded = C_AddOns and C_AddOns.IsAddOnLoaded
	if not loaded then return false end
	for _, name in ipairs({ "ElvUI", "EllesmereUI", "Tukui" }) do
		local ok, on = pcall(loaded, name)
		if ok and on then return true end
	end
	return false
end

-- A menu EldoUI skinned before its switch went off gets the game's art back.
local function UnskinMenuStyle(frame)
	local parts = GetParts(frame, "menu")
	if not parts then return end
	for _, region in ipairs({ frame:GetRegions() }) do
		if region:IsObjectType("Texture") and region ~= parts.bd then region:SetAlpha(1) end
	end
	parts.bd:Hide()
end

local function MenuGenerated(frame)
	if not Usable(frame) then return end
	if E:BlizzardAllowed("menus", "skin") then
		SkinMenuStyle(frame)
	else
		UnskinMenuStyle(frame)
	end
end
E.MenuGenerated = function(_, frame) return MenuGenerated(frame) end

-- Hook the menu style mixins once, when the menus element is switched on;
-- true when hooked.
function E:SkinBlizzardMenus()
	if menuHooked then return true end
	if not self:BlizzardAllowed("menus", "skin") then return false end
	if OtherMenuSkin() then return false end
	for _, key in ipairs(MENU_STYLES) do
		local mixin = rawget(_G, key)
		if type(mixin) == "table" and type(mixin.Generate) == "function" then
			hooksecurefunc(mixin, "Generate", function(frame)
				local ok, err = pcall(MenuGenerated, frame)
				if not ok and E.errors and E.errors.Add then E.errors:Add("warning", "EldoUI menu skin: " .. tostring(err)) end
			end)
			menuHooked = true
		end
	end
	return menuHooked
end

-- The element list loads after this file: the handler joins it once
-- EldoUI has loaded, before the switches are applied at login.
local menuOwner = {}
E:RegisterEvent("ADDON_LOADED", function(_, _, loaded)
	if loaded ~= addonName or not E.RegisterBlizzardHandler then return end
	E:UnregisterEvent("ADDON_LOADED", menuOwner)
	E:RegisterBlizzardHandler("menus", {
		apply = function() E:SkinBlizzardMenus() end,
		-- Nothing to undo now: the next menu that opens keeps the game's look.
		undo = function() end,
		install = { skin = true },
	})
end, menuOwner)

-- Before this switch existed every menu had the EldoUI look. A profile
-- that is set up keeps it, unless it lets EldoUI skin no Blizzard element
-- at all (the setup's "Blizzard's own UI" and "Only EldoUI's own frames"
-- choices skin nothing). A new profile follows the setup.
local function ProfileSkinsBlizzard(profile)
	local all = type(profile.blizzard) == "table" and profile.blizzard
	if not all then return false end
	for id, state in pairs(all) do
		if id ~= "menus" and type(state) == "table" and state.enabled and state.skin then return true end
	end
	return false
end

E:RegisterProfileMigration(function(profile)
	if profile.needsSetup or not ProfileSkinsBlizzard(profile) then return end
	local state = profile.blizzard.menus
	if type(state) ~= "table" then
		state = {}
		profile.blizzard.menus = state
	end
	state.enabled, state.skin = true, true
end, "blizzard:menus", 1)

---------------------------------------------------------------------------
-- List rows
---------------------------------------------------------------------------
local ROW_ART = { "background", "Background", "BG", "Bg", "Stripe", "StripeTexture", "NormalTexture", "Border" }

-- opts: strip (also make every other non-icon texture invisible),
-- divider (default true), stripe alpha (default 0.03).
function E:SkinRow(row, opts)
	if not Usable(row) then return end
	local parts = GetParts(row, "row")
	if parts then return parts end
	opts = opts or {}
	Capture(row)
	for _, key in ipairs(ROW_ART) do
		local region = row[key]
		if type(region) == "table" and region.IsObjectType and region:IsObjectType("Texture") then AlphaZero(region) end
	end
	if row.GetNormalTexture then AlphaZero(row:GetNormalTexture()) end
	if opts.strip then self:StripTextures(row, KeepIcons(row)) end
	parts = {}
	parts.bg = row:CreateTexture(nil, "BACKGROUND", nil, -7)
	parts.bg:SetAllPoints()
	parts.bg:SetColorTexture(1, 1, 1, opts.stripe or 0.03)
	if opts.divider ~= false then
		parts.line = row:CreateTexture(nil, "BACKGROUND", nil, -6)
		parts.line:SetPoint("BOTTOMLEFT", 0, 0)
		parts.line:SetPoint("BOTTOMRIGHT", 0, 0)
		parts.line:SetHeight(E.pixel)
		parts.line:SetColorTexture(unpack(E.tokens.edge.divider))
	end
	local highlight = row.GetHighlightTexture and row:GetHighlightTexture()
	if highlight then
		ColorTexture(highlight, 1, 1, 1, E.tokens.hover.row)
	else
		parts.hover = row:CreateTexture(nil, "HIGHLIGHT")
		parts.hover:SetAllPoints()
		parts.hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	end
	return SetParts(row, "row", parts)
end

-- Selected row: accent tint at 0.25 over the stripe (DESIGN.md, Lists).
function E:SetRowSelected(row, selected)
	local parts = GetParts(row, "row")
	if not parts then return end
	if not parts.selected then
		parts.selected = row:CreateTexture(nil, "BACKGROUND", nil, -5)
		parts.selected:SetAllPoints()
		AccentTexture(parts.selected, 0.25)
		Adopt(parts.selected, row)
	end
	parts.selected:SetShown(selected and not RecordOff(row) and true or false)
end

-- Picks the row frame out of either callback shape: (owner, frame, data)
-- from the acquire event, or (frame, data) from ForEachFrame.
local function PickFrame(a, b)
	if type(b) == "table" and type(b.GetObjectType) == "function" then return b end
	if type(a) == "table" and type(a.GetObjectType) == "function" then return a end
end

-- Run fn(row) on every row the ScrollBox shows now. The rows are read as a
-- plain list, so the list's own row code never runs inside EldoUI's call:
-- a row whose size is secret (the damage meter in combat) would make the
-- game's own math on it fail there. Lists without GetFrames (older
-- templates) use their ForEachFrame.
function E:EachScrollBoxRow(box, fn)
	if not Usable(box) or type(fn) ~= "function" then return end
	if type(box.GetFrames) == "function" then
		local ok, frames = pcall(box.GetFrames, box)
		if not (ok and type(frames) == "table") then return end
		local list = {}
		for i, frame in ipairs(frames) do list[i] = frame end
		for _, frame in ipairs(list) do fn(frame) end
	elseif type(box.ForEachFrame) == "function" then
		pcall(box.ForEachFrame, box, fn)
	end
end

-- Run fn(row) on every row the ScrollBox has now and every row it
-- acquires later. Safe to call twice with the same fn. Hooked inside a
-- record pass, each row joins that record (and is left alone while it is off).
function E:HookScrollBoxRows(box, fn)
	if not Usable(box) or type(fn) ~= "function" then return false end
	boxHooks[box] = boxHooks[box] or {}
	if boxHooks[box][fn] then return true end
	boxHooks[box][fn] = true
	local key = self:SkinRecordKey()
	local function Run(a, b)
		local frame = PickFrame(a, b)
		if frame and Usable(frame) then
			if key then
				E:SkinRecord(key, frame, fn, frame)
			else
				local ok, err = pcall(fn, frame)
				if not ok then geterrorhandler()(err) end
			end
		end
	end
	if ScrollUtil and ScrollUtil.AddAcquiredFrameCallback then
		pcall(ScrollUtil.AddAcquiredFrameCallback, box, Run, owner, false)
	end
	self:EachScrollBoxRow(box, Run)
	return true
end

---------------------------------------------------------------------------
-- Theme changes: accent textures, tab states and fonts follow at once.
---------------------------------------------------------------------------
-- Runs from the theme registry only (E:OnThemeChanged below), once per
-- theme change; the reload buttons repaint in the same pass.
function E:UpdateSkins()
	local r, g, b = Accent()
	for texture, alpha in pairs(accented) do
		if texture.SetColorTexture and not RecordOff(texture) then texture:SetColorTexture(r, g, b, alpha) end
	end
	for _, info in pairs(fonts) do ApplyFont(info) end
	self:UpdateTabs()
	if self.RefreshReloadButtons then self:RefreshReloadButtons() end
end

E:RegisterEvent("PLAYER_LOGIN", function()
	-- Once per theme change: E:RefreshTheme runs E:UpdateArtStyle, which
	-- runs the theme registry. Its own key: the skin manifests keep the
	-- key "skins" for their cache (Core/Skins.lua).
	E:OnThemeChanged("skinWidgets", function() E:UpdateSkins() end)
	-- E:RefreshPixel (UI scale changes) sets every edge back to E.pixel;
	-- windows with their own scale snap to the screen pixel again after it.
	if type(E.RefreshPixel) == "function" then
		hooksecurefunc(E, "RefreshPixel", SnapAll)
	end
	E:UpdateSkins()
	E:SkinBlizzardMenus() -- only when the menus element is switched on
end, owner, "modules")

---------------------------------------------------------------------------
-- Secure reload
--
-- WoW: Forever blocks ReloadUI() when addon code calls it, even inside a
-- click handler or a StaticPopup's OnAccept. A reload has to come from the
-- player's own click on a secure action button that runs the /reload
-- macro. EldoUI therefore never calls ReloadUI(); every "Reload" button is
--   E:CreateReloadButton(parent, label, width, height, work)
-- and every "reload now?" question is
--   E:ShowReloadPrompt(reason, work)
-- `work` (optional) runs right after the click, before the UI reloads
-- (the reload itself happens at the end of the frame). "Later" never runs
-- it. In combat the secure template ignores clicks, so the button grays out
-- and the prompt says to type /reload after combat.
---------------------------------------------------------------------------
local reloadButtons = setmetatable({}, { __mode = "k" })
-- PLAYER_REGEN_DISABLED fires just before InCombatLockdown() turns true,
-- so the event sets this flag as well.
local combatFlag = false

local function InCombat()
	return combatFlag or InCombatLockdown()
end

-- button.primary: the accent edge and a faint fill (the one main action).
-- button.pending (the options window footer): true draws the accent edge
-- while changes wait for a reload, false the muted text while none do.
local function PaintReloadButton(button)
	local combat = InCombat()
	local active = button.hover and not combat
	if active or ((button.primary or button.pending) and not combat) then
		button:SetBackdropBorderColor(Accent())
	else
		button:SetBackdropBorderColor(unpack(E.media.borderColor))
	end
	local r, g, b = Accent()
	button.tint:SetColorTexture(r, g, b, active and 0.18 or ((button.primary and not combat) and 0.1 or 0))
	if combat then
		button.text:SetTextColor(unpack(E.media.text.dim))
	elseif button.pending == false and not active then
		button.text:SetTextColor(unpack(E.tokens.text.secondary))
	else
		button.text:SetTextColor(1, 1, 1)
	end
end

-- Repaint after a theme change (E:UpdateSkins) or when combat starts or ends.
function E:RefreshReloadButtons()
	for button in pairs(reloadButtons) do PaintReloadButton(button) end
end

-- Large text grows the label; the button grows with it so it never clips.
local function FitReloadButton(button)
	local label = button.text
	if not (label and button.baseWidth) then return end
	-- A width the window set later is the button's own width.
	local width = button:GetWidth()
	if button.fitWidth and width ~= button.fitWidth then button.baseWidth = width end
	local want = button.baseWidth
	if E.TextScale and E:TextScale() > 1 then
		want = math.max(want, math.ceil(label:GetStringWidth() + 16))
	end
	if width ~= want then button:SetWidth(want) end
	button.fitWidth = want
end

-- A flat EldoUI button that reloads the UI through the /reload macro.
-- Not a protected frame (the template has no SecureFrameTemplate), so it
-- can be created, shown and moved in combat; only the click does nothing
-- there.
function E:CreateReloadButton(parent, label, width, height, work)
	local button = CreateFrame("Button", nil, parent, "InsecureActionButtonTemplate")
	button:SetSize(width or 112, height or 24)
	-- Fire on mouse up only: with the ActionButtonUseKeyDown CVar on, a
	-- secure action button waits for a key-down that a mouse click
	-- registered for "AnyUp" never sends.
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", "/reload")
	self:SetTemplate(button)
	button.tint = button:CreateTexture(nil, "BORDER")
	button.tint:SetPoint("TOPLEFT", self.pixel, -self.pixel)
	button.tint:SetPoint("BOTTOMRIGHT", -self.pixel, self.pixel)
	button.text = self:CreateText(button, E.tokens.size.body)
	button.text:SetPoint("CENTER")
	button.text:SetText(label or RELOADUI or L["Reload UI"])
	button.work = work
	button:SetScript("OnEnter", function(own)
		own.hover = true
		PaintReloadButton(own)
		if InCombat() then
			GameTooltip:SetOwner(own, "ANCHOR_TOP")
			GameTooltip:SetText(L["Type /reload after combat to apply this."], 1, 1, 1, 1, true)
			GameTooltip:Show()
		end
	end)
	button:SetScript("OnLeave", function(own)
		own.hover = false
		PaintReloadButton(own)
		GameTooltip_Hide()
	end)
	-- The template's OnClick runs the macro; PostClick only adds our work.
	button:SetScript("PostClick", function(own)
		if InCombatLockdown() then -- the template checks the same
			E:Print(L["Type /reload after combat to apply this."])
			return
		end
		if own.work then
			local ok, err = pcall(own.work)
			if not ok then geterrorhandler()(err) end
		end
	end)
	reloadButtons[button] = true
	PaintReloadButton(button)
	button.baseWidth = width or 112
	E:RegisterThemed(button, FitReloadButton)
	FitReloadButton(button)
	return button
end

local prompt

local function UpdatePrompt()
	if not prompt then return end
	local combat = InCombat()
	prompt.combat:SetShown(combat)
	prompt.reload:SetShown(not combat)
	prompt.later:SetText(combat and (OKAY or L["OK"]) or L["Later"])
	prompt:SetButtonFrames({ prompt.reload, prompt.later })
	prompt:Layout()
end

-- The reload question on the shared dialog shell (E.UIKit.CreateDialog):
-- the secure Reload button and a kit "Later" button in its footer row.
local function CreatePrompt()
	local Kit = E.UIKit
	local frame = Kit.CreateDialog("EldoUIReloadPrompt", { title = L["Reload the UI?"] })
	frame.reason = frame.text
	frame.combat = E:CreateText(frame, E.tokens.size.label, "LEFT")
	frame.combat:SetPoint("TOPLEFT", frame.text, "BOTTOMLEFT", 0, -8)
	frame.combat:SetPoint("TOPRIGHT", frame.text, "BOTTOMRIGHT", 0, -8)
	frame.combat:SetWordWrap(true)
	frame.combat:SetTextColor(unpack(E.tokens.text.warn))
	frame.combat:SetText(L["Type /reload after combat to apply this."])

	frame.works = {}
	frame.reload = E:CreateReloadButton(frame, RELOADUI or L["Reload UI"], Kit.DIALOG_BUTTON, E.tokens.height.buttonLarge, function()
		local works = frame.works
		frame.works = {}
		frame:Hide()
		for _, fn in ipairs(works) do
			local ok, err = pcall(fn)
			if not ok then geterrorhandler()(err) end
		end
	end)
	frame.reload.primary = true
	-- "Later" drops the queued work: nothing runs without the reload.
	frame.later = Kit.Button(frame, L["Later"], { width = Kit.DIALOG_BUTTON, large = true, onClick = function() frame:Hide() end })
	local layout = frame.Layout
	function frame:Layout()
		layout(self)
		if self.combat:IsShown() then
			self:SetHeight(self:GetHeight() + 8 + math.ceil(self.combat:GetStringHeight() or 0))
		end
	end
	frame:SetButtonFrames({ frame.reload, frame.later })
	frame:SetScript("OnHide", function()
		frame.works = {}
		frame.reasons = nil
	end)
	frame:Hide()
	return frame
end

-- The question for modules just switched off (a module, its name, or a
-- list of them): only the ones whose reload declaration says so
-- (E:ModuleReloadReasons, Core/Blizzard.lua) are named; nil when none.
local function ModulesOffReason(list)
	if list.name and list.title then list = { list } end
	local titles = {}
	for _, module in ipairs(list) do
		if type(module) == "string" then module = E:GetModule(module) end
		if type(module) == "table" and E:ModuleNeedsReload(module) then titles[#titles + 1] = L[module.title] end
	end
	if #titles == 0 then return nil end
	if #titles == 1 then return L["%s is off. Blizzard's own version comes fully back after a reload."]:format(titles[1]) end
	return L["Switched off: %s. Blizzard's own versions come fully back after a reload."]:format(table.concat(titles, ", "))
end

-- Ask once for a reload. Reasons that arrive while the prompt is open are
-- listed together, so changing three options shows one question. `reason`
-- is the text, or the modules just switched off (see above): then nothing
-- is asked when none of them needs a reload, and nil comes back.
function E:ShowReloadPrompt(reason, work)
	if type(reason) == "table" then
		reason = ModulesOffReason(reason)
		if not reason then return nil end
	end
	prompt = prompt or CreatePrompt()
	if not prompt:IsShown() then prompt.reasons = nil end
	prompt.reasons = prompt.reasons or {}
	reason = reason or L["Some changes take full effect after a reload."]
	if not tContains(prompt.reasons, reason) then table.insert(prompt.reasons, reason) end
	prompt.reason:SetText(table.concat(prompt.reasons, "\n"))
	if work then table.insert(prompt.works, work) end
	prompt:Show()
	prompt:Raise()
	PaintReloadButton(prompt.reload)
	UpdatePrompt()
	return prompt
end
-- The same, under its older name.
E.RequestReload = E.ShowReloadPrompt

function E:HideReloadPrompt()
	if prompt then prompt:Hide() end
end

-- For plugins: the prompt frame, if it was built.
function E:GetReloadPrompt()
	return prompt
end

local function OnCombatChange(_, event)
	combatFlag = event == "PLAYER_REGEN_DISABLED"
	E:RefreshReloadButtons()
	UpdatePrompt()
end
E:RegisterEvent("PLAYER_REGEN_DISABLED", OnCombatChange, reloadButtons)
E:RegisterEvent("PLAYER_REGEN_ENABLED", OnCombatChange, reloadButtons)

---------------------------------------------------------------------------
-- Confirm prompt: EldoUI's own question on the shared dialog shell
-- (E.UIKit.CreateDialog), for choices that are not a reload. Insecure:
-- never use it to run protected work directly; wrap that in
-- E:RunOutOfCombat inside onAccept.
--   E:ShowConfirm{ title = "...", text = "...", accept = "Replace",
--       cancel = "Keep", onAccept = fn(data, text, checked), onCancel = fn(data),
--       danger = true (the accept button is a delete or reset),
--       extra = { label, onClick = fn(data, text, checked) } (a third button),
--       edit = { text, hint, numeric, maxLetters } (a text field; its text
--         goes to onAccept, and Enter accepts),
--       check = { label, desc, checked } (a check under the text),
--       data = anything (handed to the callbacks),
--       key = a name for the question (E:CancelConfirm(key) closes it) }
-- Escape and the cancel button both run onCancel. A new question replaces
-- an open one (its onCancel runs first).
---------------------------------------------------------------------------
local confirm

local function ConfirmValues(frame)
	local text = frame.edit and frame.edit:IsShown() and (frame.edit:GetText() or "") or nil
	local checked = frame.check and frame.check:IsShown() and (frame.check:GetChecked() and true or false) or nil
	return text, checked
end

local function CloseConfirm(answer)
	local frame = confirm
	local accept, cancel, extra = frame.onAccept, frame.onCancel, frame.onExtra
	local data = frame.data
	local text, checked = ConfirmValues(frame)
	frame.onAccept, frame.onCancel, frame.onExtra, frame.data = nil, nil, nil, nil
	frame:Hide()
	local fn, args = cancel, { data }
	if answer == true then
		fn, args = accept, { data, text, checked }
	elseif answer == "extra" then
		fn, args = extra, { data, text, checked }
	end
	if fn then
		local ok, err = pcall(fn, unpack(args, 1, 3))
		if not ok then geterrorhandler()(err) end
	end
end

local function CreateConfirm()
	local Kit = E.UIKit
	local frame = Kit.CreateDialog("EldoUIConfirm", { edit = {}, check = { label = "" } })
	frame.edit:SetScript("OnEnterPressed", function() CloseConfirm(true) end)
	frame:SetButtons({
		{ OKAY or L["OK"], function() CloseConfirm(true) end, keepOpen = true, kind = "primary" },
		{ "", function() CloseConfirm("extra") end, keepOpen = true },
		{ CANCEL or L["Cancel"], function() CloseConfirm(false) end, keepOpen = true },
	})
	frame.accept, frame.extra, frame.cancel = frame.buttons[1], frame.buttons[2], frame.buttons[3]
	-- Escape hides the frame: that counts as cancel.
	frame:SetScript("OnHide", function(own)
		if own.onCancel or own.onAccept or own.onExtra then
			local cancel, data = own.onCancel, own.data
			own.onAccept, own.onCancel, own.onExtra, own.data = nil, nil, nil, nil
			if cancel then
				local ok, err = pcall(cancel, data)
				if not ok then geterrorhandler()(err) end
			end
		end
	end)
	frame:Hide()
	return frame
end

function E:ShowConfirm(info)
	info = info or {}
	confirm = confirm or CreateConfirm()
	if confirm:IsShown() then CloseConfirm(false) end
	confirm.title:SetText(info.title or L["Are you sure?"])
	confirm.text:SetText(info.text or "")
	confirm.accept:SetText(info.accept or (OKAY or L["OK"]))
	confirm.cancel:SetText(info.cancel or (CANCEL or L["Cancel"]))
	E.UIKit.SetButtonKind(confirm.accept, info.danger and "danger" or "primary")
	local extra = info.extra
	confirm.extra:SetShown(extra ~= nil)
	if extra then confirm.extra:SetText(extra[1] or extra.label or "") end
	for _, button in ipairs(confirm.buttons) do E.UIKit.FitButton(button, E.UIKit.DIALOG_BUTTON) end
	local edit = info.edit
	confirm.edit:SetShown(edit ~= nil)
	if edit then
		confirm.edit:SetNumeric(edit.numeric and true or false)
		confirm.edit:SetMaxLetters(edit.maxLetters or 0)
		confirm.edit:SetText(edit.text or "")
		confirm.edit:SetHint(edit.hint)
	end
	local check = info.check
	confirm.check:SetShown(check ~= nil)
	if check then
		confirm.check:SetLabel(check.label)
		confirm.check:SetChecked(check.checked and true or false)
		E.UIKit.Tooltip(confirm.check, check.desc and check.label or nil, check.desc)
	end
	confirm.onAccept, confirm.onCancel = info.onAccept, info.onCancel
	confirm.onExtra = extra and (extra[2] or extra.onClick) or nil
	confirm.data = info.data
	confirm.key = info.key
	confirm:SetButtonFrames(confirm.buttons)
	confirm:Show()
	confirm:Raise()
	confirm:Layout()
	if edit then
		confirm.edit:SetFocus()
		confirm.edit:HighlightText()
	end
	return confirm
end

-- For plugins: the confirm frame, if it was built.
function E:GetConfirm()
	return confirm
end

-- Cancel the open question when its key matches (nil: any question), for
-- a question whose moment passed (the vendor closed, an offer ran out).
function E:CancelConfirm(key)
	if confirm and confirm:IsShown() and (key == nil or confirm.key == key) then CloseConfirm(false) end
end

-- Answer the open question as if a button was clicked (for plugins).
-- accepted: true (accept), false (cancel) or "extra" (the third button).
function E:AnswerConfirm(accepted)
	if confirm and confirm:IsShown() then
		CloseConfirm(accepted == "extra" and "extra" or (accepted and true or false))
	end
end

---------------------------------------------------------------------------
-- E.WindowKit, part one: EldoUI's own windows (installer, setup pages).
-- One shell for every window EldoUI draws itself, so they all share the
-- options window's look: art-style panel, an inset sidebar with the logo,
-- a header with the accent line, a footer for the buttons. Modules/Skins.lua
-- adds the helpers that dress Blizzard's windows to the same table.
--
--   Kit.CreateWindow(name, opts)  the shell; opts: width, height, strata,
--                                 sidebar (width, 0 = none), logo, footer
--                                 (height, default 44), escape (default true),
--                                 search (box, or a function that returns it),
--                                 keys (handle(name, key) for its own keys),
--                                 resizable (the kit grip: true, or
--                                 { minWidth, minHeight, maxWidth, maxHeight };
--                                 off by default, for fixed pages),
--                                 sizeStore (table or fn: where w, h are kept;
--                                 default EldoUIDB.windowSizes[name]),
--                                 onResize (fn(window) after a drag),
--                                 dialog (layering: default true for the
--                                 DIALOG and FULLSCREEN_DIALOG stratas),
--                                 options (an options link target, see
--                                 E:BindOptionsLink: the header's tooltip
--                                 names it, Ctrl-click there opens it);
--                                 window:SetOptionsLink(target) sets it later,
--                                 window:SetKeys(spec) changes them later,
--                                 window:ResetSize() goes back to the design size
--   Kit.Button(parent, { text, width, large, onClick, tip }) (or the
--     older text, width, onClick[, large]),
--   Kit.Check, Kit.Choice, Kit.Paragraph, Kit.Secondary,
--   Kit.Tooltip, Kit.Divider      the small parts pages are built from
---------------------------------------------------------------------------
local Kit = E.WindowKit or {}
E.WindowKit = Kit

Kit.SECONDARY = E.tokens.text.secondary
Kit.INSET_TINT = E.tokens.inset

function Kit.Secondary(fontString)
	fontString:SetTextColor(unpack(Kit.SECONDARY))
	return fontString
end

-- Window text: no outline, a soft shadow (E:SetWindowFont).
function Kit.Paragraph(parent, size, text)
	local fontString = E:CreateText(parent, size or E.tokens.size.body, "LEFT")
	E:SetWindowFont(fontString, size or E.tokens.size.body)
	fontString:SetWordWrap(true)
	fontString:SetJustifyV("TOP")
	fontString:SetText(text or "")
	return fontString
end

-- Kit.Tooltip, Kit.Button(parent, text, width, onClick[, large]) and
-- Kit.Check are the E.UIKit parts, so the installer, plugin pages and kit
-- windows share one button, one check and one tooltip. Files
-- that load before Core/UIKit.lua keep these forwarders in locals.
function Kit.Tooltip(frame, title, text)
	return E.UIKit.Tooltip(frame, title, text)
end

-- `large` gives the footer height (height.buttonLarge); every button of a
-- window's footer row is large, every other button height.button.
-- The options form is the same as E.UIKit.Button's:
--   Kit.Button(parent, { text, width, large, kind, onClick, tip })
-- (width nil: as wide as the label). The positional form stays for older code.
function Kit.Button(parent, text, width, onClick, large)
	if type(text) == "table" then return E.UIKit.Button(parent, text) end
	return E.UIKit.Button(parent, text, { width = width or 120, large = large, onClick = onClick })
end

-- A check box with its label; `desc` becomes the tooltip.
function Kit.Check(parent, label, desc, onClick)
	return E.UIKit.Check(parent, label, desc, onClick)
end

-- A thin divider line across `parent` at `y` from its top (edge.divider).
function Kit.Divider(parent, y, alpha)
	local line = parent:CreateTexture(nil, "ARTWORK")
	local c = E.tokens.edge.divider
	line:SetColorTexture(c[1], c[2], c[3], alpha or c[4])
	E:Hairline(line, "h", 1)
	line:SetPoint("TOPLEFT", 0, -(y or 0))
	line:SetPoint("TOPRIGHT", 0, -(y or 0))
	return line
end

-- A sidebar row of the full windows (the options window's page tree and
-- the installer's steps), so both sidebars look and react the same:
-- borderless, the hover overlay (it fades) and the pressed tint, and on the
-- open row a 2 px accent bar on the left with an accent tint fading to the
-- right. row.tint and row.bar are its parts; the caller adds the text.
--   local row = Kit.NavRow(parent, width, height)
--   Kit.PaintNavRow(row, selected)          the look at once
--   Kit.SoftNavRow(row, selected[, ident])  eases into it (E.UIKit
--       SoftSelect: the bar and tint fade in and out; a row reused for
--       another item, a new ident, changes at once)
function Kit.NavRow(parent, width, height)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(width, height)
	row.tint = row:CreateTexture(nil, "BORDER")
	row.tint:SetAllPoints()
	row.tint:SetColorTexture(0, 0, 0, 0)
	row.bar = row:CreateTexture(nil, "ARTWORK")
	row.bar:SetPoint("TOPLEFT")
	row.bar:SetPoint("BOTTOMLEFT")
	E:Hairline(row.bar, "w", 2)
	row.bar:Hide()
	local hover, pressed = AddHoverPress(row)
	hover:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	SetParts(row, "nav", { hover = hover, pressed = pressed })
	E:RegisterThemed(row, function(self) if self.kitSelected then Kit.PaintNavRow(self, true) end end)
	return row
end

function Kit.PaintNavRow(row, selected)
	row.kitSelected = selected and true or nil
	local r, g, b = Accent()
	row.bar:SetColorTexture(r, g, b, 1)
	row.bar:SetShown(selected and true or false)
	if not selected then
		row.tint:SetColorTexture(0, 0, 0, 0)
	elseif CreateColor then
		row.tint:SetColorTexture(1, 1, 1, 1)
		row.tint:SetGradient("HORIZONTAL", CreateColor(r, g, b, E.tokens.pressed), CreateColor(r, g, b, 0))
	else
		row.tint:SetColorTexture(r, g, b, E.tokens.pressed)
	end
end

function Kit.SoftNavRow(row, selected, ident)
	local UIKit = E.UIKit
	if UIKit and UIKit.SoftSelect then
		UIKit.SoftSelect(row, selected, Kit.PaintNavRow, { row.tint, row.bar }, ident)
	else
		Kit.PaintNavRow(row, selected)
	end
end

-- The skin's divider on a header's accent line. Under a native skin its
-- divider art (cut in three: both ends stretch, the ornament in the middle
-- keeps its size) lies centered on the line, the ornament on top of it; the
-- accent line itself stays. The five classic skins show the line alone.
-- E:SkinHeaderDivider(line) adds it to any header line (tool windows, the
-- options window); it follows every skin change.
local headerDividers = setmetatable({}, { __mode = "k" })  -- line -> { left, middle, right }
local DIVIDER_TEXELS = 2                                    -- texels per UI pixel of the skin art

local function PaintHeaderDivider(line)
	local pieces = headerDividers[line]
	if not pieces then return end
	local m = E:SkinManifest()
	local file = not m.legacy and m.data and m.data.files and m.data.files.divider
	if not file then
		pieces.left:Hide(); pieces.middle:Hide(); pieces.right:Hide()
		return
	end
	local slices = m.data.metrics.divider and m.data.metrics.divider.slices or { 0, 112, 144, 256 }
	local width = slices[4] - slices[1]
	local a, b = (slices[2] - slices[1]) / width, (slices[3] - slices[1]) / width
	local height = 16 / DIVIDER_TEXELS
	pieces.middle:SetSize((slices[3] - slices[2]) / DIVIDER_TEXELS, height)
	pieces.left:SetHeight(height)
	pieces.right:SetHeight(height)
	pieces.left:SetTexCoord(0, a, 0, 1)
	pieces.middle:SetTexCoord(a, b, 0, 1)
	pieces.right:SetTexCoord(b, 1, 0, 1)
	for _, piece in pairs(pieces) do
		piece:SetTexture(file)
		piece:SetVertexColor(1, 1, 1, 1)
		piece:Show()
	end
end

function E:SkinHeaderDivider(line)
	if not (line and line.GetParent and line:GetParent()) or headerDividers[line] then return headerDividers[line] end
	local parent = line:GetParent()
	local pieces = {
		left = parent:CreateTexture(nil, "ARTWORK", nil, -1),
		middle = parent:CreateTexture(nil, "ARTWORK", nil, 2),
		right = parent:CreateTexture(nil, "ARTWORK", nil, -1),
	}
	pieces.middle:SetPoint("CENTER", line, "CENTER")
	pieces.left:SetPoint("LEFT", line, "LEFT")
	pieces.left:SetPoint("RIGHT", pieces.middle, "LEFT")
	pieces.right:SetPoint("LEFT", pieces.middle, "RIGHT")
	pieces.right:SetPoint("RIGHT", line, "RIGHT")
	headerDividers[line] = pieces
	PaintHeaderDivider(line)
	self:RegisterThemed(pieces.middle, function() PaintHeaderDivider(line) end)
	return pieces
end

-- The soft accent glow behind a page title, fading downward (the options
-- window and the installer). Drawn by code, so it follows the accent.
function Kit.HeaderGlow(header)
	local glow = header:CreateTexture(nil, "BACKGROUND")
	glow:SetAllPoints()
	glow:SetTexture(E.media.flat)
	Kit.PaintHeaderGlow(glow)
	E:RegisterThemed(header, function() Kit.PaintHeaderGlow(glow) end)
	return glow
end

function Kit.PaintHeaderGlow(glow)
	if not (glow and CreateColor) then return end
	local r, g, b = Accent()
	glow:SetGradient("VERTICAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, E.tokens.headerGlow))
end

-- A flat selectable box with a title and an optional description (cards,
-- choices, small pick buttons). The selected one gets the accent border.
function Kit.Choice(parent, width, height, title, desc, onClick)
	local choice = CreateFrame("Button", nil, parent)
	choice:SetSize(width, height)
	E:SetTemplate(choice, true)
	-- Hover: white overlay and an accent edge (the selected one keeps
	-- its accent edge); a press tints it. The box is the hit rect.
	local hover, pressed = AddHoverPress(choice)
	E:Hairline(hover, "inset", 1, choice)
	E:Hairline(pressed, "inset", 1, choice)
	choice:HookScript("OnEnter", function(self)
		if not self.selected and self:IsEnabled() then self:SetBackdropBorderColor(Accent()) end
	end)
	choice:HookScript("OnLeave", function(self)
		if not self.selected then self:SetBackdropBorderColor(unpack(E.media.borderColor)) end
	end)
	choice.fill = choice:CreateTexture(nil, "BACKGROUND", nil, 1)
	E:Hairline(choice.fill, "inset", 1, choice)
	choice.fill:SetColorTexture(1, 1, 1, 0)
	choice.title = E:CreateText(choice, E.tokens.size.body, "LEFT")
	choice.title:SetText(title)
	if desc then
		choice.title:SetPoint("TOPLEFT", 10, -8)
		choice.title:SetPoint("TOPRIGHT", -10, -8)
		choice.desc = Kit.Secondary(E:CreateText(choice, E.tokens.size.small, "LEFT"))
		choice.desc:SetPoint("TOPLEFT", choice.title, "BOTTOMLEFT", 0, -4)
		choice.desc:SetWidth(math.max(width - 20, 1))
		choice.desc:SetJustifyV("TOP")
		choice.desc:SetWordWrap(true)
		choice.desc:SetText(desc)
	else
		choice.title:SetPoint("LEFT", 8, 0)
		choice.title:SetPoint("RIGHT", -8, 0)
		choice.title:SetJustifyH("CENTER")
	end
	choice.SetSelected = function(self, on)
		self.selected = on and true or false
		if on then
			local r, g, b = Accent()
			self:SetBackdropBorderColor(r, g, b, 1)
			self.fill:SetColorTexture(r, g, b, E.tokens.pressed)
			self.title:SetTextColor(1, 1, 1)
		else
			self:SetBackdropBorderColor(unpack(E.media.borderColor))
			self.fill:SetColorTexture(1, 1, 1, 0)
			self.title:SetTextColor(unpack(E.media.text.body))
		end
	end
	choice.SetEnabledLook = function(self, on)
		self:SetEnabled(on)
		self:SetAlpha(on and 1 or E.tokens.disabledAlpha)
	end
	-- The card grows with its description (the given height is the least
	-- it has), so a longer text or Large text wraps instead of being cut.
	-- A caller that anchors the description elsewhere (two points)
	-- keeps its fixed height. Returns the height the card has now.
	choice.minHeight = height
	choice.FitHeight = function(self)
		local text = self.desc
		if not text or text:GetNumPoints() ~= 1 then
			if self.minHeight and math.abs((self:GetHeight() or 0) - self.minHeight) > 0.5 then self:SetHeight(self.minHeight) end
			return self:GetHeight()
		end
		text:SetWidth(math.max((self:GetWidth() or 0) - 20, 1))
		local need = math.ceil(8 + (self.title:GetStringHeight() or 0) + 4 + (text:GetStringHeight() or 0) + 8)
		local fit = math.max(self.minHeight or 0, need)
		if math.abs((self:GetHeight() or 0) - fit) > 0.5 then self:SetHeight(fit) end
		return fit
	end
	choice:HookScript("OnSizeChanged", function(self) self:FitHeight() end)
	choice:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		if onClick then onClick(self) end
	end)
	choice:SetSelected(false)
	choice:FitHeight()
	-- The selected look reads the accent: repaint it on a theme change;
	-- a new font or text size measures the card again.
	E:RegisterThemed(choice, function(self)
		if self.selected then self:SetSelected(true) end
		self:FitHeight()
	end)
	return choice
end

---------------------------------------------------------------------------
-- Pixel-exact windows (DESIGN.md 3a). UIParent draws the 1440-unit
-- layout canvas, so below 1440p one unit is less than a screen pixel (0.75
-- on 1920x1080) and a window's 13 pt text reads small and soft. EldoUI's own
-- windows (the options window, the installer, WindowKit and UIKit windows)
-- take a scale of their own so one window unit is one screen pixel:
-- (768 / screen height) / UIParent's scale. Never below 1, so 4K keeps the
-- 1440p size and a large UI scale the player picked stays large.
--   E:WindowBaseScale()                 that factor
--   E:WindowScale(user, width, height)  base x the player's window size,
--                                       shrunk so width x height fits
---------------------------------------------------------------------------
function E:WindowBaseScale()
	local parent = UIParent and UIParent:GetEffectiveScale()
	local _, height = GetPhysicalScreenSize()
	if type(parent) ~= "number" or parent <= 0 or type(height) ~= "number" or height <= 0 then return 1 end
	return math.max(1, 768 / height / parent)
end

function E:WindowScale(user, width, height)
	local scale = self:WindowBaseScale() * (tonumber(user) or 1)
	if tonumber(width) and tonumber(height) and width > 0 and height > 0 then
		local fit = math.min((UIParent:GetHeight() - 40) / height, (UIParent:GetWidth() - 40) / width)
		scale = math.min(scale, fit)
	end
	return math.max(0.3, scale)
end

-- WindowKit windows follow a new UI scale or screen size while shown.
local kitWindows = setmetatable({}, { __mode = "k" })
local kitPixelHooked = false

function Kit.ApplyScale(window)
	local scale = E:WindowScale(window.userScale or 1, window:GetWidth(), window:GetHeight())
	if math.abs((window:GetScale() or 1) - scale) > 0.0005 then window:SetScale(scale) end
	if window.kitSnapped ~= scale then
		window.kitSnapped = scale
		E:SnapBorders(window)
	end
	return scale
end

-- The window shell. Returns the frame with these parts:
--   window.sidebar  inset box on the left (when opts.sidebar > 0), logo on top
--   window.header   title (window.title), subtitle (window.subtitle), the
--                   accent line under it and window.headerRight for extras
--   window.content  the page area
--   window.footer   the button strip at the bottom
--   window.close    the close button
function Kit.CreateWindow(name, opts)
	opts = opts or {}
	local sidebarWidth = opts.sidebar or 0
	local footerHeight = opts.footer or 44
	local window = CreateFrame("Frame", name, UIParent)
	window:SetSize(opts.width or 880, opts.height or 600)
	window:SetPoint("CENTER", 0, opts.y or 40)
	window:SetFrameStrata(opts.strata or "HIGH")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:SetClampedToScreen(true)
	E:SetPanelTemplate(window)
	E:SetWindowEdge(window)
	if name and opts.escape ~= false then table.insert(UISpecialFrames, name) end

	local function Draggable(frame)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function() window:StartMoving() end)
		frame:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
	end
	Draggable(window)

	local left = 8
	if sidebarWidth > 0 then
		local sidebar = CreateFrame("Frame", nil, window)
		sidebar:SetPoint("TOPLEFT", 8, -8)
		sidebar:SetPoint("BOTTOMLEFT", 8, 8)
		sidebar:SetWidth(sidebarWidth)
		E:SetTemplate(sidebar, true)
		sidebar:SetBackdropColor(unpack(Kit.INSET_TINT))
		Draggable(sidebar)
		window.sidebar = sidebar
		if opts.logo then
			local logo = sidebar:CreateTexture(nil, "ARTWORK")
			logo:SetTexture(E.media.logo)
			logo:SetSize(sidebarWidth - 24, math.floor((sidebarWidth - 24) / 4))
			logo:SetPoint("TOP", 0, -8)
			sidebar.logo = logo
		end
		left = 8 + sidebarWidth + 16
	end

	local header = CreateFrame("Frame", nil, window)
	header:SetPoint("TOPLEFT", left, -8)
	header:SetPoint("TOPRIGHT", -8, -8)
	header:SetHeight(opts.headerHeight or 64)
	Draggable(header)
	window.header = header
	-- A full window (with a sidebar) has the options window's header: the
	-- page title size and the soft accent glow behind it.
	local full = sidebarWidth > 0
	if full then window.headerGlow = Kit.HeaderGlow(header) end
	local titleSize = full and E.tokens.size.pageTitle or E.tokens.size.windowTitle
	window.title = E:CreateText(header, titleSize, "LEFT")
	E:SetWindowFont(window.title, titleSize, true)
	window.title:SetTextColor(1, 1, 1)
	window.title:SetPoint("TOPLEFT", full and 4 or 0, -8)
	window.subtitle = Kit.Secondary(Kit.Paragraph(header, 12, ""))
	window.subtitle:SetPoint("TOPLEFT", window.title, "BOTTOMLEFT", 0, -6)
	-- The subtitle wraps at the header's width. A width, not a point on the
	-- header's right middle, which would pull its box up into the title.
	local subtitleInset = (full and 4 or 0) + 40
	local function FitSubtitle()
		local width = header:GetWidth() or 0
		if width > subtitleInset then window.subtitle:SetWidth(width - subtitleInset) end
	end
	header:HookScript("OnSizeChanged", FitSubtitle)
	window:HookScript("OnSizeChanged", FitSubtitle)
	FitSubtitle()
	window.subtitle:SetMaxLines(2)
	window.headerLine = header:CreateTexture(nil, "ARTWORK")
	E:Hairline(window.headerLine, "h", 2)
	window.headerLine:SetPoint("BOTTOMLEFT")
	window.headerLine:SetPoint("BOTTOMRIGHT")
	E:AccentTexture(window.headerLine, 1)
	window.headerDivider = E:SkinHeaderDivider(window.headerLine)
	-- Small extras (step counter, help button) right of the title.
	window.headerRight = CreateFrame("Frame", nil, header)
	window.headerRight:SetPoint("TOPRIGHT", -32, -6)
	window.headerRight:SetSize(1, 26)

	window.close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	window.close:SetSize(24, 24)
	window.close:SetPoint("TOPRIGHT", -4, -4)
	E:SkinCloseButton(window.close)
	window.close:SetScript("OnClick", function() window:Hide() end)

	local footer = CreateFrame("Frame", nil, window)
	footer:SetPoint("BOTTOMLEFT", left, 8)
	footer:SetPoint("BOTTOMRIGHT", -8, 8)
	footer:SetHeight(footerHeight)
	window.footer = footer
	local footerLine = footer:CreateTexture(nil, "ARTWORK")
	footerLine:SetColorTexture(unpack(E.tokens.edge.divider))
	E:Hairline(footerLine, "h", 1)
	footerLine:SetPoint("TOPLEFT")
	footerLine:SetPoint("TOPRIGHT")

	window.content = CreateFrame("Frame", nil, window)
	window.content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -16)
	if opts.resizable then
		-- The footer row stops short of the corner grip; the page keeps
		-- the full width.
		footer:SetPoint("BOTTOMRIGHT", -(8 + E.tokens.grip.size), 8)
		window.content:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -16, footerHeight + 20)
	else
		window.content:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", -8, 12)
	end

	-- The subline under the title: secondary gray, or the one colored line
	-- of a window that names a character or an item (class or quality
	-- color). color: { r, g, b }, "accent", or a text token ("good",
	-- "warn", "bad", "gold"); nil goes back to the secondary gray.
	local function PaintSubtitle(subtitle)
		local color = subtitle.kitColor
		if color == "accent" then
			subtitle:SetTextColor(E.UIKit.Accent())
		elseif type(color) == "string" and E.tokens.text[color] then
			subtitle:SetTextColor(unpack(E.tokens.text[color]))
		elseif type(color) == "table" and type(color[1]) == "number" then
			subtitle:SetTextColor(color[1], color[2], color[3])
		else
			subtitle:SetTextColor(unpack(Kit.SECONDARY))
		end
	end
	E:RegisterThemed(window.subtitle, PaintSubtitle)
	function window:SetSubtitleColor(color)
		self.subtitle.kitColor = color
		PaintSubtitle(self.subtitle)
	end
	window.SetTitle = function(self, title, subtitle, color)
		self.title:SetText(title or "")
		self.subtitle:SetText(subtitle or "")
		self:SetSubtitleColor(color)
	end
	-- The options link: Ctrl-click on the header opens the window's own
	-- settings; the header's tooltip (title, how to move it) names it.
	function window:SetOptionsLink(target)
		self.optionsLink = target
		if self.optionsBound or target == nil then return end
		self.optionsBound = true
		E.UIKit.Tooltip(header, nil, function(tooltip)
			if not window.optionsLink then return end
			E.UIKit.TipTitle(tooltip, window.title:GetText())
			E.UIKit.TipText(tooltip, L["Drag to move the window."])
		end)
		E:BindOptionsLink(header, function() return window.optionsLink end)
	end
	if opts.options then window:SetOptionsLink(opts.options) end
	-- One window unit is one screen pixel, set each time it opens.
	kitWindows[window] = true
	window:HookScript("OnShow", Kit.ApplyScale)
	if not kitPixelHooked and E.RegisterPixelCallback then
		kitPixelHooked = true
		E:RegisterPixelCallback(function()
			for frame in pairs(kitWindows) do
				if frame:IsShown() then Kit.ApplyScale(frame) end
			end
		end)
	end
	-- Every EldoUI window has the same keys (Ctrl+F, then Esc clears a
	-- search before it closes), out of combat only.
	if E.UIKit and E.UIKit.WindowKeys then
		E.UIKit.WindowKeys(window, { search = opts.search, handle = opts.keys })
		window.SetKeys = function(self, spec)
			spec = spec or {}
			if type(spec.search) == "table" then E.UIKit.SearchEscape(spec.search) end
			self.keys.spec = spec
		end
	end
	-- The kit grip (E.UIKit.SizeGrip): dragging changes the size, never the
	-- scale; the size is kept per window and comes back next time.
	local UI = E.UIKit
	if opts.resizable and UI and UI.SizeGrip then
		local bounds = type(opts.resizable) == "table" and opts.resizable or {}
		local width, height = opts.width or 880, opts.height or 600
		window.grip = UI.SizeGrip(window, { resize = true, width = width, height = height,
			minWidth = bounds.minWidth or width, minHeight = bounds.minHeight or height,
			maxWidth = bounds.maxWidth, maxHeight = bounds.maxHeight,
			store = function()
				local store = opts.sizeStore
				if type(store) == "function" then store = store() end
				return UI.WindowSizeStore(name, store)
			end,
			onStop = function()
				Kit.ApplyScale(window)
				if opts.onResize then opts.onResize(window) end
			end })
		window.grip:Restore()
	end
	function window:ResetSize()
		if self.grip then self.grip:ResetSize() else self:SetSize(opts.width or 880, opts.height or 600) end
	end
	window:Hide()
	-- Every EldoUI window slides in the same way.
	window:HookScript("OnShow", function(self) E:SlideIn(self, "DOWN") end)
	-- One layering rule (E.UIKit.Layer): a click brings it to the front, a
	-- dialog opened from another EldoUI window sits above it. Escape goes
	-- through the window keys above.
	if UI and UI.Layer then
		local dialog = opts.dialog
		if dialog == nil then dialog = opts.strata == "DIALOG" or opts.strata == "FULLSCREEN_DIALOG" end
		window.kitClose = window.kitClose or function() window:Hide() end
		UI.Layer(window, { dialog = dialog, escape = window.keys == nil })
	end
	return window
end
