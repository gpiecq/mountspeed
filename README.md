# MountSpeed

A World of Warcraft: Burning Crusade Classic addon that swaps between two configured equipment sets — your **Mount gear** (e.g. Carrot on a Stick, Riding Crop, Mithril Spurs) and your **Base gear** (your normal outfit). Auto-swaps on mount/dismount, with a manual button and keybind for explicit control.

## Features

- Two explicitly configured equipment sets: Mount + Base
- Auto-swap on mount / dismount (no more snapshot races)
- Floating draggable swap button + key binding for manual toggling
- "Capture current" — fill the Base set in one click from your currently worn items
- Custom dark item picker UI (matches SimpleRaidAssign aesthetic)
- 5 configurable slots: Trinket 1, Trinket 2, Feet, Hands, Back
- Per-character configuration
- Combat-safe: queues swap until combat ends
- Taxi-safe: ignores flight-master rides
- Minimap button (Carrot icon)
- No external dependencies (no Ace3, no LibStub)

## Installation

1. Download the latest release from [Releases](https://github.com/gpiecq/mountspeed/releases)
2. Extract `MountSpeed/` into `<WoW>/Interface/AddOns/`
3. Restart WoW or `/reload`

## First-time setup (or upgrading from v1.x)

1. Open the config window: `/ms` (or click the minimap carrot)
2. **Mount gear** column — for each slot, click **Set** to pick a mount-speed item from your bags
3. **Base gear** column — equip your normal outfit, then click **Capture current** at the top right of the window. This fills the Base column with what you're wearing.
4. Done. Mount up to verify the swap fires.

If you upgraded from v1.x and your Mount gear was already configured, the addon migrates it automatically — you only need to set up Base gear.

## Usage

| Command | Action |
|---------|--------|
| `/ms` | Toggle configuration window |
| `/ms hide` | Hide window |
| `/ms settings` | Open configuration |
| `/ms swap` | Manually toggle between mount and base gear |
| `/ms capture` | Save your currently worn gear into the Base set |
| `/ms reset` | Reset all data (with confirmation) |

### Floating swap button

A small mount icon appears at center-screen on first install. Drag it anywhere — its position is saved per account.

- **Click**: toggle between mount and base gear
- **Visual state**: desaturated icon + gold border = wearing mount gear; full color = wearing base gear
- **Hide it**: uncheck **Show floating swap button** at the top of the config window — the keybind and `/ms swap` keep working

### Keybind

Game Menu (Esc) → Key Bindings → scroll to **MountSpeed** → bind a key to **Toggle mount/base gear**. Pressing the key has the same effect as the floating button.

### Minimap button

- **Left-click**: toggle the configuration window
- (No right-click action in v2.0 — manual swapping is the floating button or keybind)

## How it works

1. **Mount up** — auto-swap equips your Mount gear (slots configured in BOTH columns only — slots configured in only one column are skipped to prevent accidental undressing)
2. **Dismount** — auto-swap re-equips your Base gear
3. **Dismount in combat** — the swap is queued; it fires automatically when combat ends
4. **Manual override** — the floating button, keybind, or `/ms swap` triggers the swap regardless of mount state

## Compatibility

- WoW Classic Anniversary / TBC Classic (Interface 20505)
- No required dependencies
