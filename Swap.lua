----------------------------------------------------------------------
-- MountSpeed  -  Swap.lua
-- Mount / dismount detection and equipment swap logic
----------------------------------------------------------------------
local _, NS = ...
local Swap = {}
NS.Swap = Swap

local wasMounted     = false
local pendingRestore = false

----------------------------------------------------------------------
-- Save current equipment for configured slots, then equip mount items
----------------------------------------------------------------------
function Swap:SaveAndEquip()
    local mountItems = NS.charDb.mountItems
    if not mountItems or not next(mountItems) then return end

    -- Guard: if we're already in the swapped state (e.g. aura flicker or
    -- fast dismount/remount while EquipItemByName is still pending),
    -- do NOT re-snapshot — that would capture our own mount-speed items
    -- as the "original gear" and corrupt savedEquipment.
    if NS.charDb.isMountSwapped then
        for slotId, itemId in pairs(mountItems) do
            local current = GetInventoryItemID("player", slotId)
            if current ~= itemId then
                EquipItemByName(itemId, slotId)
            end
        end
        return
    end

    -- Snapshot currently-worn items
    NS.charDb.savedEquipment = {}
    for slotId, _ in pairs(mountItems) do
        local equipped = GetInventoryItemID("player", slotId) or 0
        -- Defensive: if what's currently worn is already our own mount-speed
        -- item (manual pre-equip, or a previous restore that didn't finish),
        -- store 0 so Restore skips this slot instead of "restoring" the
        -- mount-speed item as the original.
        if equipped == mountItems[slotId] then
            NS.charDb.savedEquipment[slotId] = 0
        else
            NS.charDb.savedEquipment[slotId] = equipped
        end
    end

    -- Equip mount-speed items
    for slotId, itemId in pairs(mountItems) do
        local current = GetInventoryItemID("player", slotId)
        if current ~= itemId then
            EquipItemByName(itemId, slotId)
        end
    end

    NS.charDb.isMountSwapped = true
    NS:Print("Mount speed gear equipped.")
end

----------------------------------------------------------------------
-- Restore the gear that was worn before mounting
----------------------------------------------------------------------
function Swap:Restore()
    if InCombatLockdown() then
        pendingRestore = true
        NS:Print("In combat — gear will be restored when combat ends.")
        return
    end

    local saved = NS.charDb.savedEquipment
    if not saved or not next(saved) then return end

    for slotId, itemId in pairs(saved) do
        if itemId and itemId > 0 then
            local current = GetInventoryItemID("player", slotId)
            if current ~= itemId then
                EquipItemByName(itemId, slotId)
            end
        end
    end

    NS.charDb.savedEquipment = {}
    NS.charDb.isMountSwapped = false
    pendingRestore = false
    NS:Print("Original gear restored.")
end

----------------------------------------------------------------------
-- Compare mount state and react
----------------------------------------------------------------------
function Swap:CheckMountState()
    if not NS.charDb or not NS.charDb.enabled then return end

    local mounted = IsMounted()
    if mounted and not wasMounted then
        self:SaveAndEquip()
    elseif not mounted and wasMounted then
        self:Restore()
    end
    wasMounted = mounted
end

----------------------------------------------------------------------
-- Initialise wasMounted on login (handles login/reload while mounted)
----------------------------------------------------------------------
NS:RegisterCallback("PLAYER_LOGIN", function()
    wasMounted = IsMounted()

    -- Recover from a stale swap state (e.g. logout/crash while mounted,
    -- logged back in unmounted): restore the original gear so we don't
    -- stay stuck wearing mount-speed items with no event to trigger us.
    if NS.charDb.isMountSwapped and not wasMounted
       and NS.charDb.savedEquipment and next(NS.charDb.savedEquipment) then
        Swap:Restore()
    end
end)

----------------------------------------------------------------------
-- Event frame
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_AURA" and arg1 == "player" then
        Swap:CheckMountState()
    elseif event == "PLAYER_REGEN_ENABLED" and pendingRestore then
        Swap:Restore()
    end
end)
