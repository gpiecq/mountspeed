----------------------------------------------------------------------
-- MountSpeed  -  Swap.lua
-- Equipment set application and mount-state tracking (v2.0)
----------------------------------------------------------------------
local _, NS = ...
local Swap = {}
NS.Swap = Swap

local wasMounted     = false
local pendingApply   = nil   -- queued setName while in combat
local swappedTicker  = nil   -- polls while isMountSwapped, catches flight arrivals

----------------------------------------------------------------------
-- A slot is eligible only if BOTH sets have an item for it.
-- Prevents accidental undressing when only one column is configured.
----------------------------------------------------------------------
local function EligibleSlot(slotId)
    local s = NS.charDb.sets
    return s and s.mount[slotId] and s.base[slotId]
end

----------------------------------------------------------------------
-- Equip every eligible slot from sets[setName]. Combat-safe.
----------------------------------------------------------------------
function Swap:Apply(setName)
    if setName ~= "mount" and setName ~= "base" then return end

    if InCombatLockdown() then
        pendingApply = setName
        NS:Print("In combat — gear swap will run when combat ends.")
        return
    end

    local set = NS.charDb.sets and NS.charDb.sets[setName]
    if not set then return end

    local applied = false
    for slotId, itemId in pairs(set) do
        if EligibleSlot(slotId) then
            local current = GetInventoryItemID("player", slotId)
            if current ~= itemId then
                EquipItemByName(itemId, slotId)
                applied = true
            end
        end
    end

    NS.charDb.isMountSwapped = (setName == "mount")
    NS:FireCallback("DATA_UPDATED")

    if setName == "mount" then
        if applied then NS:Print("Mount gear equipped.") end
        Swap:StartSwappedTicker()
    else
        if applied then NS:Print("Base gear equipped.") end
    end
end

----------------------------------------------------------------------
-- Manual toggle: button, keybind, /ms swap
----------------------------------------------------------------------
function Swap:Toggle()
    if NS.charDb.isMountSwapped then
        Swap:Apply("base")
    else
        Swap:Apply("mount")
    end
end

----------------------------------------------------------------------
-- Polling ticker: while isMountSwapped, periodically verify the player
-- is still mounted or on a taxi. If not (flight arrival with lagged
-- events), force back to base.
----------------------------------------------------------------------
function Swap:StartSwappedTicker()
    if swappedTicker then return end
    swappedTicker = C_Timer.NewTicker(1.5, function(self)
        if not NS.charDb or not NS.charDb.isMountSwapped then
            self:Cancel()
            swappedTicker = nil
            return
        end
        if UnitOnTaxi("player") then return end
        if IsMounted() then return end

        self:Cancel()
        swappedTicker = nil
        Swap:Apply("base")
        wasMounted = false
    end)
end

----------------------------------------------------------------------
-- Auto-swap entry point on mount-state events
----------------------------------------------------------------------
function Swap:CheckMountState()
    if not NS.charDb or not NS.charDb.enabled then return end
    if UnitOnTaxi("player") then return end

    local mounted = IsMounted()

    -- Defensive: state says "mount" but we're not mounted (and not on taxi)
    if NS.charDb.isMountSwapped and not mounted then
        Swap:Apply("base")
        wasMounted = false
        return
    end

    if mounted and not wasMounted then
        Swap:Apply("mount")
    elseif not mounted and wasMounted then
        Swap:Apply("base")
    end
    wasMounted = mounted
end

----------------------------------------------------------------------
-- Login: initialise wasMounted, recover from stale swap state
----------------------------------------------------------------------
NS:RegisterCallback("PLAYER_LOGIN", function()
    wasMounted = IsMounted()

    if NS.charDb.isMountSwapped and not wasMounted then
        -- Logged out wearing mount gear, now unmounted: restore base
        Swap:Apply("base")
    elseif NS.charDb.isMountSwapped then
        -- Mid-flight or still mounted: arm the ticker
        Swap:StartSwappedTicker()
    end
end)

----------------------------------------------------------------------
-- Event frame
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_CONTROL_GAINED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_AURA" and arg1 == "player" then
        Swap:CheckMountState()
    elseif event == "PLAYER_CONTROL_GAINED" then
        Swap:CheckMountState()
    elseif event == "PLAYER_REGEN_ENABLED" and pendingApply then
        local target = pendingApply
        pendingApply = nil
        Swap:Apply(target)
    end
end)
