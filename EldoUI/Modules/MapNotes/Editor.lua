-- EldoUI Map Notes: your own notes.
--
-- Alt+right-click on the world map (or /eui mapnote add) opens the note
-- editor: title, note, icon and "Show on the continent map". Notes are saved
-- for the whole account (E.global.MapNotes). The editor is an EldoUI window
-- (E.WindowKit), so it follows the art style; it sits above the map and
-- closes with Escape.
--
-- The click is taken by EldoUI's own frame over the map (E:RegisterMapRightClick,
-- shared with Waypoints' Ctrl+right-click), shown only while Alt is held
-- out of combat: no Blizzard click handler is replaced, and the map keeps
-- its zone and zoom.
local _, E = ...
local L = E.L
local M = E.MapNotes

local Kit = E.WindowKit
local UI = E.UIKit

local editor

local function CreateEditBox(parent, multi)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetAutoFocus(false)
	E:SetFont(box, E.tokens.size.label) -- the theme font, not the chat font
	box:SetTextInsets(4, 4, 2, 2)
	if multi then
		box:SetMultiLine(true)
		box:SetMaxLetters(400)
	else
		box:SetMaxLetters(60)
		box:SetHeight(22)
	end
	E:SkinEditBox(box)
	-- Escape only leaves the box; the window closes with Escape after that.
	box:SetScript("OnEscapePressed", box.ClearFocus)
	return box
end

local function SelectIcon(index)
	editor.icon = index
	for i, slot in ipairs(editor.slots) do
		if i == index then
			slot:SetBackdropBorderColor(unpack(E.media.accentColor))
		else
			slot:SetBackdropBorderColor(unpack(E.media.borderColor))
		end
	end
end

local function Fields()
	return {
		t = editor.title:GetText(),
		d = editor.note:GetText(),
		i = editor.icon,
		c = editor.continent:GetChecked() and true or false,
	}
end

-- True when the fields differ from the note as it was opened.
local function Changed()
	local fields, opened = Fields(), editor.opened or {}
	for key, value in pairs(fields) do
		if value ~= opened[key] then return true end
	end
	return false
end

local function Close()
	editor.done = true
	editor:Hide()
end

local function Save()
	local fields = Fields()
	if editor.noteID then
		M:UpdateNote(editor.uiMapID, editor.noteID, fields)
	else
		M:AddNote(editor.uiMapID, editor.x, editor.y, fields)
	end
	Close()
end

local function Build()
	editor = Kit.CreateWindow("EldoUI_MapNoteEditor", { width = 380, height = 400, strata = "FULLSCREEN_DIALOG", footer = 40, headerHeight = 54 })
	local content = editor.content
	local function Label(text, anchor, gap)
		local fs = Kit.Secondary(E:CreateText(content, E.tokens.size.label, "LEFT"))
		fs:SetText(text)
		if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -(gap or 10)) else fs:SetPoint("TOPLEFT", 0, 0) end
		return fs
	end
	-- Each label spans the content, so the box under it takes the width
	-- from the label's bottom corners.
	local titleLabel = Label(L["Title"])
	titleLabel:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
	editor.title = CreateEditBox(content)
	editor.title:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 4, -4)
	editor.title:SetPoint("TOPRIGHT", titleLabel, "BOTTOMRIGHT", -4, -4)
	editor.title:SetScript("OnEnterPressed", Save)

	local noteLabel = Label(L["Note"])
	noteLabel:SetPoint("TOPLEFT", editor.title, "BOTTOMLEFT", -4, -10)
	noteLabel:SetPoint("TOPRIGHT", editor.title, "BOTTOMRIGHT", 4, -10)
	local holder = CreateFrame("Frame", nil, content)
	holder:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 0, -4)
	holder:SetPoint("TOPRIGHT", noteLabel, "BOTTOMRIGHT", 0, -4)
	holder:SetHeight(64)
	E:SetTemplate(holder, true)
	local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", -24, 4)
	if scroll.ScrollBar then E:SkinScrollBar(scroll.ScrollBar) end
	local note = CreateFrame("EditBox", nil, scroll)
	note:SetMultiLine(true)
	note:SetAutoFocus(false)
	note:SetMaxLetters(400)
	E:SetFont(note, E.tokens.size.label)
	note:SetWidth(300)
	note:SetScript("OnEscapePressed", note.ClearFocus)
	scroll:SetScrollChild(note)
	holder:EnableMouse(true)
	holder:SetScript("OnMouseDown", function() note:SetFocus() end)
	editor.note = note
	E.UIKit.TabOrder(editor.title, note)

	local iconLabel = Label(L["Icon"], holder, 10)
	editor.slots = {}
	for index, icon in ipairs(M.NOTE_ICONS) do
		local slot = CreateFrame("Button", nil, content)
		slot:SetSize(24, 24)
		local col, row = (index - 1) % 8, math.floor((index - 1) / 8)
		slot:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", col * 28, -4 - row * 28)
		E:SetTemplate(slot)
		slot.tex = slot:CreateTexture(nil, "ARTWORK")
		slot.tex:SetPoint("TOPLEFT", 2, -2)
		slot.tex:SetPoint("BOTTOMRIGHT", -2, 2)
		E:SetClientAtlas(slot.tex, icon.atlas, icon.texture)
		slot:SetScript("OnClick", function() SelectIcon(index) end)
		editor.slots[index] = slot
	end
	local rows = math.ceil(#M.NOTE_ICONS / 8)
	editor.continent = Kit.Check(content, L["Show on the continent map"], L["Also show this note on the continent map (Kalimdor, Eastern Kingdoms)."])
	editor.continent:SetPoint("TOPLEFT", iconLabel, "BOTTOMLEFT", -2, -8 - rows * 28)

	local function FooterButton(text, onClick, anchor)
		local b = UI.Button(editor.footer, text, 90, 22, onClick)
		if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -8, 0) else b:SetPoint("RIGHT", editor.footer, "RIGHT", 0, 0) end
		return b
	end
	editor.save = FooterButton(L["Save"], Save)
	editor.cancel = FooterButton(L["Cancel"], function() editor:Hide() end, editor.save)
	editor.delete = UI.Button(editor.footer, { text = L["Delete"], width = 90, kind = "danger", onClick = function()
		local uiMapID, noteID = editor.uiMapID, editor.noteID
		local saved = noteID and M:GetNote(uiMapID, noteID)
		if not saved then return Close() end
		local title = saved.t and saved.t ~= "" and saved.t or L["Map note"]
		E:ShowConfirm({ title = L["Delete map note"], text = L["Delete the map note \"%s\"? This can't be undone."]:format(title),
			accept = L["Delete"], danger = true,
			onAccept = function()
				M:DeleteNote(uiMapID, noteID)
				if editor:IsShown() and editor.noteID == noteID then Close() end
			end })
	end })
	editor.delete:SetPoint("LEFT", editor.footer, "LEFT", 0, 0)
	-- Closing with unsaved changes (Cancel, the close button, Escape) asks
	-- first; "Keep editing" opens the editor again with the text as it was.
	editor:SetScript("OnHide", function()
		editor.title:ClearFocus()
		editor.note:ClearFocus()
		local done = editor.done
		editor.done = nil
		-- Hidden with the whole UI (Alt+Z): it comes back as it was.
		if done or editor:IsShown() or not Changed() then return end
		E:ShowConfirm({ title = L["Discard your changes?"], text = L["The map note has changes that aren't saved."],
			accept = L["Discard"], cancel = L["Keep editing"], danger = true,
			onCancel = function() editor:Show(); editor:Raise() end })
	end)
end

-- uiMapID with x, y for a new note, or noteID to edit one.
function M:OpenEditor(uiMapID, x, y, noteID, title)
	if not (Kit and Kit.CreateWindow and UI and UI.Button) then
		if not noteID then self:AddNote(uiMapID, x, y, { t = title }) end
		return
	end
	if InCombatLockdown and InCombatLockdown() then
		E:Print(L["The note editor opens after combat."])
		E:RunOutOfCombat(function() M:OpenEditor(uiMapID, x, y, noteID, title) end)
		return
	end
	if not editor then Build() end
	local note = noteID and self:GetNote(uiMapID, noteID)
	if noteID and not note then return end
	editor.uiMapID, editor.noteID = uiMapID, noteID
	editor.x, editor.y = note and note.x or x, note and note.y or y
	editor:SetTitle(note and L["Edit map note"] or L["New map note"],
		("%s  %s"):format(M.MapName(uiMapID), M.FormatCoords(editor.x, editor.y)))
	editor.title:SetText(note and note.t or title or "")
	editor.note:SetText(note and note.d or "")
	editor.continent:SetChecked(note and note.c and true or false)
	SelectIcon(note and note.i or 1)
	editor.opened = Fields()
	editor.delete:SetShown(noteID ~= nil)
	editor:ClearAllPoints()
	editor:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	editor:Show()
	editor:Raise()
	editor.title:SetFocus()
end

---------------------------------------------------------------------------
-- Alt+right-click on the world map
---------------------------------------------------------------------------
-- The shared map click frame takes the click, so the map keeps its zone
-- and zoom. A map notes addon may use the same gesture for its own notes:
-- then EldoUI stands back.
E:RegisterMapRightClick("mapnotes", {
	modifier = "alt",
	wants = function() return M.active and M.db.altClick and not E:FeatureConflict("mapnotes") and true or false end,
	click = function(uiMapID, x, y) M:OpenEditor(uiMapID, x, y) end,
})

function M:EnableEditor() end
