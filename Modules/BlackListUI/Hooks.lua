-- Blacklist behavior layer: unit-popup menu entry, slash commands, whisper
-- auto-ignore, and sighting warnings (target/mouseover/party invite/group
-- roster/guild roster), ported from the old BlackList addon's BlackList.lua.
-- Also adds the new group-encounter chat announcement (party/raid), which
-- the old addon never had.
JohnnysBlackList.BlackListUI = JohnnysBlackList.BlackListUI or {}
local BlackListUI = JohnnysBlackList.BlackListUI

-- Suppresses repeat local warnings for the same name within a short window,
-- same idea as the old addon's Already_Warned_For table.
local alreadyWarned = {
	WHISPER = {},
	TARGET = {},
	PARTY_INVITE = {},
	PARTY = {},
	GUILD_ROSTER = {},
}

local function AlreadyWarnedRecently(bucket, name)
	local t = alreadyWarned[bucket][name]
	return t and (GetTime() < t + 10)
end

-- Names announced to the group already during the current, continuous
-- group session - cleared whenever the group forms fresh from solo or fully
-- disbands, so each new group gets its own one-time announcement per member.
local announcedThisSession = {}
local wasGrouped = false

local BLOCKED_CHANNELS = {
	SAY = true, YELL = true, WHISPER = true, WHISPER_INFORM = true,
	PARTY = true, RAID = true, RAID_WARNING = true, EMOTE = true,
	TEXT_EMOTE = true, CHANNEL = true, CHANNEL_JOIN = true, CHANNEL_LEAVE = true,
}

local function LatestReason(entry)
	local latest = entry.history[1]
	return (latest and latest.reason ~= "" and latest.reason) or ""
end

-- Resolves a unit token to a blacklist-addable name/level/class/race, or
-- nil if the unit isn't a valid, non-self player.
local function ResolveUnit(unit)
	if not UnitExists(unit) or not UnitIsPlayer(unit) then
		return nil
	end
	local name = UnitName(unit)
	if not name or name == UnitName("player") then
		return nil
	end
	return name, UnitLevel(unit) .. "", UnitClass(unit), (UnitRace(unit))
end

function BlackListUI:AddFromUnit(unit, reason)
	local name, level, class, race = ResolveUnit(unit)
	if not name then
		JohnnysBlackList:Print("No valid target to add to the Blacklist.")
		return
	end
	self:AddPlayer(name, reason, nil, level, class, race)
end

----------------------------------------------------------------------------
-- Unit-popup menu: adds "Blacklist" / "Guild Invite" / "Add to Friends" to
-- the right-click menu on players, party/raid members, chat roster entries,
-- and friends - ported from the old addon's AddMenuItems(). Button keys are
-- hub-prefixed to avoid colliding with any other addon's UnitPopup entries.
----------------------------------------------------------------------------
local menuHooked = false
function BlackListUI:HookUnitPopup()
	if menuHooked then
		return
	end
	menuHooked = true

	UnitPopupButtons["JAHUB_BLACKLIST_ADD"] = { text = "Blacklist", dist = 0 }
	UnitPopupButtons["JAHUB_BLACKLIST_GINV"] = { text = "Guild Invite", dist = 0 }
	UnitPopupButtons["JAHUB_BLACKLIST_FINV"] = { text = "Add to Friends", dist = 0 }

	hooksecurefunc("UnitPopup_HideButtons", function()
		local dropdownMenu = UIDROPDOWNMENU_INIT_MENU
		for i, v in pairs(UnitPopupMenus[dropdownMenu.which]) do
			if v == "JAHUB_BLACKLIST_ADD" or v == "JAHUB_BLACKLIST_GINV" or v == "JAHUB_BLACKLIST_FINV" then
				UnitPopupShown[i] = (dropdownMenu.name == UnitName("player") and 0) or 1
			end
		end
	end)

	hooksecurefunc("UnitPopup_OnClick", function()
		local dropdownMenu = UIDROPDOWNMENU_INIT_MENU
		if not dropdownMenu or not dropdownMenu.name or dropdownMenu.name == UnitName("player") then
			return
		end
		if this.value == "JAHUB_BLACKLIST_ADD" then
			BlackListUI:AddPlayer(dropdownMenu.name, nil, JohnnysAddonHubBlackListConfig.Ignore)
		elseif this.value == "JAHUB_BLACKLIST_GINV" then
			GuildInvite(dropdownMenu.name)
		elseif this.value == "JAHUB_BLACKLIST_FINV" then
			AddFriend(dropdownMenu.name)
		end
	end)

	local menus = { "PLAYER", "PARTY", "RAID_PLAYER", "CHAT_ROSTER", "FRIEND" }
	local keys = { "JAHUB_BLACKLIST_ADD", "JAHUB_BLACKLIST_GINV", "JAHUB_BLACKLIST_FINV" }
	for _, menu in ipairs(menus) do
		if UnitPopupMenus[menu] then
			for _, key in ipairs(keys) do
				table.insert(UnitPopupMenus[menu], #UnitPopupMenus[menu] - 1, key)
			end
		end
	end
end

----------------------------------------------------------------------------
-- Slash commands: /blacklist, /bl, /removeblacklist, /removebl
----------------------------------------------------------------------------
function BlackListUI:RegisterSlashCommands()
	SlashCmdList["JAHUBBLACKLISTADD"] = function(msg) BlackListUI:HandleSlashAdd(msg) end
	SLASH_JAHUBBLACKLISTADD1 = "/blacklist"
	SLASH_JAHUBBLACKLISTADD2 = "/bl"

	SlashCmdList["JAHUBBLACKLISTREMOVE"] = function(msg) BlackListUI:HandleSlashRemove(msg) end
	SLASH_JAHUBBLACKLISTREMOVE1 = "/removeblacklist"
	SLASH_JAHUBBLACKLISTREMOVE2 = "/removebl"
end

function BlackListUI:HandleSlashAdd(msg)
	msg = msg or ""
	if msg == "" then
		self:AddFromUnit("target")
		return
	end

	local name, reason = msg, ""
	local spaceIndex = string.find(msg, " ", 1, true)
	if spaceIndex then
		name = string.sub(msg, 1, spaceIndex - 1)
		reason = string.sub(msg, spaceIndex + 1)
	end
	self:AddPlayer(name, reason, JohnnysAddonHubBlackListConfig.Ignore)
end

function BlackListUI:HandleSlashRemove(msg)
	local name = msg
	if not name or name == "" then
		name = UnitName("target")
	end
	if not name then
		JohnnysBlackList:Print("No target selected to remove from the Blacklist.")
		return
	end
	self:RemovePlayer(name)
end

----------------------------------------------------------------------------
-- Whisper auto-ignore / auto-warn - overrides ChatFrame_MessageEventHandler
-- so ignored blacklisted players' whispers can be swallowed outright.
----------------------------------------------------------------------------
local originalMessageEventHandler
function BlackListUI:HookChatMessageHandler()
	if originalMessageEventHandler then
		return
	end
	originalMessageEventHandler = ChatFrame_MessageEventHandler

	ChatFrame_MessageEventHandler = function(event, ...)
		local warnName
		local eventStr = tostring(event)

		if strsub(eventStr, 1, 8) == "CHAT_MSG" then
			local channelType = strsub(eventStr, 10)
			if BLOCKED_CHANNELS[channelType] then
				local name = arg2
				local entry = name and BlackListUI:GetEntryByName(name)
				if entry then
					if entry.ignore then
						if channelType == "WHISPER" then
							if not alreadyWarned.WHISPER[name] then
								alreadyWarned.WHISPER[name] = true
							BlackListUI:RecordSighting(entry, "whispered you")
								SendChatMessage("Automatic Message: Ignored", "WHISPER", nil, name)
							end
							return
						elseif channelType == "WHISPER_INFORM" then
							warnName = name
						end
					elseif entry.warn then
						if channelType == "WHISPER" and not alreadyWarned.WHISPER[name] then
							alreadyWarned.WHISPER[name] = true
							BlackListUI:RecordSighting(entry, "whispered you")
							warnName = name
						end
					end
				end
			end
		end

		local returnValue = originalMessageEventHandler(event, ...)

		if warnName then
			BlackListUI:Message(warnName .. " is on your Blacklist.", "red")
		end

		return returnValue
	end
end

----------------------------------------------------------------------------
-- Sighting warnings: target, mouseover, party invite, guild roster, who list,
-- and generic system messages naming a blacklisted player.
----------------------------------------------------------------------------
function BlackListUI:WarnIfListed(unit, bucket, context)
	local name = UnitName(unit)
	if not name then
		return
	end
	local entry = self:GetEntryByName(name)
	if not entry or not entry.warn then
		return
	end
	if AlreadyWarnedRecently(bucket, name) then
		return
	end
	alreadyWarned[bucket][name] = GetTime()
	self:RecordSighting(entry, context)

	self:PlayAlertSound()
	self:ErrorMessage(name .. " is on your Blacklist (" .. context .. ")", "red", 5)
	local reason = LatestReason(entry)
	if reason ~= "" then
		self:Message(name .. " is on your Blacklist for: " .. reason, "yellow")
	else
		self:Message(name .. " is on your Blacklist.", "yellow")
	end
end

function BlackListUI:OnPlayerTargetChanged()
	self:WarnIfListed("target", "TARGET", "targeted")
end

function BlackListUI:OnMouseoverUnit()
	self:WarnIfListed("mouseover", "TARGET", "mouseover")
end

function BlackListUI:OnPartyInviteRequest(name)
	if not name then
		return
	end
	local entry = self:GetEntryByName(name)
	if not entry then
		return
	end

	if not AlreadyWarnedRecently("PARTY_INVITE", name) then
		self:RecordSighting(entry, "invited you to a group")
	end

	if entry.ignore then
		DeclineGroup()
		StaticPopup_Hide("PARTY_INVITE")
	elseif entry.warn and not AlreadyWarnedRecently("PARTY_INVITE", name) then
		alreadyWarned.PARTY_INVITE[name] = GetTime()
		self:PlayAlertSound()
		self:ErrorMessage(name .. " is on your Blacklist (invited you to a group)", "red", 10)
	end
end

local function IsGrouped()
	return GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0
end

local function GroupMemberNames()
	local names = {}
	if GetNumRaidMembers() > 0 then
		for i = 1, GetNumRaidMembers() do
			local name = UnitName("raid" .. i)
			if name then
				names[name] = true
			end
		end
	else
		for i = 1, GetNumPartyMembers() do
			local name = UnitName("party" .. i)
			if name then
				names[name] = true
			end
		end
	end
	return names
end

-- Handles both PARTY_MEMBERS_CHANGED and RAID_ROSTER_UPDATE (the old addon
-- only ever checked party members, never the raid roster). For every
-- blacklisted member currently in the group: keeps the existing local
-- warning behavior, and - new - announces once per group session to
-- PARTY/RAID chat if the "Announce to Group" setting is on.
function BlackListUI:OnGroupChanged()
	local grouped = IsGrouped()
	if grouped ~= wasGrouped then
		announcedThisSession = {}
		wasGrouped = grouped
	end

	if not grouped then
		return
	end

	for name in pairs(GroupMemberNames()) do
		local entry = self:GetEntryByName(name)
		if entry and entry.warn then
			local reason = LatestReason(entry)

			if not AlreadyWarnedRecently("PARTY", name) then
				alreadyWarned.PARTY[name] = GetTime()
				self:RecordSighting(entry, "in your group")
				self:PlayAlertSound()
				if reason ~= "" then
					self:Message(name .. " is on your Blacklist (in your group) for: " .. reason, "red")
				else
					self:Message(name .. " is on your Blacklist (in your group).", "red")
				end
			end

			if JohnnysAddonHubBlackListConfig.AnnounceGroup and not announcedThisSession[name] then
				announcedThisSession[name] = true
				local channel = GetNumRaidMembers() ~= 0 and "RAID" or "PARTY"
				local msg
				if reason ~= "" then
					msg = "Oxide Blacklist Addon: " .. name .. " is on the Blacklist for: " .. reason
				else
					msg = "Oxide Blacklist Addon: " .. name .. " is on the Blacklist."
				end
				SendChatMessage(msg, channel)
			end
		end
	end
end

function BlackListUI:OnGuildRosterUpdate()
	if not IsInGuild() then
		return
	end
	local _, _, playerRankIndex = GetGuildInfo("player")

	for i = 1, GetNumGuildMembers() do
		local name, rank, rankIndex, level, class, zone, note, officernote, online = GetGuildRosterInfo(i)
		if name then
			local entry = self:GetEntryByName(name)
			if entry and entry.warn and not AlreadyWarnedRecently("GUILD_ROSTER", name) then
				alreadyWarned.GUILD_ROSTER[name] = GetTime()
				self:RecordSighting(entry, "in your guild")
				self:PlayAlertSound()
				self:Message(name .. " is on your Blacklist and is in your guild.", "red")

				if JohnnysAddonHubBlackListConfig.Ban and CanGuildRemove()
					and playerRankIndex and rankIndex >= JohnnysAddonHubBlackListConfig.Rank
					and rankIndex > playerRankIndex
					and (not officernote or not string.find(officernote, "[Kk][Ii][Cc][Kk]")) then
					GuildUninvite(name)
					local reason = LatestReason(entry)
					local bannedMsg
					if reason ~= "" then
						bannedMsg = name .. " has been banned from the Guild for: " .. reason .. ". Do not reinvite!"
					else
						bannedMsg = name .. " has been banned from the Guild. Do not reinvite!"
					end
					SendChatMessage(bannedMsg, "GUILD")
					if online then
						SendChatMessage("You have been banned from the guild for life. Please do not join again!", "WHISPER", nil, name)
					end
				end
			end
		end
	end
end

function BlackListUI:OnChatMsgSystem(msg)
	if not msg then
		return
	end
	local name = string.match(msg, "(%a+)", 10)
	if name and self:GetEntryByName(name) then
		self:Message(name .. " is on your Blacklist.", "red")
	end
end

function BlackListUI:OnWhoListUpdate()
	for i = 1, GetNumWhoResults() do
		local whoName = GetWhoInfo(i)
		if whoName and self:GetEntryByName(whoName) then
			self:Message(whoName .. " is on your Blacklist (from your who search).", "red")
		end
	end
end
