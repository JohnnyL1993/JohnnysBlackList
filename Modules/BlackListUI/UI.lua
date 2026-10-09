-- Blacklist window, in the suite's "workshop rack" look.
--
-- List tab: a search box and sort toggles over a scrolling list of players
-- (two-line rows: name/level/class and when they were added, then the latest
-- reason). Selecting a row opens that player in the details panel on the
-- right - editable name/level/class/race, the two per-player switches, when
-- they were last seen, and their full add history with editable reasons.
-- Remove is one click with a timed Undo. Settings tab: alert options, plus
-- guild auto-ban in its own confirmed section.
--
-- Built with plain CreateFrame/Skin widgets. No UIDropDownMenu/AceGUI.
JohnnysBlackList.BlackListUI = JohnnysBlackList.BlackListUI or {}
local BlackListUI = JohnnysBlackList.BlackListUI
local Skin = JohnnysBlackList.Skin

local FRAME_WIDTH, FRAME_HEIGHT = 760, 520
local PAD = 12
local HEADER_HEIGHT = 28
local TAB_WIDTH, TAB_HEIGHT = 96, 26

local LIST_WIDTH = 430
local LIST_TOP = 28
local LIST_HEIGHT = 346
local ROW_HEIGHT = 36
-- The list's scrollbar renders just outside the scrollframe's own width.
local DETAIL_X = LIST_WIDTH + 28
local DETAIL_WIDTH = FRAME_WIDTH - PAD * 2 - DETAIL_X
local DETAIL_PAD = 10
local DETAIL_INNER = DETAIL_WIDTH - DETAIL_PAD * 2
-- History entries visible at once in the details panel; the < > buttons page.
local HISTORY_SHOWN = 3
local HISTORY_LINE_HEIGHT = 38
-- How long the "Removed X - Undo" bar stays up.
local UNDO_SECONDS = 12

-- "Workshop rack" palette shared with the Addon Hub drawer: blue-black
-- panels, 1px rules, one lime accent. Skin.lua uses the same values.
local C = {
	ground = { 0.063, 0.078, 0.086 },
	panel = { 0.090, 0.114, 0.125 },
	raised = { 0.122, 0.153, 0.169 },
	rule = { 0.180, 0.224, 0.243 },
	rule2 = { 0.243, 0.298, 0.322 },
	text = { 0.902, 0.925, 0.918 },
	muted = { 0.604, 0.659, 0.651 },
	dim = { 0.560, 0.620, 0.610 },
	accent = { 0.725, 0.886, 0.290 },
	short = { 1.000, 0.450, 0.400 },
}
local FONT_HEAD = "Fonts\\ARIALN.TTF"

-- Heading text (titles, labels, row numbers). Arial Narrow gets thin and hard
-- to read below about 14px, so only the larger sizes use it.
local function Heading(parent, size, color)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	if size < 14 then
		fs:SetFont("Fonts\\FRIZQT__.TTF", math.max(10, size - 1))
	else
		fs:SetFont(FONT_HEAD, size)
	end
	fs:SetTextColor(color[1], color[2], color[3])
	return fs
end

local function Body(parent, color)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	fs:SetJustifyH("LEFT")
	fs:SetTextColor(color[1], color[2], color[3])
	return fs
end

local function Solid(parent, layer, color)
	local tex = parent:CreateTexture(nil, layer)
	tex:SetTexture(Skin.WHITE)
	tex:SetVertexColor(color[1], color[2], color[3], 1)
	return tex
end

-- Turns a Skin button into the one filled lime "main action" of a view.
local function MakePrimary(btn)
	local function Idle()
		btn:SetBackdropColor(C.accent[1], C.accent[2], C.accent[3], 1)
	end
	btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
	btn.text:SetTextColor(C.ground[1], C.ground[2], C.ground[3])
	btn:SetScript("OnMouseDown", function()
		btn:SetBackdropColor(0.580, 0.710, 0.230, 1)
	end)
	btn:SetScript("OnMouseUp", Idle)
	Idle()
end

-- A Skin button that stays lit (lime border, lighter fill) while selected.
local function PaintToggle(btn, on)
	if on then
		btn:SetBackdropColor(C.raised[1], C.raised[2], C.raised[3], 0.95)
		btn:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
		btn.text:SetTextColor(C.text[1], C.text[2], C.text[3])
	else
		btn:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 0.95)
		btn:SetBackdropBorderColor(C.rule2[1], C.rule2[2], C.rule2[3], 1)
		btn.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
	end
end

local mainFrame, listScroll, listContent, countText, emptyText
local searchEdit, addNameEdit, addReasonEdit
local undoBar
local detail = {}
local rows = {}
local tabs = {}
local tabOrder = { "List", "Settings" }
local activeTab

-- The selected entry is held by reference (not by name), so it survives the
-- player being renamed from the details panel.
local selectedEntry
local historyOffset = 0

-- Sort: key plus direction. Each key has a natural first direction (names
-- A-Z, everything else newest/most first); clicking the active key flips it.
local SORTS = {
	{ key = "name", label = "Name", desc = false },
	{ key = "added", label = "Added", desc = true },
	{ key = "times", label = "Times", desc = true },
	{ key = "seen", label = "Seen", desc = true },
}
local sortKey, sortDesc = "name", false
local sortButtons = {}

----------------------------------------------------------------------------
-- Entry helpers
----------------------------------------------------------------------------
local function LatestReason(entry)
	local latest = entry.history[1]
	return (latest and latest.reason ~= "" and latest.reason) or nil
end

local function LatestDate(entry)
	return (entry.history[1] and entry.history[1].date) or 0
end

local function FirstDate(entry)
	local oldest = entry.history[#entry.history]
	return (oldest and oldest.date) or 0
end

local function SeenDate(entry)
	return (entry.seen and entry.seen.date) or 0
end

local function ShortDate(t)
	return date("%d %b %Y", t)
end

local function Ago(t)
	local seconds = time() - t
	if seconds < 60 then
		return "just now"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m ago"
	elseif seconds < 86400 then
		return math.floor(seconds / 3600) .. "h ago"
	end
	return math.floor(seconds / 86400) .. "d ago"
end

local function InfoText(entry)
	if entry.level ~= "" and entry.class ~= "" then
		return "Lvl " .. entry.level .. " " .. entry.class
	elseif entry.class ~= "" then
		return entry.class
	elseif entry.level ~= "" then
		return "Lvl " .. entry.level
	end
	return ""
end

local function IsListed(entry)
	if not entry then
		return false
	end
	for _, e in ipairs(BlackListUI:GetList()) do
		if e == entry then
			return true
		end
	end
	return false
end

local function SortNumber(entry)
	if sortKey == "added" then
		return LatestDate(entry)
	elseif sortKey == "times" then
		return #entry.history
	end
	return SeenDate(entry)
end

-- The saved list stays in its own (alphabetical) order - searching and
-- sorting only shape this view of it.
local function BuildView()
	local query = searchEdit and string.lower(searchEdit.editBox:GetText() or "") or ""
	local view = {}
	for _, entry in ipairs(BlackListUI:GetList()) do
		local matches = (query == "")
		if not matches then
			if string.find(string.lower(entry.name), query, 1, true) then
				matches = true
			else
				for _, h in ipairs(entry.history) do
					if h.reason and string.find(string.lower(h.reason), query, 1, true) then
						matches = true
						break
					end
				end
			end
		end
		if matches then
			table.insert(view, entry)
		end
	end

	table.sort(view, function(a, b)
		if sortKey ~= "name" then
			local av, bv = SortNumber(a), SortNumber(b)
			if av ~= bv then
				if sortDesc then
					return av > bv
				end
				return av < bv
			end
		end
		local an, bn = string.lower(a.name), string.lower(b.name)
		if sortKey == "name" and sortDesc then
			return an > bn
		end
		return an < bn
	end)
	return view
end

----------------------------------------------------------------------------
-- Details panel
----------------------------------------------------------------------------
local RefreshDetail

local function BuildDetail(parent)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetPoint("TOPLEFT", parent, "TOPLEFT", DETAIL_X, 0)
	panel:SetSize(DETAIL_WIDTH, LIST_TOP + LIST_HEIGHT)
	Skin:StylePanel(panel, 1)
	panel:SetBackdropColor(C.panel[1], C.panel[2], C.panel[3], 1)
	detail.panel = panel

	detail.emptyText = Body(panel, C.muted)
	detail.emptyText:SetPoint("TOPLEFT", DETAIL_PAD, -DETAIL_PAD)
	detail.emptyText:SetWidth(DETAIL_INNER)
	detail.emptyText:SetText("Select a player to see their history, edit their details, or remove them.")

	local body = CreateFrame("Frame", nil, panel)
	body:SetAllPoints()
	body:Hide()
	detail.body = body

	detail.name = Heading(body, 16, C.text)
	detail.name:SetPoint("TOPLEFT", DETAIL_PAD, -8)

	detail.meta = Body(body, C.muted)
	detail.meta:SetPoint("TOPLEFT", DETAIL_PAD, -30)
	detail.meta:SetWidth(DETAIL_INNER)

	detail.seen = Body(body, C.muted)
	detail.seen:SetPoint("TOPLEFT", DETAIL_PAD, -44)
	detail.seen:SetWidth(DETAIL_INNER)

	local function Field(label, x, y, width)
		local fs = Heading(body, 10, C.muted)
		fs:SetPoint("TOPLEFT", x, y)
		fs:SetText(label)
		local edit = Skin:CreateEditBox(body, width, 18)
		edit:SetPoint("TOPLEFT", x, y - 12)
		return edit
	end

	detail.nameEdit = Field("NAME", DETAIL_PAD, -64, 150)
	detail.levelEdit = Field("LEVEL", DETAIL_PAD + 158, -64, 44)
	detail.classEdit = Field("CLASS", DETAIL_PAD, -100, 124)
	detail.raceEdit = Field("RACE", DETAIL_PAD + 132, -100, 124)

	detail.saveBtn = Skin:CreateButton(body, 90, 20, "Save details")
	detail.saveBtn:SetPoint("TOPLEFT", DETAIL_PAD, -138)
	detail.saveBtn:SetScript("OnClick", function()
		if not selectedEntry then
			return
		end
		local ok, err = BlackListUI:EditPlayer(
			selectedEntry.name,
			detail.nameEdit.editBox:GetText(),
			detail.levelEdit.editBox:GetText(),
			detail.classEdit.editBox:GetText(),
			detail.raceEdit.editBox:GetText()
		)
		if ok then
			detail.nameEdit.editBox:ClearFocus()
			detail.levelEdit.editBox:ClearFocus()
			detail.classEdit.editBox:ClearFocus()
			detail.raceEdit.editBox:ClearFocus()
			detail.status:SetTextColor(C.accent[1], C.accent[2], C.accent[3])
			detail.status:SetText("Saved.")
			RefreshDetail()
		else
			detail.status:SetTextColor(C.short[1], C.short[2], C.short[3])
			detail.status:SetText(err or "")
		end
	end)

	detail.status = Body(body, C.short)
	detail.status:SetPoint("LEFT", detail.saveBtn, "RIGHT", 8, 0)
	detail.status:SetWidth(DETAIL_INNER - 98)

	-- The two per-player switches, with what they actually do spelled out
	-- (these were the unlabelled "Ign" / "Warn" columns).
	local function Switch(label, y, onToggle, tipTitle, tipText)
		local box = Skin:CreateCheckbox(body, 16, false, onToggle)
		box:SetPoint("TOPLEFT", DETAIL_PAD, y)
		local fs = Body(body, C.text)
		fs:SetPoint("LEFT", box, "RIGHT", 8, 0)
		fs:SetText(label)
		box:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
			GameTooltip:AddLine(tipTitle, 1, 1, 1)
			GameTooltip:AddLine(tipText, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		box:SetScript("OnLeave", function() GameTooltip:Hide() end)
		return box
	end

	detail.ignoreBox = Switch("Ignore their whispers and invites", -166, function(state)
		if selectedEntry then
			BlackListUI:SetIgnore(selectedEntry.name, state)
			BlackListUI:RefreshWindow()
		end
	end, "Ignore", "Their whispers are hidden (they get one automatic \"Ignored\" reply) and their group invites are declined for you.")

	detail.warnBox = Switch("Alert me when I see them", -188, function(state)
		if selectedEntry then
			BlackListUI:SetWarn(selectedEntry.name, state)
			BlackListUI:RefreshWindow()
		end
	end, "Alert", "Warns you when you target or mouse over them, when they whisper or invite you, and when they are in your group or guild. Group announcements and sightings also only happen with this on.")

	local historyLabel = Heading(body, 10, C.muted)
	historyLabel:SetPoint("TOPLEFT", DETAIL_PAD, -214)
	historyLabel:SetText("HISTORY")

	local historyRule = Solid(body, "ARTWORK", C.rule)
	historyRule:SetPoint("TOPLEFT", body, "TOPLEFT", DETAIL_PAD, -228)
	historyRule:SetWidth(DETAIL_INNER)
	historyRule:SetHeight(1)

	detail.newerBtn = Skin:CreateButton(body, 18, 16, "<")
	detail.olderBtn = Skin:CreateButton(body, 18, 16, ">")
	detail.olderBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -DETAIL_PAD, -210)
	detail.newerBtn:SetPoint("RIGHT", detail.olderBtn, "LEFT", -2, 0)
	detail.newerBtn:SetScript("OnClick", function()
		historyOffset = math.max(0, historyOffset - HISTORY_SHOWN)
		RefreshDetail()
	end)
	detail.olderBtn:SetScript("OnClick", function()
		historyOffset = historyOffset + HISTORY_SHOWN
		RefreshDetail()
	end)

	detail.historyRange = Body(body, C.muted)
	detail.historyRange:SetPoint("RIGHT", detail.newerBtn, "LEFT", -6, 0)

	detail.historyLines = {}
	for i = 1, HISTORY_SHOWN do
		local line = CreateFrame("Frame", nil, body)
		line:SetSize(DETAIL_INNER, HISTORY_LINE_HEIGHT - 2)
		line:SetPoint("TOPLEFT", DETAIL_PAD, -232 - (i - 1) * HISTORY_LINE_HEIGHT)

		line.dateText = Body(line, C.muted)
		line.dateText:SetPoint("TOPLEFT", 0, -1)
		line.dateText:SetWidth(DETAIL_INNER)

		line.reasonEdit = Skin:CreateEditBox(line, DETAIL_INNER - 52, 18)
		line.reasonEdit:SetPoint("TOPLEFT", 0, -15)
		line.reasonEdit.editBox:SetScript("OnTextChanged", function(self)
			if self:HasFocus() and selectedEntry and line.historyIndex then
				BlackListUI:EditHistoryReason(selectedEntry.name, line.historyIndex, self:GetText())
			end
		end)

		-- The box is one short line, so hovering shows the whole reason.
		line.reasonEdit.editBox:SetScript("OnEnter", function(self)
			local text = self:GetText() or ""
			if text ~= "" then
				GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
				GameTooltip:AddLine(text, 1, 1, 1, true)
				GameTooltip:Show()
			end
		end)
		line.reasonEdit.editBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
		line.reasonEdit.editBox:SetScript("OnEditFocusLost", function(self) self:SetCursorPosition(0) end)

		line.deleteBtn = Skin:CreateButton(line, 48, 18, "Delete")
		line.deleteBtn:SetPoint("LEFT", line.reasonEdit, "RIGHT", 4, 0)
		line.deleteBtn:SetScript("OnClick", function()
			if not selectedEntry or not line.historyIndex then
				return
			end
			local ok, err = BlackListUI:RemoveHistoryEntry(selectedEntry.name, line.historyIndex)
			if not ok then
				detail.status:SetTextColor(C.short[1], C.short[2], C.short[3])
				detail.status:SetText(err or "")
			end
		end)

		detail.historyLines[i] = line
	end

	detail.removeBtn = Skin:CreateButton(body, 150, 20, "Remove from Blacklist")
	detail.removeBtn:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", DETAIL_PAD, 8)
	detail.removeBtn.text:SetTextColor(C.short[1], C.short[2], C.short[3])
	detail.removeBtn:SetScript("OnClick", function()
		if selectedEntry then
			BlackListUI:RemovePlayer(selectedEntry.name)
		end
	end)
end

RefreshDetail = function()
	if not detail.panel then
		return
	end
	local entry = selectedEntry
	if not entry then
		detail.body:Hide()
		detail.emptyText:Show()
		return
	end
	detail.emptyText:Hide()
	detail.body:Show()

	detail.name:SetText(entry.name)

	local times = #entry.history
	local meta = "Added " .. ShortDate(FirstDate(entry))
	if times > 1 then
		meta = meta .. ", " .. times .. " times (latest " .. ShortDate(LatestDate(entry)) .. ")"
	end
	detail.meta:SetText(meta)

	if entry.seen and entry.seen.date then
		local seenText = "Last seen " .. Ago(entry.seen.date)
		if entry.seen.where and entry.seen.where ~= "" then
			seenText = seenText .. " (" .. entry.seen.where .. ")"
		end
		if (entry.seenCount or 0) > 1 then
			seenText = seenText .. ", " .. entry.seenCount .. " sightings"
		end
		detail.seen:SetText(seenText)
	else
		detail.seen:SetText("No sightings recorded yet.")
	end

	-- Fields are skipped while focused, so a redraw (every history keystroke
	-- triggers one) never stomps something mid-typing.
	if not detail.nameEdit.editBox:HasFocus() then
		detail.nameEdit.editBox:SetText(entry.name)
		detail.nameEdit.editBox:SetCursorPosition(0)
	end
	if not detail.levelEdit.editBox:HasFocus() then
		detail.levelEdit.editBox:SetText(entry.level or "")
		detail.levelEdit.editBox:SetCursorPosition(0)
	end
	if not detail.classEdit.editBox:HasFocus() then
		detail.classEdit.editBox:SetText(entry.class or "")
		detail.classEdit.editBox:SetCursorPosition(0)
	end
	if not detail.raceEdit.editBox:HasFocus() then
		detail.raceEdit.editBox:SetText(entry.race or "")
		detail.raceEdit.editBox:SetCursorPosition(0)
	end

	detail.ignoreBox:SetChecked(entry.ignore)
	detail.warnBox:SetChecked(entry.warn)

	if historyOffset >= times then
		historyOffset = math.max(0, math.floor((times - 1) / HISTORY_SHOWN) * HISTORY_SHOWN)
	end
	for i, line in ipairs(detail.historyLines) do
		local index = historyOffset + i
		local h = entry.history[index]
		if h then
			line.historyIndex = index
			line.dateText:SetText(date("%d %b %Y, %I:%M%p", h.date))
			if not line.reasonEdit.editBox:HasFocus() then
				line.reasonEdit.editBox:SetText(h.reason or "")
				-- SetText leaves the cursor at the end, which scrolls a long
				-- reason so only its last few letters show.
				line.reasonEdit.editBox:SetCursorPosition(0)
			end
			line:Show()
		else
			line.historyIndex = nil
			line:Hide()
		end
	end

	if times > HISTORY_SHOWN then
		detail.historyRange:SetText(string.format("%d-%d of %d", historyOffset + 1, math.min(times, historyOffset + HISTORY_SHOWN), times))
		detail.historyRange:Show()
		detail.newerBtn:Show()
		detail.olderBtn:Show()
		if historyOffset > 0 then
			detail.newerBtn:Enable()
		else
			detail.newerBtn:Disable()
		end
		if historyOffset + HISTORY_SHOWN < times then
			detail.olderBtn:Enable()
		else
			detail.olderBtn:Disable()
		end
	else
		detail.historyRange:Hide()
		detail.newerBtn:Hide()
		detail.olderBtn:Hide()
	end
end

local function SelectEntry(entry)
	if selectedEntry ~= entry then
		historyOffset = 0
		if detail.status then
			detail.status:SetText("")
		end
		-- Drop focus so the fields reload for the newly selected player.
		if detail.nameEdit then
			detail.nameEdit.editBox:ClearFocus()
			detail.levelEdit.editBox:ClearFocus()
			detail.classEdit.editBox:ClearFocus()
			detail.raceEdit.editBox:ClearFocus()
			for _, line in ipairs(detail.historyLines) do
				line.reasonEdit.editBox:ClearFocus()
			end
		end
	end
	selectedEntry = entry
end

----------------------------------------------------------------------------
-- List tab
----------------------------------------------------------------------------
local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(LIST_WIDTH, ROW_HEIGHT)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)

	row.bg = row:CreateTexture(nil, "BACKGROUND")
	row.bg:SetAllPoints()
	row.bg:SetTexture(Skin.WHITE)
	row.bg:SetVertexColor(C.raised[1], C.raised[2], C.raised[3], 1)
	row.bg:Hide()

	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(Skin.WHITE)
	highlight:SetVertexColor(1, 1, 1, 0.06)

	row.bar = Solid(row, "ARTWORK", C.accent)
	row.bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
	row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	row.bar:SetWidth(2)
	row.bar:Hide()

	local rule = Solid(row, "BORDER", C.rule)
	rule:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
	rule:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	rule:SetHeight(1)

	row.num = Heading(row, 14, C.accent)
	row.num:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)

	row.name = Body(row, C.text)
	row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 36, -5)

	row.info = Body(row, C.muted)
	row.info:SetPoint("LEFT", row.name, "RIGHT", 8, 0)

	row.meta = Body(row, C.muted)
	row.meta:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -5)
	row.meta:SetJustifyH("RIGHT")

	row.flags = Body(row, C.dim)
	row.flags:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -20)
	row.flags:SetJustifyH("RIGHT")

	row.reason = Body(row, C.muted)
	row.reason:SetPoint("TOPLEFT", row, "TOPLEFT", 36, -20)
	row.reason:SetWidth(LIST_WIDTH - 36 - 130)
	row.reason:SetHeight(11)
	-- One line, cut off at the right edge - without this the text wraps at a
	-- word break and a reason is cut after its first word or two.
	if row.reason.SetWordWrap then
		row.reason:SetWordWrap(false)
	end

	row:SetScript("OnClick", function(self)
		SelectEntry(self.entry)
		BlackListUI:RefreshWindow()
	end)

	return row
end

local function RefreshSortButtons()
	for _, sort in ipairs(SORTS) do
		local btn = sortButtons[sort.key]
		if btn then
			local active = (sort.key == sortKey)
			btn.text:SetText(active and (sort.label .. (sortDesc and "  v" or "  ^")) or sort.label)
			PaintToggle(btn, active)
		end
	end
end

local function RefreshUndoBar()
	if not undoBar then
		return
	end
	local last = BlackListUI.lastRemoved
	if last and (GetTime() - last.at) < UNDO_SECONDS then
		undoBar.text:SetText("Removed " .. last.entry.name .. ".")
		undoBar:Show()
	else
		undoBar:Hide()
	end
end

function BlackListUI:RefreshWindow()
	if not mainFrame or not listContent or not mainFrame:IsShown() then
		return
	end

	if selectedEntry and not IsListed(selectedEntry) then
		SelectEntry(nil)
	end

	local total = #self:GetList()
	local view = BuildView()
	local n = #view

	for i = 1, n do
		local entry = view[i]
		local row = rows[i]
		if not row then
			row = CreateRow(listContent, i)
			rows[i] = row
		end

		row.entry = entry
		row.num:SetText(string.format("%02d", i))
		row.name:SetText(entry.name)
		row.info:SetText(InfoText(entry))

		local times = #entry.history
		local meta = ShortDate(LatestDate(entry))
		if times > 1 then
			meta = times .. " times  -  " .. meta
		end
		row.meta:SetText(meta)

		local reason = LatestReason(entry)
		row.reason:SetText(reason and string.gsub(reason, "%s+", " ") or "No reason given")
		if reason then
			row.reason:SetTextColor(C.text[1], C.text[2], C.text[3])
		else
			row.reason:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
		end

		local flags = {}
		if entry.ignore then
			table.insert(flags, "ignoring")
		end
		if not entry.warn then
			table.insert(flags, "alerts off")
		end
		row.flags:SetText(table.concat(flags, ", "))

		if entry == selectedEntry then
			row.bg:Show()
			row.bar:Show()
		else
			row.bg:Hide()
			row.bar:Hide()
		end
		row:Show()
	end

	for i = n + 1, #rows do
		rows[i].entry = nil
		rows[i]:Hide()
	end
	listContent:SetHeight(math.max(20, n * ROW_HEIGHT))

	if countText then
		if n < total then
			countText:SetText(n .. " OF " .. total .. " PLAYERS")
		else
			countText:SetText(total == 1 and "1 PLAYER" or (total .. " PLAYERS"))
		end
	end

	if emptyText then
		if n > 0 then
			emptyText:Hide()
		else
			if total == 0 then
				emptyText:SetText("Nobody is blacklisted yet. Add a player below, target one and use Add Target, or right-click a player and choose Blacklist.")
			else
				emptyText:SetText("No blacklisted player matches that search.")
			end
			emptyText:Show()
		end
	end

	RefreshSortButtons()
	RefreshUndoBar()
	RefreshDetail()
end

local function BuildListTab(parent)
	-- Toolbar: search on the left, sort toggles on the right of the list.
	searchEdit = Skin:CreateEditBox(parent, 170, 20)
	searchEdit:SetPoint("TOPLEFT", 0, 0)
	searchEdit.editBox:SetScript("OnTextChanged", function()
		BlackListUI:RefreshWindow()
	end)
	local searchHint = Body(searchEdit, C.dim)
	searchHint:SetPoint("LEFT", searchEdit, "LEFT", 6, 0)
	searchHint:SetText("Search name or reason")
	searchEdit.editBox:HookScript("OnTextChanged", function(self)
		if (self:GetText() or "") == "" and not self:HasFocus() then
			searchHint:Show()
		else
			searchHint:Hide()
		end
	end)
	searchEdit.editBox:HookScript("OnEditFocusGained", function() searchHint:Hide() end)
	searchEdit.editBox:HookScript("OnEditFocusLost", function(self)
		if (self:GetText() or "") == "" then
			searchHint:Show()
		end
	end)

	local sortLabel = Heading(parent, 10, C.muted)
	sortLabel:SetPoint("LEFT", searchEdit, "RIGHT", 12, 0)
	sortLabel:SetText("SORT")

	local anchor = sortLabel
	for i, sort in ipairs(SORTS) do
		local btn = Skin:CreateButton(parent, 50, 20, sort.label)
		btn:SetPoint("LEFT", anchor, "RIGHT", (i == 1) and 6 or 2, 0)
		btn:SetScript("OnClick", function()
			if sortKey == sort.key then
				sortDesc = not sortDesc
			else
				sortKey, sortDesc = sort.key, sort.desc
			end
			BlackListUI:RefreshWindow()
		end)
		btn:SetScript("OnMouseUp", function(self) PaintToggle(self, sortKey == sort.key) end)
		sortButtons[sort.key] = btn
		anchor = btn
	end

	listScroll = CreateFrame("ScrollFrame", "JohnnysAddonHubBlackListScroll", parent, "UIPanelScrollFrameTemplate")
	listScroll:SetPoint("TOPLEFT", 0, -LIST_TOP)
	listScroll:SetSize(LIST_WIDTH, LIST_HEIGHT)

	listContent = CreateFrame("Frame", nil, listScroll)
	listContent:SetSize(LIST_WIDTH, 20)
	listScroll:SetScrollChild(listContent)

	emptyText = Body(parent, C.muted)
	emptyText:SetPoint("TOPLEFT", listScroll, "TOPLEFT", 8, -10)
	emptyText:SetWidth(LIST_WIDTH - 16)
	emptyText:Hide()

	-- Undo bar: sits over the bottom of the list for a few seconds after a
	-- Remove, since removing deletes the player's whole history.
	undoBar = CreateFrame("Frame", nil, parent)
	undoBar:SetPoint("BOTTOMLEFT", listScroll, "BOTTOMLEFT", 0, 0)
	undoBar:SetSize(LIST_WIDTH, 26)
	undoBar:SetFrameLevel(listScroll:GetFrameLevel() + 20)
	Skin:StylePanel(undoBar, 1)
	undoBar:SetBackdropColor(C.raised[1], C.raised[2], C.raised[3], 1)
	undoBar:SetBackdropBorderColor(C.accent[1], C.accent[2], C.accent[3], 1)
	undoBar:EnableMouse(true)
	undoBar:Hide()
	undoBar.text = Body(undoBar, C.text)
	undoBar.text:SetPoint("LEFT", 10, 0)
	local undoBtn = Skin:CreateButton(undoBar, 60, 18, "Undo")
	undoBtn:SetPoint("RIGHT", -4, 0)
	undoBtn:SetScript("OnClick", function()
		local ok, entry = BlackListUI:UndoRemove()
		if ok then
			SelectEntry(entry)
		end
		BlackListUI:RefreshWindow()
	end)
	MakePrimary(undoBtn)
	undoBar:SetScript("OnUpdate", function(self)
		local last = BlackListUI.lastRemoved
		if not last or (GetTime() - last.at) >= UNDO_SECONDS then
			self:Hide()
		end
	end)

	BuildDetail(parent)

	-- Add strip: labelled Name/Reason fields with the two add buttons on the
	-- same line, under a rule that closes off the list.
	local addY = -(LIST_TOP + LIST_HEIGHT + 8)

	local addRule = Solid(parent, "ARTWORK", C.rule)
	addRule:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, addY)
	addRule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, addY)
	addRule:SetHeight(1)

	local nameLabel = Heading(parent, 10, C.muted)
	nameLabel:SetPoint("TOPLEFT", 0, addY - 8)
	nameLabel:SetText("NAME")

	addNameEdit = Skin:CreateEditBox(parent, 140, 20)
	addNameEdit:SetPoint("TOPLEFT", 0, addY - 22)

	addReasonEdit = Skin:CreateEditBox(parent, 320, 20)
	addReasonEdit:SetPoint("LEFT", addNameEdit, "RIGHT", 8, 0)

	local reasonLabel = Heading(parent, 10, C.muted)
	reasonLabel:SetPoint("BOTTOMLEFT", addReasonEdit, "TOPLEFT", 0, 4)
	reasonLabel:SetText("REASON")

	local function AddTyped()
		local name = addNameEdit.editBox:GetText()
		local reason = addReasonEdit.editBox:GetText()
		if name and name ~= "" then
			local entry = BlackListUI:AddPlayer(name, reason, JohnnysAddonHubBlackListConfig.Ignore)
			addNameEdit.editBox:SetText("")
			addReasonEdit.editBox:SetText("")
			if entry then
				SelectEntry(entry)
				BlackListUI:RefreshWindow()
			end
		end
	end

	-- Tab hops from Name to Reason; Enter in either field adds the player.
	addNameEdit.editBox:SetScript("OnTabPressed", function()
		addReasonEdit.editBox:SetFocus()
	end)
	addNameEdit.editBox:SetScript("OnEnterPressed", function(self)
		AddTyped()
		self:ClearFocus()
	end)
	addReasonEdit.editBox:SetScript("OnEnterPressed", function(self)
		AddTyped()
		self:ClearFocus()
	end)

	local addBtn = Skin:CreateButton(parent, 70, 20, "Add")
	addBtn:SetPoint("LEFT", addReasonEdit, "RIGHT", 8, 0)
	addBtn:SetScript("OnClick", AddTyped)
	MakePrimary(addBtn)

	local addTargetBtn = Skin:CreateButton(parent, 90, 20, "Add Target")
	addTargetBtn:SetPoint("LEFT", addBtn, "RIGHT", 8, 0)
	addTargetBtn:SetScript("OnClick", function()
		local targetName = UnitName("target")
		BlackListUI:AddFromUnit("target", addReasonEdit.editBox:GetText())
		addReasonEdit.editBox:SetText("")
		local entry = targetName and BlackListUI:GetEntryByName(targetName)
		if entry then
			SelectEntry(entry)
			BlackListUI:RefreshWindow()
		end
	end)

	return { frame = parent, Refresh = function() BlackListUI:RefreshWindow() end }
end

----------------------------------------------------------------------------
-- Settings tab.
----------------------------------------------------------------------------
-- Turning guild auto-ban on kicks people and posts in guild chat on its own,
-- so it asks first. `data` is the checkbox, to untick it again on Cancel.
StaticPopupDialogs["JAHUB_BLACKLIST_BAN_CONFIRM"] = {
	text = "Turn on guild auto-ban?\n\nWhenever a blacklisted player is found in your guild at or below the chosen rank, this will remove them from the guild, announce it in guild chat, and whisper them - without asking you each time.",
	button1 = "Turn on",
	button2 = "Cancel",
	OnAccept = function(self, data)
		JohnnysAddonHubBlackListConfig.Ban = true
		if data then
			data:SetChecked(true)
		end
	end,
	OnCancel = function(self, data)
		JohnnysAddonHubBlackListConfig.Ban = false
		if data then
			data:SetChecked(false)
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- Config.Rank is a 0-based guild rank index (0 = Guild Master), the same
-- numbering GetGuildRosterInfo returns; GuildControlGetRankName is 1-based.
local function RankName(rankIndex)
	local name = GuildControlGetRankName and GuildControlGetRankName(rankIndex + 1)
	if name and name ~= "" then
		return name
	end
	return "Rank " .. rankIndex
end

function BlackListUI.BuildSettingsTab(parent)
	local y = 0
	local entries = {}
	local rankButton, rankMenu

	local function AddSection(text, color)
		if y > 0 then
			y = y + 14
		end
		local fs = Heading(parent, 10, color or C.muted)
		fs:SetPoint("TOPLEFT", 0, -y)
		fs:SetText(text)

		local rule = Solid(parent, "ARTWORK", color or C.rule)
		rule:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(y + 15))
		rule:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(y + 15))
		rule:SetHeight(1)
		y = y + 24
	end

	local function AddCheckboxRow(label, key, onToggle)
		local box
		box = Skin:CreateCheckbox(parent, 16, JohnnysAddonHubBlackListConfig[key], onToggle or function(state)
			JohnnysAddonHubBlackListConfig[key] = state
		end)
		box:SetPoint("TOPLEFT", 0, -y)

		local fs = Body(parent, C.text)
		fs:SetPoint("LEFT", box, "RIGHT", 8, 0)
		fs:SetText(label)

		table.insert(entries, { box = box, key = key })
		y = y + 24
		return box
	end

	local function AddNote(text, color)
		local fs = Body(parent, color or C.muted)
		fs:SetPoint("TOPLEFT", 24, -y + 4)
		fs:SetWidth(FRAME_WIDTH - PAD * 2 - 24)
		fs:SetText(text)
		y = y + math.max(14, (fs:GetStringHeight() or 12) + 4)
	end

	AddSection("WHEN A BLACKLISTED PLAYER IS SIGHTED")
	AddCheckboxRow("Play a sound", "Sound")
	AddCheckboxRow("Show a warning at screen centre", "Center")
	AddCheckboxRow("Show the reason in my chat window", "Chat")
	AddCheckboxRow("Announce them to my party or raid", "AnnounceGroup")
	AddNote("Posts their name and your latest reason in party or raid chat, where everyone in the group can read it. Once per player per group.")

	AddSection("WHEN ADDING A PLAYER")
	AddCheckboxRow("Ignore whispers and invites from newly added players", "Ignore")

	AddSection("GUILD AUTO-BAN", C.short)
	local banBox
	banBox = AddCheckboxRow("Remove blacklisted players from my guild automatically", "Ban", function(state)
		if state then
			-- Stays off until the confirmation is accepted.
			JohnnysAddonHubBlackListConfig.Ban = false
			StaticPopup_Show("JAHUB_BLACKLIST_BAN_CONFIRM", nil, nil, banBox)
		else
			JohnnysAddonHubBlackListConfig.Ban = false
		end
	end)
	AddNote("Kicks them, announces the ban in guild chat and whispers them. Needs guild-remove permission, only affects ranks below your own, and skips anyone with \"kick\" in their officer note.", C.short)

	y = y + 6
	local rankLabel = Body(parent, C.text)
	rankLabel:SetPoint("TOPLEFT", 24, -y - 4)
	rankLabel:SetText("Applies to this rank and everyone below it:")

	rankButton = Skin:CreateButton(parent, 200, 20, "")
	rankButton:SetPoint("LEFT", rankLabel, "RIGHT", 10, 0)

	rankMenu = CreateFrame("Frame", nil, parent)
	rankMenu:SetWidth(200)
	rankMenu:SetPoint("TOPLEFT", rankButton, "BOTTOMLEFT", 0, -2)
	rankMenu:SetFrameLevel(parent:GetFrameLevel() + 20)
	Skin:StylePanel(rankMenu, 1)
	rankMenu:EnableMouse(true)
	rankMenu:Hide()
	rankMenu.buttons = {}

	local function RefreshRank()
		if IsInGuild() then
			rankButton.text:SetText(RankName(JohnnysAddonHubBlackListConfig.Rank or 0) .. "  v")
			rankButton:Enable()
			rankButton.text:SetTextColor(C.text[1], C.text[2], C.text[3])
		else
			rankButton.text:SetText("You are not in a guild")
			rankButton:Disable()
			rankButton.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
			rankMenu:Hide()
		end
	end

	rankButton:SetScript("OnClick", function()
		if rankMenu:IsShown() then
			rankMenu:Hide()
			return
		end
		local count = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
		if count < 1 then
			count = 10
		end
		for i = 1, count do
			local btn = rankMenu.buttons[i]
			if not btn then
				btn = Skin:CreateButton(rankMenu, 196, 20, "")
				btn:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
				rankMenu.buttons[i] = btn
			end
			btn.text:SetText(RankName(i - 1))
			btn:SetScript("OnClick", function()
				JohnnysAddonHubBlackListConfig.Rank = i - 1
				rankMenu:Hide()
				RefreshRank()
			end)
			btn:Show()
		end
		for i = count + 1, #rankMenu.buttons do
			rankMenu.buttons[i]:Hide()
		end
		rankMenu:SetHeight(count * 20 + 4)
		rankMenu:Show()
	end)

	local function Refresh()
		for _, e in ipairs(entries) do
			e.box:SetChecked(JohnnysAddonHubBlackListConfig[e.key])
		end
		rankMenu:Hide()
		RefreshRank()
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
			tab.button.text:SetTextColor(C.text[1], C.text[2], C.text[3])
			tab.button.bar:Show()
		else
			tab.frame:Hide()
			tab.button.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
			tab.button.bar:Hide()
		end
	end
	if tabs[name] and tabs[name].Refresh then
		tabs[name].Refresh()
	end
end

-- A numbered text tab ("01  LIST") with a lime underline when active, in
-- place of a boxed button - same numbering idea as the Addon Hub drawer.
local function CreateTabButton(parent, index, name)
	local btn = CreateFrame("Button", nil, parent)
	btn:SetSize(TAB_WIDTH, TAB_HEIGHT)

	btn.text = Heading(btn, 12, C.muted)
	btn.text:SetPoint("LEFT", btn, "LEFT", 4, 0)
	btn.text:SetText(string.format("%02d  %s", index, string.upper(name)))

	btn.bar = Solid(btn, "ARTWORK", C.accent)
	btn.bar:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 0, 0)
	btn.bar:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
	btn.bar:SetHeight(2)
	btn.bar:Hide()

	btn:SetScript("OnEnter", function(self)
		self.text:SetTextColor(C.text[1], C.text[2], C.text[3])
	end)
	btn:SetScript("OnLeave", function(self)
		if activeTab ~= name then
			self.text:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
		end
	end)
	btn:SetScript("OnClick", function() SelectTab(name) end)

	return btn
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

	-- Title bar: a lighter strip holding the title, the player count, and the
	-- Cfg/close buttons on the right.
	local headBg = Solid(mainFrame, "BORDER", C.panel)
	headBg:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 1, -1)
	headBg:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -1, -1)
	headBg:SetHeight(HEADER_HEIGHT - 1)

	local headRule = Solid(mainFrame, "ARTWORK", C.rule)
	headRule:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 1, -HEADER_HEIGHT)
	headRule:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -1, -HEADER_HEIGHT)
	headRule:SetHeight(1)

	local title = Heading(mainFrame, 16, C.text)
	title:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", PAD, -7)
	title:SetText("BLACKLIST")

	countText = Heading(mainFrame, 11, C.muted)
	countText:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)
	countText:SetText("0 PLAYERS")

	local close = Skin:CreateButton(mainFrame, 20, 20, "X")
	close:SetPoint("TOPRIGHT", -4, -4)
	close:SetScript("OnClick", function() BlackListUI:Toggle() end)

	-- The update notice anchors itself to its host's top-left corner, so give
	-- it a host that starts to the right of the title and count.
	local noticeHost = CreateFrame("Frame", nil, mainFrame)
	noticeHost:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 230, 2)
	noticeHost:SetSize(300, HEADER_HEIGHT)
	JohnnysBlackList.VersionCheck:AttachNotice(noticeHost)

	if JohnnysBlackList.WindowSettings then
		JohnnysBlackList.WindowSettings:AttachButton(mainFrame)
	end

	local tabTop = -(HEADER_HEIGHT + 1)
	local tabRule = Solid(mainFrame, "ARTWORK", C.rule)
	tabRule:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 1, tabTop - TAB_HEIGHT)
	tabRule:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -1, tabTop - TAB_HEIGHT)
	tabRule:SetHeight(1)

	for index, name in ipairs(tabOrder) do
		local btn = CreateTabButton(mainFrame, index, name)
		btn:SetPoint("TOPLEFT", PAD + (index - 1) * (TAB_WIDTH + 8), tabTop)

		local tabFrame = CreateFrame("Frame", nil, mainFrame)
		tabFrame:SetPoint("TOPLEFT", PAD, tabTop - TAB_HEIGHT - 11)
		tabFrame:SetPoint("BOTTOMRIGHT", -PAD, PAD)
		tabFrame:Hide()

		tabs[name] = { button = btn, frame = tabFrame }
	end

	tabs["List"].Refresh = BuildListTab(tabs["List"].frame).Refresh
	tabs["Settings"].Refresh = BlackListUI.BuildSettingsTab(tabs["Settings"].frame).Refresh

	mainFrame:SetScript("OnShow", function()
		SelectTab(activeTab or "List")
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
