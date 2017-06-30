RaidNotifier = RaidNotifier or {}
RaidNotifier.UI = {}

local RaidNotifier = RaidNotifier

RaidNotifier.Name            = "RaidNotifier"
RaidNotifier.DisplayName     = "Raid Notifier"
RaidNotifier.Version         = "1.9.4"
RaidNotifier.Author          = "|c009ad6Kyoma, Woeler, silentgecko|r"
RaidNotifier.SV_Name         = "RNVars"
RaidNotifier.SV_Version      = 4


-- Constants for easy reading
local RAID_HEL_RA_CITADEL        = 1
local RAID_AETHERIAN_ARCHIVE     = 2
local RAID_SANCTUM_OPHIDIA       = 3
local RAID_DRAGONSTAR_ARENA      = 4
local RAID_MAW_OF_LORKHAJ        = 5
local RAID_MAELSTROM_ARENA       = 6
local RAID_HALLS_OF_FABRICATION  = 7

-- Debugging
local function p() end
local function dbg() end

------------------------------------
-- -- NOTIFICATION SYSTEM & SOUNDS
do ---------------------------------

	local lastAnnounceIndex = 0
	local lastNotifyTimes = {}
	local function GetKey(r, s)
		return (r.."_"..s)
	end

	local Sounds = {
		{name = "-None-", 					 id = SOUNDS.NONE},
		{name = "Add Guild Member", 		 id = SOUNDS.GUILD_ROSTER_ADDED},
		{name = "Book Acquired", 			 id = SOUNDS.BOOK_ACQUIRED},
		{name = "Book Collection Completed", id = SOUNDS.BOOK_COLLECTION_COMPLETED},
		{name = "Champion Point Committed",  id = SOUNDS.CHAMPION_POINTS_COMMITTED},
		{name = "Champion Point Gained", 	 id = SOUNDS.CHAMPION_POINT_GAINED},
		{name = "Dark Fissure Closed", 		 id = SOUNDS.SKILL_XP_DARK_FISSURE_CLOSED},
		{name = "Emperor Coronated", 		 id = SOUNDS.EMPEROR_CORONATED_ALDMERI},
		{name = "Gate Closed", 				 id = SOUNDS.AVA_GATE_CLOSED},
		{name = "Morph Ability", 			 id = SOUNDS.ABILITY_MORPH_PURCHASED},
		{name = "Objective Complete", 		 id = SOUNDS.OBJECTIVE_COMPLETED},
		{name = "Quest Abandoned", 			 id = SOUNDS.QUEST_ABANDONED},
		{name = "Quest Accepted",			 id = SOUNDS.QUEST_ACCEPTED},
		{name = "Quest Complete", 			 id = SOUNDS.QUEST_COMPLETED},
		{name = "Quickslot Empty", 			 id = SOUNDS.QUICKSLOT_USE_EMPTY},
		{name = "Quickslot Open", 			 id = SOUNDS.QUICKSLOT_OPEN},
		{name = "Remove Guild Member", 		 id = SOUNDS.GUILD_ROSTER_REMOVED},
		{name = "Skill Added", 				 id = SOUNDS.SKILL_LINE_ADDED},
		{name = "Skill Leveled", 			 id = SOUNDS.SKILL_LINE_LEVELED_UP},
		{name = "Stat Purchase", 			 id = SOUNDS.STATS_PURCHASE},
		{name = "Synergy Ready", 			 id = SOUNDS.ABILITY_SYNERGY_READY},
	}
	function RaidNotifier:GetSounds()
		return Sounds
	end
	function RaidNotifier:GetSoundName(soundId, category, setting)
		if soundId == nil then
			soundId = self:GetSoundValue(category, setting)
		end
		for _, entry in ipairs(self:GetSounds()) do
			if soundId == entry.id then return entry.name end
		end
		return ""
	end
	function RaidNotifier:GetSoundValue(category, setting)
		return self.Vars.sounds[GetKey(category, setting)] or SOUNDS.CHAMPION_POINTS_COMMITTED
	end
	function RaidNotifier:SetSoundValue(category, setting, value)
		self.Vars.sounds[GetKey(category, setting)] = value
	end

	function RaidNotifier:GetLastNotify(category, setting)
		local key = GetKey(category, setting)
		return lastNotifyTimes[key] or 0
	end
	function RaidNotifier:SetLastNotify(category, setting, value)
		local key = GetKey(category, setting)
		lastNotifyTimes[key] = value
	end
	
	local RN_SMALL_TEXT = CSA_EVENT_SMALL_TEXT or CSA_CATEGORY_SMALL_TEXT
	-- TODO: Overhaul this completely and make a better alternative, gonna take a while
	function RaidNotifier:AddAnnouncement(text, category, setting, interval)

		local duration = 3000
		local soundId = self:GetSoundValue(category, setting)

		if not text or text == "" then
			p("Invalid text for '%s -> %s'", category, setting)
			return
		elseif self.Vars.debug_notify then 
			dbg("Alert for '%s -> %s', sound '%s' \n\"%s\"", category, setting, soundId, text)
		end

		if (interval) then 
			local currentTime = GetTimeStamp()
			if (interval > GetDiffBetweenTimeStamps(currentTime, self:GetLastNotify(category, setting))) then
				return
			end
			self:SetLastNotify(category, setting, currentTime)
		end

		if (self.Vars.general.use_center_screen_announce) then
			CENTER_SCREEN_ANNOUNCE:AddMessage(EVENT_BROADCAST, RN_SMALL_TEXT, soundId, text, nil, nil, nil, nil, nil, duration)
			CENTER_SCREEN_ANNOUNCE.m_nextUpdateTimeSeconds = 0 --force it to update right away
			CENTER_SCREEN_ANNOUNCE.nextUpdateTimeSeconds = 0 --they renamed it in ESO:Morrowind
		else
			lastAnnounceIndex = lastAnnounceIndex + 1
			RaidNotifierUICenterAnnounce:SetHidden(false)
			RaidNotifierUICenterAnnounce:SetText(text)
		
			local index = lastAnnounceIndex
			zo_callLater(function()
				--only hide it if we are the last/most recent announcement
				if index == lastAnnounceIndex then
					RaidNotifierUICenterAnnounce:SetHidden(true)
				end
			end, duration)
		
			if soundId ~= nil then PlaySound(soundId) end
		end
	end
end


-- ----------------------
-- -- ULTIMATE EXCHANGE
do ----------------------

	local UI = RaidNotifier.UI
	local window = nil

	local LGS = LibStub:GetLibrary("LibGroupSocket")
	local ultimateHandler = LGS:GetHandler(LGS.MESSAGE_TYPE_ULTIMATE)
	local ultimateAbilityId = 46537  --Aggressive Warhorn Rank IV
	local ultimates = {}

	function RaidNotifier.OnUltimateReceived(unitTag, ultimateCurrent, ultimateCost, isSelf)
		local self     = RaidNotifier
		local userName = GetUnitDisplayName(unitTag)
		ultimates[userName] = 
		{
			userName = userName,
			name     = GetUnitName(unitTag),
			roles    = {GetGroupMemberRoles(unitTag)},
			current  = ultimateCurrent,
			percent  = math.floor((ultimateCurrent / ultimateCost) * 100), --round it down?
		}
		self:UpdateUltimates()
	end

	function RaidNotifier:UpdateUltimates()
		local settings = self.Vars.ultimate
		if settings.hidden then return end

		window = window or UI.GetElement("ultimate", "ulti_window")
		if not window then return end

		local sortedUlti = {}
		for userName, data in pairs(ultimates) do
			local r1,r2,r3 = unpack(data.roles)
			if (r1 and settings.showDps or r2 and settings.showHealers or r3 and settings.showTanks) then
				table.insert(sortedUlti, data)
			end
		end
		table.sort(sortedUlti, function(a, b) return a.percent > b.percent end)
		
		local text = "Ultimates:" --TODO: grab text from abilityId??
		for i, data in ipairs(sortedUlti) do
			local name = data.userName
			local c1,c2 = "",""
			if settings.useColor then
				if data.percent >= 100 then
					c1,c2 = "|c00ff00","|r"
				elseif data.percent >= 80 then
					c1,c2 = "|ccccc00","|r"
				end
			end
			text = string.format("%s\n%s%s %d%%%s", text, c1, name, zo_min(data.percent, 100), c2)
		end

		window.label:SetText(text)
	end

	local function ToggleLibGroupSocket(enabled)
		local settings = RaidNotifier.Vars.ultimate
		if settings.enabled then 
			local button = ZO_GroupMenu_Keyboard_LibGroupSocketToggle
			if not button then -- wait for button
				zo_callLater(function() ToggleLibGroupSocket(enabled) end, 1000)
			else
				ZO_CheckButton_SetCheckState(button, enabled)
				button:toggleFunction(enabled)
			end
		end
	end

	local listening = false
	function RaidNotifier:RegisterForUltimateChanges()
		local settings = self.Vars.ultimate
		if not settings.enabled then return end
		
		if listening then return end
		listening = true
		dbg("RegisterForUltimateChanges")
		
		UI.SetElementHidden("ultimate", "ulti_window", settings.hidden)
	
		ultimateHandler:RegisterForUltimateChanges(self.OnUltimateReceived)
		ultimateHandler:Refresh()
		ToggleLibGroupSocket(true) -- force LibGroupSocket to send data

		local function OnWeaponPairChanged()
			--get dynamic ultimate cost, should work with any cost reduction passives & sets
			ultimateHandler:SetUltimateCost(GetAbilityCost(ultimateAbilityId))
		end
		OnWeaponPairChanged()
		EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_WEAPON_PAIR_LOCK_CHANGED, OnWeaponPairChanged)

		-- TODO: check if this always runs AFTER LibGroupSocket's code on group changes
		-- UPDATE: should no longer matter
		local function OnGroupUpdate()
			local newMembers = {}
			for i=1, GetGroupSize() do
				local userName = GetUnitDisplayName("group"..i)
				if userName and userName ~= "" then 
					newMembers[userName] = IsUnitOnline("group"..i)
				end
			end
			for userName, data in pairs(ultimates) do
				if not newMembers[userName] then
					ultimates[userName] = nil
				end
			end
			zo_callLater(function() self:UpdateUltimates() end, 200) -- slight delay
		end
		OnGroupUpdate()
		EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_GROUP_MEMBER_JOINED, OnGroupUpdate)
		EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_GROUP_MEMBER_LEFT,   OnGroupUpdate)
		EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_GROUP_UPDATE,        OnGroupUpdate)
		--EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_UNIT_FRAME_UPDATE,   OnGroupUpdate)
		EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_GROUP_MEMBER_CONNECTED_STATUS , OnGroupUpdate)

		local function OnRolesChanged(_, unitTag, dps, healer, tank)
			local userName = GetUnitDisplayName(unitTag)
			if ultimates[userName] then
				ultimates[userName].roles = {dps, healer, tank}
			end
			self:UpdateUltimates()
		end
		EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_GROUP_MEMBER_ROLES_CHANGED, OnRolesChanged)
	end

	function RaidNotifier:UnregisterForUltimateChanges()
		if not listening then return end
		listening = false
		dbg("UnregisterForUltimateChanges")
		
		UI.SetElementHidden("ultimate", "ulti_window", true)

		ultimateHandler:UnregisterForUltimateChanges(self.OnUltimateReceived)
		ToggleLibGroupSocket(false) -- force LibGroupSocket to send data

		EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_WEAPON_PAIR_LOCK_CHANGED)
		EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_GROUP_MEMBER_JOINED)
		EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_GROUP_MEMBER_LEFT)
		EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_GROUP_UPDATE)
		--EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_UNIT_FRAME_UPDATE)
		EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_GROUP_MEMBER_ROLES_CHANGED)
	end


	SLASH_COMMANDS["/rnulti"] = function(arg) 
		local self     = RaidNotifier
		local settings = self.Vars.ultimate
		if (arg == nil or arg == "") then
			settings.hidden = not settings.hidden
			p("%s Ultimate Exchange", settings.hidden and "Hide" or "Show")
		elseif (arg == "show") then
			p("Show Ultimate Exchange")
			settings.hidden = false
		elseif (arg == "hide") then
			p("Hide Ultimate Exchange")
			settings.hidden = true
		elseif (arg == "enable" or arg =="1") then
			p("Enable Ultimate Exchange")
			settings.enabled = true
			settings.hidden = false
			self:RegisterForUltimateChanges()
		elseif (arg == "disable" or arg == "0") then
			p("Disable Ultimate Exchange")
			settings.enabled = false
			settings.hidden = true
			self:UnregisterForUltimateChanges()
		elseif (arg == "refresh") then
			ultimates = {}
			ultimateHandler:Refresh()
		end
		UI.SetElementHidden("ultimate", "ulti_window", settings.hidden)
		self:UpdateUltimates()
	end
end


-- ----------------------
-- -- INITIALIZE EVENTS
do ----------------------

	local UI = RaidNotifier.UI

	local function ToggleVanityPets(disable)
		local settings = RaidNotifier.Vars.general
		if settings.vanity_pets then
			if disable then
				settings.last_pet = GetActiveCollectibleByType(COLLECTIBLE_CATEGORY_TYPE_VANITY_PET)
				if settings.last_pet > 0 then
					UseCollectible(settings.last_pet)
				end
			elseif (settings.last_pet and settings.last_pet > 0) then
				UseCollectible(settings.last_pet)
				settings.last_pet = 0
			end
		end
	end

	-- These should remain the same throughout updates
	local RaidZoneIds = {
		[RAID_HEL_RA_CITADEL]        = 636,
		[RAID_AETHERIAN_ARCHIVE]     = 638,
		[RAID_SANCTUM_OPHIDIA]       = 639,
		[RAID_DRAGONSTAR_ARENA]      = 635,
		[RAID_MAW_OF_LORKHAJ]        = 725,
		[RAID_MAELSTROM_ARENA]       = 677,
		[RAID_HALLS_OF_FABRICATION]  = 975,
	}
	local RaidZones = {}
	for raidId, zoneId in pairs(RaidZoneIds) do
		RaidZones[GetZoneNameById(zoneId)] = raidId
	end
	local function GetRaidZoneName(raidId)
		return GetZoneNameById(RaidZoneIds[raidId])
	end
	local currentZoneRaidId
	function RaidNotifier:GetRaidIdFromCurrentZone()
		return currentZoneRaidId or 0
	end
	function RaidNotifier:IsInRaidZone()
		return self:GetRaidIdFromCurrentZone() > 0
	end

	local listening = false
	function RaidNotifier:RegisterEvents(raidId)
		if listening then return end

		self.raidId = raidId or self:GetRaidIdFromCurrentZone()
		self.raidDifficulty = GetCurrentZoneDungeonDifficulty()
		if (self.raidId > 0) then
			dbg("Register for %s (%s)", GetRaidZoneName(self.raidId), GetString("SI_DUNGEONDIFFICULTY", self.raidDifficulty))
			-- The main juicy events we want
			EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_COMBAT_EVENT,        self.OnCombatEvent)
			EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_EFFECT_CHANGED,      self.OnEffectChanged) --only used for food buff atm
			-- Track bosses
			EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_BOSSES_CHANGED,      self.OnBossesChanged)
			-- Toggle assistants off when combat starts
			local function OnCombatStateChanged(_, inCombat)
				local settings = self.Vars.general
				if (inCombat and settings.no_assistants and GetActiveCollectibleByType(COLLECTIBLE_CATEGORY_TYPE_ASSISTANT) > 0) then
					UseCollectible(GetActiveCollectibleByType(COLLECTIBLE_CATEGORY_TYPE_ASSISTANT))
				end
			end
			EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_PLAYER_COMBAT_STATE, OnCombatStateChanged)

			UI.AddFragment()
			listening = true
			
			-- Ultimate exchanging
			self:RegisterForUltimateChanges()

			-- Disable pets if that setting is set
			ToggleVanityPets(true)

			-- In case of initializing while already at a boss
			self.OnBossesChanged()
		end
	end

	function RaidNotifier:UnregisterEvents()
		if not listening then return end

		dbg("Unregister for %s (%s)", GetRaidZoneName(self.raidId), GetString("SI_DUNGEONDIFFICULTY", self.raidDifficulty))
		EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_COMBAT_EVENT)
		EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_EFFECT_CHANGED)
		EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_BOSSES_CHANGED)
		EVENT_MANAGER:UnregisterForEvent(self.Name, EVENT_PLAYER_COMBAT_STATE)

		UI.RemoveFragment()
		listening = false
		self.raidId = 0
		self.raidDifficulty = 0

		-- Ultimate exchanging
		self:UnregisterForUltimateChanges()

		-- Re-enable pets
		ToggleVanityPets(false)
	end

	function RaidNotifier:Initialize()
		self.Vars = ZO_SavedVars:NewAccountWide(self.SV_Name, self.SV_Version, nil, self.Defaults)

		self:CreateSettingsMenu()

		-- tiny functors
		p = function(msg, ...)
			d("[RaidNotifier] "..msg:format(...))
		end
		dbg = function(msg, ...)
			if self.Vars.debug then
				p(msg, ...)
			end
		end

		-- UI Elements
		UI.RegisterElement(RaidNotifierUI:GetNamedChild("GlyphWindow"))
		UI.RegisterElement(RaidNotifierUI:GetNamedChild("UltimateWindow"), self.Vars.ultimate.hidden)

		-- These aren't needed anymore since we now start & stop Raid Notifier solely based on being in the raid zone
	    --EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_RAID_TRIAL_STARTED,  function(...) self:RegisterEvents() end)
		--EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_RAID_TRIAL_COMPLETE, function(...) self:UnregisterEvents() end)
		self.raidId = 0
		self.raidDifficulty = 0
		-- Monitor zone changes to account for teleporting out of a trial, also for teleporting back in
		local function OnZoneChanged()
			-- Not using GetMapName() because that changes while looking at the map
			currentZoneRaidId = RaidZones[GetUnitZone("player")]

			if self:IsInRaidZone() then
				if (self.raidId ~= self:GetRaidIdFromCurrentZone()) then
					if (self.raidId > 0) then
						self:UnregisterEvents()
					end
					self:RegisterEvents()
				end
			elseif (self.raidId > 0) then
				self:UnregisterEvents()
			end
		end
		OnZoneChanged()
		--EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_ZONE_CHANGED, OnZoneChanged) -- Doesn't fire after zoning and not always when subzoning
		--EVENT_MANAGER:RegisterForEvent(self.Name, EVENT_CURRENT_SUBZONE_LIST_CHANGED, OnZoneChanged) -- Better than above but still not perfect
		CALLBACK_MANAGER:RegisterCallback("OnWorldMapChanged", OnZoneChanged) -- might as well listen to this since that code is executed anyways

		-- Change vitality bonus announcement to not conflict with our own
		-- TODO: Update to new announcement structure in ESO:Morrowind
		local CSH = ZO_CenterScreenAnnounce_GetHandlers()
		CSH[EVENT_RAID_REVIVE_COUNTER_UPDATE] = function(currentCount, countDelta)
			if not IsRaidInProgress() then
				return
			end
			if countDelta < 0 then
				if CENTER_SCREEN_ANNOUNCE.CreateMessageParams then
					local messageParams = CENTER_SCREEN_ANNOUNCE:CreateMessageParams(CSA_CATEGORY_SMALL_TEXT, SOUNDS.RAID_TRIAL_COUNTER_UPDATE)
					messageParams:SetText(zo_strformat(SI_REVIVE_COUNTER_UPDATED_LARGE, "EsoUI/Art/Trials/VitalityDepletion.dds"))
					messageParams:SetCSAType(CENTER_SCREEN_ANNOUNCE_TYPE_RAID_TRIAL)
					return messageParams
				else
					return SOUNDS.RAID_TRIAL_COUNTER_UPDATE, zo_strformat(SI_REVIVE_COUNTER_UPDATED_LARGE, "EsoUI/Art/Trials/VitalityDepletion.dds")
				end
			end
		end

	end

end


-- -----------------------------
-- EVENT: EVENT_BOSSES_CHANGED
do -----------------------------

	local UI = RaidNotifier.UI

	local function GetNumBosses()
		local count = 0
		for i = 1, MAX_BOSSES do
			if DoesUnitExist("boss"..i) then
				count = count + 1
			end
		end
		return count
	end

	function RaidNotifier.OnBossesChanged()
	
		local raidId = RaidNotifier.raidId
		if (raidId == RAID_MAW_OF_LORKHAJ) then
			local buffsDebuffs, settings = RaidNotifier.BuffsDebuffs.maw_lorkhaj, RaidNotifier.Vars.mawLorkhaj

			UI.SetElementHidden("mawLorkhaj", "zhaj_glyph_window", true)
			local map       = GetMapTileTexture()
			local bossCount = GetNumBosses()
			if (bossCount == 1 and map == "Art/maps/reapersmarch/Maw_of_Lorkaj_Base_0.dds") then
				--d("Zhaj'hassa the Forgotten")
				buffsDebuffs.zhajBoss_knownGlyphs = {}
				if (settings.zhaj_glyphs) then
					UI.SetElementHidden("mawLorkhaj", "zhaj_glyph_window", false)
				end
			elseif (bossCount == 2 and map == "Art/maps/reapersmarch/MawLorkajSuthaySanctuary_Base_0.dds") then
				--d("False Moon Twins, S’Kinrai and Vashai")
			elseif (bossCount == 1 and map == "Art/maps/reapersmarch/MawLorkajSevenRiddles_Base_0.dds") then
			
			end
		end
	end

end


-- ---------------------------
-- EVENT: EVENT_COMBAT_EVENT
do ---------------------------

	local LUNIT = LibStub:GetLibrary("LibUnits")
	local UI    = RaidNotifier.UI
	
	-- Debugging 
	local debugResults = {
		ACTION_RESULT_BEGIN,
		ACTION_RESULT_BEGIN_CHANNEL,
		ACTION_RESULT_EFFECT_GAINED,
		ACTION_RESULT_EFFECT_GAINED_DURATION,
	}
	local debugList    = {}
	for _, result in ipairs(debugResults) do
		debugList[result] = {}
	end
	local debugMsg = "[%d] %s (%d)%s%s"
	local noSpam = true

	function RaidNotifier.OnCombatEvent(_, result, isError, aName, aGraphic, aActionSlotType, sName, sType, tName, tType, hitValue, pType, dType, log, sUnitId, tUnitId, abilityId)
		
		local raidId = RaidNotifier.raidId
		local self   = RaidNotifier

		-- Debugging 
		if (self.Vars.dbg.tracker and debugList[result] ~= nil) then
			local function FormatUnit(prefix, uType, uName, uId)
				if uId == 0 then
					return ""
				else
					uName = uName ~= "" and uName or LUNIT:GetNameForUnitId(uId)
					if uName ~= "" then
						return zo_strformat("<<1>><<t:2>>", prefix, uName)
					else
						return zo_strformat("<<1>><<2>>/<<3>>", prefix, uType, uId)
					end
				end
			end

			if (not debugList[result][abilityId] or not noSpam) then
				local source = FormatUnit(", [S] ", sType, sName, sUnitId)
				local target = FormatUnit(", [T] ", tType, tName, tUnitId)
				local ability = (aName ~= "" and aName ~= nil) and aName or GetAbilityName(abilityId)

				debugList[result][abilityId] = noSpam
				d(debugMsg:format(result, ability, abilityId, source, target))
			end
		end

		-- Unregister if we left the raid instance
		if self:IsInRaidZone() == false then
			self:UnregisterEvents()
			return
		end

		if (raidId == RAID_HEL_RA_CITADEL) then
			local buffsDebuffs, settings = self.BuffsDebuffs.hel_ra, self.Vars.helra

			if (result == ACTION_RESULT_BEGIN) then

				-- Warrior Stone Form
				--   This one needs a small trick: sometimes the Warrior will attempt to stone
				--   two people but only the last person actually gets trapped. But because it 
				--   is the last person that gets trapped and not the first we cannot use the
				--   normal interval code. So we add a delay and check if we got another alert
				--   before actually displaying it.
				if (abilityId == buffsDebuffs.warrior_stoneform) then
					if (settings.warrior_stoneform >= 1) then
						tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
						
						local lastIndex = self:GetLastNotify("helra", "warrior_stoneform") + 1
						self:SetLastNotify("helra", "warrior_stoneform", lastIndex)
						zo_callLater(function()
							if (lastIndex == self:GetLastNotify("helra", "warrior_stoneform")) then
								if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
									self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_HELRA_WARRIOR_STONEFORM), "helra", "warrior_stoneform")
								elseif ( tName ~= "" and settings.warrior_stoneform == 2 ) then
									self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_HELRA_WARRIOR_STONEFORM_OTHER), tName), "helra", "warrior_stoneform")
								end
							end
						end, 200)
					end
				end

			elseif (result == ACTION_RESULT_EFFECT_GAINED_DURATION) then

				if (tType == COMBAT_UNIT_TYPE_PLAYER) then 

				end

			end
		end


		if (raidId == RAID_AETHERIAN_ARCHIVE) then
			local buffsDebuffs, settings = self.BuffsDebuffs.archive, self.Vars.archive

			if (result == ACTION_RESULT_BEGIN) then

				-- Lightning Storm Atronach
				if (buffsDebuffs.stormatro_impendingstorm == abilityId) then
					if settings.stormatro_impendingstorm then
						self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_ARCHIVE_STORMATRO_IMPENDINGSTORM), "archive", "stormatro_impendingstorm")
					end
				elseif (buffsDebuffs.stormatro_lightningstorm == abilityId) then
					if settings.stormatro_lightningstorm then
						self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_ARCHIVE_STORMATRO_LIGHTNINGSTORM), "archive", "stormatro_lightningstorm")
					end

				-- Foundation Stone Atronach
				elseif (buffsDebuffs.stoneatro_boulderstorm == abilityId) then
					if settings.stoneatro_boulderstorm then
						self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_ARCHIVE_STONEATRO_BOULDERSTORM), "archive", "stoneatro_boulderstorm", 8)
					end
				elseif (buffsDebuffs.stoneatro_bigquake == abilityId) then
					if settings.stoneatro_bigquake then
						self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_ARCHIVE_STONEATRO_BIGQUAKE), "archive", "stoneatro_bigquake", 8)
					end

				-- Celestial Mage
				elseif (buffsDebuffs.mage_conjure_axe[abilityId]) then
					if settings.mage_conjure_axe then
					
					end
				elseif (buffsDebuffs.mage_conjure_reflection[abilityId]) then
					if settings.mage_conjure_reflection then
						--self.tempVars.minions.archive.reflections[tUnitId] = {
						--	uId = tUnitId,
						--	health    = 1000000,
						--	maxHealth = 1000000,
						--	name = "Conjured Reflection",
						--}
					end

				-- Overchargers, Overcharged
				elseif (buffsDebuffs.overcharged == abilityId) then
					tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
					if settings.overcharge >= 1 then
						if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_ARCHIVE_OVERCHARGE), "archive", "overcharge")
						elseif ( tName ~= "" and settings.overcharge == 2 ) then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_ARCHIVE_OVERCHARGE_OTHER), tName), "archive", "overcharge")
						end
					end

				-- Overchargers, Call Lightning
				elseif (buffsDebuffs.call_lightning == abilityId) then
					tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
					if settings.call_lightning >= 1 then
						if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_ARCHIVE_CALL_LIGHTNING), "archive", "call_lightning")
						elseif ( tName ~= "" and settings.call_lightning == 2 ) then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_ARCHIVE_CALL_LIGHTNING_OTHER), tName), "archive", "call_lightning")
						end
					end
				end
			
			elseif (result == ACTION_RESULT_EFFECT_GAINED_DURATION) then

				if (tType == COMBAT_UNIT_TYPE_PLAYER) then 

				end

--[[		elseif (result == ACTION_RESULT_DAMAGE or
				result == ACTION_RESULT_DOT_TICK or
				result == ACTION_RESULT_CRITICAL_DAMAGE or
				result == ACTION_RESULT_DOT_TICK_CRITICAL or
				--result == ACTION_RESULT_BLOCKED_DAMAGE or
				--result == ACTION_RESULT_DAMAGE_SHIELDED or
				result == ACTION_RESULT_HOT_TICK or
				result == ACTION_RESULT_HEAL or
				result == ACTION_RESULT_CRITICAL_HEAL or
				result == ACTION_RESULT_HOT_TICK_CRITICAL) then

				if (settings.mage_conjure_reflection and self.tempVars.minions.archive.reflections[tUnitId]) then
					local target = self.tempVars.minions.archive.reflections[tUnitId]
					if (result == ACTION_RESULT_HEAL or result == ACTION_RESULT_HOT_TICK or result == ACTION_RESULT_CRITICAL_HEAL or result == ACTION_RESULT_HOT_TICK_CRITICAL) then
						hitValue = -hitValue
					end
					target.health = target.health - hitValue
					if target.health > target.maxHealth then 
						target.health = target.maxHealth
					elseif target.health < 0 then
						target.health = 0
					end
					--df("[Test Combat] Damaged #%d (%s) for %d, new health is %d", target.uId, target.name, hitValue, target.health)
				end
]]--
			end

		end


		if (raidId == RAID_SANCTUM_OPHIDIA) then
			local buffsDebuffs, settings = self.BuffsDebuffs.sanctum_ophidia, self.Vars.sanctumOphidia

			--We're lucky that alot of things can be detected slightly before they hit the player
			if (result == ACTION_RESULT_BEGIN) then

				-- Serpent, Poison Phase
				if (buffsDebuffs.poison_teleport[abilityId]) then
					local phase = buffsDebuffs.poison_teleport[abilityId]
					if settings.serpent_poison == 2 or phase == 5 then --"Full" or final poison phase, use detailed text
						self:AddAnnouncement(GetString("RAIDNOTIFIER_ALERTS_SANCTUM_SERPENT_POISON", phase), "sanctumOphidia", "serpent_poison")
					elseif settings.serpent_poison == 1 then --"Normal", use plain text
						self:AddAnnouncement(GetString("RAIDNOTIFIER_ALERTS_SANCTUM_SERPENT_POISON", 0), "sanctumOphidia", "serpent_poison")
					end

				-- Serpent (Hardmode), World-Shaper
				--    No idea why I thought this works but it simply doesn't, I probably mixed things up with 
				--    simply dying from this ability instead of it being a channel that the Serpent does
				--elseif (buffsDebuffs.serpent_worldshaper == abilityId) then
				--	tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
				--	df("WORLDSHAPER, %d, %d/%d/%s", result, tType, tUnitId, tName)
				--	dbg(string.format("World-Shaper (%d) on %s", abilityId, tName))
				--	if settings.serpent_worldshaper then
				--		if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
				--			self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_SERPENT_WORLDSHAPER), 3000, "bla")
				--		elseif ( tName ~= "" and settings.serpent_worldshaper == 2 ) then
				--			self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_SERPENT_WORLDSHAPER_PLAYER), tName), 3000, "bla")
				--		end
				--	end

				-- Trolls, Spreading Poison
				elseif (buffsDebuffs.spreading_poison[abilityId]) then
					if settings.troll_poison >= 1 then
						tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
						if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_TROLL_POISON), "sanctumOphidia", "troll_poison")
						elseif ( tName ~= "" and settings.troll_poison == 2 ) then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_TROLL_POISON_PLAYER), tName), "sanctumOphidia", "troll_poison")
						end
					end

				-- Trolls, Boulder Toss
				elseif (buffsDebuffs.boulder_toss == abilityId) then
					if settings.troll_boulder >= 1 then
						tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
						if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_TROLL_BOULDER), "sanctumOphidia", "troll_boulder")
						elseif ( tName ~= "" and settings.troll_boulder == 2 ) then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_TROLL_BOULDER_PLAYER), tName), "sanctumOphidia", "troll_boulder")
						end
					end

				-- Overchargers, Overcharged
				elseif (buffsDebuffs.overcharged == abilityId) then
					if settings.overcharge >= 1 then
						tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
						if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_OVERCHARGE), "sanctumOphidia", "overcharge")
						elseif ( tName ~= "" and settings.overcharge == 2 ) then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_OVERCHARGE_PLAYER), tName), "sanctumOphidia", "overcharge")
						end
					end

				-- Overchargers, Call Lightning
				elseif (buffsDebuffs.call_lightning == abilityId) then
					if settings.call_lightning >= 1 then
						tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
						if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_CALL_LIGHTNING), "sanctumOphidia", "call_lightning")
						elseif ( tName ~= "" and settings.call_lightning == 2 ) then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_CALL_LIGHTNING_PLAYER), tName), "sanctumOphidia", "call_lightning")
						end
					end

				end

			elseif (result == ACTION_RESULT_EFFECT_GAINED_DURATION) then
			
				-- TODO: Reintroduce simple alert when standing in a spear
			
				-- Mantikora Spear Throw Alert
				--    This one is a bit weird, the effect is added as soon as the red circle starts appearing (which is
				--    good). But this also means it may show multiple alerts, one for each of the people that are in the 
				--    target area. And since we'll always want the player to take priority we slightly delay the alert for
				--    other players and let the interval check handle the rest.
				--    The really nice thing is that we no longer have to support the "Near" option since you'll always be
				--    alerted if you'd end up inside the spear (excluding movement after it is thrown).
				--    UPDATE: Seems it simply always adds this ability to the three furthest people even if they are far
				--    away from each other.
				--if (abilityId == buffsDebuffs.mantikora_spear) then
				--	if settings.mantikora_spear >= 1 then
				--		tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
				--		df("Manti SpearThrow - %d/%d/%s", tType, tUnitId, tName)
				--		if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
				--			self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_MANTIKORA_SPEAR), 3000, SOUNDS.CHAMPION_POINTS_COMMITTED,
				--												5, "sanctumOphidia", "mantikora_spear")
				--		elseif ( tName ~= "" and settings.mantikora_spear == 2 ) then
				--			zo_callLater(function()
				--				self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_MANTIKORA_SPEAR_PLAYER), tName), 3000, SOUNDS.CHAMPION_POINTS_COMMITTED,
				--													5, "sanctumOphidia", "mantikora_spear")
				--			end, 100)
				--		else
				--			--dbg("Manticora Spear on unknown player #"..tUnitId)
				--		end
				--	end
				--end
				
				if (tType == COMBAT_UNIT_TYPE_PLAYER) then 

					-- Sanctum Serpent Magicka Detonation Alert
					if (abilityId == buffsDebuffs.magicka_deto) then
						if settings.magicka_deto then
							-- get current magicka percentage (only notify if the current magicka is over 15%)
							local current, maximum, _ = GetUnitPower("player", POWERTYPE_MAGICKA)
							local magickaPercentage   = zo_roundToNearest(current/maximum,0.01) * 100
							if magickaPercentage > 15 then
								self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_MAGICKA_DETONATION)), "sanctumOphidia", "magicka_deto", 5)
							end
						end
					end
					
					-- Mantikora Quake Alert
					if (abilityId == buffsDebuffs.mantikora_quake) then
						if settings.mantikora_quake then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_SANCTUM_MANTIKORA_QUAKE)), "sanctumOphidia", "mantikora_quake", 5)
						end
					end

				end

			end
		end


		if (raidId == RAID_DRAGONSTAR_ARENA) then
			local buffsDebuffs, settings = self.BuffsDebuffs.dragonstar, self.Vars.dragonstar

			if (result == ACTION_RESULT_BEGIN) then

				-- General: Taking Aim
				if (abilityId == buffsDebuffs.general_taking_aim) then
					tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
					dbg("Taking Aim (%d) on %s", abilityId, tName)
					if (settings.general_taking_aim) then
						if (tType == COMBAT_UNIT_TYPE_PLAYER) then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_GENERAL_TAKING_AIM), "dragonstar", "general_taking_aim")
						end
					end

				-- General: Crystal Blast
				elseif (abilityId == buffsDebuffs.general_crystal_blast) then
					tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
					dbg("Crystal Blast (%d) on %s", abilityId, tName)
					if (settings.general_crystal_blast) then
						if (tType == COMBAT_UNIT_TYPE_PLAYER) then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_GENERAL_CRYSTAL_BLAST), "dragonstar", "general_crystal_blast")
						end
					end

				-- Arena 2: Crushing Shock
				elseif (abilityId == buffsDebuffs.arena2_crushing_shock) then
					tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
					dbg("Crushing Shock (%d) on %s", abilityId, tName)
					if (settings.arena2_crushing_shock) then
						if (tType == COMBAT_UNIT_TYPE_PLAYER) then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_ARENA2_CRUSHING_SHOCK), "dragonstar", "arena2_crushing_shock")
						end
					end

				-- Arena 6: Drain Resource
				elseif (abilityId == buffsDebuffs.arena6_drain_resource) then
					tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
					dbg("Drain Resource (%d) on %s", abilityId, tName)
					if (settings.arena6_drain_resource >= 1) then
						if (tType == COMBAT_UNIT_TYPE_PLAYER) then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_ARENA6_DRAIN_RESOURCE), "dragonstar", "arena6_drain_resource")
						elseif (tName ~= "") then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_ARENA6_DRAIN_RESOURCE_OTHER), tName), "dragonstar", "arena6_drain_resource")
						end
					end

				-- Arena 8: Ice Charge
				elseif (abilityId == buffsDebuffs.arena8_ice_charge) then
					tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
					dbg("Ice Charge (%d) on %s", abilityId, tName)
					if (settings.arena8_ice_charge >= 1) then
						if (tType == COMBAT_UNIT_TYPE_PLAYER) then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_ARENA8_ICE_CHARGE), "dragonstar", "arena8_ice_charge")
						elseif (tName ~= "") then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_ARENA8_ICE_CHARGE_OTHER), tName), "dragonstar", "arena8_ice_charge")
						end
					end
				-- Arena 8: Fire Charge
				elseif (abilityId == buffsDebuffs.arena8_fire_charge) then
					tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
					dbg("Fire Charge (%d) on %s", abilityId, tName)
					if (settings.arena8_fire_charge >= 1) then
						if (tType == COMBAT_UNIT_TYPE_PLAYER) then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_ARENA8_FIRE_CHARGE), "dragonstar", "arena8_fire_charge")
						elseif (tName ~= "") then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_ARENA8_FIRE_CHARGE_OTHER), tName), "dragonstar", "arena8_fire_charge")
						end
					end

				end

			elseif (result == ACTION_RESULT_EFFECT_GAINED_DURATION) then

				-- Arena 7: Unstable Core (Eclipse)
				if (abilityId == buffsDebuffs.arena7_unstable_core) then
					if (settings.arena7_unstable_core) then
						if (tType == COMBAT_UNIT_TYPE_PLAYER) then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_DRAGONSTAR_ARENA7_UNSTABLE_CORE), "dragonstar", "arena7_unstable_core")
						end
					end

				end

			end

		end


		if (raidId == RAID_MAW_OF_LORKHAJ) then
			local buffsDebuffs, settings = self.BuffsDebuffs.maw_lorkhaj, self.Vars.mawLorkhaj

			local function GetDistanceToUnit(unit)
				local pX, pY, uX, uY = GetMapPlayerPosition("player"), GetMapPlayerPosition(unit)
				return math.sqrt((pX-uX)*(pX-uX)+(pY-uY)*(pY-uY)) * 1000
			end

			local function FindGlyph(glyphId, glyphs, knownGlyphs, allowNew)
				if not knownGlyphs[glyphId] then
					if not allowNew then return 0 end

					local lowestDistance = 9999
					local lowestIndex = 0
					local lowestUnit = ""
					for index, data in ipairs(glyphs) do
						for p=1, GetGroupSize() do
							if IsUnitOnline("group"..p) then
								local pX, pY = GetMapPlayerPosition("group"..p)
								if (knownGlyphs[index] == nil) then --only check unknown glyphs
									local x, y = data.x, data.y
									local distance = math.sqrt((pX-x)*(pX-x)+(pY-y)*(pY-y)) * 1000
									if (distance < lowestDistance) then
										lowestDistance=distance
										lowestIndex=index
										lowestUnit = GetUnitName("group"..p)
									end
								end
							end
						end
					end
					if lowestDistance < 8 and lowestIndex > 0 then
						dbg("Glyph #%d -> %d, first used by %s", lowestIndex, glyphId, lowestUnit)
						knownGlyphs[lowestIndex] = glyphId
						knownGlyphs[glyphId] = lowestIndex
						return lowestIndex
					else
						return 0
					end
				else
					return knownGlyphs[glyphId]
				end
			end

			--Zhaj'hassa the Forgotten 
			-- Glyphs & Curse (UI elements only, notification code is further down below)
			if settings.zhaj_glyphs then
				if (abilityId == buffsDebuffs.zhajBoss_glyphability) then
					local findNew = (result == ACTION_RESULT_EFFECT_FADED) --only scan for new glyph when effect/glyph is used by the player, NOT when it respawns
					local glyphIndex = FindGlyph(tUnitId, buffsDebuffs.zhajBoss_glyphs, buffsDebuffs.zhajBoss_knownGlyphs, findNew) 
					if (result == ACTION_RESULT_EFFECT_GAINED_DURATION) then
						UI.StopGlyphTimer(glyphIndex)
					elseif (result == ACTION_RESULT_EFFECT_FADED) then
						UI.StartGlyphTimer(glyphIndex, buffsDebuffs.zhajBoss_glyphcooldown)
					end
				elseif (tType == COMBAT_UNIT_TYPE_PLAYER and abilityId == buffsDebuffs.zhajBoss_curseability) then
					local glyphIndex = 7
					if (result == ACTION_RESULT_EFFECT_GAINED_DURATION) then 
						UI.StartGlyphTimer(glyphIndex, buffsDebuffs.zhajBoss_curseduration)
					elseif (result == ACTION_RESULT_EFFECT_FADED) then
						UI.StopGlyphTimer(glyphIndex)
					end
				end
			end

			if (result == ACTION_RESULT_BEGIN) then
				--Sun-Eater Eclipse Field
				if (abilityId == buffsDebuffs.suneater_eclipse) then
					if settings.suneater_eclipse >= 1 then
						tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
						if (tType == COMBAT_UNIT_TYPE_PLAYER) then 
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_SUNEATER_ECLIPSE), "mawLorkhaj", "suneater_eclipse")
						elseif ( tName ~= "" and (settings.suneater_eclipse == 2 or (settings.suneater_eclipse == 3 and GetDistanceToUnit(LUNIT:GetUnitTagForUnitId(tUnitId)) < 2000)) ) then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_SUNEATER_ECLIPSE_OTHER), tName), "mawLorkhaj", "suneater_eclipse")
						else
						end
					end

				elseif (buffsDebuffs.rakkhat_threshingwings[abilityId]) then
					if settings.rakkhat_threshingwings then
						self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_RAKKHAT_THRESHINGWINGS), "mawLorkhaj", "rakkhat_threshingwings")
					end
				elseif (buffsDebuffs.rakkhat_darknessfalls == abilityId) then
					if settings.rakkhat_darknessfalls then
						self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_RAKKHAT_DARKNESSFALLS), "mawLorkhaj", "rakkhat_darknessfalls")
					end
				elseif (buffsDebuffs.rakkhat_darkbarrage[abilityId]) then
					if settings.rakkhat_darkbarrage then
						self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_RAKKHAT_DARKBARRAGE), "mawLorkhaj", "rakkhat_darkbarrage", 12)
					end
				end

			elseif (result == ACTION_RESULT_EFFECT_GAINED_DURATION) then

				if (tType == COMBAT_UNIT_TYPE_PLAYER) then 

					--Grip of Lorkhaj (1st boss debuff)
					if (buffsDebuffs.zhaj_gripoflorkhaj[abilityId]) then
						if settings.zhaj_gripoflorkhaj then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_ZHAJ_GRIPOFLORKHAJ), "mawLorkhaj", "zhaj_gripoflorkhaj", 4)
						end
					end

					-- False Moon Twins, S’Kinrai and Vashai 
					if (buffsDebuffs.twinBoss_lunaraspect[abilityId]) then
						dbg("[%d] Receiving Lunar Aspect", abilityId)
						if settings.twinBoss_aspects >= 2 then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_LUNAR_ASPECT), "mawLorkhaj", "twinBoss_aspects", 4)
						end
					elseif (buffsDebuffs.twinBoss_shadowaspect[abilityId]) then
						dbg("[%d] Receiving Shadow Aspect", abilityId)
						if settings.twinBoss_aspects >= 2 then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_SHADOW_ASPECT), "mawLorkhaj", "twinBoss_aspects", 4)
						end
					elseif (buffsDebuffs.twinBoss_lunarconversion[abilityId]) then
						dbg("[%d] Converting to Lunar Aspect", abilityId)
						--conversion just started
						if settings.twinBoss_aspects >= 1 then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_LUNAR_CONVERSION), "mawLorkhaj", "twinBoss_aspects", 4)
						end
					elseif (buffsDebuffs.twinBoss_shadowconversion[abilityId]) then
						dbg("[%d] Converting to Shadow Aspect", abilityId)
						--conversion just started
						if settings.twinBoss_aspects >= 1 then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_SHADOW_CONVERSION), "mawLorkhaj", "twinBoss_aspects", 4)
						end
					end

					--Dro'm Athra Savage / Dro'm Athra Hulk: Armor Shatter
					if (buffsDebuffs.shattered[abilityId]) then
						if settings.shattered then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_SHATTERED), "mawLorkhaj", "shattered", 4)
						end
					end

					--Marked for Death (panthers)
					if (buffsDebuffs.markedfordeath[abilityId]) then
						if settings.markedfordeath then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_MARKEDFORDEATH), "mawLorkhaj", "markedfordeath", 4)
						end
					end

				end

				--Rakkhat, Fang of Lorkhaj
				if (abilityId == buffsDebuffs.rakkhat_unstablevoid) then
					if settings.rakkhat_unstablevoid >= 1 then
						tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
						if ( tType == COMBAT_UNIT_TYPE_PLAYER ) then 
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_RAKKHAT_UNSTABLE_VOID), "mawLorkhaj", "rakkhat_unstablevoid")
						elseif ( tName ~= "" and (settings.rakkhat_unstablevoid == 2) ) then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_RAKKHAT_UNSTABLE_VOID_OTHER), tName), "mawLorkhaj", "rakkhat_unstablevoid")
						end
					end
				elseif (buffsDebuffs.rakkhat_lunarbastion[abilityId]) then
					if settings.rakkhat_lunarbastion1 >= 1 then
						tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
						if (tType == COMBAT_UNIT_TYPE_PLAYER)  then
							if (settings.rakkhat_lunarbastion1 == 1 or settings.rakkhat_lunarbastion1 == 3) then --if "Self" or "All"
								self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_RAKKHAT_LUNARBASTION1), "mawLorkhaj", "rakkhat_lunarbastion1")
							end
						elseif (tName ~= "") then 
							if (settings.rakkhat_lunarbastion1 == 2 or settings.rakkhat_lunarbastion1 == 3) then --if "Other" or "All"
								self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_RAKKHAT_LUNARBASTION1_OTHER), tName), "mawLorkhaj", "rakkhat_lunarbastion1")
							end
						end
					end
				end

			elseif (result == ACTION_RESULT_EFFECT_FADED) then

				if (tType == COMBAT_UNIT_TYPE_PLAYER) then
					-- End of conversion now properly falls under ACTION_RESULT_EFFECT_FADED
					if (buffsDebuffs.twinBoss_lunarconversion[abilityId]) then
						--conversion ended
						dbg("[%d] Conversion Complete", abilityId)
						if settings.twinBoss_aspects >= 3 then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_LUNAR_ASPECT), "mawLorkhaj", "twinBoss_aspects", 4)
						end
					elseif (buffsDebuffs.twinBoss_shadowconversion[abilityId]) then
						--conversion ended
						dbg("[%d] Conversion Complete", abilityId)
						if settings.twinBoss_aspects >= 3 then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_SHADOW_ASPECT), "mawLorkhaj", "twinBoss_aspects", 4)
						end
					elseif (buffsDebuffs.twinBoss_aspectremoval[abilityId]) then
						dbg("[%d] Removing Aspect?", abilityId)
					end
				end

				if (buffsDebuffs.rakkhat_lunarbastion[abilityId]) then
					if settings.rakkhat_lunarbastion2 >= 1 then
						tName = LUNIT:GetNameForUnitId(tUnitId) --isn't supplied by event for group members, only for the player
						if (tType == COMBAT_UNIT_TYPE_PLAYER) then
							if (settings.rakkhat_lunarbastion2 == 1 or settings.rakkhat_lunarbastion2 == 3) then --if "Self" or "All"
								self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_RAKKHAT_LUNARBASTION2), "mawLorkhaj", "rakkhat_lunarbastion2")
							end
						elseif (tName ~= "") then 
							if (settings.rakkhat_lunarbastion2 == 2 or settings.rakkhat_lunarbastion2 == 3) then --if "Other" or "All"
								self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_MAWLORKHAJ_RAKKHAT_LUNARBASTION2_OTHER), tName), "mawLorkhaj", "rakkhat_lunarbastion2")
							end
						end
					end
				end
			end
		end


		if (raidId == RAID_MAELSTROM_ARENA) then
			local buffsDebuffs, settings = self.BuffsDebuffs.maelstrom, self.Vars.maelstrom

			if (result == ACTION_RESULT_BEGIN) then
			elseif (result == ACTION_RESULT_EFFECT_GAINED_DURATION) then

				if (tType == COMBAT_UNIT_TYPE_PLAYER) then

					if (buffsDebuffs.stage7_poison[abilityId]) then 
						if settings.stage7_poison then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAELSTROM_STAGE7_POISON), "maelstrom", "stage7_poison", 15)
						end

					elseif (buffsDebuffs.stage9_synergy == abilityId) then
						if settings.stage9_synergy then
							self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_MAELSTROM_STAGE9_SYNERGY), "maelstrom", "stage9_synergy", 15)
						end

					end

				end
			end
		end


		if (raidId == RAID_HALLS_OF_FABRICATION) then
			local buffsDebuffs, settings = self.BuffsDebuffs.halls_fab, self.Vars.halls_fab
			
			if (result == ACTION_RESULT_BEGIN) then
				--[00:25:21] [2200] Flux Burst (90755), Source: 0/0/, Target:Princess
				--[23:32:27] [2245] Channeled Lightning (90877), Source: Pinnacle Factotum, Target: Kyoma

			elseif (result == ACTION_RESULT_EFFECT_GAINED_DURATION) then
				if (tType == COMBAT_UNIT_TYPE_PLAYER) then
				
				end

			end
		end

	end
end


-- -----------------------------
-- EVENT: EVENT_EFFECT_CHANGED
do -----------------------------

	function RaidNotifier.OnEffectChanged(eventCode, changeType, eSlot, eName, uTag, beginTime, endTime, stackCount, iconName, buffType, eType, aType, statusEffectType, uName, uId, abilityId, uType) 

		local raidId = RaidNotifier.raidId
		local self   = RaidNotifier

		-- Unregister if we left the raid instance
		if self:IsInRaidZone() == false then
			self:UnregisterEvents()
			return
		end

		-- Buff Food
		-- TODO: Replace, Remove or Revamp???
		if (self.Vars.general.buffFood_reminder and uType == COMBAT_UNIT_TYPE_PLAYER) then
			local buffsDebuffs = self.BuffsDebuffs.buffFood
			local buffFoodFound = false
			local reminderInterval = self.Vars.general.buffFood_reminder_interval

			local numAuras = GetNumBuffs("player")
			if (numAuras > 0) then
				for x = 1, numAuras do
					local name, _, finish, _, _, _, _, _, _, _, abilityId, _ = GetUnitBuffInfo('player', x)
					if buffsDebuffs[abilityId] then
						buffFoodFound = true

						local bufffood_remaining = finish - (GetFrameTimeMilliseconds() / 1000)
						local formatedTime       = ZO_FormatTime(bufffood_remaining, TIME_FORMAT_STYLE_COLONS, TIME_FORMAT_PRECISION_SECONDS)

						-- new set interval
						if bufffood_remaining <= 600 then
							self:AddAnnouncement(zo_strformat(GetString(RAIDNOTIFIER_ALERTS_GENERAL_BUFFFOOD_MINUTES), name, formatedTime), "general", "buffFood_reminder", reminderInterval)
						end
					end
				end
			end
			-- no bufffood found, alert every interval
			if buffFoodFound == false then
				self:AddAnnouncement(GetString(RAIDNOTIFIER_ALERTS_GENERAL_NO_BUFFFOOD), "general", "buffFood_reminder", reminderInterval)
			end
		end

	end

end


-- ----------------------------
-- EVENT: EVENT_ADD_ON_LOADED
-- ----------------------------
local function OnAddonLoaded(_, addonName)
    if addonName ~= RaidNotifier.Name then return end
    EVENT_MANAGER:UnregisterForEvent(RaidNotifier.Name, EVENT_ADD_ON_LOADED)
	RaidNotifier:Initialize()

end
EVENT_MANAGER:RegisterForEvent(RaidNotifier.Name, EVENT_ADD_ON_LOADED, OnAddonLoaded)