-- Localized addon namespace (one intentional global for debug access)
local AddonName = "HydroHomieReminder"
local addon = {}
_G[AddonName] = addon

-- Localized Blizzard / WoW APIs (faster + avoids accidental global overrides)
local CreateFrame = CreateFrame
local UnitClass = UnitClass
local UnitExists = UnitExists
local UnitIsDead = UnitIsDead
local UnitHasVehicleUI = UnitHasVehicleUI
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local PlaySound = PlaySound

local C_Timer = C_Timer
local C_Spell = C_Spell
local IsPlayerSpell = IsPlayerSpell
local SOUNDKIT = SOUNDKIT

-- Constants
local FROST_SPEC_ID = 64

-- Spell/Talent IDs (Retail: talents typically map to spell IDs for "known" checks)
local WATER_ELEMENTAL_ID = 31687
local LONELY_WINTER_ID  = 205024

-- Options
local PLAY_SOUND = true
local SOUND_TO_PLAY = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959 -- fallback numeric if needed

-- State
local warningFrame
local eventFrame
local lastWarnState = false
local pendingUpdate = false

-- ---- Helpers ----

local function SpellKnown(spellID)
    -- Retail-safe: prefer C_Spell if available
    if C_Spell and C_Spell.IsSpellKnown then
        return C_Spell.IsSpellKnown(spellID)
    end
    return IsPlayerSpell and IsPlayerSpell(spellID)
end

local function IsFrostMage()
    local _, playerClass = UnitClass("player")
    if playerClass ~= "MAGE" then
        return false
    end

    local specIndex = GetSpecialization()
    if not specIndex then
        return false
    end

    local specID = GetSpecializationInfo(specIndex)
    return specID == FROST_SPEC_ID
end

local function HasPetOut()
    return UnitExists("pet") and not UnitIsDead("pet")
end

local function ShouldWarn()
    -- Only relevant for Frost Mage
    if not IsFrostMage() then
        return false
    end

    -- Don’t warn in vehicles/possession (pet state can be weird)
    if UnitHasVehicleUI("player") then
        return false
    end

    -- If Lonely Winter is chosen, you should NOT have a pet -> no warning
    if SpellKnown(LONELY_WINTER_ID) then
        return false
    end

    -- Only warn if Water Elemental talent/spell is known
    if not SpellKnown(WATER_ELEMENTAL_ID) then
        return false
    end

    -- Known + not lonely winter + no pet => warn
    return not HasPetOut()
end

local function UpdateWarning()
    local shouldWarn = ShouldWarn()

    if shouldWarn then
        warningFrame:Show()
    else
        warningFrame:Hide()
    end

    -- Play sound on transition: false -> true
    if PLAY_SOUND and (not lastWarnState) and shouldWarn then
        -- pcall so a sound error never bricks the addon
        pcall(PlaySound, SOUND_TO_PLAY, "Master")
    end

    lastWarnState = shouldWarn
end

local function QueueUpdate()
    -- Coalesce bursts of events into one update next frame
    if pendingUpdate then return end
    pendingUpdate = true

    C_Timer.After(0, function()
        pendingUpdate = false
        UpdateWarning()
    end)
end

-- ---- Frames ----

local function CreateWarningFrame()
    local frame = CreateFrame("Frame", AddonName .. "WarningFrame", UIParent, "BackdropTemplate")
    frame:SetSize(420, 60)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.text:SetPoint("CENTER")
    frame.text:SetText("|cffff4040SUMMON YOUR WATER ELEMENTAL|r")

    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.7)
    end

    return frame
end

local function OnEvent(self, event, ...)
    if event == "UNIT_HEALTH" then
        local unit = ...
        if unit ~= "pet" then return end
    end

    QueueUpdate()
end

local function CreateEventFrame()
    local frame = CreateFrame("Frame", AddonName .. "EventFrame")

    frame:RegisterEvent("PLAYER_LOGIN")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    frame:RegisterEvent("UNIT_PET")
    frame:RegisterEvent("PET_BAR_UPDATE")
    frame:RegisterEvent("UNIT_HEALTH")

    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")

    -- Talent changes can fire different events across patches; include a couple common ones:
    frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    frame:RegisterEvent("PLAYER_TALENT_UPDATE")

    frame:SetScript("OnEvent", OnEvent)
    return frame
end

-- Public (optional) controls
function addon:Disable()
    if warningFrame then warningFrame:Hide() end
    if eventFrame then
        eventFrame:UnregisterAllEvents()
        eventFrame:SetScript("OnEvent", nil)
    end
end

function addon:ForceUpdate()
    QueueUpdate()
end

-- Init
warningFrame = CreateWarningFrame()
eventFrame = CreateEventFrame()
QueueUpdate()

-- Expose for debugging (optional)
addon.warningFrame = warningFrame
addon.UpdateWarning = UpdateWarning
addon.SpellKnown = SpellKnown
