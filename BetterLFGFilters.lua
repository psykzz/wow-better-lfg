local addonName = ...
local settings
local browseFrame
local installed
local roleDataWarningShown
local menuWarningShown
local providerWarningShown
local classDataWarningShown
local playerClassWarningShown
local playerDataWarningShown
local playerLevelWarningShown

local MIN_PLAYER_LEVEL = 1
local MAX_PLAYER_LEVEL = 60

local function normalizeLevel(value, fallback)
    local level = tonumber(value)
    if not level then
        level = fallback
    end
    return math.max(MIN_PLAYER_LEVEL, math.min(MAX_PLAYER_LEVEL, math.floor(level)))
end

local FALLBACK_PLAYER_CLASSES = {
    "WARRIOR",
    "PALADIN",
    "HUNTER",
    "ROGUE",
    "PRIEST",
    "SHAMAN",
    "MAGE",
    "WARLOCK",
    "DRUID",
}

local function getPlayerClassList()
    if type(CLASS_SORT_ORDER) == "table" and #CLASS_SORT_ORDER > 0 then
        return CLASS_SORT_ORDER
    end
    return FALLBACK_PLAYER_CLASSES
end

local function getSelectedRoleFlags()
    local roles
    local roleAPI = C_LFGListRoles
    if roleAPI and type(roleAPI.GetRoles) == "function" then
        roles = roleAPI.GetRoles()
    end

    if type(roles) ~= "table" or not (roles.tank or roles.healer or roles.dps) then
        if roleAPI and type(roleAPI.GetSavedRoles) == "function" then
            roles = roleAPI.GetSavedRoles()
        end
    end

    if type(roles) ~= "table" or not (roles.tank or roles.healer or roles.dps) then
        roles = {}
    end
    if not (roles.tank or roles.healer or roles.dps)
        and C_LFGList
        and type(C_LFGList.GetAvailableRoles) == "function"
    then
        local tank, healer, damager = C_LFGList.GetAvailableRoles()
        roles.tank = tank == true
        roles.healer = healer == true
        roles.dps = damager == true
    end

    return roles
end

local function initializeSettings()
    if type(BetterLFGFiltersDB) ~= "table" then
        BetterLFGFiltersDB = {}
    end

    settings = BetterLFGFiltersDB
    local version = tonumber(settings.version) or 0
    if version < 1 then
        if settings.requireTank == nil then
            settings.requireTank = false
        end
        if settings.requireHealer == nil then
            settings.requireHealer = false
        end
        if settings.openForMyRole == nil then
            settings.openForMyRole = true
        end
        version = 1
    end

    if version < 2 then
        local roles = getSelectedRoleFlags()
        local legacyOpenForMyRole = settings.openForMyRole == true
        local selectedRoleCount = (roles.tank and 1 or 0)
            + (roles.healer and 1 or 0)
            + (roles.dps and 1 or 0)
        -- The old any-role filter maps cleanly only to one role-specific checkbox.
        local migrateLegacyRole = legacyOpenForMyRole and selectedRoleCount == 1
        if settings.needsTank == nil then
            settings.needsTank = migrateLegacyRole and roles.tank == true
        end
        if settings.needsHealer == nil then
            settings.needsHealer = migrateLegacyRole and roles.healer == true
        end
        if settings.needsDamage == nil then
            settings.needsDamage = migrateLegacyRole and roles.dps == true
        end
        if settings.hasTank == nil then
            settings.hasTank = settings.requireTank == true
        end
        if settings.hasHealer == nil then
            settings.hasHealer = settings.requireHealer == true
        end
        if settings.noMyClass == nil then
            settings.noMyClass = false
        end
        if settings.groupFit == nil then
            settings.groupFit = false
        end
        settings.version = 2
    end

    if version < 3 then
        settings.playerHasTank = false
        settings.playerHasHealer = false
        settings.playerHasDamage = false
        settings.playerMinLevel = MIN_PLAYER_LEVEL
        settings.playerMaxLevel = MAX_PLAYER_LEVEL
        settings.version = 3
    end

    if version < 4 then
        settings.playerClasses = {}
        settings.version = 4
    end

    settings.needsTank = settings.needsTank == true
    settings.needsHealer = settings.needsHealer == true
    settings.needsDamage = settings.needsDamage == true
    settings.noMyClass = settings.noMyClass == true
    settings.hasTank = settings.hasTank == true
    settings.hasHealer = settings.hasHealer == true
    settings.groupFit = settings.groupFit == true
    settings.playerHasTank = settings.playerHasTank == true
    settings.playerHasHealer = settings.playerHasHealer == true
    settings.playerHasDamage = settings.playerHasDamage == true
    settings.playerMinLevel = normalizeLevel(settings.playerMinLevel, MIN_PLAYER_LEVEL)
    settings.playerMaxLevel = normalizeLevel(settings.playerMaxLevel, MAX_PLAYER_LEVEL)
    if settings.playerMinLevel > settings.playerMaxLevel then
        settings.playerMaxLevel = settings.playerMinLevel
    end
    if type(settings.playerClasses) ~= "table" then
        settings.playerClasses = {}
    end

    local supportedClasses = {}
    for _, classFilename in ipairs(getPlayerClassList()) do
        supportedClasses[classFilename] = true
        settings.playerClasses[classFilename] = settings.playerClasses[classFilename] == true
    end
    for classFilename in pairs(settings.playerClasses) do
        if not supportedClasses[classFilename] then
            settings.playerClasses[classFilename] = nil
        end
    end
end

local function getSelectedRoleSlots()
    local selected = {}
    local roles = getSelectedRoleFlags()
    if roles.tank then
        selected[#selected + 1] = "TANK_REMAINING"
    end
    if roles.healer then
        selected[#selected + 1] = "HEALER_REMAINING"
    end
    if roles.dps then
        selected[#selected + 1] = "DAMAGER_REMAINING"
    end
    return selected
end

local function getCurrentGroupComposition()
    local memberCount = 1
    if type(GetNumGroupMembers) == "function" then
        local groupCount = GetNumGroupMembers()
        if type(groupCount) == "number" and groupCount > 0 then
            memberCount = groupCount
        end
    end

    local roleCounts = {}
    local soloRoleSlots
    if memberCount == 1 then
        soloRoleSlots = getSelectedRoleSlots()
    elseif type(GetGroupMemberCounts) == "function" then
        local counts = GetGroupMemberCounts()
        if type(counts) == "table" then
            roleCounts = counts
        end
    end

    local tanks = tonumber(roleCounts.TANK) or 0
    local healers = tonumber(roleCounts.HEALER) or 0
    local damage = tonumber(roleCounts.DAMAGER) or 0
    local restriction
    if memberCount >= 4 then
        restriction = "4+ members"
    elseif tanks >= 2 then
        restriction = "2 tanks"
    elseif healers >= 2 then
        restriction = "2 healers"
    end

    return {
        memberCount = memberCount,
        tanks = tanks,
        healers = healers,
        damage = damage,
        soloRoleSlots = soloRoleSlots,
        restriction = restriction,
    }
end

local function getFilterState()
    local groupComposition = settings.groupFit and getCurrentGroupComposition() or nil
    local groupFitActive = settings.groupFit
        and groupComposition
        and not groupComposition.restriction
    local active = settings.needsTank
        or settings.needsHealer
        or settings.needsDamage
        or settings.noMyClass
        or settings.hasTank
        or settings.hasHealer
        or groupFitActive
    return groupComposition, groupFitActive, active
end

local function getClassCount(counts)
    if type(UnitClass) ~= "function" then
        return nil
    end

    local _, classFilename = UnitClass("player")
    if not classFilename then
        return nil
    end

    return tonumber(counts[classFilename])
end

local function hasGroupFit(counts, groupComposition)
    local tankSlots = tonumber(counts.TANK_REMAINING) or 0
    local healerSlots = tonumber(counts.HEALER_REMAINING) or 0
    local damageSlots = tonumber(counts.DAMAGER_REMAINING) or 0

    if groupComposition.memberCount == 1 then
        if #groupComposition.soloRoleSlots == 0 then
            return tankSlots + healerSlots + damageSlots > 0
        end
        for _, roleSlot in ipairs(groupComposition.soloRoleSlots) do
            if (tonumber(counts[roleSlot]) or 0) > 0 then
                return true
            end
        end
        return false
    end

    if tankSlots < groupComposition.tanks
        or healerSlots < groupComposition.healers
        or damageSlots < groupComposition.damage
    then
        return false
    end

    local assignedMembers = groupComposition.tanks
        + groupComposition.healers
        + groupComposition.damage
    local unassignedMembers = math.max(0, groupComposition.memberCount - assignedMembers)
    return tankSlots + healerSlots + damageSlots - assignedMembers >= unassignedMembers
end

local function matchesGroupFilters(counts, groupComposition, groupFitActive)
    if type(counts) ~= "table" then
        return nil
    end

    if settings.needsTank and (tonumber(counts.TANK_REMAINING) or 0) == 0 then
        return false
    end
    if settings.needsHealer and (tonumber(counts.HEALER_REMAINING) or 0) == 0 then
        return false
    end
    if settings.needsDamage and (tonumber(counts.DAMAGER_REMAINING) or 0) == 0 then
        return false
    end
    if settings.noMyClass then
        local classCount = getClassCount(counts)
        if classCount == nil then
            if not classDataWarningShown then
                print(addonName .. ": class counts are unavailable; the class filter was skipped.")
                classDataWarningShown = true
            end
        elseif classCount > 0 then
            return false
        end
    end
    if settings.hasTank and (tonumber(counts.TANK) or 0) == 0 then
        return false
    end
    if settings.hasHealer and (tonumber(counts.HEALER) or 0) == 0 then
        return false
    end
    if groupFitActive and not hasGroupFit(counts, groupComposition) then
        return false
    end

    return true
end

local function arePlayerClassFiltersActive()
    for _, classFilename in ipairs(getPlayerClassList()) do
        if settings.playerClasses[classFilename] then
            return true
        end
    end
    return false
end

local function arePlayerFiltersActive()
    return settings.playerHasTank
        or settings.playerHasHealer
        or settings.playerHasDamage
        or arePlayerClassFiltersActive()
        or settings.playerMinLevel > MIN_PLAYER_LEVEL
        or settings.playerMaxLevel < MAX_PLAYER_LEVEL
end

local function matchesPlayerFilters(playerInfo)
    if type(playerInfo) ~= "table" then
        if not playerDataWarningShown then
            print(addonName .. ": player listing data is unavailable; player filters were skipped.")
            playerDataWarningShown = true
        end
        return nil
    end

    local roles = playerInfo.lfgRoles
    if type(roles) == "table" then
        local roleFilterSelected = settings.playerHasTank
            or settings.playerHasHealer
            or settings.playerHasDamage
        if roleFilterSelected
            and not (settings.playerHasTank and roles.tank)
            and not (settings.playerHasHealer and roles.healer)
            and not (settings.playerHasDamage and roles.dps)
        then
            return false
        end
    elseif settings.playerHasTank or settings.playerHasHealer or settings.playerHasDamage then
        if not playerDataWarningShown then
            print(addonName .. ": player role data is unavailable; role filters were skipped.")
            playerDataWarningShown = true
        end
    end

    if arePlayerClassFiltersActive() then
        local classFilename = playerInfo.classFilename
        if type(classFilename) ~= "string" then
            if not playerClassWarningShown then
                print(addonName .. ": player class data is unavailable; class filters were skipped.")
                playerClassWarningShown = true
            end
        elseif not settings.playerClasses[classFilename] then
            return false
        end
    end

    local level = tonumber(playerInfo.level)
    if level == nil then
        if (settings.playerMinLevel > MIN_PLAYER_LEVEL
            or settings.playerMaxLevel < MAX_PLAYER_LEVEL)
            and not playerLevelWarningShown
        then
            print(addonName .. ": player level data is unavailable; level filters were skipped.")
            playerLevelWarningShown = true
        end
        return true
    end

    return level >= settings.playerMinLevel and level <= settings.playerMaxLevel
end

local function getPlayerListingInfo(resultID)
    if type(C_LFGList.GetSearchResultPlayerInfo) == "function" then
        local playerInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
        if type(playerInfo) == "table" then
            return playerInfo
        end
    end
    if type(C_LFGList.GetSearchResultLeaderInfo) == "function" then
        return C_LFGList.GetSearchResultLeaderInfo(resultID)
    end
end

local function applyProviderFilter(scrollBox)
    local groupComposition, groupFitActive, active = getFilterState()
    local playerFiltersActive = arePlayerFiltersActive()
    if not active and not playerFiltersActive then
        return
    end

    if not C_LFGList
        or type(C_LFGList.GetSearchResultInfo) ~= "function"
        or (active and type(C_LFGList.GetSearchResultMemberCounts) ~= "function")
    then
        if not roleDataWarningShown then
            print(addonName .. ": LFG role data is unavailable; role filters were skipped.")
            roleDataWarningShown = true
        end
        return
    end

    local provider = scrollBox:GetDataProvider()
    if not provider or type(provider.ForEach) ~= "function" or type(provider.Remove) ~= "function" then
        if not providerWarningShown then
            print(addonName .. ": the LFG results provider is unavailable; role filters were skipped.")
            providerWarningShown = true
        end
        return
    end

    local nodesToRemove = {}
    local groupDividerNodes = {}
    local playerDividerNodes = {}
    local visibleGroupCount = 0
    local visiblePlayerCount = 0
    provider:ForEach(function(node)
        local data = node
        if type(node) == "table" and type(node.GetData) == "function" then
            data = node:GetData()
        end

        if type(data) == "table" and data.resultID then
            local resultInfo = C_LFGList.GetSearchResultInfo(data.resultID)
            local isGroup = resultInfo
                and type(resultInfo.numMembers) == "number"
                and resultInfo.numMembers > 1
                and data.category ~= 1
            local isPlayer = resultInfo
                and resultInfo.numMembers == 1

            if isGroup then
                if active and not resultInfo.hasSelf then
                    local counts = C_LFGList.GetSearchResultMemberCounts(data.resultID)
                    local matches = matchesGroupFilters(counts, groupComposition, groupFitActive)
                    if matches == false then
                        nodesToRemove[#nodesToRemove + 1] = node
                    else
                        visibleGroupCount = visibleGroupCount + 1
                    end
                else
                    visibleGroupCount = visibleGroupCount + 1
                end
            elseif isPlayer then
                if playerFiltersActive and not resultInfo.hasSelf then
                    local matches = matchesPlayerFilters(getPlayerListingInfo(data.resultID))
                    if matches == false then
                        nodesToRemove[#nodesToRemove + 1] = node
                    else
                        visiblePlayerCount = visiblePlayerCount + 1
                    end
                else
                    visiblePlayerCount = visiblePlayerCount + 1
                end
            end
        elseif type(data) == "table" and data.dividerType == 2 then
            groupDividerNodes[#groupDividerNodes + 1] = node
        elseif type(data) == "table" and data.dividerType == 1 then
            playerDividerNodes[#playerDividerNodes + 1] = node
        end
    end, false)

    if active and visibleGroupCount == 0 then
        for _, node in ipairs(groupDividerNodes) do
            nodesToRemove[#nodesToRemove + 1] = node
        end
    end
    if playerFiltersActive and visiblePlayerCount == 0 then
        for _, node in ipairs(playerDividerNodes) do
            nodesToRemove[#nodesToRemove + 1] = node
        end
    end

    for _, node in ipairs(nodesToRemove) do
        provider:Remove(node)
    end
end

local function hookResultListUpdate(frame, scrollBox)
    hooksecurefunc(frame, "UpdateResultList", function()
        applyProviderFilter(scrollBox)
    end)
end

local function createFilterMenuItems(rootDescription)
    rootDescription:CreateSpacer()
    rootDescription:CreateTitle("Group requires")

    local function addFilterCheckbox(label, settingKey, canToggle)
        return rootDescription:CreateCheckbox(label, function()
            return settings[settingKey]
        end, function()
            if canToggle and not canToggle() then
                return
            end
            settings[settingKey] = not settings[settingKey]
            browseFrame:UpdateResultList()
        end)
    end

    addFilterCheckbox("Needs Tank", "needsTank")
    addFilterCheckbox("Needs Healer", "needsHealer")
    addFilterCheckbox("Needs Damage", "needsDamage")

    local className = type(UnitClass) == "function" and select(1, UnitClass("player"))
    addFilterCheckbox(
        "No " .. (className or "same class") .. " already in group",
        "noMyClass"
    )

    addFilterCheckbox("Has Tank", "hasTank")
    addFilterCheckbox("Has Healer", "hasHealer")

    local groupComposition = getCurrentGroupComposition()
    local groupFitLabel = "Group fit"
    if groupComposition.restriction then
        groupFitLabel = groupFitLabel
            .. " |cffff0000("
            .. groupComposition.restriction
            .. ")|r"
    end

    local groupFitCheckbox = addFilterCheckbox(groupFitLabel, "groupFit", function()
        return not getCurrentGroupComposition().restriction
    end)
    if groupComposition.restriction and type(groupFitCheckbox.SetEnabled) == "function" then
        groupFitCheckbox:SetEnabled(false)
    end

    rootDescription:CreateSpacer()
    rootDescription:CreateTitle("Player requires")

    local function addPlayerRoleCheckbox(label, settingKey)
        rootDescription:CreateCheckbox(label, function()
            return settings[settingKey]
        end, function()
            settings[settingKey] = not settings[settingKey]
            browseFrame:UpdateResultList()
        end)
    end

    addPlayerRoleCheckbox("Has Tank", "playerHasTank")
    addPlayerRoleCheckbox("Has Healer", "playerHasHealer")
    addPlayerRoleCheckbox("Has DPS", "playerHasDamage")

    rootDescription:CreateTitle("Player level (1-60)")
    local levelRange = rootDescription:CreateTemplate("LevelRangeFrameTemplate")
    levelRange:AddInitializer(function(frame)
        frame:Reset()
        frame.MinLevel:SetMaxLetters(2)
        frame.MaxLevel:SetMaxLetters(2)
        frame:SetMinLevel(settings.playerMinLevel)
        frame:SetMaxLevel(settings.playerMaxLevel)
        frame:SetLevelRangeChangedCallback(function(minLevel, maxLevel)
            minLevel = normalizeLevel(minLevel, MIN_PLAYER_LEVEL)
            maxLevel = normalizeLevel(maxLevel, MAX_PLAYER_LEVEL)
            if minLevel > maxLevel then
                minLevel = maxLevel
            end
            settings.playerMinLevel = minLevel
            settings.playerMaxLevel = maxLevel
            browseFrame:UpdateResultList()
        end)
    end)

    rootDescription:CreateTitle("Player class")
    local localizedClassNames = _G.LOCALIZED_CLASS_NAMES_MALE
    for _, classFile in ipairs(getPlayerClassList()) do
        local classFilename = classFile
        local className = type(localizedClassNames) == "table"
            and localizedClassNames[classFilename]
            or classFilename
        rootDescription:CreateCheckbox(className, function()
            return settings.playerClasses[classFilename]
        end, function()
            settings.playerClasses[classFilename] = not settings.playerClasses[classFilename]
            browseFrame:UpdateResultList()
        end)
    end
end

local function addOptionsMenuItems(optionsButton)
    if not Menu or type(Menu.ModifyMenu) ~= "function" then
        return false
    end

    Menu.ModifyMenu("MENU_LFG_LISTING_SETTINGS", function(owner, rootDescription)
        if owner == optionsButton then
            createFilterMenuItems(rootDescription)
        end
    end)
    return true
end

local function install()
    if installed then
        return true
    end

    local frame = _G.LFGBrowseFrame
    local scrollBox = _G.LFGBrowseFrameScrollBox
    local optionsButton = _G.LFGBrowseFrameOptionsButton
    if not frame
        or not scrollBox
        or not optionsButton
        or type(frame.UpdateResultList) ~= "function"
    then
        return false
    end

    initializeSettings()
    browseFrame = frame
    if not addOptionsMenuItems(optionsButton) then
        if not menuWarningShown then
            print(addonName .. ": the LFG options menu cannot be extended.")
            menuWarningShown = true
        end
        return false
    end

    hookResultListUpdate(frame, scrollBox)
    installed = true
    browseFrame:UpdateResultList()
    return true
end

local events = CreateFrame("Frame")
local initialLogin
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, ...)
    if event == "GROUP_ROSTER_UPDATE" then
        if settings.groupFit then
            browseFrame:UpdateResultList()
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        initialLogin = ...
        self:UnregisterEvent(event)
    end

    if install() then
        if initialLogin then
            print(addonName .. " loaded in the Groups list.")
            initialLogin = false
        end
        self:UnregisterEvent("ADDON_LOADED")
        self:UnregisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
    end
end)
