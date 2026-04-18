# MountSpeed Equipment Swap — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically swap equipment when mounting/dismounting in WoW TBC Classic, with a configuration UI.

**Architecture:** 4 Lua modules (Core, Slots, Swap, UI) communicating via an internal event bus. No external dependencies. Per-character item config, account-wide window settings.

**Tech Stack:** Lua (WoW API 20505), pure WoW frame system, no libraries.

**Testing:** WoW addons have no unit test framework. Each task deploys to the WoW AddOns folder and lists in-game verification steps.

**Deploy target:** `C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\MountSpeed\`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Core.lua` | Modify | Update CHAR_DEFAULTS, reset popup, TOC notes |
| `Slots.lua` | Create | 5 slot constants, invType mapping, bag scanning |
| `Swap.lua` | Create | Mount detection via UNIT_AURA, save/restore with combat queue |
| `UI.lua` | Create | Config window, dropdown, drag&drop, minimap button |
| `MountSpeed.toc` | Modify | Add new files to load order, fix Notes |
| `package.sh` | Modify | Add new Lua files to build |
| `.github/workflows/build-addon.yml` | Modify | Add new Lua files |
| `.github/workflows/release.yml` | Modify | Add new Lua files |
| `README.md` | Modify | Update if needed after implementation |

---

### Task 1: Update Core.lua data model and TOC

**Files:**
- Modify: `Core.lua:11-20` (CHAR_DEFAULTS), `Core.lua:140-154` (reset popup)
- Modify: `MountSpeed.toc`

- [ ] **Step 1: Update CHAR_DEFAULTS in Core.lua**

Replace lines 18-20:

```lua
local CHAR_DEFAULTS = {
    ui = {},
}
```

With:

```lua
local CHAR_DEFAULTS = {
    enabled = true,
    mountItems = {},
    savedEquipment = {},
    isMountSwapped = false,
}
```

- [ ] **Step 2: Update reset popup to also reset per-character data**

Replace the OnAccept function in the `MOUNTSPEED_RESET_ALL` popup (line 144):

```lua
OnAccept = function()
    MountSpeedDB = DeepCopy(DEFAULTS)
    NS.db = MountSpeedDB
    NS:FireCallback("DATA_UPDATED")
    NS:Print("All data has been reset.")
end,
```

With:

```lua
OnAccept = function()
    local pos = NS.db and NS.db.settings.minimapPos or 215
    MountSpeedDB = DeepCopy(DEFAULTS)
    MountSpeedDB.settings.minimapPos = pos
    MountSpeedCharDB = DeepCopy(CHAR_DEFAULTS)
    NS.db = MountSpeedDB
    NS.charDb = MountSpeedCharDB
    NS:FireCallback("DATA_UPDATED")
    NS:Print("All data has been reset.")
end,
```

- [ ] **Step 3: Update MountSpeed.toc**

Replace full contents with:

```toc
## Interface: 20505
## Title: MountSpeed
## Notes: Auto-swap equipment when mounting for speed bonuses
## Author: PIECQ Grégory
## Version: 0.1.0
## SavedVariables: MountSpeedDB
## SavedVariablesPerCharacter: MountSpeedCharDB

Core.lua
Slots.lua
Swap.lua
UI.lua
```

- [ ] **Step 4: Deploy and verify**

```bash
mkdir -p "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed"
cp MountSpeed.toc Core.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In-game: `/reload` then `/ms` — should print help text without errors. The addon loads but Slots.lua/Swap.lua/UI.lua don't exist yet (WoW silently skips missing files listed in TOC).

- [ ] **Step 5: Commit**

```bash
git add Core.lua MountSpeed.toc
git commit -m "Update data model for per-character mount items and fix TOC"
```

---

### Task 2: Create Slots.lua

**Files:**
- Create: `Slots.lua`

- [ ] **Step 1: Create Slots.lua with slot constants, invType mapping, and bag scanning**

```lua
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
```

- [ ] **Step 2: Deploy and verify**

```bash
cp Slots.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In-game: `/reload` — no errors. Run `/script MountSpeed_NS = select(2, ...); print(#MountSpeedSlots)` won't work from chat, but the absence of Lua errors in the chat confirms the file loaded.

- [ ] **Step 3: Commit**

```bash
git add Slots.lua
git commit -m "Add Slots module with 5 mount speed slots and bag scanning"
```

---

### Task 3: Create Swap.lua

**Files:**
- Create: `Swap.lua`

- [ ] **Step 1: Create Swap.lua with mount detection and equipment swap logic**

```lua
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
```

- [ ] **Step 2: Deploy and verify**

```bash
cp Swap.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In-game: `/reload` — no Lua errors. Mount up — nothing happens yet (no items configured). Dismount — no errors. The swap logic is wired but idle until UI lets the user configure items.

- [ ] **Step 3: Commit**

```bash
git add Swap.lua
git commit -m "Add Swap module with mount detection and combat-safe restore"
```

---

### Task 4: Create UI.lua

**Files:**
- Create: `UI.lua`

- [ ] **Step 1: Create UI.lua with config window, slot rows, dropdown, drag&drop, and minimap button**

```lua
----------------------------------------------------------------------
-- MountSpeed  -  UI.lua
-- Configuration window, item selection, minimap button
----------------------------------------------------------------------
local _, NS = ...

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
local BACKDROP = {
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local ROW_HEIGHT    = 32
local WINDOW_WIDTH  = 350
local WINDOW_HEIGHT = 100 + (#NS.Slots.ORDER * ROW_HEIGHT) -- header + rows

----------------------------------------------------------------------
-- Forward declarations
----------------------------------------------------------------------
local mainFrame, enableCB, rows, dropdown
local activeSlotId
local positionApplied = false
rows = {}

----------------------------------------------------------------------
-- Refresh all 5 slot rows from saved data
----------------------------------------------------------------------
local function RefreshRows()
    if not mainFrame or not mainFrame:IsShown() then return end
    for _, row in ipairs(rows) do
        local itemId = NS.charDb.mountItems[row.slotId]
        if itemId then
            local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(itemId)
            row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.itemText:SetText(name or "Loading...")
            if quality and ITEM_QUALITY_COLORS[quality] then
                local c = ITEM_QUALITY_COLORS[quality]
                row.itemText:SetTextColor(c.r, c.g, c.b)
            else
                row.itemText:SetTextColor(1, 1, 1)
            end
            row.setBtn:Hide()
            row.clearBtn:Show()
        else
            row.icon:SetTexture(nil)
            row.itemText:SetText("--")
            row.itemText:SetTextColor(0.5, 0.5, 0.5)
            row.setBtn:Show()
            row.clearBtn:Hide()
        end
    end
    if enableCB then
        enableCB:SetChecked(NS.charDb.enabled)
    end
end

----------------------------------------------------------------------
-- Lazy-create the main config window (called once)
----------------------------------------------------------------------
local function CreateMainFrame()
    if mainFrame then return end

    ----------------------------------------------------------------
    -- Shared dropdown (one instance, re-initialised per slot click)
    ----------------------------------------------------------------
    dropdown = CreateFrame("Frame", "MountSpeedItemDropdown", UIParent,
                           "UIDropDownMenuTemplate")

    UIDropDownMenu_Initialize(dropdown, function()
        if not activeSlotId then return end
        local items = NS.Slots:ScanBagsForSlot(activeSlotId)
        if #items == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "No items found in bags"
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)
        else
            for _, item in ipairs(items) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = item.name
                info.icon = item.icon
                info.notCheckable = true
                if item.quality and ITEM_QUALITY_COLORS[item.quality] then
                    local c = ITEM_QUALITY_COLORS[item.quality]
                    info.colorCode =
                        format("|cff%02x%02x%02x",
                               c.r * 255, c.g * 255, c.b * 255)
                end
                info.func = function()
                    NS.charDb.mountItems[activeSlotId] = item.itemId
                    NS:FireCallback("DATA_UPDATED")
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end, "MENU")

    ----------------------------------------------------------------
    -- Main window
    ----------------------------------------------------------------
    mainFrame = CreateFrame("Frame", "MountSpeedMainFrame", UIParent,
                            "BackdropTemplate")
    mainFrame:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetBackdrop(BACKDROP)
    mainFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.92)
    mainFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:Hide()
    tinsert(UISpecialFrames, "MountSpeedMainFrame")

    -- Title bar (drag region)
    local titleBar = CreateFrame("Frame", nil, mainFrame)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(28)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        mainFrame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        mainFrame:StopMovingOrSizing()
        local point, _, _, x, y = mainFrame:GetPoint()
        NS.db.settings.windowPos =
            { point = point, x = x, y = y }
    end)

    local title = titleBar:CreateFontString(nil, "OVERLAY",
                                            "GameFontNormalLarge")
    title:SetPoint("LEFT", 12, 0)
    title:SetText("MountSpeed")
    title:SetTextColor(0, 0.8, 1)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, mainFrame,
                                 "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Enable checkbox
    enableCB = CreateFrame("CheckButton", "MountSpeedEnableCB", mainFrame,
                           "UICheckButtonTemplate")
    enableCB:SetPoint("TOPLEFT", 12, -32)
    enableCB:SetChecked(NS.charDb.enabled)
    _G["MountSpeedEnableCBText"]:SetText("Enable auto-swap")
    _G["MountSpeedEnableCBText"]:SetTextColor(1, 1, 1)
    enableCB:SetScript("OnClick", function(self)
        NS.charDb.enabled = self:GetChecked() and true or false
    end)

    -- Section header
    local header = mainFrame:CreateFontString(nil, "OVERLAY",
                                              "GameFontNormal")
    header:SetPoint("TOPLEFT", 14, -58)
    header:SetText("Equipment to swap when mounted:")
    header:SetTextColor(0.8, 0.8, 0.8)

    ----------------------------------------------------------------
    -- Slot rows (5 fixed rows, no scroll)
    ----------------------------------------------------------------
    local contentWidth = WINDOW_WIDTH - 24 -- left + right padding
    for i, slotInfo in ipairs(NS.Slots.ORDER) do
        local row = CreateFrame("Frame", nil, mainFrame)
        row:SetSize(contentWidth, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 12, -(72 + (i - 1) * ROW_HEIGHT))
        row.slotId = slotInfo.id

        -- Alternating row background
        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.03)
        end

        -- Item icon (24x24)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 4, 0)
        row.icon = icon

        -- Slot name label
        local slotLabel = row:CreateFontString(nil, "OVERLAY",
                                               "GameFontNormalSmall")
        slotLabel:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        slotLabel:SetWidth(70)
        slotLabel:SetJustifyH("LEFT")
        slotLabel:SetText(slotInfo.name)
        slotLabel:SetTextColor(0.7, 0.7, 0.7)

        -- Item name
        local itemText = row:CreateFontString(nil, "OVERLAY",
                                              "GameFontHighlightSmall")
        itemText:SetPoint("LEFT", slotLabel, "RIGHT", 4, 0)
        itemText:SetPoint("RIGHT", row, "RIGHT", -64, 0)
        itemText:SetJustifyH("LEFT")
        itemText:SetText("--")
        itemText:SetTextColor(0.5, 0.5, 0.5)
        row.itemText = itemText

        -- "Set" button (visible when slot is empty)
        local setBtn = CreateFrame("Button", nil, row,
                                   "UIPanelButtonTemplate")
        setBtn:SetSize(55, 22)
        setBtn:SetPoint("RIGHT", -4, 0)
        setBtn:SetText("Set")
        setBtn:SetScript("OnClick", function(self)
            activeSlotId = slotInfo.id
            ToggleDropDownMenu(1, nil, dropdown, self, 0, 0)
        end)
        row.setBtn = setBtn

        -- "Clear" button (visible when slot has an item)
        local clearBtn = CreateFrame("Button", nil, row,
                                     "UIPanelButtonTemplate")
        clearBtn:SetSize(55, 22)
        clearBtn:SetPoint("RIGHT", -4, 0)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            NS.charDb.mountItems[slotInfo.id] = nil
            NS:FireCallback("DATA_UPDATED")
        end)
        clearBtn:Hide()
        row.clearBtn = clearBtn

        -- Tooltip on hover
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local itemId = NS.charDb.mountItems[self.slotId]
            if itemId then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local _, link = GetItemInfo(itemId)
                if link then
                    GameTooltip:SetHyperlink(link)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Drag & drop: accept items from bags
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnReceiveDrag", function(self)
            local infoType, itemId, itemLink = GetCursorInfo()
            if infoType == "item" and itemId then
                local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemId)
                if equipLoc and
                   NS.Slots:FitsSlot(equipLoc, self.slotId) then
                    NS.charDb.mountItems[self.slotId] = itemId
                    NS:FireCallback("DATA_UPDATED")
                    ClearCursor()
                else
                    NS:Print("This item cannot go in the "
                             .. (NS.Slots.byId[self.slotId].name or "")
                             .. " slot.")
                end
            end
        end)
        row:SetScript("OnMouseUp", function(self)
            -- Also handle click-to-place (item on cursor)
            local infoType, itemId = GetCursorInfo()
            if infoType == "item" and itemId then
                local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemId)
                if equipLoc and
                   NS.Slots:FitsSlot(equipLoc, self.slotId) then
                    NS.charDb.mountItems[self.slotId] = itemId
                    NS:FireCallback("DATA_UPDATED")
                    ClearCursor()
                end
            end
        end)

        rows[#rows + 1] = row
    end

    ----------------------------------------------------------------
    -- Apply saved window position (once)
    ----------------------------------------------------------------
    if NS.db.settings.windowPos then
        local pos = NS.db.settings.windowPos
        mainFrame:ClearAllPoints()
        mainFrame:SetPoint(pos.point or "CENTER", UIParent,
                           pos.point or "CENTER",
                           pos.x or 0, pos.y or 0)
    end
end

----------------------------------------------------------------------
-- Minimap button
----------------------------------------------------------------------
local minimapBtn

local function UpdateMinimapPosition(angle)
    local rad = math.rad(angle or 215)
    minimapBtn:ClearAllPoints()
    minimapBtn:SetPoint("CENTER", Minimap, "CENTER",
                        math.cos(rad) * 80, math.sin(rad) * 80)
end

local function CreateMinimapButton()
    if minimapBtn then return end

    minimapBtn = CreateFrame("Button", "MountSpeedMinimapBtn", Minimap)
    minimapBtn:SetSize(32, 32)
    minimapBtn:SetFrameStrata("MEDIUM")
    minimapBtn:SetFrameLevel(8)
    minimapBtn:EnableMouse(true)
    minimapBtn:SetMovable(true)
    minimapBtn:RegisterForDrag("LeftButton")
    minimapBtn:RegisterForClicks("LeftButtonUp")
    minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Icon
    local icon = minimapBtn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Staff_07")

    -- Border overlay
    local border = minimapBtn:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("CENTER")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    -- Background
    local bg = minimapBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- Click handler
    minimapBtn:SetScript("OnClick", function()
        NS:FireCallback("TOGGLE_WINDOW")
    end)

    -- Tooltip
    minimapBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("MountSpeed")
        GameTooltip:AddLine("Left-click to toggle config", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    minimapBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Drag to reposition around minimap edge
    minimapBtn:SetScript("OnDragStart", function(self)
        self:StartMoving()
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local bx, by = self:GetCenter()
            local angle = math.deg(math.atan2(by - my, bx - mx))
            UpdateMinimapPosition(angle)
        end)
    end)
    minimapBtn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self:SetScript("OnUpdate", nil)
        local mx, my = Minimap:GetCenter()
        local bx, by = self:GetCenter()
        NS.db.settings.minimapPos =
            math.deg(math.atan2(by - my, bx - mx))
        UpdateMinimapPosition(NS.db.settings.minimapPos)
    end)

    UpdateMinimapPosition(NS.db.settings.minimapPos)
end

----------------------------------------------------------------------
-- Callbacks
----------------------------------------------------------------------
NS:RegisterCallback("ADDON_LOADED", function()
    CreateMinimapButton()
end)

NS:RegisterCallback("TOGGLE_WINDOW", function()
    CreateMainFrame()
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        RefreshRows()
    end
end)

NS:RegisterCallback("HIDE_WINDOW", function()
    if mainFrame then mainFrame:Hide() end
end)

NS:RegisterCallback("SHOW_SETTINGS", function()
    CreateMainFrame()
    mainFrame:Show()
    RefreshRows()
end)

NS:RegisterCallback("DATA_UPDATED", function()
    RefreshRows()
end)
```

- [ ] **Step 2: Deploy and verify**

```bash
cp UI.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In-game verification:
1. `/reload` — no Lua errors
2. Minimap: carrot icon visible, draggable around the edge
3. Click minimap button or `/ms` — config window opens
4. Enable checkbox works (toggles on/off)
5. Click "Set" on a slot — dropdown shows items from bags for that slot
6. Select an item — icon/name appear, button changes to "Clear"
7. Hover over configured item — tooltip appears
8. Drag an item from bags onto a slot row — item is configured
9. Click "Clear" — slot returns to empty
10. Escape closes the window
11. Window position persists after drag + `/reload`

- [ ] **Step 3: Commit**

```bash
git add UI.lua
git commit -m "Add UI with config window, dropdown, drag&drop, and minimap button"
```

---

### Task 5: Update build files

**Files:**
- Modify: `package.sh:23-24`
- Modify: `.github/workflows/build-addon.yml:25-26`
- Modify: `.github/workflows/release.yml:42-43`

- [ ] **Step 1: Update package.sh**

Replace the cp block (lines 23-24):

```bash
cp "$TOC_FILE" \
   Core.lua \
   "build/$ADDON_NAME/"
```

With:

```bash
cp "$TOC_FILE" \
   Core.lua \
   Slots.lua \
   Swap.lua \
   UI.lua \
   "build/$ADDON_NAME/"
```

- [ ] **Step 2: Update build-addon.yml**

Replace the cp block in the "Prepare addon folder" step:

```yaml
          cp MountSpeed.toc \
             Core.lua \
             "build/$ADDON_NAME/"
```

With:

```yaml
          cp MountSpeed.toc \
             Core.lua \
             Slots.lua \
             Swap.lua \
             UI.lua \
             "build/$ADDON_NAME/"
```

- [ ] **Step 3: Update release.yml**

Replace the cp block in the "Build zip" step:

```yaml
          cp MountSpeed.toc \
             Core.lua \
             "/tmp/addon-build/$ADDON_NAME/"
```

With:

```yaml
          cp MountSpeed.toc \
             Core.lua \
             Slots.lua \
             Swap.lua \
             UI.lua \
             "/tmp/addon-build/$ADDON_NAME/"
```

- [ ] **Step 4: Commit**

```bash
git add package.sh .github/workflows/build-addon.yml .github/workflows/release.yml
git commit -m "Add new Lua modules to build and CI workflows"
```

---

### Task 6: Full deploy and end-to-end test

**Files:**
- Modify: `README.md` (update if needed)

- [ ] **Step 1: Deploy all files to WoW**

```bash
cp MountSpeed.toc Core.lua Slots.lua Swap.lua UI.lua \
   "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

- [ ] **Step 2: End-to-end in-game test**

Full test checklist:
1. `/reload` — addon loads without errors
2. `/ms` — config window opens
3. Configure a trinket via "Set" dropdown
4. Configure boots via drag & drop from bags
5. Close window (Escape)
6. Mount up — chat shows "Mount speed gear equipped.", configured items are now worn
7. Inspect character panel — mount speed items in the correct slots
8. Dismount — chat shows "Original gear restored.", original items are back
9. Mount in a zone with mobs, get hit to dismount in combat — chat shows combat message
10. Leave combat — gear automatically restores
11. `/ms reset` — confirm popup, all config cleared
12. `/reload` — minimap button position preserved

- [ ] **Step 3: Update README.md if needed**

Verify the README accurately describes the current feature set. Update if any details changed during implementation.

- [ ] **Step 4: Final commit**

```bash
git add README.md
git commit -m "Update README for mount speed equipment swap feature"
```
