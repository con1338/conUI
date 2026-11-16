-- Nemesis details use the game's visible player model and a browser link.
local _, E = ...
local L = E.L
local M = E.modules.Nemesis
local Read = E.PlainCall

local REGIONS = { US = "us", EU = "eu", KR = "kr", TW = "tw" }
local copyLease

local function NamePart(value)
	if E.Secret(value) or type(value) ~= "string" or value == "" then return end
	return (value:lower():gsub("[^a-z0-9%-._~]", function(byte)
		return ("%%%02X"):format(byte:byte())
	end))
end

function M:ArmoryURL(record)
	if type(record) ~= "table" or self:IsNameMasked(record) then return end
	local first, surname = NamePart(record.first), NamePart(record.surname)
	local region = record.region
	if E.Secret(region) then return end
	if type(region) == "nil" then region = Read(GetCurrentRegionName) end
	if E.Secret(region) or type(region) ~= "string" then return end
	region = REGIONS[region:upper()]
	if not (first and surname and region) then return end
	return ("https://worldofwarcraft.blizzard.com/forever/%s/armory/character/%s-%s"):format(region, first, surname)
end

function M:CopyArmory(record)
	local url = self:ArmoryURL(record)
	if not url then return false end
	local title = L["Armory link"]
	E:ShowCopyBox(title, L["Press Ctrl+C to copy, then paste the link in your browser."], url)
	local window = rawget(_G, "EldoUITextWindow")
	if window and window.box and window.box:GetText() == url then
		copyLease = { window = window, url = url, title = title, record = record, private = E.private }
	end
	return true
end

function M:RefreshArmoryCopy()
	local lease = copyLease
	if not lease then return end
	local window = lease.window
	if not window:IsShown() or window.title:GetText() ~= lease.title then
		copyLease = nil
		return
	end
	if not self.active or E.private ~= lease.private or self:IsNameMasked(lease.record) then
		copyLease = nil
		window.box:SetText("")
		window:Hide()
	end
end

local function ClearModel(view)
	view.guid, view.unit, view.dragX = nil, nil, nil
	view.model:SetScript("OnUpdate", nil)
	view.model:Hide()
	pcall(view.model.ClearModel, view.model)
end

local function Available(record, unit)
	if type(record) ~= "table" or E.Secret(record.guid) or type(record.guid) ~= "string"
		or E.Secret(unit) or type(unit) ~= "string" or E.IdentitySecret(unit) then return false end
	return Read(UnitExists, unit) == true and Read(UnitIsPlayer, unit) == true
		and Read(UnitIsVisible, unit) == true and Read(UnitGUID, unit) == record.guid
end

function M:UpdateModel(record, unit, force)
	local view = self.modelView
	if not view then return false end
	if not Available(record, unit) then
		ClearModel(view)
		view.status:SetText(L["Appearance unavailable"])
		view.status:Show()
		return false
	end
	if not force and view.guid == record.guid and view.unit == unit and view.model:IsShown() then return true end
	ClearModel(view)
	view.model:Show()
	local success = Read(view.model.SetUnit, view.model, unit, false, true)
	-- The unit can change while the client obtains its model.
	if success ~= true or not Available(record, unit) then
		ClearModel(view)
		view.status:SetText(L["Appearance unavailable"])
		view.status:Show()
		return false
	end
	view.guid, view.unit = record.guid, unit
	view.rotation, view.zoom = 0, 0
	pcall(view.model.SetRotation, view.model, view.rotation)
	pcall(view.model.SetPortraitZoom, view.model, view.zoom)
	pcall(view.model.SetCamDistanceScale, view.model, 1)
	view.status:Hide()
	return true
end

function M:ClearModelView()
	if self.modelView then ClearModel(self.modelView) end
end

function M:CreateModelView(parent)
	local view = CreateFrame("Frame", nil, parent)
	local model = CreateFrame("PlayerModel", nil, view)
	view.model = model
	model:SetAllPoints()
	model:SetKeepModelOnHide(false)
	model:EnableMouse(true)
	model:EnableMouseWheel(true)
	model:SetScript("OnMouseDown", function(_, button)
		if button ~= "LeftButton" or not view.guid then return end
		view.dragX = Read(GetCursorPosition)
		model:SetScript("OnUpdate", function()
			local x = Read(GetCursorPosition)
			if type(x) ~= "number" or type(view.dragX) ~= "number" then return end
			view.rotation = (view.rotation or 0) + (x - view.dragX) / 80
			view.dragX = x
			pcall(model.SetRotation, model, view.rotation)
		end)
	end)
	model:SetScript("OnMouseUp", function()
		view.dragX = nil
		model:SetScript("OnUpdate", nil)
	end)
	model:SetScript("OnMouseWheel", function(_, delta)
		if not view.guid or E.Secret(delta) or type(delta) ~= "number" then return end
		view.zoom = math.max(0, math.min(0.9, (view.zoom or 0) + delta * 0.1))
		pcall(model.SetPortraitZoom, model, view.zoom)
	end)
	view.status = E:CreateText(view, E.tokens.size.body, "CENTER")
	view.status:SetPoint("CENTER")
	view.status:SetPoint("LEFT", 12, 0)
	view.status:SetPoint("RIGHT", -12, 0)
	view.status:SetWordWrap(true)
	view.status:SetTextColor(unpack(E.tokens.text.secondary))
	view.status:SetText(L["Appearance unavailable"])
	view:HookScript("OnHide", function() ClearModel(view) end)
	model:Hide()
	self.modelView = view
	return view
end
