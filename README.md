# ODH VFX Addon

Overdrive H visual-effects addon.

## Required repository layout

```text
ODH-VFX-Addon/
├─ ODH_VFX_Addon.lua
├─ manifest.json
└─ assets/
   ├─ ixry_vfx_jumpcircle.png
   ├─ ixry_vfx_cube_glow.png
   ├─ ixry_vfx_wing_prism_left.png
   ├─ ixry_vfx_wing_prism_right.png
   ├─ ixry_vfx_wing_prism_left_aura.png
   ├─ ixry_vfx_wing_prism_right_aura.png
   ├─ ixry_vfx_lineglyph_dash.png
   ├─ ixry_vfx_lineglyph_glowdash.png
   └─ ixry_vfx_lineglyph_glow_solid.png
```

The addon downloads PNGs from this repository and caches them locally before calling `getcustomasset` / `getsynasset`. Users only need the addon Lua; they do not need to manually copy PNG files.

## Asset cache updates

When any PNG changes, increment `assetsVersion` in `manifest.json`. The addon tracks the version per cached file and downloads the new file automatically.

## Persistent config

Settings are saved to a plugin-private `ODH_VFX_Addon_Data/config.json` folder under the ODH workspace when file APIs are available.

## ODH

The file intentionally does not use `loadstring()`.
