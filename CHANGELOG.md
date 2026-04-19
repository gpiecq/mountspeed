# Changelog

All notable changes to MountSpeed will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
