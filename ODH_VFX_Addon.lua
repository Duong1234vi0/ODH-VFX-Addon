--> Overdrive H On Top.
--> VFX Addon: JumpCircle + Wraith Cubes + Wraith Wings + Wraith LineGlyphs

local shared = odh_shared_plugins

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    return
end

local function getRuntimeEnv()
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" then
            return env
        end
    end
    return _G
end

local ENV = getRuntimeEnv()
local ADDON_RUNTIME_KEY = "__ODH_VFX_AddonRuntime"

if ENV[ADDON_RUNTIME_KEY] and type(ENV[ADDON_RUNTIME_KEY].Cleanup) == "function" then
    pcall(ENV[ADDON_RUNTIME_KEY].Cleanup)
end

local function disconnect(connection)
    if connection then
        connection:Disconnect()
    end
end

local function notify(text, duration)
    if shared and type(shared.Notify) == "function" then
        pcall(shared.Notify, text, duration or 2)
    end
end

local function getLocalAssetLoader()
    if type(getcustomasset) == "function" then
        return getcustomasset
    end
    if type(getsynasset) == "function" then
        return getsynasset
    end
    if type(syn) == "table" and type(syn.getcustomasset) == "function" then
        return syn.getcustomasset
    end
    if type(ENV.getcustomasset) == "function" then
        return ENV.getcustomasset
    end
    if type(ENV.getsynasset) == "function" then
        return ENV.getsynasset
    end
    return nil
end

local function normalizeFsPath(path)
    return tostring(path or "")
        :gsub("\\", "/")
        :gsub("/+", "/")
end

local function assetBasename(path)
    path = normalizeFsPath(path)
    return path:match("([^/]+)$") or path
end

local function collectAssetCandidates(primaryPath, fallbacks)
    local result = {}
    local seen = {}

    local function add(path)
        if type(path) ~= "string" or path == "" then
            return
        end

        path = normalizeFsPath(path)

        local function push(value)
            if value ~= "" and not seen[value] then
                seen[value] = true
                result[#result + 1] = value
            end
        end

        push(path)
        if path:sub(1, 2) == "./" then
            push(path:sub(3))
        elseif path:sub(1, 1) ~= "/" then
            push("./" .. path)
        end
    end

    local filename = assetBasename(primaryPath)

    -- IMPORTANT: plugin-private assets only.
    -- Do NOT search ./Ixry Shizuka/assets/: that directory belongs to ODH itself
    -- and may contain unrelated files named circle.png / glow.png.
    local privateDirs = {
        ".",
        "./ODH_VFX_Addon_Assets",
        "./Ixry Shizuka/plugins/Workspace",
        "./Ixry Shizuka/plugins/Workspace/ODH_VFX_Addon_Assets",
        "./Ixry Shizuka/plugins",
        "./Ixry Shizuka/plugins/ODH_VFX_Addon_Assets",
    }

    for _, dir in ipairs(privateDirs) do
        if dir == "." then
            add("./" .. filename)
        else
            add(dir .. "/" .. filename)
        end
    end

    add(primaryPath)
    for _, path in ipairs(fallbacks or {}) do
        add(path)
    end

    return result
end

local function tryLoadAsset(primaryPath, fallbacks)
    local loader = getLocalAssetLoader()
    if not loader then
        return nil, nil
    end

    local candidates = collectAssetCandidates(primaryPath, fallbacks)

    for _, path in ipairs(candidates) do
        -- Do not trust isfile() as the sole authority: several executors expose
        -- different relative-path semantics to isfile and getcustomasset.
        local exists = nil
        if type(isfile) == "function" then
            local ok, value = pcall(isfile, path)
            if ok then
                exists = value == true
            end
        end

        if exists ~= false then
            local ok, asset = pcall(loader, path)
            if ok and type(asset) == "string" and asset ~= "" then
                return asset, path
            end
        else
            -- One last loader attempt even when isfile reports false; harmless
            -- under pcall and fixes executors where "./x" vs "x" differs.
            local ok, asset = pcall(loader, path)
            if ok and type(asset) == "string" and asset ~= "" then
                return asset, path
            end
        end
    end

    return nil, nil
end

-- ============================================================================
-- JumpCircle module
-- Modes:
--   V-Core    -> texture jump ring ported from V-Core.
--   HitEffect -> Wraith/LiquidBounce HitEffect terrain-block wave adapted to
--                Roblox and triggered by jumping instead of AttackEntityEvent.
-- ============================================================================

local JumpCircle = {
    Enabled = false,
    Config = {
        Mode = "V-Core",

        -- V-Core texture mode
        AssetPath = "ixry_vfx_jumpcircle.png",
        EaseOut = true,
        RotateSpeed = 2.0,
        CircleScale = 1.0,
        RadiusMultiplier = 3.0,
        Color = Color3.fromRGB(255, 255, 255),
        GlowLayerAlpha = 0.65,
        Brightness = 2.0,
        AlwaysOnTop = false,
        -- SurfaceGui has its own distance culling. Keep it very high so
        -- camera zoom does not make an active ring disappear.
        GuiMaxDistance = 100000,
        AlignToGroundNormal = true,
        GroundOffset = 0.025,
        RaycastDistance = 9,
        PartThickness = 0.01,
        SmoothFinalFade = true,
        FinalFadeTime = 0.35,
        JumpCooldown = 0.12,

        -- Wraith HitEffect mode. Defaults mirror ModuleHitEffect.kt:
        -- DURATION_MS=2000, MAX_RADIUS=8, RING_THICKNESS=0.8,
        -- SEARCH_HEIGHT=10, MAX_BLOCKS_PER_WAVE_FRAME=400.
        HitEffectDuration = 2.0,
        HitEffectMaxRadius = 8.0,
        HitEffectRingThickness = 0.8,
        HitEffectSearchHeight = 10,
        HitEffectMaxCells = 400,
        -- Minecraft block -> Roblox stud adaptation, same approximate scale
        -- used by the Cubes port. CircleScale multiplies the whole wave.
        HitEffectWorldScale = 2.75,
        -- Keep each voxel flush with the sampling grid so adjacent cells touch.
        -- Do not independently scale the cell geometry: that creates visible gaps.
        HitEffectCellInset = 0.0,
        HitEffectCellHeight = 0.92,
        HitEffectFill = true,
        HitEffectFillStrength = 0.10,
        HitEffectLineBase = 0.018,
        HitEffectLineBoost = 0.045,
        HitEffectSurfaceOffset = 0.012,
    },
}

JumpCircle._effects = {}
JumpCircle._folder = nil
JumpCircle._asset = nil
JumpCircle._renderConnection = nil
JumpCircle._stateConnection = nil
JumpCircle._characterConnection = nil
JumpCircle._lastJump = 0

function JumpCircle:_loadAsset()
    if self._asset then
        return self._asset
    end

    local asset, resolvedPath = tryLoadAsset(self.Config.AssetPath, {
        "ODH_VFX_Addon_Assets/ixry_vfx_jumpcircle.png",
    })

    self._asset = asset
    self._assetResolvedPath = resolvedPath
    return asset
end

function JumpCircle:_ensureFolder()
    if self._folder and self._folder.Parent then
        return self._folder
    end

    local oldNames = {
        "_ODH_JumpCircleTexture",
        "_ODH_JumpCircleEffects",
    }
    for _, name in ipairs(oldNames) do
        local old = Workspace:FindFirstChild(name)
        if old then
            old:Destroy()
        end
    end

    local folder = Instance.new("Folder")
    folder.Name = "_ODH_JumpCircleEffects"
    folder.Parent = Workspace
    self._folder = folder
    return folder
end

function JumpCircle:_destroyEffect(effect)
    if not effect then
        return
    end

    local root = effect.Root or effect.Part or effect.Container
    if root and root.Parent then
        root:Destroy()
    end
end

function JumpCircle:Clear()
    for i = #self._effects, 1, -1 do
        self:_destroyEffect(self._effects[i])
        self._effects[i] = nil
    end
end

local function frameFromNormal(position, normal)
    local up = normal
    if not up or up.Magnitude < 0.001 then
        up = Vector3.new(0, 1, 0)
    else
        up = up.Unit
    end

    local worldForward = Vector3.new(0, 0, -1)
    local right = worldForward:Cross(up)
    if right.Magnitude < 0.001 then
        right = Vector3.new(1, 0, 0)
    else
        right = right.Unit
    end

    local back = right:Cross(up)
    if back.Magnitude < 0.001 then
        back = Vector3.new(0, 0, 1)
    else
        back = back.Unit
    end

    return CFrame.fromMatrix(position, right, up, back)
end

function JumpCircle:_groundFrame(character, root)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character, self:_ensureFolder()}
    params.IgnoreWater = false

    local result = Workspace:Raycast(
        root.Position,
        Vector3.new(0, -self.Config.RaycastDistance, 0),
        params
    )

    if result then
        local position = result.Position
        local up = self.Config.AlignToGroundNormal and result.Normal.Unit or Vector3.new(0, 1, 0)
        position = position + up * self.Config.GroundOffset
        return frameFromNormal(position, up), result
    end

    local position = Vector3.new(
        root.Position.X,
        math.floor(root.Position.Y - 2.8) + self.Config.GroundOffset,
        root.Position.Z
    )
    return CFrame.new(position), nil
end

-- --------------------------------------------------------------------------
-- V-Core texture mode
-- --------------------------------------------------------------------------

function JumpCircle:_makeImage(parent, zIndex)
    local image = Instance.new("ImageLabel")
    image.Name = zIndex == 1 and "Glow" or "Core"
    image.BackgroundTransparency = 1
    image.BorderSizePixel = 0
    image.Position = UDim2.fromScale(0, 0)
    image.Size = UDim2.fromScale(1, 1)
    image.Image = self._asset
    image.ImageColor3 = self.Config.Color
    image.ImageTransparency = 1
    image.ScaleType = Enum.ScaleType.Stretch
    image.ZIndex = zIndex
    image.Parent = parent
    return image
end

function JumpCircle:_makeRing(frame)
    local part = Instance.new("Part")
    part.Name = "JumpCircleTexture"
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Transparency = 1
    part.Size = Vector3.new(0.05, self.Config.PartThickness, 0.05)
    part.CFrame = frame
    part.Parent = self:_ensureFolder()

    local surface = Instance.new("SurfaceGui")
    surface.Name = "CircleSurface"
    surface.Face = Enum.NormalId.Top
    surface.AlwaysOnTop = self.Config.AlwaysOnTop
    surface.LightInfluence = 0
    pcall(function()
        surface.MaxDistance = self.Config.GuiMaxDistance
    end)
    pcall(function()
        surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
    end)
    surface.CanvasSize = Vector2.new(1024, 1024)
    surface.Parent = part

    pcall(function()
        surface.Brightness = self.Config.Brightness
    end)

    local glow = self:_makeImage(surface, 1)
    local core = self:_makeImage(surface, 2)
    return part, glow, core
end

function JumpCircle:_spawnTexture(character, root, now)
    if not self._asset and not self:_loadAsset() then
        notify("JumpCircle: ixry_vfx_jumpcircle.png not found", 4)
        return
    end

    local frame = self:_groundFrame(character, root)
    local part, glow, core = self:_makeRing(frame)

    self._effects[#self._effects + 1] = {
        Kind = "V-Core",
        Root = part,
        Part = part,
        Glow = glow,
        Core = core,
        StartedAt = now,
        Lifetime = self.Config.EaseOut and 5.0 or 6.0,
        EaseOut = self.Config.EaseOut,
        RotateSpeed = self.Config.RotateSpeed,
        Scale = self.Config.CircleScale,
        Color = self.Config.Color,
    }
end

function JumpCircle:_texturePulse(effect, elapsed)
    local speed = effect.EaseOut and 2.0 or 1.0
    local x = 1.0 - (elapsed * speed / 5.0)
    return math.clamp(1.0 - (x ^ 4), 0, 1)
end

function JumpCircle:_updateTextureEffect(effect, elapsed)
    local pulse = self:_texturePulse(effect, elapsed)
    local sizeAnim = pulse * effect.Scale
    local radius = math.max(0.01, self.Config.RadiusMultiplier * sizeAnim)
    local diameter = radius * 2

    effect.Part.Size = Vector3.new(diameter, self.Config.PartThickness, diameter)

    local rotation = (pulse * effect.RotateSpeed * 1000) % 360
    effect.Glow.Rotation = rotation
    effect.Core.Rotation = rotation

    local alpha = math.clamp(1 - (elapsed / 6.0), 0, 1)
    if self.Config.SmoothFinalFade then
        local remaining = effect.Lifetime - elapsed
        local finalFade = math.clamp(
            remaining / math.max(self.Config.FinalFadeTime, 0.001),
            0,
            1
        )
        alpha = math.min(alpha, finalFade)
    end

    effect.Glow.ImageColor3 = effect.Color
    effect.Core.ImageColor3 = effect.Color
    effect.Glow.ImageTransparency = 1 - math.clamp(alpha * self.Config.GlowLayerAlpha, 0, 1)
    effect.Core.ImageTransparency = 1 - alpha
end

-- --------------------------------------------------------------------------
-- Wraith HitEffect mode
-- Source semantics preserved:
--   duration 2s, easeOutCubic radius, 0.8 ring thickness, smooth fade,
--   local alpha squared, 10% translucent fill and bright block outline.
-- The original is triggered by AttackEntityEvent at the target block. Because
-- this is a JumpCircle mode, the center is the block/cell under LocalPlayer
-- when they jump.
-- --------------------------------------------------------------------------

function JumpCircle:_hitEaseOutCubic(t)
    t = math.clamp(t, 0, 1)
    return 1 - ((1 - t) ^ 3)
end

function JumpCircle:_hitSmoothAlpha(progress)
    progress = math.clamp(progress, 0, 1)
    local fadeIn = math.min(1, progress / 0.1)
    fadeIn = fadeIn * fadeIn * (3 - 2 * fadeIn)
    local fadeOut = (1 - progress) ^ 4.8
    return fadeIn * fadeOut
end

function JumpCircle:_sampleHitCells(character, centerPosition, worldCellSize, container)
    local maxRadius = math.max(1, math.floor(self.Config.HitEffectMaxRadius + 0.5))
    local thickness = math.max(0.05, self.Config.HitEffectRingThickness)
    local searchHeight = math.max(1, self.Config.HitEffectSearchHeight)
    local samples = {}

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {character, self:_ensureFolder(), container}
    params.IgnoreWater = false

    local castHeight = searchHeight * worldCellSize
    local castLength = castHeight * 2 + worldCellSize * 2
    for gx = -maxRadius, maxRadius do
        for gz = -maxRadius, maxRadius do
            local radialDistance = math.sqrt(gx * gx + gz * gz)
            if radialDistance <= maxRadius + thickness then
                local x = centerPosition.X + gx * worldCellSize
                local z = centerPosition.Z + gz * worldCellSize
                local origin = Vector3.new(x, centerPosition.Y + castHeight, z)
                local result = Workspace:Raycast(
                    origin,
                    Vector3.new(0, -castLength, 0),
                    params
                )

                if result then
                    samples[#samples + 1] = {
                        GX = gx,
                        GZ = gz,
                        Distance = radialDistance,
                        HitPosition = result.Position,
                        Normal = result.Normal,
                    }
                end
            end
        end
    end

    return samples
end

function JumpCircle:_makeHitCell(effect, sample, index)
    local worldCellSize = effect.WorldCellSize
    local inset = math.clamp(self.Config.HitEffectCellInset, 0, 0.45)
    -- Cell footprint follows the grid spacing 1:1 so neighboring voxels remain
    -- flush with each other instead of separating when a visual scale is reduced.
    local side = math.max(0.05, worldCellSize * (1 - inset))
    local height = math.max(0.04, worldCellSize * self.Config.HitEffectCellHeight)

    local up = self.Config.AlignToGroundNormal and sample.Normal or Vector3.new(0, 1, 0)
    if not up or up.Magnitude < 0.001 then
        up = Vector3.new(0, 1, 0)
    else
        up = up.Unit
    end

    -- Sink most of the proxy block below the sampled surface. This matches the
    -- original renderer outlining the existing terrain block instead of placing
    -- a new cube on top of it, while the tiny positive offset avoids z-fighting.
    local topPosition = sample.HitPosition + up * self.Config.HitEffectSurfaceOffset
    local center = topPosition - up * (height * 0.5)
    local frame = frameFromNormal(center, up)

    local part = Instance.new("Part")
    part.Name = "HitCell" .. tostring(index)
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Material = Enum.Material.SmoothPlastic
    part.Color = effect.Color
    part.Transparency = 1
    part.Size = Vector3.new(side, height, side)
    part.CFrame = frame
    part.Parent = effect.Root

    local outline = Instance.new("SelectionBox")
    outline.Name = "Outline"
    outline.Adornee = part
    outline.Color3 = effect.Color
    outline.SurfaceColor3 = effect.Color
    outline.SurfaceTransparency = 1
    outline.Transparency = 1
    outline.LineThickness = self.Config.HitEffectLineBase
    outline.Parent = part

    local visual = {
        Part = part,
        Outline = outline,
    }
    effect.Visuals[index] = visual
    return visual
end

function JumpCircle:_spawnHitEffect(character, root, now)
    local centerFrame = self:_groundFrame(character, root)
    local scale = math.max(0.05, self.Config.CircleScale)
    local worldCellSize = math.max(0.1, self.Config.HitEffectWorldScale * scale)

    local model = Instance.new("Model")
    model.Name = "JumpHitEffectWave"
    model.Parent = self:_ensureFolder()

    local effect = {
        Kind = "HitEffect",
        Root = model,
        StartedAt = now,
        Lifetime = math.max(0.1, self.Config.HitEffectDuration),
        Color = self.Config.Color,
        WorldCellSize = worldCellSize,
        Visuals = {},
    }

    effect.Samples = self:_sampleHitCells(
        character,
        centerFrame.Position,
        worldCellSize,
        model
    )

    self._effects[#self._effects + 1] = effect
end

function JumpCircle:_updateHitEffect(effect, elapsed)
    local progress = math.clamp(elapsed / math.max(effect.Lifetime, 0.001), 0, 1)
    local globalAlpha = self:_hitSmoothAlpha(progress)
    local currentRadius = self:_hitEaseOutCubic(progress) * self.Config.HitEffectMaxRadius
    local ringThickness = math.max(0.05, self.Config.HitEffectRingThickness)
    local rendered = 0
    local renderLimit = math.max(1, math.floor(self.Config.HitEffectMaxCells))

    for index, sample in ipairs(effect.Samples or {}) do
        local diff = math.abs(sample.Distance - currentRadius)
        local localAlpha = 0

        if diff <= ringThickness and globalAlpha > 0.01 then
            localAlpha = 1.1 - (diff / ringThickness)
            localAlpha = localAlpha * localAlpha
            localAlpha = math.clamp(localAlpha * globalAlpha, 0, 1)
        end

        local visual = effect.Visuals[index]
        if localAlpha > 0.015 and rendered < renderLimit then
            rendered = rendered + 1
            if not visual or not visual.Part or not visual.Part.Parent then
                visual = self:_makeHitCell(effect, sample, index)
            end

            local color = effect.Color
            visual.Part.Color = color
            if self.Config.HitEffectFill then
                visual.Part.Transparency = 1 - math.clamp(
                    localAlpha * self.Config.HitEffectFillStrength,
                    0,
                    1
                )
            else
                visual.Part.Transparency = 1
            end

            visual.Outline.Color3 = color
            visual.Outline.SurfaceColor3 = color
            visual.Outline.Transparency = 1 - localAlpha
            visual.Outline.LineThickness = self.Config.HitEffectLineBase
                + localAlpha * self.Config.HitEffectLineBoost
        elseif visual then
            visual.Part.Transparency = 1
            visual.Outline.Transparency = 1
        end
    end
end

function JumpCircle:Spawn(character)
    if not self.Enabled then
        return
    end

    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end

    local now = os.clock()
    if now - self._lastJump < self.Config.JumpCooldown then
        return
    end
    self._lastJump = now

    if self.Config.Mode == "HitEffect" then
        self:_spawnHitEffect(character, root, now)
    else
        self:_spawnTexture(character, root, now)
    end
end

function JumpCircle:_update()
    local now = os.clock()

    for i = #self._effects, 1, -1 do
        local effect = self._effects[i]
        local elapsed = now - effect.StartedAt
        local root = effect.Root or effect.Part

        if elapsed >= effect.Lifetime
            or not root
            or not root.Parent then

            self:_destroyEffect(effect)
            table.remove(self._effects, i)
        else
            if effect.Kind == "HitEffect" then
                self:_updateHitEffect(effect, elapsed)
            else
                self:_updateTextureEffect(effect, elapsed)
            end
        end
    end
end

function JumpCircle:_bindCharacter(character)
    disconnect(self._stateConnection)
    self._stateConnection = nil

    if not self.Enabled then
        return
    end

    local humanoid = character:WaitForChild("Humanoid", 8)
    if not humanoid or not self.Enabled then
        return
    end

    self._stateConnection = humanoid.StateChanged:Connect(function(_, newState)
        if self.Enabled and newState == Enum.HumanoidStateType.Jumping then
            self:Spawn(character)
        end
    end)
end

function JumpCircle:Enable()
    if self.Enabled then
        return true
    end

    -- HitEffect is geometry-only and needs no texture asset.
    if self.Config.Mode ~= "HitEffect" and not self:_loadAsset() then
        notify("JumpCircle: ixry_vfx_jumpcircle.png not found", 4)
        return false
    end

    self.Enabled = true
    self:_ensureFolder()

    if LocalPlayer.Character then
        task.spawn(function()
            self:_bindCharacter(LocalPlayer.Character)
        end)
    end

    self._characterConnection = LocalPlayer.CharacterAdded:Connect(function(character)
        self:Clear()
        task.spawn(function()
            self:_bindCharacter(character)
        end)
    end)

    self._renderConnection = RunService.RenderStepped:Connect(function()
        if self.Enabled then
            self:_update()
        end
    end)

    return true
end

function JumpCircle:Disable()
    if not self.Enabled then
        return
    end

    self.Enabled = false
    disconnect(self._renderConnection)
    disconnect(self._stateConnection)
    disconnect(self._characterConnection)

    self._renderConnection = nil
    self._stateConnection = nil
    self._characterConnection = nil

    self:Clear()

    if self._folder and self._folder.Parent then
        self._folder:Destroy()
    end
    self._folder = nil
end

function JumpCircle:Cleanup()
    self:Disable()
end

-- ============================================================================
-- Wraith Cubes module
-- ============================================================================

local Cubes = {
    Enabled = false,
    Config = {
        Animation = "Scatter",
        Count = 30,
        Size = 1.0,
        Speed = 1.0,
        Color = Color3.fromRGB(105, 170, 255),
        WorldScale = 2.75,
        FaceMaterial = Enum.Material.Neon,
        EdgeThickness = 0.035,
        GlowEnabled = true,
        -- Wraith renders glow with no depth stencil. Keep Roblox BillboardGui
        -- AlwaysOnTop to avoid self-occlusion / transparent depth-sort flicker.
        GlowNoDepth = true,
        -- Roblox BillboardGui has its own distance limit. Keep it high so
        -- zooming the third-person camera cannot hide the glow.
        GuiMaxDistance = 100000,
        -- Do not fade particles based on camera distance. Cubes are simulated
        -- around the character, not around the camera. Roblox can cull offscreen
        -- geometry on its own.
        ManualCameraCulling = false,
        DashedEdges = true,
        OutlineAlwaysOnTop = true,
        GlowAssetPath = "ixry_vfx_cube_glow.png",
        UpdateRate = 30,
    },
}

local CUBE_RULES = {
    SPAWN_RADIUS = 12,
    BASE_SIZE = 0.18,
    BASE_SPEED = 0.25,
    GLOW_MULTIPLIER = 1.7,
    MAX_RENDER_DISTANCE_SQ = 900,
    RAY_RANGE = 128,
    RAY_DISTANCE_SQ = 1.32,
    IMPULSE_FORCE = 0.08,
    IMPULSE_VERTICAL = 0.02,
    GLOW_SCALES = {10, 6, 3.5},
    GLOW_ALPHAS = {0.06, 0.14, 0.25},
}

local CUBE_CORNERS = {
    Vector3.new(-1, -1, -1),
    Vector3.new( 1, -1, -1),
    Vector3.new( 1, -1,  1),
    Vector3.new(-1, -1,  1),
    Vector3.new(-1,  1, -1),
    Vector3.new( 1,  1, -1),
    Vector3.new( 1,  1,  1),
    Vector3.new(-1,  1,  1),
}

local CUBE_EDGES = {
    {1,2}, {2,3}, {3,4}, {4,1},
    {5,6}, {6,7}, {7,8}, {8,5},
    {1,5}, {2,6}, {3,7}, {4,8},
}

Cubes._particles = {}
Cubes._folder = nil
Cubes._renderConnection = nil
Cubes._inputConnection = nil
Cubes._characterConnection = nil
Cubes._accumulator = 0
Cubes._glowAsset = nil
Cubes._camera = Workspace.CurrentCamera

local function randomRange(a, b)
    return a + math.random() * (b - a)
end

local function clamp01(x)
    return math.clamp(x, 0, 1)
end

local function brighten(color, mult)
    return Color3.new(
        math.min(1, color.R * mult),
        math.min(1, color.G * mult),
        math.min(1, color.B * mult)
    )
end

function Cubes:_loadAssets()
    if self._glowAsset then
        return
    end

    local asset, resolvedPath = tryLoadAsset(self.Config.GlowAssetPath, {
        "ODH_VFX_Addon_Assets/ixry_vfx_cube_glow.png",
    })

    self._glowAsset = asset
    self._glowAssetResolvedPath = resolvedPath
end

function Cubes:_ensureFolder()
    if self._folder and self._folder.Parent then
        return self._folder
    end

    local old = Workspace:FindFirstChild("_ODH_WraithCubes")
    if old then
        old:Destroy()
    end

    local folder = Instance.new("Folder")
    folder.Name = "_ODH_WraithCubes"
    folder.Parent = Workspace
    self._folder = folder
    return folder
end

function Cubes:_halfSize()
    return CUBE_RULES.BASE_SIZE
        * math.clamp(self.Config.Size, 0.1, 3.0)
        * self.Config.WorldScale
end

function Cubes:_makeGlow(body, halfSize)
    if not self.Config.GlowEnabled or not self._glowAsset then
        return nil, {}
    end

    local largest = halfSize
        * CUBE_RULES.GLOW_SCALES[1]
        * CUBE_RULES.GLOW_MULTIPLIER

    local gui = Instance.new("BillboardGui")
    gui.Name = "Glow"
    gui.Adornee = body
    -- Wraith's glow pipeline has no depth stencil. In Roblox, leaving this
    -- false lets the billboard intersect the rotating cube and be depth-sorted
    -- against transparent faces, which appears as rapid blinking/flicker.
    gui.AlwaysOnTop = self.Config.GlowNoDepth ~= false
    gui.LightInfluence = 0
    pcall(function()
        gui.MaxDistance = self.Config.GuiMaxDistance
    end)
    gui.Size = UDim2.new(largest, 0, largest, 0)
    gui.Parent = body

    local layers = {}
    for i, scale in ipairs(CUBE_RULES.GLOW_SCALES) do
        local image = Instance.new("ImageLabel")
        image.Name = "GlowLayer" .. i
        image.AnchorPoint = Vector2.new(0.5, 0.5)
        image.Position = UDim2.fromScale(0.5, 0.5)

        local ratio = scale / CUBE_RULES.GLOW_SCALES[1]
        image.Size = UDim2.fromScale(ratio, ratio)
        image.BackgroundTransparency = 1
        image.BorderSizePixel = 0
        image.Image = self._glowAsset
        image.ImageColor3 = self.Config.Color
        image.ImageTransparency = 1
        image.ZIndex = i
        image.Parent = gui
        layers[i] = image
    end

    return gui, layers
end

function Cubes:_makeEdges(body, halfSize)
    local visuals = {}
    local edgeColor = brighten(self.Config.Color, 1.5)
    local thickness = math.max(0.012, self.Config.EdgeThickness * self.Config.WorldScale)
    local overlap = math.max(0, thickness * 0.35)

    local function addSegment(localA, localB, edgeIndex, segmentIndex)
        local delta = localB - localA
        local length = delta.Magnitude
        if length <= 1e-4 then
            return
        end

        local mid = (localA + localB) * 0.5
        local adornment = Instance.new("BoxHandleAdornment")
        adornment.Name = string.format("Edge%d_%d", edgeIndex, segmentIndex)
        adornment.Adornee = body
        adornment.AlwaysOnTop = self.Config.OutlineAlwaysOnTop ~= false
        adornment.ZIndex = 2
        adornment.Color3 = edgeColor
        adornment.Transparency = 1
        adornment.Size = Vector3.new(thickness, thickness, length + overlap)
        adornment.CFrame = CFrame.lookAt(mid, localB)
        adornment.Parent = body
        visuals[#visuals + 1] = adornment
    end

    for edgeIndex, edge in ipairs(CUBE_EDGES) do
        local a = CUBE_CORNERS[edge[1]] * halfSize
        local b = CUBE_CORNERS[edge[2]] * halfSize

        if self.Config.DashedEdges then
            local edgeVec = b - a
            local edgeLength = edgeVec.Magnitude
            local direction = edgeVec.Unit
            local dashLength = halfSize * 0.30
            local gapLength = halfSize * 0.25
            local position = 0
            local segmentIndex = 1

            while position < edgeLength - 1e-4 do
                local finish = math.min(edgeLength, position + dashLength)
                addSegment(
                    a + direction * position,
                    a + direction * finish,
                    edgeIndex,
                    segmentIndex
                )
                position = position + dashLength + gapLength
                segmentIndex = segmentIndex + 1
            end
        else
            addSegment(a, b, edgeIndex, 1)
        end
    end

    return visuals
end

function Cubes:_makeVisual(particle)
    local halfSize = self:_halfSize()
    local side = halfSize * 2

    local body = Instance.new("Part")
    body.Name = "Cube"
    body.Anchored = true
    body.CanCollide = false
    body.CanTouch = false
    body.CanQuery = false
    body.CastShadow = false
    body.Material = self.Config.FaceMaterial
    body.Color = self.Config.Color
    body.Size = Vector3.new(side, side, side)
    body.Transparency = 1
    body.Parent = self:_ensureFolder()

    particle.Body = body
    particle.EdgeVisuals = self:_makeEdges(body, halfSize)
    particle.GlowGui, particle.GlowLayers = self:_makeGlow(body, halfSize)
    particle.HalfSize = halfSize
end

function Cubes:_destroyParticle(particle)
    if particle and particle.Body then
        particle.Body:Destroy()
    end
end

function Cubes:Clear()
    for i = #self._particles, 1, -1 do
        self:_destroyParticle(self._particles[i])
        self._particles[i] = nil
    end
end

function Cubes:Rebuild()
    self:Clear()
    self._accumulator = 0
end

function Cubes:_getRoot()
    local character = LocalPlayer.Character
    if not character then
        return nil
    end
    return character:FindFirstChild("HumanoidRootPart")
end

function Cubes:_spawnParticle(root)
    if not root then
        return nil
    end

    local ws = self.Config.WorldScale
    local r = CUBE_RULES.SPAWN_RADIUS
    local falling = self.Config.Animation == "Falling"
    local baseLife

    if falling then
        baseLife = 260 + math.random(0, 219)
    else
        baseLife = 420 + math.random(0, 419)
    end

    local x = root.Position.X + randomRange(-r, r) * ws
    local y
    if falling then
        y = root.Position.Y + (4.0 + math.random() * (r * 0.55)) * ws
    else
        y = root.Position.Y + (2.0 + math.random() * (r * 0.8)) * ws
    end
    local z = root.Position.Z + randomRange(-r, r) * ws

    local speedMult = math.clamp(self.Config.Speed, 0.1, 5.0)
    local vx, vy, vz

    if falling then
        vx = (math.random() - 0.5) * 0.008 * speedMult
        vy = (-0.012 - math.random() * 0.012) * speedMult
        vz = (math.random() - 0.5) * 0.008 * speedMult
    else
        local yaw = math.random() * math.pi * 2
        local vel = (0.01 + math.random() * 0.02) * speedMult
        vx = -math.sin(yaw) * vel
        vz = math.cos(yaw) * vel
        vy = (math.random() - 0.5) * 0.01 * speedMult
    end

    local particle = {
        Position = Vector3.new(x, y, z),
        Velocity = Vector3.new(vx, vy, vz),
        Rotation = Vector3.new(
            math.random() * 360,
            math.random() * 360,
            math.random() * 360
        ),
        RotSpeed = Vector3.new(
            (math.random() - 0.5) * 1.5,
            (math.random() - 0.5) * 1.5,
            (math.random() - 0.5) * 1.5
        ),
        Life = baseLife,
        MaxLife = baseLife,
        WobblePhase = math.random() * math.pi * 2,
        WobbleOffset = math.random() * 10,
        RenderAlpha = 0,
    }

    self:_makeVisual(particle)
    return particle
end

function Cubes:_alphaOf(particle)
    if particle.MaxLife <= 0 then
        return 0
    end

    local lifeProgress = clamp01(particle.Life / particle.MaxLife)
    local fadeIn = math.min(1, (particle.MaxLife - particle.Life) / 20)
    return lifeProgress * fadeIn
end

function Cubes:_replaceParticle(index, root)
    local old = self._particles[index]
    if old then
        self:_destroyParticle(old)
    end
    self._particles[index] = self:_spawnParticle(root)
end

function Cubes:_maintainCount(root)
    local target = math.clamp(math.floor(self.Config.Count), 5, 100)
    local current = #self._particles

    if current < target then
        local toAdd = math.min(target - current, 5)
        for _ = 1, toAdd do
            local particle = self:_spawnParticle(root)
            if particle then
                self._particles[#self._particles + 1] = particle
            end
        end
    elseif current > target then
        for i = current, target + 1, -1 do
            self:_destroyParticle(self._particles[i])
            table.remove(self._particles, i)
        end
    end
end

function Cubes:_physicsStep()
    if not self.Enabled then
        return
    end

    local root = self:_getRoot()
    if not root then
        return
    end

    self:_maintainCount(root)

    local speed = math.clamp(self.Config.Speed, 0.1, 5.0)
    local spd = CUBE_RULES.BASE_SPEED * speed
    local falling = self.Config.Animation == "Falling"
    local ws = self.Config.WorldScale
    local maxDistSq = (CUBE_RULES.SPAWN_RADIUS * ws) ^ 2 * 6.25

    for i = #self._particles, 1, -1 do
        local p = self._particles[i]

        if falling then
            p.WobblePhase = p.WobblePhase + 0.06 * spd
            p.Position = p.Position + Vector3.new(
                (p.Velocity.X * spd
                    + math.sin(p.WobblePhase + p.WobbleOffset) * 0.0024 * spd) * ws,
                p.Velocity.Y * spd * ws,
                (p.Velocity.Z * spd
                    + math.cos(p.WobblePhase * 0.8 + p.WobbleOffset) * 0.002 * spd) * ws
            )

            p.Velocity = Vector3.new(
                p.Velocity.X,
                math.max(p.Velocity.Y - 8.0e-5 * spd, -0.032),
                p.Velocity.Z
            )

            p.Rotation = p.Rotation + p.RotSpeed * (0.2 * spd)
        else
            p.Position = p.Position + p.Velocity * (spd * ws)
            p.Rotation = p.Rotation + p.RotSpeed * spd
            p.Velocity = p.Velocity * 0.995
        end

        p.Life = p.Life - 1

        local rel = p.Position - root.Position
        local distSq = rel:Dot(rel)

        if p.Life <= 0
            or distSq > maxDistSq
            or (falling and p.Position.Y < root.Position.Y - 2.5 * ws) then
            self:_replaceParticle(i, root)
        end
    end
end

function Cubes:_setVisualAlpha(particle, alpha)
    alpha = clamp01(alpha)
    particle.RenderAlpha = alpha

    if not particle.Body or not particle.Body.Parent then
        return
    end

    local faceAlpha = alpha * 0.4
    particle.Body.Transparency = 1 - faceAlpha
    particle.Body.Color = self.Config.Color

    local edgeColor = brighten(self.Config.Color, 1.5)
    for _, edgeVisual in ipairs(particle.EdgeVisuals or {}) do
        edgeVisual.Color3 = edgeColor
        edgeVisual.Transparency = 1 - alpha
        edgeVisual.AlwaysOnTop = self.Config.OutlineAlwaysOnTop ~= false
    end

    if particle.GlowGui then
        particle.GlowGui.AlwaysOnTop = self.Config.GlowNoDepth ~= false
    end

    for i, image in ipairs(particle.GlowLayers or {}) do
        local glowAlpha = clamp01(
            alpha
                * CUBE_RULES.GLOW_ALPHAS[i]
                * CUBE_RULES.GLOW_MULTIPLIER
        )
        image.ImageColor3 = self.Config.Color
        image.ImageTransparency = 1 - glowAlpha
    end
end

function Cubes:_render()
    if not self.Enabled then
        return
    end

    self._camera = Workspace.CurrentCamera or self._camera
    if not self._camera then
        return
    end

    local ws = self.Config.WorldScale
    local camPos = self._camera.CFrame.Position
    local look = self._camera.CFrame.LookVector

    for _, particle in ipairs(self._particles) do
        if particle.Body and particle.Body.Parent then
            particle.Body.CFrame = CFrame.new(particle.Position)
                * CFrame.Angles(
                    math.rad(particle.Rotation.X),
                    math.rad(particle.Rotation.Y),
                    math.rad(particle.Rotation.Z)
                )

            local alpha = self:_alphaOf(particle)

            -- Legacy/source-like camera culling is optional. It is disabled by
            -- default because a Roblox third-person camera can move far away from
            -- the character while the particles themselves are still nearby.
            if self.Config.ManualCameraCulling then
                local maxRenderDistSq = CUBE_RULES.MAX_RENDER_DISTANCE_SQ * ws * ws
                local rel = particle.Position - camPos
                local distSq = rel:Dot(rel)
                local cameraDot = rel:Dot(look)
                if distSq > maxRenderDistSq or cameraDot < -1.0 * ws then
                    alpha = 0
                end
            end

            self:_setVisualAlpha(particle, alpha)
        end
    end
end

function Cubes:_applyHitImpulse()
    if not self.Enabled or #self._particles == 0 then
        return
    end

    self._camera = Workspace.CurrentCamera or self._camera
    if not self._camera then
        return
    end

    -- Use the actual mouse cursor ray. Camera.LookVector only represents the
    -- screen centre, which is why the old impulse worked mainly in first person.
    local mousePosition = UserInputService:GetMouseLocation()
    local ray

    local ok, result = pcall(function()
        return self._camera:ScreenPointToRay(mousePosition.X, mousePosition.Y, 0)
    end)

    if ok and result then
        ray = result
    else
        -- Fallback for executors/clients where ScreenPointToRay behaves oddly.
        ray = self._camera:ViewportPointToRay(mousePosition.X, mousePosition.Y, 0)
    end

    local origin = ray.Origin
    local direction = ray.Direction.Unit
    local ws = self.Config.WorldScale
    local maxRange = CUBE_RULES.RAY_RANGE * ws
    local maxDistanceSq = CUBE_RULES.RAY_DISTANCE_SQ * ws * ws

    local best
    local bestT = math.huge

    for _, particle in ipairs(self._particles) do
        local op = particle.Position - origin
        local t = op:Dot(direction)
        if t >= 0 and t <= maxRange then
            local closest = origin + direction * t
            local delta = particle.Position - closest
            local distSq = delta:Dot(delta)

            if distSq <= maxDistanceSq and t < bestT then
                bestT = t
                best = particle
            end
        end
    end

    if best then
        local force = CUBE_RULES.IMPULSE_FORCE
            * math.clamp(self.Config.Speed, 0.1, 5.0)

        best.Velocity = best.Velocity
            + direction * force
            + Vector3.new(0, CUBE_RULES.IMPULSE_VERTICAL, 0)
    end
end

function Cubes:Enable()
    if self.Enabled then
        return true
    end

    self:_loadAssets()
    if self.Config.GlowEnabled and not self._glowAsset then
        notify("Cubes: ixry_vfx_cube_glow.png not found; continuing without glow", 4)
    end
    self:_ensureFolder()
    self.Enabled = true
    self._accumulator = 0

    self._characterConnection = LocalPlayer.CharacterAdded:Connect(function()
        self:Clear()
        self._accumulator = 0
    end)

    self._inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed or not self.Enabled then
            return
        end

        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self:_applyHitImpulse()
        end
    end)

    self._renderConnection = RunService.RenderStepped:Connect(function(dt)
        if not self.Enabled then
            return
        end

        local step = 1 / math.max(1, self.Config.UpdateRate)
        self._accumulator = self._accumulator + math.min(dt, 0.1)

        local loops = 0
        while self._accumulator >= step and loops < 5 do
            self._accumulator = self._accumulator - step
            self:_physicsStep()
            loops = loops + 1
        end

        self:_render()
    end)

    return true
end

function Cubes:Disable()
    if not self.Enabled then
        return
    end

    self.Enabled = false
    disconnect(self._renderConnection)
    disconnect(self._inputConnection)
    disconnect(self._characterConnection)

    self._renderConnection = nil
    self._inputConnection = nil
    self._characterConnection = nil
    self._accumulator = 0

    self:Clear()

    if self._folder and self._folder.Parent then
        self._folder:Destroy()
    end
    self._folder = nil
end

function Cubes:Cleanup()
    self:Disable()
end

-- ============================================================================
-- Wraith Wings module
-- Source basis: ModuleWings.kt (procedural / EvaWare branch)
-- Roblox adaptation:
--   Prism -> procedural shape baked into plugin-private alpha textures while
--            preserving the source flap/spread/pose behavior.
-- ============================================================================

local Wings = {
    Enabled = false,
    Config = {
        Self = true,
        Players = false,
        Size = 1.0,
        Alpha = 220,
        OffsetX = 0.0,
        OffsetY = 0.0,
        OffsetZ = 0.18,
        Color = Color3.fromRGB(255, 100, 255),
        GuiMaxDistance = 100000,

        -- Prism-local aura. Native BloomEffect does not reliably affect SurfaceGui
        -- pixels, so the glow is rendered as blurred wing layers on the wing itself.
        AuraEnabled = true,
        AuraStrength = 0.95,
        AuraRadius = 18.0,
    },
}

local WING_ASSETS = {
    Left = "ixry_vfx_wing_prism_left.png",
    Right = "ixry_vfx_wing_prism_right.png",
    AuraLeft = "ixry_vfx_wing_prism_left_aura.png",
    AuraRight = "ixry_vfx_wing_prism_right_aura.png",
}

Wings._folder = nil
Wings._rigs = {}
Wings._assetCache = {}
Wings._renderConnection = nil
Wings._playerRemovingConnection = nil
Wings._animationStartedAt = os.clock()

local function wingAssetCandidates(path)
    return {
        "ODH_VFX_Addon_Assets/" .. path,
    }
end

function Wings:_loadAsset(path)
    if self._assetCache[path] then
        return self._assetCache[path]
    end

    local asset = tryLoadAsset(path, wingAssetCandidates(path))
    self._assetCache[path] = asset
    return asset
end

function Wings:_selectedAssetPaths()
    return WING_ASSETS.Left, WING_ASSETS.Right
end

function Wings:_selectedAssets()
    local leftPath, rightPath = self:_selectedAssetPaths()
    local left = self:_loadAsset(leftPath)
    local right = self:_loadAsset(rightPath)

    local auraLeftPath = WING_ASSETS.AuraLeft
    local auraRightPath = WING_ASSETS.AuraRight
    local auraLeft = self:_loadAsset(auraLeftPath)
    local auraRight = self:_loadAsset(auraRightPath)

    return left, right, leftPath, rightPath, auraLeft, auraRight
end

function Wings:_ensureFolder()
    if self._folder and self._folder.Parent then
        return self._folder
    end

    local old = Workspace:FindFirstChild("_ODH_WraithWings")
    if old then
        old:Destroy()
    end

    local folder = Instance.new("Folder")
    folder.Name = "_ODH_WraithWings"
    folder.Parent = Workspace
    self._folder = folder
    return folder
end

function Wings:_destroyRig(rig)
    if rig and rig.Model then
        rig.Model:Destroy()
    end
end

function Wings:Clear()
    for player, rig in pairs(self._rigs) do
        self:_destroyRig(rig)
        self._rigs[player] = nil
    end
end

function Wings:Rebuild()
    self:Clear()
    self._animationStartedAt = os.clock()

    if self.Enabled then
        local left, right, leftPath, rightPath = self:_selectedAssets()
        if not left or not right then
            notify(
                "Wings: missing asset " .. tostring(not left and leftPath or rightPath),
                4
            )
        end
    end
end

local function makeWingImage(surface, asset, name, zIndex)
    local image = Instance.new("ImageLabel")
    image.Name = name or "WingImage"
    image.BackgroundTransparency = 1
    image.BorderSizePixel = 0
    image.AnchorPoint = Vector2.new(0.5, 0.5)
    image.Position = UDim2.fromScale(0.5, 0.5)
    image.Size = UDim2.fromScale(1, 1)
    image.Image = asset
    image.ImageTransparency = 1
    image.ScaleType = Enum.ScaleType.Stretch
    image.ZIndex = zIndex or 1
    image.Parent = surface
    return image
end

function Wings:_makeWingPart(parent, name, asset, auraAsset)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.CastShadow = false
    part.Transparency = 1
    part.Size = Vector3.new(1, 1, 0.025)
    part.Parent = parent

    local coreImages = {}
    local innerAuraImages = {}
    local outerAuraImages = {}

    auraAsset = auraAsset or asset

    for _, face in ipairs({Enum.NormalId.Front, Enum.NormalId.Back}) do
        local surface = Instance.new("SurfaceGui")
        surface.Name = face == Enum.NormalId.Front and "Front" or "Back"
        surface.Face = face
        surface.AlwaysOnTop = false
        surface.LightInfluence = 0
        pcall(function()
            surface.MaxDistance = self.Config.GuiMaxDistance
        end)
        pcall(function()
            surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
        end)
        surface.CanvasSize = Vector2.new(512, 768)
        surface.Parent = part

        outerAuraImages[#outerAuraImages + 1] = makeWingImage(surface, auraAsset, "OuterAura", 1)
        innerAuraImages[#innerAuraImages + 1] = makeWingImage(surface, auraAsset, "InnerAura", 2)
        coreImages[#coreImages + 1] = makeWingImage(surface, asset, "WingImage", 3)
    end

    return part, coreImages, innerAuraImages, outerAuraImages
end

function Wings:_makeRig(player)
    local leftAsset, rightAsset, _, _, auraLeft, auraRight = self:_selectedAssets()
    if not leftAsset or not rightAsset then
        return nil
    end

    local model = Instance.new("Model")
    model.Name = "Wings_" .. player.Name
    model.Parent = self:_ensureFolder()

    local leftPart, leftImages, leftInnerAura, leftOuterAura =
        self:_makeWingPart(model, "LeftWing", leftAsset, auraLeft)
    local rightPart, rightImages, rightInnerAura, rightOuterAura =
        self:_makeWingPart(model, "RightWing", rightAsset, auraRight)

    local rig = {
        Model = model,
        LeftPart = leftPart,
        RightPart = rightPart,
        LeftImages = leftImages,
        RightImages = rightImages,
        LeftInnerAura = leftInnerAura,
        RightInnerAura = rightInnerAura,
        LeftOuterAura = leftOuterAura,
        RightOuterAura = rightOuterAura,
    }

    self._rigs[player] = rig
    return rig
end

function Wings:_hideRig(rig)
    if not rig then
        return
    end
    for _, list in ipairs({
        rig.LeftImages,
        rig.RightImages,
        rig.LeftInnerAura,
        rig.RightInnerAura,
        rig.LeftOuterAura,
        rig.RightOuterAura,
    }) do
        for _, image in ipairs(list or {}) do
            image.ImageTransparency = 1
        end
    end
end

function Wings:_characterParts(player)
    local character = player.Character
    if not character then
        return nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    local torso = character:FindFirstChild("UpperTorso")
        or character:FindFirstChild("Torso")
        or root

    if not humanoid or not root or not torso or humanoid.Health <= 0 then
        return nil
    end

    return character, humanoid, root, torso
end

function Wings:_isFirstPerson(character)
    local camera = Workspace.CurrentCamera
    if not camera then
        return false
    end

    local head = character:FindFirstChild("Head")
    if not head then
        return false
    end

    return (camera.CFrame.Position - head.Position).Magnitude < 1.15
end

function Wings:_shouldRenderPlayer(player, character, humanoid)
    if player == LocalPlayer then
        if not self.Config.Self then
            return false
        end
        if self:_isFirstPerson(character) then
            return false
        end
    else
        if not self.Config.Players then
            return false
        end
    end

    if humanoid:GetState() == Enum.HumanoidStateType.Swimming then
        return false
    end

    return true
end

function Wings:_baseColor()
    return self.Config.Color
end

function Wings:_setImages(rig, color, transparency, tint)
    local coreAlpha = math.clamp(1 - transparency, 0, 1)

    local function applyCore(image)
        image.ImageColor3 = tint and color or Color3.new(1, 1, 1)
        image.ImageTransparency = transparency
        image.Size = UDim2.fromScale(1, 1)
        image.Position = UDim2.fromScale(0.5, 0.5)
    end

    for _, image in ipairs(rig.LeftImages or {}) do
        applyCore(image)
    end
    for _, image in ipairs(rig.RightImages or {}) do
        applyCore(image)
    end

    local auraEnabled = self.Config.AuraEnabled == true
    local strength = math.clamp(self.Config.AuraStrength or 0.95, 0, 2.5)
    local radius = math.clamp(self.Config.AuraRadius or 18, 0, 48)

    local basePaddedScale = 1.20
    local innerScale = basePaddedScale + radius * 0.0025
    local outerScale = basePaddedScale + radius * 0.0050

    local innerAlpha = auraEnabled
        and math.clamp(coreAlpha * 0.62 * strength, 0, 0.92)
        or 0
    local outerAlpha = auraEnabled
        and math.clamp(coreAlpha * 0.30 * strength, 0, 0.72)
        or 0

    local function applyAura(image, alpha, scale)
        image.ImageColor3 = color
        image.ImageTransparency = 1 - alpha
        image.Size = UDim2.fromScale(scale, scale)
        image.Position = UDim2.fromScale(0.5, 0.5)
    end

    for _, image in ipairs(rig.LeftInnerAura or {}) do
        applyAura(image, innerAlpha, innerScale)
    end
    for _, image in ipairs(rig.RightInnerAura or {}) do
        applyAura(image, innerAlpha, innerScale)
    end
    for _, image in ipairs(rig.LeftOuterAura or {}) do
        applyAura(image, outerAlpha, outerScale)
    end
    for _, image in ipairs(rig.RightOuterAura or {}) do
        applyAura(image, outerAlpha, outerScale)
    end
end

local function rotationOnly(cframe)
    return cframe - cframe.Position
end

function Wings:_avatarScale(torso)
    return math.clamp(torso.Size.Y / 2.0, 0.72, 1.35)
end

function Wings:_updateEvaWare(player, humanoid, root, torso, rig)
    local avatarScale = self:_avatarScale(torso)
    local size = math.clamp(self.Config.Size, 0.5, 3.0) * avatarScale
    local width = 2.75 * size
    local height = 4.35 * size

    rig.LeftPart.Size = Vector3.new(width, height, 0.025)
    rig.RightPart.Size = Vector3.new(width, height, 0.025)

    local movement = math.clamp(humanoid.MoveDirection.Magnitude, 0, 1)
    local state = humanoid:GetState()
    local airborne = state == Enum.HumanoidStateType.Freefall
        or state == Enum.HumanoidStateType.Jumping

    local timeTicks = os.clock() * 20
    local flapAmplitude = airborne and 0.58 or 4.5
    local flapSpeed = airborne and 0.13 or 0.12
    local flap = math.sin(timeTicks * flapSpeed) * flapAmplitude
    local openMultiplier = airborne and 0.76 or 1.0
    local motionSpreadBoost = airborne and 0.10 or 0.18
    local open = (8.0 + flap + movement * motionSpreadBoost) * openMultiplier

    local sideRoll = airborne and -5.0 or -11.0
    local sidePitch = airborne and -2.0 or -4.0
    local pitchRotation = airborne and -20.0 or 0.0
    local modeScale = airborne and 0.92 or 1.0

    width = width * modeScale
    height = height * modeScale
    rig.LeftPart.Size = Vector3.new(width, height, 0.025)
    rig.RightPart.Size = Vector3.new(width, height, 0.025)

    local bodyOrientation = rotationOnly(root.CFrame)
    local base = CFrame.new(torso.Position)
        * bodyOrientation
        * CFrame.new(
            self.Config.OffsetX,
            0.48 * avatarScale + self.Config.OffsetY,
            0.72 * avatarScale + self.Config.OffsetZ
        )
        * CFrame.Angles(math.rad(pitchRotation), 0, 0)

    -- Root is ~41% down the procedural wing image. Center offset keeps the
    -- texture's inner root pinned to the same shoulder anchor while it flaps.
    local rootYFraction = 0.414
    local centerY = (rootYFraction - 0.5) * height
    local rootMargin = 0.045
    local centerX = (0.5 - rootMargin) * width

    for _, side in ipairs({-1, 1}) do
        local rotation = CFrame.Angles(
            math.rad(sidePitch),
            math.rad(side * open),
            math.rad(side * sideRoll)
        )
        local frame = base
            * CFrame.new(side * 0.10 * avatarScale, 0, 0.05 * avatarScale)
            * rotation
            * CFrame.new(side * centerX, centerY, 0)

        if side < 0 then
            rig.LeftPart.CFrame = frame
        else
            rig.RightPart.CFrame = frame
        end
    end

    local color = self:_baseColor()
    local transparency = 1 - math.clamp(self.Config.Alpha / 255, 0, 1)
    self:_setImages(rig, color, transparency, true)
end

function Wings:_updatePlayer(player)
    local character, humanoid, root, torso = self:_characterParts(player)
    local rig = self._rigs[player]

    if not character then
        if rig then
            self:_destroyRig(rig)
            self._rigs[player] = nil
        end
        return false
    end

    if not self:_shouldRenderPlayer(player, character, humanoid) then
        if rig then
            self:_hideRig(rig)
        end
        return false
    end

    if not rig then
        rig = self:_makeRig(player)
        if not rig then
            self._rigs[player] = nil
            return false
        end
    end

    self:_updateEvaWare(player, humanoid, root, torso, rig)
    return true
end

function Wings:_render()
    if not self.Enabled then
        return
    end

    local visibleCount = 0
    for _, player in ipairs(Players:GetPlayers()) do
        if self:_updatePlayer(player) then
            visibleCount = visibleCount + 1
        end
    end

end

function Wings:Enable()
    if self.Enabled then
        return true
    end

    local left, right, leftPath, rightPath = self:_selectedAssets()
    if not left or not right then
        notify(
            "Wings: missing asset " .. tostring(not left and leftPath or rightPath),
            4
        )
        return false
    end

    self.Enabled = true
    self._animationStartedAt = os.clock()
    self:_ensureFolder()

    self._playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
        local rig = self._rigs[player]
        if rig then
            self:_destroyRig(rig)
            self._rigs[player] = nil
        end
    end)

    self._renderConnection = RunService.RenderStepped:Connect(function()
        self:_render()
    end)

    return true
end

function Wings:Disable()
    if not self.Enabled then
        return
    end

    self.Enabled = false
    disconnect(self._renderConnection)
    disconnect(self._playerRemovingConnection)
    self._renderConnection = nil
    self._playerRemovingConnection = nil

    self:Clear()

    if self._folder and self._folder.Parent then
        self._folder:Destroy()
    end
    self._folder = nil
end

function Wings:Cleanup()
    self:Disable()
end

-- ============================================================================
-- Wraith LineGlyphs module
-- Source basis: ModuleLineGlyphs.kt + WyvernLineGlyphRules.kt
-- Roblox adaptation:
--   Source emits each dash as a separate square-capped GPU line and then draws
--   four additive glow widths behind one core pass. Roblox Beam transparency
--   sequences interpolate at dash boundaries, and camera Bloom bleeds along the
--   line direction. This version uses binary-alpha repeating textures instead:
--   hard X cutoffs for the dash/gap and a Y-only soft profile for glow.
-- ============================================================================

local LineGlyphs = {
    Enabled = false,
    Config = {
        -- Source settings
        Count = 50,          -- 10..200
        Speed = 1.0,         -- 0.1..5.0
        Glow = true,
        Thickness = 1.5,     -- 0.5..5.0

        -- Roblox presentation. Source uses ClientTheme.accentA; ODH does not
        -- expose LiquidBounce's ClientTheme, so this is the local accent fallback.
        Color = Color3.fromRGB(105, 170, 255),
        WorldScale = 2.75,
        BeamWidthUnit = 0.015,
        GlowWidthMultiplier = 5.0,
        GlowAlpha = 0.34,
        GlowBrightness = 2.5,
        UpdateRate = 20,

        -- Plugin-private textures. These are intentionally not generic names so
        -- they cannot collide with ODH's own assets.
        DashAssetPath = "ixry_vfx_lineglyph_dash.png",
        GlowDashAssetPath = "ixry_vfx_lineglyph_glowdash.png",
        GlowSolidAssetPath = "ixry_vfx_lineglyph_glow_solid.png",
    },
}

local LINE_GLYPH_RULES = {
    ALPHA_DURATION = 1.2,
    MOVEMENT_PROGRESS = 0.025,
    STEP_LENGTH = 2.5,
    DASH_LENGTH = 0.58,
    GAP_LENGTH = 0.34,
    REVERSE_DOT_LIMIT = -0.5,
    SPAWN_RANGE_XZ = 30.0,
    SPAWN_RANGE_Y = 15.0,
    MIN_POINTS = 12,
    MAX_POINTS = 26,
}

LineGlyphs._paths = {}
LineGlyphs._folder = nil
LineGlyphs._anchor = nil
LineGlyphs._renderConnection = nil
LineGlyphs._characterConnection = nil
LineGlyphs._accumulator = 0
LineGlyphs._lastVisualUpdate = 0
LineGlyphs._dashAsset = nil
LineGlyphs._glowDashAsset = nil
LineGlyphs._glowSolidAsset = nil

local function glyphQuadInOut(progress)
    local value = math.clamp(progress, 0, 1)
    if value < 0.5 then
        return 2 * value * value
    end
    local t = -2 * value + 2
    return 1 - (t * t) / 2
end

local function glyphRandomAxisDirection()
    local sign = math.random() < 0.5 and -1 or 1
    local axis = math.random(1, 3)
    if axis == 1 then
        return Vector3.new(sign, 0, 0)
    elseif axis == 2 then
        return Vector3.new(0, sign, 0)
    end
    return Vector3.new(0, 0, sign)
end

local function glyphNextDirection(lastDirection)
    local direction
    repeat
        direction = glyphRandomAxisDirection()
    until direction:Dot(lastDirection) >= LINE_GLYPH_RULES.REVERSE_DOT_LIMIT
    return direction
end

local function glyphFadeValue(fade, now)
    local elapsed = math.clamp(
        (now - fade.StartedAt) / LINE_GLYPH_RULES.ALPHA_DURATION,
        0,
        1
    )
    local eased = glyphQuadInOut(elapsed)
    return fade.From + (fade.Target - fade.From) * eased
end

local function glyphSetFadeTarget(fade, target, now)
    if math.abs(target - fade.Target) <= 1.0e-4 then
        return
    end
    fade.From = glyphFadeValue(fade, now)
    fade.Target = target
    fade.StartedAt = now
end

function LineGlyphs:_loadAssets()
    if not self._dashAsset then
        self._dashAsset = tryLoadAsset(self.Config.DashAssetPath, {
            "ODH_VFX_Addon_Assets/ixry_vfx_lineglyph_dash.png",
        })
    end
    if not self._glowDashAsset then
        self._glowDashAsset = tryLoadAsset(self.Config.GlowDashAssetPath, {
            "ODH_VFX_Addon_Assets/ixry_vfx_lineglyph_glowdash.png",
        })
    end
    if not self._glowSolidAsset then
        self._glowSolidAsset = tryLoadAsset(self.Config.GlowSolidAssetPath, {
            "ODH_VFX_Addon_Assets/ixry_vfx_lineglyph_glow_solid.png",
        })
    end

    return self._dashAsset ~= nil
end

function LineGlyphs:_destroyLegacyBloomEffect()
    local camera = Workspace.CurrentCamera
    if not camera then
        return
    end
    local old = camera:FindFirstChild("_ODH_LineGlyphBloom")
    if old then
        old:Destroy()
    end
end

function LineGlyphs:_ensureFolder()
    if self._folder and self._folder.Parent and self._anchor and self._anchor.Parent then
        return self._folder
    end

    local old = Workspace:FindFirstChild("_ODH_WraithLineGlyphs")
    if old then
        old:Destroy()
    end

    local folder = Instance.new("Folder")
    folder.Name = "_ODH_WraithLineGlyphs"
    folder.Parent = Workspace

    local anchor = Instance.new("Part")
    anchor.Name = "GlyphAnchor"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanTouch = false
    anchor.CanQuery = false
    anchor.CastShadow = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.05, 0.05, 0.05)
    anchor.CFrame = CFrame.new(0, 0, 0)
    anchor.Parent = folder

    self._folder = folder
    self._anchor = anchor
    return folder
end

function LineGlyphs:_destroyPath(path)
    if not path then
        return
    end

    for _, segment in ipairs(path.Segments or {}) do
        if segment.Beam and segment.Beam.Parent then
            segment.Beam:Destroy()
        end
        if segment.GlowBeam and segment.GlowBeam.Parent then
            segment.GlowBeam:Destroy()
        end
    end

    for _, attachment in ipairs(path.Attachments or {}) do
        if attachment and attachment.Parent then
            attachment:Destroy()
        end
    end

    path.Segments = {}
    path.Attachments = {}
end

function LineGlyphs:Clear()
    for i = #self._paths, 1, -1 do
        self:_destroyPath(self._paths[i])
        self._paths[i] = nil
    end
end

function LineGlyphs:_makeAttachment(position)
    local attachment = Instance.new("Attachment")
    attachment.Name = "GlyphPoint"
    attachment.Position = position
    attachment.Parent = self._anchor
    return attachment
end

function LineGlyphs:_coreWidth()
    return self.Config.BeamWidthUnit
        * self.Config.WorldScale
        * math.clamp(self.Config.Thickness, 0.5, 5.0)
end

function LineGlyphs:_styleCoreBeam(beam)
    local width = self:_coreWidth()
    beam.Width0 = width
    beam.Width1 = width
    beam.Color = ColorSequence.new(self.Config.Color)
    beam.LightInfluence = 0
    beam.LightEmission = self.Config.Glow and 1 or 0
    pcall(function()
        beam.Brightness = self.Config.Glow and 2.0 or 1.0
    end)
end

function LineGlyphs:_styleGlowBeam(beam)
    local width = self:_coreWidth() * self.Config.GlowWidthMultiplier
    beam.Width0 = width
    beam.Width1 = width
    beam.Color = ColorSequence.new(self.Config.Color)
    beam.LightInfluence = 0
    beam.LightEmission = 1
    pcall(function()
        beam.Brightness = self.Config.GlowBrightness
    end)
end

function LineGlyphs:_newBeam(name, a0, a1, glow)
    local beam = Instance.new("Beam")
    beam.Name = name
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.FaceCamera = true
    -- One flat quad per straight source segment gives cleaner, squarer corners.
    beam.Segments = 1
    beam.CurveSize0 = 0
    beam.CurveSize1 = 0
    beam.TextureSpeed = 0
    beam.TextureOffset = 0
    beam.Transparency = NumberSequence.new(1)
    beam.Parent = self:_ensureFolder()

    if glow then
        self:_styleGlowBeam(beam)
    else
        self:_styleCoreBeam(beam)
    end
    return beam
end

function LineGlyphs:_makeSegment(a0, a1)
    local segment = {
        Beam = self:_newBeam("GlyphCore", a0, a1, false),
        GlowBeam = nil,
    }
    if self.Config.Glow and self._glowDashAsset and self._glowSolidAsset then
        segment.GlowBeam = self:_newBeam("GlyphGlow", a0, a1, true)
    end
    return segment
end

function LineGlyphs:_syncGlowBeam(segment)
    if self.Config.Glow and self._glowDashAsset and self._glowSolidAsset then
        if not segment.GlowBeam or not segment.GlowBeam.Parent then
            local core = segment.Beam
            if core and core.Attachment0 and core.Attachment1 then
                segment.GlowBeam = self:_newBeam(
                    "GlyphGlow",
                    core.Attachment0,
                    core.Attachment1,
                    true
                )
            end
        end
    elseif segment.GlowBeam then
        if segment.GlowBeam.Parent then
            segment.GlowBeam:Destroy()
        end
        segment.GlowBeam = nil
    end
end

function LineGlyphs:_applyDashTexture(beam, length, alpha, isGlow)
    if not beam then
        return
    end

    alpha = math.clamp(alpha, 0, 1)
    if alpha <= 0.001 or length <= 0.0001 then
        beam.Transparency = NumberSequence.new(1)
        return
    end

    local period = (LINE_GLYPH_RULES.DASH_LENGTH + LINE_GLYPH_RULES.GAP_LENGTH)
        * self.Config.WorldScale

    -- Source special case: while the currently-growing segment is shorter than
    -- one complete dash+gap period, render it as one solid line.
    if length <= period + 1.0e-6 then
        if isGlow then
            beam.Texture = self._glowSolidAsset or ""
            beam.TextureMode = Enum.TextureMode.Stretch
        else
            beam.Texture = ""
        end
    else
        beam.Texture = isGlow
            and (self._glowDashAsset or "")
            or (self._dashAsset or "")
        beam.TextureMode = Enum.TextureMode.Wrap
        beam.TextureLength = period
    end

    -- Constant Beam transparency: dash boundaries now come only from the texture's
    -- binary alpha, so there is no NumberSequence interpolation/faint tail in gaps.
    local effectiveAlpha = isGlow
        and math.clamp(alpha * self.Config.GlowAlpha, 0, 1)
        or alpha
    beam.Transparency = NumberSequence.new(1 - effectiveAlpha)
end

function LineGlyphs:_spawnPath()
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root then
        return
    end

    self:_ensureFolder()

    local ws = self.Config.WorldScale
    local start = root.Position + Vector3.new(
        (math.random() - 0.5) * LINE_GLYPH_RULES.SPAWN_RANGE_XZ * 2 * ws,
        (math.random() - 0.5) * LINE_GLYPH_RULES.SPAWN_RANGE_Y * ws,
        (math.random() - 0.5) * LINE_GLYPH_RULES.SPAWN_RANGE_XZ * 2 * ws
    )

    local now = os.clock()
    local firstAttachment = self:_makeAttachment(start)

    self._paths[#self._paths + 1] = {
        Points = {start},
        Attachments = {firstAttachment},
        Segments = {},
        MaxPoints = math.random(LINE_GLYPH_RULES.MIN_POINTS, LINE_GLYPH_RULES.MAX_POINTS),
        LastDirection = Vector3.zero,
        MoveProgress = 0,
        PreviousMoveProgress = 0,
        Removing = false,
        Fade = {
            From = 0,
            Target = 0,
            StartedAt = now,
        },
    }
end

function LineGlyphs:_addPoint(path)
    local points = path.Points
    local last = points[#points]
    if not last then
        path.Removing = true
        return
    end

    local direction = glyphNextDirection(path.LastDirection)
    path.LastDirection = direction

    local nextPoint = last + direction * (LINE_GLYPH_RULES.STEP_LENGTH * self.Config.WorldScale)
    points[#points + 1] = nextPoint

    -- Source begins drawing a newly-created point from the previous point and
    -- interpolates toward its final axis-aligned position over following ticks.
    local attachment = self:_makeAttachment(last)
    path.Attachments[#path.Attachments + 1] = attachment

    local previousAttachment = path.Attachments[#path.Attachments - 1]
    local segment = self:_makeSegment(previousAttachment, attachment)
    segment.FromIndex = #points - 1
    segment.ToIndex = #points
    path.Segments[#path.Segments + 1] = segment
end

function LineGlyphs:_removePath(path, now)
    if path.Removing then
        return
    end
    path.Removing = true
    glyphSetFadeTarget(path.Fade, 0, now)
end

function LineGlyphs:_tickPath(path, now)
    glyphSetFadeTarget(path.Fade, path.Removing and 0 or 1, now)
    if path.Removing then
        return
    end

    path.PreviousMoveProgress = path.MoveProgress
    path.MoveProgress = path.MoveProgress
        + LINE_GLYPH_RULES.MOVEMENT_PROGRESS * math.clamp(self.Config.Speed, 0.1, 5.0)

    if path.MoveProgress >= 1 then
        path.PreviousMoveProgress = 0
        path.MoveProgress = 0
        self:_addPoint(path)
    end

    if #path.Points >= path.MaxPoints then
        self:_removePath(path, now)
    end
end

function LineGlyphs:_tick()
    if not self.Enabled then
        return
    end

    local now = os.clock()

    for i = #self._paths, 1, -1 do
        local path = self._paths[i]
        if path.Removing and glyphFadeValue(path.Fade, now) <= 0.01 then
            self:_destroyPath(path)
            table.remove(self._paths, i)
        end
    end

    for _, path in ipairs(self._paths) do
        self:_tickPath(path, now)
    end

    -- Source adds at most one new path per game tick.
    if #self._paths < math.floor(math.clamp(self.Config.Count, 10, 200)) then
        self:_spawnPath()
    end
end

function LineGlyphs:_renderProgress(path, tickFraction)
    return math.clamp(
        path.PreviousMoveProgress
            + (path.MoveProgress - path.PreviousMoveProgress) * tickFraction,
        0,
        1
    )
end

function LineGlyphs:_renderPoint(path, index, progress)
    local points = path.Points
    if index == #points and #points >= 2 and not path.Removing then
        local previous = points[index - 1]
        local current = points[index]
        return previous:Lerp(current, progress)
    end
    return points[index]
end

function LineGlyphs:_isFirstPersonPathCulled(path)
    local camera = Workspace.CurrentCamera
    local character = LocalPlayer.Character
    if not camera or not character then
        return false
    end

    local head = character:FindFirstChild("Head")
    if not head or (camera.CFrame.Position - head.Position).Magnitude >= 1.15 then
        return false
    end

    local firstPoint = path.Points[1]
    if not firstPoint then
        return false
    end

    return (firstPoint - camera.CFrame.Position):Dot(camera.CFrame.LookVector) < 0
end

function LineGlyphs:_updateGeometry(tickFraction)
    for _, path in ipairs(self._paths) do
        local count = #path.Points
        if count >= 2 then
            local progress = self:_renderProgress(path, tickFraction)
            local lastAttachment = path.Attachments[count]
            if lastAttachment and lastAttachment.Parent then
                lastAttachment.Position = self:_renderPoint(path, count, progress)
            end
        end
    end
end

function LineGlyphs:_updateSegmentVisual(segment, segmentIndex, pointCount, pathAlpha, culled)
    local beam = segment and segment.Beam
    if not beam or not beam.Parent then
        return
    end

    local alpha = 0
    if not culled and pointCount > 0 then
        alpha = pathAlpha * (segmentIndex / pointCount)
    end

    local a0 = beam.Attachment0
    local a1 = beam.Attachment1
    local length = 0
    if a0 and a1 then
        length = (a1.WorldPosition - a0.WorldPosition).Magnitude
    end

    self:_applyDashTexture(beam, length, alpha, false)

    local glow = segment.GlowBeam
    if glow and glow.Parent then
        self:_applyDashTexture(glow, length, alpha, true)
    end
end

function LineGlyphs:_updateVisuals()
    local now = os.clock()

    for _, path in ipairs(self._paths) do
        local pointCount = #path.Points
        local pathAlpha = glyphFadeValue(path.Fade, now)
        local culled = self:_isFirstPersonPathCulled(path)

        -- Most source segments are static for ~2 seconds between point additions.
        -- Refresh the full path only when its alpha/cull/point-count changes;
        -- otherwise only the actively-growing tip needs a texture/alpha refresh.
        local refreshAll = path._VisualPointCount ~= pointCount
            or path._VisualCulled ~= culled
            or path._VisualAlpha == nil
            or math.abs(pathAlpha - path._VisualAlpha) >= 0.01

        if refreshAll then
            for segmentIndex, segment in ipairs(path.Segments) do
                self:_updateSegmentVisual(segment, segmentIndex, pointCount, pathAlpha, culled)
            end
        else
            local lastIndex = #path.Segments
            if lastIndex > 0 then
                self:_updateSegmentVisual(
                    path.Segments[lastIndex],
                    lastIndex,
                    pointCount,
                    pathAlpha,
                    culled
                )
            end
        end

        path._VisualPointCount = pointCount
        path._VisualCulled = culled
        path._VisualAlpha = pathAlpha
    end
end

function LineGlyphs:RefreshStyle()
    self:_loadAssets()
    for _, path in ipairs(self._paths) do
        path._VisualPointCount = nil
        path._VisualAlpha = nil
        for _, segment in ipairs(path.Segments) do
            self:_syncGlowBeam(segment)
            if segment.Beam and segment.Beam.Parent then
                self:_styleCoreBeam(segment.Beam)
            end
            if segment.GlowBeam and segment.GlowBeam.Parent then
                self:_styleGlowBeam(segment.GlowBeam)
            end
        end
    end
    self:_updateVisuals()
end

function LineGlyphs:Enable()
    if self.Enabled then
        return true
    end

    self:_destroyLegacyBloomEffect()
    if not self:_loadAssets() then
        notify("LineGlyphs: ixry_vfx_lineglyph_dash.png not found", 4)
        return false
    end

    if self.Config.Glow and (not self._glowDashAsset or not self._glowSolidAsset) then
        notify("LineGlyphs: glow textures missing; Glow disabled", 4)
        self.Config.Glow = false
    end

    self.Enabled = true
    self._accumulator = 0
    self._lastVisualUpdate = 0
    self:_ensureFolder()

    self._characterConnection = LocalPlayer.CharacterAdded:Connect(function()
        self:Clear()
        self._accumulator = 0
    end)

    self._renderConnection = RunService.RenderStepped:Connect(function(dt)
        if not self.Enabled then
            return
        end

        local step = 1 / math.max(1, self.Config.UpdateRate)
        self._accumulator = self._accumulator + math.min(dt, 0.1)

        local loops = 0
        while self._accumulator >= step and loops < 5 do
            self._accumulator = self._accumulator - step
            self:_tick()
            loops = loops + 1
        end

        local tickFraction = math.clamp(self._accumulator / step, 0, 1)
        self:_updateGeometry(tickFraction)

        local now = os.clock()
        if now - self._lastVisualUpdate >= (1 / 30) then
            self._lastVisualUpdate = now
            self:_updateVisuals()
        end
    end)

    return true
end

function LineGlyphs:Disable()
    if not self.Enabled then
        self:_destroyLegacyBloomEffect()
        return
    end

    self.Enabled = false
    disconnect(self._renderConnection)
    disconnect(self._characterConnection)
    self._renderConnection = nil
    self._characterConnection = nil
    self._accumulator = 0

    self:Clear()

    if self._folder and self._folder.Parent then
        self._folder:Destroy()
    end
    self._folder = nil
    self._anchor = nil
    self:_destroyLegacyBloomEffect()
end

function LineGlyphs:Cleanup()
    self:Disable()
end


-- ============================================================================
-- Persistent config + ODH UI
-- ============================================================================

-- ODH does not currently document an addon-config API, so this addon keeps its
-- own small JSON file. Only settings exposed in the UI are persisted.
local CONFIG_VERSION = 1
local CONFIG_DIR_CANDIDATES = {
    "Ixry Shizuka/plugins/Workspace/ODH_VFX_Addon_Data",
    "Ixry Shizuka/plugins/ODH_VFX_Addon_Data",
    "ODH_VFX_Addon_Data",
}

local function fsParent(path)
    return tostring(path):match("^(.*)/[^/]+$")
end

local function fsFolderExists(path)
    if type(isfolder) ~= "function" then
        return false
    end
    local ok, result = pcall(isfolder, path)
    return ok and result == true
end

local function fsEnsureFolder(path)
    if fsFolderExists(path) then
        return true
    end
    if type(makefolder) ~= "function" then
        return false
    end
    local parent = fsParent(path)
    if parent and parent ~= "" and not fsFolderExists(parent) then
        return false
    end
    local ok = pcall(makefolder, path)
    return ok and fsFolderExists(path)
end

local function chooseConfigPath()
    for _, dir in ipairs(CONFIG_DIR_CANDIDATES) do
        local parent = fsParent(dir)
        if not parent or parent == "" or fsFolderExists(parent) then
            if fsEnsureFolder(dir) then
                return dir .. "/config.json"
            end
        end
    end
    return nil
end

local CONFIG_PATH = chooseConfigPath()
local configRestoreInProgress = true
local configSaveGeneration = 0

local function colorToData(color)
    return {
        r = color.R,
        g = color.G,
        b = color.B,
    }
end

local function dataToColor(value, fallback)
    if type(value) ~= "table" then
        return fallback
    end
    local r = tonumber(value.r or value[1])
    local g = tonumber(value.g or value[2])
    local b = tonumber(value.b or value[3])
    if not r or not g or not b then
        return fallback
    end
    return Color3.new(
        math.clamp(r, 0, 1),
        math.clamp(g, 0, 1),
        math.clamp(b, 0, 1)
    )
end

local function readSavedConfig()
    if not CONFIG_PATH or type(isfile) ~= "function" or type(readfile) ~= "function" then
        return nil
    end
    local okExists, exists = pcall(isfile, CONFIG_PATH)
    if not okExists or not exists then
        return nil
    end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(CONFIG_PATH))
    end)
    if ok and type(decoded) == "table" then
        return decoded
    end
    return nil
end

local desiredEnabled = {
    JumpCircle = false,
    Cubes = false,
    LineGlyphs = false,
    Wings = false,
}

local function num(value, fallback, minimum, maximum)
    value = tonumber(value)
    if not value then
        return fallback
    end
    if minimum ~= nil then
        value = math.max(minimum, value)
    end
    if maximum ~= nil then
        value = math.min(maximum, value)
    end
    return value
end

local function applySavedConfig(saved)
    if type(saved) ~= "table" then
        return
    end

    local jump = saved.JumpCircle
    if type(jump) == "table" then
        desiredEnabled.JumpCircle = jump.Enabled == true
        if jump.Mode == "V-Core" or jump.Mode == "HitEffect" then
            JumpCircle.Config.Mode = jump.Mode
        end
        JumpCircle.Config.CircleScale = num(jump.CircleScale, JumpCircle.Config.CircleScale, 0.5, 3.0)
        JumpCircle.Config.RotateSpeed = num(jump.RotateSpeed, JumpCircle.Config.RotateSpeed, 0.5, 5.0)
        JumpCircle.Config.HitEffectMaxRadius = num(jump.HitEffectMaxRadius, JumpCircle.Config.HitEffectMaxRadius, 3, 12)
        JumpCircle.Config.HitEffectDuration = num(jump.HitEffectDuration, JumpCircle.Config.HitEffectDuration, 0.5, 4.0)
        JumpCircle.Config.HitEffectRingThickness = num(jump.HitEffectRingThickness, JumpCircle.Config.HitEffectRingThickness, 0.3, 1.5)
        if type(jump.AlignToGroundNormal) == "boolean" then JumpCircle.Config.AlignToGroundNormal = jump.AlignToGroundNormal end
        if type(jump.EaseOut) == "boolean" then JumpCircle.Config.EaseOut = jump.EaseOut end
        if type(jump.HitEffectFill) == "boolean" then JumpCircle.Config.HitEffectFill = jump.HitEffectFill end
        JumpCircle.Config.Color = dataToColor(jump.Color, JumpCircle.Config.Color)
    end

    local cubes = saved.Cubes
    if type(cubes) == "table" then
        desiredEnabled.Cubes = cubes.Enabled == true
        if cubes.Animation == "Scatter" or cubes.Animation == "Falling" then
            Cubes.Config.Animation = cubes.Animation
        end
        Cubes.Config.Count = math.floor(num(cubes.Count, Cubes.Config.Count, 5, 100) + 0.5)
        Cubes.Config.Size = num(cubes.Size, Cubes.Config.Size, 0.1, 3.0)
        Cubes.Config.Speed = num(cubes.Speed, Cubes.Config.Speed, 0.1, 5.0)
        if type(cubes.GlowEnabled) == "boolean" then Cubes.Config.GlowEnabled = cubes.GlowEnabled end
        if type(cubes.GlowNoDepth) == "boolean" then Cubes.Config.GlowNoDepth = cubes.GlowNoDepth end
        if type(cubes.DashedEdges) == "boolean" then Cubes.Config.DashedEdges = cubes.DashedEdges end
        if type(cubes.OutlineAlwaysOnTop) == "boolean" then Cubes.Config.OutlineAlwaysOnTop = cubes.OutlineAlwaysOnTop end
        Cubes.Config.Color = dataToColor(cubes.Color, Cubes.Config.Color)
    end

    local glyphs = saved.LineGlyphs
    if type(glyphs) == "table" then
        desiredEnabled.LineGlyphs = glyphs.Enabled == true
        LineGlyphs.Config.Count = math.floor(num(glyphs.Count, LineGlyphs.Config.Count, 10, 200) + 0.5)
        LineGlyphs.Config.Speed = num(glyphs.Speed, LineGlyphs.Config.Speed, 0.1, 5.0)
        LineGlyphs.Config.Thickness = num(glyphs.Thickness, LineGlyphs.Config.Thickness, 0.5, 5.0)
        if type(glyphs.Glow) == "boolean" then LineGlyphs.Config.Glow = glyphs.Glow end
        LineGlyphs.Config.Color = dataToColor(glyphs.Color, LineGlyphs.Config.Color)
    end

    local wings = saved.Wings
    if type(wings) == "table" then
        desiredEnabled.Wings = wings.Enabled == true
        Wings.Config.Size = num(wings.Size, Wings.Config.Size, 0.5, 3.0)
        Wings.Config.Alpha = math.floor(num(wings.Alpha, Wings.Config.Alpha, 60, 255) + 0.5)
        Wings.Config.AuraStrength = num(wings.AuraStrength, Wings.Config.AuraStrength, 0.0, 2.5)
        Wings.Config.AuraRadius = num(wings.AuraRadius, Wings.Config.AuraRadius, 0.0, 48.0)
        Wings.Config.OffsetX = num(wings.OffsetX, Wings.Config.OffsetX, -1.5, 1.5)
        Wings.Config.OffsetY = num(wings.OffsetY, Wings.Config.OffsetY, -1.5, 1.5)
        Wings.Config.OffsetZ = num(wings.OffsetZ, Wings.Config.OffsetZ, -1.5, 1.5)
        if type(wings.AuraEnabled) == "boolean" then Wings.Config.AuraEnabled = wings.AuraEnabled end
        if type(wings.Self) == "boolean" then Wings.Config.Self = wings.Self end
        if type(wings.Players) == "boolean" then Wings.Config.Players = wings.Players end
        Wings.Config.Color = dataToColor(wings.Color, Wings.Config.Color)
    end
end

applySavedConfig(readSavedConfig())

local function snapshotConfig()
    return {
        version = CONFIG_VERSION,
        JumpCircle = {
            Enabled = JumpCircle.Enabled,
            Mode = JumpCircle.Config.Mode,
            CircleScale = JumpCircle.Config.CircleScale,
            RotateSpeed = JumpCircle.Config.RotateSpeed,
            Color = colorToData(JumpCircle.Config.Color),
            AlignToGroundNormal = JumpCircle.Config.AlignToGroundNormal,
            EaseOut = JumpCircle.Config.EaseOut,
            HitEffectMaxRadius = JumpCircle.Config.HitEffectMaxRadius,
            HitEffectDuration = JumpCircle.Config.HitEffectDuration,
            HitEffectRingThickness = JumpCircle.Config.HitEffectRingThickness,
            HitEffectFill = JumpCircle.Config.HitEffectFill,
        },
        Cubes = {
            Enabled = Cubes.Enabled,
            Animation = Cubes.Config.Animation,
            Count = Cubes.Config.Count,
            Size = Cubes.Config.Size,
            Speed = Cubes.Config.Speed,
            Color = colorToData(Cubes.Config.Color),
            GlowEnabled = Cubes.Config.GlowEnabled,
            GlowNoDepth = Cubes.Config.GlowNoDepth,
            DashedEdges = Cubes.Config.DashedEdges,
            OutlineAlwaysOnTop = Cubes.Config.OutlineAlwaysOnTop,
        },
        LineGlyphs = {
            Enabled = LineGlyphs.Enabled,
            Count = LineGlyphs.Config.Count,
            Speed = LineGlyphs.Config.Speed,
            Glow = LineGlyphs.Config.Glow,
            Thickness = LineGlyphs.Config.Thickness,
            Color = colorToData(LineGlyphs.Config.Color),
        },
        Wings = {
            Enabled = Wings.Enabled,
            Size = Wings.Config.Size,
            Alpha = Wings.Config.Alpha,
            Color = colorToData(Wings.Config.Color),
            AuraEnabled = Wings.Config.AuraEnabled,
            AuraStrength = Wings.Config.AuraStrength,
            AuraRadius = Wings.Config.AuraRadius,
            Self = Wings.Config.Self,
            Players = Wings.Config.Players,
            OffsetX = Wings.Config.OffsetX,
            OffsetY = Wings.Config.OffsetY,
            OffsetZ = Wings.Config.OffsetZ,
        },
    }
end

local function saveConfigNow()
    if configRestoreInProgress or not CONFIG_PATH or type(writefile) ~= "function" then
        return
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(snapshotConfig())
    end)
    if ok then
        pcall(writefile, CONFIG_PATH, encoded)
    end
end

local function queueConfigSave()
    if configRestoreInProgress then
        return
    end
    configSaveGeneration = configSaveGeneration + 1
    local generation = configSaveGeneration
    task.delay(0.30, function()
        if generation == configSaveGeneration then
            saveConfigNow()
        end
    end)
end

local tab = shared.CreateTab(
    "Visual Effects",
    "/axioriasolver/testplugin/refs/heads/main/icon"
)

local jumpSection = tab:AddSection("JumpCircle", "Jump effect styles & settings")
jumpSection:AddParagraph(
    "JumpCircle",
    "Choose a jump-effect style and tune its shared or style-specific settings below."
)

local jumpEnabledToggle = jumpSection:AddToggle("Enabled", function(state)
    if state then
        if JumpCircle:Enable() then
            notify("JumpCircle enabled", 2)
        end
    else
        JumpCircle:Disable()
        notify("JumpCircle disabled", 2)
    end
    queueConfigSave()
end)

local MODE_DISPLAY_TO_INTERNAL = {
    ["Pulse Ring"] = "V-Core",
    ["Voxel Ripple"] = "HitEffect",
}
local MODE_INTERNAL_TO_DISPLAY = {
    ["V-Core"] = "Pulse Ring",
    ["HitEffect"] = "Voxel Ripple",
}

local jumpModeDropdown = jumpSection:AddDropdown("Style", {"Pulse Ring", "Voxel Ripple"}, function(selected)
    local internal = MODE_DISPLAY_TO_INTERNAL[selected]
    if internal then
        JumpCircle.Config.Mode = internal
        JumpCircle:Clear()
        if internal == "V-Core" and not JumpCircle:_loadAsset() then
            notify("JumpCircle: ixry_vfx_jumpcircle.png not found", 4)
        end
        queueConfigSave()
    end
end)
pcall(function()
    jumpModeDropdown:Select(MODE_INTERNAL_TO_DISPLAY[JumpCircle.Config.Mode] or "Pulse Ring")
end)

jumpSection:AddSlider("Effect Scale", 0.5, 3.0, JumpCircle.Config.CircleScale, function(value)
    JumpCircle.Config.CircleScale = value
    queueConfigSave()
end)

jumpSection:AddColorpicker("Effect Color", JumpCircle.Config.Color, function(color)
    JumpCircle.Config.Color = color
    queueConfigSave()
end)

local alignGroundToggle = jumpSection:AddToggle("Align To Ground", function(state)
    JumpCircle.Config.AlignToGroundNormal = state
    queueConfigSave()
end)
if JumpCircle.Config.AlignToGroundNormal then alignGroundToggle() end

jumpSection:AddLabel("Pulse Ring Settings")
jumpSection:AddSlider("Rotate Speed", 0.5, 5.0, JumpCircle.Config.RotateSpeed, function(value)
    JumpCircle.Config.RotateSpeed = value
    queueConfigSave()
end)

local easeOutToggle = jumpSection:AddToggle("Ease Out", function(state)
    JumpCircle.Config.EaseOut = state
    queueConfigSave()
end)
if JumpCircle.Config.EaseOut then easeOutToggle() end

jumpSection:AddLabel("Voxel Ripple Settings")
jumpSection:AddSlider("Wave Radius", 3, 12, JumpCircle.Config.HitEffectMaxRadius, function(value)
    JumpCircle.Config.HitEffectMaxRadius = value
    queueConfigSave()
end)
jumpSection:AddSlider("Duration", 0.5, 4.0, JumpCircle.Config.HitEffectDuration, function(value)
    JumpCircle.Config.HitEffectDuration = value
    queueConfigSave()
end)
jumpSection:AddSlider("Wave Width", 0.3, 1.5, JumpCircle.Config.HitEffectRingThickness, function(value)
    JumpCircle.Config.HitEffectRingThickness = value
    queueConfigSave()
end)
local hitFillToggle = jumpSection:AddToggle("Cell Fill", function(state)
    JumpCircle.Config.HitEffectFill = state
    queueConfigSave()
end)
if JumpCircle.Config.HitEffectFill then hitFillToggle() end
jumpSection:AddButton("Clear Effects", function() JumpCircle:Clear() end)

local cubesSection = tab:AddSection("Cubes", "Ambient cube settings")
cubesSection:AddParagraph("Cubes", "Ambient cubes with glow, dashed outline and Scatter/Falling animation.")
local cubesEnabledToggle = cubesSection:AddToggle("Cubes", function(state)
    if state then
        Cubes:Enable()
        notify("Cubes enabled", 2)
    else
        Cubes:Disable()
        notify("Cubes disabled", 2)
    end
    queueConfigSave()
end)
local cubesAnimationDropdown = cubesSection:AddDropdown("Animation", {"Scatter", "Falling"}, function(selected)
    if selected == "Scatter" or selected == "Falling" then
        Cubes.Config.Animation = selected
        if Cubes.Enabled then Cubes:Rebuild() end
        queueConfigSave()
    end
end)
pcall(function() cubesAnimationDropdown:Select(Cubes.Config.Animation) end)
cubesSection:AddSlider("Count", 5, 100, Cubes.Config.Count, function(value)
    Cubes.Config.Count = math.floor(value + 0.5)
    queueConfigSave()
end)
cubesSection:AddSlider("Size", 0.1, 3.0, Cubes.Config.Size, function(value)
    Cubes.Config.Size = value
    if Cubes.Enabled then Cubes:Rebuild() end
    queueConfigSave()
end)
cubesSection:AddSlider("Speed", 0.1, 5.0, Cubes.Config.Speed, function(value)
    Cubes.Config.Speed = value
    queueConfigSave()
end)
cubesSection:AddColorpicker("Cube Color", Cubes.Config.Color, function(color)
    Cubes.Config.Color = color
    queueConfigSave()
end)
local glowToggle = cubesSection:AddToggle("Glow", function(state)
    Cubes.Config.GlowEnabled = state
    if Cubes.Enabled then Cubes:Rebuild() end
    queueConfigSave()
end)
if Cubes.Config.GlowEnabled then glowToggle() end
local glowDepthToggle = cubesSection:AddToggle("Glow No Depth (Wraith)", function(state)
    Cubes.Config.GlowNoDepth = state
    queueConfigSave()
end)
if Cubes.Config.GlowNoDepth then glowDepthToggle() end
local dashedOutlineToggle = cubesSection:AddToggle("Dashed Outline", function(state)
    Cubes.Config.DashedEdges = state
    if Cubes.Enabled then Cubes:Rebuild() end
    queueConfigSave()
end)
if Cubes.Config.DashedEdges then dashedOutlineToggle() end
local outlineTopToggle = cubesSection:AddToggle("Outline Always On Top", function(state)
    Cubes.Config.OutlineAlwaysOnTop = state
    queueConfigSave()
end)
if Cubes.Config.OutlineAlwaysOnTop then outlineTopToggle() end
cubesSection:AddButton("Clear Cubes", function() Cubes:Clear() end)

local glyphSection = tab:AddSection("LineGlyphs", "Wraith ambient line paths")
glyphSection:AddParagraph("LineGlyphs", "Axis-aligned dashed glyph paths with source-style growth, fade and emissive glow.")
local glyphEnabledToggle = glyphSection:AddToggle("LineGlyphs", function(state)
    if state then
        if LineGlyphs:Enable() then notify("LineGlyphs enabled", 2) end
    else
        LineGlyphs:Disable()
        notify("LineGlyphs disabled", 2)
    end
    queueConfigSave()
end)
glyphSection:AddSlider("Count", 10, 200, LineGlyphs.Config.Count, function(value)
    LineGlyphs.Config.Count = math.floor(value + 0.5)
    queueConfigSave()
end)
glyphSection:AddSlider("Speed", 0.1, 5.0, LineGlyphs.Config.Speed, function(value)
    LineGlyphs.Config.Speed = value
    queueConfigSave()
end)
local glyphGlowToggle = glyphSection:AddToggle("Glow", function(state)
    LineGlyphs.Config.Glow = state
    LineGlyphs:RefreshStyle()
    queueConfigSave()
end)
if LineGlyphs.Config.Glow then glyphGlowToggle() end
glyphSection:AddSlider("Thickness", 0.5, 5.0, LineGlyphs.Config.Thickness, function(value)
    LineGlyphs.Config.Thickness = value
    LineGlyphs:RefreshStyle()
    queueConfigSave()
end)
glyphSection:AddColorpicker("Glyph Color", LineGlyphs.Config.Color, function(color)
    LineGlyphs.Config.Color = color
    LineGlyphs:RefreshStyle()
    queueConfigSave()
end)
glyphSection:AddButton("Clear Glyphs", function() LineGlyphs:Clear() end)

local wingsSection = tab:AddSection("Wings", "Prism wing effect")
wingsSection:AddParagraph("Wings", "Animated Prism wings with local soft aura and Wraith-inspired flap motion.")
local wingsEnabledToggle = wingsSection:AddToggle("Wings", function(state)
    if state then
        if Wings:Enable() then notify("Wings enabled", 2) end
    else
        Wings:Disable()
        notify("Wings disabled", 2)
    end
    queueConfigSave()
end)
wingsSection:AddSlider("Size", 0.5, 3.0, Wings.Config.Size, function(value)
    Wings.Config.Size = value
    queueConfigSave()
end)
wingsSection:AddSlider("Opacity", 60, 255, Wings.Config.Alpha, function(value)
    Wings.Config.Alpha = math.floor(value + 0.5)
    queueConfigSave()
end)
wingsSection:AddColorpicker("Wing Color", Wings.Config.Color, function(color)
    Wings.Config.Color = color
    queueConfigSave()
end)
wingsSection:AddLabel("Aura / Bloom")
local wingBloomToggle = wingsSection:AddToggle("Bloom Aura", function(state)
    Wings.Config.AuraEnabled = state
    queueConfigSave()
end)
if Wings.Config.AuraEnabled then wingBloomToggle() end
wingsSection:AddSlider("Aura Strength", 0.0, 2.5, Wings.Config.AuraStrength, function(value)
    Wings.Config.AuraStrength = value
    queueConfigSave()
end)
wingsSection:AddSlider("Aura Radius", 0.0, 48.0, Wings.Config.AuraRadius, function(value)
    Wings.Config.AuraRadius = value
    queueConfigSave()
end)
local wingSelfToggle = wingsSection:AddToggle("Self", function(state)
    Wings.Config.Self = state
    queueConfigSave()
end)
if Wings.Config.Self then wingSelfToggle() end
local wingPlayersToggle = wingsSection:AddToggle("Other Players", function(state)
    Wings.Config.Players = state
    queueConfigSave()
end)
if Wings.Config.Players then wingPlayersToggle() end

wingsSection:AddLabel("Position")
-- Current ODH sliders support float values directly, so offsets no longer need
-- the old integer x100 workaround.
wingsSection:AddSlider("Offset X", -1.5, 1.5, Wings.Config.OffsetX, function(value)
    Wings.Config.OffsetX = value
    queueConfigSave()
end)
wingsSection:AddSlider("Offset Y", -1.5, 1.5, Wings.Config.OffsetY, function(value)
    Wings.Config.OffsetY = value
    queueConfigSave()
end)
wingsSection:AddSlider("Offset Z", -1.5, 1.5, Wings.Config.OffsetZ, function(value)
    Wings.Config.OffsetZ = value
    queueConfigSave()
end)
wingsSection:AddButton("Clear Wings", function() Wings:Clear() end)

-- Restore module enabled states only after all controls exist. Toggle callbacks
-- are intentionally suppressed from writing config while restoration is active.
if desiredEnabled.JumpCircle then jumpEnabledToggle() end
if desiredEnabled.Cubes then cubesEnabledToggle() end
if desiredEnabled.LineGlyphs then glyphEnabledToggle() end
if desiredEnabled.Wings then wingsEnabledToggle() end
configRestoreInProgress = false

local function cleanupAddon()
    saveConfigNow()
    JumpCircle:Cleanup()
    Cubes:Cleanup()
    Wings:Cleanup()
    LineGlyphs:Cleanup()

    if ENV[ADDON_RUNTIME_KEY]
        and ENV[ADDON_RUNTIME_KEY].Cleanup == cleanupAddon then
        ENV[ADDON_RUNTIME_KEY] = nil
    end
end

ENV[ADDON_RUNTIME_KEY] = {
    JumpCircle = JumpCircle,
    Cubes = Cubes,
    Wings = Wings,
    LineGlyphs = LineGlyphs,
    ConfigPath = CONFIG_PATH,
    SaveConfig = saveConfigNow,
    Cleanup = cleanupAddon,
}
