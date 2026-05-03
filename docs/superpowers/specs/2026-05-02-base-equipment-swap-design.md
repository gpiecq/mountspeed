# Base Equipment Swap — Design (v2.0.0)

## Problem

The current addon auto-detects the player's "original gear" by snapshotting `GetInventoryItemID` at the moment of mounting, then restoring it on dismount. Because `EquipItemByName` is asynchronous and mount/dismount events fire in unpredictable orders (especially on flight-path arrivals, taxi flights, and rapid mount/remount cycles), the snapshot frequently captures in-flight state and leaves the character stuck in the wrong gear.

`Swap.lua` has accumulated ~170 lines of guards, watchdogs, tickers, grace windows, and end-of-grace sweeps to paper over these races. The complexity is no longer pulling its weight: the user reports that equipment management is still unreliable.

## Solution

Eliminate the snapshot. The user explicitly configures **two equipment sets** — `mount` (mount-speed gear, already exists) and `base` (normal gear, new) — and the addon swaps between two known fixed sets. No detection, no race, no guards.

A floating in-game button and a key binding let the user trigger the swap manually. Auto-swap on mount/dismount is preserved but now reads from `sets.base` instead of snapshotting.

## Scope

Five equipment slots (Trinket 1, Trinket 2, Feet, Hands, Back) — same as today. No expansion to a full outfit manager.

## Data Model

Per-character SavedVariables (`MountSpeedCharDB`):

```lua
{
    enabled        = true,
    sets = {
        mount = { [13] = id, [14] = id, [8] = id, [10] = id, [15] = id },
        base  = { [13] = id, [14] = id, [8] = id, [10] = id, [15] = id },
    },
    isMountSwapped = false,  -- current state: true = wearing mount, false = wearing base
}
```

Account-wide SavedVariables (`MountSpeedDB`) gains one field for the new floating button position:

```lua
settings = {
    windowPos      = { point, x, y },
    minimapPos     = 215,
    swapButtonPos  = { point = "CENTER", x = 0, y = -100 },  -- NEW
}
```

## Migration (one-shot, in `Core.lua` ADDON_LOADED)

```lua
if MountSpeedCharDB.mountItems then
    MountSpeedCharDB.sets = MountSpeedCharDB.sets or { mount = {}, base = {} }
    MountSpeedCharDB.sets.mount = MountSpeedCharDB.mountItems
    MountSpeedCharDB.mountItems = nil
end
MountSpeedCharDB.savedEquipment = nil  -- obsolete
```

`CHAR_DEFAULTS` is updated to the new schema. The migration block becomes a no-op after the first load.

### User-visible impact of the migration

Existing 1.x users have `mountItems` configured but no `sets.base`. After migration, the eligibility rule (both sets must be filled) means **auto-swap will not fire until the user populates `sets.base`**. The "Capture current gear" button is the one-click remedy: open the window, click capture, done.

A one-time chat message on first launch after the upgrade prompts the user:

> `MountSpeed: Updated to v2.0. Please open the window (/ms) and configure your "Base gear" — auto-swap is paused until you do.`

Triggered by detecting `sets.base` is empty AND `sets.mount` has entries (i.e. migrated state). Stored flag `MountSpeedCharDB.migrationNoticeShown = true` after first display so it doesn't repeat.

## Swap.lua Architecture

### New surface

```
Swap:Apply(setName)        -- Equip sets[setName] for slots configured in BOTH sets.
                              Combat-safe (queues if InCombatLockdown).
                              Updates isMountSwapped accordingly.

Swap:Toggle()              -- Manual button / keybind / "/ms swap":
                              Apply("base") if isMountSwapped else Apply("mount").

Swap:CheckMountState()     -- Auto-swap entry point. Calls Apply("mount") on mount
                              transition, Apply("base") on dismount transition.
                              Logic gates on NS.charDb.enabled.

Swap:StartSwappedTicker()  -- Polling ticker for flight-arrival recovery.
                              Cancels itself when isMountSwapped goes false.
```

### Apply(setName) — slot eligibility rule

A slot is swapped only if **both** `sets.mount[slotId]` and `sets.base[slotId]` are configured. Slots configured in only one set are skipped. This prevents accidental undressing when the user has only filled one column.

### Code removed

- `savedEquipment` table and all its readers/writers
- `restoreGuardEnd` and the post-restore grace window
- `RestoreWatchdog` and the `PLAYER_EQUIPMENT_CHANGED` handler that drives it
- The `prior` peek in `SaveAndEquip` (no longer needed — set is fixed)
- The end-of-grace sweep in `Restore`
- The defensive re-snapshot logic when `isMountSwapped` is already true

### Code preserved

- Combat queue (renamed `pendingRestore` → `pendingApply`, holds the target setName)
- Ticker for flight-path arrivals (still useful: `UNIT_AURA` can lag minutes after landing)
- Event handlers: `UNIT_AURA`, `PLAYER_CONTROL_GAINED`, `PLAYER_REGEN_ENABLED`
- Login rescue: if logged out wearing mount gear and now unmounted, force `Apply("base")`
- Taxi guard: skip transitions while `UnitOnTaxi("player")`

### Removed event registration

`PLAYER_EQUIPMENT_CHANGED` is no longer needed — the watchdog it drove is gone.

## UI Changes (`UI.lua`)

### Row layout

Each of the five rows now displays both sets side by side:

```
[icon] Trinket 1   [mount item name]  ⇄  [base item name]   [Set/Clear][Set/Clear]
```

- Two item zones per row, each with: icon, quality-colored name, drag-drop receiver, tooltip on hover, Set (dropdown) / Clear button
- A small `⇄` separator between zones

### Column header

Above the rows:

```
                       Mount gear         Base gear   [Capture current]
```

### "Capture current gear" button

Reads `GetInventoryItemID("player", slotId)` for all 5 slots and writes them into `sets.base`. If `sets.base` already has any entries, a confirmation popup (`StaticPopup`) asks before overwriting. Combat-safe (read-only — no `EquipItemByName`).

### Window dimensions

Width: 350 → 520. Height unchanged. Saved position (`windowPos`) preserved across the change — if the new width pushes the right edge offscreen, `SetClampedToScreen(true)` (already set) handles it.

### Enable checkbox

Unchanged. When unchecked, auto-swap on mount/dismount is suppressed; the manual button, keybind, and `/ms swap` continue to work.

### Empty-slot visual

Slots with one column filled and one empty show the empty side as `--` (greyed) — matches today's look. Reminds the user that the row is inactive (per the eligibility rule above).

## Manual Swap Button

A draggable floating frame, 32×32, parented to `UIParent`. Created at login (in the existing `ADDON_LOADED` callback path).

- **Texture:** `Interface\\Icons\\Ability_Mount_RidingHorse` (mount icon)
- **Position:** stored in `MountSpeedDB.settings.swapButtonPos` (account-wide). Default: center, offset down 100px so it's visible on first install but not in the way.
- **Visual state:**
  - `isMountSwapped == false` (wearing base) → full-color icon, tooltip "Switch to mount gear"
  - `isMountSwapped == true` (wearing mount) → desaturated icon + gold border overlay, tooltip "Switch to base gear"
- **Left click:** `Swap:Toggle()`
- **Drag:** repositions, saves new position on drag stop
- **Tooltip:** anchors right of cursor, shows "MountSpeed" header + current action

The button refreshes its visual state via the `DATA_UPDATED` callback (already fired on every state change).

## Keybind

Declared via WoW's standard binding globals:

```lua
BINDING_HEADER_MOUNTSPEED          = "MountSpeed"
BINDING_NAME_MOUNTSPEED_TOGGLE     = "Toggle mount/base gear"
```

An invisible `Button` named `MountSpeedToggleButton` with an `OnClick` handler that calls `Swap:Toggle()`. The binding appears in **Game Menu > Key Bindings > MountSpeed** for the user to assign.

No default key — avoids stomping existing bindings.

## Slash Commands

| Command | Action |
|---|---|
| `/ms` (or `/ms show` / `/ms toggle`) | Toggle main window — unchanged |
| `/ms settings` | Open settings — unchanged |
| `/ms swap` | **NEW** — `Swap:Toggle()` |
| `/ms capture` | **NEW** — capture current gear into `sets.base` |
| `/ms restore` | Force-equip `sets.base` (kept for muscle memory) |
| `/ms reset` | Wipe all data — unchanged |

## Version Bump

`1.0.1` → `2.0.0`. Major because:
1. SavedVariables schema breaks (`mountItems` → `sets.mount`, `savedEquipment` removed)
2. Behavior model changes (explicit base set vs. dynamic snapshot)

`Core.lua` `NS.version` and `MountSpeed.toc` `## Version` both updated. README and CHANGELOG entries follow at release time.

## Out of Scope

- Locking the floating button position
- More than 2 named loadouts
- Equipment slots beyond the existing 5
- Default keybind
- Sharing sets across characters

## File-Level Impact

| File | Change |
|---|---|
| `Core.lua` | New `CHAR_DEFAULTS` shape, migration block, two new slash commands, version bump |
| `Swap.lua` | Major rewrite: `Apply` + `Toggle`, drop snapshot machinery (~100 lines removed) |
| `UI.lua` | Row layout doubled (mount + base columns), capture button, header, width 520, floating swap button frame, keybind declarations |
| `Slots.lua` | No change |
| `MountSpeed.toc` | Version bump |
| `README.md` | Document new behavior, capture button, keybind |
| `CHANGELOG.md` | 2.0.0 entry at release time |
