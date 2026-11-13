-- EldoUI Notifications: tutorials, help tips and cutscenes.
--
--   Hide     tutorials off (CVar showTutorials) and help tips off (CVar
--            hideHelptips when the client has it); the player's own values
--            come back with "Blizzard default"
--   Skin     the "skip this cutscene?" dialogs and the old tutorial window
--   Improve  Esc skips a cutscene in one press (no question), and,
--            optional, cutscenes and movies you have already seen are skipped
--
-- Skipping is the same as the player's Esc + "Yes": StopCinematic() for
-- real cutscenes and the movie frame's own StopMovie(). Vehicle and scene
-- "cinematics" are left to Blizzard's dialog (leaving a vehicle is a
-- gameplay action).
local _, E = ...
local L = E.L
local M = E:GetModule("Notifications")
local U = M.util

local ID = "tutorials-cinematics"

-- The movies and cutscenes already seen, account-wide in the saved file
-- under "notifications" (the key they always had): seenMovies[movieID] and
-- seenCinematics[place]. Seen() is the only place that writes the key.
E:RegisterStore("notifications", { owner = "Notifications", accessor = "Seen" })

local function Shape(store)
	store = type(store) == "table" and store or {}
	if store.seenMovies == nil then store.seenMovies = {} end
	if store.seenCinematics == nil then store.seenCinematics = {} end
	return store
end

local function Seen()
	EldoUIDB.notifications = Shape(EldoUIDB.notifications)
	return EldoUIDB.notifications
end

-- Cutscenes have no ID; the place they start is the key.
local function CinematicKey()
	local zone = U.Safe(GetRealZoneText and GetRealZoneText()) or ""
	local sub = U.Safe(GetSubZoneText and GetSubZoneText()) or ""
	local mapID = C_Map and C_Map.GetBestMapForUnit and U.Safe(C_Map.GetBestMapForUnit("player")) or 0
	return ("%d|%s|%s"):format(mapID, zone, sub)
end

local function Improve(key)
	return U.Allowed(ID, "improve") and M.db.cinematics[key]
end

local function StopRealCinematic()
	if CinematicFrame and CinematicFrame.isRealCinematic and StopCinematic then
		StopCinematic()
		return true
	end
end

local function StopGameMovie()
	if MovieFrame and MovieFrame:IsShown() and MovieFrame.StopMovie then
		MovieFrame:StopMovie()
		return true
	end
end

---------------------------------------------------------------------------
-- Hooks (installed once, check the switch each time)
---------------------------------------------------------------------------
local hooked = false

local function Hook()
	if hooked then return end
	hooked = true
	local cinematicDialog = CinematicFrame and (CinematicFrame.closeDialog or _G.CinematicFrameCloseDialog)
	if cinematicDialog then
		cinematicDialog:HookScript("OnShow", function(dialog)
			if not Improve("escSkip") then return end
			if StopRealCinematic() then dialog:Hide() end
		end)
	end
	local movieDialog = MovieFrame and MovieFrame.CloseDialog
	if movieDialog then
		movieDialog:HookScript("OnShow", function(dialog)
			if not Improve("escSkip") then return end
			dialog:Hide()
			StopGameMovie()
		end)
	end
end

U.On("CINEMATIC_START", function(_, canBeCancelled)
	if not canBeCancelled or not U.Allowed(ID) then return end
	local key = CinematicKey()
	local store = Seen().seenCinematics
	if store[key] and Improve("skipSeen") then
		C_Timer.After(0, StopRealCinematic)
		return
	end
	store[key] = true
end)

U.On("PLAY_MOVIE", function(_, movieID)
	if not movieID or not U.Allowed(ID) then return end
	local store = Seen().seenMovies
	if store[movieID] and Improve("skipSeen") then
		C_Timer.After(0.1, function()
			if MovieFrame and MovieFrame.movieID == movieID then StopGameMovie() end
		end)
		return
	end
	store[movieID] = true
end)

---------------------------------------------------------------------------
-- Apply / restore
---------------------------------------------------------------------------
local skinned = false

local function Skin()
	if skinned then return end
	skinned = true
	local dialog = CinematicFrame and (CinematicFrame.closeDialog or _G.CinematicFrameCloseDialog)
	if dialog then
		E:SkinPanel(dialog, { accentLine = false })
		if dialog.Border then E:SkinAlphaZero(dialog.Border) end
		E:SkinButton(_G.CinematicFrameCloseDialogConfirmButton)
		E:SkinButton(_G.CinematicFrameCloseDialogResumeButton)
	end
	local movie = MovieFrame and MovieFrame.CloseDialog
	if movie then
		E:SkinPanel(movie, { accentLine = false })
		if movie.BackgroundTile then E:SkinAlphaZero(movie.BackgroundTile) end
		if movie.Buttons then
			E:SkinButton(movie.Buttons.ConfirmButton)
			E:SkinButton(movie.Buttons.ResumeButton)
		end
	end
	if TutorialFrame then E:SkinPanel(TutorialFrame, { accentLine = false }) end
end

local function Apply(state)
	Hook()
	if state.skin then Skin() end
	local db = M.db.cinematics
	if state.hide and db.tutorials then U.SetCVar("showTutorials", 0, ID) else U.RestoreCVar("showTutorials", ID) end
	if state.hide and db.helpTips then U.SetCVar("hideHelptips", 1, ID) else U.RestoreCVar("hideHelptips", ID) end
end

local function Restore()
	U.RestoreCVar("showTutorials", ID)
	U.RestoreCVar("hideHelptips", ID)
end

U.Element(ID, {
	apply = Apply,
	restore = Restore,
	handler = {
		reload = { skin = true },
		install = { skin = true, improve = true },
	},
})

-- /eui notify: forget which cutscenes were seen.
function M:ForgetSeenCinematics()
	local store = Seen()
	wipe(store.seenMovies)
	wipe(store.seenCinematics)
	self:Print(L["Seen cutscenes forgotten; each one plays again once."])
end
