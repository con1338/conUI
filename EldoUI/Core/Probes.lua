-- /eui probe <kind> ...: small in-game checks that print what the game
-- reports (battleground widgets, charge timings and so on). Modules add a
-- kind with E:RegisterProbe; there is one shared "probe" command.
local _, E = ...
local L = E.L

local Key = E.Key
E.probes = E.probes or {}

-- E:RegisterProbe(kind, usage, fn(rest))
--   kind   one word, case-insensitive
--   usage  the help text after "/eui probe <kind>"
--   fn     called with the rest of the command line
function E:RegisterProbe(kind, usage, fn)
	if type(kind) ~= "string" or type(fn) ~= "function" then return end
	E.probes[kind:lower()] = { usage = usage, run = fn }
end

-- E:RegisterDevProbe(kind, usage, fn): the same, for the developer checks
-- of the separate developer folder, which is never part of the player
-- download. They exist only while that folder is loaded, so a player's
-- EldoUI has none. Their help text is English only and is not translated.
function E:RegisterDevProbe(kind, usage, fn)
	if type(kind) ~= "string" or type(fn) ~= "function" then return end
	E.probes[kind:lower()] = { usage = usage, run = fn, dev = true }
end

-- The developer check kinds that are registered now, sorted.
function E:DevProbeKinds()
	local kinds = {}
	for kind, info in pairs(E.probes) do
		if info.dev then kinds[#kinds + 1] = kind end
	end
	table.sort(kinds)
	return kinds
end

E:AddCommand("probe", "<kind> ...  in-game checks that print what the game reports", function(arg)
	local kind, rest = tostring(arg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	local entry = E.probes[(kind or ""):lower()]
	if entry then
		entry.run(rest)
		return
	end
	local lines, devLines = {}, {}
	for key, info in pairs(E.probes) do
		if info.dev then
			devLines[#devLines + 1] = ("/eui probe %s  %s"):format(key, info.usage or "")
		else
			lines[#lines + 1] = ("/eui probe %s  %s"):format(key, info.usage and L[info.usage] or "")
		end
	end
	table.sort(lines)
	table.sort(devLines)
	E:Print(L["In-game checks:"])
	for _, line in ipairs(lines) do print(line) end
	if #devLines > 0 then
		print("Developer checks:")
		for _, line in ipairs(devLines) do print(line) end
	end
end, "Tools")

-- /eui probe textures: which original 2004 interface textures this client
-- ships, and which drawing calls it offers. The result opens in a copy box
-- (and goes to chat), ready to paste into a bug report.
local TEXTURE_PATHS = {
	-- Unit frames
	"Interface\\TargetingFrame\\UI-TargetingFrame",
	"Interface\\TargetingFrame\\UI-TargetingFrame-Elite",
	"Interface\\TargetingFrame\\UI-TargetingFrame-Rare",
	"Interface\\TargetingFrame\\UI-TargetingFrame-Rare-Elite",
	"Interface\\TargetingFrame\\UI-TargetingFrame-LevelBackground",
	"Interface\\TargetingFrame\\UI-TargetingFrame-Flash",
	"Interface\\TargetingFrame\\UI-TargetingFrame-BarFill",
	"Interface\\TargetingFrame\\UI-TargetofTargetFrame",
	"Interface\\TargetingFrame\\UI-SmallTargetingFrame",
	"Interface\\TargetingFrame\\UI-PartyFrame",
	"Interface\\TargetingFrame\\UI-PartyFrame-Flash",
	"Interface\\TargetingFrame\\UI-StatusBar",
	"Interface\\TargetingFrame\\UI-Player-AttackStatus",
	"Interface\\CharacterFrame\\UI-Player-Status",
	"Interface\\CharacterFrame\\UI-StateIcon",
	"Interface\\PetPaperDollFrame\\UI-PetHappiness",
	-- Action bars
	"Interface\\MainMenuBar\\UI-MainMenuBar-Dwarf",
	"Interface\\MainMenuBar\\UI-MainMenuBar-Human",
	"Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Dwarf",
	"Interface\\MainMenuBar\\UI-MainMenuBar-EndCap-Human",
	"Interface\\MainMenuBar\\UI-MainMenuBar-MaxLevel",
	"Interface\\MainMenuBar\\UI-MainMenuBar-KeyRing",
	"Interface\\Buttons\\UI-Quickslot",
	"Interface\\Buttons\\UI-Quickslot2",
	"Interface\\Buttons\\UI-Quickslot-Depress",
	"Interface\\Buttons\\ButtonHilight-Square",
	"Interface\\Buttons\\CheckButtonHilight",
	"Interface\\Buttons\\UI-ActionButton-Border",
	"Interface\\ShapeshiftBar\\ShapeshiftBar",
	"Interface\\ShapeshiftBar\\ShapeshiftBarMiddle",
	"Interface\\PetActionBar\\UI-PetBar",
	"Interface\\Buttons\\UI-Button-KeyRing",
	"Interface\\Buttons\\UI-Button-KeyRing-Highlight",
	"Interface\\Buttons\\UI-Button-KeyRing-Down",
	-- Micro menu and bags
	"Interface\\Buttons\\UI-MicroButton-Spellbook-Up",
	"Interface\\Buttons\\UI-MicroButton-Spellbook-Down",
	"Interface\\Buttons\\UI-MicroButton-Spellbook-Disabled",
	"Interface\\Buttons\\UI-MicroButton-Talents-Up",
	"Interface\\Buttons\\UI-MicroButton-World-Up",
	"Interface\\Buttons\\UI-MicroButton-MainMenu-Up",
	"Interface\\Buttons\\UI-MicroButton-Help-Up",
	"Interface\\Buttons\\UI-MicroButton-Abilities-Up",
	"Interface\\Buttons\\UI-MicroButton-LFG-Up",
	"Interface\\Buttons\\UI-MicroButtonCharacter-Up",
	"Interface\\Buttons\\UI-MicroButton-Character-Up",
	"Interface\\Buttons\\UI-MicroButton-Quest-Up",
	"Interface\\Buttons\\UI-MicroButton-Socials-Up",
	"Interface\\Buttons\\UI-MicroButton-Options-Up",
	"Interface\\Buttons\\UI-MicroButton-Hilight",
	"Interface\\Buttons\\UI-EmptySlot",
	"Interface\\Buttons\\UI-EmptySlot-Disabled",
	"Interface\\ContainerFrame\\KeyRing-Bag-Icon",
	"Interface\\ContainerFrame\\UI-Backpack-Background",
	"Interface\\ContainerFrame\\UI-Bag-Border",
	-- Minimap
	"Interface\\Minimap\\UI-Minimap-Border",
	"Interface\\Minimap\\UI-Minimap-ZoomInButton-Up",
	"Interface\\Minimap\\UI-Minimap-ZoomInButton-Down",
	"Interface\\Minimap\\UI-Minimap-ZoomOutButton-Up",
	"Interface\\Minimap\\UI-Minimap-ZoomOutButton-Down",
	"Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight",
	"Interface\\Minimap\\MiniMap-TrackingBorder",
	"Interface\\Minimap\\UI-Minimap-Background",
	"Interface\\Minimap\\CompassNorthTag",
	"Interface\\Minimap\\UI-Minimap-Ping-Center",
	"Interface\\Icons\\INV_Letter_15",
	-- Experience, reputation, cast bar
	"Interface\\MainMenuBar\\UI-XP-Bar",
	"Interface\\MainMenuBar\\UI-ExhaustionTickNormal",
	"Interface\\PaperDollInfoFrame\\UI-ReputationWatchBar",
	"Interface\\CastingBar\\UI-CastingBar-Border",
	"Interface\\CastingBar\\UI-CastingBar-Border-Small",
	"Interface\\CastingBar\\UI-CastingBar-Flash",
	"Interface\\CastingBar\\UI-CastingBar-Flash-Small",
	"Interface\\CastingBar\\UI-CastingBar-Spark",
	-- Window controls
	"Interface\\Buttons\\UI-Panel-Button-Up",
	"Interface\\Buttons\\UI-Panel-Button-Down",
	"Interface\\Buttons\\UI-Panel-Button-Disabled",
	"Interface\\Buttons\\UI-Panel-Button-Highlight",
	"Interface\\Buttons\\UI-CheckBox-Up",
	"Interface\\Buttons\\UI-CheckBox-Check",
	"Interface\\Buttons\\UI-SliderBar-Border",
	"Interface\\Buttons\\UI-SliderBar-Button-Horizontal",
	"Interface\\Buttons\\UI-ScrollBar-Knob",
	"Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up",
	"Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up",
	"Interface\\Common\\Common-Input-Border",
	"Interface\\DialogFrame\\UI-DialogBox-Border",
	"Interface\\DialogFrame\\UI-DialogBox-Background",
	"Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	"Interface\\DialogFrame\\UI-DialogBox-Header",
	"Interface\\Tooltips\\UI-Tooltip-Border",
	"Interface\\Tooltips\\UI-Tooltip-Background",
	"Interface\\PaperDollInfoFrame\\UI-Character-General-TopLeft",
	"Interface\\PaperDollInfoFrame\\UI-Character-General-TopRight",
	"Interface\\PaperDollInfoFrame\\UI-Character-General-BottomLeft",
	"Interface\\PaperDollInfoFrame\\UI-Character-General-BottomRight",
}
E.probeTexturePaths = TEXTURE_PATHS

local function TextureFileID(path)
	if not GetFileIDFromPath then return nil end
	local ok, id = pcall(GetFileIDFromPath, path)
	if ok and type(id) == "number" and id > 0 then return id end
	return nil
end

-- One line per check, in a form that reads well pasted into a report.
function E:TextureProbeReport()
	local lines, found, missing = {}, 0, 0
	local _, build, _, interface = GetBuildInfo()
	lines[1] = ("EldoUI %s, client build %s, interface %s, %s"):format(tostring(E.version), tostring(build),
		tostring(interface), date("!%Y-%m-%d %H:%M UTC"))
	if not GetFileIDFromPath then
		lines[#lines + 1] = "GetFileIDFromPath: missing (no texture can be checked)"
	end
	for _, path in ipairs(TEXTURE_PATHS) do
		local id = TextureFileID(path)
		if id then found = found + 1 else missing = missing + 1 end
		lines[#lines + 1] = ("%s %s"):format(id and ("found " .. id) or "MISSING", path)
	end
	local probe = CreateFrame("Frame"):CreateTexture()
	local apis = {
		{ "Texture:SetTextureSliceMargins", type(probe.SetTextureSliceMargins) == "function" },
		{ "C_CooldownViewer", type(C_CooldownViewer) == "table" },
		{ "C_EditMode", type(C_EditMode) == "table" },
		{ "C_Texture.GetAtlasInfo", type(C_Texture) == "table" and type(C_Texture.GetAtlasInfo) == "function" },
	}
	for _, api in ipairs(apis) do
		lines[#lines + 1] = ("%s %s"):format(api[2] and "present" or "MISSING", api[1])
	end
	table.insert(lines, 2, ("textures: %d found, %d missing of %d"):format(found, missing, #TEXTURE_PATHS))
	return table.concat(lines, "\n"), found, missing
end

E:RegisterProbe("textures", Key("which original interface textures this client ships (opens a copy box)"), function()
	local text, found, missing = E:TextureProbeReport()
	E:Print(L["Texture check: %d found, %d missing. The full list is in the copy box."]:format(found, missing))
	if E.ShowCopyBox then
		E:ShowCopyBox(L["Texture check"], L["Press Ctrl+C to copy the list, then paste it into the report."], text)
	else
		for line in text:gmatch("[^\n]+") do print(line) end
	end
end)
