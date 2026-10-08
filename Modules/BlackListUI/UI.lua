-- Blacklist window: a List tab (scrollable player rows, each with a History
-- popout showing every past add with date/time and reason) and a Settings
-- tab, built with the hub's plain CreateFrame/Skin widgets - same window
-- chrome and tab-strip pattern as Modules\RaidRollUI\Init.lua, and the same
-- pooled-row scrollframe pattern as Modules\RaidBrowserUI\Init.lua. No
-- UIDropDownMenu/AceGUI, matching the rest of the hub.
JohnnysBlackList.BlackListUI = JohnnysBlackList.BlackListUI or {}
local BlackListUI = JohnnysBlackList.BlackListUI
local Skin = JohnnysBlackList.Skin

local FRAME_WIDTH, FRAME_HEIGHT = 700, 560
local TAB_HEIGHT = 24
-- Rows size to fit their reason text (which may wrap to several lines)
-- instead of a fixed height, so a long reason doesn't run into the next
-- player's row and a short one doesn't waste space with a big empty gap.
local ROW_MIN_HEIGHT = 20
local ROW_TEXT_PADDING = 8
local ROW_GAP = 4

local COL = { name = 130, info = 100, reason = 130, ignore = 40, warn = 40, history = 70, edit = 50, remove = 60 }
local ROW_WIDTH = COL.name + COL.info + COL.reason + COL.ignore + COL.warn + COL.history + COL.edit + COL.remove

local function ColumnX(key)
	local order = { "name", "info", "reason", "ignore", "warn", "history", "edit", "remove" }
	local x = 0
	for _, k in ipairs(order) do
		if k == key then
			return x
		end
		x = x + COL[k]
	end
	return x
end

local mainFrame, listScroll, listContent, statusText
local addNameEdit, addReasonEdit
local rows = {}
local tabs = {}
local tabOrder = { "List", "Settings" }
local activeTab
local historyPopout
local editPopout

----------------------------------------------------------------------------
-- History popout - a single reusable flat panel anchored under whichever
-- row's History button was clicked, listing that player's history entries
-- (date/time + reason), most recent first.
----------------------------------------------------------------------------
local function EnsureHistoryPopout()
	if historyPopout then
		return historyPopout
	end

	historyPopout = CreateFrame("Frame", "JohnnysAddonHubBlackListHistoryPopout", UIParent)
	historyPopout:SetFrameStrata("TOOLTIP")
	historyPopout:SetWidth(300)
	Skin:StylePanel(historyPopout, 0.98)
	historyPopout:Hide()

	historyPopout.title = historyPopout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	historyPopout.title:SetPoint("TOPLEFT", 8, -6)
	historyPopout.title:SetTextColor(1, 1, 1)

	historyPopout.lines = {}

	return historyPopout
end

function BlackListUI:ToggleHistoryPopout(row)
	local popout = EnsureHistoryPopout()

	if popout:IsShown() and popout.owner == row then
		popout:Hide()
		popout.owner = nil
		return
	end

	local entry = self:GetEntryByName(row.playerName)
	if not entry then
		return
	end

	popout.title:SetText("Blacklist History: " .. entry.name)

	local y = -22
	for i = 1, #entry.history do
		local h = entry.history[i]
		local fs = popout.lines[i]
		if not fs then
			fs = popout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetPoint("TOPLEFT", 8, 0)
			fs:SetWidth(284)
			fs:SetJustifyH("LEFT")
			popout.lines[i] = fs
		end

		local dateText = date("%I:%M%p on %b %d, %Y", h.date)
		local reasonText = (h.reason ~= "" and h.reason) or "(no reason given)"
		fs:SetText("|cffffd200" .. dateText .. "|r  -  " .. reasonText)
		fs:SetTextColor(0.85, 0.85, 0.85)
		fs:ClearAllPoints()
		fs:SetPoint("TOPLEFT", 8, y)
		fs:Show()
		y = y - 16
	end

	for i = #entry.history + 1, #popout.lines do
		popout.lines[i]:Hide()
	end

	popout:SetHeight(math.max(40, -y + 8))
	popout:ClearAllPoints()
	popout:SetPoint("TOPLEFT", row.historyBtn, "BOTTOMLEFT", 0, -2)
	popout.owner = row
	popout:Show()
end

----------------------------------------------------------------------------
-- Edit popout - a single reusable panel anchored under whichever row's Edit
-- button was clicked. Top section edits Name/Level/Class/Race in place (no
-- history side-effects, unlike re-adding). Bottom section lists every
-- history entry with an editable reason and a per-entry Delete button.
----------------------------------------------------------------------------
local EDIT_POPOUT_WIDTH = 320

local function EnsureEditPopout()
	if editPopout then
		return editPopout
	end

	editPopout = CreateFrame("Frame", "JohnnysAddonHubBlackListEditPopout", UIParent)
	editPopout:SetFrameStrata("TOOLTIP")
	editPopout:SetWidth(EDIT_POPOUT_WIDTH)
	Skin:StylePanel(editPopout, 0.98)
	editPopout:Hide()

	editPopout.title = editPopout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	editPopout.title:SetPoint("TOPLEFT", 8, -6)
	editPopout.title:SetTextColor(1, 1, 1)

	local function AddLabel(text, x, y)
		local fs = editPopout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("TOPLEFT", x, y)
		fs:SetTextColor(0.7, 0.7, 0.7)
		fs:SetText(text)
		return fs
	end

	AddLabel("Name:", 8, -24)
	editPopout.nameEdit = Skin:CreateEditBox(editPopout, 130, 18)
	editPopout.nameEdit:SetPoint("TOPLEFT", 44, -22)

	AddLabel("Level:", 190, -24)
	editPopout.levelEdit = Skin:CreateEditBox(editPopout, 40, 18)
	editPopout.levelEdit:SetPoint("TOPLEFT", 232, -22)

	AddLabel("Class:", 8, -48)
	editPopout.classEdit = Skin:CreateEditBox(editPopout, 110, 18)
	editPopout.classEdit:SetPoint("TOPLEFT", 44, -46)

	AddLabel("Race:", 162, -48)
	editPopout.raceEdit = Skin:CreateEditBox(editPopout, 110, 18)
	editPopout.raceEdit:SetPoint("TOPLEFT", 198, -46)

	editPopout.saveBtn = Skin:CreateButton(editPopout, 60, 20, "Save")
	editPopout.saveBtn:SetPoint("TOPLEFT", 8, -70)
	editPopout.saveBtn:SetScript("OnClick", function()
		local entry = BlackListUI:GetEntryByName(editPopout.entryName)
		if not entry then
			return
		end
		local ok, err = BlackListUI:EditPlayer(
			entry.name,
			editPopout.nameEdit.editBox:GetText(),
			editPopout.levelEdit.editBox:GetText(),
			editPopout.classEdit.editBox:GetText(),
			editPopout.raceEdit.editBox:GetText()
		)
		if ok then
			editPopout:Hide()
			editPopout.owner = nil
		else
			editPopout.errorText:SetText(err or "")
		end
	end)

	editPopout.errorText = editPopout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	editPopout.errorText:SetPoint("LEFT", editPopout.saveBtn, "RIGHT", 8, 0)
	editPopout.errorText:SetWidth(EDIT_POPOUT_WIDTH - 84)
	editPopout.errorText:SetJustifyH("LEFT")
	editPopout.errorText:SetTextColor(1, 0.3, 0.3)

	AddLabel("History:", 8, -98)

	editPopout.historyLines = {}

	return editPopout
end

-- (Re)populates an already-shown edit popout: the form fields (skipped while
-- a field has focus, so a history-section redraw never stomps a field the
-- user is mid-typing) and the pooled history-line rows.
local function RefreshEditPopoutContent(popout, entry)
	popout.entryName = entry.name
	popout.title:SetText("Edit: " .. entry.name)
	popout.errorText:SetText("")

	if not popout.nameEdit.editBox:HasFocus() then
		popout.nameEdit.editBox:SetText(entry.name)
	end
	if not popout.levelEdit.editBox:HasFocus() then
		popout.levelEdit.editBox:SetText(entry.level or "")
	end
	if not popout.classEdit.editBox:HasFocus() then
		popout.classEdit.editBox:SetText(entry.class or "")
	end
	if not popout.raceEdit.editBox:HasFocus() then
		popout.raceEdit.editBox:SetText(entry.race or "")
	end

	local y = -114
	for i = 1, #entry.history do
		local h = entry.history[i]
		local line = popout.historyLines[i]
		if not line then
			line = CreateFrame("Frame", nil, popout)
			line:SetSize(EDIT_POPOUT_WIDTH - 16, 36)

			line.dateText = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			line.dateText:SetPoint("TOPLEFT", 0, 0)
			line.dateText:SetWidth(EDIT_POPOUT_WIDTH - 16)
			line.dateText:SetJustifyH("LEFT")
			line.dateText:SetTextColor(0.85, 0.85, 0.85)

			line.reasonEdit = Skin:CreateEditBox(line, EDIT_POPOUT_WIDTH - 74, 18)
			line.reasonEdit:SetPoint("TOPLEFT", 0, -16)

			line.deleteBtn = Skin:CreateButton(line, 46, 18, "Delete")
			line.deleteBtn:SetPoint("LEFT", line.reasonEdit, "RIGHT", 4, 0)

			popout.historyLines[i] = line
		end

		line.historyIndex = i
		line.dateText:SetText(date("%I:%M%p on %b %d, %Y", h.date))
		if not line.reasonEdit.editBox:HasFocus() then
			line.reasonEdit.editBox:SetText(h.reason or "")
		end
		line.reasonEdit.editBox:SetScript("OnTextChanged", function(self)
			if self:HasFocus() then
				BlackListUI:EditHistoryReason(popout.entryName, line.historyIndex, self:GetText())
			end
		end)
		line.deleteBtn:SetScript("OnClick", function()
			local ok, err = BlackListUI:RemoveHistoryEntry(popout.entryName, line.historyIndex)
			if ok then
				local refreshedEntry = BlackListUI:GetEntryByName(popout.entryName)
				if refreshedEntry then
					RefreshEditPopoutContent(popout, refreshedEntry)
				end
			else
				popout.errorText:SetText(err or "")
			end
		end)

		line:ClearAllPoints()
		line:SetPoint("TOPLEFT", 8, y)
		line:Show()
		y = y - 40
	end

	for i = #entry.history + 1, #popout.historyLines do
		popout.historyLines[i]:Hide()
	end

	popout:SetHeight(math.max(96, -y + 8))
end

function BlackListUI:ToggleEditPopout(row)
	local popout = EnsureEditPopout()

	if popout:IsShown() and popout.owner == row then
		popout:Hide()
		popout.owner = nil
		return
	end

	local entry = self:GetEntryByName(row.playerName)
	if not entry then
		return
	end

	RefreshEditPopoutContent(popout, entry)

	popout:ClearAllPoints()
	popout:SetPoint("TOPLEFT", row.editBtn, "BOTTOMLEFT", 0, -2)
	popout.owner = row
	popout:Show()
end

----------------------------------------------------------------------------
-- List tab: pooled row scrollframe.
----------------------------------------------------------------------------
-- Stacks only the currently-shown rows, each at its own current height (set
-- beforehand in RefreshWindow based on how many lines its reason wrapped
-- to), with a small fixed gap between them - so a one-line reason and a
-- three-line reason both get exactly the room they need, no more.
local function LayoutRows()
	local y = 0
	for i = 1, #rows do
		local row = rows[i]
		if row:IsShown() then
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", listContent, "TOPLEFT", 0, -y)
			y = y + row:GetHeight() + ROW_GAP
		end
	end
	listContent:SetHeight(math.max(20, y))
end

local function CreateRow(parent)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(ROW_WIDTH, ROW_MIN_HEIGHT)

	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(Skin.WHITE)
	bg:SetVertexColor(1, 1, 1, 0.03)

	-- Every column is anchored from the top of the row (not vertically
	-- centered), so they all line up flush at the top regardless of how
	-- tall the row grows to fit a wrapped reason.
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnX("name") + 4, -4)
	row.name:SetWidth(COL.name - 8)
	row.name:SetJustifyH("LEFT")
	row.name:SetTextColor(1, 1, 1)

	row.info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.info:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnX("info") + 4, -4)
	row.info:SetWidth(COL.info - 8)
	row.info:SetJustifyH("LEFT")
	row.info:SetTextColor(0.7, 0.7, 0.7)

	row.reason = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.reason:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnX("reason") + 4, -4)
	row.reason:SetWidth(COL.reason - 8)
	row.reason:SetJustifyH("LEFT")
	row.reason:SetJustifyV("TOP")
	row.reason:SetTextColor(0.85, 0.85, 0.85)

	row.ignoreBox = Skin:CreateCheckbox(row, 16, false, function(state)
		if row.playerName then
			BlackListUI:SetIgnore(row.playerName, state)
		end
	end)
	row.ignoreBox:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnX("ignore") + 12, -2)

	row.warnBox = Skin:CreateCheckbox(row, 16, false, function(state)
		if row.playerName then
			BlackListUI:SetWarn(row.playerName, state)
		end
	end)
	row.warnBox:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnX("warn") + 12, -2)

	row.historyBtn = Skin:CreateButton(row, COL.history - 6, 18, "History")
	row.historyBtn:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnX("history"), -1)
	row.historyBtn:SetScript("OnClick", function()
		BlackListUI:ToggleHistoryPopout(row)
	end)

	row.editBtn = Skin:CreateButton(row, COL.edit - 6, 18, "Edit")
	row.editBtn:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnX("edit"), -1)
	row.editBtn:SetScript("OnClick", function()
		BlackListUI:ToggleEditPopout(row)
	end)

	row.removeBtn = Skin:CreateButton(row, COL.remove - 6, 18, "Remove")
	row.removeBtn:SetPoint("TOPLEFT", row, "TOPLEFT", ColumnX("remove"), -1)
	row.removeBtn:SetScript("OnClick", function()
		if row.playerName then
			BlackListUI:RemovePlayer(row.playerName)
		end
	end)

	return row
end

function BlackListUI:RefreshWindow()
	if not mainFrame or not listContent then
		return
	end

	local list = self:GetList()
	local n = #list

	for i = 1, n do
		local entry = list[i]
		local row = rows[i]
		if not row then
			row = CreateRow(listContent)
			rows[i] = row
		end

		row.playerName = entry.name
		row.name:SetText(entry.name)

		local infoText = ""
		if entry.level ~= "" and entry.class ~= "" then
			infoText = "Lvl " .. entry.level .. " " .. entry.class
		elseif entry.class ~= "" then
			infoText = entry.class
		elseif entry.level ~= "" then
			infoText = "Lvl " .. entry.level
		end
		row.info:SetText(infoText)

		local latest = entry.history[1]
		row.reason:SetText((latest and latest.reason ~= "" and latest.reason) or "(no reason given)")

		row.ignoreBox:SetChecked(entry.ignore)
		row.warnBox:SetChecked(entry.warn)
		row.historyBtn.text:SetText("History (" .. #entry.history .. ")")

		-- Grow the row to fit however many lines the reason wrapped to.
		local reasonHeight = row.reason:GetStringHeight() or ROW_MIN_HEIGHT
		row:SetHeight(math.max(ROW_MIN_HEIGHT, reasonHeight + ROW_TEXT_PADDING))

		row:Show()
	end

	for i = n + 1, #rows do
		rows[i].playerName = nil
		rows[i]:Hide()
	end

	LayoutRows()

	if statusText then
		statusText:SetText(n .. " player(s) blacklisted")
	end

	if historyPopout and historyPopout:IsShown() and historyPopout.owner and not historyPopout.owner:IsShown() then
		historyPopout:Hide()
		historyPopout.owner = nil
	end

	if editPopout and editPopout:IsShown() and editPopout.owner and not editPopout.owner:IsShown() then
		editPopout:Hide()
		editPopout.owner = nil
	end
end

local function BuildListTab(parent)
	local header = CreateFrame("Frame", nil, parent)
	header:SetSize(ROW_WIDTH, 18)
	header:SetPoint("TOPLEFT", 0, 0)

	local labels = { name = "Name", info = "Info", reason = "Reason", ignore = "Ign", warn = "Warn", history = "History", edit = "", remove = "" }
	for _, key in ipairs({ "name", "info", "reason", "ignore", "warn", "history", "edit", "remove" }) do
		local fs = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", header, "LEFT", ColumnX(key) + 4, 0)
		fs:SetWidth(COL[key] - 4)
		fs:SetJustifyH("LEFT")
		fs:SetTextColor(0.7, 0.7, 0.7)
		fs:SetText(labels[key])
	end

	listScroll = CreateFrame("ScrollFrame", "JohnnysAddonHubBlackListScroll", parent, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", 0, -20)
	listScroll:SetSize(ROW_WIDTH, 330)

	listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetSize(ROW_WIDTH, 20)
	listScroll:SetScrollChild(listContent)

	addNameEdit = Skin:CreateEditBox(parent, 130, 20)
	addNameEdit:SetPoint("TOPLEFT", 0, -358)

	addReasonEdit = Skin:CreateEditBox(parent, 280, 20)
	addReasonEdit:SetPoint("LEFT", addNameEdit, "RIGHT", 8, 0)

	local addBtn = Skin:CreateButton(parent, 90, 20, "Add")
	addBtn:SetPoint("LEFT", addReasonEdit, "RIGHT", 8, 0)
	addBtn:SetScript("OnClick", function()
		local name = addNameEdit.editBox:GetText()
		local reason = addReasonEdit.editBox:GetText()
		if name and name ~= "" then
			BlackListUI:AddPlayer(name, reason, JohnnysAddonHubBlackListConfig.Ignore)
			addNameEdit.editBox:SetText("")
			addReasonEdit.editBox:SetText("")
		end
	end)

	local addTargetBtn = Skin:CreateButton(parent, 100, 20, "Add Target")
	addTargetBtn:SetPoint("TOPLEFT", 0, -384)
	addTargetBtn:SetScript("OnClick", function()
		BlackListUI:AddFromUnit("target", addReasonEdit.editBox:GetText())
		addReasonEdit.editBox:SetText("")
	end)

	statusText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("LEFT", addTargetBtn, "RIGHT", 12, 0)
	statusText:SetTextColor(0.7, 0.7, 0.7)
	statusText:SetText("0 player(s) blacklisted")

	return { frame = parent, Refresh = function() BlackListUI:RefreshWindow() end }
end

----------------------------------------------------------------------------
-- Settings tab.
----------------------------------------------------------------------------
function BlackListUI.BuildSettingsTab(parent)
	local y = 8
	local entries = {}
	local rankEdit

	local function AddCheckboxRow(label, key)
		local box = Skin:CreateCheckbox(parent, 16, JohnnysAddonHubBlackListConfig[key], function(state)
			JohnnysAddonHubBlackListConfig[key] = state
		end)
		box:SetPoint("TOPLEFT", 8, -y)

		local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		fs:SetPoint("LEFT", box, "RIGHT", 6, 0)
		fs:SetTextColor(0.9, 0.9, 0.9)
		fs:SetText(label)

		table.insert(entries, { box = box, key = key })
		y = y + 24
	end

	AddCheckboxRow("Play sound when a blacklisted player is sighted", "Sound")
	AddCheckboxRow("Show warning at screen center", "Center")
	AddCheckboxRow("Show reason in chat", "Chat")
	AddCheckboxRow("Auto-ignore whispers from newly added players", "Ignore")
	AddCheckboxRow("Announce to Group (once per group, party or raid)", "AnnounceGroup")
	AddCheckboxRow("Guild Officer Auto-Ban", "Ban")

	y = y + 8
	local rankLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	rankLabel:SetPoint("TOPLEFT", 8, -y)
	rankLabel:SetTextColor(1, 1, 1)
	rankLabel:SetText("Guild rank filter (auto-ban applies at this rank index and below):")
	y = y + 20

	rankEdit = Skin:CreateEditBox(parent, 60, 20)
	rankEdit:SetPoint("TOPLEFT", 8, -y)
	rankEdit.editBox:SetText(tostring(JohnnysAddonHubBlackListConfig.Rank))
	rankEdit.editBox:SetScript("OnTextChanged", function(self)
		local n = tonumber(self:GetText())
		if n then
			JohnnysAddonHubBlackListConfig.Rank = n
		end
	end)

	local function Refresh()
		for _, e in ipairs(entries) do
			e.box:SetChecked(JohnnysAddonHubBlackListConfig[e.key])
		end
		if not rankEdit.editBox:HasFocus() then
			rankEdit.editBox:SetText(tostring(JohnnysAddonHubBlackListConfig.Rank))
		end
	end

	return { frame = parent, Refresh = Refresh }
end

----------------------------------------------------------------------------
-- Window shell / tab strip.
----------------------------------------------------------------------------
local function SelectTab(name)
	activeTab = name
	for tabName, tab in pairs(tabs) do
		if tabName == name then
			tab.frame:Show()
			tab.button:SetBackdropColor(0.22, 0.22, 0.22, 0.95)
			tab.button:SetBackdropBorderColor(0.7, 0.7, 0.7, 1)
		else
			tab.frame:Hide()
			tab.button:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
			tab.button:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
		end
	end
	if tabs[name] and tabs[name].Refresh then
		tabs[name].Refresh()
	end
end

local function BuildFrame()
	mainFrame = CreateFrame("Frame", "JohnnysAddonHubBlackListFrame", UIParent)
	mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
	mainFrame:SetPoint("RIGHT", UIParent, "RIGHT", -20, 0)
	mainFrame:SetFrameStrata("DIALOG")
	mainFrame:SetMovable(true)
	mainFrame:EnableMouse(true)
	mainFrame:RegisterForDrag("LeftButton")
	mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
	mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
	Skin:StylePanel(mainFrame, 0.95)
	mainFrame:Hide()

	-- Per-window scale/opacity (see Modules\WindowSettings.lua). Guarded so a
	-- stale .toc (client not fully restarted after the file was added) just
	-- skips the feature instead of erroring the whole window.
	if JohnnysBlackList.WindowSettings then
		JohnnysBlackList.WindowSettings:Register(mainFrame, "main", "Blacklist")
	end

	local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	title:SetPoint("TOP", 0, -16)
	title:SetText("Blacklist")

	local close = Skin:CreateButton(mainFrame, 20, 20, "X")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() BlackListUI:Toggle() end)

	JohnnysBlackList.VersionCheck:AttachNotice(mainFrame)

	if JohnnysBlackList.WindowSettings then
		JohnnysBlackList.WindowSettings:AttachButton(mainFrame)
	end

	local tabX = 16
	for _, name in ipairs(tabOrder) do
		local btn = Skin:CreateButton(mainFrame, 100, TAB_HEIGHT, name)
		btn:SetPoint("TOPLEFT", tabX, -44)
		btn:SetScript("OnClick", function() SelectTab(name) end)
		tabX = tabX + 104

		local tabFrame = CreateFrame("Frame", nil, mainFrame)
		tabFrame:SetPoint("TOPLEFT", 16, -76)
		tabFrame:SetPoint("BOTTOMRIGHT", -16, 16)
		tabFrame:Hide()

		tabs[name] = { button = btn, frame = tabFrame }
	end

	tabs["List"].Refresh = BuildListTab(tabs["List"].frame).Refresh
	tabs["Settings"].Refresh = BlackListUI.BuildSettingsTab(tabs["Settings"].frame).Refresh

	mainFrame:SetScript("OnShow", function()
		SelectTab(activeTab or "List")
	end)
	mainFrame:SetScript("OnHide", function()
		if historyPopout then
			historyPopout:Hide()
			historyPopout.owner = nil
		end
		if editPopout then
			editPopout:Hide()
			editPopout.owner = nil
		end
	end)
end

function BlackListUI:Toggle()
	if not mainFrame then
		BuildFrame()
	end
	if mainFrame:IsShown() then
		mainFrame:Hide()
	else
		mainFrame:Show()
	end
end
