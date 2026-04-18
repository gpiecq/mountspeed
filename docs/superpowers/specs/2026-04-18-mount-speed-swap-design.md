# MountSpeed — Equipment Swap on Mount/Dismount

## Overview

WoW TBC Classic addon that automatically swaps configured equipment when the player mounts or dismounts. Saves the currently equipped items before swapping, restores them on dismount.

Target interface: `20505` (TBC Classic 2.5.x).

## Architecture

4 Lua modules, no external dependencies (same pattern as SimpleRaidAssign):

| File | Responsibility |
|------|---------------|
| `Core.lua` | Addon init, SavedVariables defaults, event bus, slash commands |
| `Slots.lua` | Equipment slot constants (5 slots), bag scanning, invType mapping |
| `Swap.lua` | Mount/dismount detection via `UNIT_AURA` + `IsMounted()`, equipment save/restore with combat queue |
| `UI.lua` | Configuration window, dropdown + drag&drop item selection, minimap button |

Communication between modules uses the internal event bus (`NS:RegisterCallback` / `NS:FireCallback`).

## Data Model

### Account-wide (`MountSpeedDB`)

```lua
settings = {
    windowPos = { point = "CENTER", x = 0, y = 0 },
    minimapPos = 215,  -- angle on minimap edge
}
```

### Per-character (`MountSpeedCharDB`)

```lua
enabled = true,            -- toggle auto-swap per character
mountItems = {},           -- [slotId] = itemId — configured mount speed items
savedEquipment = {},       -- [slotId] = itemId — gear snapshot before mounting
isMountSwapped = false,    -- whether mount gear is currently active
```

`mountItems` and `enabled` are per-character because different characters have different items and may want independent on/off control.

## Configurable Slots

5 slots relevant for TBC mount speed bonuses:

| Slot ID | Name | Typical use |
|---------|------|-------------|
| 13 | Trinket 1 | Carrot on a Stick, Riding Crop |
| 14 | Trinket 2 | Second speed trinket |
| 8 | Feet | Boots with Mithril Spurs enchant |
| 10 | Hands | Riding Gloves |
| 15 | Back | Speed cloak |

## Swap Logic (Swap.lua)

### Mount detection

- Listen to `UNIT_AURA` for `"player"`
- Track `wasMounted` state, compare to `IsMounted()` on each event
- `false -> true` = just mounted, trigger swap
- `true -> false` = just dismounted, trigger restore

### Mount flow

1. Snapshot currently equipped items for all configured slots into `savedEquipment`
2. For each configured slot: `EquipItemByName(itemId, slotId)` if current item differs
3. Set `isMountSwapped = true`
4. Print: "Mount speed gear equipped."

### Dismount flow

1. If `InCombatLockdown()`: set `pendingRestore = true`, print "In combat — gear will be restored when combat ends."
2. Otherwise: for each saved slot, `EquipItemByName(savedItemId, slotId)` if current differs
3. Clear `savedEquipment`, set `isMountSwapped = false`
4. Print: "Original gear restored."

### Combat queue

- Listen to `PLAYER_REGEN_ENABLED` (combat end)
- If `pendingRestore` is true, execute restore

### Edge cases

- **Login/reload while mounted:** `wasMounted` initialized from `IsMounted()` at `PLAYER_LOGIN`. If `isMountSwapped` is already true in saved vars, no re-swap occurs.
- **No items configured:** swap silently skipped.
- **Item not in bags:** `EquipItemByName` is a no-op if item is missing.

## Bag Scanning (Slots.lua)

### invType mapping

Maps WoW `equipLoc` strings to valid slot IDs:

- `INVTYPE_TRINKET` -> 13, 14
- `INVTYPE_FEET` -> 8
- `INVTYPE_HAND` -> 10
- `INVTYPE_CLOAK` -> 15

### ScanBagsForSlot(targetSlotId)

- Iterates bags 0-4
- For each item: gets `equipLoc` from `GetItemInfo`, checks if it maps to `targetSlotId`
- Deduplicates by `itemId`
- Returns sorted list: `{ itemId, name, icon, quality, link }`

### GetEquippedItem(slotId)

- Returns info about the currently equipped item: `{ itemId, name, icon, quality }` or nil

## UI (UI.lua)

### Configuration window

```
+------------------------------------------+
|  MountSpeed                       [X]    |
+------------------------------------------+
|  [✓] Enable auto-swap                    |
|                                          |
|  Equipment to swap when mounted:         |
|                                          |
|  Trinket 1:  [icon] Riding Crop   [Clear]|
|  Trinket 2:  --                   [Set v]|
|  Feet:       [icon] Mithril Boots [Clear]|
|  Hands:      --                   [Set v]|
|  Back:       --                   [Set v]|
|                                          |
+------------------------------------------+
```

- Lazy-init on first `/ms` call
- Draggable title bar, position persisted to `windowPos`
- Escape to close (`UISpecialFrames`)
- Dark backdrop style (same as SimpleRaidAssign)
- 5 fixed rows (no scroll needed)

### Per-slot row

- 24x24 item icon (or empty texture)
- Slot name label (gray)
- Item name colored by quality (`ITEM_QUALITY_COLORS`) or "--" if empty
- `GameTooltip` on hover via `SetHyperlink`
- **Set button:** opens `UIDropDownMenu` populated with bag items for that slot, colored by quality
- **Clear button:** removes the configured item for that slot
- **Drag & drop:** accepts items via `OnReceiveDrag` / `GetCursorInfo()`, validates item fits the slot via invType mapping

### Minimap button

- Carrot on a Stick icon (`Interface\Icons\INV_Staff_07`)
- Draggable around minimap edge (angle persisted to `minimapPos`)
- Left-click: toggle config window

### Refresh

- `DATA_UPDATED` callback triggers refresh of all 5 rows
- Each row updates: icon texture, item text + color, button visibility (Set vs Clear)

## Slash Commands

- `/ms` or `/mountspeed` — toggle config window
- `/ms hide` — hide window
- `/ms settings` — open config (alias for toggle)
- `/ms reset` — wipe all data (with confirmation popup)

## Files to update

- `Core.lua` — update defaults for new data model
- `MountSpeed.toc` — add Slots.lua, Swap.lua, UI.lua to load order
- `package.sh` — add new files to build
- `.github/workflows/build-addon.yml` — add new files
- `.github/workflows/release.yml` — add new files
