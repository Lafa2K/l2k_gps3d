# l2k_gps3d

3D GPS ribbon renderer focused on two route sources:

- `USER` = player waypoint
- `MISSION` = active routed blip from another script

`multi` stays disabled by default and is ignored when `Config.routeSources.multi = false`.

The geo animation module is now bundled inside this same resource. No separate `l2k_geoanim` dependency is required.

## Commands

- `/gps3d`
  Toggle the 3D GPS on or off.

- `/gps3d_route manual`
  Force `USER` mode.

- `/gps3d_route blip`
  Force `MISSION` mode if a routed blip exists.

- `/gps3d_route toggle`
  Switch between `USER` and `MISSION`.

- `/gps3d_route status`
  Show current source, preset and route state.

- `/gpspreset index|next|prev|status`
  Change or inspect the current ribbon preset.

- `/gpscolordefault r g b [a]`
  Set the `USER` route color.

- `/gpscolormission r g b [a]`
  Set the `MISSION` route color.

- `/geoanim`
- `/geoanim on`
- `/geoanim shutdown`
- `/geoanim off`
- `/geoanim status`
  Control the bundled AR animation module manually when needed.

## Shortcuts

All shortcuts require an allowed vehicle and can be disabled in the config.

- `SHIFT + UP`
  Switch between `USER` and `MISSION`.
- `SHIFT + E`
  Cycle the color of the current route source.
- `SHIFT + LEFT / RIGHT`
  Cycle the ribbon preset.
- `SHIFT + DOWN`
  Toggle the 3D GPS with cooldown protection when re-enabling.
- `SHIFT + K`
  Toggle extra geo animations used by GPS mode changes. This also resets the one-shot intro animation so it can be shown again later.

## Presets

Presets only change the ribbon style:

- texture dictionary
- texture name

They do not overwrite the colors chosen for `USER` and `MISSION`.

## External Blip Capture

If another script already does:

```lua
local blip = AddBlipForCoord(x, y, z)
SetBlipRoute(blip, true)
```

`l2k_gps3d` can capture that route automatically when:

```lua
Config.enableExternalBlipRouteCapture = true
```

## Route Safety

`l2k_gps3d` is designed to be non-intrusive.

- It reads routes that already exist in the game.
- It does not own external waypoint or mission route creation.
- It does not clear external routed blips.
- It does not refresh or rebuild another script's GPS logic.
- It only decides which available route the 3D ribbon should follow.

This means another resource can keep handling:

- `SetBlipRoute(blip, true)`
- waypoint creation
- mission flow
- delivery flow
- race checkpoints

while `l2k_gps3d` only adds the 3D visual layer on top.

## Exports

### `SetEnabled(enabled)`

```lua
exports.l2k_gps3d:SetEnabled(true)
```

### `SetActiveRouteSource(source)`

```lua
exports.l2k_gps3d:SetActiveRouteSource('manual')
exports.l2k_gps3d:SetActiveRouteSource('blip')
```

### `SetTrackedBlip(blip)`

```lua
exports.l2k_gps3d:SetTrackedBlip(blip)
```

### `ClearTrackedBlip()`

```lua
exports.l2k_gps3d:ClearTrackedBlip()
```

### `SetRoutePreset(index)`

```lua
exports.l2k_gps3d:SetRoutePreset(2)
```

### `SetDefaultRouteColor(r, g, b, a)`

```lua
exports.l2k_gps3d:SetDefaultRouteColor(255, 255, 255, 205)
```

### `SetMissionRouteColor(r, g, b, a)`

```lua
exports.l2k_gps3d:SetMissionRouteColor(255, 214, 64, 215)
```

### Bundled GeoAnim Exports

These are now exposed by the same `l2k_gps3d` resource:

```lua
exports.l2k_gps3d:PlayProfile('on', vehicle)
exports.l2k_gps3d:PlayProfile('on_fast', vehicle)
exports.l2k_gps3d:PlayProfile('off', vehicle)
exports.l2k_gps3d:StopExtraAnimations()
```

## Notes

- External blip routes are not cleared by this resource.
- Route commands and shortcuts affect only the 3D ribbon, colors, presets and bundled visual effects.
- Boat and plane classes are ignored by default.
- The ribbon uses speed-based sampling and distance limits for lighter runtime at high speed.
- The first large GPS intro plays once, then later activations use a faster `on_fast` profile until you reset it with `SHIFT + K`.

## Credit

If you use this resource as a base for your own project, please provide visible credit to the original project and author. It would be greatly appreciated.
