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

    -- Snapshot currently-worn items
    NS.charDb.savedEquipment = {}
    for slotId, _ in pairs(mountItems) do
        NS.charDb.savedEquipment[slotId] =
            GetInventoryItemID("player", slotId) or 0
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
