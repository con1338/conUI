-- EldoUI config window. One window in the EldoUI design system (DESIGN.md):
-- an art-style panel, theme fonts, flat boxes and the accent color for
-- whatever is selected or active.
--
--   +-----------------------+--------------------------------------------+
--   | logo                  | Hub or page title              [- 100% +] [x]|
--   | # Keybind mode        | one muted line                             |
--   | * Global settings     | Page  Page  Page          [search] [Share v]|
--   | o Profiles            |   Tab  Tab  Tab   (a hub page's own tabs)  |
--   | [Search features]     | Section                                    |
--   |   Layout and style    | label  [control] | label  [control]        |
--   |   Modules             | label  [control] | label  [control]        |
--   |   Lists and tags      |                                            |
--   | v Chat and Social   7 |                                            |
--   |    Chat           (o) |                                            |
--   | > Bags and Economy  8 |                                            |
--   | --------------------- |                                            |
--   | What's new  Errors (2)|                                            |
--   | v0.6.0  Memory 12 MB  | [Reset X] [Reload UI (2)] [Move mode] [Recent] [Done]/|
--
-- The sidebar (DESIGN.md 3b): three quick actions, the Search features box,
-- one row per hub (its general pages are the tabs at the top of the hub
-- page), then the module groups with one row per module and its power
-- switch, and the foot with What's new, Errors and the version line. A
-- page's tabs show only at the top of the page. The footer has one primary
-- button (Done); Reload UI counts the changes that wait for a reload, and
-- Move mode sits right after it on every page. The
-- corner grip resizes the window (saved per account).
--
-- Modules describe their settings declaratively:
--   M.options = {
--       { type = "tab", label = "Display" },           -- starts a tab (optional;
--                                                         oneColumn = true: one row per line)
--       { type = "header", label = "Size" },           -- starts a section
--       { type = "toggle", key = "showZone", label = "Show zone name", desc = "..." },
--       { type = "range", key = "size", label = "Size", min = 150, max = 400, step = 1 },
--       { type = "select", key = "portrait", label = "Show", values = { none = "None", left = "Left" } },
--       { type = "color", key = "color", label = "Color" },          -- { r, g, b } table
--       { type = "input", key = "name", label = "Name" },
--       { type = "execute", label = "Reset", func = function() end },
--       { type = "description", label = "Free text" },
--   }
--       { type = "media", key = "sound", label = "Sound", mediaKind = "sound" }, -- registry picker
-- A sound row (media with mediaKind "sound", or a select with sound = true)
-- gets a speaker to play the chosen sound and one on every list entry;
-- `channel` names the setting that holds its volume channel.
-- `key` is a dotted path into the module's settings ("units.player.width"),
-- or a function returning one.
-- `values` may be a function; `hidden` may be a boolean or a function.
-- A select with `wide = true` (on a oneColumn tab) gets room for long
-- choice names.
-- A select's `order` (a list of values, or a function returning one) shows
-- those first, in that order (a ladder such as Off, Subtle, Standard,
-- Vivid); the rest by name. Its
-- `valueDescs` ({ [value] = "one sentence" }, or a function returning one)
-- gives a choice in the list its own tooltip. Its `valueDisabled`
-- (function(value) returning nil, or the translated reason) grays a choice
-- that can't be taken right now and shows the reason in its tooltip.
-- `reload = true` marks an option that needs a reload: the footer's
-- Reload UI button (the secure /reload) counts them, names them in its
-- tooltip, and the window asks once when it closes. `reload = "off"` is for
-- a toggle that applies at once when turned on and needs a reload only to
-- take a change back off (most skins): it counts only for on to off.
-- A page without "tab" entries shows no tab bar.
-- Every change calls module:OnProfileChanged() so the module re-applies.
-- Plugins get a page in the same window by setting M.options too.
--
-- More fields, all optional:
--   desc        one plain sentence for the tooltip (every option has one)
--   hint        on a header: a few muted words after the section label
--   keywords    "word word" or { "word", ... }: extra words the search finds
--   requires    function() return bool end: probed once when the page is
--               built; false hides the row (or tab / section) for good,
--               e.g. a feature this client or class doesn't have
--   requiresAPI "C_Foo.Bar" or a list of them: the same, as an API probe
--   disabled    true, or a function returning true or a reason ("Controlled
--               by Party and Raid"): the row stays visible but grayed, and the
--               reason shows in its tooltip
--   dependsOn   key of the toggle this row needs ("castbar.enabled"): the
--               row is grayed with "Turn on <that> first" while it is off,
--               and the search points there when the row is hidden
--   cog         { options }: rare sub-settings of this row, shown in a small
--               popup from a gear on the row; grayed while the row (a
--               toggle) is off
--   confirm     (execute) true: the button asks first, with its label and
--               desc (plus "This can't be undone."), for work that can't be
--               undone; a text (or a function returning one) asks that
--               question instead, for a desc that only fits the page.
--               The accept button repeats the label in the danger look;
--               `confirmAccept` gives a shorter word, `confirmDanger =
--               false` the normal look for work that deletes nothing
--   noUndo      true: an action row (copy, delete, "set every module")
--               whose setter runs once and keeps no value; it stays out of
--               Recent changes, since Undo could not take it back
--   status      (header) function() return text end: a short state after
--               the section title, read again on every refresh
--   unit        range only: "s", "px", "yd", "ms", "%" shown after the
--               number ("0.5 s"); keep units out of the label
--   percent     range only: true stores 0-1 and shows 0-100 % ("85 %")
--   zeroText    range only: what the box shows at 0 ("Auto", "Off", "Full
--               width"); keep "(0 = ...)" out of the label
--   softMax     range only: where the slider ends; the box still takes
--               values up to max (money and other wide ranges)
--               A range applies when the slider is released, not on every
--               step of a drag (DESIGN.md 5).
--   preview     range only: function(value) for a cheap live preview while
--               the slider is dragged (one sample text, one frame)
--   live        range only: true applies on every step of a drag; only for
--               a setting that costs nothing to apply
--   less        true: a rare setting. It folds under a "More settings"
--               link at the end of its section; a search, or opening the
--               row from a search result, shows it
--   tone        description only: "muted" (default), "warning" or "body";
--               the renderer colors the text from the theme tokens, so a
--               text never carries its own color code.
--               `label` may be a function, read again on every refresh
--   terms       description only: { { "term", "meaning" }, ... } drawn one
--               per line with the term in body text (reference lists)
--   emptyText   select only: why there is nothing to pick while `values`
--               is empty ("No other profiles yet"); the row is grayed with
--               it
--   empty       tab row only: what the tab says while none of its rows
--               shows (default: the switch its hidden rows wait for)
-- A row that waits on a switch uses `dependsOn` or `disabled` (grayed, with
-- the reason); `hidden` is for rows that can't apply right now at all.
-- The tooltip of a select or range names its default ("Default: Top.")
-- unless the desc already does, so no desc has to type it.
--
-- More row types:
--   { type = "cog", label = "More", options = { ... }, dependsOn = "key" }
--       a row with only a gear button, for a group of rare settings
--   { type = "preview", height = 96, create = function(frame, page) end,
--     update = function(frame, settings) end }
--       a live preview block (put it first on a tab or section); update
--       runs after every change on the page. `height` may be a
--       function(canvas, width) that lays the block out for the page width
--       and returns its height (a card grid that wraps); `noCaption` hides
--       the small label in its corner
--   { type = "copyFrom", path = "units.target", label = "Copy settings from",
--     values = { ["units.player"] = "Player", ["units.focus"] = "Focus" },
--     keep = { "enabled" } }
--       copies a sibling's settings table into `path` (after a confirm),
--       keeping the keys in `keep` ("enabled" by default; frame positions
--       live in the movers, so they are never touched). The same menu has
--       "Apply these to all", and every row of the tab gets "Apply to all"
--       on right-click. `path` and `values` may be functions.
--
-- Every row with a value shows a small accent dot while it differs from
-- its default; right-click resets it. Section headers get a Reset link.
-- Pages know their defaults through page.defaults() (module pages: the
-- module's `defaults`).
--
-- A module page re-applies the module after every change while it is on.
-- `M.refreshWhenOff` keeps that going while it is off: a function(module)
-- runs instead (settings that also work with the module off), or `true`
-- calls M:OnProfileChanged() anyway.
--
-- M.options may be a function that returns the table: it runs the first
-- time the page opens (lazy pages). E:GetModuleOptions(module) gives the
-- table either way.
local _, E = ...
local L = E.L

local WIDTH, HEIGHT = 1000, 680
local SIDEBAR = 220        -- sidebar width
local MAIN_LEFT = 240      -- left edge of the page area
local NAV_WIDTH = 186      -- sidebar entry width (room for the scroll bar)
local ROW = E.tokens.height.settingsRow -- height of one settings row (DESIGN.md §3)
local RESULT_ROW = 24      -- height of one search result
local SECTION_GAP = 12
local DEFAULT_TAB = "General"
local CHEVRON = "Interface\\AddOns\\EldoUI\\Media\\Textures\\EldoChevron.tga"
-- Game art the window draws, with a bundled EldoUI glyph (or nothing) in
-- its place when this client lacks the file (E:SetClientFile).
local CLIENT_ART = {
	gear = { "Interface\\WorldMap\\GEAR_64GREY", "chevron-right" },
	speaker = { "Interface\\Common\\VoiceChat-Speaker", "play" },
	speakerOn = { "Interface\\Common\\VoiceChat-On" },
}
local function SetClientArt(texture, key)
	local art = CLIENT_ART[key]
	return E:SetClientFile(texture, art[1], art[2])
end

-- Button heights (DESIGN.md §3): the footer row is large, the rest normal.
local BUTTON = E.tokens.height.button
local BUTTON_LARGE = E.tokens.height.buttonLarge
local COG_WIDTH = 380      -- width of a cog popup
local SCALE_MIN, SCALE_MAX, SCALE_STEP = 0.7, 1.3, 0.05

-- Text colors by meaning (DESIGN.md): body white, secondary gray,
-- orange for a warning (why a row is disabled).
local TEXT = E.tokens.text.body
local SECONDARY = E.tokens.text.secondary
local DIM = E.tokens.text.dim
-- Read when the text is built, so the color-blind safe colors apply.
local function Warn() return E:TextHex("warn") end
local GREY = E:TokenHex(E.tokens.text.secondary)
local WARN_RGB = E.tokens.text.warn
local INSET_TINT = E.tokens.inset     -- inset areas, as E:SkinInset

-- Option types that hold a value (they get the changed dot and reset).
local VALUE_TYPES = { toggle = true, range = true, select = true, color = true, input = true, media = true }

local window
local pages = {}      -- ordered list of { id, title, options, target, refresh, order }
local currentPage
local pageFilter      -- lower-case text of the page search, or nil
local searching       -- the global search results are showing
local suppressSearch  -- ignore search box changes we make ourselves
local pendingReload = {}   -- id -> label of a change that needs a reload
local reloadSeen = {}      -- id -> value when the row was first shown
local promptedReloads = 0  -- pending count the closing prompt last asked about

-- Forward declarations: these call each other.
local ShowPage, ShowTab, ShowResults, UpdateNav, UpdateTabBar, HideShareMenu, BuildNav, SetNavHits
-- The sidebar tree and the window's size live in two tables (a Lua chunk
-- has room for 200 locals).
local Tree, Size = {}, {}
local OpenCog, RefreshCog, UpdateReloadButton

-- Account-wide settings of the window itself (scale, What's New).
local function WindowDB()
	if type(EldoUIDB) ~= "table" then return {} end
	EldoUIDB.configWindow = EldoUIDB.configWindow or {}
	return EldoUIDB.configWindow
end

-- The window's own size (resize grip), saved for the account. WIDTH and
-- HEIGHT are the default; the smallest size still shows a whole settings
-- row in two columns.
Size.MIN_WIDTH, Size.MIN_HEIGHT = 860, 560

function Size.Width()
	local width = tonumber(WindowDB().width)
	return width and math.max(Size.MIN_WIDTH, width) or WIDTH
end

function Size.Height()
	local height = tonumber(WindowDB().height)
	return height and math.max(Size.MIN_HEIGHT, height) or HEIGHT
end

-- The largest size that fits the screen at `scale` (window units).
function Size.Max(scale)
	scale = scale or 1
	return math.max(Size.MIN_WIDTH, math.floor((UIParent:GetWidth() - 40) / scale)),
		math.max(Size.MIN_HEIGHT, math.floor((UIParent:GetHeight() - 40) / scale))
end

---------------------------------------------------------------------------
-- Settings access by dotted path
---------------------------------------------------------------------------
local function GetPath(root, path)
	local value = root
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then return nil end
		value = value[tonumber(part) or part]
	end
	return value
end

local function SetPath(root, path, newValue)
	local parts = {}
	for part in path:gmatch("[^%.]+") do table.insert(parts, tonumber(part) or part) end
	local tableRef = root
	for index = 1, #parts - 1 do
		tableRef[parts[index]] = tableRef[parts[index]] or {}
		tableRef = tableRef[parts[index]]
	end
	tableRef[parts[#parts]] = newValue
end
E.GetPath, E.SetPath = GetPath, SetPath

-- `key` may be a function, for rows that edit whichever item is selected
-- (for example "triggers.<selected>.name").
local function KeyOf(option)
	if type(option.key) == "function" then return option.key() end
	return option.key
end

-- The table a row reads and writes: the page's, or the row's own `root`
-- (a Show switch on a module page keeps its value in the profile's list
-- of hidden boxes, Core/Hideable.lua).
function Tree.RootOf(page, option)
	if type(option.root) == "function" then return option.root() end
	return page.target()
end

-- Labels may carry color codes; search and tooltips use the plain text.
local function StripCodes(text)
	text = tostring(text or ""):gsub("|c%x%x%x%x%x%x%x%x", "")
	return (text:gsub("|r", ""))
end

-- Search synonyms: a search for one word of a group also
-- finds the others, so "colour", "alpha" or "scale" find the rows that
-- say "color", "opacity" or "size". The first word of a group is the one
-- the labels use. Only the typed search words are swapped; labels are
-- matched as they are. The British forms are search input, not text.
-- Search text and labels are compared folded (E:FoldText: case and accents
-- in every client language, punctuation as a space), so "see-through" is
-- the two words "see through".
do
	local SYNONYMS = {
		{ "color", "colour" }, -- spelling: ok
		{ "center", "centre" }, -- spelling: ok
		{ "gray", "grey" }, -- spelling: ok
		{ "behavior", "behaviour" }, -- spelling: ok
		{ "opacity", "alpha", "transparency", "transparent", "see-through" },
		{ "size", "scale" },
		{ "text size", "font size" },
		{ "keybind", "hotkey", "key bind" },
		{ "cooldown", "cd" },
	}
	-- Words that also find a group, one way only: "clear" finds the opacity
	-- rows, but "opacity" does not list every "Clear this list" row.
	local ALSO = { clear = "opacity" }
	local synonymOf, wordSynonyms
	local function Setup()
		synonymOf, wordSynonyms = {}, {}
		local groupOf = {}
		for _, group in ipairs(SYNONYMS) do
			local folded = {}
			for _, word in ipairs(group) do folded[#folded + 1] = E:FoldText(word) end
			for _, word in ipairs(folded) do synonymOf[word] = folded end
			groupOf[folded[1]] = folded
		end
		for word, first in pairs(ALSO) do synonymOf[word] = groupOf[first] end
		-- One-word synonyms, for the any-order word test.
		for word, group in pairs(synonymOf) do
			if not word:find(" ", 1, true) then
				local list = { word }
				for _, other in ipairs(group) do
					if other ~= word and not other:find(" ", 1, true) then list[#list + 1] = other end
				end
				wordSynonyms[word] = list
			end
		end
	end
	local termCache, termCount = {}, 0
	local planCache, planCount = {}, 0

	-- The filter (folded) and its variants with one synonym swapped in
	-- (whole words only, so "cd" never matches inside another word), cached.
	function Tree.SearchTerms(filter)
		local terms = termCache[filter]
		if terms then return terms end
		if not synonymOf then Setup() end
		local folded = E:FoldText(filter)
		terms = { folded }
		local seen = { [folded] = true }
		for word, group in pairs(synonymOf) do
			local at = folded:find(word, 1, true)
			local before = at and folded:sub(at - 1, at - 1) or ""
			local after = at and folded:sub(at + #word, at + #word) or ""
			if at and not before:find("%a") and not after:find("%a") then
				for _, other in ipairs(group) do
					local variant = folded:sub(1, at - 1) .. other .. folded:sub(at + #word)
					if not seen[variant] then
						seen[variant] = true
						terms[#terms + 1] = variant
					end
				end
			end
		end
		if termCount >= 500 then wipe(termCache); termCount = 0 end
		termCache[filter], termCount = terms, termCount + 1
		return terms
	end

	-- Every word of the search in any order: for each variant of the
	-- filter, its words, each with its one-word synonyms. A text matches
	-- when, for one variant, every word (or one of its synonyms) is in it.
	function Tree.SearchPlan(filter)
		local plan = planCache[filter]
		if plan then return plan end
		plan = {}
		for _, term in ipairs(Tree.SearchTerms(filter)) do
			local variant = {}
			for word in term:gmatch("%S+") do variant[#variant + 1] = wordSynonyms[word] or { word } end
			if #variant > 0 then plan[#plan + 1] = variant end
		end
		if planCount >= 500 then wipe(planCache); planCount = 0 end
		planCache[filter], planCount = plan, planCount + 1
		return plan
	end
end
E.ConfigSearchTerms = Tree.SearchTerms

-- Labels and descriptions folded for the search, cached (the same texts are
-- searched again on every key press).
do
	local foldCache, foldCount = {}, 0
	function Tree.Folded(text)
		text = tostring(text or "")
		local folded = foldCache[text]
		if not folded then
			folded = E:FoldText(StripCodes(text))
			if foldCount >= 20000 then wipe(foldCache); foldCount = 0 end
			foldCache[text], foldCount = folded, foldCount + 1
		end
		return folded
	end
end

function Tree.HasAllWords(text, variant)
	for _, words in ipairs(variant) do
		local found = false
		for _, word in ipairs(words) do
			if text:find(word, 1, true) then found = true break end
		end
		if not found then return false end
	end
	return true
end

-- True when the text holds every word of the filter, in any order.
local function Matches(label, filter)
	local text = Tree.Folded(label)
	for _, variant in ipairs(Tree.SearchPlan(filter)) do
		if Tree.HasAllWords(text, variant) then return true end
	end
	return false
end

E.ConfigSearchMatches = Matches -- read-only, for plugins

-- True when the text holds the filter as one phrase (ranks first).
function Tree.MatchesPhrase(label, filter)
	local text = Tree.Folded(label)
	for _, term in ipairs(Tree.SearchTerms(filter)) do
		if text:find(term, 1, true) then return true end
	end
	return false
end

local function IsHidden(option)
	local hidden = option.hidden
	if type(hidden) == "function" then return hidden() end
	return hidden
end

-- `requiresAPI`: "C_Foo.Bar" resolves through the global table.
local function HasAPI(path)
	local value = _G
	for part in tostring(path):gmatch("[^%.]+") do
		if type(value) ~= "table" then return false end
		value = value[part]
	end
	return value ~= nil
end

-- false when the client (or class) can't use the option: the row is never
-- built, searched or shown, so no option without an effect appears.
local function IsAvailable(option)
	local api = option.requiresAPI
	if type(api) == "string" then api = { api } end
	if type(api) == "table" then
		for _, path in ipairs(api) do
			if not HasAPI(path) then return false end
		end
	end
	local requires = option.requires
	if type(requires) == "function" then
		local ok, result = pcall(requires)
		return ok and result and true or false
	end
	return requires ~= false
end

-- The key a row depends on (`dependsOn`, a key or a function).
local function ParentKey(option)
	local key = option.dependsOn
	if type(key) == "function" then key = key() end
	return type(key) == "string" and key or nil
end

-- nil while the row can be used; otherwise true or the reason it can't.
local function DisabledReason(option, page)
	local disabled = option.disabled
	if type(disabled) == "function" then disabled = disabled() end
	if disabled then return disabled end
	if option.type == "select" and Tree.NoChoices(option) then
		return option.emptyText and L[option.emptyText] or L["Nothing to choose yet."]
	end
	local parentKey = ParentKey(option)
	if parentKey and page and not GetPath(page.target(), parentKey) then
		local parent = page.optionsByKey and page.optionsByKey[parentKey]
		return L["Turn on \"%s\" first."]:format(parent and StripCodes(parent.label) or parentKey)
	end
end

-- The default of a row, from page.defaults() (nil when unknown).
local function DefaultOf(page, option)
	if not (page.defaults and VALUE_TYPES[option.type]) then return nil end
	local key = KeyOf(option)
	local defaults = type(key) == "string" and page.defaults()
	if type(defaults) ~= "table" then return nil end
	return GetPath(defaults, key)
end

local function IsChanged(page, option)
	local default = DefaultOf(page, option)
	if default == nil then return false end
	return not E.DeepEqual(GetPath(Tree.RootOf(page, option), KeyOf(option)), default)
end

---------------------------------------------------------------------------
-- Recent changes: every value a row sets this session, with the
-- value before it, newest first, at most 200. The footer's "Recent
-- changes" list undoes one or all of them. A slider drag or a color pick
-- counts once: the next set of the same row updates the newest entry. The
-- list is not saved; it is empty after a reload.
---------------------------------------------------------------------------
-- Recent.MAX entries at most; Recent.UpdateButton (set with the window)
-- keeps the footer button's count.
local Recent = { ROW = 44, MAX = 200 }
E.ConfigRecent = Recent -- exposed for inspection
-- Recent.log: { page, option, key, root, old, new }, newest first.
Recent.log = {}

function Recent.Copy(value)
	return type(value) == "table" and CopyTable(value) or value
end

-- Set a row's value through the renderer, and log it.
local function SetOption(page, option, value)
	local key = KeyOf(option)
	if type(key) ~= "string" then return end
	local root = Tree.RootOf(page, option)
	local old = GetPath(root, key)
	if E.DeepEqual(old, value) then return end
	SetPath(root, key, value)
	-- An action row keeps no value: Undo could not take it back.
	if option.noUndo then return end
	local newest = Recent.log[1]
	if newest and newest.page == page and newest.key == key and newest.root == root then
		newest.new = Recent.Copy(value)
		-- Dragged back to where it started: nothing changed after all.
		if E.DeepEqual(newest.old, newest.new) then table.remove(Recent.log, 1) end
	else
		table.insert(Recent.log, 1, { page = page, option = option, key = key, root = root,
			old = Recent.Copy(old), new = Recent.Copy(value) })
		Recent.log[Recent.MAX + 1] = nil
	end
	if Recent.UpdateButton then Recent.UpdateButton() end
end

-- A copy into a whole settings table (Copy settings from, Apply these to
-- all): one entry whose Undo puts the table's values back in place,
-- leaving the keys the copy keeps (the on/off switch) as they are now.
function Recent.LogCopy(page, path, label, old, keep)
	local root = page.target()
	local now = GetPath(root, path)
	if type(old) ~= "table" or type(now) ~= "table" or E.DeepEqual(old, now) then return end
	table.insert(Recent.log, 1, { page = page, option = { type = "copy", label = label }, key = path, root = root,
		old = old, new = CopyTable(now), keep = keep })
	Recent.log[Recent.MAX + 1] = nil
	if Recent.UpdateButton then Recent.UpdateButton() end
end

-- For plugins: the session's changes, newest first.
function E:ConfigRecentChanges()
	return Recent.log
end

local function ResetOption(page, option)
	local default = DefaultOf(page, option)
	if default == nil then return end
	SetOption(page, option, Recent.Copy(default))
end

-- Decimals a range's step needs: 1 -> 0, 0.5 -> 1, 0.05 -> 2.
function Recent.StepDecimals(step)
	step = tonumber(step) or 1
	if step >= 1 and step == math.floor(step) then return 0 end
	local text = ("%.4f"):format(step):gsub("0+$", "")
	local dot = text:find(".", 1, true)
	return dot and math.min(#text - dot, 4) or 0
end

-- A range's value as it is stored, rounded to its step.
function E:ConfigRangeValue(option, value)
	value = tonumber(value) or option.min or 0
	local decimals = Recent.StepDecimals(option.step)
	if decimals == 0 then return math.floor(value + 0.5) end
	return tonumber(("%." .. decimals .. "f"):format(value))
end

-- A range's value as the player reads it: `percent = true`
-- shows a 0-1 value as 0-100 % ("85 %"), `unit` ("s", "px", "yd", "%")
-- follows the number ("0.5 s"), and the decimals follow the step.
function E:ConfigRangeText(option, value)
	value = self:ConfigRangeValue(option, value)
	if value == 0 and type(option.zeroText) == "string" then return L[option.zeroText] end
	if option.percent then
		return ("%." .. Recent.StepDecimals((option.step or 0.01) * 100) .. "f %%"):format(value * 100)
	end
	local decimals = Recent.StepDecimals(option.step)
	local text = decimals == 0 and tostring(value) or ("%." .. decimals .. "f"):format(value)
	if type(option.unit) == "string" and option.unit ~= "" then text = text .. " " .. L[option.unit] end
	return text
end

---------------------------------------------------------------------------
-- Search scoring: the label counts most, then `keywords`, then the names
-- of a select's choices and the description. Returns the score (0 = no
-- match) and, for a matching choice, its name.
---------------------------------------------------------------------------
-- The choice names in the player's language. A fixed values table is
-- translated once; a values function is translated on every call. Tables
-- marked with E:RawValues (fonts, textures, profiles) are shown as they are.
local translatedValues = setmetatable({}, { __mode = "k" })
local function SelectValues(option)
	local values = option.values
	if type(values) == "function" then values = values() end
	if type(values) ~= "table" then return {} end
	if E:IsRawValues(values) then return values end
	local copy = translatedValues[values]
	if not copy then
		copy = {}
		for value, name in pairs(values) do copy[value] = type(name) == "string" and L[name] or name end
		if type(option.values) == "table" then translatedValues[values] = copy end
	end
	return copy
end

-- A select whose values are empty right now (lists of lists, one profile).
function Tree.NoChoices(option)
	local ok, values = pcall(SelectValues, option)
	return ok and type(values) == "table" and next(values) == nil
end

-- "Default: Top." for the tooltip of a select or range, or nil when the
-- default is unknown or the desc already names it (or says "default").
function E:ConfigDefaultText(option, default, desc)
	if default == nil then return nil end
	local name
	if option.type == "select" then
		local ok, values = pcall(SelectValues, option)
		name = ok and values[default]
		if type(name) ~= "string" then return nil end
		name = StripCodes(name)
	elseif option.type == "range" and type(default) == "number" then
		name = self:ConfigRangeText(option, default)
	else
		return nil
	end
	desc = type(desc) == "string" and desc:lower() or ""
	if desc:find("default", 1, true) or (option.type == "select" and desc:find(name:lower(), 1, true)) then return nil end
	return L["Default: %s."]:format(name)
end

-- How well a row matches: the label as one phrase first, then every word
-- in the label, the keywords, a choice, the description, and last every
-- word spread over all of them and `context` (the page title, so "sort
-- bags" finds the sort rows of the Bags page).
local function Score(option, filter, context)
	local label = option.label
	if label and Tree.MatchesPhrase(label, filter) then return 3 end
	if label and Matches(label, filter) then return 2.5 end
	local keywords = option.keywords
	if type(keywords) == "table" then keywords = table.concat(keywords, " ") end
	if type(keywords) == "string" and Matches(keywords, filter) then return 2 end
	local choices
	if option.type == "select" and not option.sound then
		local ok, values = pcall(SelectValues, option)
		for _, name in pairs(ok and values or {}) do
			if type(name) == "string" then
				if Matches(name, filter) then return 1, StripCodes(name) end
				choices = (choices and (choices .. " ") or "") .. Tree.Folded(name)
			end
		end
	end
	local desc = option.desc
	if type(desc) == "string" and Matches(desc, filter) then return 1 end
	local all = Tree.Folded(label) .. " " .. (type(keywords) == "string" and Tree.Folded(keywords) or "") .. " "
		.. (type(desc) == "string" and Tree.Folded(desc) or "") .. " " .. (choices or "") .. " " .. Tree.Folded(context)
	-- The page title alone never matches every row of its page.
	local page = Tree.Folded(context)
	for _, variant in ipairs(Tree.SearchPlan(filter)) do
		if Tree.HasAllWords(all, variant) and not Tree.HasAllWords(page, variant) then return 0.5 end
	end
	return 0
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
-- Subtitles for the built-in pages (module pages use the module's desc):
-- English keys, translated where the header and the sidebar tooltip show
-- them, so they follow the language picked after the files load.
local PAGE_DESC = {
	general = E.Key("Accent, panels, sounds and scale for the whole UI."),
	overview = E.Key("Your whole look in one place: a complete look, its layout, the UI amount and Blizzard's windows, applied together."),
	appearance = E.Key("The skin of your whole UI and of each part. A skin never moves frames or turns modules on or off."),
	uiamount = E.Key("How much EldoUI shows: Essential, Moderate or Full. It only switches modules on or off."),
	modules = E.Key("Every part of EldoUI is a module. Switch off the ones you don't want."),
	layouts = E.Key("Ready-made layouts that move every EldoUI frame into place."),
	styles = E.Key("Ready-made looks for each part of the UI. Mix and match."),
	positions = E.Key("Exact positions for every movable frame."),
	keybinds = E.Key("Key sets for your action bars, and keybind mode."),
	profiles = E.Key("Switch, create, copy or reset the profile this character uses."),
	share = E.Key("Import any string (EldoUI, EllesmereUI, ElvUI, Edit Mode) with a preview, or share your setup as one."),
	blizzard = E.Key("Choose which parts of Blizzard's UI EldoUI may change. Off = Blizzard default."),
	profilerules = E.Key("Switch profiles automatically by talent group or content."),
	safearea = E.Key("Limit EldoUI to a centered area on ultrawide screens."),
	whatsnew = E.Key("What changed in each EldoUI version."),
	thanks = E.Key("The people who made EldoUI possible."),
	glows = E.Key("Style and color of every glow: procs, highlights, reminders."),
	tags = E.Key("Every text tag with what it shows, and a place to try tag strings."),
	aurafilters = E.Key("Spell lists that decide which auras EldoUI shows, for all your characters."),
}
-- What's New and Thanks are links in the sidebar foot, around Errors.
local BOTTOM_PAGES = { whatsnew = 1, thanks = 2 }
-- The general pages fold into five hubs (DESIGN.md §0b and §3b): each hub
-- is one sidebar row (Global settings and Profiles are quick actions) and
-- its pages, in this fixed order, are the tabs at the top of the hub page.
-- A page not listed here (a plugin's) joins Modules by its own order number.
Tree.HUBS = {
	{ key = "global", title = "Global settings", pages = { "general", "fonts", "textures", "colors", "glows",
		"accessibility", "windows", "safearea", "visibility" } },
	{ key = "layout", title = "Layout and style", pages = { "overview", "layouts", "positions", "appearance", "uiamount", "styles", "role" } },
	{ key = "modules", title = "Modules", pages = { "modules", "plugins", "addons", "blizzard", "hidden" } },
	{ key = "profiles", title = "Profiles", pages = { "profiles", "profilerules", "share" } },
	{ key = "lists", title = "Lists and tags", pages = { "tags", "aurafilters", "keybinds" } },
}
Tree.OTHER_HUB = 3
Tree.pageHub, Tree.pageRank = {}, {}
for hubIndex, hub in ipairs(Tree.HUBS) do
	for rank, id in ipairs(hub.pages) do
		Tree.pageHub[id], Tree.pageRank[id] = hubIndex, rank
	end
end
-- Shown translated: L["Global settings"], L["Layout and style"], L["Modules"],
-- L["Profiles"], L["Lists and tags"]

-- target() returns the settings table; refresh() re-applies after a change.
-- Returns the page, so callers can add fields such as `desc`.
function E:RegisterConfigPage(id, title, options, target, refresh, order)
	for _, page in ipairs(pages) do
		if page.id == id then return page end
	end
	local page = { id = id, title = L[title], options = options, target = target, refresh = refresh,
		order = order or 50, desc = PAGE_DESC[id] }
	table.insert(pages, page)
	table.sort(pages, function(a, b)
		if a.order ~= b.order then return a.order < b.order end
		return a.title < b.title
	end)
	return page
end

local function HasTabs(options)
	for _, option in ipairs(options or {}) do
		if option.type == "tab" then return true end
	end
end

-- A module's options table. `M.options` may be a function that builds it
-- (lazy pages): it runs once, the first time anything asks.
function E:GetModuleOptions(module)
	if type(module) == "string" then module = self.modules[module] end
	if not module then return nil end
	if type(module.options) == "function" then
		local ok, result = pcall(module.options, module)
		if not ok then
			-- Kept on the module, so its page says so.
			module.optionsError = true
			geterrorhandler()(("EldoUI module %s: options failed: %s"):format(module.name, tostring(result)))
		end
		module.options = ok and type(result) == "table" and result or {}
	end
	return module.options
end

-- The page of a module: its own options plus its style presets.
local function BuildModuleOptions(module)
	local name = module.name
	local own = E:GetModuleOptions(module)
	local options = {}
	local styles = E:StyleOptions(name)
	if HasTabs(own) then
		-- Tabbed module: its own tabs first, the style presets last.
		-- Only descriptions before the first tab: they open the first
		-- tab instead of making a "General" tab with no setting on it.
		local intro, first = 0, nil
		for index, option in ipairs(own) do
			if option.type == "tab" then first = index break end
			if option.type == "description" then intro = intro + 1 end
		end
		if first > 1 and intro == first - 1 and IsAvailable(own[first]) then
			table.insert(options, own[first])
			for index = 1, first - 1 do table.insert(options, own[index]) end
			for index = first + 1, #own do table.insert(options, own[index]) end
		else
			if own[1].type ~= "tab" then table.insert(options, { type = "tab", label = DEFAULT_TAB }) end
			for _, option in ipairs(own) do table.insert(options, option) end
		end
		if styles then
			table.insert(options, { type = "tab", label = "Presets" })
			for _, option in ipairs(styles) do table.insert(options, option) end
		end
	else
		-- Untabbed module: the same order as tabbed pages, its own settings
		-- first and the style presets (with their own header) last.
		for _, option in ipairs(own or {}) do table.insert(options, option) end
		for _, option in ipairs(styles or {}) do table.insert(options, option) end
	end
	-- Show switches for the module's boxes (Core/Hideable.lua), at the end
	-- of its first tab: the same setting as the right-click Hide.
	local shows = E.GetHideableModuleOptions and E:GetHideableModuleOptions(module) or {}
	if #shows > 0 then
		local at = HasTabs(own) and #options + 1 or #(own or {}) + 1
		for index = 2, HasTabs(own) and #options or 0 do
			if options[index].type == "tab" then at = index break end
		end
		for offset, option in ipairs(shows) do table.insert(options, at + offset - 1, option) end
	end
	-- A module whose options or start failed says so at the top of its
	-- first tab, with a way to the error log.
	if E:ModuleFailed(module) then
		local at = options[1] and options[1].type == "tab" and 2 or 1
		table.insert(options, at, { type = "execute", label = "Open error log", noUndo = true,
			desc = "Shows the errors EldoUI caught, with what happened.",
			func = function() if E.ToggleErrorWindow then E:ToggleErrorWindow(true) end end })
		table.insert(options, at, { type = "description", tone = "warning", label = function()
			return E:StatusMark("warn") .. " " .. L["Part of this module failed to load, so some settings may be missing or not work. The error log shows what happened."]
		end })
	end
	return options
end

-- One page per module with options or styles. The option list is built
-- when the page first opens (or the search first looks at it).
local function ModulePages()
	for name, module in E:IterateModules() do
		if module.options or E.styles[name] then
			local page = E:RegisterConfigPage("module:" .. name, module.title, nil,
				function() return module.db end,
				function()
					if module.active and module.OnProfileChanged then
						-- One queued refresh per module while in combat.
						E:RefreshModule(module, true)
					elseif not module.active and module.refreshWhenOff then
						-- Settings that also work while the module is off.
						local refresh = module.refreshWhenOff
						E:RunOutOfCombat(function()
							if type(refresh) == "function" then
								refresh(module)
							elseif module.OnProfileChanged then
								module:OnProfileChanged()
							end
						end, "Refresh:" .. name)
					end
				end)
			if not page.module then
				page.module = module
				page.build = function() return BuildModuleOptions(module) end
				page.defaults = function() return module.defaults end
			end
			if page.desc == nil and module.desc ~= "" then page.desc = L[module.desc] end
			-- Earlier names of the page: the search still finds it by them.
			if #module.aliases > 0 then page.keywords = module.aliases end
		end
	end
end

-- Rows that can carry a gear (`cog = true` rows below fold into them).
local COG_HOSTS = { toggle = true, range = true, select = true, color = true, input = true, media = true, cog = true }

-- Rare sub-settings of a row: its `cog` table, or a cog row's `options`.
local function CogOptions(option)
	if option.type == "cog" then return option.options end
	return type(option.cog) == "table" and option.cog or nil
end

-- Split a page's options into tabs, and each tab into sections that start
-- at a header. Built once per page and cached. Rows, sections and tabs
-- whose `requires` probe fails are left out here, once.
-- Labels and descriptions are written in English and shown in the player's
-- language: each option is translated once, in place, the first time
-- its page is built, cog rows included.
-- A label or description with a %s keeps one key for every row that
-- shares it: labelFill / descFill hold what goes into it (an English text,
-- a list of them, or a function that returns either), translated too.
-- labelKey / descKey keep the key.
-- A row with gameName shows a name the game gives (a spell or a stat) as
-- the game names it, never translated: gameName = true keeps the label,
-- a function returns the game's name, and the label stays when it has none.
local function Filled(text, fill, translate)
	if fill == nil then return text end
	if type(fill) == "function" then fill = fill() end
	if type(fill) ~= "table" then fill = { fill } end
	local args = {}
	for index = 1, #fill do args[index] = translate and E:Translate(fill[index]) or fill[index] end
	local ok, out = pcall(string.format, text, unpack(args))
	return ok and out or text
end

local function Localize(options)
	for _, option in ipairs(options or {}) do
		if type(option) == "table" and not option.localized then
			option.localized = true
			-- The English texts stay readable as englishLabel / englishDesc for
			-- code that finds a row by its label after the page was built.
			if type(option.label) == "string" then
				if option.labelFill ~= nil then option.labelKey = option.label end
				option.englishLabel = option.englishLabel or Filled(option.label, option.labelFill)
				if option.gameName then
					local ok, name = true, nil
					if type(option.gameName) == "function" then ok, name = pcall(option.gameName) end
					if ok and type(name) == "string" and name ~= "" then option.label = name end
				else
					option.label = Filled(L[option.label], option.labelFill, true)
				end
			end
			if type(option.desc) == "string" then
				if option.descFill ~= nil then option.descKey = option.desc end
				option.englishDesc = option.englishDesc or Filled(option.desc, option.descFill)
				option.desc = Filled(L[option.desc], option.descFill, true)
			end
			if type(option.hint) == "string" then option.hint = L[option.hint] end
			if type(option.cog) == "table" then Localize(option.cog) end
			if type(option.options) == "table" then Localize(option.options) end
		end
	end
end

local function Structure(page)
	if page.tabs then return page.tabs end
	if not page.options then page.options = page.build and page.build() or {} end
	Localize(page.options)
	local tabs, tab, section = {}, nil, nil
	local skipTab, skipSection = false, false
	page.optionsByKey = {}
	page.cogParent = {}   -- cog child -> the row that owns the cog
	page.cogItems = {}    -- row -> its available cog children, in order
	local function NewTab(label, oneColumn)
		tab = { label = label, sections = {}, page = page, widgets = {}, sectionByHeader = {}, oneColumn = oneColumn }
		table.insert(tabs, tab)
		section = nil
	end
	page.tabOf = {}       -- option -> index of its tab
	local function Index(option)
		page.tabOf[option] = #tabs
		if type(option.key) == "string" and not page.optionsByKey[option.key] then
			page.optionsByKey[option.key] = option
		end
	end
	for _, option in ipairs(page.options) do
		if option.type == "tab" then
			skipTab = not IsAvailable(option)
			if not skipTab then
				NewTab(option.label or L[DEFAULT_TAB], option.oneColumn)
				tab.empty = option.empty
				tab.englishLabel = option.englishLabel
			end
		elseif not skipTab then
			if not tab then NewTab(L[DEFAULT_TAB]) end
			if option.type == "header" then
				skipSection = not IsAvailable(option)
				if not skipSection then
					section = { header = option, items = {} }
					table.insert(tab.sections, section)
					tab.sectionByHeader[option] = section
				end
			elseif not skipSection and IsAvailable(option) then
				if not section then
					section = { items = {} }
					table.insert(tab.sections, section)
				end
				section.cogItems = section.cogItems or {}
				local function AddChild(parent, child)
					local list = page.cogItems[parent]
					if not list then
						list = {}
						page.cogItems[parent] = list
						section.cogItems[parent] = list
					end
					table.insert(list, child)
					page.cogParent[child] = parent
					Index(child)
				end
				if option.cog == true and section.lastRow then
					-- `cog = true`: a rare setting folded into the gear of the
					-- row above it (shared engines).
					AddChild(section.lastRow, option)
				else
					table.insert(section.items, option)
					Index(option)
					if COG_HOSTS[option.type] then section.lastRow = option end
					-- Rows that hide themselves need a re-layout after every change.
					if type(option.hidden) == "function" then tab.dynamic = true end
					if option.type == "copyFrom" and not tab.copyFrom then tab.copyFrom = option end
					for _, child in ipairs(CogOptions(option) or {}) do
						if IsAvailable(child) then AddChild(option, child) end
					end
				end
			end
		end
	end
	if not tab then NewTab(L[DEFAULT_TAB]) end
	page.tabs = tabs
	page.hasTabs = #tabs > 1 or HasTabs(page.options)
	return tabs
end

-- The options of a section that pass `hidden` and the filter. A header
-- that matches the filter shows its whole section; a row whose cog holds
-- a match shows too.
local function VisibleItems(section, filter, context)
	local showAll = not filter or (section.header and Matches(section.header.label, filter))
	local list = {}
	for _, option in ipairs(section.items) do
		if not IsHidden(option) then
			local show = showAll or (option.type ~= "description" and option.type ~= "preview" and Score(option, filter, context) > 0)
			if not show and section.cogItems and section.cogItems[option] then
				for _, child in ipairs(section.cogItems[option]) do
					if Score(child, filter, context) > 0 then show = true break end
				end
			end
			if show then table.insert(list, option) end
		end
	end
	return list
end

local function CountMatches(tab, filter)
	local count = 0
	for _, section in ipairs(tab.sections) do count = count + #VisibleItems(section, filter, tab.page.title) end
	return count
end

-- The share string key for a page.
local function ExportKey(page)
	if page.module then return "module:" .. page.module.name end
	if page.id == "general" or page.id == "positions" then return page.id end
	return "all"
end

---------------------------------------------------------------------------
-- Notices
---------------------------------------------------------------------------
-- Confirmation of a click in the options window, or a problem with it,
-- shows in the window over its footer (E.UIKit.Toast, DESIGN.md §5), not in
-- chat. With the window closed (a slash command) it goes to chat.
-- A notice of more lines than E.CONFIG_NOTICE_LINES shows its first ones in
-- the window and the whole text in chat, where a long list (a report) can
-- be read.
E.CONFIG_NOTICE_LINES = 6

function E:ConfigNotice(text, warn)
	if not (window and window:IsShown() and self.UIKit and self.UIKit.Toast) then
		self:Print(text)
		return
	end
	text = tostring(text or "")
	local lines = { strsplit("\n", text) }
	local most = self.CONFIG_NOTICE_LINES
	if #lines > most then
		self:Print(text)
		local shown = {}
		for index = 1, most - 1 do shown[index] = lines[index] end
		shown[#shown + 1] = L["The full list is in chat."]
		text = table.concat(shown, "\n")
	end
	-- More than one line: the toast grows with its text (Kit.Toast).
	self.UIKit.Toast(window, text, { anchor = window, point = "BOTTOM", y = 52, warn = warn,
		time = #lines > 1 and math.max(self.UIKit.TOAST_ACTION_TIME, self.UIKit.ToastTime(text)) or nil })
end

-- Chat lines a config row writes while the window is open become one
-- notice in the window (DESIGN.md §5): a confirmation of the click, or
-- why it did nothing. A module's "[Title]" prefix is left out there.
-- Lines written later (after a delay) still go to chat.
function E:RunConfigRow(fn, ...)
	if type(fn) ~= "function" then return end
	if not (window and window:IsShown()) then return fn(...) end
	local lines = {}
	local print = E.Print
	E.Print = function(_, ...)
		local parts = {}
		for index = 1, select("#", ...) do
			local part = tostring((select(index, ...)))
			-- The module prefix Module:Print adds: "[Title]" in a color code.
			if not (index == 1 and part:match("^|c%x%x%x%x%x%x%x%x%[.-%]|r$")) then parts[#parts + 1] = part end
		end
		local line = table.concat(parts, " ")
		if line ~= "" then lines[#lines + 1] = line end
	end
	local ok, err = pcall(fn, ...)
	E.Print = print
	if #lines > 0 then E:ConfigNotice(table.concat(lines, "\n")) end
	if not ok then geterrorhandler()(err) end
end

---------------------------------------------------------------------------
-- Module reset
---------------------------------------------------------------------------
-- Put a module's settings back to its defaults. The on/off state and the
-- frame positions are kept, and so are the keys a module lists in
-- `keepOnReset` (player data such as click-cast bindings).
function E:ResetModuleSettings(name)
	local module = self.modules[name]
	if not module or not module.db then return end
	local enabled = module.db.enabled
	local db = self.db.modules[name] or {}
	local kept = {}
	for _, key in ipairs(module.keepOnReset or {}) do kept[key] = db[key] end
	wipe(db)
	db.enabled = enabled
	for key, value in pairs(kept) do db[key] = value end
	self.db.modules[name] = db
	module.db = self:GetModuleDB(module)
	self:RefreshModule(module, true)
	self:RefreshConfig()
	self:ConfigNotice(L["%s reset to its defaults."]:format(L[module.title]))
end

-- Questions go through the shared confirm dialog (E:ShowConfirm,
-- Core/Skin.lua): one look and one Escape rule for every EldoUI question.
-- Resetting a whole module: what stays is named in the text.
function E:ConfirmModuleReset(name)
	local module = self.modules[name]
	if not module then return end
	local note = module.keepOnResetNote and (" " .. L[module.keepOnResetNote]) or ""
	return self:ShowConfirm({
		title = L["Reset %s"]:format(L[module.title]),
		text = L["Every %s setting goes back to its default. The on/off state and frame positions are kept.%s"]:format(
			L[module.title], note),
		accept = RESET or L["Reset"],
		danger = true,
		onAccept = function() E:ResetModuleSettings(name) end,
	})
end

-- Changes to many rows at once: reset, copy, apply to all.
local Bulk = {}

function Bulk.ConfirmReset(module)
	E:ConfirmModuleReset(module.name)
end

-- One confirm for the smaller resets, copies and deletes, for modules too:
-- E:ConfigConfirm(text, work [, opts]); opts: title, accept, danger.
function E:ConfigConfirm(text, work, opts)
	opts = opts or {}
	return self:ShowConfirm({
		title = opts.title,
		text = text,
		accept = opts.accept or (YES or L["Yes"]),
		danger = opts.danger,
		onAccept = function() E:RunConfigRow(work) end,
	})
end

local function Confirm(text, work)
	E:ConfigConfirm(text, work)
end

---------------------------------------------------------------------------
-- Look: everything is drawn through the EldoUI templates and theme fonts
-- (DESIGN.md), and registered here so a theme change re-applies it.
---------------------------------------------------------------------------
local texts = setmetatable({}, { __mode = "k" })   -- font string -> { size, header }
local boxes = setmetatable({}, { __mode = "k" })   -- frame -> { transparent, tint }

-- Window text has no outline: a soft 1 px shadow keeps it crisp at 11-14 px.
-- The outline setting stays for HUD text over bars.
local function ApplyTextFont(fontString, info)
	if info.header then
		E:SetHeaderFont(fontString, info.size, "")
	else
		E:SetFont(fontString, info.size, "")
	end
	fontString:SetShadowOffset(1, -1)
	fontString:SetShadowColor(0, 0, 0, 0.6)
end

-- Theme text. header = the header font (window titles).
local function Text(parent, size, justify, color, header)
	local fontString = E:CreateText(parent, size, justify or "LEFT")
	local info = { size = size, header = header }
	texts[fontString] = info
	ApplyTextFont(fontString, info)
	if color then fontString:SetTextColor(unpack(color)) end
	return fontString
end

-- Small box (E:SetTemplate). tint: optional { r, g, b, a } background.
local function Box(frame, transparent, tint)
	boxes[frame] = { transparent = transparent, tint = tint }
	E:SetTemplate(frame, transparent)
	if tint then frame:SetBackdropColor(unpack(tint)) end
	return frame
end

-- Parts built after the window took its scale get their 1-pixel edges
-- snapped to the screen pixel too (Core/Skin.lua, DESIGN.md 3a).
local function Snap(frame)
	if frame and E.SnapBorders then E:SnapBorders(frame, true) end
	return frame
end

-- Optional helpers from Core/Skin.lua; skipped when it isn't loaded.
local function Skin(method, frame, opts)
	if frame and type(E[method]) == "function" then E[method](E, frame, opts) end
end

local function Accent(alpha)
	local c = E.media.accentColor
	return c[1], c[2], c[3], alpha or 1
end

---------------------------------------------------------------------------
-- Small parts: tooltips, flash, buttons
---------------------------------------------------------------------------
-- Tooltip from `desc`; also shown when the label is cut off.
local function AddTooltip(widget, title, desc, label)
	widget:HookScript("OnEnter", function(self)
		local text = desc
		if type(text) == "function" then text = text() end
		if type(text) ~= "string" or text == "" then text = nil end
		if not text and not (label and label:IsTruncated()) then return end
		local heading = title
		if type(heading) == "function" then heading = heading() end
		-- Right of the row, or left of it when the screen edge is near.
		E.UIKit.AnchorTooltip(self, GameTooltip)
		E.UIKit.TipTitle(GameTooltip, StripCodes(heading))
		E.UIKit.TipText(GameTooltip, text)
		GameTooltip:Show()
	end)
	if label and type(title) == "string" then
		label.fullTextTooltip = { title = title, owner = widget, handler = widget:GetScript("OnEnter") }
	end
	widget:HookScript("OnLeave", GameTooltip_Hide)
end

-- A short accent flash, used when a search result opens a row.
local function AddFlash(frame)
	local flash = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
	flash:SetAllPoints()
	flash:SetColorTexture(1, 1, 1, 1)
	flash:SetAlpha(0)
	local anim = flash:CreateAnimationGroup()
	local fade = anim:CreateAnimation("Alpha")
	fade:SetFromAlpha(0.4)
	fade:SetToAlpha(0)
	fade:SetDuration(1.6)
	anim:SetToFinalAlpha(true)
	frame.Flash = function()
		frame.flashedAt = GetTime() -- when it last flashed
		flash:SetVertexColor(Accent())
		anim:Stop()
		anim:Play()
	end
end

-- Text buttons are the shared kit's (E.UIKit.Button): one look for every
-- EldoUI button, hover and pressed states included. `primary` buttons
-- (Done, a pending Reload) take the kit's primary kind.
local buttons = setmetatable({}, { __mode = "k" })

local function PaintButton(button)
	E.UIKit.SetButtonKind(button, button.primary and "primary" or nil)
end

-- A nil width sizes the button to its label (Kit.FitButton).
local function Button(parent, text, width, height, onClick, primary)
	local button = E.UIKit.Button(parent, { text = text, width = width, height = height or BUTTON, size = E.tokens.size.body })
	button.primary = primary
	button:SetScript("OnClick", function(self, mouse)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		onClick(self, mouse)
	end)
	buttons[button] = true
	PaintButton(button)
	return button
end

local function RepaintButtons()
	for button in pairs(buttons) do PaintButton(button) end
end

-- Sound preview: a small speaker next to each sound in a list. One
-- preview plays at a time, so clicking through a list never stacks.
-- Plays even with "Mute EldoUI sounds" on (it is the player's own click).
local previewHandle

-- The sound preview buttons.
local Sounds = {}

function Sounds.PreviewSound(id, channel)
	if previewHandle then E:StopMedia(previewHandle); previewHandle = nil end
	if not id or id == "none" then return end
	local _, handle = E:PlayMedia(id, channel, { preview = true })
	previewHandle = handle
end

-- Draws the speaker on `button` (any frame with mouse); getId and
-- getChannel are read on click.
function Sounds.MakeSpeaker(button, getId, getChannel, rowHeight)
	button:SetSize(18, 18)
	-- Small icon: a few pixels more hit area than it draws, never past
	-- its row (DESIGN.md 3a).
	E:PadHitRect(button, 3, rowHeight or ROW)
	local icon = button.speakerIcon or button:CreateTexture(nil, "ARTWORK")
	SetClientArt(icon, "speaker")
	icon:SetAllPoints()
	icon:SetVertexColor(unpack(SECONDARY))
	local waves = button.speakerWaves or button:CreateTexture(nil, "OVERLAY")
	SetClientArt(waves, "speakerOn")
	waves:SetAllPoints()
	waves:Hide()
	button.speakerIcon, button.speakerWaves = icon, waves
	button:SetScript("OnEnter", function(self)
		self.speakerIcon:SetVertexColor(1, 1, 1)
		self.speakerWaves:Show()
		E.UIKit.AnchorTooltip(self, GameTooltip)
		E.UIKit.TipTitle(GameTooltip, L["Play"])
		E.UIKit.TipText(GameTooltip, L["Plays this sound once so you can hear it."])
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self.speakerIcon:SetVertexColor(unpack(SECONDARY))
		self.speakerWaves:Hide()
		GameTooltip_Hide()
	end)
	button:SetScript("OnClick", function() Sounds.PreviewSound(getId(), getChannel and getChannel()) end)
	return button
end

local function Speaker(parent, getId, getChannel)
	return Sounds.MakeSpeaker(CreateFrame("Button", nil, parent), getId, getChannel)
end

-- Adds a speaker to the right of a menu entry (the game's menu system).
-- The initializer returns the row size so the menu leaves room for it.
function Sounds.AddMenuSpeaker(description, id, getChannel)
	if not (description and description.AddInitializer and id) or id == "none" then return end
	description:AddInitializer(function(row)
		local ok, speaker = pcall(row.AttachFrame, row, "Button")
		if not (ok and speaker) then return end
		Sounds.MakeSpeaker(speaker, function() return id end, getChannel, 20)
		speaker:ClearAllPoints()
		speaker:SetPoint("RIGHT", row, "RIGHT", -2, 0)
		local fontString = row.fontString or (row.GetFontString and row:GetFontString())
		local width = fontString and fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth() or 120
		return width + 60, 20
	end)
end

-- Older rows say "/reload" in their desc instead of `reload = true`: they
-- count as reload rows, and the tooltip reads "a reload" (EldoUI never
-- tells the player to type /reload; the window has the button).
local function NeedsReload(option)
	if option.reload then return true end
	local desc = option.englishDesc or option.desc
	return type(desc) == "string" and desc:find("/reload", 1, true) ~= nil
end

local function DescText(option)
	local desc = option.desc
	if type(desc) == "function" then desc = desc() end
	if type(desc) ~= "string" then return nil end
	return (desc:gsub("/reload", function() return L["a reload"] end))
end

-- Changes that wait for a reload (one table: a Lua chunk has room for 200 locals).
local Reloads = {}

---------------------------------------------------------------------------
-- Changes that need a reload. Each `reload = true` row
-- remembers its value when it is first shown; while the value differs
-- from that, the change waits for a reload. The footer's Reload UI counts
-- them and reloads through the secure /reload button; the window asks once
-- when it closes.
---------------------------------------------------------------------------
function Reloads.ReloadId(page, option)
	return page.id .. "\001" .. tostring(KeyOf(option))
end

-- Called when a reload row is shown: the value it had before any change.
function Reloads.RememberReloadValue(page, option)
	local id = Reloads.ReloadId(page, option)
	if reloadSeen[id] == nil then
		local value = GetPath(page.target(), KeyOf(option))
		if type(value) == "table" then value = CopyTable(value) end
		reloadSeen[id] = value == nil and false or value
	end
end

local function TrackReload(page, option)
	local id = Reloads.ReloadId(page, option)
	local before = reloadSeen[id]
	local now = GetPath(page.target(), KeyOf(option))
	if before ~= nil and E.DeepEqual(now == nil and false or now, before) then
		pendingReload[id] = nil
	elseif option.reload == "off" and (now or not before) then
		-- Only turning a shown "on" off waits for a reload.
		pendingReload[id] = nil
	else
		pendingReload[id] = StripCodes(option.label or L["A setting"])
	end
	UpdateReloadButton()
end

-- A change made by a page button (not a row) that needs a reload: it
-- joins the same count. `id` keeps one entry per kind of change.
function E:ConfigNeedsReload(id, label)
	pendingReload["extra\001" .. tostring(id)] = label or L["A setting"]
	UpdateReloadButton()
end

-- A module switched off waits for a reload only when its reload
-- declaration says Blizzard's version needs one to come back
-- (E:ModuleNeedsReload, Core/Blizzard.lua); switching it on again cancels
-- that. One that is on but could not start (it asks for a reload with
-- `reloadToEnable`, or did not start) waits for a reload too, the same from
-- the sidebar switch, the Modules page and the off panel.
local function TrackModule(module)
	local id = "module\001" .. module.name
	if module:IsEnabled() then
		if module.reloadToEnable or (not module.active and not InCombatLockdown()) then
			pendingReload[id] = L["%s on"]:format(L[module.title])
		else
			pendingReload[id] = nil
		end
	elseif not E.ModuleNeedsReload or E:ModuleNeedsReload(module) then
		pendingReload[id] = L["%s off"]:format(L[module.title])
	else
		pendingReload[id] = nil
	end
	UpdateReloadButton()
end

function Reloads.PendingReloads()
	local labels = {}
	for _, label in pairs(pendingReload) do table.insert(labels, label) end
	table.sort(labels)
	return labels
end

function Reloads.ClearReloads()
	wipe(pendingReload)
	promptedReloads = 0
end

-- "Font, Bar texture and 2 more"
function Reloads.ReloadSummary(labels)
	if #labels <= 3 then return table.concat(labels, ", ") end
	return L["%s, %s and %d more"]:format(labels[1], labels[2], #labels - 2)
end

-- Refresh every row of a tab that is on screen (values, dots, grayed rows).
local function RefreshTab(tab)
	for _, widget in pairs(tab.widgets) do
		if widget and widget:IsShown() and widget.refresh then widget.refresh() end
	end
end

-- A row value changed: re-apply, keep the sidebar in sync, re-lay the tab
-- when rows can hide themselves, otherwise refresh its rows (changed
-- dots, rows grayed by `dependsOn`), and the open cog popup.
-- Pages whose refresh repaints every module (General, Colors): a slider
-- drag or a color pick sends many values, so their refresh waits until the
-- values stop for a moment and then applies the last one.
local Changed
do
	local THEME_PAGES = { general = true, colors = true }
	local DRAGGED_TYPES = { range = true, color = true }
	local THEME_REFRESH_DELAY = 0.15

	function Changed(page, tab, option)
		if THEME_PAGES[page.id] and option and DRAGGED_TYPES[option.type] then
			E:Debounce("ConfigRefresh:" .. page.id, THEME_REFRESH_DELAY, function() page.refresh() end)
		else
			page.refresh()
		end
		if option and NeedsReload(option) then TrackReload(page, option) end
		UpdateNav()
		if currentPage == page and not searching and page.tabs then
			local current = page.tabs[page.currentTab or 1]
			if current and (current.dynamic or (tab and tab.dynamic)) then
				ShowTab(page.currentTab, true)
			elseif current then
				RefreshTab(current)
			end
		end
		RefreshCog()
	end
end

-- Value rows of a section, cog children included.
function Bulk.SectionRows(page, section)
	local rows = {}
	for _, option in ipairs(section.items) do
		if VALUE_TYPES[option.type] and not IsHidden(option) then table.insert(rows, option) end
		for _, child in ipairs(page.cogItems and page.cogItems[option] or {}) do
			if VALUE_TYPES[child.type] then table.insert(rows, child) end
		end
	end
	return rows
end

local function ChangedRows(page, section)
	local changed = {}
	if not page.defaults then return changed end
	for _, option in ipairs(Bulk.SectionRows(page, section)) do
		if IsChanged(page, option) then table.insert(changed, option) end
	end
	return changed
end

function Bulk.ResetRows(page, rows)
	for _, option in ipairs(rows) do
		ResetOption(page, option)
		if NeedsReload(option) then TrackReload(page, option) end
	end
	page.refresh()
	E:RefreshConfig()
end

function Bulk.ConfirmSectionReset(page, section)
	local rows = ChangedRows(page, section)
	if #rows == 0 then return end
	local name = section.header and StripCodes(section.header.label) or page.title
	local question = #rows == 1 and L["Put the %d changed setting under %s back to its default?"]
		or L["Put the %d changed settings under %s back to their default?"]
	Confirm(question:format(#rows, E:Highlight(name)), function() Bulk.ResetRows(page, rows) end)
end

---------------------------------------------------------------------------
-- Copy settings between siblings: a `copyFrom` row names the
-- settings table it edits (`path`) and its siblings (`values`).
---------------------------------------------------------------------------
local function CopyPath(option)
	local path = option.path
	if type(path) == "function" then path = path() end
	return type(path) == "string" and path or nil
end

local function CopyKeep(option)
	return option.keep or { "enabled" }
end

-- Row labels by full key, for the preview of a copy: keys that are
-- functions name the frame the page edits now.
function Bulk.CopyLabels(page)
	local labels = {}
	local function Walk(options)
		for _, option in ipairs(options or {}) do
			if type(option) == "table" then
				local ok, key = pcall(KeyOf, option)
				if ok and type(key) == "string" and type(option.label) == "string" and labels[key] == nil then
					labels[key] = StripCodes(option.label)
				end
				Walk(CogOptions(option))
			end
		end
	end
	Walk(page.options)
	return function(key) return labels[key] end
end

-- Sibling paths with their labels, sorted by label, without `own`.
local function Siblings(option, own)
	local list = {}
	for path, label in pairs(SelectValues(option)) do
		if path ~= own then table.insert(list, { path = path, label = StripCodes(label) }) end
	end
	table.sort(list, function(a, b) return a.label < b.label end)
	return list
end

local function LabelOfPath(option, path)
	return StripCodes(SelectValues(option)[path] or path)
end

function Bulk.ConfirmCopy(page, option, from)
	local to = CopyPath(option)
	if not to then return end
	local fromName, toName = E:Highlight(LabelOfPath(option, from)), E:Highlight(LabelOfPath(option, to))
	local changes = E:CopySettingsRowChanges(option, page.target(), from, to)
	if #changes == 0 then
		E:ConfigNotice(L["%s and %s already have the same settings: nothing to copy."]:format(fromName, toName))
		return
	end
	local preview = E:CopySettingsPreview(changes, to, Bulk.CopyLabels(page))
	Confirm(L["Copy the settings of %s to %s?\n\nThis changes: %s.\n\nThe on/off switch and the frame position stay as they are."]:format(
		fromName, toName, preview),
		function()
			local before = CopyTable(GetPath(page.target(), to) or {})
			if E:RunCopySettings(option, page.target(), from, to) then
				Recent.LogCopy(page, to, StripCodes(LabelOfPath(option, to)), before, CopyKeep(option))
				page.refresh()
				E:RefreshConfig()
				E:ConfigNotice(L["Copied the settings of %s to %s."]:format(fromName, toName))
			end
		end)
end

function Bulk.ConfirmApplyAll(page, option)
	local from = CopyPath(option)
	local siblings = from and Siblings(option, from) or {}
	if #siblings == 0 then return end
	local root = page.target()
	local names, targets = {}, {}
	for _, sibling in ipairs(siblings) do
		local count = #E:CopySettingsRowChanges(option, root, from, sibling.path)
		if count > 0 then
			targets[#targets + 1] = sibling
			names[#names + 1] = (count == 1 and L["%s (1 change)"] or L["%s (%d changes)"]):format(sibling.label, count)
		end
	end
	local fromName = E:Highlight(LabelOfPath(option, from))
	if #targets == 0 then
		E:ConfigNotice(L["All of them already have the settings of %s: nothing to copy."]:format(fromName))
		return
	end
	Confirm(L["Copy every setting from %s to %s?\n\nTheir on/off switches and frame positions stay as they are."]:format(
		fromName, table.concat(names, ", ")),
		function()
			for _, sibling in ipairs(targets) do
				local before = CopyTable(GetPath(page.target(), sibling.path) or {})
				if E:RunCopySettings(option, page.target(), from, sibling.path) then
					Recent.LogCopy(page, sibling.path, sibling.label, before, CopyKeep(option))
				end
			end
			page.refresh()
			E:RefreshConfig()
			E:ConfigNotice(L["Copied the settings of %s to %d others."]:format(fromName, #targets))
		end)
end

-- "Apply to all" for one row: the same value on every sibling. Only for
-- rows inside the copyFrom row's settings table.
function Bulk.SiblingTargets(page, tab, option)
	local copy = tab and tab.copyFrom
	local base = copy and CopyPath(copy)
	local key = KeyOf(option)
	if not (base and type(key) == "string" and key:sub(1, #base + 1) == base .. ".") then return nil end
	local rest = key:sub(#base + 2)
	for _, kept in ipairs(CopyKeep(copy)) do
		if rest == kept then return nil end
	end
	local targets = {}
	for _, sibling in ipairs(Siblings(copy, base)) do
		table.insert(targets, { key = sibling.path .. "." .. rest, label = sibling.label })
	end
	return #targets > 0 and targets or nil, copy
end

function Bulk.ConfirmRowApplyAll(page, tab, option)
	local targets = Bulk.SiblingTargets(page, tab, option)
	if not targets then return end
	local names = {}
	for _, target in ipairs(targets) do table.insert(names, target.label) end
	Confirm(L["Set %s the same on %s?"]:format(E:Highlight(StripCodes(option.label)), table.concat(names, ", ")),
		function()
			local value = GetPath(page.target(), KeyOf(option))
			-- Each sibling is set like a row of its own: in Recent changes,
			-- and marked when it needs a reload.
			for _, target in ipairs(targets) do
				local row = setmetatable({ key = target.key, label = ("%s (%s)"):format(StripCodes(option.label), target.label) }, { __index = option })
				SetOption(page, row, Recent.Copy(value))
				if NeedsReload(row) then TrackReload(page, row) end
			end
			page.refresh()
			E:RefreshConfig()
		end)
end

---------------------------------------------------------------------------
-- Row widgets. Each builder returns a frame with `kind`:
--   cell    half-width row: label left, control right (two per line)
--   flow    a button that sits next to the previous one
--   full    full width (descriptions)
--   header  section title
---------------------------------------------------------------------------
local builders = {}

-- Tooltip text of a row: its desc, why it is grayed, the reload note and
-- the reset hint.
local function RowTooltip(cell)
	local option, page = cell.option, cell.page
	local lines = {}
	local desc = DescText(option)
	if desc and desc ~= "" then table.insert(lines, desc) end
	local reason = cell.disabledReason
	if type(reason) == "string" then table.insert(lines, Warn() .. reason .. "|r") end
	local default = page and E:ConfigDefaultText(option, DefaultOf(page, option), desc)
	if default then table.insert(lines, GREY .. default .. "|r") end
	if option.reload == "off" then
		table.insert(lines, GREY .. L["Turning it off takes full effect after a reload."] .. "|r")
	elseif option.reload then
		table.insert(lines, GREY .. L["Takes full effect after a reload."] .. "|r")
	end
	if page and IsChanged(page, option) then
		table.insert(lines, GREY .. L["Changed from the default."] .. "|r")
		table.insert(lines, "")
		table.insert(lines, E.UIKit.HintText(L["Right-click"], L["reset it to the default"]))
	end
	return #lines > 0 and table.concat(lines, "\n") or nil
end

-- Row anatomy: the label left on one line (cut with "..." when the
-- column is narrow; the tooltip shows it whole), one control right. Every
-- select, slider and text box is Tree.ControlWidth() wide, so their edges
-- line up in one column down the page, and switches and swatches share
-- the right edge. Both grow with Large text.
function Tree.ControlWidth()
	return math.floor(152 * E:TextScale() + 0.5)
end

-- The narrowest page that keeps two columns: each cell has room for a
-- label of about 100 px next to its control. Narrower pages use one.
function Tree.TwoColumnWidth()
	return 2 * (16 + math.floor(100 * E:TextScale() + 0.5) + 8 + Tree.ControlWidth() + 12)
end

-- The narrowest page width that keeps two columns (read-only, for
-- plugins that lay out pages like the options window).
function E:ConfigTwoColumnWidth()
	return Tree.TwoColumnWidth()
end

local function Cell(parent, option, page)
	local cell = CreateFrame("Frame", nil, parent)
	cell:SetHeight(ROW)
	cell:EnableMouse(true)
	cell.kind = "cell"
	cell.option, cell.page = option, page
	cell.controls = {}
	cell.tip = function() return RowTooltip(cell) end
	cell.label = Text(cell, E.tokens.size.body, "LEFT", TEXT)
	cell.label:SetText(option.label)
	cell.label:SetWordWrap(false)
	cell.label:SetMaxLines(1)
	cell.label:SetPoint("LEFT", 16, 0)
	-- Changed-from-default marker, left of the label.
	cell.dot = cell:CreateTexture(nil, "OVERLAY")
	cell.dot:SetTexture(E.media.flat)
	cell.dot:SetSize(4, 4)
	cell.dot:SetPoint("LEFT", 6, 0)
	cell.dot:Hide()
	-- The whole row lights up under the mouse (hover.row), also while the
	-- mouse is on one of its controls, so it is clear which row a click
	-- or a right-click (reset) belongs to.
	cell.hoverTex = cell:CreateTexture(nil, "BACKGROUND", nil, 1)
	cell.hoverTex:SetAllPoints()
	cell.hoverTex:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	cell.hoverTex:Hide()
	cell:HookScript("OnEnter", function(self) self.hoverTex:Show() end)
	cell:HookScript("OnLeave", function(self)
		if not self:IsMouseOver() then self.hoverTex:Hide() end
	end)
	cell:HookScript("OnHide", function(self) self.hoverTex:Hide() end)
	AddFlash(cell)
	AddTooltip(cell, option.label, cell.tip, cell.label)
	return cell
end

-- A control inside a cell keeps the row's hover while the mouse is on it.
local function RowHover(cell, control)
	control:HookScript("OnEnter", function() cell.hoverTex:Show() end)
	control:HookScript("OnLeave", function()
		if not cell:IsMouseOver() then cell.hoverTex:Hide() end
	end)
end

-- Put a control on the right of the cell; the label fills the rest.
-- Controls attached here are grayed with the row.
local function Attach(cell, control, option, right)
	control:SetPoint("RIGHT", cell, "RIGHT", right or -12, 0)
	cell.label:SetPoint("RIGHT", control, "LEFT", -8, 0)
	AddTooltip(control, option.label, cell.tip)
	RowHover(cell, control)
	table.insert(cell.controls, control)
end

-- Hover overlay and pressed tint on a flat box button (select, media,
-- copy menus): drawn inside its 1-pixel edge, the box is the hit rect.
local function BoxHover(button)
	local hover, pressed = E:SkinHoverPress(button)
	E:Hairline(hover, "inset", 1)
	E:Hairline(pressed, "inset", 1)
	button:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(Accent()) end)
	button:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(E.media.borderColor)) end)
end

-- Small text link (section Reset): gray, accent on hover.
local function TextLink(parent, label, onClick)
	local link = CreateFrame("Button", nil, parent)
	link:SetHeight(18)
	link.text = Text(link, E.tokens.size.small, "RIGHT", SECONDARY)
	link.text:SetPoint("RIGHT")
	link.text:SetText(label)
	link:SetWidth(math.ceil(link.text:GetStringWidth() + 8))
	link:SetScript("OnEnter", function(self) self.text:SetTextColor(E:TokenColor("accent")) end)
	link:SetScript("OnLeave", function(self) self.text:SetTextColor(unpack(SECONDARY)) end)
	link:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		onClick(self)
	end)
	return link
end

-- Section label (DESIGN.md 0a rule 4): small uppercase text in the
-- secondary color, with an optional muted `hint` after it, over the
-- section's card; the accent stays for what is selected or on (§2).
-- Sections with changed values get a Reset link.
Tree.SECTION_LABEL = 24 -- height of a section label line

-- Folding sections: a header with `fold = true` is drawn as the kit's fold
-- divider (E.UIKit.FoldDivider: the name between two thin accent lines, a
-- chevron on the right, the whole line is the hit rect). A click folds the
-- section's card and rows away; the state is saved for the account
-- (EldoUIDB.configWindow.folds, by page, tab and header). `fold =
-- "folded"` starts folded. A search shows every match, folded or not, and
-- opening a row of a folded section (search result, options link) opens
-- its section.
function Tree.FoldKey(tab, option)
	local page = tab and tab.page
	return ("%s|%s|%s"):format(tostring(page and page.id or "?"), tostring(tab and (tab.englishLabel or tab.label) or ""),
		tostring(option.englishLabel or option.label or ""))
end

function Tree.IsFolded(tab, option)
	if not (option and option.fold) then return false end
	local folds = WindowDB().folds
	local saved = folds and folds[Tree.FoldKey(tab, option)]
	if saved == nil then return option.fold == "folded" end
	return saved and true or false
end

function Tree.SetFolded(tab, option, folded)
	local db = WindowDB()
	db.folds = db.folds or {}
	folded = folded and true or false
	-- Only what differs from the header's own start is kept.
	if folded == (option.fold == "folded") then folded = nil end
	db.folds[Tree.FoldKey(tab, option)] = folded
end

-- Lays the tab out again after a fold: the open page's tab, or a pseudo
-- tab of its own (a cog popup) by itself.
function Tree.Relayout(tab)
	local page = tab and tab.page
	if page and page == currentPage and page.tabs and page.tabs[page.currentTab or 1] == tab then
		ShowTab(page.currentTab, true)
	elseif tab and tab.frame and Tree.LayoutTab then
		Tree.LayoutTab(tab, nil)
	end
end

function Tree.FoldHeader(parent, option, page, tab)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetHeight(Tree.SECTION_LABEL)
	holder.kind = "header"
	holder.fold = true
	local divider = E.UIKit.FoldDivider(holder, {
		label = E.UIKit.SectionText(option.label),
		onToggle = function(folded)
			-- Searching shows every match: the fold waits until it ends.
			if pageFilter then
				holder.divider:SetFolded(false, true)
				return
			end
			Tree.SetFolded(tab, option, folded)
			Tree.Relayout(tab)
		end,
	})
	divider:SetPoint("BOTTOMLEFT", 0, 1)
	holder.divider = divider
	holder.text = divider.label
	E.UIKit.Tooltip(divider, StripCodes(option.label), option.desc or L["Fold or unfold this section. It stays that way."],
		{ { L["Click"], L["fold or unfold"] } })
	local section = tab and tab.sectionByHeader and tab.sectionByHeader[option]
	local reset
	if section and page and page.defaults then
		reset = TextLink(holder, L["Reset section"], function() Bulk.ConfirmSectionReset(page, section) end)
		reset:SetPoint("BOTTOMRIGHT", -4, 3)
		AddTooltip(reset, L["Reset section"], L["Put the changed settings of this section back to their defaults."])
	end
	-- The line stops before the Reset link.
	divider:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", reset and -(reset:GetWidth() + 12) or 0, 1)
	holder.refresh = function()
		local label = E.UIKit.SectionText(option.label)
		local extra = option.hint
		if type(option.status) == "function" then
			local ok, value = pcall(option.status)
			if ok and type(value) == "string" and value ~= "" then extra = value end
		end
		if type(extra) == "string" and extra ~= "" then
			label = label .. "  " .. E:TokenHex(SECONDARY) .. extra .. "|r"
		end
		divider:SetLabel(label)
		divider:SetFolded(not pageFilter and Tree.IsFolded(tab, option), true)
		if reset then reset:SetShown(#ChangedRows(page, section) > 0) end
	end
	AddFlash(holder)
	return holder
end

function builders.header(parent, option, page, tab)
	if option.fold then return Tree.FoldHeader(parent, option, page, tab) end
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetHeight(Tree.SECTION_LABEL)
	holder.kind = "header"
	local text, hint = E.UIKit.SectionLabel(holder, option.label, option.hint)
	text:SetPoint("BOTTOMLEFT", 4, 4)
	holder.text, holder.hint = text, hint
	-- `status`: a short state word after the title (a function, re-read on
	-- every refresh).
	local status
	if type(option.status) == "function" then
		status = Text(holder, E.tokens.size.label, "LEFT", SECONDARY)
		status:SetPoint("LEFT", hint:IsShown() and hint or text, "RIGHT", 8, 0)
	end
	local section = tab and tab.sectionByHeader and tab.sectionByHeader[option]
	local reset
	if section and page and page.defaults then
		reset = TextLink(holder, L["Reset section"], function() Bulk.ConfirmSectionReset(page, section) end)
		reset:SetPoint("BOTTOMRIGHT", -4, 3)
		AddTooltip(reset, L["Reset section"], L["Put the changed settings of this section back to their defaults."])
	end
	-- A long label or hint never runs under the Reset link.
	hint:SetPoint("RIGHT", holder, "RIGHT", reset and -(reset:GetWidth() + 12) or -4, 0)
	holder.refresh = function()
		text:SetText(E.UIKit.SectionText(option.label))
		text:SetTextColor(unpack(SECONDARY))
		if status then
			local ok, value = pcall(option.status)
			status:SetText(ok and type(value) == "string" and value or "")
		end
		if reset then reset:SetShown(#ChangedRows(page, section) > 0) end
	end
	AddFlash(holder)
	return holder
end

-- Text colors of a description's `tone` (theme tokens, read at draw time).
Tree.TONES = { muted = "secondary", warning = "warn", body = "body", good = "good", bad = "bad" }

function Tree.DescriptionText(option)
	-- `terms`: { { "term", "what it means" }, ... }, one per line, the term in
	-- body text (a reference list such as the text tags).
	if type(option.terms) == "table" then
		local body, lines = E:TokenHex(TEXT), {}
		for _, term in ipairs(option.terms) do
			lines[#lines + 1] = body .. tostring(term[1]) .. "|r  " .. tostring(term[2] or "")
		end
		return table.concat(lines, "\n")
	end
	local label = option.label
	if type(label) == "function" then
		local ok, value = pcall(label)
		label = ok and value or nil
	end
	return type(label) == "string" and label or ""
end

function Tree.ToneColor(option)
	local tone = option.tone
	if type(tone) == "function" then tone = tone() end
	return E.tokens.text[Tree.TONES[tone] or "secondary"] or SECONDARY
end

function builders.description(parent, option)
	local holder = CreateFrame("Frame", nil, parent)
	holder.kind = "full"
	local text = Text(holder, E.tokens.size.label, "LEFT", SECONDARY)
	text:SetWordWrap(true)
	text:SetPoint("TOPLEFT", 4, -4)
	holder.text = text
	local function Paint()
		text:SetText(Tree.DescriptionText(option))
		text:SetTextColor(unpack(Tree.ToneColor(option)))
	end
	Paint()
	holder.Resize = function(self, width)
		Paint()
		text:SetWidth(width - 8)
		self:SetHeight(math.max(20, math.ceil((text:GetStringHeight() + 8) / 4) * 4))
	end
	holder.refresh = Paint
	holder:Resize(400)
	return holder
end

-- On/off rows are switches (E.UIKit.Switch, accent when on) on the right
-- edge. The kit gives the 18 px switch 3 px more hit height each way,
-- inside the row (DESIGN.md 3a); clicking the label toggles too, and
-- hovering the row lights the switch the same way hovering it does.
function builders.toggle(parent, option, page, tab)
	local cell = Cell(parent, option, page)
	local switch = E.UIKit.Switch(cell, {
		onChange = function(on)
			SetOption(page, option, on)
			Changed(page, tab, option)
		end,
	})
	cell.switch = switch
	Attach(cell, switch, option, -12)
	cell.refresh = function() switch:SetChecked(GetPath(Tree.RootOf(page, option), KeyOf(option)) and true or false) end
	cell:HookScript("OnEnter", function()
		if not cell.disabledReason then switch.kitHover = true; switch:Paint() end
	end)
	cell:HookScript("OnLeave", function(self)
		if not self:IsMouseOver() then switch.kitHover = false; switch:Paint() end
	end)
	-- Clicking the label toggles too.
	cell:SetScript("OnMouseUp", function(_, mouse)
		if mouse == "LeftButton" and not cell.disabledReason and cell:IsMouseOver() then switch:Click() end
	end)
	return cell
end

local function EditBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetSize(width, E.tokens.height.row)
	box:SetAutoFocus(false)
	E:SetFont(box, E.tokens.size.body)
	Skin("SkinEditBox", box, { size = E.tokens.size.body })
	return box
end

function builders.range(parent, option, page, tab)
	local cell = Cell(parent, option, page)

	-- A unit or percent needs a wider box ("85 %", "120 px").
	local box = EditBox(cell, (option.unit or option.percent) and 56 or 44)
	-- A word for 0 ("Off", "Full width") gets the room it needs, up to 120.
	if type(option.zeroText) == "string" then
		local probe = box:CreateFontString(nil, "OVERLAY")
		local font, size, flags = box:GetFont()
		if font then probe:SetFont(font, size, flags) end
		probe:SetText(L[option.zeroText])
		local need = math.ceil(probe:GetStringWidth() or 0) + 16
		probe:Hide()
		if need > (box:GetWidth() or 0) then box:SetWidth(math.min(need, 120)) end
	end
	box:SetJustifyH("CENTER")
	box:SetPoint("RIGHT", -12, 0)

	local slider = CreateFrame("Slider", nil, cell)
	slider:SetOrientation("HORIZONTAL")
	-- Slider and value box together fill the control column.
	local function SliderWidth()
		return math.max(60, Tree.ControlWidth() - box:GetWidth() - 12)
	end
	slider:SetSize(SliderWidth(), 8)
	slider:SetPoint("RIGHT", box, "LEFT", -12, 0)
	-- Flat track, accent fill and thumb; the hit rect is as tall as the
	-- thumb (Core/Skin.lua), so the drawn thumb is where it clicks.
	local look = E:SkinSlider(slider, { rowHeight = ROW - 4 })
	boxes[slider] = { transparent = true }
	-- option.softMax: the slider ends there, the box takes up to max (a
	-- gold goal drags from 0 to 5000 and still takes 50000 typed).
	local top = tonumber(option.softMax) and math.min(option.softMax, option.max) or option.max
	slider:SetMinMaxValues(option.min, top)
	slider:SetValueStep(option.step or 1)
	slider:SetObeyStepOnDrag(true)
	cell.label:SetPoint("RIGHT", slider, "LEFT", -8, 0)
	AddTooltip(slider, option.label, cell.tip)
	AddTooltip(box, option.label, cell.tip)
	RowHover(cell, slider)
	RowHover(cell, box)
	table.insert(cell.controls, slider)
	table.insert(cell.controls, box)

	-- Stored value as it is saved; the box shows it with its unit.
	local function Format(value)
		return E:ConfigRangeValue(option, value)
	end
	local function Display(value)
		return E:ConfigRangeText(option, value)
	end
	local updating = false
	cell.refresh = function()
		updating = true
		slider:SetWidth(SliderWidth())
		look.Paint()
		local value = GetPath(page.target(), KeyOf(option)) or option.min
		slider:SetValue(math.min(value, top))
		if not box:HasFocus() then box:SetText(Display(value)) end
		updating = false
	end
	-- The setting applies when the slider is released (DESIGN.md 5):
	-- while the thumb is dragged only the slider and its value box move,
	-- plus the option's own cheap preview. option.live = true applies on
	-- every step, for the few settings that cost nothing to apply.
	local Feed = E.UIKit.SliderCommit(slider, {
		live = option.live,
		preview = option.preview and function(value) option.preview(Format(value)) end,
		commit = function(value)
			SetOption(page, option, Format(value))
			Changed(page, tab, option)
		end,
	})
	slider:SetScript("OnValueChanged", function(_, value)
		if updating then return end
		box:SetText(Display(value))
		Feed(value)
	end)
	box:SetScript("OnEnterPressed", function(self)
		-- "85 %", "85" or "0.5 s": the number counts, the unit is optional.
		local value = tonumber((self:GetText() or ""):gsub(",", "."):match("%-?[%d%.]+") or "")
		if value then
			if option.percent then value = value / 100 end
			value = math.max(option.min, math.min(option.max, value))
			if value > top then
				-- Past the slider's end: store it as typed, rounded to the step.
				local step = option.step or 1
				value = math.floor(value / step + 0.5) * step
				SetOption(page, option, Format(value))
				Changed(page, tab, option)
				updating = true
				slider:SetValue(top)
				updating = false
			else
				slider:SetValue(value)
			end
		end
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:HookScript("OnEditFocusLost", function(self)
		self:SetText(Display(GetPath(page.target(), KeyOf(option)) or option.min))
	end)
	return cell
end

-- option.valueIcons(value) -> texture, left, right, top, bottom: a small
-- picture left of each choice (a language's flag), in the list and in the
-- box. A value without one, or a picture that does not load, shows its
-- name only. Returns whether the picture shows.
function Tree.ValueIcon(icon, option, value)
	local ok, path, left, right, top, bottom = pcall(option.valueIcons, value)
	if not ok or (type(path) ~= "string" and type(path) ~= "number") or icon:SetTexture(path) == false then
		icon:Hide()
		return false
	end
	if left then icon:SetTexCoord(left, right, top, bottom) else icon:SetTexCoord(0, 1, 0, 1) end
	icon:Show()
	return true
end

function builders.select(parent, option, page, tab)
	local cell = Cell(parent, option, page)
	local button = CreateFrame("Button", nil, cell)
	-- The box grows with Large text, so a choice name that fits at
	-- 100 % fits at 160 % too.
	-- `wide`: long choice names (a row of its own) get up to 1.8 times the
	-- width, as long as the row's label keeps its room.
	local function SizeBox()
		local scale = E:TextScale()
		local width = Tree.ControlWidth() - (option.sound and 26 or 0)
		if option.wide then
			local label = cell.label.GetUnboundedStringWidth and cell.label:GetUnboundedStringWidth() or cell.label:GetStringWidth()
			local room = (cell:GetWidth() or 0) - 16 - math.ceil(label or 0) - 8 - 12
			width = math.max(width, math.min(math.floor(width * 1.8), math.floor(room)))
		end
		button:SetSize(width, math.max(20, math.ceil(E.tokens.size.label * scale + 8)))
	end
	SizeBox()
	Box(button, true)
	button.text = Text(button, E.tokens.size.label, "LEFT", TEXT)
	button.text:SetPoint("LEFT", 8, 0)
	button.text:SetPoint("RIGHT", -20, 0)
	local arrow = button:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture(CHEVRON)
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -4, 0)
	arrow:SetVertexColor(unpack(SECONDARY))
	if option.valueIcons then button.icon = button:CreateTexture(nil, "ARTWORK") end
	-- option.sound: the values are sounds; adds speakers to preview them.
	local function Channel()
		local key = type(option.channel) == "function" and option.channel() or option.channel
		return key and GetPath(page.target(), key)
	end
	if option.sound then
		local speaker = Speaker(cell, function() return GetPath(page.target(), KeyOf(option)) end, Channel)
		Attach(cell, speaker, option)
		button:SetPoint("RIGHT", speaker, "LEFT", -6, 0)
		cell.label:SetPoint("RIGHT", button, "LEFT", -8, 0)
		AddTooltip(button, option.label, cell.tip)
		RowHover(cell, button)
		table.insert(cell.controls, button)
	else
		Attach(cell, button, option)
	end
	BoxHover(button)

	cell.refresh = function()
		SizeBox()
		local current = GetPath(page.target(), KeyOf(option))
		local name = SelectValues(option)[current]
		if name == nil and Tree.NoChoices(option) then name = L["None"] end
		-- An action select (copy from, delete, set every module) keeps no
		-- value: it shows a prompt instead.
		button.text:SetText(name or (current == nil and L["Choose..."]) or tostring(current))
		if button.icon then
			local size = math.max(12, math.floor(button:GetHeight() - 6))
			button.icon:SetSize(size, size)
			button.icon:SetPoint("LEFT", 8, 0)
			local shown = Tree.ValueIcon(button.icon, option, current)
			button.text:SetPoint("LEFT", shown and (8 + size + 5) or 8, 0)
		end
	end
	button:SetScript("OnClick", function(self)
		local list = {}
		for value, name in pairs(SelectValues(option)) do
			table.insert(list, { value = value, name = name })
		end
		-- option.order lists values in the order they show (a ladder such as
		-- Off, Subtle, Standard, Vivid); the rest follow by name.
		local rank = {}
		local order = option.order
		if type(order) == "function" then order = order() end
		if type(order) == "table" then
			for index, value in ipairs(order) do rank[value] = index end
		end
		table.sort(list, function(a, b)
			local ra, rb = rank[a.value], rank[b.value]
			if ra or rb then
				if ra and rb then return ra < rb end
				return ra ~= nil
			end
			return tostring(a.name) < tostring(b.name)
		end)
		local descs = option.valueDescs
		if type(descs) == "function" then descs = descs() end
		if type(descs) ~= "table" then descs = nil end
		-- The kit menu under the row's box, scrolling when long.
		E.UIKit.ContextMenu(self, function(_, root)
			root:SetScrollMode(360)
			for _, entry in ipairs(list) do
				local radio = root:CreateRadio(entry.name,
					function() return GetPath(page.target(), KeyOf(option)) == entry.value end,
					function()
						SetOption(page, option, entry.value)
						cell.refresh()
						Changed(page, tab, option)
					end)
				if option.sound then Sounds.AddMenuSpeaker(radio, entry.value, Channel) end
				if option.valueIcons then
					radio:AddInitializer(function(row)
						if not (row.text and row.AttachFrame) then return end
						local holder = row:AttachFrame("Frame")
						local size = math.max(12, math.floor(row:GetHeight() - 8))
						holder:SetSize(size, size)
						holder:SetPoint("LEFT", row, "LEFT", E.UIKit.MENU_TEXT_LEFT, 0)
						holder.icon = holder.icon or holder:CreateTexture(nil, "ARTWORK")
						holder.icon:SetAllPoints()
						if not Tree.ValueIcon(holder.icon, option, entry.value) then
							holder:Hide()
							return
						end
						row.text:SetPoint("LEFT", holder, "RIGHT", 6, 0)
						local width = row.text.GetUnboundedStringWidth and row.text:GetUnboundedStringWidth() or row.text:GetStringWidth()
						return math.ceil(tonumber(width) or 0) + E.UIKit.MENU_TEXT_LEFT + size + 6 + 8
					end)
				end
				local tip = descs and descs[entry.value]
				if type(tip) ~= "string" or tip == "" then tip = nil end
				-- A choice that can't be taken right now stays in the list, grayed,
				-- with the reason in its tooltip.
				local blocked = type(option.valueDisabled) == "function" and option.valueDisabled(entry.value) or nil
				if blocked then radio:SetEnabled(false) end
				if tip or type(blocked) == "string" then
					radio:SetTooltip(function(tooltip)
						E.UIKit.TipTitle(tooltip, tostring(entry.name))
						if tip then E.UIKit.TipText(tooltip, L[tip]) end
						if type(blocked) == "string" then E.UIKit.TipText(tooltip, blocked) end
					end)
				end
			end
		end, { at = "owner" })
	end)
	return cell
end

-- Media picker (sounds, fonts, bar textures) from the media registry
-- (Core/MediaRegistry.lua): one submenu per source, a speaker to play
-- the chosen sound and one on every sound in the list, and each font
-- shown in its own face.
--   option.mediaKind  "sound" | "font" | "statusbar"
--   option.filter     passed to E:MediaList (sounds: { playable = "file" })
--   option.none       adds "None" (sounds)
--   option.default    adds "Module default" with this value (e.g. "default")
--   option.allowCustom  adds "Custom file ID or path..." (sounds)
-- "Custom file ID or path...": asks in the shared confirm's edit box;
-- Set gets the new sound id.
function Tree.AskCustomSound(Set)
	return E:ShowConfirm({
		title = L["Custom sound"],
		text = L["Sound file ID (a number) or an addon path such as Interface\\AddOns\\MyMedia\\horn.ogg"],
		edit = { hint = L["File ID or path"] },
		accept = L["Use"],
		onAccept = function(_, typed)
			local text = strtrim(typed or "")
			local id
			if tonumber(text) then id = "fid:" .. tonumber(text)
			elseif E:IsSoundPath(text) then id = "file:" .. text end
			if id then Set(id) else E:ConfigNotice(L["That is not a sound file ID or an addon .ogg/.mp3 path."], true) end
		end,
	})
end

function builders.media(parent, option, page, tab)
	local kind = option.mediaKind or "sound"
	local cell = Cell(parent, option, page)
	local button = CreateFrame("Button", nil, cell)
	cell.picker = button
	local function SizeBox()
		local width = Tree.ControlWidth() - (kind == "sound" and 26 or 0)
		if button.text then
			local label = cell.label:GetUnboundedStringWidth()
			local room = (cell:GetWidth() or 0) - 16 - math.ceil(label or 0) - 8 - 12 - (kind == "sound" and 26 or 0)
			width = math.max(width, math.min(math.ceil(button.text:GetUnboundedStringWidth() + 28), room))
		end
		button:SetSize(width, math.max(20, math.ceil(E.tokens.size.label * E:TextScale() + 8)))
	end
	SizeBox()
	Box(button, true)
	button.text = Text(button, E.tokens.size.label, "LEFT", TEXT)
	button.text:SetPoint("LEFT", 8, 0)
	button.text:SetPoint("RIGHT", -20, 0)
	local arrow = button:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture(CHEVRON)
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -4, 0)
	arrow:SetVertexColor(unpack(SECONDARY))
	BoxHover(button)

	local function Current() return GetPath(page.target(), KeyOf(option)) end
	local function Set(value)
		SetOption(page, option, value)
		cell.refresh()
		Changed(page, tab, option)
	end

	local function Channel()
		local key = type(option.channel) == "function" and option.channel() or option.channel
		return key and GetPath(page.target(), key)
	end
	if kind == "sound" then
		local play = Speaker(cell, Current, Channel)
		play:SetPoint("RIGHT", cell, "RIGHT", -12, 0)
		button:SetPoint("RIGHT", play, "LEFT", -6, 0)
		cell.label:SetPoint("RIGHT", button, "LEFT", -8, 0)
		AddTooltip(button, option.label, cell.tip)
		RowHover(cell, button)
		RowHover(cell, play)
		table.insert(cell.controls, button)
	else
		Attach(cell, button, option)
	end

	cell.refresh = function()
		local current = Current()
		if option.default and current == option.default then
			button.text:SetText(option.defaultLabel and L[option.defaultLabel] or L["General setting"])
		else
			button.text:SetText(E:MediaLabel(kind, current))
		end
		if kind == "font" then
			local path = (current and current ~= option.default) and E:FetchMedia("font", current)
			-- The value in the picked font, as window text: it follows
			-- Large text, and a font the client refuses falls back to the theme.
			E:SetWindowFont(button.text, E.tokens.size.label, false, path or nil)
		end
		SizeBox()
	end

	button:SetScript("OnClick", function(self)
		local groups, sources = {}, {}
		for _, entry in ipairs(E:MediaList(kind, option.filter)) do
			if not groups[entry.source] then
				groups[entry.source] = {}
				table.insert(sources, entry.source)
			end
			table.insert(groups[entry.source], entry)
		end
		E.UIKit.ContextMenu(self, function(_, root)
			local function IsSelected(value) return function() return Current() == value end end
			local function Radio(menu, label, value, entry)
				local radio = menu:CreateRadio(label, IsSelected(value), function() Set(value) end)
				if entry and kind == "sound" then Sounds.AddMenuSpeaker(radio, entry.id, Channel) end
				if entry and kind == "font" and radio.AddInitializer then
					radio:AddInitializer(function(widget)
						local fontString = widget.fontString or (widget.GetFontString and widget:GetFontString())
						if fontString then fontString:SetFont(E:FetchMedia("font", entry.id) or E.media.font, 13, "") end
					end)
				end
				return radio
			end
			if option.default then Radio(root, option.defaultLabel and L[option.defaultLabel] or L["General setting"], option.default) end
			if option.none then Radio(root, NONE or L["None"], "none") end
			for _, source in ipairs(sources) do
				-- A single source shows its items directly; several get submenus.
				local menu = #sources > 1 and root:CreateButton(source) or root
				if menu.SetScrollMode then menu:SetScrollMode(360) end
				for _, entry in ipairs(groups[source]) do Radio(menu, entry.name, entry.id, entry) end
			end
			if option.allowCustom then
				root:CreateButton(L["Custom file ID or path..."], function()
					Tree.AskCustomSound(Set)
				end)
			end
		end, { at = "owner" })
	end)
	return cell
end

function builders.color(parent, option, page, tab)
	local cell = Cell(parent, option, page)
	local swatch = CreateFrame("Button", nil, cell)
	swatch:SetSize(36, 16)
	Box(swatch)
	-- A 16 px swatch: 4 px more hit height above and below (DESIGN.md 3a).
	E:PadHitRect(swatch, 4, ROW)
	Attach(cell, swatch, option)
	swatch:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(Accent()) end)
	swatch:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(E.media.borderColor)) end)
	cell.refresh = function()
		local color = GetPath(page.target(), KeyOf(option)) or { 1, 1, 1 }
		swatch:SetBackdropColor(color[1], color[2], color[3], 1)
	end
	swatch:SetScript("OnClick", function()
		local color = GetPath(page.target(), KeyOf(option)) or { 1, 1, 1 }
		local previous = { color[1], color[2], color[3] }
		local function Apply(r, g, b)
			SetOption(page, option, { r, g, b })
			cell.refresh()
			Changed(page, tab, option)
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = color[1], g = color[2], b = color[3],
			swatchFunc = function() Apply(ColorPickerFrame:GetColorRGB()) end,
			cancelFunc = function() Apply(previous[1], previous[2], previous[3]) end,
		})
	end)
	return cell
end

function builders.input(parent, option, page, tab)
	local cell = Cell(parent, option, page)
	local box = EditBox(cell, Tree.ControlWidth())
	Attach(cell, box, option)
	cell.refresh = function()
		box:SetWidth(Tree.ControlWidth())
		if not box:HasFocus() then box:SetText(tostring(GetPath(page.target(), KeyOf(option)) or "")) end
	end
	box:SetScript("OnEnterPressed", function(self)
		SetOption(page, option, self:GetText())
		self:ClearFocus()
		Changed(page, tab, option)
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:HookScript("OnEditFocusLost", function() cell.refresh() end)
	return cell
end

-- An execute row's `active` function, safe: a failing check marks nothing.
local function ActiveRow(option)
	if type(option.active) ~= "function" then return false end
	local ok, active = pcall(option.active)
	return ok and active and true or false
end

-- Consecutive execute options flow side by side as a grid of buttons.
function builders.execute(parent, option)
	local button
	button = Button(parent, option.label, option.width or 200, BUTTON, function()
		if button.disabledReason then return end
		-- `confirm = true`: work that can't be undone asks first.
		if option.confirm then
			local question = option.confirm
			if type(question) == "function" then question = question() end
			local danger = option.confirmDanger ~= false
			if type(question) == "string" then
				question = L[question]
			else
				-- The row's tooltip line, plus the warning the hand-written
				-- questions give.
				question = DescText(option)
				if danger then
					question = question and (question .. " " .. L["This can't be undone."]) or L["This can't be undone."]
				end
			end
			-- The accept button names the action ("Delete theme") in the
			-- danger look, like the hand-written questions;
			-- `confirmAccept` for a shorter word, `confirmDanger = false`
			-- for work that deletes or resets nothing.
			E:ShowConfirm({ title = StripCodes(option.label), text = question,
				accept = option.confirmAccept and L[option.confirmAccept] or StripCodes(option.label),
				danger = danger,
				onAccept = function() E:RunConfigRow(option.func) end })
		else
			E:RunConfigRow(option.func)
		end
	end)
	button.kind = "flow"
	E.UIKit.FitButton(button, option.width or 200)
	AddFlash(button)
	AddTooltip(button, option.label, function()
		local desc = DescText(option)
		if ActiveRow(option) then
			desc = (desc and desc ~= "" and (desc .. "\n") or "") .. E:Highlight(L["Applied last"])
		end
		local reason = button.disabledReason
		if type(reason) == "string" then
			return (desc and desc ~= "" and (desc .. "\n") or "") .. Warn() .. reason .. "|r"
		end
		return desc
	end, button.text)
	return button
end

-- Live preview block: the module draws into the frame once
-- (create) and redraws it after every change (update).
function builders.preview(parent, option, page)
	local holder = CreateFrame("Frame", nil, parent)
	holder.kind = "full"
	holder.isPreview = true
	Box(holder, true, INSET_TINT)
	-- `height` may be a function(canvas, width) that lays the block out for
	-- the page width and returns its height (a card grid that wraps).
	holder.Resize = function(self, width)
		local height = option.height
		if type(height) == "function" then
			local ok, result = pcall(height, self.canvas, math.max((width or 400) - 16, 1))
			if not ok then geterrorhandler()(result) end
			height = ok and type(result) == "number" and result + 16 or nil
		end
		self:SetHeight(height or 96)
	end
	holder.canvas = CreateFrame("Frame", nil, holder)
	holder.canvas:SetPoint("TOPLEFT", 8, -8)
	holder.canvas:SetPoint("BOTTOMRIGHT", -8, 8)
	if option.label and not option.noCaption then
		local caption = Text(holder, E.tokens.size.small, "RIGHT", DIM)
		caption:SetPoint("TOPRIGHT", -8, -6)
		caption:SetText(option.label)
	end
	if type(option.create) == "function" then
		local ok, err = pcall(option.create, holder.canvas, page)
		if not ok then geterrorhandler()(err) end
	end
	holder:Resize(400)
	holder.refresh = function()
		if type(option.update) ~= "function" then return end
		local ok, err = pcall(option.update, holder.canvas, page.target())
		if not ok then geterrorhandler()(err) end
	end
	return holder
end

-- Copy settings from a sibling: a menu of the siblings, plus
-- "Apply these to all".
function builders.copyFrom(parent, option, page)
	local cell = Cell(parent, option, page)
	local button = CreateFrame("Button", nil, cell)
	button:SetSize(168, E.tokens.height.row)
	Box(button, true)
	button.text = Text(button, E.tokens.size.label, "LEFT", SECONDARY)
	button.text:SetPoint("LEFT", 8, 0)
	button.text:SetPoint("RIGHT", -20, 0)
	button.text:SetText(L["Choose..."])
	local arrow = button:CreateTexture(nil, "OVERLAY")
	arrow:SetTexture(CHEVRON)
	arrow:SetSize(12, 12)
	arrow:SetPoint("RIGHT", -4, 0)
	arrow:SetVertexColor(unpack(SECONDARY))
	Attach(cell, button, option)
	BoxHover(button)
	button:SetScript("OnClick", function(self)
		local own = CopyPath(option)
		if not own then return end
		local siblings = Siblings(option, own)
		E.UIKit.ContextMenu(self, function(_, root)
			root:CreateTitle(L["Copy into %s from"]:format(LabelOfPath(option, own)))
			for _, sibling in ipairs(siblings) do
				root:CreateButton(sibling.label, function() Bulk.ConfirmCopy(page, option, sibling.path) end)
			end
			if #siblings > 0 then
				root:CreateDivider()
				root:CreateButton(L["Apply %s to all of them"]:format(LabelOfPath(option, own)), function() Bulk.ConfirmApplyAll(page, option) end)
			end
		end, { at = "owner" })
	end)
	return cell
end

-- A row with only a gear: opens a group of rare settings.
function builders.cog(parent, option, page)
	local cell = Cell(parent, option, page)
	local gear = CreateFrame("Button", nil, cell) -- lint: no-click ok (SetupGear gives cell.gear its scripts)
	gear:SetSize(20, 20)
	gear.icon = gear:CreateTexture(nil, "ARTWORK")
	SetClientArt(gear.icon, "gear")
	gear.icon:SetAllPoints()
	E:PadHitRect(gear, 3, ROW)
	Attach(cell, gear, option, -14)
	cell.gear = gear
	return cell
end

---------------------------------------------------------------------------
-- Tab layout
---------------------------------------------------------------------------
-- The gear of a row with a cog: grayed while the row is grayed or (for a
-- toggle) off.
local function GearBlocked(cell)
	if cell.disabledReason then return cell.disabledReason end
	local option = cell.option
	if option.type == "toggle" and not GetPath(cell.page.target(), KeyOf(option)) then
		return L["Turn on \"%s\" first."]:format(StripCodes(option.label))
	end
end

local function PaintGear(cell)
	local gear = cell.gear
	local blocked = GearBlocked(cell)
	gear:SetAlpha(blocked and 0.3 or 1)
	if gear.hover and not blocked then
		gear.icon:SetVertexColor(Accent())
	else
		gear.icon:SetVertexColor(unpack(SECONDARY))
	end
end

local function SetupGear(cell, tab)
	local option, page = cell.option, cell.page
	local gear = cell.gear
	if not gear then
		gear = CreateFrame("Button", nil, cell)
		gear:SetSize(18, 18)
		gear.icon = gear:CreateTexture(nil, "ARTWORK")
		SetClientArt(gear.icon, "gear")
		gear.icon:SetAllPoints()
		-- Left of the row's control; the label ends before it.
		local first = cell.controls[1]
		if first then
			gear:SetPoint("RIGHT", first, "LEFT", -6, 0)
		else
			gear:SetPoint("RIGHT", cell, "RIGHT", -12, 0)
		end
		cell.label:SetPoint("RIGHT", gear, "LEFT", -6, 0)
		E:PadHitRect(gear, 3, ROW)
		cell.gear = gear
	end
	gear:SetScript("OnEnter", function(self)
		self.hover = true
		PaintGear(cell)
		E.UIKit.AnchorTooltip(self, GameTooltip)
		E.UIKit.TipTitle(GameTooltip, StripCodes(option.label))
		local names = {}
		for _, child in ipairs(page.cogItems[option] or {}) do
			if child.label and child.type ~= "description" then table.insert(names, StripCodes(child.label)) end
		end
		E.UIKit.TipText(GameTooltip, L["More settings: %s."]:format(table.concat(names, ", ")))
		local blocked = GearBlocked(cell)
		if type(blocked) == "string" then GameTooltip:AddLine(blocked, WARN_RGB[1], WARN_RGB[2], WARN_RGB[3], true) end
		GameTooltip:Show()
	end)
	gear:SetScript("OnLeave", function(self)
		self.hover = false
		PaintGear(cell)
		GameTooltip_Hide()
	end)
	gear:SetScript("OnClick", function()
		if GearBlocked(cell) then return end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		OpenCog(cell, option, page, tab)
	end)
	-- After the scripts above, which replace any earlier hook.
	RowHover(cell, gear)
end

-- Right-click on a row: reset it, or set it the same on every sibling.
local function RowMenu(cell)
	local option, page, tab = cell.option, cell.page, cell.tab
	if not VALUE_TYPES[option.type] or cell.disabledReason then return end
	local changed = IsChanged(page, option)
	local targets = Bulk.SiblingTargets(page, tab, option)
	if not changed and not targets then return end
	E.UIKit.ContextMenu(cell, function(_, root)
		root:CreateTitle(StripCodes(option.label))
		if changed then
			root:CreateButton(L["Reset to default"], function()
				ResetOption(page, option)
				Changed(page, tab, option)
			end)
		end
		if targets then
			root:CreateButton(L["Apply to all (%d)"]:format(#targets), function() Bulk.ConfirmRowApplyAll(page, tab, option) end)
		end
	end)
end

-- Grayed rows, the changed dot and the gear, after every refresh.
local function UpdateRowState(widget)
	local option, page = widget.option, widget.page
	local reason = DisabledReason(option, page)
	widget.disabledReason = reason
	if widget.kind == "cell" then
		widget.label:SetTextColor(unpack(reason and DIM or TEXT))
		for _, control in ipairs(widget.controls) do
			control:EnableMouse(not reason)
			control:SetAlpha(reason and 0.4 or 1)
		end
		-- A gear row also shows the dot when one of its cog settings changed.
		local changed = IsChanged(page, option)
		if not changed and widget.gear then
			for _, child in ipairs(page.cogItems[option] or {}) do
				if IsChanged(page, child) then changed = true break end
			end
		end
		widget.dot:SetVertexColor(Accent())
		widget.dot:SetShown(changed)
		if widget.gear then PaintGear(widget) end
		if NeedsReload(option) then Reloads.RememberReloadValue(page, option) end
	elseif widget.kind == "flow" then
		widget:SetAlpha(reason and 0.4 or 1)
		-- `active = function`: the selected look on the row in use (the
		-- style applied last on a Presets tab).
		if option.active then E.UIKit.SetButtonSelected(widget, ActiveRow(option)) end
	end
end

local function Decorate(widget, option, tab)
	widget.option, widget.page, widget.tab = option, tab.page, tab
	if widget.kind == "cell" then
		local children = tab.page.cogItems and tab.page.cogItems[option]
		if children and #children > 0 then SetupGear(widget, tab) end
		widget:HookScript("OnMouseUp", function(self, mouse)
			if mouse == "RightButton" then RowMenu(self) end
		end)
	end
	if widget.kind == "cell" or widget.kind == "flow" then
		local refresh = widget.refresh
		widget.refresh = function()
			if refresh then refresh() end
			UpdateRowState(widget)
		end
	end
end

local function Widget(tab, option)
	local widget = tab.widgets[option]
	if widget == nil then
		local builder = builders[option.type]
		widget = builder and builder(tab.frame, option, tab.page, tab) or false
		if widget then
			Decorate(widget, option, tab)
			Snap(widget)
		end
		tab.widgets[option] = widget
	end
	return widget or nil
end

-- Section cards (DESIGN.md 0a rule 4): each section's rows sit on one
-- E.UIKit.SectionCard, under the section's label. The card draws the
-- alternating row tint, the divider under each row and the one between the
-- two halves. A cog popup is already a small panel, so its card shows the
-- rows' tint and dividers only (no box inside a box).
local function SectionCard(tab, section)
	tab.cards = tab.cards or {}
	local card = tab.cards[section]
	if not card then
		card = E.UIKit.SectionCard(tab.frame, { rowHeight = ROW, bare = tab.single })
		card:SetFrameLevel(tab.frame:GetFrameLevel())
		tab.cards[section] = card
		Snap(card)
	end
	return card
end

-- Coordinate pairs share one row, in this order: X | Y, Width | Height,
-- Offset X | Offset Y (design decision). A row ending in x, X, Width or
-- width (or starting with x and a capital, as xOffset) pairs with the row
-- right after it when that row has the same key with y, Y, Height, height
-- (or yOffset). `pair = "start"` on a row pairs it with the next row by
-- hand, `pair = false` turns the pairing off. When a pair would start in
-- the right half, the row before it keeps a row of its own, and the empty
-- half next to it is meant to be there.
Tree.PAIR_ENDS = { { "x", "y" }, { "X", "Y" }, { "Width", "Height" }, { "width", "height" } }

function Tree.PairName(name)
	if type(name) ~= "string" then return nil end
	for _, ends in ipairs(Tree.PAIR_ENDS) do
		local first = ends[1]
		if name:sub(-#first) == first then return name:sub(1, -#first - 1) .. ends[2] end
	end
	local rest = name:match("^x(%u.*)$")
	if rest then return "y" .. rest end
end

-- The key the row right after `option` needs to pair with it (nil: none).
function Tree.PartnerKey(option)
	local key = option and KeyOf(option)
	if type(key) ~= "string" then return nil end
	local prefix, name = key:match("^(.-)([^%.]+)$")
	local partner = Tree.PairName(name)
	return partner and (prefix .. partner) or nil
end

function Tree.StartsPair(option, nextOption)
	if not (option and nextOption) or option.pair == false then return false end
	if option.pair == "start" then return true end
	local partner = Tree.PartnerKey(option)
	return partner ~= nil and partner == KeyOf(nextOption)
end
E.ConfigPartnerKey = Tree.PartnerKey -- exposed for inspection

-- Place every visible row of a tab; returns the content height.
local function LayoutTab(tab, filter)
	local frame = tab.frame
	local width = frame:GetWidth()
	-- A cog popup, and a page too narrow for two label and control
	-- columns, put one row per line.
	local single = tab.single or tab.oneColumn or width < Tree.TwoColumnWidth()
	local half = single and width or math.floor(width / 2)
	for _, widget in pairs(tab.widgets) do
		if widget then widget:Hide() end
	end
	for _, card in pairs(tab.cards or {}) do card:Hide() end
	tab.foldLinks = tab.foldLinks or {}
	for _, link in pairs(tab.foldLinks) do link:Hide() end

	local y, col = 0, 0
	local rows
	local flowX, flowHeight = 0, 0
	local function EndRow()
		if col > 0 then y = y + ROW; col = 0 end
	end
	local function EndFlow()
		if flowX > 0 then y = y + flowHeight + 4; flowX = 0 end
	end
	local function Place(widget, x, w)
		widget:ClearAllPoints()
		widget:SetPoint("TOPLEFT", x, -y)
		if w then widget:SetWidth(w) end
		widget.layoutX, widget.layoutY = x, y
		widget:Show()
		if widget.refresh then widget.refresh() end
	end

	for _, section in ipairs(tab.sections) do
		local items = VisibleItems(section, filter, tab.page.title)
		-- Rare rows (less = true) fold under a link at the section's end,
		-- unless the player opened the fold or is searching.
		local folded, rare = 0, 0
		if not filter and not tab.single then
			local kept = {}
			for _, option in ipairs(items) do
				if option.less then rare = rare + 1 end
				if option.less and not section.unfolded then folded = folded + 1 else kept[#kept + 1] = option end
			end
			items = kept
		end
		local header = section.header and not IsHidden(section.header) and section.header
		local showHeader = header and (#items + folded > 0 or (not filter and #section.items == 0))
		-- A folded section shows its header only.
		local shut = showHeader and header.fold and not filter and Tree.IsFolded(tab, header)
		if shut then items, folded, rare = {}, 0, 0 end
		if showHeader then
			local widget = Widget(tab, header)
			Place(widget, 0, width)
			y = y + widget:GetHeight() + 4
		end
		rows = 0
		-- The card starts at the section's first row; a preview strip that
		-- comes before it stays above the card.
		local cardTop, card, lastStripe
		local function StartCard()
			if cardTop then return end
			cardTop = y
			card = SectionCard(tab, section)
			card.layoutY = y -- where the card starts on the page
			card:ClearAllPoints()
			card:SetPoint("TOPLEFT", 0, -y)
			card:SetWidth(width)
			card:Show()
		end
		for index, option in ipairs(items) do
			local widget = Widget(tab, option)
			if widget and not (widget.isPreview and not cardTop) then StartCard() end
			lastStripe = widget and widget.kind == "cell" and lastStripe or nil
			if widget and widget.kind == "cell" then
				EndFlow()
				-- A pair never starts in the right half.
				if col == 1 and not single and Tree.StartsPair(option, items[index + 1]) then
					local partner = Widget(tab, items[index + 1])
					if partner and partner.kind == "cell" then EndRow() end
				end
				if col == 0 then
					rows = rows + 1
					lastStripe = card:Stripe(rows, y - cardTop, ROW, rows % 2 == 1, half < width and half or nil)
				end
				if col == 0 then Place(widget, 0, half) else Place(widget, half, width - half) end
				col = col + 1
				if col == 2 or single then EndRow() end
			elseif widget and widget.kind == "flow" then
				EndRow()
				if flowX > 0 and flowX + widget:GetWidth() > width then EndFlow() end
				Place(widget, flowX)
				flowX = flowX + widget:GetWidth() + 4
				flowHeight = widget:GetHeight()
			elseif widget then
				EndRow(); EndFlow()
				if widget.Resize then widget:Resize(width) end
				Place(widget, 0, width)
				y = y + widget:GetHeight() + 4
			end
		end
		EndRow(); EndFlow()
		if rare > 0 then StartCard(); lastStripe = nil end
		if rare > 0 then
			local link = tab.foldLinks[section]
			if not link then
				link = TextLink(frame, "", function()
					section.unfolded = not section.unfolded
					ShowTab(tab.page and tab.page.currentTab, true)
				end)
				link.text:ClearAllPoints()
				link.text:SetPoint("LEFT", 4, 0)
				tab.foldLinks[section] = link
			end
			link.text:SetText(section.unfolded and L["Fewer settings"] or L["More settings (%d)"]:format(folded))
			link:SetWidth(math.ceil(link.text:GetStringWidth() + 8))
			link:ClearAllPoints()
			link:SetPoint("TOPLEFT", 8, -(y + 2))
			link:Show()
			y = y + 22
		end
		if card then
			card:HideStripes(rows + 1)
			-- The last row's divider would sit on the card's own edge.
			if lastStripe then lastStripe.line:Hide() end
			card:SetBodyHeight(y - cardTop)
		end
		if shut then
			y = y + 4
		elseif showHeader or #items > 0 then
			y = y + SECTION_GAP
		end
	end
	frame:SetHeight(math.max(y, 1))
	return y
end
Tree.LayoutTab = LayoutTab

local function ContentWidth()
	local width = window.scroll:GetWidth()
	if not width or width < 100 then width = Size.Width() - MAIN_LEFT - 32 end
	return math.floor(width)
end

local function SetScrollChild(frame)
	local scroll = window.scroll
	local old = scroll:GetScrollChild()
	if old and old ~= frame then old:Hide() end
	scroll:SetScrollChild(frame)
	frame:Show()
end

-- Show one tab of the current page. keepScroll keeps the scroll position
-- (after a change); focusOption scrolls to that row and flashes it.
---------------------------------------------------------------------------
-- Cog popup: a small panel with a row's rare settings, one row
-- per line, built with the same row widgets.
---------------------------------------------------------------------------
local cogPopup

local function CogPopup()
	if cogPopup then return cogPopup end
	-- The tool window shell (header, title, accent line, close X, Escape),
	-- opened beside its row: no drag, no grip, no slide.
	local frame = E.UIKit.CreateToolWindow("EldoUIConfigCog", { parent = window, width = COG_WIDTH, height = 120,
		strata = "FULLSCREEN_DIALOG", movable = false, resizable = false, slide = false, dialog = false })
	frame.tabs = {}   -- row option -> pseudo tab of its cog
	Snap(frame)
	cogPopup = frame
	return frame
end

local function LayoutCog()
	local frame = cogPopup
	local tab = frame.tab
	local pad = E.UIKit.TOOL_PAD
	tab.frame:SetWidth(COG_WIDTH - 2 * pad)
	local height = LayoutTab(tab, nil)
	frame:SetHeight(height + E.UIKit.TOOL_HEADER + 2 * pad)
end

-- Opens the cog of `option` next to its row; focusChild flashes one row.
OpenCog = function(cell, option, page, parentTab, focusChild)
	local frame = CogPopup()
	if frame:IsShown() and frame.option == option and not focusChild then
		frame:Hide()
		return
	end
	local tab = frame.tabs[option]
	if not tab then
		tab = { page = page, widgets = {}, sectionByHeader = {}, single = true,
			sections = { { items = page.cogItems[option] or {} } } }
		for _, child in ipairs(tab.sections[1].items) do
			if type(child.hidden) == "function" then tab.dynamic = true end
		end
		tab.frame = CreateFrame("Frame", nil, frame.content)
		tab.frame:SetPoint("TOPLEFT")
		frame.tabs[option] = tab
	end
	tab.copyFrom = parentTab and parentTab.copyFrom
	for _, other in pairs(frame.tabs) do other.frame:SetShown(other == tab) end
	frame.tab, frame.option, frame.cell = tab, option, cell
	frame:SetTitle(StripCodes(option.label))
	E:SetPanelTemplate(frame)
	Snap(frame)
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", cell, "BOTTOMRIGHT", 0, -2)
	frame:Show()
	LayoutCog()
	if focusChild then
		local widget = tab.widgets[focusChild]
		if widget and widget.Flash then widget.Flash() end
	end
end

-- After a change: refresh the open cog (re-lay it when its rows can
-- hide), or close it when its row was grayed or switched off.
RefreshCog = function()
	if not (cogPopup and cogPopup:IsShown()) then return end
	local cell = cogPopup.cell
	if not (cell and cell:IsVisible()) or GearBlocked(cell) then
		cogPopup:Hide()
		return
	end
	if cogPopup.tab.dynamic then LayoutCog() else RefreshTab(cogPopup.tab) end
end

local function HideCog()
	if cogPopup then cogPopup:Hide() end
end

---------------------------------------------------------------------------
-- A switched-off module shows its description and an Enable button
-- instead of its settings; "Edit settings anyway" opens them. A module
-- another addon does the job of (Core/AddonConflicts.lua) shows the
-- player's pick instead: Use EldoUI's or Keep <Addon>.
---------------------------------------------------------------------------
local function IsOffView(page)
	local module = page.module
	return module and (not module:IsEnabled() or E:GetModuleConflict(module) ~= nil) and not page.showOff
end

local function OffPanel()
	if window.offPanel then return window.offPanel end
	local panel = CreateFrame("Frame", nil, window.scroll)
	panel:SetSize(1, 260)
	panel.desc = Text(panel, E.tokens.size.cardTitle, "LEFT", TEXT)
	panel.desc:SetPoint("TOPLEFT", 4, -16)
	panel.desc:SetWordWrap(true)
	panel.state = Text(panel, E.tokens.size.body, "LEFT", SECONDARY)
	panel.state:SetPoint("TOPLEFT", panel.desc, "BOTTOMLEFT", 0, -16)
	panel.state:SetWordWrap(true)
	panel.enable = Button(panel, L["Turn on"], 200, BUTTON_LARGE, function()
		local module = currentPage and currentPage.module
		if not module then return end
		local conflict = E:GetModuleConflict(module)
		if conflict then
			E:ChooseEldoUI(conflict, module.name)
			E:RefreshConfig()
			return
		end
		E:SetModuleEnabled(module.name, true)
		-- Most modules start at once; one that can't joins the reload count.
		TrackModule(module)
		E:RefreshConfig()
	end, true)
	panel.enable:SetPoint("TOPLEFT", panel.state, "BOTTOMLEFT", 0, -20)
	panel.keep = Button(panel, L["Keep"], 200, BUTTON_LARGE, function()
		local module = currentPage and currentPage.module
		local conflict = module and E:GetModuleConflict(module)
		if not conflict then return end
		E:ChooseCompetitor(conflict, module.name)
		E:RefreshConfig()
	end)
	panel.keep:SetPoint("LEFT", panel.enable, "RIGHT", 8, 0)
	panel.anyway = Button(panel, L["Edit settings anyway"], 200, BUTTON_LARGE, function()
		if not currentPage then return end
		currentPage.showOff = true
		ShowTab(currentPage.currentTab or 1)
	end)
	panel.anyway:SetPoint("LEFT", panel.enable, "RIGHT", 8, 0)
	AddTooltip(panel.anyway, L["Edit settings anyway"], L["Change this module's settings while it is off. They apply when you turn it on."])
	Snap(panel)
	window.offPanel = panel
	return panel
end

local function ShowOffPanel(page)
	local module = page.module
	local panel = OffPanel()
	local width = ContentWidth()
	panel:SetWidth(width)
	panel.desc:SetWidth(width - 8)
	panel.state:SetWidth(width - 8)
	panel.desc:SetText(module.desc ~= "" and L[module.desc] or L[module.title])
	local addon, conflict = E:GetModuleConflict(module)
	local function Fit(button)
		button:SetWidth(math.max(200, math.ceil((button.text:GetStringWidth() + 32) / 4) * 4))
	end
	if conflict then
		-- The player picks who does the job: EldoUI (the other addon off
		-- after a reload) or the other addon. Keep shows once EldoUI was
		-- picked; until then it is what happens already.
		local picked = E:GetCompetitorChoice(addon, module.name) == "eldoui" or E:CompetitorDisabledNow(addon)
		local text = L["%s does this job, so EldoUI's %s stands back and the two never fight over the same frames."]:format(conflict, L[module.title])
		if E:CompetitorDisabledNow(addon) then
			text = text .. " " .. L["%s is off for this character after a reload."]:format(conflict)
		elseif picked then
			text = text .. " " .. L["You picked EldoUI, but %s is still on."]:format(conflict)
		end
		panel.state:SetText(Warn() .. text .. "|r")
		panel.enable.text:SetText(L["Use EldoUI's"])
		Fit(panel.enable)
		panel.enable:SetShown(not E:CompetitorDisabledNow(addon))
		panel.keep.text:SetText(L["Keep %s"]:format(conflict))
		Fit(panel.keep)
		panel.keep:SetShown(picked)
		panel.keep:ClearAllPoints()
		if panel.enable:IsShown() then
			panel.keep:SetPoint("LEFT", panel.enable, "RIGHT", 8, 0)
		else
			panel.keep:SetPoint("TOPLEFT", panel.state, "BOTTOMLEFT", 0, -20)
		end
		local last = panel.keep:IsShown() and panel.keep or panel.enable:IsShown() and panel.enable or nil
		panel.anyway:ClearAllPoints()
		if last then
			panel.anyway:SetPoint("LEFT", last, "RIGHT", 8, 0)
		else
			panel.anyway:SetPoint("TOPLEFT", panel.state, "BOTTOMLEFT", 0, -20)
		end
	else
		panel.keep:Hide()
		panel.state:SetText(L["%s is off. Blizzard's own version (if there is one) is used instead. Turn it on to use it and see its settings."]:format(L[module.title]))
		panel.enable.text:SetText(L["Turn on %s"]:format(L[module.title]))
		Fit(panel.enable)
		panel.enable:Show()
		panel.anyway:ClearAllPoints()
		panel.anyway:SetPoint("LEFT", panel.enable, "RIGHT", 8, 0)
	end
	SetScrollChild(panel)
	window.empty:Hide()
	window.pageSearch:Hide()
	window.scroll:UpdateScrollChildRect()
	window.scroll:SetVerticalScroll(0)
	UpdateTabBar()
end

-- What an empty tab says: the search found nothing, the tab's own
-- `empty` text (the tab row's field), or the switch its hidden rows wait
-- for, never a blank pane.
function Tree.EmptyText(tab, filter)
	if filter then return L["No settings match."] end
	local empty = tab.empty
	if type(empty) == "function" then empty = empty() end
	if type(empty) == "string" and empty ~= "" then return L[empty] end
	local page = tab.page
	for _, section in ipairs(tab.sections) do
		local lastOff
		for _, option in ipairs(section.items) do
			local parent = ParentKey(option) and page.optionsByKey[ParentKey(option)]
			if IsHidden(option) and (parent or lastOff) then
				return L["Nothing to set here yet. Turn on \"%s\" first."]:format(StripCodes((parent or lastOff).label))
			end
			local key = KeyOf(option)
			if option.type == "toggle" and type(key) == "string" and not IsHidden(option) and not GetPath(Tree.RootOf(page, option), key) then
				lastOff = option
			end
		end
	end
	return L["Nothing to set on this tab right now. Its settings show when the switch they need is on."]
end

-- For plugins: what an empty tab would say.
E.ConfigEmptyText = function(tab, filter) return Tree.EmptyText(tab, filter) end

ShowTab = function(index, keepScroll, focusOption)
	local page = currentPage
	-- A re-layout after a change keeps the open cog; a tab switch closes it.
	if not keepScroll then HideCog() end
	if IsOffView(page) then
		ShowOffPanel(page)
		return
	end
	window.pageSearch:Show()
	local tabs = Structure(page)
	index = math.max(1, math.min(index or 1, #tabs))
	page.currentTab = index
	local tab = tabs[index]
	local scroll = window.scroll
	local offset = keepScroll and scroll:GetVerticalScroll() or 0
	if not tab.frame then tab.frame = CreateFrame("Frame", nil, scroll) end
	tab.frame:SetWidth(ContentWidth())
	-- Opening a folded rare row (a search result) opens its fold.
	if focusOption and focusOption.less then
		for _, section in ipairs(tab.sections) do
			if tContains(section.items, focusOption) then section.unfolded = true end
		end
	end
	-- Opening a row of a folded section (or its header) opens the section.
	if focusOption then
		local row = page.cogParent and page.cogParent[focusOption] or focusOption
		for _, section in ipairs(tab.sections) do
			local header = section.header
			if header and header.fold and (header == row or tContains(section.items, row)) and Tree.IsFolded(tab, header) then
				Tree.SetFolded(tab, header, false)
			end
		end
	end
	local height = LayoutTab(tab, pageFilter)
	SetScrollChild(tab.frame)
	if height <= 1 then window.empty:SetText(Tree.EmptyText(tab, pageFilter)) end
	window.empty:SetShown(height <= 1)
	if focusOption then
		local widget = tab.widgets[focusOption]
		if widget and widget:IsShown() then
			offset = math.max(0, widget.layoutY - 40)
			if widget.Flash then widget.Flash() end
		end
	end
	scroll:UpdateScrollChildRect()
	scroll:SetVerticalScroll(math.min(offset, math.max(0, height - scroll:GetHeight())))
	UpdateTabBar()
	UpdateNav()
end

---------------------------------------------------------------------------
-- Tab bar: flat tabs, gray text, the active one in accent text with a
-- 2-px accent underline. On a hub page (DESIGN.md §3b) the top row holds
-- the hub's pages and the open page's own tabs show as a second, smaller
-- row (accent text when active, no underline). The page search and the
-- Share menu sit at the right end of the first line.
-- bar.buttons are always the open page's own tabs, by tab index;
-- bar.hubButtons the hub's pages.
---------------------------------------------------------------------------
local function TabButton(index, pool)
	local bar = window.tabBar
	pool = pool or "buttons"
	bar[pool] = bar[pool] or {}
	local button = bar[pool][index]
	if button then return button end
	button = CreateFrame("Button", nil, bar)
	button:SetHeight(E.tokens.height.tab)
	button.text = Text(button, E.tokens.size.body, "CENTER", SECONDARY)
	button.text:SetPoint("CENTER", 0, 1)
	button.underline = button:CreateTexture(nil, "OVERLAY")
	E:Hairline(button.underline, "h", 2)
	button.underline:SetPoint("BOTTOMLEFT", 4, 0)
	button.underline:SetPoint("BOTTOMRIGHT", -4, 0)
	-- Hover and pressed fill the whole tab, which is its hit rect.
	E:SkinHoverPress(button)
	bar[pool][index] = button
	return button
end

Tree.TAB_ROW = 26       -- one line of tabs (24 px tab and a 2 px gap)
Tree.SUB_TAB = 20       -- a tab of the second, smaller row
Tree.SUB_ROW = 22       -- one line of that row (20 px tab and a 2 px gap)
Tree.SHARE = 76         -- width of the Share menu button
Tree.PAGE_SEARCH = 188  -- room the page search takes on the first line (Share comes on top)

-- kind "top": a tab of the main row; "sub": the smaller second row.
function Tree.StyleTab(button, kind, active)
	local size = kind == "sub" and E.tokens.size.label or E.tokens.size.body
	local info = texts[button.text]
	if info and info.size ~= size then
		info.size = size
		ApplyTextFont(button.text, info)
	end
	button.kind = kind
	button:SetHeight(kind == "sub" and Tree.SUB_TAB or 24)
	if active then button.text:SetTextColor(E:TokenColor("accent")) else button.text:SetTextColor(unpack(SECONDARY)) end
	button.underline:SetColorTexture(Accent())
	button.underline:SetShown(active and kind ~= "sub")
	button.active = active
end

-- The tabs of the open page in the order the bar shows them: the hub's
-- pages, with the open one's own tabs in its place (the order Left and
-- Right walk).
function Tree.TabSteps(page)
	local steps = {}
	local hub = Tree.HubOf(page)
	local list = hub and Tree.HubPages(hub.key) or { page }
	for _, member in ipairs(list) do
		if member == page and page.hasTabs and not IsOffView(page) then
			for index in ipairs(Structure(page)) do steps[#steps + 1] = { page = page, tab = index } end
		else
			steps[#steps + 1] = { page = member }
		end
	end
	return steps
end

UpdateTabBar = function()
	local bar = window.tabBar
	for _, pool in ipairs({ "buttons", "hubButtons" }) do
		for _, button in ipairs(bar[pool] or {}) do button:Hide() end
	end
	local page = currentPage
	if searching or not page then
		bar:SetHeight(E.tokens.height.tab)
		return
	end
	local hub = Tree.HubOf(page)
	local members = hub and Tree.HubPages(hub.key) or nil
	if members and #members < 2 then members = nil end
	local ownTabs = page.hasTabs and not IsOffView(page)
	if not (members or ownTabs) then
		bar:SetHeight(E.tokens.height.tab)
		return
	end
	local width = bar:GetWidth()
	if not width or width < 100 then width = Size.Width() - MAIN_LEFT - 8 end
	local searchRoom = Tree.PAGE_SEARCH + (window.share and window.share:GetWidth() or Tree.SHARE) + 6
	-- Lays out one row of tabs from `top` down, wrapping instead of
	-- overflowing; returns the lines it used and their height.
	local function Row(list, kind, top, firstRoom)
		local x, line = 0, 0
		local lineHeight = kind == "sub" and Tree.SUB_ROW or Tree.TAB_ROW
		for _, button in ipairs(list) do
			button:SetWidth(math.ceil((button.text:GetStringWidth() + (kind == "sub" and 16 or 24)) / 4) * 4)
			local room = width - (line == 0 and firstRoom or 0)
			if x > 0 and x + button:GetWidth() > room then
				line, x = line + 1, 0
			end
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", x, -(top + line * lineHeight))
			x = x + button:GetWidth() + 4
			button:Show()
		end
		return line + 1, lineHeight
	end
	local height = 0
	if members then
		local list = {}
		for index, member in ipairs(members) do
			local button = TabButton(index, "hubButtons")
			button.text:SetText(member.title)
			Tree.StyleTab(button, "top", member == page)
			button.hubPage = member
			button:SetScript("OnClick", function(self)
				PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
				if self.hubPage ~= currentPage then ShowPage(self.hubPage) end
			end)
			list[#list + 1] = button
		end
		height = Row(list, "top", 0, searchRoom) * Tree.TAB_ROW
	end
	if ownTabs then
		local kind = members and "sub" or "top"
		local list = {}
		for index, tab in ipairs(Structure(page)) do
			local button = TabButton(index)
			local label = tab.label
			if pageFilter then label = ("%s (%d)"):format(label, CountMatches(tab, pageFilter)) end
			button.text:SetText(label)
			Tree.StyleTab(button, kind, index == page.currentTab)
			button:SetScript("OnClick", function()
				PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
				ShowTab(index)
			end)
			list[#list + 1] = button
		end
		local lines, lineHeight = Row(list, kind, height, members and 0 or searchRoom)
		height = height + lines * lineHeight
	end
	bar:SetHeight(math.max(24, height - 2))
end

-- Left and Right: the tab before or after the open one, through the hub's
-- pages and their tabs in the order the bar shows them.
function Tree.StepTab(delta)
	local page = currentPage
	if searching or not page then return false end
	local steps = Tree.TabSteps(page)
	local at
	for index, step in ipairs(steps) do
		if step.page == page and (step.tab == nil or step.tab == page.currentTab) then at = index break end
	end
	local step = at and steps[at + delta]
	if not step then return at ~= nil and #steps > 1 end
	PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
	if step.page ~= page then
		-- Into the next page from its near end: its first tab going right,
		-- its last going left.
		local tab = delta < 0 and step.page.tabs and #step.page.tabs or 1
		ShowPage(step.page, step.page.hasTabs and math.max(1, tab) or nil)
	else
		ShowTab(step.tab)
	end
	return true
end

---------------------------------------------------------------------------
-- Share menu: the kit menu, like every other list of the window. It opens
-- from the small Share button next to the page search.
---------------------------------------------------------------------------
local shareAnchor

HideShareMenu = function()
	local menu = E.UIKit.GetMenu()
	if shareAnchor and menu and menu:IsShown() and menu.owner == shareAnchor then E.UIKit.CloseMenu() end
end

-- Copy one module's settings (and its frames' positions) from another
-- profile into this one, after asking.
function Tree.CopyModuleFrom(module, from)
	local title = L[module.title]
	E:ConfigConfirm(L["Copy the %s settings from the profile %s into %s? Your other settings stay as they are."]:format(
		title, E:Highlight(from), E:Highlight(E.profileName)), function()
		E:RunOutOfCombat(function()
			local ok = E:CopyProfileParts(from, { modules = { [module.name] = true }, positions = true })
			if ok then
				E:Print(L["Copied %s from %s."]:format(title, from))
				-- Parts a module sets up once at login take the copy after a reload.
				E:ConfigNeedsReload("copy:" .. module.name, L["%s copied from %s"]:format(title, from))
			end
			E:RefreshConfig()
		end)
	end, { title = L["Copy from profile"], accept = L["Copy"] })
end

-- The other profiles, as a submenu of Share.
function Tree.CopyFromItems(module)
	local items = {}
	for _, name in ipairs(E:GetProfileList()) do
		if name ~= E.profileName then
			items[#items + 1] = { text = name, func = function() Tree.CopyModuleFrom(module, name) end }
		end
	end
	if #items == 0 then
		items[1] = { text = L["No other profile yet"], disabled = true }
	end
	return items
end

-- The Share menu and the quick actions.
local Actions = {}

function Actions.ShareItems(page)
	local key = ExportKey(page)
	local items = {
		{ text = key == "all" and L["Export this (whole profile)"] or L["Export this"], func = function() E:ShowExport(key) end },
		{ text = L["Import..."], func = function() E:ShowImport() end },
		{ text = L["Export everything"], func = function() E:ShowExport("all") end },
		-- The look (layout, skin, accent, styles) as a preset pack string.
		{ text = L["Export my look as a pack"], func = function() E:ShowExport("share:pack") end },
	}
	if page.module then
		local module = page.module
		table.insert(items, { text = L["Copy from profile"], menu = function() return Tree.CopyFromItems(module) end,
			tooltip = L["Copy this module's settings and frame positions from another of your profiles."] })
		-- Red means danger (DESIGN.md color meaning).
		table.insert(items, { divider = true })
		table.insert(items, { text = L["Reset to defaults"], danger = true, func = function() Bulk.ConfirmReset(page.module) end })
	end
	return items
end
E.ConfigShareItems = function(page) return Actions.ShareItems(page or currentPage) end -- exposed for inspection

function Actions.ShowShareMenu(anchor)
	shareAnchor = anchor
	E.UIKit.OpenMenu(anchor, Actions.ShareItems(currentPage), { width = 200, align = "right" })
end

---------------------------------------------------------------------------
-- Sidebar
---------------------------------------------------------------------------
function Actions.ToggleMoveMode()
	E:ToggleMoveMode()
end

-- Move mode starts (Core/Movers.lua): the window gets out of the way so
-- frames can be dragged. Returns the page it showed, to come back to.
function E:CloseConfigForMoveMode()
	if not (window and window:IsShown()) then return nil end
	local page = currentPage and currentPage.id
	window.quietHide = true   -- no reload question on the way to move mode
	window:Hide()
	return page
end

-- Move mode ended with Done (or the Move mode button): the window it hid
-- comes back as it was, on the same page, with fresh values. Only a window
-- move mode hid itself is shown again; nothing else opens it.
function E:ReopenConfigAfterMoveMode()
	if not window or window:IsShown() then return false end
	window:Show()
	self:RefreshConfig()
	return true
end

function Actions.ToggleKeybindMode()
	if E.ToggleKeybindMode then E:ToggleKeybindMode() end
end

-- The error log has its own window (Core/ErrorWindow.lua), with or
-- without the Chat module.
function Actions.OpenErrors()
	if E.ToggleErrorWindow then E:ToggleErrorWindow(true) end
end

-- Quick actions (DESIGN.md §3b): one icon row each at the top of the
-- sidebar, above the search and outside the scroll list. Keybind mode runs
-- at once; Global settings and Profiles open their hubs (their only sidebar
-- rows). Move mode is the footer button next to Reload UI. The names are
-- shown translated: L["Keybind mode"], L["Global settings"], L["Profiles"]
Tree.QUICK = {
	{ key = "keys", label = "Keybind mode", glyph = "keybind", run = Actions.ToggleKeybindMode,
		tip = "Point at an action button and press a key to bind it." },
	{ key = "global", label = "Global settings", glyph = "gear", hub = "global",
		tip = "Accent, panels, fonts, textures and the other settings for the whole UI." },
	{ key = "profiles", label = "Profiles", glyph = "profile", hub = "profiles",
		tip = "Switch, copy or reset the profile this character uses, and import or export a setup." },
}

-- The rows the sidebar shows above the search, in order, for the layout,
-- Up / Down and the repaint.
function Tree.LayoutQuick()
	if not (window and window.quickAll) then return end
	local shown = {}
	for _, row in ipairs(window.quickAll) do
		row:Show()
		shown[#shown + 1] = row
	end
	for index, row in ipairs(shown) do
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 8, -(Tree.QUICK_TOP + (index - 1) * (Tree.ROW + Tree.GAP)))
	end
	window.quick = shown
	local searchTop = Tree.QUICK_TOP + #shown * (Tree.ROW + Tree.GAP) + 6
	if window.search then
		window.search:ClearAllPoints()
		window.search:SetPoint("TOPLEFT", 16, -searchTop)
	end
	if window.nav and window.nav.scroll then
		window.nav.scroll:SetPoint("TOPLEFT", 8, -(searchTop + 32))
	end
end
Tree.QUICK_TOP = 60

-- Is the open page in this hub?
function Tree.InHub(key)
	local hub = not searching and Tree.HubOf(currentPage)
	return hub and hub.key == key or false
end

-- Search hits of a hub: the sum over its pages, nil when none.
function Tree.HubHits(key)
	if not Tree.hits then return nil end
	local total = 0
	for _, page in ipairs(Tree.HubPages(key)) do
		local hits = Tree.hits[page]
		if hits then total = total + hits.total end
	end
	return total > 0 and { total = total } or nil
end

-- Sidebar rows ease into a new selection and hover color (E.UIKit
-- soft changes, over motion.hover; at once with Animations off).
function Tree.SoftNav(row, selected, ident)
	E.WindowKit.SoftNavRow(row, selected, ident)
end

function Tree.SoftColor(region, r, g, b)
	if region.SetTextColor then
		E.UIKit.FadeTextColor(region, r, g, b)
	else
		E.UIKit.FadeVertexColor(region, r, g, b)
	end
end

function Tree.PaintQuick(row)
	local selected = row.hubKey and Tree.InHub(row.hubKey)
	Tree.SoftNav(row, selected, row.key)
	local hits = row.hubKey and Tree.HubHits(row.hubKey)
	row.text:SetText(hits and ("%s (%d)"):format(row.label, hits.total) or row.label)
	local text, glyph
	if Tree.hits and row.hubKey and not hits then
		text, glyph = DIM, DIM
	elseif selected or row.hover then
		text, glyph = Tree.WHITE, Tree.WHITE
	else
		text, glyph = TEXT, SECONDARY
	end
	Tree.SoftColor(row.text, text[1], text[2], text[3])
	Tree.SoftColor(row.glyph, glyph[1], glyph[2], glyph[3])
end
Tree.WHITE = { 1, 1, 1 }

function Tree.QuickRow(parent, spec)
	local row = E.WindowKit.NavRow(parent, NAV_WIDTH, Tree.ROW)
	row.key, row.hubKey, row.run, row.label = spec.key, spec.hub, spec.run, L[spec.label]
	row.glyph = row:CreateTexture(nil, "OVERLAY")
	row.glyph:SetSize(14, 14)
	row.glyph:SetPoint("LEFT", 8, 0)
	E.UIKit.SetGlyph(row.glyph, spec.glyph)
	row.text = Text(row, E.tokens.size.body, "LEFT", TEXT)
	row.text:SetPoint("LEFT", row.glyph, "RIGHT", 8, 0)
	row.text:SetPoint("RIGHT", -8, 0)
	row.text:SetText(L[spec.label])
	row:HookScript("OnEnter", function(self)
		self.hover = true
		Tree.PaintQuick(self)
		local Kit = E.UIKit
		Kit.AnchorTooltip(self)
		Kit.TipTitle(GameTooltip, L[spec.label])
		Kit.TipText(GameTooltip, L[spec.tip])
		GameTooltip:Show()
	end)
	row:HookScript("OnLeave", function(self)
		self.hover = false
		Tree.PaintQuick(self)
		GameTooltip_Hide()
	end)
	row:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		if self.run then
			self.run()
		elseif self.hubKey then
			Tree.OpenHub(self.hubKey)
		end
	end)
	Snap(row)
	Tree.PaintQuick(row)
	return row
end

-- Open a registered page by its id (a quick action, a foot link).
function Tree.OpenPage(id)
	for _, page in ipairs(pages) do
		if page.id == id then
			page.showOff = nil
			ShowPage(page)
			return true
		end
	end
	return false
end

-- Sidebar foot: What's New, Errors and Thanks as small links (Errors with
-- the count of new errors in the warning color; Thanks only while the
-- Thanks page has names), then the version line with memory (and CPU
-- while the game's profiling is on).
Tree.FOOT = 50      -- height of the sidebar foot with one row of links
Tree.FOOT_ROW = 20  -- each further row of links

function Tree.PaintLink(link)
	if link.selected then
		Tree.SoftColor(link.text, E:TokenColor("accent"))
	elseif link.hover then
		Tree.SoftColor(link.text, 1, 1, 1)
	else
		Tree.SoftColor(link.text, unpack(SECONDARY))
	end
end

function Tree.FootLink(parent, onClick, tipTitle, tip)
	local link = CreateFrame("Button", nil, parent)
	link:SetHeight(20)
	link.text = Text(link, E.tokens.size.small, "LEFT", SECONDARY)
	link.text:SetPoint("LEFT", 4, 0)
	link.text:SetWordWrap(false)
	E:SkinHoverPress(link)
	link:HookScript("OnEnter", function(self) self.hover = true Tree.PaintLink(self) end)
	link:HookScript("OnLeave", function(self) self.hover = false Tree.PaintLink(self) end)
	link:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		onClick()
	end)
	AddTooltip(link, tipTitle, tip)
	return link
end

function Tree.Foot(sidebar)
	local foot = CreateFrame("Frame", nil, sidebar)
	foot:SetPoint("BOTTOMLEFT", 8, 4)
	foot:SetPoint("BOTTOMRIGHT", -8, 4)
	foot:SetHeight(Tree.FOOT)
	local line = foot:CreateTexture(nil, "ARTWORK")
	E:Hairline(line, "h", 1)
	line:SetColorTexture(unpack(E.tokens.edge.divider))
	line:SetPoint("TOPLEFT", 4, 0)
	line:SetPoint("TOPRIGHT", -4, 0)
	foot.whatsnew = Tree.FootLink(foot, function() Tree.OpenPage("whatsnew") end,
		L["What's new"], L["What changed in each EldoUI version."])
	foot.whatsnew:SetPoint("TOPLEFT", 0, -4)
	foot.errors = Tree.FootLink(foot, Actions.OpenErrors, L["Errors"],
		L["The error log: what went wrong in EldoUI, with a copy button for a report."])
	foot.errors:SetPoint("LEFT", foot.whatsnew, "RIGHT", 8, 0)
	foot.thanks = Tree.FootLink(foot, function() Tree.OpenPage("thanks") end,
		L["Thanks"], L["The people who made EldoUI possible."])
	foot.thanks:SetPoint("LEFT", foot.errors, "RIGHT", 8, 0)
	foot.thanks:Hide()
	-- Pointing at the version line measures again.
	local statsArea = CreateFrame("Frame", nil, foot)
	statsArea:SetPoint("BOTTOMLEFT", 0, 2)
	statsArea:SetPoint("BOTTOMRIGHT", 0, 2)
	statsArea:SetHeight(20)
	statsArea:EnableMouse(true)
	foot.stats = Text(statsArea, E.tokens.size.small, "LEFT", SECONDARY)
	foot.stats:SetPoint("LEFT", 4, 0)
	foot.stats:SetPoint("RIGHT", -4, 0)
	foot.stats:SetWordWrap(false)
	statsArea:SetScript("OnEnter", function() Tree.UpdateStats() end)
	AddTooltip(statsArea, L["EldoUI version and memory"], L["The memory EldoUI uses right now. It is measured when this window opens and each time you point at this line."])
	foot.Update = function()
		foot.whatsnew.text:SetText(L["What's new"])
		foot.whatsnew.selected = not searching and currentPage ~= nil and currentPage.id == "whatsnew"
		-- New errors since the log was last opened show as a count.
		local unseen = E.errors and tonumber(E.errors.unseen) or 0
		foot.errors.text:SetText(unseen > 0 and E:StatusText("warn", ("%s (%d)"):format(L["Errors"], unseen)) or L["Errors"])
		foot.thanks.text:SetText(L["Thanks"])
		foot.thanks.selected = not searching and currentPage ~= nil and currentPage.id == "thanks"
		foot.thanks:SetShown(Tree.ThanksCount() > 0)
		-- The links flow in rows as wide as the foot: a link that would run
		-- past its edge (Large text, a long count) starts the next row, and
		-- the foot grows by that row; the sidebar list ends above it.
		local room = foot:GetWidth()
		if not room or room <= 0 then room = math.huge end
		local x, row = 0, 0
		for _, link in ipairs({ foot.whatsnew, foot.errors, foot.thanks }) do
			link:SetWidth(math.ceil(link.text:GetStringWidth() + 8))
			Tree.PaintLink(link)
			if link:IsShown() then
				if x > 0 and x + link:GetWidth() > room then x, row = 0, row + 1 end
				link:ClearAllPoints()
				link:SetPoint("TOPLEFT", x, -4 - row * Tree.FOOT_ROW)
				x = x + link:GetWidth() + 8
			end
		end
		foot:SetHeight(Tree.FOOT + row * Tree.FOOT_ROW)
	end
	return foot
end

-- The module's power switch (E.UIKit.Switch, small): accent when on,
-- fainter than off while another addon holds the module's job.
local function PaintPower(power, module)
	power.blocked = E:GetModuleConflict(module) and true or false
	power:SetChecked(module:IsEnabled())
end

local function CreatePower(button)
	-- A 12 px tall switch: the kit pads its hit rect to 20 px, inside its
	-- 24 px row.
	local power = E.UIKit.Switch(button, { size = "small" })
	power:SetPoint("RIGHT", -4, 0)
	local function ShowTip(self)
		local module = button.module
		if not module then return end
		E.UIKit.AnchorTooltip(self, GameTooltip)
		E.UIKit.TipTitle(GameTooltip, L[module.title])
		local _, conflict = E:GetModuleConflict(module)
		if conflict then
			GameTooltip:AddLine(L["Handled by %s."]:format(conflict), WARN_RGB[1], WARN_RGB[2], WARN_RGB[3], true)
			E:TooltipHint(GameTooltip, { L["Click"], L["choose on the Other addons page"] })
		else
			E.UIKit.TipText(GameTooltip, module:IsEnabled() and L["On."] or L["Off."])
			E:TooltipHint(GameTooltip, { L["Click"], module:IsEnabled() and L["switch it off"] or L["switch it on"] })
		end
		if E:ModuleFailed(module) then
			GameTooltip:AddLine(E:StatusText("warn", L["Part of this module failed to load."]), nil, nil, nil, true)
		end
		GameTooltip:Show()
	end
	power:SetScript("OnClick", function(self)
		local module = button.module
		if not module then return end
		-- Another addon does this module's job: the switch opens the
		-- Other addons page, where the player picks.
		if E:GetModuleConflict(module) then
			PaintPower(self, module)
			E:ToggleConfig("addons", true)
			return
		end
		local on = not module:IsEnabled()
		PlaySound(on and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		E:SetModuleEnabled(module.name, on)
		-- Switching off waits for a reload (Reload UI counts it); on works at once.
		TrackModule(module)
		E:RefreshConfig()
		if GameTooltip:IsOwned(self) then ShowTip(self) end
	end)
	power:HookScript("OnEnter", ShowTip)
	power:HookScript("OnLeave", GameTooltip_Hide)
	return power
end

---------------------------------------------------------------------------
-- Sidebar (DESIGN.md §0b and 3b): one row per hub (its general pages are
-- the tabs of the hub page), then the module groups as folding sections
-- with one row per module and its power switch. A page's tabs live only at
-- the top of the page, never as rows here. A section header shows its name
-- and how many rows it holds; clicking it folds or unfolds it. A section
-- opens while it holds the open page, unless the player folded it; what the
-- player opens or folds by hand is saved for the account. While the global
-- search shows results, every section with a match unfolds, and its pages
-- and the hubs show counts.
---------------------------------------------------------------------------
Tree.ROW = 24        -- height of a page row
Tree.PAGE_TITLE = E.tokens.size.pageTitle -- page title size: a step above window titles
Tree.HEADER = 26     -- height of a section header
Tree.GAP = 2         -- space under a page row
Tree.TEXT = 12       -- left edge of a page row's text (indented under its header)
Tree.hits = nil       -- page -> { total = n, tabs = { [index] = n } } while searching

function Tree.PaintGlow()
	-- The installer's header has the same glow (E.WindowKit).
	if window and window.headerGlow then E.WindowKit.PaintHeaderGlow(window.headerGlow) end
end

function Tree.Expanded()
	local db = WindowDB()
	if type(db.expanded) ~= "table" then db.expanded = {} end
	return db.expanded
end

-- A section's saved state lives next to the old page keys, under its own
-- prefix, so a profile from before keeps working.
function Tree.SectionKey(section)
	return "section:" .. section.key
end

-- Open: while the search found something in it, when the player opened it
-- (saved as true), or while it holds the open page and was not folded by
-- hand (saved as false).
function Tree.IsOpen(section)
	if Tree.hits then
		for _, page in ipairs(section.pages) do
			if Tree.hits[page] then return true end
		end
		return false
	end
	local state = Tree.Expanded()[Tree.SectionKey(section)]
	if state ~= nil then return state end
	return currentPage ~= nil and tContains(section.pages, currentPage)
end

function Tree.ToggleSection(section)
	local key = Tree.SectionKey(section)
	local open = not Tree.IsOpen(section)
	-- The section of the open page opens by itself, so only "folded" is
	-- worth saving there; any other section is folded unless saved open.
	local state
	if tContains(section.pages, currentPage) then
		if not open then state = false end
	elseif open then
		state = true
	end
	Tree.Expanded()[key] = state
	BuildNav()
end

-- Borderless rows. Selected entry: a 2 px accent bar on
-- the left and an accent tint fading to the right, white text. Hover: the
-- hover overlay only. A switched-off module is dimmed.
local function PaintNav(button)
	local selected = not searching and ((button.page and button.page == currentPage)
		or (button.hub and Tree.InHub(button.hub.key)))
	local dim = button.module and not button.module:IsEnabled()
	if Tree.hits and button.page and not Tree.hits[button.page] then dim = true end
	if Tree.hits and button.hub and not Tree.HubHits(button.hub.key) then dim = true end
	-- The installer's steps are the same rows (E.WindowKit.NavRow). A row
	-- the list reuses for another page takes its look at once.
	local ident = button.page or button.hub
	local reused = button.kitSoftIdent ~= ident
	Tree.SoftNav(button, selected, ident)
	local r, g, b
	if selected then
		r, g, b = 1, 1, 1
	elseif dim then
		r, g, b = DIM[1], DIM[2], DIM[3]
	elseif Tree.hits and (button.page or button.hub) then
		r, g, b = E:TokenColor("accent")
	else
		r, g, b = unpack(TEXT)
	end
	if reused then
		E.UIKit.StopEase(button.text)
		button.text:SetTextColor(r, g, b)
	else
		Tree.SoftColor(button.text, r, g, b)
	end
	if button.module then
		button.power:Show()
		PaintPower(button.power, button.module)
	else
		button.power:Hide()
	end
end

-- A section header: the name in the accent, the count muted on the right,
-- the chevron white while the mouse is on it.
function Tree.PaintHeader(header)
	local open = header.section and Tree.IsOpen(header.section)
	header.label:SetTextColor(E:TokenColor("accent"))
	header.count:SetTextColor(unpack(SECONDARY))
	header.chevron:SetRotation(open and 0 or math.pi / 2)
	local c = header.hover and Tree.WHITE or SECONDARY
	Tree.SoftColor(header.chevron, c[1], c[2], c[3])
end

-- A sidebar row's tooltip: the full page name and its summary when
-- the name is cut, and a module's failure.
function Tree.RowTooltip(button)
	local page = button.page or (button.hub and { title = button.hub.title })
	if not page then return end
	local failed = button.module and E:ModuleFailed(button.module)
	if not (failed or button.text:IsTruncated()) then return end
	local Kit = E.UIKit
	Kit.AnchorTooltip(button)
	Kit.TipTitle(GameTooltip, page.title)
	Kit.TipText(GameTooltip, E:Translate(page.desc))
	if failed then
		GameTooltip:AddLine(E:StatusText("warn", L["Part of this module failed to load."]), nil, nil, nil, true)
	end
	GameTooltip:Show()
end

local function NavButton(index)
	local nav = window.nav
	local button = nav.buttons[index]
	if button then return button end
	-- Borderless row with its bar, tint and hover: the installer's too.
	button = E.WindowKit.NavRow(nav.content, NAV_WIDTH, Tree.ROW)
	button.text = Text(button, E.tokens.size.body, "LEFT", TEXT)
	button.text:SetPoint("LEFT", Tree.TEXT, 0)
	button.text:SetWordWrap(true)
	button.text:SetMaxLines(2)
	button.power = CreatePower(button)
	button:HookScript("OnEnter", function(self) self.hover = true; PaintNav(self); Tree.RowTooltip(self) end)
	button:HookScript("OnLeave", function(self) self.hover = false; PaintNav(self); GameTooltip_Hide() end)
	button:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		if self.page then
			-- A switched-off module opens on its Turn on page again.
			self.page.showOff = nil
			ShowPage(self.page)
		elseif self.hub then
			Tree.OpenHub(self.hub.key)
		end
	end)
	Snap(button)
	nav.buttons[index] = button
	return button
end

-- A section header's name gets the room left of its count, on up to two
-- lines; the row grows with it. Returns the row's height.
function Tree.FitSectionHeader(header)
	local room = NAV_WIDTH - 16 - 6 - 6 - math.ceil(header.count:GetStringWidth() or 0)
	header.label:SetWidth(math.max(room, 1))
	local height = math.max(Tree.HEADER, math.ceil(header.label:GetStringHeight() or 0) + 10)
	header:SetHeight(height)
	return height
end

-- A section header row: chevron, name, count. The whole row is its hit
-- rect; clicking it folds or unfolds the section and opens nothing.
function Tree.Header(index)
	local nav = window.nav
	local header = nav.headers[index]
	if header then return header end
	header = CreateFrame("Button", nil, nav.content)
	header:SetSize(NAV_WIDTH, Tree.HEADER)
	header.chevron = header:CreateTexture(nil, "OVERLAY")
	header.chevron:SetTexture(CHEVRON)
	header.chevron:SetSize(10, 10)
	header.chevron:SetPoint("LEFT", 2, 0)
	header.count = Text(header, E.tokens.size.small, "RIGHT", SECONDARY)
	header.count:SetPoint("RIGHT", -6, 0)
	-- The name wraps to a second line rather than being cut (Large text);
	-- Tree.FitSectionHeader gives it its width and the row its height.
	header.label = Text(header, E.tokens.size.small, "LEFT", SECONDARY)
	header.label:SetPoint("LEFT", 16, 0)
	header.label:SetWordWrap(true)
	if header.label.SetMaxLines then header.label:SetMaxLines(2) end
	header:SetScript("OnEnter", function(self)
		self.hover = true
		Tree.PaintHeader(self)
		E.UIKit.AnchorTooltip(self, GameTooltip)
		E.UIKit.TipTitle(GameTooltip, self.title or "")
		E.UIKit.TipText(GameTooltip, self.section and Tree.IsOpen(self.section) and L["Fold this group."] or L["Show this group."])
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", function(self)
		self.hover = false
		Tree.PaintHeader(self)
		GameTooltip_Hide()
	end)
	E:SkinHoverPress(header)
	header:SetScript("OnClick", function(self)
		if not self.section or Tree.hits then return end
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Tree.ToggleSection(self.section)
	end)
	nav.headers[index] = header
	-- The audit reads the names the sidebar shows.
	nav.captions[index] = header.label
	return header
end

-- The config window follows the skin by default, like the installer
-- and every other EldoUI window; a fixed style such as
-- Classic stone stays a choice.
E.defaults.general.configStyle = "Follow"

local function SkinWindow()
	if not window then return end
	-- A window: the light window edge under Modern.
	if not E:IsWindowEdge(window) then E:SetWindowEdge(window) end
	local style = E.db.general.configStyle
	if style == "Follow" or not E.artStyles[style] then
		E:SetPanelTemplate(window)
		return
	end
	E:SetPanelTemplate(window)
	E.panels[window] = nil
	E.artStyles[style](window)
end

-- Module categories and their groups.
local Category = {}

-- Sidebar groups for module pages, in this order. A module names its group
-- with `category` in E:NewModule; built-in modules are listed here.
E.moduleCategories = { "Interface", "Combat", "Group", "Chat & Social", "Items & Economy", "Quality of Life", "Plugins" }
-- The names are keys: modules and plugins pass them as `category`, so they
-- never change. What the player reads is E:CategoryTitle(key), which spells
-- out "and" (DESIGN.md §4). Shown translated: L["Interface"],
-- L["Combat"], L["Group"], L["Chat and Social"], L["Items and Economy"],
-- L["Quality of Life"], L["Plugins"]
E.categoryTitles = { ["Chat & Social"] = "Chat and Social", ["Items & Economy"] = "Items and Economy" }
-- A plugin may also write the title as its category: it lands in the same group.
Category.CATEGORY_KEYS = {}
for key, title in pairs(E.categoryTitles) do Category.CATEGORY_KEYS[title] = key end

-- The category's name as the player reads it, translated.
function E:CategoryTitle(key)
	return L[self.categoryTitles[key] or key]
end
-- Every built-in module is listed, also the ones that set `category`
-- themselves, so a module addon after the split lands in the same group
-- even if its NewModule call leaves `category` out.
Category.DEFAULT_CATEGORY = {
	-- Interface
	InfoBar = "Interface", Minimap = "Interface", Maps = "Interface", Tooltip = "Interface",
	Character = "Interface", Loot = "Interface", Reminders = "Interface", Counters = "Interface",
	Setups = "Interface", StatusBars = "Interface", MicroMenu = "Interface", ObjectiveTracker = "Interface",
	Notifications = "Interface", AFK = "Interface", SystemUI = "Interface", EditMode = "Interface",
	Integrations = "Interface", DBM = "Interface", Fanfare = "Interface", Skins = "Interface", NPCWindows = "Interface",
	-- Combat
	UnitFrames = "Combat", ActionBars = "Combat", Nameplates = "Combat", Alerts = "Combat",
	EnemySpotter = "Combat", CombatHUD = "Combat", CooldownManager = "Combat", Auras = "Combat",
	ClassPower = "Combat", PetCare = "Combat", AuraGroups = "Combat", Quickdraw = "Combat",
	CombatText = "Combat", CastFX = "Combat", Battlegrounds = "Combat", CooldownPulse = "Combat", TrackingBars = "Combat",
	ConsumableBar = "Combat", EncounterTimeline = "Combat", ShamanTotems = "Combat", ClassBar = "Combat",
	-- Group
	GroupFrames = "Group", ClickCast = "Group", RaidTools = "Group", Instances = "Group",
	DungeonRoutes = "Group", RaidLoot = "Group",
	-- Chat & Social (friends, guild and group finder sit with chat)
	Chat = "Chat & Social", Messages = "Chat & Social", ChatBubbles = "Chat & Social",
	Social = "Chat & Social", PlayerNotes = "Chat & Social",
	Streamer = "Chat & Social", ChatInput = "Chat & Social",
	Finder = "Quality of Life", Macros = "Interface",
	ReadyReport = "Group", MobAbilities = "Combat", SpellEfficiency = "Combat",
	Hardcore = "Quality of Life", SplitTimer = "Quality of Life", FlightGames = "Quality of Life",
	-- Items & Economy
	Bags = "Items & Economy", BagActions = "Items & Economy", Merchant = "Items & Economy", Auction = "Items & Economy",
	Upgrades = "Items & Economy", MobInfo = "Items & Economy", Mail = "Items & Economy",
	Trade = "Items & Economy", LootGuide = "Items & Economy", Characters = "Items & Economy", Attunements = "Items & Economy",
	Adventure = "Items & Economy", ProfessionPlanner = "Items & Economy", Appearances = "Items & Economy",
	-- Quality of Life
	QoL = "Quality of Life",
	Training = "Quality of Life", Talents = "Quality of Life",
	Waypoints = "Quality of Life", Snapshots = "Quality of Life", Camp = "Quality of Life",
	QuestTint = "Quality of Life", Gathering = "Quality of Life", Farming = "Quality of Life",
	ZoneInfo = "Quality of Life", Legacy = "Quality of Life",
	Camera = "Quality of Life", MapNotes = "Quality of Life", RareScanner = "Quality of Life",
	Fishing = "Quality of Life", Eldostar = "Quality of Life",
	Transport = "Quality of Life", MageTravel = "Quality of Life",
	BlessingPlan = "Group",
}
-- The built-in table, for read-only use.
E.defaultModuleCategory = Category.DEFAULT_CATEGORY

-- A module's own `category` wins. Third-party plugins go under Plugins;
-- EldoUI's own module addons (addon "EldoUI_<Name>", the planned split)
-- stay in their group even when they are separate addons.
function Category.CategoryOf(module)
	if module.category then return Category.CATEGORY_KEYS[module.category] or module.category end
	if not E:IsFirstPartyModule(module) then return "Plugins" end
	return Category.DEFAULT_CATEGORY[module.name] or "Quality of Life"
end

-- The category of a module: a key from E.moduleCategories (or a plugin's
-- own). Plugins and move mode read it, so the keys stay as they are.
function E:GetModuleCategory(module)
	if type(module) == "string" then module = self.modules[module] end
	return module and Category.CategoryOf(module) or nil
end

-- Sidebar groups: short, even groups of modules, one sidebar row per module
-- (DESIGN.md §0b). The installer's Modules step uses the same groups. The
-- names are the titles; shown translated: L["Unit Frames"],
-- L["Action Bars and Cooldowns"], L["Combat Info"], L["Group and Instances"],
-- L["Interface"], L["Blizzard Windows"], L["Chat and Social"],
-- L["Bags and Economy"], L["Collections and Progress"], L["World and Travel"],
-- L["Quality of Life"], L["Plugins"]
E.moduleGroups = { "Unit Frames", "Action Bars and Cooldowns", "Combat Info", "Group and Instances", "Interface",
	"Blizzard Windows", "Chat and Social", "Bags and Economy", "Collections and Progress", "World and Travel",
	"Quality of Life", "Plugins" }
local MODULE_GROUP = {}
for group, names in pairs({
	["Unit Frames"] = { "UnitFrames", "GroupFrames", "Nameplates", "ClassPower", "PetCare", "Auras", "AuraGroups" },
	["Action Bars and Cooldowns"] = { "ActionBars", "MyBars", "CooldownManager", "CooldownPulse", "ConsumableBar", "ClassBar",
		"Quickdraw", "TrackingBars", "Macros", "ClickCast" },
	["Combat Info"] = { "Alerts", "CombatHUD", "CombatText", "CastFX", "EnemySpotter", "MobAbilities",
		"SpellEfficiency", "EncounterTimeline", "DBM" },
	["Group and Instances"] = { "RaidTools", "BlessingPlan", "Instances", "DungeonRoutes", "RaidLoot", "ReadyReport",
		"Battlegrounds", "Finder", "PartyQuests" },
	["Interface"] = { "InfoBar", "Minimap", "MicroMenu", "StatusBars", "ObjectiveTracker", "Tooltip",
		"Notifications", "Fanfare" },
	["Blizzard Windows"] = { "Skins", "NPCWindows", "SystemUI", "Character", "EditMode", "AFK", "Integrations",
		"Setups", "Dialogue" },
	["Chat and Social"] = { "Chat", "ChatInput", "ChatBubbles", "Messages", "Social", "PlayerNotes", "Streamer" },
	["Bags and Economy"] = { "Bags", "BagActions", "Merchant", "Auction", "Mail", "Trade", "Upgrades", "MobInfo" },
	["Collections and Progress"] = { "Characters", "Adventure", "Attunements", "LootGuide", "QuestDrops",
		"ZoneQuests", "Eldostar", "Appearances", "ProfessionPlanner", "Talents", "Training" },
	["World and Travel"] = { "Maps", "MapNotes", "Waypoints", "Transport", "MageTravel", "ZoneInfo", "RareScanner", "QuestTint",
		"Gathering", "Fishing", "Farming", "FlightGames" },
	["Quality of Life"] = { "QoL", "Loot", "Reminders", "Counters", "Snapshots", "Camp", "Camera", "Legacy",
		"Hardcore", "SplitTimer" },
}) do
	for _, name in ipairs(names) do MODULE_GROUP[name] = group end
end
-- The built-in table, for read-only use.
E.defaultModuleGroup = MODULE_GROUP
-- A plugin's category lands in the group that covers it; a plugin may also
-- name a group itself.
Category.CATEGORY_GROUP = { Combat = "Combat Info", Group = "Group and Instances",
	["Chat & Social"] = "Chat and Social", ["Items & Economy"] = "Bags and Economy" }

-- The sidebar group of a module.
function E:GetModuleGroup(module)
	if type(module) == "string" then module = self.modules[module] end
	if not module then return nil end
	if E:IsFirstPartyModule(module) and MODULE_GROUP[module.name] then return MODULE_GROUP[module.name] end
	local category = Category.CategoryOf(module)
	return Category.CATEGORY_GROUP[category] or category
end

-- The sidebar's folding sections: the module groups with their module
-- pages (alphabetical inside each). Also returns the pages of the foot
-- (What's New) and the five hubs with their general pages, in order.
function Tree.Sections()
	local hubs, groups, bottom = {}, {}, {}
	for index, hub in ipairs(Tree.HUBS) do
		hubs[index] = { key = hub.key, title = L[hub.title], pages = {} }
	end
	for _, page in ipairs(pages) do
		if page.module then
			local group = E:GetModuleGroup(page.module) or "Plugins"
			groups[group] = groups[group] or { key = "group:" .. group, title = E:CategoryTitle(group), pages = {} }
			table.insert(groups[group].pages, page)
		elseif BOTTOM_PAGES[page.id] then
			table.insert(bottom, page)
		else
			table.insert(hubs[Tree.pageHub[page.id] or Tree.OTHER_HUB].pages, page)
		end
	end
	local sections, hubList = {}, {}
	for _, hub in ipairs(hubs) do
		table.sort(hub.pages, function(a, b)
			local ra, rb = Tree.pageRank[a.id], Tree.pageRank[b.id]
			if ra and rb then return ra < rb end
			if ra or rb then return ra ~= nil end
			if a.order ~= b.order then return a.order < b.order end
			return a.id < b.id
		end)
		if #hub.pages > 0 then hubList[#hubList + 1] = hub end
	end
	local order = {}
	for _, group in ipairs(E.moduleGroups) do order[#order + 1] = group end
	local extra = {}
	for group in pairs(groups) do
		if not tContains(order, group) then extra[#extra + 1] = group end
	end
	table.sort(extra)
	for _, group in ipairs(extra) do table.insert(order, #order, group) end
	for _, group in ipairs(order) do
		local section = groups[group]
		if section then
			table.sort(section.pages, function(a, b) return a.title < b.title end)
			sections[#sections + 1] = section
		end
	end
	table.sort(bottom, function(a, b) return BOTTOM_PAGES[a.id] < BOTTOM_PAGES[b.id] end)
	return sections, bottom, hubList
end

-- The hub definition (Tree.HUBS) a page belongs to; nil for module pages
-- and the foot's pages.
function Tree.HubOf(page)
	if not page or page.module or BOTTOM_PAGES[page.id] then return nil end
	return Tree.HUBS[Tree.pageHub[page.id] or Tree.OTHER_HUB]
end

-- The registered pages of a hub, in its order.
function Tree.HubPages(key)
	local _, _, hubs = Tree.Sections()
	for _, hub in ipairs(hubs) do
		if hub.key == key then return hub.pages end
	end
	return {}
end

-- A hub opens on the page last shown in it (this session), else its first.
Tree.hubLast = {}
function Tree.OpenHub(key)
	local list = Tree.HubPages(key)
	local page = Tree.hubLast[key]
	if not tContains(list, page) then page = list[1] end
	if not page then return false end
	ShowPage(page)
	return true
end

-- Is this hub one of the quick actions (its row sits above the search)?
function Tree.QuickHub(key)
	for _, spec in ipairs(Tree.QUICK) do
		if spec.hub == key then return true end
	end
	return false
end

-- Rebuild the sidebar: one row per hub (the hubs without a quick action),
-- then the module groups. What's New and Errors are links in the sidebar
-- foot (Tree.Foot).
BuildNav = function()
	local nav = window.nav
	for _, button in ipairs(nav.buttons) do button:Hide() end
	for _, header in ipairs(nav.headers) do header:Hide() end

	local sections, _, hubs = Tree.Sections()
	local y, used, headers = 0, 0, 0
	local selectedTop, selectedBottom
	-- Where each row starts, so a scroll can stop on a whole row.
	local rowTops = {}
	-- Rows in sidebar order, for Up / Down.
	nav.order = {}
	-- The quick actions come first for Up / Down.
	Tree.LayoutQuick()
	for _, row in ipairs(window.quick or {}) do nav.order[#nav.order + 1] = row end
	local function Entry(text, page, hub)
		used = used + 1
		local button = NavButton(used)
		button.page, button.hub = page, hub
		button.module = page and page.module
		-- A long name wraps to a second line and the row grows with it.
		local left, right = hub and 8 or Tree.TEXT, button.module and 32 or 8
		button.text:ClearAllPoints()
		button.text:SetPoint("LEFT", left, 0)
		button.text:SetWidth(NAV_WIDTH - left - right)
		local hits = Tree.hits and (page and Tree.hits[page] or hub and Tree.HubHits(hub.key))
		if button.module and E:ModuleFailed(button.module) then text = E:StatusText("warn", text) end
		button.text:SetText(hits and ("%s (%d)"):format(text, hits.total) or text)
		local height = math.max(Tree.ROW, math.ceil(tonumber(button.text:GetStringHeight()) or 0) + 8)
		button:SetHeight(height)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 0, -y)
		button:Show()
		rowTops[#rowTops + 1] = y
		nav.order[#nav.order + 1] = button
		if (page ~= nil and page == currentPage) or (hub and Tree.InHub(hub.key)) then
			selectedTop, selectedBottom = y, y + height
		end
		y = y + height + Tree.GAP
	end
	-- One row per hub; its pages are the tabs of the hub page.
	local hubRows = 0
	for _, hub in ipairs(hubs) do
		if not Tree.QuickHub(hub.key) then
			Entry(hub.title, nil, hub)
			hubRows = hubRows + 1
		end
	end
	if hubRows > 0 then y = y + 6 end
	for _, section in ipairs(sections) do
		headers = headers + 1
		local header = Tree.Header(headers)
		header.section, header.title = section, section.title
		header.label:SetText(section.title)
		header.count:SetText(#section.pages)
		header:ClearAllPoints()
		header:SetPoint("TOPLEFT", 0, -y)
		header:Show()
		rowTops[#rowTops + 1] = y
		Tree.PaintHeader(header)
		nav.order[#nav.order + 1] = header
		y = y + Tree.FitSectionHeader(header)
		if Tree.IsOpen(section) then
			for _, page in ipairs(section.pages) do Entry(page.title, page) end
			y = y + 4
		end
	end
	nav.content:SetHeight(math.max(1, y))
	Tree.RefocusKeys()
	UpdateNav()
	-- Keep the open page in view.
	local scroll = nav.scroll
	local height = scroll:GetHeight()
	if selectedTop and height and height > 0 then
		local offset = scroll:GetVerticalScroll() or 0
		if selectedTop < offset then
			scroll:SetVerticalScroll(selectedTop)
		elseif selectedBottom > offset + height then
			-- Scroll just far enough, to the first whole row at the top, so
			-- no row is cut in half above the open page.
			local target = math.max(0, math.min(selectedTop, selectedBottom - height))
			for _, top in ipairs(rowTops) do
				if top >= target then target = math.min(top, selectedTop) break end
			end
			scroll:SetVerticalScroll(target)
		end
	end
end

UpdateNav = function()
	if not window then return end
	for _, button in ipairs(window.nav.buttons) do
		if button:IsShown() then PaintNav(button) end
	end
	for _, row in ipairs(window.quick or {}) do Tree.PaintQuick(row) end
	if window.foot then window.foot.Update() end
	for _, header in ipairs(window.nav.headers) do
		if header:IsShown() then Tree.PaintHeader(header) end
	end
end

-- The Errors link follows the error log while the window is open.
if E.errors and E.errors.OnChange then
	local pending = false
	E.errors:OnChange("ConfigNav", function()
		if pending or not (window and window:IsShown() and window.foot) then return end
		pending = true
		C_Timer.After(0.5, function()
			pending = false
			if window and window:IsShown() and window.foot then window.foot.Update() end
		end)
	end)
end

-- Search hits per page and tab, for the tree (nil clears them).
SetNavHits = function(groups)
	if not groups then
		if Tree.hits then
			Tree.hits = nil
			BuildNav()
		end
		return
	end
	Tree.hits = {}
	for _, group in ipairs(groups) do
		local hits = { total = #group.results, tabs = {} }
		for _, entry in ipairs(group.results) do
			if entry.tab then hits.tabs[entry.tab] = (hits.tabs[entry.tab] or 0) + 1 end
		end
		Tree.hits[group.page] = hits
	end
	BuildNav()
end

---------------------------------------------------------------------------
-- Header and footer
---------------------------------------------------------------------------
-- "Reset <module>" shows on module pages; Reload UI takes its place elsewhere.
local function ShowResetButton(page)
	local reload = window.reload
	reload:ClearAllPoints()
	if page and page.module then
		window.reset.fullText = L["Reset %s"]:format(page.title)
		window.reset:Show()
		reload:SetPoint("LEFT", window.reset, "RIGHT", 8, 0)
	else
		window.reset:Hide()
		reload:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", MAIN_LEFT, 12)
	end
	Size.FitFooter()
end

-- The page title ends at the leftmost header button that shows (Reset size
-- only while the size differs from the default), and a title that is still
-- too long for that room (Large text, a narrow window) steps its size down
-- until it fits, never below the section size.
function Tree.FitTitle()
	local title = window and window.title
	if not (title and window.scaleBox) then return end
	local right = window.resetSize and window.resetSize:IsShown() and window.resetSize or window.scaleBox
	title:ClearAllPoints()
	-- Its box reaches from the top down to the scale box's bottom, so the
	-- title stays centered on the row of buttons beside it.
	title:SetPoint("TOPLEFT", 4, -8)
	title:SetPoint("BOTTOMRIGHT", window.scaleBox, "BOTTOMLEFT", right == window.scaleBox and -8 or -(right:GetWidth() + 16), 0)
	local info = texts[title]
	if not info then return end
	local left, stop = window.header and window.header:GetLeft(), right:GetLeft()
	local room = left and stop and (stop - 8 - (left + 4))
	local size = Tree.PAGE_TITLE
	repeat
		info.size = size
		ApplyTextFont(title, info)
		local width = title.GetUnboundedStringWidth and title:GetUnboundedStringWidth() or title:GetStringWidth()
		if not room or not width or width <= room then break end
		size = size - 1
	until size < E.tokens.size.section
end

-- Is the page's one line of text cut short?
-- The page description under the title wraps to this many lines.
Tree.SUBTITLE_LINES = 2

function Tree.SubtitleCut()
	local subtitle = window and window.subtitle
	if not subtitle then return false end
	local text = subtitle:GetText()
	if type(text) ~= "string" or text == "" then return false end
	if subtitle.IsTruncated then return subtitle:IsTruncated() and true or false end
	local full = subtitle.GetUnboundedStringWidth and subtitle:GetUnboundedStringWidth() or subtitle:GetStringWidth()
	local room = subtitle:GetWidth()
	return type(full) == "number" and type(room) == "number" and full > room * Tree.SUBTITLE_LINES + 0.5
end

-- The header grows with its title and text line (Large text), so the tab
-- bar below never runs into them.
function Tree.FitHeader()
	local header, title, subtitle = window and window.header, window and window.title, window and window.subtitle
	if not (header and title and subtitle) then return end
	local titleHeight = tonumber(title:GetStringHeight()) or Tree.PAGE_TITLE
	local lineHeight = math.ceil(E.tokens.size.label * E:TextScale() + 2)
	-- A description that wraps to its second line makes the header taller.
	local textHeight = math.min(tonumber(subtitle:GetStringHeight()) or 0, lineHeight * Tree.SUBTITLE_LINES)
	header:SetHeight(math.max(64, math.ceil(8 + titleHeight + 4 + math.max(lineHeight, textHeight) + 10)))
	if window.subtitleHit then window.subtitleHit:EnableMouse(Tree.SubtitleCut()) end
end

local function UpdateHeader(page)
	-- A hub page shows the hub's name; its tabs name the page.
	local hub = Tree.HubOf(page)
	window.title:SetText(hub and L[hub.title] or page.title)
	Tree.FitTitle()
	local desc = E:Translate(page.desc) or ""
	local module = page.module
	if module then
		local _, conflict = E:GetModuleConflict(module)
		if conflict then
			desc = desc .. "  " .. Warn() .. L["Off while %s is loaded."]:format(conflict) .. "|r"
		elseif E:ModuleFailed(module) then
			desc = desc .. "  " .. E:StatusText("warn", L["Part of this module failed to load."])
		elseif not module:IsEnabled() then
			desc = desc .. "  " .. L["This module is off."]
		end
	end
	window.subtitle:SetText(desc)
	Tree.FitHeader()
	window.share:Show()
	window.pageSearch:Show()
	Tree.PlaceShare()
	ShowResetButton(page)
end

-- The page search sits left of Share at the end of the tab bar's first line.
function Tree.PlaceShare()
	local search, share = window and window.pageSearch, window and window.share
	if not (search and share) then return end
	search:ClearAllPoints()
	search:SetPoint("RIGHT", share, "LEFT", -6, 0)
end

-- Version, memory and (when profiling is on) CPU in the sidebar foot.
function Tree.UpdateStats()
	local text = "v" .. E.version
	local updateMemory = UpdateAddOnMemoryUsage or (C_AddOns and C_AddOns.UpdateAddOnMemoryUsage)
	local getMemory = GetAddOnMemoryUsage or (C_AddOns and C_AddOns.GetAddOnMemoryUsage)
	if updateMemory and getMemory then
		updateMemory()
		local kb = getMemory("EldoUI") or 0
		if kb >= 1024 then
			text = text .. "   " .. L["Memory %.2f MB"]:format(kb / 1024)
		else
			text = text .. "   " .. L["Memory %.0f KB"]:format(kb)
		end
	end
	local getCPU = GetAddOnCPUUsage or (C_AddOns and C_AddOns.GetAddOnCPUUsage)
	if getCPU then
		local updateCPU = UpdateAddOnCPUUsage or (C_AddOns and C_AddOns.UpdateAddOnCPUUsage)
		if updateCPU then updateCPU() end
		local ms = getCPU("EldoUI")
		if ms and ms > 0 then text = text .. "   " .. L["CPU %.0f ms"]:format(ms) end
	end
	window.stats:SetText(text)
end

---------------------------------------------------------------------------
-- Pages and global search
---------------------------------------------------------------------------
-- note: optional text for the subtitle (why the search landed here).
ShowPage = function(page, tabIndex, focusOption, note)
	HideShareMenu()
	local previous = currentPage
	searching = false
	currentPage = page
	local hub = Tree.HubOf(page)
	if hub then Tree.hubLast[hub.key] = page end
	pageFilter = nil
	suppressSearch = true
	window.pageSearch:SetText("")
	suppressSearch = false
	UpdateHeader(page)
	ShowTab(tabIndex or page.currentTab or 1, false, focusOption)
	if note then window.subtitle:SetText(note) end
	-- The open page's section unfolds (Tree.IsOpen), so a new page
	-- rebuilds the sidebar; leaving the search brings the player's tree back.
	if Tree.hits then
		SetNavHits(nil)
	elseif previous ~= page then
		BuildNav()
	else
		UpdateNav()
	end
	for _, fn in ipairs(Tree.pageShown) do
		local ok, err = pcall(fn, page.id)
		if not ok then geterrorhandler()(err) end
	end
end

-- "A page opened" listeners: fn(pageId) after the page is drawn (the tour
-- helps point at a row the first time its page opens).
Tree.pageShown = {}
function E:OnConfigPageShown(fn)
	assert(type(fn) == "function", "EldoUI:OnConfigPageShown(fn)")
	table.insert(Tree.pageShown, fn)
end

-- The row that hides `option` right now: its `dependsOn` row, or else the
-- nearest toggle above it in its section that is off.
local function HiddenParent(page, section, option)
	local key = ParentKey(option)
	if key and page.optionsByKey[key] then return page.optionsByKey[key] end
	local found
	for _, item in ipairs(section.items) do
		if item == option then break end
		local itemKey = KeyOf(item)
		if item.type == "toggle" and type(itemKey) == "string" and not IsHidden(item)
			and not GetPath(Tree.RootOf(page, item), itemKey) then
			found = item
		end
	end
	return found
end

-- Rows shown per page in the results; "Show all N on this page" opens the
-- page with its own search filled.
Tree.RESULTS_PER_PAGE = 8

-- Every row, section and page that matches, grouped by page, all counted
-- (no cap that cuts the tail of the sidebar). Pages with the best
-- match come first, then in sidebar order. Rows that a switched-off
-- setting hides are found too, marked hidden.
local function SearchAll(filter)
	local groups, total = {}, 0
	for pageIndex, page in ipairs(pages) do
		local results = {}
		if Matches(page.title, filter) then
			table.insert(results, { page = page, label = page.title, path = L["Page"], score = 4, order = 0 })
		elseif type(page.keywords) == "table" then
			for _, word in ipairs(page.keywords) do
				if Matches(L[word], filter) or Matches(word, filter) then
					table.insert(results, { page = page, label = page.title, path = L["Page"], score = 3, order = 0 })
					break
				end
			end
		end
		local order = 0
		for tabIndex, tab in ipairs(Structure(page)) do
			for _, section in ipairs(tab.sections) do
				local function Path(extra)
					local parts = {}
					if page.hasTabs then table.insert(parts, tab.label) end
					if section.header then table.insert(parts, StripCodes(section.header.label)) end
					if extra then table.insert(parts, extra) end
					return table.concat(parts, " > ")
				end
				local function Consider(option, cogParent)
					order = order + 1
					if not (option.label and builders[option.type]) or option.type == "description" or option.type == "preview" then return end
					local score, hint = Score(option, filter, page.title)
					if score == 0 then return end
					local entry = { page = page, tab = tabIndex, option = option, label = StripCodes(option.label),
						score = score, order = order, hint = hint, cogParent = cogParent,
						path = Path(cogParent and L["%s (gear)"]:format(StripCodes(cogParent.label))) }
					if IsHidden(option) or (cogParent and IsHidden(cogParent)) then
						entry.hidden = true
						entry.parent = HiddenParent(page, section, cogParent or option)
					end
					table.insert(results, entry)
				end
				local header = section.header
				if header and not IsHidden(header) and Matches(header.label, filter) then
					order = order + 1
					table.insert(results, { page = page, tab = tabIndex, option = header, label = StripCodes(header.label),
						score = 3, order = order, path = page.hasTabs and L["%s > section"]:format(tab.label) or L["Section"] })
				end
				for _, option in ipairs(section.items) do
					Consider(option)
					for _, child in ipairs(page.cogItems[option] or {}) do Consider(child, option) end
				end
			end
		end
		if #results > 0 then
			-- Best matches first; rows hidden right now after the visible ones.
			table.sort(results, function(a, b)
				if a.score ~= b.score then return a.score > b.score end
				if (a.hidden or false) ~= (b.hidden or false) then return not a.hidden end
				return a.order < b.order
			end)
			table.insert(groups, { page = page, results = results, best = results[1].score, index = pageIndex })
			total = total + #results
		end
	end
	table.sort(groups, function(a, b)
		if a.best ~= b.best then return a.best > b.best end
		return a.index < b.index
	end)
	return groups, total
end
E.ConfigSearchAll = SearchAll -- read-only, for plugins
E.ConfigResultsPerPage = Tree.RESULTS_PER_PAGE

-- The search index: every page's rows, built a page at a time over a few
-- frames once the window opens (E:RunSliced), so the first search never
-- stalls the game. A search before it ends builds the rest right away.
local indexJob
local function WarmSearchIndex()
	if indexJob and not indexJob.done then return end
	indexJob = E:RunSliced(function()
		for _, page in ipairs(pages) do
			if not page.tabs then
				Structure(page)
				E.SliceYield()
			end
		end
	end, 4)
end
E.ConfigSearchIndex = function() return indexJob end -- exposed for inspection
E.ConfigPageList = function() return pages end -- exposed for inspection
E.ConfigCurrentPage = function() return currentPage end -- exposed for inspection
E.ConfigHubs = function() return select(3, Tree.Sections()) end -- exposed for inspection
E.ConfigHubOf = function(page) return Tree.HubOf(page) end -- exposed for inspection

-- Open a search result: the row (flashed), the gear popup that holds it,
-- or for a hidden row the setting that shows it, with a note.
local function OpenResult(entry)
	if not entry then return end
	local page = entry.page
	-- Searching for a setting of a switched-off module opens its settings.
	if page.module and not page.module:IsEnabled() and (entry.option or entry.showAll) then page.showOff = true end
	-- "Show all N on this page": the page with its own search filled.
	if entry.showAll then
		local tabIndex
		for _, result in ipairs(entry.showAll.results) do
			if result.tab then tabIndex = result.tab break end
		end
		ShowPage(page, tabIndex)
		suppressSearch = true
		window.pageSearch:SetText(entry.filter)
		suppressSearch = false
		pageFilter = entry.filter:lower()
		ShowTab(page.currentTab)
		return
	end
	if entry.hidden then
		local parent = entry.parent
		local note
		if parent then
			note = Warn() .. L["\"%s\" shows when \"%s\" is on."]:format(entry.label, StripCodes(parent.label)) .. "|r"
		else
			note = Warn() .. L["\"%s\" is hidden by another setting on this page right now."]:format(entry.label) .. "|r"
		end
		local tabIndex = parent and page.tabOf[parent] or entry.tab
		-- A parent inside a gear: flash the row that owns the gear.
		local target = parent and (page.cogParent[parent] or parent)
		ShowPage(page, tabIndex, target, note)
		return
	end
	if entry.cogParent then
		ShowPage(page, entry.tab, entry.cogParent)
		local tab = page.tabs and page.tabs[page.currentTab]
		local cell = tab and tab.widgets[entry.cogParent]
		if cell and cell:IsShown() then
			if GearBlocked(cell) then
				window.subtitle:SetText(Warn() .. L["\"%s\" is under the gear of \"%s\": turn that on first."]:format(
					entry.label, StripCodes(entry.cogParent.label)) .. "|r")
			else
				OpenCog(cell, entry.cogParent, page, tab, entry.option)
			end
		end
		return
	end
	ShowPage(page, entry.tab, entry.option)
end

-- The row of `page` with option key `key` as a search result, so an
-- options link opens it the way a search does: the row flashed, the gear
-- that holds it opened, or for a hidden row the setting that shows it.
function Tree.LinkEntry(page, key)
	for tabIndex, tab in ipairs(Structure(page)) do
		for _, section in ipairs(tab.sections) do
			for _, option in ipairs(section.items) do
				local hit, cogParent
				if KeyOf(option) == key then
					hit = option
				else
					for _, child in ipairs(page.cogItems[option] or {}) do
						if KeyOf(child) == key then hit, cogParent = child, option break end
					end
				end
				if hit then
					local entry = { page = page, tab = tabIndex, option = hit, label = StripCodes(hit.label or ""), cogParent = cogParent }
					if IsHidden(hit) or (cogParent and IsHidden(cogParent)) then
						entry.hidden = true
						entry.parent = HiddenParent(page, section, cogParent or hit)
					end
					return entry
				end
			end
		end
	end
end

function Tree.OpenLink(page, key, tabLabel)
	if key then
		local entry = Tree.LinkEntry(page, key)
		if entry then OpenResult(entry) return true end
	end
	if tabLabel then
		for index, tab in ipairs(Structure(page)) do
			if tab.label == tabLabel or tab.label == L[tabLabel] then
				ShowPage(page, index)
				return true
			end
		end
	end
	return key == nil and tabLabel == nil
end

local function ResultButton(index)
	local frame = window.results
	local button = frame.buttons[index]
	if button then return button end
	button = CreateFrame("Button", nil, frame)
	button:SetHeight(RESULT_ROW)
	button.bg = button:CreateTexture(nil, "BACKGROUND")
	button.bg:SetAllPoints()
	button.line = button:CreateTexture(nil, "BORDER")
	button.line:SetPoint("BOTTOMLEFT")
	button.line:SetPoint("BOTTOMRIGHT")
	E:Hairline(button.line, "h", 1)
	button.line:SetColorTexture(unpack(E.tokens.edge.divider))
	button.highlight = button:CreateTexture(nil, "HIGHLIGHT")
	button.highlight:SetAllPoints()
	button.highlight:SetColorTexture(1, 1, 1, E.tokens.hover.row)
	button.path = Text(button, E.tokens.size.small, "RIGHT", SECONDARY)
	button.path:SetPoint("RIGHT", -12, 0)
	button.label = Text(button, E.tokens.size.body, "LEFT", TEXT)
	button.label:SetPoint("LEFT", 12, 0)
	button.label:SetPoint("RIGHT", button.path, "LEFT", -12, 0)
	button:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		if self.group then
			ShowPage(self.group.page)
		else
			OpenResult(self.entry)
		end
	end)
	frame.buttons[index] = button
	return button
end

-- Keyboard selection (Up / Down / Enter in the search box).
local function PaintResults()
	local frame = window.results
	for _, button in ipairs(frame.buttons) do
		if button:IsShown() and not button.group then
			if button.resultIndex == frame.selected then
				button.bg:SetColorTexture(Accent(0.25))
			else
				button.bg:SetColorTexture(1, 1, 1, button.stripe and 0.03 or 0)
			end
		end
	end
end

local function SelectResult(delta)
	local frame = window.results
	local count = #(frame.flat or {})
	if not searching or count == 0 then return end
	frame.selected = math.max(1, math.min(count, (frame.selected or 1) + delta))
	PaintResults()
	-- Keep the selected row in view.
	for _, button in ipairs(frame.buttons) do
		if button:IsShown() and button.resultIndex == frame.selected then
			local scroll = window.scroll
			local top, height = button.layoutY, scroll:GetHeight()
			local offset = scroll:GetVerticalScroll()
			if top < offset then
				scroll:SetVerticalScroll(top)
			elseif top + RESULT_ROW > offset + height then
				scroll:SetVerticalScroll(top + RESULT_ROW - height)
			end
		end
	end
end

local function OpenSelectedResult()
	local frame = window.results
	if searching and frame.flat and frame.selected then OpenResult(frame.flat[frame.selected]) end
end
E.ConfigOpenResult = function(entry) OpenResult(entry) end -- exposed for inspection

ShowResults = function(text)
	HideShareMenu()
	HideCog()
	searching = true
	if indexJob then indexJob:Finish() end
	local filter = strtrim(text):lower()
	local groups, total = SearchAll(filter)
	window.title:SetText(L["Search"])
	Tree.FitTitle()
	if total == 0 then
		window.subtitle:SetText(L["Nothing matches \"%s\". The search looks at names, descriptions and choices."]:format(text))
	else
		window.subtitle:SetText((total == 1 and L["%d match for \"%s\". Up, Down and Enter pick one, or click it."]
			or L["%d matches for \"%s\". Up, Down and Enter pick one, or click it."]):format(total, text))
	end
	window.share:Hide()
	window.pageSearch:Hide()
	ShowResetButton(nil)
	UpdateTabBar()

	local frame = window.results
	local width = ContentWidth()
	frame:SetWidth(width)
	for _, button in ipairs(frame.buttons) do button:Hide() end
	frame.flat = {}
	local index, y = 0, 0
	local function Place(button)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", 0, -y)
		button:SetWidth(width)
		button.layoutY = y
		button:Show()
		y = y + RESULT_ROW
	end
	for _, group in ipairs(groups) do
		-- Page caption in the accent color; a click opens the page.
		index = index + 1
		local caption = ResultButton(index)
		caption.group, caption.entry, caption.resultIndex, caption.stripe = group, nil, nil, nil
		caption.label:SetText(group.page.title)
		caption.label:SetTextColor(E:TokenColor("accent"))
		caption.path:SetText(tostring(#group.results))
		caption.bg:SetColorTexture(1, 1, 1, 0)
		Place(caption)
		local shown = #group.results
		if shown > Tree.RESULTS_PER_PAGE + 1 then shown = Tree.RESULTS_PER_PAGE end
		for row = 1, shown do
			local entry = group.results[row]
			index = index + 1
			table.insert(frame.flat, entry)
			local button = ResultButton(index)
			button.group, button.entry, button.resultIndex = nil, entry, #frame.flat
			button.stripe = row % 2 == 1
			local label = "    " .. entry.label
			if entry.hint then label = label .. ("  %s(%s)|r"):format(GREY, entry.hint) end
			button.label:SetText(label)
			button.label:SetTextColor(unpack(entry.hidden and DIM or TEXT))
			if entry.hidden then
				button.path:SetText(entry.parent and L["hidden: turn on \"%s\" first"]:format(StripCodes(entry.parent.label))
					or L["hidden right now"])
			else
				button.path:SetText(entry.path)
			end
			Place(button)
		end
		if shown < #group.results then
			-- The rest of this page's matches: one row that opens the page.
			index = index + 1
			local entry = { page = group.page, showAll = group, filter = strtrim(text) }
			table.insert(frame.flat, entry)
			local button = ResultButton(index)
			button.group, button.entry, button.resultIndex, button.stripe = nil, entry, #frame.flat, false
			local count = #group.results
			button.label:SetText("    " .. E:Plural(count, "Show all %d on this page", "Show all %d on this page"):format(count))
			button.label:SetTextColor(E:TokenColor("accent"))
			button.path:SetText("")
			Place(button)
		end
	end
	frame.selected = #frame.flat > 0 and 1 or nil
	PaintResults()
	frame:SetHeight(math.max(1, y))
	SetScrollChild(frame)
	window.empty:Hide()
	window.scroll:UpdateScrollChildRect()
	window.scroll:SetVerticalScroll(0)
	SetNavHits(groups)
end

local function OnGlobalSearch(text)
	text = strtrim(text or "")
	if #text >= 2 then
		ShowResults(text)
	elseif searching then
		ShowPage(currentPage or pages[1])
	end
end

---------------------------------------------------------------------------
-- Reload UI in the footer is the one place that shows changes waiting for
-- a reload: "Reload UI (2)" with the accent edge, the changes named in its
-- tooltip, and muted while nothing waits. It never becomes the primary
-- button (Done stays the one). It reloads through the secure /reload button.
---------------------------------------------------------------------------
UpdateReloadButton = function()
	if not (window and window.reload) then return end
	local labels = Reloads.PendingReloads()
	local count = #labels
	local button = window.reload
	button.pending = count > 0
	if count > 0 then
		button.text:SetText(L["Reload UI (%d)"]:format(count))
		button.tipText = (count == 1 and L["%d change needs a reload: %s"] or L["%d changes need a reload: %s"]):format(
			count, #labels <= 8 and table.concat(labels, ", ") or Reloads.ReloadSummary(labels))
	else
		button.text:SetText(L["Reload UI"])
		button.tipText = L["Nothing waits for a reload right now. A reload starts every part of EldoUI fresh."]
	end
	Size.FitButton(button, 112)
	if E.RefreshReloadButtons then E:RefreshReloadButtons() end
	Size.FitFooter()
end

-- Closing the window with changes waiting asks once (again only when more
-- changes came in since the last answer).
function Reloads.PromptPendingReloads()
	local labels = Reloads.PendingReloads()
	if #labels == 0 or #labels <= promptedReloads then return end
	promptedReloads = #labels
	E:ShowReloadPrompt((#labels == 1 and L["%d change takes full effect after a reload: %s."]
		or L["%d changes take full effect after a reload: %s."]):format(#labels, Reloads.ReloadSummary(labels)), Reloads.ClearReloads)
end

---------------------------------------------------------------------------
-- Recent changes list: a footer button "Recent changes (N)" opens
-- a small list of this session's changes (option, before and after) with
-- Undo on every row and Undo all. Undo writes the old value back and
-- re-applies the page like any other change; changes of frames that are
-- protected in combat wait for combat to end (E:RunOutOfCombat).
---------------------------------------------------------------------------

function Recent.ChangeValueText(entry, value)
	local option = entry.option
	if option.type == "copy" then return value == entry.old and L["before the copy"] or L["copied"] end
	if value == nil then return L["not set"] end
	if option.type == "toggle" then return value and L["On"] or L["Off"] end
	if option.type == "range" then return E:ConfigRangeText(option, value) end
	if option.type == "select" then
		local ok, values = pcall(SelectValues, option)
		local name = ok and values[value]
		return StripCodes(name or tostring(value))
	end
	if option.type == "media" then return StripCodes(E:MediaLabel(option.mediaKind or "sound", value) or tostring(value)) end
	if option.type == "color" and type(value) == "table" then
		local hex = ("#%02X%02X%02X"):format((value[1] or 1) * 255 + 0.5, (value[2] or 1) * 255 + 0.5, (value[3] or 1) * 255 + 0.5)
		return E:TokenHex(value) .. hex .. "|r"
	end
	return "\"" .. tostring(value) .. "\""
end

-- Where a change lives: "Unit Frames > Player".
function Recent.ChangePath(entry)
	local page = entry.page
	local tab = page.tabs and page.tabOf and page.tabOf[entry.option]
	local name = tab and page.hasTabs and page.tabs[tab] and page.tabs[tab].label
	return name and ("%s > %s"):format(page.title, name) or page.title
end

-- Put one change back. False when the profile changed since (the value
-- then belongs to another profile and stays as it is).
function Recent.UndoChange(entry)
	local page = entry.page
	if page.target() ~= entry.root then return false end
	local current = GetPath(entry.root, entry.key)
	if entry.option.type == "copy" and type(current) == "table" then
		local kept = {}
		for _, key in ipairs(entry.keep or {}) do kept[key] = current[key] end
		wipe(current)
		for key, value in pairs(CopyTable(entry.old)) do current[key] = value end
		for key, value in pairs(kept) do current[key] = value end
	else
		SetPath(entry.root, entry.key, Recent.Copy(entry.old))
	end
	Changed(page, nil, entry.option)
	return true
end

function Recent.UndoNotice(undone, skipped)
	local text = undone == 1 and L["1 change undone."] or L["%d changes undone."]:format(undone)
	if InCombatLockdown() and undone > 0 then text = text .. " " .. L["Frames update when combat ends."] end
	if skipped > 0 then text = text .. " " .. L["%d belonged to another profile and stay as they are."]:format(skipped) end
	E:ConfigNotice(text, skipped > 0)
end

function E:UndoConfigChange(entry)
	for index, logged in ipairs(Recent.log) do
		if logged == entry then
			table.remove(Recent.log, index)
			local ok = Recent.UndoChange(entry)
			Recent.UndoNotice(ok and 1 or 0, ok and 0 or 1)
			Recent.UpdateButton()
			return ok
		end
	end
	return false
end

function E:UndoAllConfigChanges()
	local undone, skipped = 0, 0
	-- Newest first, so a row changed twice ends at its first value.
	local list = { unpack(Recent.log) }
	wipe(Recent.log)
	for _, entry in ipairs(list) do
		if Recent.UndoChange(entry) then undone = undone + 1 else skipped = skipped + 1 end
	end
	Recent.UndoNotice(undone, skipped)
	E:RefreshConfig()
	Recent.UpdateButton()
	return undone, skipped
end

function Recent.CreateChangeRow(row)
	row.label = Text(row, E.tokens.size.body, "LEFT", TEXT)
	row.label:SetPoint("TOPLEFT", 10, -6)
	row.label:SetPoint("TOPRIGHT", -96, -6)
	row.label:SetWordWrap(false)
	row.values = Text(row, E.tokens.size.small, "LEFT", SECONDARY)
	row.values:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -4)
	row.values:SetPoint("TOPRIGHT", row.label, "BOTTOMRIGHT", 0, -4)
	row.values:SetWordWrap(false)
	row.stripe = row:CreateTexture(nil, "BACKGROUND")
	row.stripe:SetAllPoints()
	row.line = row:CreateTexture(nil, "BORDER")
	row.line:SetPoint("BOTTOMLEFT")
	row.line:SetPoint("BOTTOMRIGHT")
	E:Hairline(row.line, "h", 1)
	row.line:SetColorTexture(unpack(E.tokens.edge.divider))
	row.undo = Button(row, L["Undo"], 76, BUTTON, function(self)
		local entry = self:GetParent().item
		if entry then E:UndoConfigChange(entry) end
	end)
	row.undo:SetPoint("RIGHT", -8, 0)
	AddTooltip(row.undo, L["Undo"], L["Put this setting back to the value it had before."])
	-- The two lines are cut to the row; the tooltip shows them in full.
	row:SetScript("OnEnter", function(self)
		local entry = self.item
		if not entry then return end
		E.UIKit.AnchorTooltip(self, GameTooltip)
		E.UIKit.TipTitle(GameTooltip, StripCodes(entry.option.label or entry.key))
		E.UIKit.TipText(GameTooltip, Recent.ChangePath(entry))
		E.UIKit.TipText(GameTooltip, row.values:GetText())
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	Snap(row)
end

function Recent.UpdateChangeRow(row, entry, index)
	row.label:SetText(("%s  %s%s|r"):format(StripCodes(entry.option.label or entry.key), GREY, Recent.ChangePath(entry)))
	row.values:SetText(L["%s to %s"]:format(Recent.ChangeValueText(entry, entry.old), Recent.ChangeValueText(entry, entry.new)))
	row.stripe:SetColorTexture(1, 1, 1, index % 2 == 1 and 0.03 or 0)
end

function Recent.ChangesPopup()
	if Recent.popup then return Recent.popup end
	-- The tool window shell, opened above the footer button that shows
	-- it: no drag, no grip, no slide. Undo all sits in the header.
	local frame = E.UIKit.CreateToolWindow("EldoUIConfigChanges", { parent = window, width = 480, height = 360,
		strata = "FULLSCREEN_DIALOG", movable = false, resizable = false, slide = false, dialog = false, footer = 28 })
	frame.undoAll = Button(frame.header, L["Undo all"], 96, BUTTON, function() E:UndoAllConfigChanges() end)
	frame.undoAll:SetPoint("RIGHT", frame.close, "LEFT", -6, 0)
	AddTooltip(frame.undoAll, L["Undo all"], L["Put every setting in this list back to the value it had before this session's changes."])
	frame.note = frame.footerText
	frame.note:SetText(L["Changes made in this window since the last reload, newest first."])
	frame.list = E.UIKit.CreateList(frame.content, { rowHeight = Recent.ROW, create = Recent.CreateChangeRow, update = Recent.UpdateChangeRow,
		empty = { L["No changes yet"], L["Settings you change in this window show up here until the next reload."] } })
	frame.list:SetAllPoints()
	Snap(frame)
	Recent.popup = frame
	return frame
end

function Recent.RefreshChanges()
	local frame = Recent.popup
	if not (frame and frame:IsShown()) then return end
	frame:SetTitle(L["Recent changes (%d)"]:format(#Recent.log))
	frame.undoAll:SetShown(#Recent.log > 0)
	frame.list:SetData({ unpack(Recent.log) })
end

function Recent.ToggleChanges()
	local frame = Recent.ChangesPopup()
	if frame:IsShown() then
		frame:Hide()
		return
	end
	HideCog()
	HideShareMenu()
	frame:ClearAllPoints()
	frame:SetPoint("BOTTOMLEFT", window.changes, "TOPLEFT", 0, 6)
	E:SetPanelTemplate(frame)
	Snap(frame)
	frame:Show()
	Recent.RefreshChanges()
end

function Recent.UpdateButton()
	if not (window and window.changes) then return end
	local count = #Recent.log
	local button = window.changes
	button.text:SetText(L["Recent changes (%d)"]:format(count))
	Size.FitButton(button, 120)
	button:SetShown(count > 0)
	Recent.RefreshChanges()
	Size.FitFooter()
end

---------------------------------------------------------------------------
-- Window scale: 70 to 130 %, saved for the account, on top of
-- the fit-to-screen scale. The UI scale is not touched.
---------------------------------------------------------------------------
local function UserScale()
	local scale = tonumber(WindowDB().scale) or 1
	return math.max(SCALE_MIN, math.min(SCALE_MAX, scale))
end

function Size.Changed()
	local db = WindowDB()
	return db.width ~= nil or db.height ~= nil or db.scale ~= nil
end

local function ApplyWindowScale()
	if not window then return end
	-- The saved size, never larger than the screen at the chosen scale.
	-- One window unit is one screen pixel below 1440p
	-- (E:WindowBaseScale), times the player's window size.
	local user = UserScale()
	local wanted = E:WindowBaseScale() * user
	local maxWidth, maxHeight = Size.Max(wanted)
	local width, height = math.min(Size.Width(), maxWidth), math.min(Size.Height(), maxHeight)
	if math.abs((window:GetWidth() or 0) - width) > 0.5 or math.abs((window:GetHeight() or 0) - height) > 0.5 then
		window:SetSize(width, height)
	end
	-- Never larger than the screen allows (a big UI scale, a small screen).
	local scale = E:WindowScale(user, width, height)
	window:SetScale(scale)
	if window.SetResizeBounds then
		window:SetResizeBounds(Size.MIN_WIDTH, Size.MIN_HEIGHT, Size.Max(scale))
	end
	-- 1-pixel edges stay one screen pixel at this scale (DESIGN.md 3a).
	if window.snappedScale ~= scale then
		window.snappedScale = scale
		E:SnapBorders(window)
	end
	if window.scaleText then window.scaleText:SetText(("%d%%"):format(math.floor(user * 100 + 0.5))) end
	if window.resetSize then window.resetSize:SetShown(Size.Changed()) end
	Tree.FitTitle()
end

-- A new UI scale or screen size: the open window follows.
E:RegisterPixelCallback(function()
	if window and window:IsShown() then ApplyWindowScale() end
end)

local function StepScale(steps)
	local scale = UserScale() + steps * SCALE_STEP
	scale = math.floor(scale / SCALE_STEP + 0.5) * SCALE_STEP
	scale = math.max(SCALE_MIN, math.min(SCALE_MAX, scale))
	local db = WindowDB()
	db.scale = math.abs(scale - 1) > 0.001 and scale or nil
	ApplyWindowScale()
	HideCog()
end

-- After the grip: remember the size (nothing saved while it is the default).
function Size.Save()
	local db = WindowDB()
	local width = math.floor((window:GetWidth() or WIDTH) + 0.5)
	local height = math.floor((window:GetHeight() or HEIGHT) + 0.5)
	db.width = width ~= WIDTH and width or nil
	db.height = height ~= HEIGHT and height or nil
	ApplyWindowScale()
end

-- Back to the default size, 100 % scale, centered.
function Size.Reset()
	local db = WindowDB()
	db.width, db.height, db.scale = nil, nil, nil
	HideCog()
	HideShareMenu()
	window:ClearAllPoints()
	window:SetPoint("CENTER")
	ApplyWindowScale()
end

---------------------------------------------------------------------------
-- Size.Reflow: the window changed size. The tab bar, the page (or the search
-- results), the header text and the footer follow, at most every 0.05 s
-- while the grip is dragged.
---------------------------------------------------------------------------
-- A footer button as wide as its label (in steps of 4), never narrower
-- than `least`.
function Size.FitButton(button, least)
	button:SetWidth(math.max(least, math.ceil((button.text:GetStringWidth() + 24) / 4) * 4))
end

-- The footer (DESIGN.md §0a rule 8): Reset <Module>, Reload UI, Move mode
-- and Recent changes on the left, Done on the right as the one primary
-- button. When there is no room (a long module name, Large text, a narrow
-- window), Reset drops the module name first, then Recent changes shortens
-- to "Changes (n)" and at last to the count (their tooltips still say what
-- they do); Reload UI and Move
-- mode always keep their full labels, side by side.
function Size.FitFooter()
	local footer = window.footer
	if not (footer and window.move) then return end
	local reset, changes = window.reset, window.changes
	Size.FitButton(window.move, 112)
	local count = #Recent.log
	if changes then
		changes.text:SetText(L["Recent changes (%d)"]:format(count))
		Size.FitButton(changes, 120)
	end
	local function Over()
		local left = MAIN_LEFT + window.reload:GetWidth() + 8 + window.move:GetWidth()
		if reset:IsShown() then left = left + reset:GetWidth() + 8 end
		if changes and changes:IsShown() then left = left + changes:GetWidth() + 8 end
		return left > (window:GetWidth() or WIDTH) - 20 - footer.done:GetWidth() - 8
	end
	if reset:IsShown() then
		reset.text:SetText(reset.fullText or L["Reset"])
		Size.FitButton(reset, 120)
		if Over() then
			reset.text:SetText(L["Reset"])
			Size.FitButton(reset, 72)
		end
	end
	if changes and changes:IsShown() and Over() then
		changes.text:SetText(L["Changes (%d)"]:format(count))
		Size.FitButton(changes, 72)
	end
	-- The last step: the count alone (Large text in the narrowest window).
	if changes and changes:IsShown() and Over() then
		changes.text:SetText(tostring(count))
		Size.FitButton(changes, 40)
	end
end

function Size.Reflow()
	if not (window and window:IsShown()) then return end
	window.subtitle:SetWidth(math.max(240, math.floor((window.header:GetWidth() or 560) - 40)))
	Tree.FitTitle()
	Tree.FitHeader()
	Size.FitFooter()
	if searching then
		local offset = window.scroll:GetVerticalScroll()
		ShowResults(window.search:GetText())
		window.scroll:SetVerticalScroll(math.min(offset or 0, window.scroll:GetVerticalScrollRange() or 0))
	elseif currentPage then
		ShowTab(currentPage.currentTab, true)
	end
	RefreshCog()
end

Size.queued = false
function Size.QueueReflow()
	if Size.queued then return end
	Size.queued = true
	C_Timer.After(0.05, function()
		Size.queued = false
		Size.Reflow()
	end)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function SearchBox(parent, width, hint, onChange)
	local box = CreateFrame("EditBox", nil, parent, "SearchBoxTemplate")
	box:SetSize(width, E.tokens.height.row)
	box:SetAutoFocus(false)
	E:SetFont(box, E.tokens.size.body)
	if box.Instructions then box.Instructions:SetText(hint) end
	Skin("SkinEditBox", box, { size = 13 })
	box:HookScript("OnTextChanged", function(self)
		if not suppressSearch then onChange(self:GetText()) end
	end)
	return box
end

local function ScrollFrame(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
	Skin("SkinScrollBar", scroll.ScrollBar)
	return scroll
end

---------------------------------------------------------------------------
-- Keyboard (E.UIKit.KeyHandler): Ctrl+F or / goes to the search, Up and
-- Down walk the quick actions and the sidebar tree (or the search
-- results), Left and Right walk the tabs (a hub's pages and their tabs),
-- Enter opens, Esc closes a popup, then clears a search, and only then
-- closes the window. The arrows and Enter belong to the window only while
-- the sidebar, the tab bar or the search box has focus (a click in one, or
-- Ctrl+F); a click anywhere else hands them back to the game, so the arrow
-- keys still move the character while the window is open (design decision).
-- Out of combat only; every other key goes on to the game.
---------------------------------------------------------------------------
-- The tree row the keyboard is on (nil until Up or Down is pressed).
Tree.keyFocus = nil
-- True while the tree or the search box has focus.
Tree.keysOn = false

function Tree.SetKeysOn(on)
	on = on and true or false
	Tree.keysOn = on
	if not on then
		Tree.keyFocus = nil
		if window and window.focusRing then window.focusRing:Attach(nil) end
	end
end

-- A mouse click: inside the tree or on the search box gives them focus,
-- anywhere else takes it away.
function Tree.OnMouseDown()
	if not window then return end
	local nav, search, bar = window.nav and window.nav.scroll, window.search, window.tabBar
	local quick = false
	for _, row in ipairs(window.quick or {}) do quick = quick or row:IsMouseOver() end
	Tree.SetKeysOn((nav and nav:IsMouseOver()) or quick or (bar and bar:IsMouseOver())
		or (search and (search:IsMouseOver() or search:HasFocus())))
end

function Tree.HasKeyFocus()
	return Tree.keysOn or (window and window.search and window.search:HasFocus()) or false
end

function Tree.RefocusKeys()
	local focus = Tree.keyFocus
	if not (window and window.focusRing) then return end
	if focus and focus:IsShown() and tContains(window.nav.order or {}, focus) then
		window.focusRing:Attach(focus)
	else
		Tree.keyFocus = nil
		window.focusRing:Attach(nil)
	end
end

-- The sidebar row of the open page, where Up / Down start.
function Tree.CurrentRow()
	for _, row in ipairs(window.nav.order or {}) do
		if (row.page and row.page == currentPage) or (row.hub and Tree.InHub(row.hub.key))
			or (row.hubKey and Tree.InHub(row.hubKey)) then
			return row
		end
	end
end

function Tree.StepKeys(delta)
	local order = window.nav.order or {}
	if #order == 0 then return end
	local at
	for index, row in ipairs(order) do
		if row == (Tree.keyFocus or Tree.CurrentRow()) then at = index break end
	end
	if not at then at = delta > 0 and 0 or #order + 1 end
	local row = order[math.max(1, math.min(#order, at + delta))]
	Tree.keyFocus = row
	window.focusRing:Attach(row)
	-- Keep it in view (the quick actions sit above the scroll list).
	if row:GetParent() ~= window.nav.content then return end
	local scroll = window.nav.scroll
	local _, _, _, _, top = row:GetPoint(1)
	top = -(top or 0)
	local height, offset = scroll:GetHeight() or 0, scroll:GetVerticalScroll() or 0
	if top < offset then
		scroll:SetVerticalScroll(top)
	elseif height > 0 and top + row:GetHeight() > offset + height then
		scroll:SetVerticalScroll(top + row:GetHeight() - height)
	end
end

function Tree.OpenKeyFocus()
	local row = Tree.keyFocus
	if not (row and row:IsShown()) then return false end
	local onClick = row:GetScript("OnClick")
	if onClick then onClick(row, "LeftButton") end
	-- The tree was rebuilt: the ring stays on the row that was opened.
	Tree.keyFocus = Tree.CurrentRow() or row
	Tree.RefocusKeys()
	return true
end

function Tree.HandleKey(name)
	if name == "CTRL-F" or name == "/" then
		window.search:SetFocus()
		window.search:HighlightText()
		return true
	elseif name == "ESCAPE" then
		if cogPopup and cogPopup:IsShown() then
			HideCog()
			return true
		elseif E.UIKit.MenuShown() then
			-- Any list of the window (Share, a select row) closes first.
			E.UIKit.CloseMenu()
			return true
		elseif strtrim(window.search:GetText() or "") ~= "" then
			window.search:SetText("")
			return true
		elseif strtrim(window.pageSearch:GetText() or "") ~= "" then
			window.pageSearch:SetText("")
			return true
		end
		return false
	elseif (name == "UP" or name == "DOWN" or name == "ENTER" or name == "LEFT" or name == "RIGHT")
		and not Tree.HasKeyFocus() then
		return false
	elseif name == "LEFT" or name == "RIGHT" then
		return Tree.StepTab(name == "LEFT" and -1 or 1)
	elseif name == "UP" or name == "DOWN" then
		local delta = name == "UP" and -1 or 1
		if searching then SelectResult(delta) else Tree.StepKeys(delta) end
		return true
	elseif name == "ENTER" then
		if searching and window.results.selected then
			OpenSelectedResult()
			return true
		end
		return Tree.OpenKeyFocus()
	end
	return false
end
E.ConfigHandleKey = function(name) return window and Tree.HandleKey(name) end

local function CreateWindow()
	-- Large text: the sidebar grows with the text scale (up to 64 px),
	-- so long page names still fit; the page area gives up the room.
	Tree.navBase = Tree.navBase or { SIDEBAR, MAIN_LEFT, NAV_WIDTH }
	local extra = math.min(64, math.floor(Tree.navBase[3] * (E:TextScale() - 1) + 0.5))
	SIDEBAR, MAIN_LEFT, NAV_WIDTH = Tree.navBase[1] + extra, Tree.navBase[2] + extra, Tree.navBase[3] + extra
	window = CreateFrame("Frame", "EldoUIConfig", UIParent)
	-- A new frame starts shown; start hidden so the first /eui opens it
	-- instead of toggling it shut.
	window:Hide()
	window:SetSize(Size.Width(), Size.Height())
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	-- Resizable from the grip in the bottom-right corner (saved for the
	-- account); the contents reflow as it changes.
	window:SetResizable(true)
	if window.SetResizeBounds then window:SetResizeBounds(Size.MIN_WIDTH, Size.MIN_HEIGHT, Size.Max(1)) end
	window:SetClampedToScreen(true)
	window:SetScript("OnSizeChanged", function() Size.QueueReflow() end)
	SkinWindow()
	table.insert(UISpecialFrames, "EldoUIConfig")

	-- The player's window scale, shrunk to fit small screens or large UI
	-- scales.
	window:SetScript("OnShow", function()
		ApplyWindowScale()
		-- Measuring the memory walks every addon, so it happens when the
		-- window opens and when the player points at the line, not on a timer.
		Tree.UpdateStats()
	end)
	window:SetScript("OnHide", function()
		HideShareMenu()
		HideCog()
		if Recent.popup then Recent.popup:Hide() end
		GameTooltip:Hide()
		if not window.quietHide then Reloads.PromptPendingReloads() end
		window.quietHide = nil
	end)

	local function Draggable(frame)
		frame:EnableMouse(true)
		frame:RegisterForDrag("LeftButton")
		frame:SetScript("OnDragStart", function() window:StartMoving() end)
		frame:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
	end

	-- Sidebar: an inset box like E:SkinInset, the full height of the
	-- window ---------------------------------------------------------------
	local sidebar = CreateFrame("Frame", nil, window)
	sidebar:SetPoint("TOPLEFT", 8, -8)
	sidebar:SetPoint("BOTTOMLEFT", 8, 8)
	sidebar:SetWidth(SIDEBAR)
	Box(sidebar, true, INSET_TINT)
	Draggable(sidebar)
	window.sidebar = sidebar

	local logo = sidebar:CreateTexture(nil, "ARTWORK")
	logo:SetTexture(E.media.logo)
	logo:SetSize(176, 44)
	logo:SetPoint("TOP", 0, -8)

	-- Quick actions: one icon row each, above the search.
	window.quickAll = {}
	for _, spec in ipairs(Tree.QUICK) do
		window.quickAll[#window.quickAll + 1] = Tree.QuickRow(sidebar, spec)
	end
	local searchTop = Tree.QUICK_TOP + #Tree.QUICK * (Tree.ROW + Tree.GAP) + 6

	window.search = SearchBox(sidebar, 196, L["Search features"], OnGlobalSearch)
	window.search:SetPoint("TOPLEFT", 16, -searchTop)
	-- Up / Down pick a result, Enter opens it.
	window.search:HookScript("OnArrowPressed", function(_, key)
		if key == "UP" then SelectResult(-1) elseif key == "DOWN" then SelectResult(1) end
	end)
	window.search:HookScript("OnEnterPressed", function(self)
		OpenSelectedResult()
		self:ClearFocus()
	end)
	-- Esc in a search box clears it first (the next Esc closes the window).
	window.search:HookScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then self:SetText("") end
		self:ClearFocus()
	end)

	-- Sidebar foot: What's New, Errors and Thanks, then the version line.
	window.foot = Tree.Foot(sidebar)
	window.stats = window.foot.stats

	local navScroll = ScrollFrame(sidebar)
	navScroll:SetPoint("TOPLEFT", 8, -(searchTop + 32))
	-- Ends at the foot's top, which rises when the foot links take two rows.
	navScroll:SetPoint("BOTTOMRIGHT", window.foot, "TOPRIGHT", -16, 0)
	-- Hide the bar while everything fits (best effort; the template may re-show it).
	navScroll:HookScript("OnScrollRangeChanged", function(self, _, yRange)
		if self.ScrollBar then self.ScrollBar:SetShown((yRange or 0) > 0) end
	end)
	local navContent = CreateFrame("Frame", nil, navScroll)
	navContent:SetSize(NAV_WIDTH, 1)
	navScroll:SetScrollChild(navContent)
	window.nav = { scroll = navScroll, content = navContent, buttons = {}, headers = {}, captions = {} }
	Tree.LayoutQuick()

	-- Header ----------------------------------------------------------------
	local header = CreateFrame("Frame", nil, window)
	header:SetPoint("TOPLEFT", MAIN_LEFT, -8)
	header:SetPoint("TOPRIGHT", -8, -8)
	header:SetHeight(64)
	Draggable(header)
	window.header = header
	-- The accent line under the title, as on every EldoUI panel.
	window.headerLine = header:CreateTexture(nil, "ARTWORK")
	E:Hairline(window.headerLine, "h", 2)
	window.headerLine:SetPoint("BOTTOMLEFT")
	window.headerLine:SetPoint("BOTTOMRIGHT")
	-- The skin's divider ornament on the line (none on the classic skins).
	window.headerDivider = E:SkinHeaderDivider(window.headerLine)
	-- A soft accent glow behind the page title, fading downward, drawn by
	-- code so it follows the accent.
	window.headerGlow = header:CreateTexture(nil, "BACKGROUND")
	window.headerGlow:SetAllPoints()
	window.headerGlow:SetTexture(E.media.flat)
	Tree.PaintGlow()

	window.title = Text(header, Tree.PAGE_TITLE, "LEFT", TEXT, true)
	window.title:SetPoint("TOPLEFT", 4, -8)
	window.subtitle = Text(header, E.tokens.size.label, "LEFT", SECONDARY)
	window.subtitle:SetPoint("TOPLEFT", window.title, "BOTTOMLEFT", 0, -4)
	window.subtitle:SetWidth(Size.Width() - MAIN_LEFT - 48)
	-- Up to two muted lines; a longer text is cut and shows whole in a
	-- tooltip.
	window.subtitle:SetWordWrap(true)
	window.subtitle:SetMaxLines(Tree.SUBTITLE_LINES)
	local subtitleHit = CreateFrame("Frame", nil, header)
	subtitleHit:SetAllPoints(window.subtitle)
	subtitleHit:SetScript("OnEnter", function(self)
		if not Tree.SubtitleCut() then return end
		E.UIKit.AnchorTooltip(self, GameTooltip)
		E.UIKit.TipTitle(GameTooltip, window.title:GetText() or "")
		E.UIKit.TipText(GameTooltip, window.subtitle:GetText())
		GameTooltip:Show()
	end)
	subtitleHit:SetScript("OnLeave", function() GameTooltip_Hide() end)
	-- Only takes the mouse while the line is cut, so the header still drags.
	subtitleHit:EnableMouse(false)
	window.subtitleHit = subtitleHit

	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -4, -4)
	Skin("SkinCloseButton", close)

	-- Window size: - 100% +, the mouse wheel works on it too.
	local scaleBox = CreateFrame("Frame", nil, header)
	scaleBox:SetSize(92, BUTTON)
	scaleBox:SetPoint("TOPRIGHT", -32, -8)
	scaleBox:EnableMouseWheel(true)
	scaleBox:SetScript("OnMouseWheel", function(_, delta) StepScale(delta > 0 and 1 or -1) end)
	local smaller = Button(scaleBox, "-", BUTTON, BUTTON, function() StepScale(-1) end)
	smaller:SetPoint("LEFT")
	local larger = Button(scaleBox, "+", BUTTON, BUTTON, function() StepScale(1) end)
	larger:SetPoint("RIGHT")
	window.scaleText = Text(scaleBox, E.tokens.size.label, "CENTER", SECONDARY)
	window.scaleText:SetPoint("LEFT", smaller, "RIGHT", 0, 0)
	window.scaleText:SetPoint("RIGHT", larger, "LEFT", 0, 0)
	local scaleTip = L["Scale of this options window, saved for your account. The UI scale stays as it is. The mouse wheel works here too; drag the corner at the bottom right to change its width and height."]
	AddTooltip(smaller, L["Window size"], scaleTip)
	AddTooltip(larger, L["Window size"], scaleTip)
	scaleBox:EnableMouse(true)
	AddTooltip(scaleBox, L["Window size"], scaleTip)
	-- Shown while the size or scale differs from the default.
	-- As wide as its label in the language and font in use.
	window.resetSize = Button(header, L["Reset size"], nil, BUTTON, function() Size.Reset() end)
	window.resetSize:SetPoint("RIGHT", scaleBox, "LEFT", -8, 0)
	AddTooltip(window.resetSize, L["Reset size"], L["Put this window back to its normal size and 100 % scale, in the middle of the screen."])
	window.resetSize:Hide()
	window.scaleBox = scaleBox
	-- A long page title stops before the buttons (a narrow window).
	Tree.FitTitle()

	-- Tab bar and page search ----------------------------------------------
	local tabBar = CreateFrame("Frame", nil, window)
	tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
	tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -4)
	tabBar:SetHeight(E.tokens.height.tab)
	tabBar.buttons = {}
	local tabLine = tabBar:CreateTexture(nil, "ARTWORK")
	tabLine:SetColorTexture(unpack(E.tokens.edge.divider))
	E:Hairline(tabLine, "h", 1)
	tabLine:SetPoint("BOTTOMLEFT")
	tabLine:SetPoint("BOTTOMRIGHT")
	window.tabBar = tabBar

	-- Share: a small menu button at the right end of the tab bar.
	local share = Button(tabBar, L["Share"], Tree.SHARE, BUTTON, function(self) Actions.ShowShareMenu(self) end)
	share:SetPoint("TOPRIGHT", -4, -1)
	local shareArrow = share:CreateTexture(nil, "OVERLAY")
	shareArrow:SetTexture(CHEVRON)
	shareArrow:SetSize(12, 12)
	shareArrow:SetPoint("RIGHT", -6, 0)
	share.text:ClearAllPoints()
	share.text:SetPoint("LEFT", 8, 0)
	share.text:SetPoint("RIGHT", shareArrow, "LEFT", -2, 0)
	-- Wide enough for its label at any text size.
	share:SetWidth(math.max(Tree.SHARE, math.ceil((share.text:GetStringWidth() + 8 + 2 + 12 + 6 + 4) / 4) * 4))
	AddTooltip(share, L["Share"], L["Export this page as a string, import one, export everything, copy a module from another profile, or reset it."])
	window.share = share

	window.pageSearch = SearchBox(tabBar, 180, L["Search this page"], function(text)
		text = strtrim(text or "")
		pageFilter = text ~= "" and text:lower() or nil
		if currentPage and not searching then ShowTab(currentPage.currentTab) end
	end)
	Tree.PlaceShare()
	window.pageSearch:HookScript("OnEscapePressed", function(self)
		if self:GetText() ~= "" then self:SetText("") end
		self:ClearFocus()
	end)

	-- Keys: out of combat, unused keys go on to the game.
	window.keys = E.UIKit.KeyHandler(window, Tree.HandleKey)
	window.focusRing = E.UIKit.FocusRing(window)
	-- Focus for Up, Down and Enter: the tree or the search box.
	window.keyClicks = CreateFrame("Frame", nil, window)
	window.keyClicks:RegisterEvent("GLOBAL_MOUSE_DOWN")
	window.keyClicks:SetScript("OnEvent", function()
		if window:IsShown() then Tree.OnMouseDown() end
	end)
	window.search:HookScript("OnEditFocusGained", function() Tree.SetKeysOn(true) end)
	window:HookScript("OnHide", function() Tree.SetKeysOn(false) end)

	-- Content ----------------------------------------------------------------
	local scroll = ScrollFrame(window)
	scroll:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -8)
	scroll:SetPoint("BOTTOMRIGHT", -32, 52)
	window.scroll = scroll
	window.results = CreateFrame("Frame", nil, scroll)
	window.results:SetSize(1, 1)
	window.results.buttons = {}
	window.results:Hide()
	window.empty = Text(window, E.tokens.size.body, "CENTER", SECONDARY)
	window.empty:SetPoint("TOPLEFT", scroll, "TOPLEFT", 24, -40)
	window.empty:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -24, -40)
	window.empty:SetWordWrap(true)
	window.empty:SetText(L["No settings match."])
	window.empty:Hide()

	-- Footer -----------------------------------------------------------------
	local footerLine = window:CreateTexture(nil, "ARTWORK")
	footerLine:SetColorTexture(unpack(E.tokens.edge.divider))
	E:Hairline(footerLine, "h", 1)
	footerLine:SetPoint("BOTTOMLEFT", MAIN_LEFT, 44)
	footerLine:SetPoint("BOTTOMRIGHT", -12, 44)

	window.reset = Button(window, L["Reset"], 120, BUTTON_LARGE, function()
		if currentPage and currentPage.module then Bulk.ConfirmReset(currentPage.module) end
	end)
	window.reset:SetPoint("BOTTOMLEFT", MAIN_LEFT, 12)
	AddTooltip(window.reset, L["Reset"], L["Put every setting of this module back to its default. Asks first."])
	-- Secure /reload button: Forever blocks ReloadUI() from addon code. It
	-- counts the changes that wait for a reload (UpdateReloadButton).
	window.reload = E:CreateReloadButton(window, L["Reload UI"], 112, BUTTON_LARGE, Reloads.ClearReloads)
	window.reload:SetPoint("LEFT", window.reset, "RIGHT", 8, 0)
	window.reload.pending = false
	window.reload:HookScript("OnEnter", function(self)
		-- In combat the button's own tooltip says why it waits.
		if InCombatLockdown() then return end
		local Kit = E.UIKit
		Kit.AnchorTooltip(self)
		Kit.TipTitle(GameTooltip, L["Reload UI"])
		Kit.TipText(GameTooltip, self.tipText)
		GameTooltip:Show()
	end)
	-- This session's changes with Undo; shown once there is one.
	-- Move mode, right after Reload UI on every page: the same kit button
	-- as the other footer actions, with no secure action of its own. The
	-- window steps aside while frames are dragged and comes back on the
	-- same page after Done (E:CloseConfigForMoveMode).
	window.move = Button(window, L["Move mode"], 112, BUTTON_LARGE, function() Actions.ToggleMoveMode() end)
	window.move:SetPoint("LEFT", window.reload, "RIGHT", 8, 0)
	AddTooltip(window.move, L["Move mode"], L["Unlock every EldoUI frame to drag it into place. This window steps aside until you press Done."])
	window.changes = Button(window, L["Recent changes (%d)"]:format(0), 140, BUTTON_LARGE, function() Recent.ToggleChanges() end)
	window.changes:SetPoint("LEFT", window.move, "RIGHT", 8, 0)
	AddTooltip(window.changes, L["Recent changes"], L["Every setting you changed in this window since the last reload, with Undo for each one or all of them."])
	window.changes:Hide()

	-- Done sits clear of the resize grip in the corner.
	local done = Button(window, L["Done"], 100, BUTTON_LARGE, function() window:Hide() end, true)
	done:SetPoint("BOTTOMRIGHT", -20, 12)
	window.footer = { done = done }

	-- Resize grip: the kit's one grip (E.UIKit.SizeGrip), accent on hover.
	-- The window keeps its own bounds (they follow the window scale) and
	-- saves its size for the account.
	local grip = E.UIKit.SizeGrip(window, {
		resize = true, bounds = false,
		tipTitle = L["Window size"],
		tip = L["Drag to make this window wider, narrower, taller or shorter. Saved for your account; Reset size next to the scale puts it back."],
		onStart = function()
			HideCog()
			HideShareMenu()
		end,
		onStop = function()
			Size.Save()
			Size.Reflow()
		end,
	})
	window.grip = grip
	-- One layering rule with every EldoUI window: a dialog opened from here
	-- (import, export, a question) stays above it, centered on it.
	E.UIKit.Layer(window, { escape = false })
end

-- Re-apply fonts, boxes and accent colors after a theme change (accent,
-- font, outline or skin). Panels follow E:UpdateArtStyle on their own.
local function Restyle()
	if not window then return end
	SkinWindow()
	for fontString, info in pairs(texts) do ApplyTextFont(fontString, info) end
	for frame, info in pairs(boxes) do
		E:SetTemplate(frame, info.transparent)
		if info.tint then frame:SetBackdropColor(unpack(info.tint)) end
	end
	window.headerLine:SetColorTexture(Accent())
	Tree.PaintGlow()
	RepaintButtons()
	-- Restyling put every edge back to E.pixel: snap them to this scale.
	E:SnapBorders(window)
	E:RefreshConfig()
end
-- Once per theme change, through the theme registry (Core/Media.lua).
E:OnThemeChanged("config", Restyle)

-- The config window opens only from /eui, from the EldoUI button in the
-- Game Menu, from the "EldoUI options" button beside Edit Mode, from a
-- box's "Options…" and from the options link, a Ctrl-click on an EldoUI
-- frame bound with E:BindOptionsLink (design decision): no other click on a
-- frame, mover, other menu, data text or other window opens it. Once it is
-- open, its own buttons may switch page. The /eui dispatcher
-- (Core/Commands.lua) runs every command through E:RunFromSlash; the Game
-- Menu button calls E:OpenConfigFromGameMenu, the options link
-- E:OpenConfigFromLink, the Edit Mode panel E:OpenConfigFromEditMode and a
-- box's "Options…" (move mode or on screen) E:OpenConfigFromMoveBox.
local fromSlash = false

function E:RunFromSlash(fn, ...)
	local was = fromSlash
	fromSlash = true
	local ok, err = pcall(fn, ...)
	fromSlash = was
	if not ok then geterrorhandler()(err) end
end

-- May the window open (or switch page) now?
function E:ConfigOpenAllowed()
	return fromSlash or (window ~= nil and window:IsShown())
end

-- The Game Menu's EldoUI button (Modules/SystemUI.lua): opens the window,
-- or brings it up after combat like /eui does.
function E:OpenConfigFromGameMenu()
	self:RunFromSlash(self.ToggleConfig, self, nil, true)
end

-- The options link (Ctrl-click on an EldoUI frame, design decision): the
-- third way in, opened only from that click's handler (E:BindOptionsLink
-- in Core/UIKit.lua). It opens the page of the frame and its row.
function E:OpenConfigFromLink(pageId, key, tabLabel)
	if type(pageId) ~= "string" then return end
	self:RunFromSlash(self.ToggleConfig, self, pageId, true, key, tabLabel)
end

-- Is there a page `pageId` with a row `key` (or a tab `tabLabel`)? For
-- the options links' checks; builds the module pages it needs.
function E:ConfigLinkResolves(pageId, key, tabLabel)
	ModulePages()
	E:RegisterModulesPage()
	E:RegisterPositionsPage()
	for _, page in ipairs(pages) do
		if page.id == pageId then
			if key and not Tree.LinkEntry(page, key) then return false, "no row " .. tostring(key) end
			if tabLabel then
				for _, tab in ipairs(Structure(page)) do
					if tab.label == tabLabel or tab.label == L[tabLabel] then return true end
				end
				return false, "no tab " .. tostring(tabLabel)
			end
			return true
		end
	end
	return false, "no page " .. tostring(pageId)
end

-- One more door (design decision): the "EldoUI options" button on EldoUI's
-- panel beside Blizzard's Edit Mode (Modules/EditMode.lua) opens the Edit
-- Mode page, or brings it up after combat like /eui does.
function E:OpenConfigFromEditMode()
	self:RunFromSlash(self.ToggleConfig, self, "module:EditMode", true)
end

-- One more door (design decision): "Options…" in a box's menu, in move
-- mode or on screen (Core/Hideable.lua), opens that box's module page,
-- scrolled to its row (or on its tab) when it has one.
function E:OpenConfigFromMoveBox(pageId, optionKey, tabLabel)
	if type(pageId) ~= "string" then return end
	self:RunFromSlash(self.ToggleConfig, self, pageId, true, optionKey, tabLabel)
end

-- pageId opens that page; stayOpen keeps an open window open. optionKey
-- (or a string in stayOpen's place) scrolls to that row and flashes it;
-- tabLabel opens a tab by its label.
function E:ToggleConfig(pageId, stayOpen, optionKey, tabLabel)
	if type(stayOpen) == "string" then stayOpen, optionKey = true, stayOpen end
	if not self:ConfigOpenAllowed() then return false end
	if InCombatLockdown() then
		-- Closing is safe in combat (a plain frame); opening and page
		-- builds wait. The queued call never closes the window again.
		local open = window and window:IsShown()
		if open and not pageId then
			if not stayOpen then window:Hide() end
			return
		end
		self:Print(open and L["That page opens after combat."] or L["The config window opens after combat."])
		self:RunOutOfCombat(function() self:RunFromSlash(self.ToggleConfig, self, pageId, true, optionKey, tabLabel) end, "config:open")
		return
	end
	if not window then
		CreateWindow()
		Restyle()
	end
	if window:IsShown() and not pageId then
		if not stayOpen then window:Hide() end
		return
	end
	ModulePages()
	E:RegisterModulesPage()
	E:RegisterPositionsPage()
	if E.RegisterHiddenBoxesPage then E:RegisterHiddenBoxesPage() end
	window:Show()
	suppressSearch = true
	window.search:SetText("")
	suppressSearch = false
	searching = false
	BuildNav()
	UpdateReloadButton()
	Recent.UpdateButton()
	local target = pages[1]
	for _, page in ipairs(pages) do
		if page.id == pageId or (not pageId and currentPage and page.id == currentPage.id) then target = page end
	end
	if target then
		ShowPage(target)
		if (optionKey or tabLabel) and target.id == pageId then Tree.OpenLink(target, optionKey, tabLabel) end
	end
	WarmSearchIndex()
end

-- Open a page on one of its tabs, found by its label (the English text or
-- the shown one). False when the window can't open now or has no such tab.
function E:ShowConfigTab(pageId, label)
	self:ToggleConfig(pageId, true)
	if not (window and window:IsShown() and currentPage and currentPage.id == pageId) then return false end
	for index, tab in ipairs(currentPage.tabs or {}) do
		if tab.label == label or tab.label == L[label] then
			ShowPage(currentPage, index)
			return true
		end
	end
	return false
end

-- The shown row of the option with `key` on the open page `pageId`, or
-- nil (a tour help points at it).
function E:ConfigOptionFrame(pageId, key)
	if not (window and window:IsShown() and currentPage and currentPage.id == pageId) then return nil end
	local tab = Structure(currentPage)[currentPage.currentTab or 1]
	for option, widget in pairs(tab and tab.widgets or {}) do
		if widget and option.key == key and widget:IsVisible() then return widget end
	end
	return nil
end

-- The options window's frame while it is shown, else nil.
function E:ConfigWindowFrame()
	return window and window:IsShown() and window or nil
end

-- Re-read every widget, e.g. after a profile or layout switch.
function E:RefreshConfig()
	if not (window and window:IsShown()) then return end
	UpdateNav()
	UpdateReloadButton()
	if searching then
		ShowResults(window.search:GetText())
	elseif currentPage then
		UpdateHeader(currentPage)
		ShowTab(currentPage.currentTab, true)
	end
end

-- Open the window with the global search filled in (/eui search <text>).
function E:SearchConfig(text)
	text = strtrim(text or "")
	if InCombatLockdown() then
		if not self:ConfigOpenAllowed() then return end
		self:Print(L["The config window opens after combat."])
		self:RunOutOfCombat(function() self:RunFromSlash(self.SearchConfig, self, text) end, "config:open")
		return
	end
	self:ToggleConfig(nil, true)
	if not (window and window:IsShown()) or #text < 2 then return end
	suppressSearch = true
	window.search:SetText(text)
	suppressSearch = false
	ShowResults(text)
end

---------------------------------------------------------------------------
-- Built-in pages: General, Layouts and Profiles
---------------------------------------------------------------------------
-- Its own block: these locals are freed after it (the chunk has room
-- for 200).
do
	-- Live preview of the theme on the General page: a panel in the art
	-- style with the header font, body text, a bar in the bar texture and a
	-- selected tab (both with the thin frame line under WoW Forever).
	local function CreateLookPreview(frame)
		if not frame then return end
		local panel = CreateFrame("Frame", nil, frame)
		panel:SetSize(300, 72)
		panel:SetPoint("LEFT", 4, 0)
		frame.panel = panel
		frame.title = E:CreateText(panel, E.tokens.size.dialogTitle, "LEFT")
		frame.title:SetPoint("TOPLEFT", 10, -8)
		frame.title:SetText("EldoUI") -- no-L: addon name
		frame.body = E:CreateText(panel, E.tokens.size.body, "LEFT")
		frame.body:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -4)
		frame.body:SetText(L["Body text in your font and size."])
		frame.secondary = E:CreateText(panel, E.tokens.size.small, "LEFT")
		frame.secondary:SetPoint("TOPLEFT", frame.body, "BOTTOMLEFT", 0, -3)
		frame.secondary:SetText(L["Secondary text: times, counts, hints"])
		frame.secondary:SetTextColor(unpack(SECONDARY))
		frame.bar = E:CreateStatusBar(frame)
		frame.bar:SetSize(260, 16)
		frame.bar:SetPoint("LEFT", panel, "RIGHT", 24, 10)
		frame.bar:SetMinMaxValues(0, 100)
		frame.bar:SetValue(65)
		frame.barText = E:CreateText(frame.bar, E.tokens.size.small, "CENTER")
		frame.barText:SetPoint("CENTER")
		frame.barText:SetText("65 / 100")
		frame.box = CreateFrame("Frame", nil, frame)
		frame.box:SetSize(260, 20)
		frame.box:SetPoint("TOPLEFT", frame.bar, "BOTTOMLEFT", 0, -10)
		frame.boxText = E:CreateText(frame.box, E.tokens.size.label, "CENTER")
		frame.boxText:SetPoint("CENTER")
		frame.boxText:SetText(L["Selected"])
	end

	local function UpdateLookPreview(frame, settings)
		if not (frame and frame.panel and settings) then return end
		E:SetPanelTemplate(frame.panel)
		E:SetHeaderFont(frame.title, E.tokens.size.dialogTitle, settings.fontOutline or "")
		frame.title:SetTextColor(E:TokenColor("accent"))
		local bodySize = settings.fontSize or E.tokens.size.body
		E:SetFont(frame.body, bodySize)
		E:SetFont(frame.secondary, math.max(9, bodySize - (E.tokens.size.body - E.tokens.size.small)))
		E:SetFont(frame.barText, E.tokens.size.small)
		E:SetFont(frame.boxText, E.tokens.size.label)
		frame.bar:SetStatusBarTexture(E.media.statusbar)
		frame.bar:SetStatusBarColor(Accent())
		E:SetTemplate(frame.box)
		frame.box:SetBackdropBorderColor(Accent())
		frame.box:SetBackdropColor(Accent(0.25))
		-- A skin with a tab fill (WoW Forever, the native skins): the selected tab look.
		if E:SkinFlag("selectedTabTint") then frame.box:SetBackdropColor(E:SelectedTabColor()) end
		E:SetStyleEdge(frame.box)
		E:SetStyleEdge(frame.bar.bg)
	end

	local generalOptions = {
		{ type = "preview", label = "Preview", height = 92, create = CreateLookPreview, update = UpdateLookPreview },
		{ type = "header", label = "Look" },
		{ type = "select", key = "accent", label = "Accent color",
			desc = "Used for highlights, the EldoUI name and cast bars. Layout presets set their own.",
			values = E.accentNames },
		{ type = "color", key = "accentCustom", label = "Custom color", desc = "The accent when Accent color is set to Custom color.",
			hidden = function() return E.db.general.accent ~= "custom" end },
		{ type = "range", key = "panelAlpha", label = "Panel opacity", min = E.tokens.panel.minAlpha, max = 1, step = 0.02, percent = true,
			desc = "How solid EldoUI's panels on the screen are, such as chat, tooltips and meters. Windows are always solid. See-through panels never drop below 80%, so their text stays readable." },
		-- The skin and the look of each part have their own page.
		{ type = "execute", label = "Open Appearance", keywords = "skin art style theme look frames",
			desc = function()
				local info = E.artStyleInfo[E:ArtStyle()]
				return L["Now: %s. The skin of every window, bar and frame, and of each part on its own."]:format(info and L[info.title] or E:ArtStyle())
			end,
			func = function() E:ToggleConfig("appearance", true) end },
		-- Fonts and textures live on their own pages, once each.
		{ type = "execute", label = "Open Fonts and text", desc = "The EldoUI font, text size, outline and shadow, number styles and the fonts of each module.",
			func = function() E:ToggleConfig("fonts") end },
		{ type = "execute", label = "Open Textures", desc = "The bar texture, smooth bars and the textures of each module.",
			func = function() E:ToggleConfig("textures") end },
		{ type = "toggle", key = "animations", label = "Animations",
			desc = "Windows and toasts slide and fade in, glows move and switches change softly. Off shows every change at once and holds glows still, like Reduce motion on the Accessibility page." },
		-- Account-wide (E.global.locale, see the page target below).
		{ type = "header", label = "Language" },
		{ type = "select", key = "locale.language", label = "EldoUI language", reload = true,
			keywords = "dansk danish english sprog translation",
			desc = "Language of EldoUI's own texts: settings, windows, tooltips and chat messages. The game's own texts keep the game's language. EldoUI builds its windows once, so the change shows after a reload.",
			values = function() return (E:LanguageChoices()) end,
			order = function() return select(2, E:LanguageChoices()) end,
			valueIcons = function(code) return E:LocaleFlag(code) end },
		{ type = "header", label = "Lua errors" },
		{ type = "select", key = "errorPopup", label = "Game error window",
			desc = "The game's own Lua error window, which pops up on every error until you close it. Hide keeps it closed; EldoUI still logs every error in /eui errors. Don't touch leaves the game's setting as it is.",
			values = { HIDE = "Hide", SHOW = "Show", KEEP = "Don't touch" }, order = { "HIDE", "SHOW", "KEEP" } },
		{ type = "header", label = "Sound" },
		{ type = "select", key = "soundChannel", label = "Sound channel",
			desc = "Volume channel for EldoUI's sounds (Fanfare and modules set to Default). Master plays even with game sound effects off.",
			values = function() return E.soundChannels end },
		{ type = "toggle", key = "soundMute", label = "Mute EldoUI sounds",
			desc = "Silences every sound EldoUI plays through its media library. The game's own sounds are not affected." },
		-- Shared by every module that shows them (Info Bar, Minimap, the
		-- character window, the ready report, ...): set once, here.
		{ type = "header", label = "Clock and durability" },
		{ type = "select", key = "clock24", label = "Clock format", keywords = "24-hour 12-hour time am pm",
			desc = "How every EldoUI clock writes the time: the Info Bar, the minimap clock, journals and logs. Game setting follows the game's own 24-hour clock option.",
			values = { game = "Game setting", ["24"] = "24-hour (18:30)", ["12"] = "12-hour (6:30 PM)" }, order = { "game", "24", "12" } },
		{ type = "range", key = "durabilityWarn", label = "Worn gear at", unit = "%", min = 10, max = 90, step = 5, keywords = "durability repair yellow",
			desc = "Gear at or below this durability shows as worn (yellow) everywhere EldoUI shows durability: the Info Bar, the character window, the ready report and the reminders." },
		{ type = "range", key = "durabilityLow", label = "Low durability at", unit = "%", min = 0, max = 50, step = 5, keywords = "durability repair red",
			desc = "Gear at or below this durability shows as low (red) everywhere EldoUI shows durability." },
		{ type = "header", label = "Scale" },
		{ type = "select", key = "uiScale", label = "UI scale",
			-- Every choice in the list says how it suits the layouts (E:ScaleAdvice).
			desc = "Auto makes every screen 1440 UI units tall, so layouts look as designed on any screen. Pixel perfect makes one UI unit one pixel; frames keep their 1440p size and can overlap on a smaller screen.",
			values = function()
				local marks = { recommended = L["%s (recommended)"], supported = L["%s (supported)"], small = L["%s (not recommended)"], large = L["%s (not recommended)"] }
				local function Label(value, title)
					local tier = E:ScaleAdvice(value)
					return tier and marks[tier]:format(title) or title
				end
				local values = { auto = L["Auto: 1440p (recommended)"], pixel = Label("pixel", L["Pixel perfect for this screen (%.2f)"]:format(E:GetPixelPerfectScale())) }
				for _, value in ipairs({ 0.45, 0.5, 0.58, 0.64, 0.71, 0.8, 1 }) do values[value] = Label(value, ("%.2f"):format(value)) end
				local own = E.db.general.uiScale
				if type(own) == "number" and not values[own] then values[own] = Label(own, ("%.2f"):format(own)) end
				-- Already in the player's language.
				return E:RawValues(values)
			end },
		{ type = "toggle", key = "layoutFit", label = "Fit layouts to the screen height",
			desc = "Layouts are made for a 1440 px tall screen. On scales their positions to your screen height; off uses them as they are. Frames you dragged are never scaled.",
			-- Auto is the 1440-unit canvas: nothing to fit (E:GetLayoutRatio).
			hidden = function() return E.db.general.uiScale == "auto" end },
		{ type = "header", label = "Move mode" },
		{ type = "range", key = "gridSize", label = "Grid size", min = 4, max = 128, step = 4, unit = "px",
			desc = "Distance between the grid lines in move mode. Frames snap to the grid when Snap is on." },
		{ type = "select", key = "gridColor", label = "Grid color",
			desc = "Color of the grid lines in move mode. The two center lines use the accent color (white when the grid itself is in the accent color).",
			values = { black = "Black", white = "White", accent = "Accent color" } },
		{ type = "range", key = "gridAlpha", label = "Grid opacity", min = 0.1, max = 1, step = 0.05, percent = true,
			desc = "How strongly the grid lines show in move mode." },
		{ type = "range", key = "gridThickness", label = "Grid line width", min = 1, max = 4, step = 1, unit = "px",
			desc = "Width of the grid lines in screen pixels." },
		{ type = "toggle", key = "snap", label = "Snap frames",
			desc = "Dragged frames snap to the grid, to the edges and centers of other frames and to the screen center. Hold Alt while dragging to place a frame freely." },
		{ type = "toggle", key = "moverGuides", label = "Alignment guides",
			desc = "While you drag a frame, lines show where its edges or center line up with another frame or the screen center." },
		{ type = "header", label = "Chat messages" },
		{ type = "toggle", key = "welcome", label = "Show the welcome message at login",
			desc = "One line in chat at login with the EldoUI version and how to open these settings." },
		{ type = "header", label = "Setup" },
		{ type = "execute", label = "Run the installer", desc = "Walk through layout, style and addon setup again.",
			func = function()
				if window then
					window.quietHide = true
					window:Hide()
				end
				E:ShowInstaller()
			end },
		{ type = "toggle", key = "installerRemind", label = "Setup reminders", keywords = "installer remind setup",
			desc = "While the setup is not finished: one chat line per login and a small alert. Off: the setup no longer opens by itself; /eui install still opens it." },
		-- Account-wide (E.global.tourHelps, see the page target below).
		{ type = "toggle", key = "tours.enabled", label = "Tour helps", keywords = "tour help hint tip first time explain",
			desc = "Small helps that explain something new once, the first time you meet it. Off: no tour help shows anywhere in EldoUI; /eui tour still shows one when you ask." },
		{ type = "execute", label = "Show tour helps again", keywords = "tour help reset",
			desc = "Every tour help shows once more, the next time its place comes up. /eui tour lists them.",
			func = function()
				E.Tour:Reset()
				E:ConfigNotice(L["Every tour help shows again, once, the next time its place comes up."])
			end },
	}

	local function LayoutOptions()
		local options = {
			{ type = "description", label = "Click a layout to move every EldoUI frame into place. Frames you dragged yourself stay where you put them." },
		}
		-- The layout picker (Core/Overview.lua): the families, the legacy
		-- layouts a profile still uses, then My layouts.
		table.insert(options, E.Overview.PickerOption("layouts"))
		table.insert(options, { type = "header", label = "Frames" })
		table.insert(options, { type = "execute", label = "Move mode", desc = "Unlock EldoUI's frames so you can drag them. It opens on your fight screen (Combat mode); pick All frames or a group on the move panel for the rest. Done in move mode brings this window back.",
			func = function() E:ToggleMoveMode() end })
		table.insert(options, { type = "execute", label = "Reset dragged frames", desc = "Put every frame you dragged back where the current layout puts it.",
			func = function() E:ConfirmResetMovers() end })
		-- Gamepad Mode UI (Core/GamepadMode.lua): the profile's two switches,
		-- the game's Controller settings, Restore now and the controller
		-- spells. The switch to the game's gamepad interface stays the
		-- player's own, in the game's settings.
		local function GamepadStatus()
			if E:GamepadModeActive() then return L["On"] end
			if E.db.gamepadUI and E.db.gamepadUI.always then return L["Ready"] end
			return L["Off"]
		end
		table.insert(options, { type = "header", label = "Gamepad Mode UI", status = GamepadStatus,
			keywords = "gamepad controller pad console radial" })
		table.insert(options, { type = "description", label = function()
			local text
			if E:GamepadModeActive() then
				text = L["On: EldoUI's frames are placed for controller play while the game's gamepad interface is on."]
			elseif E.db.gamepadUI and E.db.gamepadUI.always then
				text = L["Ready: it starts when you turn on the game's gamepad interface in the game's Controller settings."]
			else
				text = L["Places your frames above the game's controller bar, clear of its radial menu. Normal layouts and moved frames stay saved."]
			end
			return text
		end })
		table.insert(options, { type = "description", hidden = function()
			local _, title = E:ControllerAddon()
			return not title
		end, label = function()
			local _, title = E:ControllerAddon()
			return title and L["%s binds your controller's buttons, so EldoUI only places its frames."]:format(title) or ""
		end })
		table.insert(options, { type = "toggle", key = "gamepadUI.always", label = "Use Gamepad Mode UI",
			keywords = "gamepad controller layout",
			desc = "Places your frames for controller play while the game's gamepad interface is on. Your layout and dragged frames return when it is off. EldoUI never switches the game's interface." })
		table.insert(options, { type = "toggle", key = "gamepadUI.ask", label = "Ask when I start using a controller",
			keywords = "gamepad controller question",
			desc = "When the game notices a controller, EldoUI asks once whether to place its frames for controller play. Nothing changes until you choose.",
			hidden = function() return E.db.gamepadUI and E.db.gamepadUI.always end })
		table.insert(options, { type = "execute", label = "Open controller settings", keywords = "gamepad controller interface",
			desc = "Opens the game's Controller settings, where you turn the game's gamepad interface on or off.",
			hidden = function() return E:GamepadUIActive() end,
			func = function() E:OpenControllerSettings() end })
		table.insert(options, { type = "execute", label = "Restore now", keywords = "gamepad edit mode layout modern",
			desc = "Switches Edit Mode back to the layout you used before the game set it to Modern, out of combat.",
			hidden = function() return E:GamepadReturn() == nil end,
			func = function() E:RestoreGamepadReturn() end })
		table.insert(options, { type = "execute", label = "Controller spells", keywords = "gamepad controller spells bars buttons",
			desc = "Opens the Key sets window on its Controller view: where your role's spells go on the game's controller bars. You see every change first, and nothing is placed until you choose Apply.",
			func = function() E:OpenKeysAndSpells(nil, { view = "controller" }) end })
		-- The settings panel's "Layouts and styles" button lands here.
		table.insert(options, { type = "header", label = "Styles" })
		table.insert(options, { type = "execute", label = "Style presets", desc = "One look per part of the UI (bars, unit frames, minimap and more). A style that makes a frame bigger moves its neighbors to make room, and a style that doesn't fit this layout is grayed out.",
			func = function() E:ToggleConfig("styles") end })
		return options
	end

	local fittedLayout -- layoutFit as last applied by the General page

	-- The EldoUI language choices: English (US) and every complete
	-- translation (Dansk), plus the game's own language when EldoUI has texts
	-- in it (a German client keeps its German Loot Guide), and a language
	-- the player picked earlier.
	-- Names stay in their own language. Returns the choices and their order.
	function E:LanguageChoices()
		local values = E:RawValues({ enUS = "English (US)" })
		local order = { "enUS" }
		local available = {}
		for _, code in ipairs(E:AvailableLanguages()) do available[code] = true end
		-- Every complete translation: each installed language pack (a pack
		-- ships only when it is complete, so it is listed before it loads),
		-- and a translation that marks itself in E.completeLanguages.
		local complete, listed = {}, {}
		local function Add(code)
			if available[code] and code ~= "enUS" and not listed[code] then
				listed[code] = true
				complete[#complete + 1] = code
			end
		end
		for code in pairs(E:LocalePacks()) do Add(code) end
		for code in pairs(E.completeLanguages or {}) do Add(code) end
		table.sort(complete)
		for _, code in ipairs(complete) do
			values[code] = E.localeNames[code] or code
			order[#order + 1] = code
		end
		local client, saved = GetLocale(), E.global and E.global.locale and E.global.locale.language
		for _, code in ipairs({ client, saved }) do
			if type(code) == "string" and available[code] and not values[code] then
				values[code] = E.localeNames[code] or code
				table.insert(order, code)
			end
		end
		return values, order
	end

	-- Earlier versions saved "auto" (the game's language). It becomes the
	-- language it already showed, so nothing changes on screen.
	function E:SettleLanguageChoice()
		local locale = E.global and E.global.locale
		if not locale then return end
		local code = locale.language
		if code == nil or code == "" or code == "auto" then
			code = GetLocale()
			if code == "enGB" then code = "enUS" end
		end
		if not E:LanguageChoices()[code] then code = "enUS" end
		locale.language = code
	end

	-- The General page edits the profile's general settings, the
	-- account-wide language under `locale` and the tour helps switch under
	-- `tours`.
	local generalTarget = setmetatable({}, {
		__index = function(_, key)
			if key == "locale" then return E.global and E.global.locale end
			if key == "tours" then return E:GetGlobal("tourHelps") end
			return E.db.general[key]
		end,
		__newindex = function(_, key, value) E.db.general[key] = value end,
	})

	E:RegisterEvent("PLAYER_LOGIN", function()
		E:SettleLanguageChoice()
		fittedLayout = E.db.general.layoutFit
		-- Character names (Core/Names.lua) go before the chat messages.
		if E.NameOptionRows and not generalOptions.names then
			generalOptions.names = true
			local at = #generalOptions + 1
			for index, option in ipairs(generalOptions) do
				if option.type == "header" and option.label == "Chat messages" then at = index break end
			end
			for offset, row in ipairs(E:NameOptionRows()) do table.insert(generalOptions, at + offset - 1, row) end
		end
		local general = E:RegisterConfigPage("general", "General", generalOptions,
			function() return generalTarget end,
			function()
				E:KeepDurabilityOrder()
				E:RefreshTheme()
				E:ApplyScale()
				-- Layout fit changes where the layout points land.
				if fittedLayout ~= E.db.general.layoutFit then
					fittedLayout = E.db.general.layoutFit
					E:RefreshMovers()
				end
				if E.RefreshNames then E:RefreshNames() end
				if E.RefreshMoveModeLook then E:RefreshMoveModeLook() end
				if E.MotionChanged then E:MotionChanged() end
				if E.errors and E.errors.ApplyPopup then E.errors:ApplyPopup() end
				Tree.LayoutQuick()
			end, 1)
		general.defaults = function() return E.defaults.general end
		local layouts = E:RegisterConfigPage("layouts", "Layouts", LayoutOptions(),
			function() return E.db end, function() E:GamepadSettingsChanged() end, 2)
		layouts.defaults = function() return E.defaults end
		-- The Profiles page comes from Core/Share.lua (registered at ADDON_LOADED).
	end, {}, "pages")
end

---------------------------------------------------------------------------
-- What's New: a page fed from E.whatsNew (Data/WhatsNew.lua) and a
-- one-time "EldoUI was updated" note for players who had EldoUI before.
-- The entry's date, summary and lines are English keys, translated where
-- they are drawn.
---------------------------------------------------------------------------
-- Its own block: these locals are freed after it (the chunk has room
-- for 200).
do
	local updateNote

	local function NewestNotes()
		return type(E.whatsNew) == "table" and E.whatsNew[1] or nil
	end

	local function Bullets(items, limit)
		local lines = {}
		for index, item in ipairs(items or {}) do
			if limit and index > limit then
				table.insert(lines, GREY .. L["...and %d more on the What's New page."]:format(#items - limit) .. "|r")
				break
			end
			table.insert(lines, "\226\128\162 " .. L[item])
		end
		return table.concat(lines, "\n")
	end

	function E:ShowUpdateNote()
		local notes = NewestNotes()
		if not notes then return end
		if not updateNote then
			-- The shared dialog shell (E.UIKit.CreateDialog): title, accent
			-- line, text and a centered button row; Escape closes it.
			local frame = E.UIKit.CreateDialog("EldoUIUpdateNote", { width = 460, strata = "DIALOG",
				title = L["EldoUI was updated"],
				check = { label = L["Never show again, even after updates"],
					desc = L["Turns the note off for good. The switch on the What's new page turns it back on."] },
				buttons = {
					-- The player asked for the page: the same as typing /eui whatsnew.
					{ L["See what's new"], function() E:RunFromSlash(E.ToggleConfig, E, "whatsnew", true) end, kind = "primary" },
					{ L["Close"] },
				} })
			frame.version = E.UIKit.Text(frame, E.tokens.size.label, "RIGHT", "secondary")
			frame.version:SetPoint("TOPRIGHT", -16, -16)
			frame.open, frame.close = frame.buttons[1], frame.buttons[2]
			-- Seen once it closes, however it closes; ticked, no note again.
			frame:HookScript("OnHide", function(note)
				local db = WindowDB()
				db.seenVersion = E.version
				if note.check:GetChecked() then
					db.updatePopup = false
					if E.RefreshConfig then E:RefreshConfig() end
				end
			end)
			updateNote = frame
		end
		local frame = updateNote
		frame:SetTitle(L["EldoUI was updated"])
		frame.check:SetLabel(L["Never show again, even after updates"])
		E.UIKit.Tooltip(frame.check, L["Never show again, even after updates"],
			L["Turns the note off for good. The switch on the What's new page turns it back on."])
		frame.open:SetText(L["See what's new"])
		frame.close:SetText(L["Close"])
		E.UIKit.FitButton(frame.open, E.UIKit.DIALOG_BUTTON)
		E.UIKit.FitButton(frame.close, E.UIKit.DIALOG_BUTTON)
		frame:SetButtonFrames(frame.buttons)
		frame.check:SetChecked(false)
		frame.version:SetText(L["Version %s"]:format(notes.version))
		-- The summary in body text, then up to four changes, dimmer.
		local summary = notes.summary and L[notes.summary] or ""
		local bullets = Bullets(notes.items, 4)
		frame:SetText(summary ~= "" and (summary .. "\n\n" .. GREY .. bullets .. "|r") or bullets)
		-- Seen as soon as it shows: a reload or a crash while it is open
		-- does not bring it back.
		WindowDB().seenVersion = E.version
		frame:Show()
	end

	-- Once per version, a few seconds after login, out of combat and not over
	-- the installer. A brand-new install starts with this version as seen.
	-- Only a saved older version brings the note: when the
	-- beta loses saved variables (all of them, or only this window's), the
	-- player is not shown it again on every login.
	-- Fork (WoW-UI-Addon): its versions carry a mark, "0.7.2001-p1"; the notes
	-- belong to the EldoUI release in front of it, and a new mark on the same
	-- release brings no note.
	local function Release(version)
		return type(version) == "string" and version:match("^(.-)%-p%d+$") or version
	end
	local function CheckUpdateNote()
		local db = WindowDB()
		local notes = NewestNotes()
		if not notes or E.version == "dev" or db.seenVersion == E.version then return end
		if db.seenVersion == nil or Release(db.seenVersion) == Release(E.version) then
			db.seenVersion = E.version
			return
		end
		if notes.version ~= Release(E.version) or db.updatePopup == false then
			db.seenVersion = E.version
			return
		end
		C_Timer.After(6, function()
			E:RunOutOfCombat(function()
				local installer = _G.EldoUIInstaller
				if installer and installer:IsShown() then return end
				E:ShowUpdateNote()
			end)
		end)
	end

	E.CheckUpdateNote = CheckUpdateNote -- exposed for inspection

	local function WhatsNewOptions()
		local options = {
			{ type = "toggle", key = "updatePopup", label = "Show a short note after an update",
				desc = "Once per new EldoUI version, a small window lists the main changes. Saved for your account." },
			{ type = "execute", label = "Show the update note", desc = "Open the short update note for this version again.",
				testSafe = true, func = function() E:ShowUpdateNote() end },
		}
		for _, notes in ipairs(E.whatsNew or {}) do
			-- The date is the header's secondary status text, the same on
			-- every version, translated where it is drawn.
			table.insert(options, { type = "header", label = L["Version %s"]:format(notes.version),
				status = function() return notes.date and L[notes.date] or "" end })
			if notes.summary then table.insert(options, { type = "description", label = notes.summary }) end
			-- Translated line by line where it is drawn: the joined list is no key.
			table.insert(options, { type = "description", label = function() return Bullets(notes.items) end })
		end
		return options
	end

	E:RegisterEvent("PLAYER_LOGIN", function()
		local db = WindowDB()
		if db.updatePopup == nil then db.updatePopup = true end
		local page = E:RegisterConfigPage("whatsnew", "What's new", WhatsNewOptions(), WindowDB, function() end, 97)
		page.defaults = function() return { updatePopup = true } end
		CheckUpdateNote()
	end, {}, "modules")
end

---------------------------------------------------------------------------
-- Thanks: the people who helped build EldoUI (Contributors), then the
-- people who stand behind it (Supporters), from E.thanks (Data/Thanks.lua).
-- A quiet page in the sidebar foot with no setting on it: a thank-you, never
-- a request, a link or a perk. The names come sorted; each group draws its
-- names in columns that fit the page width and the text size, in the name
-- font, so names in other alphabets keep their letters. A group without
-- names is left out.
---------------------------------------------------------------------------
do
	local GAP_X, GAP_Y = 24, 4
	local GROUPS = {
		{ key = "contributors", label = E.Key("Contributors"),
			line = E.Key("Thank you for the code, research and testing that went into EldoUI.") },
		{ key = "supporters", label = E.Key("Supporters"),
			line = E.Key("Thank you for standing behind EldoUI.") },
	}
	local proxy = {}

	local function Names(key)
		local list = type(E.thanks) == "table" and E.thanks[key]
		return type(list) == "table" and list or {}
	end

	function Tree.ThanksCount()
		local count = 0
		for _, group in ipairs(GROUPS) do count = count + #Names(group.key) end
		return count
	end

	-- Columns, top to bottom, then left to right, as wide as the widest
	-- name; a name wider than the page wraps in a single column. Returns
	-- the height the names take.
	local function LayoutNames(canvas, width, names)
		-- Asked before the page is drawn (no canvas yet): a rough height.
		if not canvas then return #names > 0 and 20 or 0 end
		width = width or 400
		canvas.names = canvas.names or {}
		local pool, widest = canvas.names, 0
		for index, name in ipairs(names) do
			local text = pool[index]
			if not text then
				text = Text(canvas, E.tokens.size.body, "LEFT", TEXT)
				E:UseNameFont(text)
				text:SetWordWrap(true)
				pool[index] = text
			end
			text:SetText(tostring(name))
			text:Show()
			local own = text.GetUnboundedStringWidth and text:GetUnboundedStringWidth() or text:GetStringWidth()
			widest = math.max(widest, math.ceil(own or 0))
		end
		for index = #names + 1, #pool do pool[index]:Hide() end
		if #names == 0 then return 0 end
		local columns = math.max(1, math.min(#names, math.floor((width + GAP_X) / (widest + GAP_X))))
		local columnWidth = math.floor((width - GAP_X * (columns - 1)) / columns)
		local rows = math.ceil(#names / columns)
		local rowHeight = {}
		for index = 1, #names do
			local text, row = pool[index], (index - 1) % rows + 1
			text:SetWidth(columnWidth)
			rowHeight[row] = math.max(rowHeight[row] or 0, math.ceil(text:GetStringHeight() or 0))
		end
		local top, rowTop = 0, {}
		for row = 1, rows do
			rowTop[row] = top
			top = top + rowHeight[row] + (row < rows and GAP_Y or 0)
		end
		for index = 1, #names do
			local text = pool[index]
			local column, row = math.floor((index - 1) / rows), (index - 1) % rows + 1
			text:ClearAllPoints()
			text:SetPoint("TOPLEFT", canvas, "TOPLEFT", column * (columnWidth + GAP_X), -rowTop[row])
		end
		return top
	end

	local function ThanksOptions()
		local options = {}
		for _, group in ipairs(GROUPS) do
			local key = group.key
			local function Empty() return #Names(key) == 0 end
			table.insert(options, { type = "header", label = group.label, hidden = Empty })
			table.insert(options, { type = "description", label = group.line, tone = "body", hidden = Empty })
			table.insert(options, { type = "preview", label = group.label, noCaption = true, hidden = Empty,
				height = function(canvas, width) return LayoutNames(canvas, width, Names(key)) end })
		end
		table.insert(options, { type = "description",
			label = "EldoUI also builds on open-source work; its credits are in the file THIRD_PARTY_NOTICES.md in the EldoUI folder." })
		return options
	end

	E:RegisterEvent("PLAYER_LOGIN", function()
		E:RegisterConfigPage("thanks", "Thanks", ThanksOptions(), function() return proxy end, function() end, 98)
	end, {}, "modules")
end

---------------------------------------------------------------------------
-- Positions: X/Y sliders and an anchor for every movable frame
---------------------------------------------------------------------------
-- Its own block: these locals are freed after it (the chunk has room
-- for 200).
do
	local POINTS = {
		TOPLEFT = "Top left", TOP = "Top", TOPRIGHT = "Top right",
		LEFT = "Left", CENTER = "Center", RIGHT = "Right",
		BOTTOMLEFT = "Bottom left", BOTTOM = "Bottom", BOTTOMRIGHT = "Bottom right",
	}
	local positionProxy = {}

	local function PositionTarget()
		for name, mover in pairs(E.movers) do
			local pos = E.db.movers[name] or E:GetLayoutPoint(name) or mover.defaultPoint
			positionProxy[name] = { point = pos[1], x = pos[4], y = pos[5] }
		end
		return positionProxy
	end

	local function PositionRefresh()
		for name, values in pairs(positionProxy) do
			local saved = E.db.movers[name]
			local pos = saved or E:GetLayoutPoint(name) or (E.movers[name] and E.movers[name].defaultPoint)
			if pos and (values.point ~= pos[1] or values.x ~= pos[4] or values.y ~= pos[5]) then
				local x, y = values.x, values.y
				-- A new anchor keeps the frame where it is: the offsets are
				-- measured again from that point.
				if values.point ~= pos[1] then
					local mx, my = E:MoverOffsetsFor(name, values.point)
					if mx then x, y = mx, my end
					values.x, values.y = x, y
				end
				-- Exact numbers place the frame on the screen, so it is no
				-- longer attached to another frame.
				if type(saved) == "table" and type(saved.link) == "table" then
					E:ConfigNotice(L["%s is no longer attached to another frame."]:format(L[E.movers[name].title]))
				end
				E.db.movers[name] = { values.point, "UIParent", values.point, x, y }
			end
		end
		E:RefreshMovers()
	end

	-- The movers and screen size the rows were made for: a frame made later
	-- (a module switched on, a window loaded on demand) or a new screen size
	-- builds the rows again.
	local builtFor

	-- The module that owns a mover, while that module is off (nil when it
	-- is on, or the mover belongs to no module).
	local function ModuleOff(mover)
		local module = mover.module and E.modules[mover.module]
		if module and not module.active then return module end
		return nil
	end

	function E:RegisterPositionsPage()
		local names = {}
		for name in pairs(self.movers) do table.insert(names, name) end
		if #names == 0 then return end
		table.sort(names)
		local states = {}
		for i, name in ipairs(names) do states[i] = ModuleOff(self.movers[name]) and "0" or "1" end
		local signature = table.concat(names, ",") .. "#" .. table.concat(states)
			.. ("@%dx%d"):format(math.floor(UIParent:GetWidth() or 0), math.floor(UIParent:GetHeight() or 0))
		if signature == builtFor then return end
		-- One tab per move-mode group, in move mode's order; the frames of a
		-- group sorted by title inside it.
		local byGroup = {}
		for _, name in ipairs(names) do
			local group = self:GetMoverGroup(name) or "Other"
			byGroup[group] = byGroup[group] or {}
			table.insert(byGroup[group], name)
		end
		local order = {}
		for _, group in ipairs(self.moverGroups) do order[#order + 1] = group end
		for group in pairs(byGroup) do
			if not tContains(order, group) then order[#order + 1] = group end
		end
		local w, h = UIParent:GetSize()
		local options = {
			{ type = "description", label = "Exact positions for every EldoUI frame, measured from the anchor point. Move mode (drag with snapping) changes the same values." },
			{ type = "execute", label = "Move mode", desc = "Unlock EldoUI's frames so you can drag them. It opens on your fight screen (Combat mode); pick All frames or a group on the move panel for the rest. Done in move mode brings this window back.", func = function() E:ToggleMoveMode() end },
		}
		local first = true
		for _, group in ipairs(order) do
			local list = byGroup[group]
			if list then
				table.sort(list, function(a, b) return self.movers[a].title < self.movers[b].title end)
				-- The intro and the Move mode button sit on the first tab.
				if first then
					table.insert(options, 1, { type = "tab", label = group })
					first = false
				else
					table.insert(options, { type = "tab", label = group })
				end
				for _, name in ipairs(list) do
					local mover = self.movers[name]
					local title = mover.title
					-- A frame of a module that is off stays listed, grayed, and
					-- says why.
					local function Off()
						local module = ModuleOff(mover)
						return module and L["Turn on the %s module first."]:format(L[module.title or module.name]) or nil
					end
					table.insert(options, { type = "header", label = title })
					table.insert(options, { type = "select", key = name .. ".point", label = "Anchor", values = POINTS, disabled = Off,
						desc = L["The point of the screen %s is measured from."]:format(L[title]) })
					table.insert(options, { type = "range", key = name .. ".x", label = "X", min = -math.ceil(w), max = math.ceil(w), step = 1, disabled = Off,
						desc = "Distance from the anchor to the right (negative: to the left)." })
					table.insert(options, { type = "range", key = name .. ".y", label = "Y", min = -math.ceil(h), max = math.ceil(h), step = 1, disabled = Off,
						desc = "Distance from the anchor upwards (negative: down)." })
				end
			end
		end
		local page = self:RegisterConfigPage("positions", "Positions", options, PositionTarget, PositionRefresh, 3)
		if builtFor and page.options ~= options then
			page.options = options
			page.tabs = nil
		end
		builtFor = signature
	end
end

---------------------------------------------------------------------------
-- Modules: switch each part of EldoUI on or off
---------------------------------------------------------------------------
-- Its own block: these locals are freed after it (the chunk has room
-- for 200).
do
	local moduleProxy = {}

	function E:RegisterModulesPage()
		local options = {
			{ type = "description", label = "Every part of EldoUI is a module. Switch off the ones you don't want; Blizzard's own version comes fully back after a reload." },
		}
		-- Grouped like the sidebar: one header per category, alphabetical
		-- inside.
		local groups, order = {}, {}
		for name, module in self:IterateModules() do
			local category = self:GetModuleCategory(module)
			if not groups[category] then
				groups[category] = {}
				if not tContains(self.moduleCategories, category) then order[#order + 1] = category end
			end
			table.insert(groups[category], { name = name, module = module })
		end
		local categories = {}
		for _, category in ipairs(self.moduleCategories) do categories[#categories + 1] = category end
		for _, category in ipairs(order) do categories[#categories + 1] = category end
		for _, category in ipairs(categories) do
			local list = groups[category]
			if list then
				table.sort(list, function(a, b) return L[a.module.title] < L[b.module.title] end)
				table.insert(options, { type = "header", label = self:CategoryTitle(category) })
				for _, item in ipairs(list) do
					local module = item.module
					local _, conflict = self:GetModuleConflict(module)
					local label = L[module.title] .. (conflict and (" " .. L["(off while %s is loaded)"]:format(conflict)) or "")
					if not conflict and self:ModuleFailed(module) then
						label = label .. " " .. self:StatusText("warn", L["(failed to load, see the error log)"])
					end
					table.insert(options, { type = "toggle", key = item.name, label = label,
						desc = module.desc ~= "" and module.desc or L["Switch %s on or off."]:format(L[module.title]) })
				end
			end
		end
		self:RegisterConfigPage("modules", "Modules", options,
			function()
				for name, module in self:IterateModules() do moduleProxy[name] = module:IsEnabled() and true or false end
				return moduleProxy
			end,
			function()
				for name, module in self:IterateModules() do
					if moduleProxy[name] ~= (module:IsEnabled() and true or false) then
						self:SetModuleEnabled(name, moduleProxy[name])
						-- Reload UI counts it (secure button) instead of a chat line.
						TrackModule(module)
					end
				end
			end, 1.5)
	end
end
