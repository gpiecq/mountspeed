----------------------------------------------------------------------
-- MountSpeed  -  Core.lua
-- Addon initialisation, SavedVariables defaults, event bus, slash cmds
----------------------------------------------------------------------
local ADDON_NAME, NS = ...
NS.version = "1.0.0"

----------------------------------------------------------------------
-- Default saved-variables template (account-wide)
----------------------------------------------------------------------
local DEFAULTS = {
    settings = {
        windowPos     = { point = "CENTER", x = 0, y = 0 },
        minimapPos    = 215,
        swapButtonPos = { point = "CENTER", x = 0, y = -100 },
    },
}

local CHAR_DEFAULTS = {
    enabled = true,
    sets = {
        mount = {},
        base  = {},
    },
    isMountSwapped         = false,
    migrationNoticeShown   = false,
}

----------------------------------------------------------------------
-- Deep-copy helper (for defaults)
----------------------------------------------------------------------
local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local copy = {}
    for k, v in pairs(src) do copy[k] = DeepCopy(v) end
    return copy
end
NS.DeepCopy = DeepCopy

----------------------------------------------------------------------
-- Merge defaults into saved table (non-destructive)
----------------------------------------------------------------------
local function MergeDefaults(sv, def)
    for k, v in pairs(def) do
        if type(v) == "table" then
            if type(sv[k]) ~= "table" then sv[k] = {} end
            MergeDefaults(sv[k], v)
        elseif sv[k] == nil then
            sv[k] = v
        end
    end
end

----------------------------------------------------------------------
-- Simple internal event bus
----------------------------------------------------------------------
NS.callbacks = {}

function NS:RegisterCallback(event, fn)
    if not self.callbacks[event] then self.callbacks[event] = {} end
    self.callbacks[event][#self.callbacks[event] + 1] = fn
end

function NS:FireCallback(event, ...)
    local cbs = self.callbacks[event]
    if not cbs then return end
    for i = 1, #cbs do cbs[i](...) end
end

----------------------------------------------------------------------
-- Pretty print helper
----------------------------------------------------------------------
function NS:Print(msg)
    print("|cff00ccffMountSpeed:|r " .. tostring(msg))
end

----------------------------------------------------------------------
-- Addon init frame
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_LOGOUT")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        -- Initialise / migrate account-wide saved variables
        if not MountSpeedDB then
            MountSpeedDB = DeepCopy(DEFAULTS)
        else
            MergeDefaults(MountSpeedDB, DEFAULTS)
        end

        -- Per-character saved variables
        if not MountSpeedCharDB then
            MountSpeedCharDB = DeepCopy(CHAR_DEFAULTS)
        else
            MergeDefaults(MountSpeedCharDB, CHAR_DEFAULTS)
        end

        -- Migrate from v1.x schema (mountItems → sets.mount, drop savedEquipment)
        if MountSpeedCharDB.mountItems then
            for slotId, itemId in pairs(MountSpeedCharDB.mountItems) do
                MountSpeedCharDB.sets.mount[slotId] = itemId
            end
            MountSpeedCharDB.mountItems = nil
            -- migrationNoticeShown stays false → user gets the one-time message
        end
        MountSpeedCharDB.savedEquipment = nil  -- obsolete in v2.0

        NS.db     = MountSpeedDB
        NS.charDb = MountSpeedCharDB

        NS:FireCallback("ADDON_LOADED")
        frame:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        NS:FireCallback("PLAYER_LOGIN")

    elseif event == "PLAYER_LOGOUT" then
        NS:FireCallback("PLAYER_LOGOUT")
    end
end)

----------------------------------------------------------------------
-- Slash commands  /ms  /mountspeed
----------------------------------------------------------------------
SLASH_MOUNTSPEED1 = "/ms"
SLASH_MOUNTSPEED2 = "/mountspeed"

SlashCmdList["MOUNTSPEED"] = function(msg)
    msg = strtrim(msg or ""):lower()

    if msg == "" or msg == "show" or msg == "toggle" then
        NS:FireCallback("TOGGLE_WINDOW")

    elseif msg == "hide" then
        NS:FireCallback("HIDE_WINDOW")

    elseif msg == "settings" or msg == "config" then
        NS:FireCallback("SHOW_SETTINGS")

    elseif msg == "reset" then
        StaticPopup_Show("MOUNTSPEED_RESET_ALL")

    else
        NS:Print("v" .. NS.version .. " commands:")
        print("  /ms            - toggle main window")
        print("  /ms settings   - open settings panel")
        print("  /ms reset      - wipe ALL data (confirm)")
    end
end

----------------------------------------------------------------------
-- Static popup for "reset all" confirmation
----------------------------------------------------------------------
StaticPopupDialogs["MOUNTSPEED_RESET_ALL"] = {
    text = "Reset ALL MountSpeed data?\nThis cannot be undone.",
    button1 = "Yes, Reset",
    button2 = "Cancel",
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
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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
