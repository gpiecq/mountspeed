# MountSpeed

A World of Warcraft: Burning Crusade Classic addon that automatically swaps your equipment when you mount or dismount. Configure mount speed items (Carrot on a Stick, Riding Crop, Mithril Spurs boots, etc.) and the addon handles the rest.

## Features

- Automatic equipment swap on mount/dismount
- Per-character configuration
- 5 configurable slots: Trinket 1, Trinket 2, Feet, Hands, Back
- Item selection via dropdown (bag scan) or drag & drop
- Saves your current gear before swapping, restores it on dismount
- Combat-safe: queues gear restore if dismounted in combat
- Minimap button (Carrot icon)
- No external dependencies (no Ace3, no LibStub)

## Installation

1. Download the latest release from [Releases](https://github.com/gpiecq/mountspeed/releases)
2. Extract `MountSpeed/` into `<WoW>/Interface/AddOns/`
3. Restart WoW or `/reload`

## Usage

| Command | Action |
|---------|--------|
| `/ms` | Toggle configuration window |
| `/ms hide` | Hide window |
| `/ms settings` | Open configuration |
| `/ms reset` | Reset all data (with confirmation) |

Or click the carrot icon on the minimap.

### Configuration

1. Open the config window (`/ms`)
2. For each slot, click **Set** to pick an item from your bags, or drag & drop an item onto the slot
3. Click **Clear** to remove a configured item
4. Toggle **Enable auto-swap** to activate/deactivate

### How it works

1. **You mount** — the addon saves your currently equipped items in the configured slots, then equips your mount speed items
2. **You dismount** — the addon restores your original equipment
3. **Dismount in combat** — the addon waits for combat to end, then restores automatically

## Compatibility

- WoW TBC Classic (Interface 20505)
- No required dependencies
