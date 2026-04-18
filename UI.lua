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

local function CreateMinimapButton()
    if minimapBtn then return end
    if not Minimap then return end

    local btn = CreateFrame("Button", "MountSpeedMinimapBtn", Minimap)
    btn:SetSize(32, 32)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)

    -- Dark circular background (same as other minimap buttons)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")

    -- Icon (circular mask to match other minimap buttons)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Food_54")
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    btn.icon = icon

    -- Circular border (matches standard minimap tracking buttons)
    local overlay = btn:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT")

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
