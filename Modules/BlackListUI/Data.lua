-- Blacklist data layer: SavedVariables init, one-time migration from the old
-- standalone BlackList addon, and CRUD. Kept account-wide per realm (not in
-- a per-character profile) so every character on a realm shares one
-- blacklist, same as the old addon did.
JohnnysBlackList.BlackListUI = JohnnysBlackList.BlackListUI or {}
local BlackListUI = JohnnysBlackList.BlackListUI

local CONFIG_DEFAULTS = {
	Sound = true,
	Center = true,
	Chat = true,
	Ignore = true,
	Ban = false,
	Rank = 5,
	AnnounceGroup = true,
}

local function Realm()
	return GetRealmName()
end

-- Lower the name and upper the first letter, same normalization the old
-- addon used - skipped for locales where that transform doesn't apply.
local function NormalizeName(name)
	local locale = GetLocale()
	if locale == "zhTW" or locale == "zhCN" or locale == "koKR" then
		return name
	end
	local _, len = string.find(name, "[%z\1-\127\194-\244][\128-\191]*")
	return string.upper(string.sub(name, 1, len)) .. string.lower(string.sub(name, len + 1))
end

function BlackListUI:InitData()
	if not JohnnysAddonHubBlackList then
		JohnnysAddonHubBlackList = {}
	end
	if not JohnnysAddonHubBlackList[Realm()] then
		JohnnysAddonHubBlackList[Realm()] = {}
	end

	if not JohnnysAddonHubBlackListConfig then
		JohnnysAddonHubBlackListConfig = {}
	end
	for key, default in pairs(CONFIG_DEFAULTS) do
		if JohnnysAddonHubBlackListConfig[key] == nil then
			JohnnysAddonHubBlackListConfig[key] = default
		end
	end

	self:MigrateFromOldAddon()
end

-- One-time import of the old BlackList addon's SavedVariables (only
-- possible while that addon is still enabled, since that's what populates
-- the old global). Guarded so it never runs twice; safe to run again anyway
-- since existing names are skipped.
function BlackListUI:MigrateFromOldAddon()
	if JohnnysAddonHubBlackListConfig.MigratedFromOldAddon then
		return
	end
	JohnnysAddonHubBlackListConfig.MigratedFromOldAddon = true

	if type(BlackListedPlayers) ~= "table" then
		return
	end
	local oldList = BlackListedPlayers[Realm()]
	if type(oldList) ~= "table" then
		return
	end

	local imported = 0
	for i = 1, #oldList do
		local old = oldList[i]
		if old and old.name and self:GetIndexByName(old.name) == 0 then
			table.insert(self:GetList(), {
				name = old.name,
				level = old.level or "",
				class = old.class or "",
				race = old.race or "",
				warn = old.warn,
				ignore = old.ignore,
				history = { { reason = old.reason or "", date = old.added or time() } },
			})
			imported = imported + 1
		end
	end

	if imported > 0 then
		self:Sort()
		JohnnysBlackList:Print("Blacklist: imported " .. imported .. " entr" .. (imported == 1 and "y" or "ies") .. " from the old BlackList addon.")
	end
end

function BlackListUI:GetList()
	return JohnnysAddonHubBlackList[Realm()]
end

function BlackListUI:GetIndexByName(name)
	local list = self:GetList()
	for i = 1, #list do
		if list[i].name == name then
			return i
		end
	end
	return 0
end

function BlackListUI:GetEntryByIndex(index)
	local list = self:GetList()
	if index < 1 or index > #list then
		return nil
	end
	return list[index]
end

function BlackListUI:GetEntryByName(name)
	if not name then
		return nil
	end
	local index = self:GetIndexByName(name)
	if index == 0 then
		return nil
	end
	return self:GetEntryByIndex(index)
end

local function Comparator(a, b)
	local strA, strB = a.name, b.name
	local length = math.max(strlen(strA), strlen(strB))
	for i = 1, length do
		local byteA = strbyte(strA, i) or 0
		local byteB = strbyte(strB, i) or 0
		if byteA < byteB then
			return true
		elseif byteA > byteB then
			return false
		end
	end
	return true
end

function BlackListUI:Sort()
	table.sort(self:GetList(), Comparator)
end

-- Adds a player to the blacklist. If they're already on it, this appends a
-- new dated/reasoned history entry instead of rejecting the add (the old
-- addon's "already blacklisted" behavior), so re-blacklisting someone builds
-- a timeline instead of being a no-op. Most recent history entry is kept at
-- index 1.
function BlackListUI:AddPlayer(name, reason, ignoreOverride, level, class, race)
	if not name or name == "" then
		return nil
	end
	name = NormalizeName(name)
	reason = reason or ""

	local ignore = ignoreOverride
	if ignore == nil then
		ignore = JohnnysAddonHubBlackListConfig.Ignore
	end

	local entry = self:GetEntryByName(name)
	if entry then
		table.insert(entry.history, 1, { reason = reason, date = time() })
		if level and level ~= "" then entry.level = level end
		if class and class ~= "" then entry.class = class end
		if race and race ~= "" then entry.race = race end
		entry.ignore = ignore
		self:Message(name .. " added to Blacklist again.", "yellow")
	else
		entry = {
			name = name,
			level = level or "",
			class = class or "",
			race = race or "",
			warn = true,
			ignore = ignore,
			history = { { reason = reason, date = time() } },
		}
		table.insert(self:GetList(), entry)
		self:Sort()
		self:Message(name .. " added to Blacklist.", "yellow")
	end

	if self.RefreshWindow then
		self:RefreshWindow()
	end

	return entry
end

function BlackListUI:RemovePlayer(name)
	if not name then
		return false
	end
	local index = self:GetIndexByName(name)
	if index == 0 then
		self:Message("Player not found.", "yellow")
		return false
	end

	local removedName = self:GetEntryByIndex(index).name
	table.remove(self:GetList(), index)
	self:Message(removedName .. " removed from Blacklist.", "yellow")

	if self.RefreshWindow then
		self:RefreshWindow()
	end

	return true
end

function BlackListUI:SetIgnore(name, ignore)
	local entry = self:GetEntryByName(name)
	if entry then
		entry.ignore = ignore and true or false
	end
end

function BlackListUI:SetWarn(name, warn)
	local entry = self:GetEntryByName(name)
	if entry then
		entry.warn = warn and true or false
	end
end

-- Edits an existing entry's name/level/class/race in place. Unlike AddPlayer,
-- this never touches history and never prints an "added again" message -
-- it's a correction, not a new sighting.
function BlackListUI:EditPlayer(oldName, newName, level, class, race)
	local entry = self:GetEntryByName(oldName)
	if not entry then
		return false, "Player not found."
	end

	newName = NormalizeName(newName or "")
	if newName == "" then
		return false, "Name cannot be empty."
	end

	if newName ~= entry.name then
		local existingIndex = self:GetIndexByName(newName)
		if existingIndex ~= 0 and self:GetEntryByIndex(existingIndex) ~= entry then
			return false, newName .. " is already on the Blacklist."
		end
		entry.name = newName
	end

	entry.level = level or ""
	entry.class = class or ""
	entry.race = race or ""

	self:Sort()

	if self.RefreshWindow then
		self:RefreshWindow()
	end

	return true
end

function BlackListUI:EditHistoryReason(name, historyIndex, reason)
	local entry = self:GetEntryByName(name)
	if not entry or not entry.history[historyIndex] then
		return false
	end
	entry.history[historyIndex].reason = reason or ""

	if self.RefreshWindow then
		self:RefreshWindow()
	end

	return true
end

-- Removes a single history entry rather than the whole player. Refuses to
-- leave an entry with zero history records - Remove is the right tool for
-- clearing a player out entirely.
function BlackListUI:RemoveHistoryEntry(name, historyIndex)
	local entry = self:GetEntryByName(name)
	if not entry or not entry.history[historyIndex] then
		return false, "History entry not found."
	end
	if #entry.history <= 1 then
		return false, "Can't delete the last history entry - use Remove to delete the player instead."
	end

	table.remove(entry.history, historyIndex)

	if self.RefreshWindow then
		self:RefreshWindow()
	end

	return true
end

function BlackListUI:Message(msg, color)
	if not JohnnysAddonHubBlackListConfig.Chat then
		return
	end
	local r, g, b = 1, 1, 1
	if color == "red" then
		r, g, b = 1, 0, 0
	elseif color == "yellow" then
		r, g, b = 1, 1, 0
	end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage("[Blacklist] " .. msg, r, g, b)
	end
end

function BlackListUI:ErrorMessage(msg, color, timeout)
	if not JohnnysAddonHubBlackListConfig.Center then
		return
	end
	local r, g, b = 1, 1, 1
	if color == "red" then
		r, g, b = 1, 0, 0
	elseif color == "yellow" then
		r, g, b = 1, 1, 0
	end
	if UIErrorsFrame then
		UIErrorsFrame:AddMessage(msg, r, g, b, nil, timeout)
	end
end

function BlackListUI:PlayAlertSound()
	if not JohnnysAddonHubBlackListConfig.Sound then
		return
	end
	PlaySound("PVPTHROUGHQUEUE")
end
