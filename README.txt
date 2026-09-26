ODH VFX Addon

Modules:
- JumpCircle: Pulse Ring / Voxel Ripple
- Cubes
- LineGlyphs
- Wings (Prism)

Plugin-private assets:
- ixry_vfx_jumpcircle.png
- ixry_vfx_cube_glow.png
- ixry_vfx_wing_prism_left.png / right.png
- ixry_vfx_wing_prism_left_aura.png / right_aura.png
- ixry_vfx_lineglyph_dash.png
- ixry_vfx_lineglyph_glowdash.png
- ixry_vfx_lineglyph_glow_solid.png

LineGlyphs hard-dash renderer:
- no NumberSequence dash interpolation
- no camera BloomEffect bleed between dashes
- hard dash/gap mask matching Wraith 0.58 / 0.34 ratio
- transverse-only glow texture for a cleaner single-line appearance


Config persistence:
- Settings now save automatically to ODH_VFX_Addon_Data/config.json (prefers Ixry Shizuka/plugins/Workspace or plugins).
- Current ODH float sliders are used directly for Wings Offset X/Y/Z.

Online assets:
- The addon still ships local fallback assets in this pack.
- Arbitrary online asset download requires a repository/raw asset base URL to be configured in a future build.
