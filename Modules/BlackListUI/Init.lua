-- AceAddon lifecycle hooks for JohnnysBlackList - all real logic lives in
-- Data.lua/Hooks.lua/UI.lua on the JohnnysBlackList.BlackListUI namespace
-- table. The addon object itself is the module now (standalone addon, no
-- Hub sub-module lookup needed).

-- Keybindings.xml label strings for JAHUB_TOGGLE_BLACKLIST (Bindings.xml at
-- the addon root) - the keybindings UI reads these globals by convention
-- (BINDING_HEADER_<header>/BINDING_NAME_<name>) to label the category/action.
BINDING_HEADER_JAHUB = "Johnny's Blacklist"
BINDING_NAME_JAHUB_TOGGLE_BLACKLIST = "Toggle Blacklist"

function JohnnysBlackList:OnInitialize()
	JohnnysBlackList.BlackListUI:InitData()
end

function JohnnysBlackList:OnEnable()
	local UI = JohnnysBlackList.BlackListUI

	UI:HookUnitPopup()
	UI:HookChatMessageHandler()
	UI:RegisterSlashCommands()

	self:RegisterEvent("PLAYER_TARGET_CHANGED", function() UI:OnPlayerTargetChanged() end)
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() UI:OnMouseoverUnit() end)
	self:RegisterEvent("PARTY_INVITE_REQUEST", function(event, name) UI:OnPartyInviteRequest(name) end)
	self:RegisterEvent("PARTY_MEMBERS_CHANGED", function() UI:OnGroupChanged() end)
	self:RegisterEvent("RAID_ROSTER_UPDATE", function() UI:OnGroupChanged() end)
	self:RegisterEvent("GUILD_ROSTER_UPDATE", function() UI:OnGuildRosterUpdate() end)
	self:RegisterEvent("CHAT_MSG_SYSTEM", function(event, msg) UI:OnChatMsgSystem(msg) end)
	self:RegisterEvent("WHO_LIST_UPDATE", function() UI:OnWhoListUpdate() end)
end

function JohnnysBlackList:OnDisable()
	self:UnregisterAllEvents()
end

function JohnnysBlackList:Toggle()
	JohnnysBlackList.BlackListUI:Toggle()
end
