----------------------------------------------------------------------
-- MountSpeed  -  UI.lua
-- Configuration window, item selection, minimap button
----------------------------------------------------------------------
local _, NS = ...

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
local WINDOW_WIDTH  = 520
local WINDOW_HEIGHT = 100 + (#NS.Slots.ORDER * ROW_HEIGHT) -- header + rows

----------------------------------------------------------------------
-- Forward declarations
----------------------------------------------------------------------
local mainFrame, enableCB, rows, itemPicker
local activeSlotId, activeSetName
local positionApplied = false
rows = {}

-- Forward decl so CreateMainFrame can call it
local OpenItemPicker

----------------------------------------------------------------------
-- SRA-style item picker window (custom dark frame, scrollable rows)
-- One instance, reused across opens. Anchored at the cursor.
----------------------------------------------------------------------
local PICKER_WIDTH        = 280
local PICKER_ROW_HEIGHT   = 22
local PICKER_VISIBLE_ROWS = 9
local PICKER_HEIGHT       = PICKER_VISIBLE_ROWS * PICKER_ROW_HEIGHT + 42  -- title bar + padding

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

----------------------------------------------------------------------
-- Refresh helpers
----------------------------------------------------------------------
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

----------------------------------------------------------------------
-- Lazy-create the main config window (called once)
----------------------------------------------------------------------
local function CreateMainFrame()
    if mainFrame then return end

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

    -- Close button (parented to titleBar so it stays above the drag region)
    local closeBtn = CreateFrame("Button", nil, titleBar,
                                 "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 0, 0)
    closeBtn:SetScript("OnClick", function() mainFrame:Hide() end)

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
        GameTooltip:ClearLines()
        GameTooltip:AddLine("Capture current equipment")
        GameTooltip:AddLine("Saves the items currently in your "
            .. "5 configurable slots into Base gear.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    captureBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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

local function CreateMinimapButton()
    if minimapBtn then return end
    if not Minimap then return end

    local btn = CreateFrame("Button", "MountSpeedMinimapButton", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)

    -- Circular tracking border (matches other minimap buttons)
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

    -- Carrot icon
    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Food_54")
    btn.icon = icon

    -- Hover glow
    local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(24, 24)
    highlight:SetPoint("CENTER")
    highlight:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    highlight:SetBlendMode("ADD")

    -- Position on minimap edge
    local function UpdatePosition()
        local angle = math.rad(NS.db and NS.db.settings.minimapPos or 215)
        local x = math.cos(angle) * 80
        local y = math.sin(angle) * 80
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    UpdatePosition()

    -- Drag: follow cursor around minimap edge
    btn:RegisterForDrag("LeftButton")
    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(self)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            if NS.db then NS.db.settings.minimapPos = angle end
            local rad = math.rad(angle)
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER",
                          math.cos(rad) * 80, math.sin(rad) * 80)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- Left-click toggles config window
    btn:RegisterForClicks("LeftButtonUp")
    btn:SetScript("OnClick", function()
        NS:FireCallback("TOGGLE_WINDOW")
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("MountSpeed")
        GameTooltip:AddLine("Left-click to toggle config", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    minimapBtn = btn
end

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

----------------------------------------------------------------------
-- Callbacks
----------------------------------------------------------------------
NS:RegisterCallback("ADDON_LOADED", function()
    CreateMinimapButton()
    CreateSwapButton()
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
    UpdateSwapBtnVisual()
end)

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
