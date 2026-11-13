-- EldoUI My Adventure: the quick note card (design.md 4.7).
--
-- A small card for writing a note without opening the Journal window:
-- the place and level, a writing field, the reminder row (filled in from
-- what you write) and "Pin to Journey". Enter saves, Shift+Enter starts a
-- new line, Esc closes. It opens at the top of the screen until you drag
-- it, then remembers its place for this character. It is not a layout
-- mover, like the Journal window itself.
--
--   /eui jot [text]       with text: writes the note here and now (the
--                         reminder read from the text); alone: the card
--   A.QuickNote:Open([text]), :Close(), :Toggle(), :Save(), :Jot(text)
--   A.QuickNote.frame     the card once built (EldoUI_JournalQuickNote)
-- The key binding (Bindings.xml) calls A.QuickNote:Toggle().
local _, E = ...
local L = E.L
local A = E.Adventure
local J = E.Journal
local K = E.AdventureKit
local LG = E.LootGuide
local G = A.Goals
local N = A.Notes
local T = E.tokens
local UI = A.PageUI

local function Kit() return LG.Kit end

local Q = {}
A.QuickNote = Q

Q.WIDTH, Q.HEIGHT = 420, 212
Q.NAME = "EldoUI_JournalQuickNote"

local card

local function UIState()
	local rec = J:Char()
	return rec and rec.ui or nil
end

local function Place()
	card:ClearAllPoints()
	local ui = UIState()
	local saved = ui and ui.quickNote
	if type(saved) == "table" and type(saved.x) == "number" and type(saved.y) == "number" then
		card:SetPoint(saved.point or "TOPLEFT", UIParent, saved.point or "TOPLEFT", saved.x, saved.y)
	else
		card:SetPoint("TOP", UIParent, "TOP", 0, -200)
	end
end

local function Remember()
	local ui = UIState()
	if not ui then return end
	local left, top = card:GetLeft(), card:GetTop()
	local height = UIParent:GetHeight() or 0
	if not (left and top) then return end
	ui.quickNote = { point = "TOPLEFT", x = math.floor(left + 0.5), y = math.floor(top - height + 0.5) }
end

local function Fill()
	local here = N:Here()
	card.place:SetText((L["%s · level %d"]):format(N:WhereText(here), here.level or 0))
	card.pin:SetChecked(A.db and A.db.pinNewNotes and true or false)
end

local function Build()
	if card then return card end
	-- The tool window shell (header, title, accent line, close X, Escape).
	-- Dragged by its header; the place it is left at is kept per character.
	card = E.UIKit.CreateToolWindow(Q.NAME, { title = L["Quick note"], width = Q.WIDTH, height = Q.HEIGHT,
		strata = "DIALOG", resizable = false, dialog = false })
	card.header:HookScript("OnDragStop", Remember)
	card.close:SetScript("OnClick", function() Q:Close() end)
	card.place = K.Text(card, K.size.small, "LEFT", "secondary")
	card.place:SetPoint("TOPLEFT", 12, -(E.UIKit.TOOL_HEADER + 8))
	card.place:SetPoint("TOPRIGHT", -12, -(E.UIKit.TOOL_HEADER + 8))
	card.place:SetWordWrap(false)
	card.field = UI.WritingField(card, 70, N.MAX_LETTERS,
		L["Write about this place, a reminder for later, or shift-click an item into it."])
	card.field:SetPoint("TOPLEFT", 12, -52)
	card.field:SetPoint("TOPRIGHT", -12, -52)
	card.reminder = UI.ReminderRow(card)
	card.reminder:SetPoint("TOPLEFT", card.field, "BOTTOMLEFT", 0, -8)
	card.pin = UI.Check(card, L["Pin to Journey"], L["Shows the note on your Journey, under the level you wrote it at."])
	card.pin:SetPoint("TOPLEFT", card.reminder, "BOTTOMLEFT", 0, -6)
	card.save = Kit().Button(card, L["Save note"], 100, T.height.button, function() Q:Save() end,
		L["Save note"], L["Writes the note into your journal with where and when you wrote it."])
	card.save:SetPoint("BOTTOMRIGHT", -12, 10)
	card.hint = K.Text(card, K.size.small, "LEFT", "secondary")
	card.hint:SetPoint("BOTTOMLEFT", 12, 14)
	card.hint:SetPoint("BOTTOMRIGHT", card.save, "BOTTOMLEFT", -8, 4)
	card.hint:SetWordWrap(false)
	card.hint:SetText(L["Enter saves, Shift+Enter new line, Esc closes."])

	local box = card.field.box
	UI.EnterSaves(box, function() Q:Save() end)
	box:SetScript("OnEscapePressed", function() Q:Close() end)
	UI.FollowSuggestion(box, card.reminder)
	UI.LinkIntoBox(box)
	card:HookScript("OnHide", function() box:ClearFocus() end)
	Q.frame = card
	return card
end
Q.Build = Build

function Q:IsShown()
	return card ~= nil and card:IsShown()
end

function Q:Open(text)
	if not A:Running() then
		E:Print(A:OffHint() or A:OffReason() or L["My Adventure is off."])
		return false
	end
	Build()
	Place()
	Fill()
	local box = card.field.box
	box:SetText(type(text) == "string" and text or "")
	card.reminder:Reset(nil)
	if box:GetText() ~= "" then card.reminder:Suggest(N:Suggest(box:GetText())) end
	card:Show()
	-- A frame later, so the key that opened the card is not typed into it.
	C_Timer.After(0, function() if card:IsShown() then box:SetFocus() end end)
	return true
end

function Q:Close()
	if card then card:Hide() end
end

function Q:Toggle()
	if self:IsShown() then self:Close() else self:Open() end
end

-- The confirmation goes through the moment card ("Noted in your journal.").
local function Confirm(note)
	UI.NoteSound()
	local db = A.db or {}
	local kinds = type(db.momentKinds) == "table" and db.momentKinds or {}
	if kinds.note == false then return end
	G.Announce({ kind = "note", title = L["Journal"], text = UI.SavedText(note), icon = N.ICON,
		seconds = db.momentSeconds, key = "journal-noted" })
end

function Q:Save()
	if not card then return nil end
	local trigger, repeats = card.reminder:Get()
	local note, err = N:Add(card.field.box:GetText(), { trigger = trigger, repeats = repeats,
		pinned = card.pin:GetChecked() and true or false })
	if not note then
		card.place:SetText(err or L["Write something first."])
		K.Paint(card.place, "bad")
		C_Timer.After(2, function()
			if card:IsShown() then
				K.Paint(card.place, "secondary")
				Fill()
			end
		end)
		return nil, err
	end
	card.field.box:SetText("")
	self:Close()
	Confirm(note)
	return note
end

-- /eui jot <text>: the note here and now, with the reminder its text suggests.
function Q:Jot(text)
	if not A:Running() then
		E:Print(A:OffHint() or A:OffReason() or L["My Adventure is off."])
		return nil
	end
	local note, err = N:Add(text, { trigger = N:Suggest(text) })
	if not note then
		E:Print(err or L["Write something first."])
		return nil
	end
	Confirm(note)
	return note
end

E:AddCommand("jot", "[text]  write a note in your journal here and now, or open the quick note card", function(arg)
	arg = type(arg) == "string" and strtrim(arg) or ""
	if arg == "" then
		Q:Toggle()
	else
		Q:Jot(arg)
	end
end, "Tools")

A:AddPart("quicknote", {
	order = 32,
	stop = function() Q:Close() end,
})
