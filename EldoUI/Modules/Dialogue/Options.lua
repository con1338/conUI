-- EldoUI Dialog: settings page and style presets.
local _, E = ...
local L = E.L
local D = E:GetModule("Dialogue")

local function CameraOff()
	local camera = E.modules.Camera
	return not (camera and camera.active)
end

D.options = {
	{ type = "description", label = L["Quest and gossip NPCs talk in a wide panel at the top: numbered choices, Space to go on, Esc to leave. Nothing is accepted for you."] },

	{ type = "header", label = L["Text"] },
	{ type = "select", key = "textSpeed", label = L["Text speed"], values = D.SPEED_TITLE, order = { "instant", "fast", "slow" },
		desc = L["How the text comes in: all at once, or a sentence at a time, fast or slow. A click on the text or Space shows all of it."] },
	{ type = "range", key = "fontSize", label = L["Text size"], min = 11, max = 24, step = 1,
		desc = L["Size of the NPC's text and the choices. The name is a little larger."] },

	{ type = "header", label = L["Panel"] },
	{ type = "select", key = "look", label = L["Look"], values = D.LOOK_TITLE,
		order = { "cinematic", "book", "compact", "large", "bronze", "minimal" },
		desc = L["The panel's look: the standard panel, a see-through page with the heading font, tighter spacing, the standard panel for large text, a bronze frame, or text with no panel."] },
	{ type = "range", unit = "px", key = "width", label = L["Panel width"], min = 480, max = 800, step = 10,
		desc = L["Width of the panel. It stays centered on its place (move mode: NPC Dialog)."] },
	{ type = "range", key = "dim", label = L["Screen dim"], min = 0, max = 0.7, step = 0.05, percent = true, zeroText = "Off",
		desc = L["Darkens the world behind the panel while an NPC talks."] },
	{ type = "toggle", key = "model", label = L["NPC model"],
		desc = L["The NPC's 3D model next to the text."] },

	{ type = "header", label = L["Keys"] },
	{ type = "toggle", key = "numberKeys", label = L["Number keys pick"],
		desc = L["1 to 9 pick the numbered choice or reward while the panel shows. Off: those keys stay on your action bars."] },
	{ type = "toggle", key = "spaceKey", label = L["Space goes on"],
		desc = L["Space first shows all of the text, then accepts, continues or completes the quest on the page. Off: Space jumps as usual."] },
	{ type = "toggle", key = "copyKey", label = L["Ctrl+C copies the text"],
		desc = L["Ctrl+C opens the page's text in a copy box. Esc always leaves."] },
	{ type = "toggle", key = "rewardsKey", label = L["R shows only the rewards"],
		desc = L["On a quest page, R hides the text so only the rewards show, and R again brings it back. With Shift or Alt held, R always goes on to the game. Off: R stays on your Reply key."] },

	{ type = "header", label = L["Camera"] },
	{ type = "description", label = L["To zoom in on the NPC, use the Talking to an NPC distance in Camera Situations; this view never moves the camera itself."] },
	{ type = "execute", label = L["Camera Situations settings"], func = function() E:ToggleConfig("module:Camera", true) end,
		disabled = function() if CameraOff() then return L["Turn on Camera Situations first."] end end,
		desc = L["Opens Camera Situations, where Talking to an NPC sets the distance."] },
}

E:RegisterStyles("Dialogue", {
	{ key = "Cinematic", title = L["Cinematic"], desc = L["A wide panel with the model and a darker screen behind it."],
		settings = { look = "cinematic", width = 700, fontSize = 16, dim = 0.45, model = true, textSpeed = "fast" } },
	{ key = "Book", title = L["Book"], desc = L["A see-through page in the heading font, text at reading pace, no model."],
		settings = { look = "book", width = 560, fontSize = 15, dim = 0.25, model = false, textSpeed = "slow" } },
	{ key = "Compact", title = L["Compact"], desc = L["A narrow panel with small text, all of it at once."],
		settings = { look = "compact", width = 480, fontSize = 13, dim = 0, model = false, textSpeed = "instant" } },
	{ key = "Large", title = L["Large text"], desc = L["Big text in a wide panel, easy to read from a distance."],
		settings = { look = "large", width = 780, fontSize = 20, dim = 0.3, model = true, textSpeed = "fast" } },
	{ key = "Bronze", title = L["Forever bronze"], desc = L["A bronze frame and bronze names, to match the WoW Forever art style."],
		settings = { look = "bronze", width = 620, fontSize = 15, dim = 0.3, model = true, textSpeed = "fast" } },
	{ key = "Minimal", title = L["Minimal"], desc = L["Text only, no panel and no dim."],
		settings = { look = "minimal", width = 600, fontSize = 15, dim = 0, model = false, textSpeed = "instant" } },
})
