# Changelog

All notable changes to MountSpeed will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-05-03

### Changed
- **Breaking:** replaced single-set snapshot model with two explicit equipment
  sets — `Mount gear` and `Base gear`. The snapshot machinery (which tried to
  remember whatever you were wearing at mount time) is gone, eliminating the
  race conditions that could leave a character stuck in mount gear.
- Auto-swap on mount/dismount now switches between the two configured sets.
  Slots configured in only one column are skipped to prevent accidental
  undressing.
- Saved-variables schema: `mountItems` → `sets.{mount,base}`. Existing v1.x
  configurations are migrated automatically (old mount items move into
  `sets.mount`); a one-time in-game notice prompts users to populate the new
  Base set.
- Configuration window redesigned: dual-column layout (Mount | Base) with a
  custom dark item picker (SimpleRaidAssign aesthetic) replacing the native
  dropdown.
- Minimap right-click no longer triggers a manual swap — manual swapping is
  now done via the floating button, keybind, or `/ms swap`.

### Added
- Floating draggable swap button at center-screen, with a visual state
  indicator (desaturated + gold border = mount gear equipped; full color =
  base gear equipped). Position is saved account-wide. Can be hidden via the
  **Show floating swap button** checkbox at the top of the config window
  (keybind and `/ms swap` keep working when hidden).
- Key binding: **Toggle mount/base gear** (Game Menu → Key Bindings →
  MountSpeed).
- **Capture current gear** button: fills the Base set in one click from the
  items currently worn, with overwrite confirmation.
- Slash commands: `/ms swap` (manual toggle) and `/ms capture` (save current
  gear into the Base set).

### Removed
- Snapshot/`savedEquipment` machinery and the associated re-entry guards —
  obsolete now that both sets are explicit.

## [1.0.1] - 2026-04-20

### Fixed
- Mount-speed items could occasionally be saved as "original gear" and then
  re-equipped on dismount, leaving the character stuck with mount gear.
  Triggered by aura flicker, fast dismount/remount, or a logout/crash while
  mounted.

### Added
- Re-entry guard in `SaveAndEquip`: skip the snapshot when already in the
  swapped state.
- Per-slot defensive check: never record a configured mount-speed item as the
  slot's original gear.
- Login recovery: if `isMountSwapped` is still set but the character is not
  mounted at login, restore the saved gear automatically.

## [1.0.0] - 2026-04-19

### Added
- Automatic equipment swap on mount/dismount
- Per-character configuration with 5 slots: Trinket 1, Trinket 2, Feet, Hands, Back
- Configuration window with item selection via dropdown (bag scan) and drag & drop
- Combat-safe restore: queues gear restore if dismounted in combat
- Minimap button (carrot icon) to toggle config window
- Slash commands `/ms` and `/mountspeed`
- Saved variables: account-wide window settings, per-character item config
- C_Container API compatibility for modern WoW clients
