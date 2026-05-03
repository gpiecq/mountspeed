# Base Equipment Swap (v2.0.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the buggy snapshot-at-mount approach with two user-configured equipment sets (mount + base) and add a floating swap button + keybind for manual toggling.

**Architecture:** Per-character SavedVariables holds two equipment sets keyed by slot id. A unified `Swap:Apply(setName)` function equips a given set; `Swap:Toggle()` switches between mount/base. Auto-swap on mount/dismount remains, but reads `sets.base` instead of snapshotting. The UI gains a second column per slot row plus a "Capture current gear" helper. A floating draggable button and a keybind both call `Swap:Toggle()`.

**Tech Stack:** WoW Classic Anniversary (Interface 20505) Lua 5.1 addon. No test framework — validation is via in-game `/reload` and manual exercise.

**Deploy target (per user memory):** `C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\MountSpeed\` — copy `*.lua` and `MountSpeed.toc` after each task before reloading.

**Spec:** `docs/superpowers/specs/2026-05-02-base-equipment-swap-design.md`

---

## File Structure

| File | Role | Touched in Task |
|---|---|---|
| `Core.lua` | Init, SavedVariables schema, migration, slash commands, version | 1, 2, 4, 7, 8, 9 |
| `Slots.lua` | Slot definitions, bag scanning | (no change) |
| `Swap.lua` | Equipment apply/toggle, mount-state tracking, combat queue | 2 |
| `UI.lua` | Config window, capture button, floating swap button, keybind | 2, 3, 4, 5, 6 |
| `Bindings.xml` | Keybind declaration (loaded by .toc) | 6 (created) |
| `MountSpeed.toc` | Addon manifest | 6, 9 |
| `package.sh` | Release zip builder | 6 |
| `README.md` | User docs | 9 |

---

## Task 1: Schema migration + new SavedVariables defaults

**Files:**
- Modify: `Core.lua` (DEFAULTS, CHAR_DEFAULTS, ADDON_LOADED handler, reset popup)

- [ ] **Step 1: Update DEFAULTS to add swapButtonPos**

In `Core.lua`, replace the `DEFAULTS` table (currently around lines 11-16):

```lua
local DEFAULTS = {
    settings = {
        windowPos     = { point = "CENTER", x = 0, y = 0 },
        minimapPos    = 215,
        swapButtonPos = { point = "CENTER", x = 0, y = -100 },
    },
}
```

- [ ] **Step 2: Update CHAR_DEFAULTS to new schema**

Replace `CHAR_DEFAULTS` (currently around lines 18-23):

```lua
local CHAR_DEFAULTS = {
    enabled = true,
    sets = {
        mount = {},
        base  = {},
    },
    isMountSwapped         = false,
    migrationNoticeShown   = false,
}
```

- [ ] **Step 3: Add migration block to ADDON_LOADED handler**

In `Core.lua`, inside the `frame:SetScript("OnEvent", ...)` block, after `MergeDefaults(MountSpeedCharDB, CHAR_DEFAULTS)` and before the `MountSpeedCharDB.debugLog = nil` lines, insert the migration:

```lua
        -- Migrate from v1.x schema. We ALIAS sets.mount to the same table as
        -- mountItems so v1.x UI code (which still reads
        -- MountSpeedCharDB.mountItems) keeps working through Tasks 1-2. Task 3
        -- converts the UI to read sets.* directly and finalises this migration
        -- by replacing the alias with a deep copy + dropping mountItems.
        if MountSpeedCharDB.mountItems then
            MountSpeedCharDB.sets = MountSpeedCharDB.sets or { mount = {}, base = {} }
            MountSpeedCharDB.sets.mount = MountSpeedCharDB.mountItems
            -- migrationNoticeShown stays false → user gets the one-time message
        end
        MountSpeedCharDB.savedEquipment = nil  -- obsolete in v2.0
```

- [ ] **Step 4: Update reset popup to clear new schema**

The `MOUNTSPEED_RESET_ALL` static popup already deep-copies `CHAR_DEFAULTS` so it picks up the new shape automatically. No code change needed — verify the existing block (around lines 156-174) works as-is after the CHAR_DEFAULTS rewrite above.

- [ ] **Step 5: Deploy and reload**

```bash
cp Core.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In game: `/reload`

- [ ] **Step 6: Verify migration**

In game: `/dump MountSpeedCharDB`

Expected: `sets.mount` contains the items previously in `mountItems`. `mountItems` ALSO still exists (alias of `sets.mount` — the same table reference; Task 3 will drop it). `savedEquipment` is `nil`. `sets.base` is an empty table. `migrationNoticeShown` is `false`.

If you have a fresh character with no prior data, expected: empty `sets.mount`, empty `sets.base`, no migration triggered.

Quick alias sanity check: `/run MountSpeedCharDB.mountItems[13] = 99999` then `/dump MountSpeedCharDB.sets.mount[13]` — expected: `99999` (proves they share the same table). Reset with `/run MountSpeedCharDB.mountItems[13] = nil`.

- [ ] **Step 7: Commit**

```bash
git add Core.lua
git commit -m "v2.0 schema: add sets.{mount,base}, migrate from mountItems"
```

---

## Task 2: Rewrite Swap.lua with Apply/Toggle

**Files:**
- Modify: `Swap.lua` (full rewrite — drop ~100 lines of snapshot/watchdog machinery)

- [ ] **Step 1: Replace Swap.lua with new architecture**

Overwrite the entire `Swap.lua` with:

```lua
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
```

- [ ] **Step 2: Deploy and reload**

```bash
cp Swap.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In game: `/reload`

- [ ] **Step 3: Verify Swap.lua loads cleanly**

In game: `/dump NS.Swap.Apply` — expected: returns a function reference.
In game: `/dump NS.Swap.Toggle` — expected: returns a function reference.

No Lua errors should appear in chat or BugSack. (Note: the v1.x `/ms restore` slash command and minimap right-click handler don't exist in the 1.0.1 baseline — there's nothing to update; the new `/ms swap` is added in Task 7.)

- [ ] **Step 4: Verify behavior — note: no auto-swap yet because sets.base is empty**

The UI still uses the v1.x schema (rewritten in Task 3) but reads/writes through the `mountItems` alias which points at the same table as `sets.mount`. Both names refer to the same data.

In game: configure mount gear via the existing UI dropdown for at least one slot (e.g. Trinket 1). Mount up. Expected: NOTHING equips because the eligibility rule requires `sets.base` to also be filled. This is correct per spec — the migration UX message in Task 8 will guide the user.

Manually populate base in game: `/run MountSpeedCharDB.sets.base[13] = <some_trinket_itemId>` (use a trinket item id from your bags that fits Trinket 1; check your bags via mouseover or `/dump GetContainerItemLink(0, 1)` etc.). Mount up — expected: Trinket 1 swaps to the mount item. Dismount — expected: it swaps back to the base item. Watch for chat lines "Mount gear equipped." / "Base gear equipped."

- [ ] **Step 5: Commit**

```bash
git add Swap.lua
git commit -m "Swap.lua: unified Apply/Toggle, drop snapshot machinery"
```

---

## Task 3: UI dual-column rows + SRA-style item picker

**Files:**
- Modify: `UI.lua` (style helpers, item picker window, RefreshRows, CreateMainFrame row construction, window width)
- Modify: `Core.lua` (finalise migration)

The Blizzard `UIDropDownMenu` used in v1.x is replaced by a custom dark window styled to match SimpleRaidAssign (cyan accent on near-black background, scrollable item list, anchored at cursor). The drag-and-drop receivers on each item zone are kept as a fast-path alternative.

- [ ] **Step 1: Add SRA-style helpers at top of UI.lua**

In `UI.lua`, immediately after `local _, NS = ...` (line 5), insert the style block:

```lua
----------------------------------------------------------------------
-- Style (matches SimpleRaidAssign palette for visual coherence)
----------------------------------------------------------------------
local COLOURS = {
    bg        = { 0.08, 0.08, 0.10, 0.95 },
    panel     = { 0.12, 0.12, 0.14, 0.96 },
    border    = { 0.30, 0.30, 0.34, 1    },
    accent    = { 0.00, 0.80, 1.00, 1    },
    text      = { 1, 1, 1, 1 },
    dim       = { 0.65, 0.65, 0.70, 1 },
    rowAlt    = { 1, 1, 1, 0.04 },
    rowHover  = { 1, 1, 1, 0.10 },
}

local function SkinFrame(f)
    if not f.SetBackdrop and BackdropTemplateMixin then
        Mixin(f, BackdropTemplateMixin)
    end
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        f:SetBackdropColor(unpack(COLOURS.bg))
        f:SetBackdropBorderColor(unpack(COLOURS.border))
    end
end

local function FS(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 12, "OUTLINE")
    fs:SetTextColor(unpack(COLOURS.text))
    return fs
end
```

- [ ] **Step 2: Update window width constant**

In `UI.lua`, find:

```lua
local WINDOW_WIDTH  = 350
```

Replace with:

```lua
local WINDOW_WIDTH  = 520
```

- [ ] **Step 3: Update forward declarations**

In `UI.lua`, find the forward declarations:

```lua
local mainFrame, enableCB, rows, dropdown
local activeSlotId
local positionApplied = false
rows = {}
```

Replace with:

```lua
local mainFrame, enableCB, rows, itemPicker
local activeSlotId, activeSetName
local positionApplied = false
rows = {}

-- Forward decl so CreateMainFrame can call it
local OpenItemPicker
```

- [ ] **Step 4: Remove the v1.x UIDropDownMenu setup and add the SRA-style item picker**

In `UI.lua`, find inside `CreateMainFrame` the entire "Shared dropdown" block (the comment header plus the `dropdown = CreateFrame(...)` call and the entire `UIDropDownMenu_Initialize(...)` call that follows). It looks like this:

```lua
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
```

DELETE that entire block (it spans from the `--- Shared dropdown ---` banner through the closing `, "MENU")` line — roughly 30 lines).

Then, OUTSIDE `CreateMainFrame` (above it, near the top of the file just after the style helpers from Step 1), add the SRA-style item picker:

```lua
----------------------------------------------------------------------
-- SRA-style item picker window (custom dark frame, scrollable rows)
-- One instance, reused across opens. Anchored at the cursor.
----------------------------------------------------------------------
local PICKER_WIDTH       = 280
local PICKER_HEIGHT      = 240
local PICKER_ROW_HEIGHT  = 22
local PICKER_VISIBLE_ROWS = 9

local function CreateItemPicker()
    if itemPicker then return itemPicker end

    local f = CreateFrame("Frame", "MountSpeedItemPicker", UIParent,
                          BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(PICKER_WIDTH, PICKER_HEIGHT)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    SkinFrame(f)
    tinsert(UISpecialFrames, "MountSpeedItemPicker")

    -- Title bar (drag region)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(24)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local title = FS(titleBar, 13)
    title:SetPoint("LEFT", 10, 0)
    title:SetTextColor(unpack(COLOURS.accent))
    f.title = title

    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", 2, 2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Scroll frame containing the rows
    local scroll = CreateFrame("ScrollFrame", "MountSpeedItemPickerScroll", f,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 8, -28)
    scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    f.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(PICKER_WIDTH - 36, PICKER_HEIGHT - 36)
    scroll:SetScrollChild(content)
    f.content = content

    f.rows = {}

    itemPicker = f
    return f
end

----------------------------------------------------------------------
-- Build / refresh picker rows for the current activeSlotId / activeSetName
----------------------------------------------------------------------
local function RefreshPickerRows()
    local f = itemPicker
    if not f or not activeSlotId or not activeSetName then return end

    local items = NS.Slots:ScanBagsForSlot(activeSlotId)

    -- Hide all prior rows; we'll re-show / re-create as needed
    for _, row in ipairs(f.rows) do row:Hide() end

    if #items == 0 then
        if not f.emptyText then
            f.emptyText = FS(f.content, 12)
            f.emptyText:SetPoint("CENTER")
            f.emptyText:SetTextColor(unpack(COLOURS.dim))
            f.emptyText:SetText("No matching items in your bags.")
        end
        f.emptyText:Show()
        f.content:SetHeight(60)
        return
    end
    if f.emptyText then f.emptyText:Hide() end

    for i, item in ipairs(items) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Button", nil, f.content)
            row:SetHeight(PICKER_ROW_HEIGHT)
            row:SetPoint("LEFT", f.content, "LEFT", 0, 0)
            row:SetPoint("RIGHT", f.content, "RIGHT", 0, 0)

            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            row.bg = bg

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(18, 18)
            icon:SetPoint("LEFT", 4, 0)
            row.icon = icon

            local name = FS(row, 12)
            name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
            name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            name:SetJustifyH("LEFT")
            row.name = name

            row:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(unpack(COLOURS.rowHover))
                if self.itemId then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local _, link = GetItemInfo(self.itemId)
                    if link then GameTooltip:SetHyperlink(link) end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function(self)
                if self.alt then
                    self.bg:SetColorTexture(unpack(COLOURS.rowAlt))
                else
                    self.bg:SetColorTexture(0, 0, 0, 0)
                end
                GameTooltip:Hide()
            end)
            row:SetScript("OnClick", function(self)
                NS.charDb.sets[activeSetName][activeSlotId] = self.itemId
                NS:FireCallback("DATA_UPDATED")
                f:Hide()
            end)

            f.rows[i] = row
        end

        row:SetPoint("TOP", f.content, "TOP", 0, -((i - 1) * PICKER_ROW_HEIGHT))
        row.itemId = item.itemId
        row.alt    = (i % 2 == 0)
        row.icon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        local color = ITEM_QUALITY_COLORS[item.quality or 1] or { r = 1, g = 1, b = 1 }
        row.name:SetText(item.name)
        row.name:SetTextColor(color.r, color.g, color.b)

        if row.alt then
            row.bg:SetColorTexture(unpack(COLOURS.rowAlt))
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        row:Show()
    end

    f.content:SetHeight(#items * PICKER_ROW_HEIGHT)
end

----------------------------------------------------------------------
-- Open the picker for a given slot/set, anchored at the cursor
----------------------------------------------------------------------
function OpenItemPicker(slotId, setName)
    activeSlotId  = slotId
    activeSetName = setName

    local f = CreateItemPicker()
    local slotName = (NS.Slots.byId[slotId] and NS.Slots.byId[slotId].name) or "?"
    local setLabel = (setName == "mount") and "Mount" or "Base"
    f.title:SetText(("Select %s item — %s"):format(setLabel, slotName))

    RefreshPickerRows()

    -- Anchor at cursor (clamped to screen by SetClampedToScreen)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale + 8, y / scale - 8)
    f:Show()
    f:Raise()
end
```

- [ ] **Step 5: Rewrite RefreshRows for two zones**

Replace the entire `RefreshRows` function (currently around lines 32-59) with:

```lua
local function RefreshZone(zone, itemId)
    if itemId then
        local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(itemId)
        zone.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        zone.itemText:SetText(name or "Loading...")
        if quality and ITEM_QUALITY_COLORS[quality] then
            local c = ITEM_QUALITY_COLORS[quality]
            zone.itemText:SetTextColor(c.r, c.g, c.b)
        else
            zone.itemText:SetTextColor(1, 1, 1)
        end
        zone.setBtn:Hide()
        zone.clearBtn:Show()
    else
        zone.icon:SetTexture(nil)
        zone.itemText:SetText("--")
        zone.itemText:SetTextColor(0.5, 0.5, 0.5)
        zone.setBtn:Show()
        zone.clearBtn:Hide()
    end
end

local function RefreshRows()
    if not mainFrame or not mainFrame:IsShown() then return end
    for _, row in ipairs(rows) do
        RefreshZone(row.mountZone, NS.charDb.sets.mount[row.slotId])
        RefreshZone(row.baseZone,  NS.charDb.sets.base[row.slotId])
    end
    if enableCB then
        enableCB:SetChecked(NS.charDb.enabled)
    end
end
```

- [ ] **Step 6: Update header text and add column labels**

Find the section header (around lines 161-166):

```lua
    -- Section header
    local header = mainFrame:CreateFontString(nil, "OVERLAY",
                                              "GameFontNormal")
    header:SetPoint("TOPLEFT", 14, -58)
    header:SetText("Equipment to swap when mounted:")
    header:SetTextColor(0.8, 0.8, 0.8)
```

Replace with:

```lua
    -- Section header
    local header = mainFrame:CreateFontString(nil, "OVERLAY",
                                              "GameFontNormal")
    header:SetPoint("TOPLEFT", 14, -58)
    header:SetText("Equipment to swap when mounted:")
    header:SetTextColor(0.8, 0.8, 0.8)

    -- Column labels for the two zones
    local mountColLabel = mainFrame:CreateFontString(nil, "OVERLAY",
                                                     "GameFontNormalSmall")
    mountColLabel:SetPoint("TOPLEFT", 110, -58)
    mountColLabel:SetText("Mount gear")
    mountColLabel:SetTextColor(0.6, 0.9, 1)

    local baseColLabel = mainFrame:CreateFontString(nil, "OVERLAY",
                                                    "GameFontNormalSmall")
    baseColLabel:SetPoint("TOPLEFT", 290, -58)
    baseColLabel:SetText("Base gear")
    baseColLabel:SetTextColor(1, 0.9, 0.6)
```

- [ ] **Step 7: Replace single-row construction with dual-zone rows**

Find the row-construction loop (around lines 172-285, the `for i, slotInfo in ipairs(NS.Slots.ORDER) do` block). Replace the **entire loop** with:

```lua
    ----------------------------------------------------------------
    -- Helper: build one item zone (icon + name + Set/Clear buttons + drag/drop)
    ----------------------------------------------------------------
    local function CreateZone(parent, slotInfo, setName, anchorOffsetX)
        local zone = CreateFrame("Frame", nil, parent)
        zone:SetSize(170, ROW_HEIGHT)
        zone:SetPoint("LEFT", parent, "LEFT", anchorOffsetX, 0)
        zone.slotId = slotInfo.id
        zone.setName = setName

        local icon = zone:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 4, 0)
        zone.icon = icon

        local itemText = zone:CreateFontString(nil, "OVERLAY",
                                               "GameFontHighlightSmall")
        itemText:SetPoint("LEFT", icon, "RIGHT", 4, 0)
        itemText:SetPoint("RIGHT", zone, "RIGHT", -50, 0)
        itemText:SetJustifyH("LEFT")
        itemText:SetText("--")
        itemText:SetTextColor(0.5, 0.5, 0.5)
        zone.itemText = itemText

        local setBtn = CreateFrame("Button", nil, zone, "UIPanelButtonTemplate")
        setBtn:SetSize(45, 22)
        setBtn:SetPoint("RIGHT", -2, 0)
        setBtn:SetText("Set")
        setBtn:SetScript("OnClick", function()
            OpenItemPicker(slotInfo.id, setName)
        end)
        zone.setBtn = setBtn

        local clearBtn = CreateFrame("Button", nil, zone, "UIPanelButtonTemplate")
        clearBtn:SetSize(45, 22)
        clearBtn:SetPoint("RIGHT", -2, 0)
        clearBtn:SetText("Clear")
        clearBtn:SetScript("OnClick", function()
            NS.charDb.sets[setName][slotInfo.id] = nil
            NS:FireCallback("DATA_UPDATED")
        end)
        clearBtn:Hide()
        zone.clearBtn = clearBtn

        zone:EnableMouse(true)
        zone:SetScript("OnEnter", function(self)
            local itemId = NS.charDb.sets[setName][self.slotId]
            if itemId then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                local _, link = GetItemInfo(itemId)
                if link then GameTooltip:SetHyperlink(link) end
                GameTooltip:Show()
            end
        end)
        zone:SetScript("OnLeave", function() GameTooltip:Hide() end)

        zone:RegisterForDrag("LeftButton")
        local function HandleDrop(self)
            local infoType, itemId = GetCursorInfo()
            if infoType == "item" and itemId then
                local _, _, _, _, _, _, _, _, equipLoc = GetItemInfo(itemId)
                if equipLoc and NS.Slots:FitsSlot(equipLoc, self.slotId) then
                    NS.charDb.sets[setName][self.slotId] = itemId
                    NS:FireCallback("DATA_UPDATED")
                    ClearCursor()
                else
                    NS:Print("This item cannot go in the "
                             .. (NS.Slots.byId[self.slotId].name or "")
                             .. " slot.")
                end
            end
        end
        zone:SetScript("OnReceiveDrag", HandleDrop)
        zone:SetScript("OnMouseUp", HandleDrop)

        return zone
    end

    ----------------------------------------------------------------
    -- Slot rows (5 fixed rows, each with mount + base zones)
    ----------------------------------------------------------------
    local contentWidth = WINDOW_WIDTH - 24
    for i, slotInfo in ipairs(NS.Slots.ORDER) do
        local row = CreateFrame("Frame", nil, mainFrame)
        row:SetSize(contentWidth, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 12, -(76 + (i - 1) * ROW_HEIGHT))
        row.slotId = slotInfo.id

        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0.03)
        end

        local slotLabel = row:CreateFontString(nil, "OVERLAY",
                                               "GameFontNormalSmall")
        slotLabel:SetPoint("LEFT", 4, 0)
        slotLabel:SetWidth(80)
        slotLabel:SetJustifyH("LEFT")
        slotLabel:SetText(slotInfo.name)
        slotLabel:SetTextColor(0.7, 0.7, 0.7)

        row.mountZone = CreateZone(row, slotInfo, "mount", 86)
        row.baseZone  = CreateZone(row, slotInfo, "base",  86 + 180)

        -- Separator arrow between zones
        local arrow = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        arrow:SetPoint("LEFT", row, "LEFT", 86 + 170, 0)
        arrow:SetWidth(10)
        arrow:SetJustifyH("CENTER")
        arrow:SetText("⇄")
        arrow:SetTextColor(0.6, 0.6, 0.6)

        rows[#rows + 1] = row
    end
```

- [ ] **Step 8: Finalise the v1.x → v2.0 migration in Core.lua**

The UI no longer reads `MountSpeedCharDB.mountItems`, so the alias from Task 1 can be replaced with a proper deep migration that drops `mountItems`.

In `Core.lua`, find the migration block from Task 1:

```lua
        -- Migrate from v1.x schema. We ALIAS sets.mount to the same table as
        -- mountItems so v1.x UI code (which still reads
        -- MountSpeedCharDB.mountItems) keeps working through Tasks 1-2. Task 3
        -- converts the UI to read sets.* directly and finalises this migration
        -- by replacing the alias with a deep copy + dropping mountItems.
        if MountSpeedCharDB.mountItems then
            MountSpeedCharDB.sets = MountSpeedCharDB.sets or { mount = {}, base = {} }
            MountSpeedCharDB.sets.mount = MountSpeedCharDB.mountItems
            -- migrationNoticeShown stays false → user gets the one-time message
        end
        MountSpeedCharDB.savedEquipment = nil  -- obsolete in v2.0
```

Replace with:

```lua
        -- Migrate from v1.x schema (mountItems → sets.mount, drop savedEquipment)
        if MountSpeedCharDB.mountItems then
            MountSpeedCharDB.sets = MountSpeedCharDB.sets or { mount = {}, base = {} }
            for slotId, itemId in pairs(MountSpeedCharDB.mountItems) do
                MountSpeedCharDB.sets.mount[slotId] = itemId
            end
            MountSpeedCharDB.mountItems = nil
            -- migrationNoticeShown stays false → user gets the one-time message
        end
        MountSpeedCharDB.savedEquipment = nil  -- obsolete in v2.0
```

Note: for users who already loaded the alias build (Task 1 deployed), `sets.mount` already holds the data — the `for` loop just copies an entry that's already there, then nils `mountItems`. Idempotent.

- [ ] **Step 9: Deploy and reload**

```bash
cp Core.lua UI.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In game: `/reload` then `/ms`

- [ ] **Step 10: Verify dual-column UI + SRA-style picker**

Expected:
- Window is wider (520px)
- Each row shows: slot name on left, then mount item zone, then `⇄`, then base item zone
- Column headers "Mount gear" and "Base gear" appear above the rows
- Click "Set" on either zone opens a **dark SRA-style picker window** at the cursor with:
  - Title bar showing "Select Mount item — Trinket 1" (or "Select Base item — ..."), title text in cyan
  - Close button (X) on the right of the title bar
  - Scrollable list of fitting items from bags, each row showing icon + name colored by quality
  - Hover row → light grey overlay; click row → assigns the item and closes the picker
  - Tooltip on hover (`SetItemByID`)
  - "No matching items in your bags." dim text if empty
  - Picker draggable by its title bar
- Drag an item from bags onto a zone → still works as the fast-path alternative
- Click "Clear" removes the item from that zone only (other zone unaffected)
- Hover over a configured zone shows its tooltip

Also verify migration finalisation: `/dump MountSpeedCharDB.mountItems` — expected: `nil`. `/dump MountSpeedCharDB.sets.mount` — expected: still has your configured items.

- [ ] **Step 11: Commit**

```bash
git add Core.lua UI.lua
git commit -m "UI: dual-column rows + SRA-style item picker, finalise v2.0 migration"
```

---

## Task 4: "Capture current gear" button

**Files:**
- Modify: `UI.lua` (header area, capture popup), `Core.lua` (StaticPopupDialogs)

- [ ] **Step 1: Add capture confirmation popup to Core.lua**

In `Core.lua`, after the existing `MOUNTSPEED_RESET_ALL` popup (after line 174), append:

```lua
StaticPopupDialogs["MOUNTSPEED_CAPTURE_OVERWRITE"] = {
    text = "Replace your current Base gear with what you're wearing now?",
    button1 = "Yes, Capture",
    button2 = "Cancel",
    OnAccept = function()
        NS:FireCallback("CAPTURE_BASE_CONFIRMED")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}
```

- [ ] **Step 2: Add capture button to UI.lua main frame**

In `UI.lua`, inside `CreateMainFrame()` after the column labels you added in Task 3 (right after `baseColLabel:SetTextColor(1, 0.9, 0.6)`), insert:

```lua
    -- Capture current gear → sets.base
    local captureBtn = CreateFrame("Button", nil, mainFrame,
                                   "UIPanelButtonTemplate")
    captureBtn:SetSize(140, 22)
    captureBtn:SetPoint("TOPRIGHT", -12, -56)
    captureBtn:SetText("Capture current")
    captureBtn:SetScript("OnClick", function()
        local hasAny = false
        for _ in pairs(NS.charDb.sets.base) do hasAny = true; break end
        if hasAny then
            StaticPopup_Show("MOUNTSPEED_CAPTURE_OVERWRITE")
        else
            NS:FireCallback("CAPTURE_BASE_CONFIRMED")
        end
    end)
    captureBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("Capture current equipment")
        GameTooltip:AddLine("Saves the items currently in your "
            .. "5 configurable slots into Base gear.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    captureBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
```

- [ ] **Step 3: Add CAPTURE_BASE_CONFIRMED callback to UI.lua**

In `UI.lua`, at the bottom of the file alongside the other `NS:RegisterCallback` blocks (after `NS:RegisterCallback("DATA_UPDATED", ...)`), append:

```lua
NS:RegisterCallback("CAPTURE_BASE_CONFIRMED", function()
    for _, slotInfo in ipairs(NS.Slots.ORDER) do
        local equipped = GetInventoryItemID("player", slotInfo.id)
        if equipped and equipped > 0 then
            NS.charDb.sets.base[slotInfo.id] = equipped
        end
    end
    NS:FireCallback("DATA_UPDATED")
    NS:Print("Base gear captured from current equipment.")
end)
```

- [ ] **Step 4: Deploy and reload**

```bash
cp Core.lua UI.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In game: `/reload` then `/ms`

- [ ] **Step 5: Verify capture flow**

Empty `sets.base`: `/run MountSpeedCharDB.sets.base = {}` then `/reload` then `/ms`.

Click **Capture current** with empty base → expected: no popup, base columns immediately fill from your equipped items.

Click **Capture current** again with base now populated → expected: popup asks to confirm overwrite. Cancel → no change. Yes → re-captures (same result if you didn't change gear).

- [ ] **Step 6: Commit**

```bash
git add Core.lua UI.lua
git commit -m "UI: add Capture current gear button with overwrite confirm"
```

---

## Task 5: Floating swap button

**Files:**
- Modify: `UI.lua` (new draggable frame, registered on ADDON_LOADED)

- [ ] **Step 1: Add the floating button creation function**

In `UI.lua`, after the `CreateMinimapButton` function definition (around the end of the minimap button section), append:

```lua
----------------------------------------------------------------------
-- Floating manual-swap button (draggable, position saved per account)
----------------------------------------------------------------------
local swapBtn

local function UpdateSwapBtnVisual()
    if not swapBtn then return end
    if NS.charDb.isMountSwapped then
        swapBtn.icon:SetDesaturated(true)
        swapBtn.border:Show()
        swapBtn.tooltipText = "Switch to base gear"
    else
        swapBtn.icon:SetDesaturated(false)
        swapBtn.border:Hide()
        swapBtn.tooltipText = "Switch to mount gear"
    end
end

local function CreateSwapButton()
    if swapBtn then return end

    local btn = CreateFrame("Button", "MountSpeedSwapButton", UIParent)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp")

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse")
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetAllPoints()
    border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    border:SetBlendMode("ADD")
    border:SetVertexColor(1, 0.85, 0.2)  -- gold
    border:Hide()
    btn.border = border

    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    -- Apply saved position
    local pos = NS.db and NS.db.settings.swapButtonPos
                or { point = "CENTER", x = 0, y = -100 }
    btn:ClearAllPoints()
    btn:SetPoint(pos.point or "CENTER", UIParent,
                 pos.point or "CENTER", pos.x or 0, pos.y or -100)

    -- Drag → reposition + save
    btn:SetScript("OnDragStart", function(self) self:StartMoving() end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        NS.db.settings.swapButtonPos = { point = point, x = x, y = y }
    end)

    btn:SetScript("OnClick", function()
        if NS.Swap and NS.Swap.Toggle then NS.Swap:Toggle() end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("MountSpeed")
        GameTooltip:AddLine(self.tooltipText or "Switch gear", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    swapBtn = btn
    UpdateSwapBtnVisual()
end
```

- [ ] **Step 2: Wire the button into ADDON_LOADED and DATA_UPDATED callbacks**

In `UI.lua`, find the `ADDON_LOADED` callback (around the end of the file):

```lua
NS:RegisterCallback("ADDON_LOADED", function()
    CreateMinimapButton()
end)
```

Replace with:

```lua
NS:RegisterCallback("ADDON_LOADED", function()
    CreateMinimapButton()
    CreateSwapButton()
end)
```

Also find the `DATA_UPDATED` callback:

```lua
NS:RegisterCallback("DATA_UPDATED", function()
    RefreshRows()
end)
```

Replace with:

```lua
NS:RegisterCallback("DATA_UPDATED", function()
    RefreshRows()
    UpdateSwapBtnVisual()
end)
```

- [ ] **Step 3: Deploy and reload**

```bash
cp UI.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In game: `/reload`

- [ ] **Step 4: Verify floating button**

Expected: a 32×32 mount icon button appears at center-screen, slightly below center. Drag it to a new spot — `/reload` — it stays where you put it.

Configure both `sets.mount` and `sets.base` for at least one slot (use `/ms` UI). Click the button — expected: gear swaps, button icon desaturates and gets a gold border. Click again — expected: gear swaps back, button returns to full color.

Mount up — expected: auto-swap fires AND button visual updates to "swapped" state. Dismount — same in reverse.

- [ ] **Step 5: Commit**

```bash
git add UI.lua
git commit -m "UI: add floating draggable swap button with state visual"
```

---

## Task 6: Keybind (via Bindings.xml)

**Files:**
- Create: `Bindings.xml`
- Modify: `MountSpeed.toc` (reference Bindings.xml)

WoW's keybinding system in Classic loads bindings from `Bindings.xml` declared at the addon root. The XML provides both the binding label AND the action body (Lua snippet), so we don't need an invisible button or `BINDING_NAME_*` globals.

- [ ] **Step 1: Create Bindings.xml**

At the addon root (same directory as `MountSpeed.toc`), create `Bindings.xml` with:

```xml
<Bindings>
    <Binding name="MOUNTSPEED_TOGGLE" header="MOUNTSPEED" category="MountSpeed">
        if MountSpeedSwapTrigger then MountSpeedSwapTrigger() end
    </Binding>
</Bindings>
```

The `<Binding>` element runs its body when the bound key is pressed. We dispatch through a global function (set up next step) rather than referencing `NS.Swap:Toggle()` directly, because the Bindings.xml execution context doesn't have access to the addon's local `NS` namespace.

- [ ] **Step 2: Expose the trigger function from UI.lua**

In `UI.lua`, append at the bottom of the file (alongside the other callbacks):

```lua
----------------------------------------------------------------------
-- Global trigger callable from Bindings.xml (no NS access in that scope)
----------------------------------------------------------------------
function MountSpeedSwapTrigger()
    if NS.Swap and NS.Swap.Toggle then NS.Swap:Toggle() end
end

-- Localized labels for the Key Bindings UI
BINDING_HEADER_MOUNTSPEED        = "MountSpeed"
BINDING_NAME_MOUNTSPEED_TOGGLE   = "Toggle mount/base gear"
```

- [ ] **Step 3: Reference Bindings.xml from the .toc**

In `MountSpeed.toc`, after the existing `UI.lua` line, add:

```
Bindings.xml
```

The full file should look like:

```
## Interface: 20505
## Title: MountSpeed
## Notes: Auto-swap equipment when mounting for speed bonuses
## Author: PIECQ Grégory
## Version: 1.0.1
## SavedVariables: MountSpeedDB
## SavedVariablesPerCharacter: MountSpeedCharDB

Core.lua
Slots.lua
Swap.lua
UI.lua
Bindings.xml
```

(The version bump to 2.0.0 happens in Task 9 — leave 1.0.1 here for now.)

- [ ] **Step 4: Update package.sh to include Bindings.xml in release zips**

In `package.sh`, find the source-files block (around lines 23-28):

```bash
cp "$TOC_FILE" \
   Core.lua \
   Slots.lua \
   Swap.lua \
   UI.lua \
   "build/$ADDON_NAME/"
```

Replace with:

```bash
cp "$TOC_FILE" \
   Core.lua \
   Slots.lua \
   Swap.lua \
   UI.lua \
   Bindings.xml \
   "build/$ADDON_NAME/"
```

- [ ] **Step 5: Deploy and reload**

```bash
cp UI.lua MountSpeed.toc Bindings.xml "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In game: `/reload`

- [ ] **Step 6: Verify keybind**

Open **Game Menu (Esc) → Key Bindings → scroll to "MountSpeed" header**.

Expected: a row labeled "Toggle mount/base gear" with a "Not bound" button next to it.

Click the binding row, press a key (e.g. F12), click "Okay" then "Save and exit".

Press the bound key — expected: gear swaps (same effect as the floating button or `/ms swap`). Floating button visual updates accordingly.

- [ ] **Step 7: Commit**

```bash
git add UI.lua MountSpeed.toc Bindings.xml package.sh
git commit -m "UI: add 'Toggle mount/base gear' keybind via Bindings.xml"
```

---

## Task 7: Slash commands /ms swap and /ms capture

**Files:**
- Modify: `Core.lua` (SlashCmdList["MOUNTSPEED"], help text)

- [ ] **Step 1: Add the two new slash branches**

In `Core.lua`, find the `SlashCmdList["MOUNTSPEED"]` function (around lines 122-151). The 1.0.1 baseline has these branches: empty/show/toggle, hide, settings/config, reset, then `else` (help). Add two new `elseif` branches between the `reset` branch and the final `else`:

Find:

```lua
    elseif msg == "reset" then
        StaticPopup_Show("MOUNTSPEED_RESET_ALL")

    else
```

Replace with:

```lua
    elseif msg == "reset" then
        StaticPopup_Show("MOUNTSPEED_RESET_ALL")

    elseif msg == "swap" then
        if NS.Swap and NS.Swap.Toggle then
            NS.Swap:Toggle()
        end

    elseif msg == "capture" then
        NS:FireCallback("CAPTURE_BASE_CONFIRMED")

    else
```

- [ ] **Step 2: Update help text**

Still in `Core.lua`, in the same function, find the help block (the lines after the final `else`):

```lua
    else
        NS:Print("v" .. NS.version .. " commands:")
        print("  /ms            - toggle main window")
        print("  /ms settings   - open settings panel")
        print("  /ms reset      - wipe ALL data (confirm)")
    end
```

Replace with:

```lua
    else
        NS:Print("v" .. NS.version .. " commands:")
        print("  /ms            - toggle main window")
        print("  /ms settings   - open settings panel")
        print("  /ms swap       - toggle mount / base gear")
        print("  /ms capture    - save current gear as Base set")
        print("  /ms reset      - wipe ALL data (confirm)")
    end
```

- [ ] **Step 3: Deploy and reload**

```bash
cp Core.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In game: `/reload`

- [ ] **Step 4: Verify slash commands**

In game:
- `/ms swap` — expected: gear swaps (same effect as button/keybind)
- `/ms capture` — expected: current equipment overwrites `sets.base` immediately; chat message confirms. (Note: unlike the **Capture current** button, the slash command does NOT prompt — typing it is taken as explicit intent.)
- `/ms help` (any unknown arg) — expected: help text now lists the two new commands

- [ ] **Step 5: Commit**

```bash
git add Core.lua
git commit -m "Core: add /ms swap and /ms capture slash commands"
```

---

## Task 8: One-time migration UX message

**Files:**
- Modify: `Core.lua` (PLAYER_LOGIN callback)

- [ ] **Step 1: Add the one-time message logic**

In `Core.lua`, after the existing event-frame block but before the slash commands section (roughly between line 114 and line 119), append:

```lua
----------------------------------------------------------------------
-- One-time migration notice for v1.x → v2.0 upgrades
----------------------------------------------------------------------
NS:RegisterCallback("PLAYER_LOGIN", function()
    if NS.charDb.migrationNoticeShown then return end

    local sets = NS.charDb.sets
    if not sets then return end

    local hasMount = next(sets.mount) ~= nil
    local hasBase  = next(sets.base)  ~= nil

    if hasMount and not hasBase then
        NS:Print("Updated to v" .. NS.version
            .. ". Open the window (/ms) and configure your "
            .. "|cffffd200Base gear|r — auto-swap is paused until you do.")
        NS:Print("Tip: equip your normal gear, then click "
            .. "|cffffd200Capture current|r to fill it in one click.")
    end

    NS.charDb.migrationNoticeShown = true
end)
```

- [ ] **Step 2: Deploy and reload**

```bash
cp Core.lua "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In game: simulate the migrated state by running `/run MountSpeedCharDB.migrationNoticeShown = false; MountSpeedCharDB.sets.base = {}` then `/reload`.

- [ ] **Step 3: Verify the notice fires once**

Expected on `/reload`: two `MountSpeed:` chat lines appear with the upgrade prompt and the tip.

`/reload` again — expected: notice does NOT re-appear (flag is now true).

`/dump MountSpeedCharDB.migrationNoticeShown` — expected: `true`.

- [ ] **Step 4: Commit**

```bash
git add Core.lua
git commit -m "Core: one-time v2.0 migration notice for users with empty base set"
```

---

## Task 9: Version bump, .toc update, README

**Files:**
- Modify: `Core.lua`, `MountSpeed.toc`, `README.md`

- [ ] **Step 1: Bump NS.version in Core.lua**

In `Core.lua`, find:

```lua
NS.version = "1.0.0"
```

Replace with:

```lua
NS.version = "2.0.0"
```

(Note: version in code may currently be "1.0.0" or "1.0.1" depending on uncommitted state — set to "2.0.0" regardless.)

- [ ] **Step 2: Bump version in MountSpeed.toc**

In `MountSpeed.toc`, find:

```
## Version: 1.0.1
```

Replace with:

```
## Version: 2.0.0
```

- [ ] **Step 3: Update README.md**

Read the current `README.md` first. Update the relevant sections so the README reflects v2.0 behavior:

- Replace any reference to "automatically saves your gear before mounting" / "restores original gear" with "swaps between two configured sets (Mount + Base)"
- Add a section listing how to set up Base gear: "Equip your normal gear, open `/ms`, click **Capture current**"
- Document the new floating swap button: drag to reposition, click to toggle
- Document the keybind: Game Menu → Key Bindings → MountSpeed → "Toggle mount/base gear"
- Document the new slash commands: `/ms swap`, `/ms capture`
- Update the version at the top of the file to 2.0.0 if it's mentioned

(Per the user's persistent feedback rule: README is updated before each commit, CHANGELOG is updated only on release. Do not edit `CHANGELOG.md` in this task.)

- [ ] **Step 4: Deploy and reload**

```bash
cp Core.lua MountSpeed.toc README.md "/c/Program Files (x86)/World of Warcraft/_anniversary_/Interface/AddOns/MountSpeed/"
```

In game: `/reload` then `/ms help` (or any unknown arg).

- [ ] **Step 5: Verify version**

Expected: chat shows `MountSpeed: v2.0.0 commands:` followed by the help list.

In the WoW addon list (Esc → Interface → AddOns or the character-select screen), MountSpeed shows as version 2.0.0.

- [ ] **Step 6: Commit**

```bash
git add Core.lua MountSpeed.toc README.md
git commit -m "v2.0.0: bump version, update README for new behavior"
```

---

## Task 10: End-to-end smoke test

This task is verification only — no code changes.

- [ ] **Step 1: Reset to a clean migrated state**

In game:
```
/run MountSpeedCharDB = nil; MountSpeedDB = nil
/reload
```

Expected: `/dump MountSpeedCharDB` shows the new schema with empty `sets.mount`, empty `sets.base`, `enabled = true`, `migrationNoticeShown = false` (no migration notice fires because `sets.mount` is also empty).

- [ ] **Step 2: Configure both sets**

`/ms` → use the dropdown to set a Mount item and a Base item for at least Trinket 1 and Feet (any items from your bags that fit).

- [ ] **Step 3: Test auto-swap**

Mount up. Expected: chat says "Mount gear equipped." Floating button desaturates with gold border.

Open character pane (C) — expected: configured slots show the mount items.

Dismount. Expected: chat says "Base gear equipped." Floating button returns to full color. Configured slots show the base items.

- [ ] **Step 4: Test manual toggle (3 entry points)**

Click the floating button — gear swaps to mount. Click again — back to base.
Run `/ms swap` — same.
Bind a key (Game Menu → Key Bindings → MountSpeed) and press it — same.

- [ ] **Step 5: Test combat queue**

Get into combat. Press the swap key. Expected: chat says "In combat — gear swap will run when combat ends." Leave combat. Expected: swap fires automatically.

- [ ] **Step 6: Test capture**

Equip your normal "base" outfit manually. `/ms` → click **Capture current**. With non-empty base, expected: confirm popup. Click Yes. Expected: base column populated from current equipment.

- [ ] **Step 7: Test eligibility rule**

Clear the Base item for Trinket 1 (Clear button). Mount up. Expected: Trinket 1 stays as-is (not swapped), other configured slots still swap. Dismount. Expected: same — Trinket 1 untouched, other slots restore.

- [ ] **Step 8: Verify no Lua errors**

Throughout testing, no `BugSack` / `LuaErrors` notifications should appear. If you have a Lua error display addon enabled, no errors should trigger.

- [ ] **Step 9: Final state check**

`/dump MountSpeedCharDB` — should show:
- `enabled = true`
- `sets.mount` populated
- `sets.base` populated
- `isMountSwapped` matching current state (true if mounted with mount gear, false otherwise)
- `migrationNoticeShown = true`
- No `mountItems`, no `savedEquipment` keys

If everything passes, the v2.0 implementation is complete.
