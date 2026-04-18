----------------------------------------------------------------------
-- MountSpeed  -  Slots.lua
-- Equipment slot definitions and bag-scanning helpers
----------------------------------------------------------------------
local _, NS = ...
local Slots = {}
NS.Slots = Slots

----------------------------------------------------------------------
-- The 5 configurable mount-speed slots (display order)
----------------------------------------------------------------------
Slots.ORDER = {
    { id = 13, name = "Trinket 1" },
    { id = 14, name = "Trinket 2" },
    { id = 8,  name = "Feet" },
    { id = 10, name = "Hands" },
    { id = 15, name = "Back" },
}

-- Quick lookup by slot id
Slots.byId = {}
for _, s in ipairs(Slots.ORDER) do
    Slots.byId[s.id] = s
end

----------------------------------------------------------------------
-- invType → valid slot IDs (only the 5 we care about)
----------------------------------------------------------------------
local INVTYPE_TO_SLOTS = {
    INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_FEET    = { 8 },
    INVTYPE_HAND    = { 10 },
    INVTYPE_CLOAK   = { 15 },
}

----------------------------------------------------------------------
-- Check whether an equipLoc string is valid for a given slot id
----------------------------------------------------------------------
function Slots:FitsSlot(equipLoc, targetSlotId)
    local valid = INVTYPE_TO_SLOTS[equipLoc]
    if not valid then return false end
    for _, id in ipairs(valid) do
        if id == targetSlotId then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Info about the item currently in an equipment slot
-- Returns { itemId, name, icon, quality } or nil
----------------------------------------------------------------------
function Slots:GetEquippedItem(slotId)
    local itemId = GetInventoryItemID("player", slotId)
    if not itemId then return nil end
    local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(itemId)
    return {
        itemId  = itemId,
        name    = name or ("Item #" .. itemId),
        link    = link,
        icon    = icon,
        quality = quality or 1,
    }
end

----------------------------------------------------------------------
-- Scan bags 0-4 for items equippable in targetSlotId
-- Returns sorted list of { itemId, name, icon, quality, link }
----------------------------------------------------------------------
function Slots:ScanBagsForSlot(targetSlotId)
    local items = {}
    local seen  = {}

    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local itemId = tonumber(link:match("item:(%d+)"))
                if itemId and not seen[itemId] then
                    local name, _, quality, _, _, _, _, _, equipLoc, icon =
                        GetItemInfo(link)
                    if equipLoc and self:FitsSlot(equipLoc, targetSlotId) then
                        seen[itemId] = true
                        items[#items + 1] = {
                            itemId  = itemId,
                            name    = name or ("Item #" .. itemId),
                            icon    = icon,
                            quality = quality or 1,
                            link    = link,
                        }
                    end
                end
            end
        end
    end

    table.sort(items, function(a, b) return a.name < b.name end)
    return items
end
