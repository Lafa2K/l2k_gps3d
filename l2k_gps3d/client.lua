--[[
===============================================================================
 l2k_gps3d
-----------------------------------------------------------------------------
 3D GPS ribbon renderer for:
 - USER route    = manual waypoint
 - MISSION route = active blip GPS route

 Main commands:
 - /gps3d
 - /gps3d_route manual|blip|toggle|status
 - /gpspreset index|next|prev|status
 - /gpscolordefault r g b [a]
 - /gpscolormission r g b [a]

 Main exports:
 - SetEnabled(enabled)
 - SetActiveRouteSource(source)
 - SetTrackedBlip(blip)
 - ClearTrackedBlip()
 - SetRoutePreset(index)
 - SetDefaultRouteColor(r, g, b, a)
 - SetMissionRouteColor(r, g, b, a)
===============================================================================
]]

local function clampColorChannel(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        return fallback or 255
    end

    return math.floor(math.max(0, math.min(255, numeric)))
end

local function copyColor(color, fallback)
    local base = color or fallback or { r = 255, g = 255, b = 255, a = 255 }
    return {
        r = clampColorChannel(base.r, 255),
        g = clampColorChannel(base.g, 255),
        b = clampColorChannel(base.b, 255),
        a = clampColorChannel(base.a, 255),
    }
end

local function colorsEqual(a, b)
    if not a or not b then
        return false
    end

    return clampColorChannel(a.r, 0) == clampColorChannel(b.r, 0)
        and clampColorChannel(a.g, 0) == clampColorChannel(b.g, 0)
        and clampColorChannel(a.b, 0) == clampColorChannel(b.b, 0)
        and clampColorChannel(a.a, 255) == clampColorChannel(b.a, 255)
end

local Config = {
    -- General
    enabled = true,
    drawWhenOnFoot = false,
    ignoredVehicleClasses = {
        [14] = true, -- boats
        [16] = true, -- planes
    },

    -- Route sources
    routeSource = 'manual',
    routeSources = {
        manual = true,
        blip = true,
        multi = false, -- intentionally ignored
    },
    enableExternalBlipRouteCapture = true,
    externalBlipRouteScanIntervalMs = 1000,
    routeSwitchKeysEnabled = true,
    shortcutRouteToggleEnabled = true,
    shortcutColorCycleEnabled = true,
    shortcutPresetCycleEnabled = true,
    shortcutGpsToggleEnabled = true,
    shortcutAnimationToggleEnabled = true,
    shortcutModifierKey = 21, -- SHIFT
    routeSwitchKeyUp = 188,
    routeColorKey = 246, -- Y
    routePresetKeyLeft = 189,
    routePresetKeyRight = 190,
    routeToggleKey = 187, -- DOWN
    routeAnimationToggleKey = 303, -- U
    routeToggleCooldownMs = 10000,

    -- Route sampling
    lowSpeedSampleStep = 6.0,
    mediumSpeedSampleStep = 7.5,
    highSpeedSampleStep = 9.0,
    lowSpeedRouteDistance = 90.0,
    mediumSpeedRouteDistance = 150.0,
    highSpeedRouteDistance = 200.0,
    mediumSpeedKmh = 100.0,
    highSpeedKmh = 200.0,

    -- Junction smoothing
    ignoreJunctionNodes = false,
    smoothJunctionTransitions = true,
    junctionPaddingPoints = 1,
    junctionCurveStrength = 0.22,
    junctionCurveMaxHandle = 6.2,

    -- Route placement
    routeHeight = 0.22,

    -- Periodic update by velocity
    lowSpeedUpdateMs = 2500,
    mediumSpeedUpdateMs = 1500,
    highSpeedUpdateMs = 500,
    periodicRebuildEnabled = true,

    -- Route extend
    routeExtendNearEndEnabled = true,
    routeExtendNearEndPoints = 30,
    routeExtendNearEndDistance = 130.0,
    routeExtendMaxJoinDistance = 10.0,
    routeExtendCooldownMs = 700,

    -- Route trim
    routeTrimBehindEnabled = true,
    routeTrimKeepBehindPoints = 18,
    routeTrimMinHeadDistance = 100.0,

    -- Draw culling
    markerDrawAheadOnly = true,
    markerBehindCullBuffer = -2.5,

    -- Off-route rebuild
    offRouteRebuildEnabled = true,
    offRouteRebuildDistance = 14.0,
    offRouteRebuildConfirmMs = 500,
    offRouteRebuildCooldownMs = 1400,
    offRouteRebuildMinSpeedKmh = 100.0,

    -- Ground / Z
    routeGroundProbeEnabled = true,
    routeGroundProbeZ = 1000.0,
    routeGroundOffset = 0.0,
    routeGroundMaxDelta = 2.5,
    routeHeightAssistEnabled = false,
    routeHeightAssistBlend = 0.45,
    routeHeightAssistMaxDelta = 3.0,
    groundProbeCacheEnabled = true,
    groundProbeCacheCell = 1.0,
    groundProbeCacheTtlMs = 1200,
    groundProbeCacheMaxEntries = 1500,

    -- Ribbon
    texturedRoute = {
        width = 1.35,
        lift = 0.03,
        repeatDistance = 4.0,
        maxMiterScale = 1.35,
        nearFadeEnabled = true,
        nearFadeDistance = 12.0,
        nearFadeStartAlpha = 0.0,
    },

    -- Presets
    currentRoutePreset = 0,
    routePresets = {
        [0] = {
            name = 'Classic Chevron',
            textureDict = 'chevrons',
            textureName = 'chevrons',
        },
        [1] = {
            name = 'chevron_line_06',
            textureDict = 'chevrons',
            textureName = 'chevron_line_06',
        },
        [2] = {
            name = 'chevron_fire_01',
            textureDict = 'chevrons',
            textureName = 'chevron_fire_01',
        },
        [3] = {
            name = 'chevron_ice_01',
            textureDict = 'chevrons',
            textureName = 'chevron_ice_01',
        },
        [4] = {
            name = 'chevron_neon_01',
            textureDict = 'chevrons',
            textureName = 'chevron_neon_01',
        },
        [5] = {
            name = 'chevron_line_05',
            textureDict = 'chevrons',
            textureName = 'chevron_line_05',
        },
        [6] = {
            name = 'chevron_line_07',
            textureDict = 'chevrons',
            textureName = 'chevron_line_07',
        },
        [7] = {
            name = 'chevron_line_01',
            textureDict = 'chevrons',
            textureName = 'chevron_line_01',
        },
        [8] = {
            name = 'chevron_line_02',
            textureDict = 'chevrons',
            textureName = 'chevron_line_02',
        },
        [9] = {
            name = 'chevron_line_08',
            textureDict = 'chevrons',
            textureName = 'chevron_line_08',
        },
        [10] = {
            name = 'chevron_line_04',
            textureDict = 'chevrons',
            textureName = 'chevron_line_04',
        },
        [11] = {
            name = 'chevron_line_03',
            textureDict = 'chevrons',
            textureName = 'chevron_line_03',
        },
    },
    routeColorPalette = {
        { name = 'Hot Red', color = { r = 255, g = 0, b = 0, a = 205 } },
        { name = 'Crimson', color = { r = 220, g = 20, b = 60, a = 205 } },
        { name = 'Orange Red', color = { r = 255, g = 69, b = 0, a = 205 } },
        { name = 'Amber', color = { r = 255, g = 140, b = 0, a = 205 } },
        { name = 'Gold', color = { r = 255, g = 184, b = 28, a = 205 } },
        { name = 'Sun Yellow', color = { r = 255, g = 214, b = 64, a = 205 } },
        { name = 'Rose Pink', color = { r = 255, g = 92, b = 138, a = 205 } },
        { name = 'Magenta', color = { r = 255, g = 0, b = 140, a = 205 } },
        { name = 'Ice Blue', color = { r = 100, g = 210, b = 255, a = 205 } },
        { name = 'White', color = { r = 255, g = 255, b = 255, a = 205 } },
    },

    -- Mode switch feedback
    modeFxEnabled = true,
    modeFxName = 'SwitchHUDOut',
    modeFxDurationMs = 300,
    modeFxSoundName = '5_SEC_WARNING',
    modeFxSoundSet = 'HUD_MINI_GAME_SOUNDSET',
    noRouteSoundName = 'ERROR',
    noRouteSoundSet = 'HUD_FRONTEND_DEFAULT_SOUNDSET',

    -- Extra animations
    extraAnimationsEnabled = true,
    animationOnEnabled = true,
    animationOffEnabled = true,
    geoAnimIntroProfile = 'on',
    geoAnimQuickOnProfile = 'on_fast',
    geoAnimOffProfile = 'off',

    -- 3D mode banner
    modeHintEnabled = true,
    modeHintDurationMs = 1800,
    modeHintUserText = 'GPS MODE: USER',
    modeHintMissionText = 'GPS MODE: MISSION',
    modeHintOffText = 'GPS MODE: OFF',
    modeHintAnchorOffsetZ = 1.1,
    modeHintTextOffsetZ = 2.0,
    modeHintLineColor = { r = 255, g = 255, b = 255, a = 165 },
}

local initialPreset = Config.routePresets[Config.currentRoutePreset] or Config.routePresets[0]

local NodeFlags = {
    JUNCTION = 128,
}

local state = {
    enabled = Config.enabled,
    routeSource = Config.routeSource,
    points = {},
    activeSlot = nil,
    lastUpdate = 0,
    routeLength = 0.0,
    destinationPos = nil,
    groundProbeCache = {},
    lastGroundProbeCleanup = 0,
    lastExtendAttempt = 0,
    offRouteSince = 0,
    lastOffRouteRebuild = 0,
    trackedBlip = 0,
    trackedBlipDestination = nil,
    trackedBlipMode = 'none', -- none | external | explicit
    lastExternalBlipScan = 0,
    texturedRouteReady = false,
    texturedRouteDict = nil,
    routePresetIndex = Config.currentRoutePreset,
    defaultRouteColor = copyColor(initialPreset and initialPreset.defaultColor),
    missionRouteColor = copyColor(initialPreset and initialPreset.missionColor),
    modeHintText = nil,
    modeHintUntil = 0,
    modeHintColor = copyColor(initialPreset and initialPreset.defaultColor),
    modeFxToken = 0,
    gpsToggleCooldownUntil = 0,
    extraAnimationsEnabled = Config.extraAnimationsEnabled ~= false,
    geoAnimIntroPlayed = false,
}

local function notify(message)
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 255 },
        multiline = false,
        args = { 'l2k_gps3d', message }
    })
end

local function clearRouteState()
    state.points = {}
    state.activeSlot = nil
    state.routeLength = 0.0
    state.destinationPos = nil
    state.lastExtendAttempt = 0
    state.offRouteSince = 0
end

local function isIgnoredVehicleClass(vehicle)
    if not vehicle or vehicle == 0 or type(GetVehicleClass) ~= 'function' then
        return false
    end

    local ignoredClasses = Config.ignoredVehicleClasses
    if type(ignoredClasses) ~= 'table' then
        return false
    end

    local vehicleClass = GetVehicleClass(vehicle)
    return ignoredClasses[vehicleClass] == true
end

local function getGpsEligibleVehicle(ped)
    if not ped or ped == 0 or not IsPedInAnyVehicle(ped, false) then
        return 0
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 or isIgnoredVehicleClass(vehicle) then
        return 0
    end

    return vehicle
end

local function canUseGpsShortcuts()
    local ped = PlayerPedId()
    return getGpsEligibleVehicle(ped) ~= 0
end

local function parseColorInput(args, rawCommand)
    local values = {}

    if type(rawCommand) == 'string' and rawCommand ~= '' then
        local payload = rawCommand:gsub('^%S+%s*', '')
        payload = payload:gsub('^rgba?%s*%(', '')
        payload = payload:gsub('%)', ' ')

        for token in payload:gmatch('[%+%-]?%d+%.?%d*') do
            values[#values + 1] = tonumber(token)
            if #values >= 4 then
                break
            end
        end
    end

    if #values == 0 and type(args) == 'table' then
        for i = 1, 4 do
            local numeric = tonumber(args[i] or '')
            if numeric ~= nil then
                values[#values + 1] = numeric
            end
        end
    end

    return values[1], values[2], values[3], values[4]
end

local function vecLength2(v)
    return (v.x * v.x) + (v.y * v.y) + (v.z * v.z)
end

local function vecLength2D(v)
    return (v.x * v.x) + (v.y * v.y)
end

local function vecNormalize2D(v)
    local magnitude = math.sqrt((v.x * v.x) + (v.y * v.y))
    if magnitude < 0.0001 then
        return vector3(0.0, 0.0, 0.0)
    end

    return vector3(v.x / magnitude, v.y / magnitude, 0.0)
end

local function vecDistance2D(a, b)
    if not a or not b then
        return 0.0
    end

    local delta = a - b
    return math.sqrt((delta.x * delta.x) + (delta.y * delta.y))
end

local function pointToSegmentDistance2D(p, a, b)
    local ab = b - a
    local abLen2 = vecLength2D(ab)
    if abLen2 < 0.0001 then
        return vecDistance2D(p, a)
    end

    local ap = p - a
    local t = ((ap.x * ab.x) + (ap.y * ab.y)) / abLen2
    if t < 0.0 then
        t = 0.0
    elseif t > 1.0 then
        t = 1.0
    end

    local nearest = vector3(a.x + (ab.x * t), a.y + (ab.y * t), 0.0)
    return vecDistance2D(p, nearest)
end

local function positionsClose2D(a, b, threshold)
    if a == nil or b == nil then
        return a == b
    end

    local maxDist = threshold or 0.0
    return vecLength2D(a - b) <= (maxDist * maxDist)
end

local function cubicBezier(p0, p1, p2, p3, t)
    local omt = 1.0 - t
    local omt2 = omt * omt
    local omt3 = omt2 * omt
    local t2 = t * t
    local t3 = t2 * t

    return (p0 * omt3)
        + (p1 * (3.0 * omt2 * t))
        + (p2 * (3.0 * omt * t2))
        + (p3 * t3)
end

local function clonePoint(point)
    return {
        pos = vector3(point.pos.x, point.pos.y, point.pos.z),
        junction = point.junction,
        junctionZone = point.junctionZone,
    }
end

local function getDirection(points, fromIndex, toIndex, fallback)
    if fromIndex < 1 or toIndex < 1 or fromIndex > #points or toIndex > #points then
        return fallback or vector3(0.0, 0.0, 0.0)
    end

    local dir = vecNormalize2D(points[toIndex].pos - points[fromIndex].pos)
    if vecLength2D(dir) < 0.0001 then
        return fallback or vector3(0.0, 0.0, 0.0)
    end

    return dir
end

local function getRoutePresetIndices()
    local indices = {}

    for index in pairs(Config.routePresets or {}) do
        indices[#indices + 1] = index
    end

    table.sort(indices, function(a, b)
        return a < b
    end)

    return indices
end

local function normalizePresetIndex(index)
    local presetIndices = getRoutePresetIndices()
    if #presetIndices == 0 then
        return 0
    end

    local numeric = tonumber(index)
    if numeric == nil then
        return Config.currentRoutePreset or presetIndices[1]
    end

    numeric = math.floor(numeric)
    for i = 1, #presetIndices do
        if presetIndices[i] == numeric then
            return numeric
        end
    end

    return Config.currentRoutePreset or presetIndices[1]
end

local function getCurrentPreset()
    local presetIndex = normalizePresetIndex(state.routePresetIndex)
    return Config.routePresets[presetIndex] or Config.routePresets[0]
end

local function getRouteColorPaletteIndex(color)
    local palette = Config.routeColorPalette or {}
    for i = 1, #palette do
        local entry = palette[i]
        if entry and colorsEqual(entry.color, color) then
            return i
        end
    end

    return 0
end

local function getActiveRouteTint()
    if state.routeSource == 'blip' then
        return state.missionRouteColor
    end

    return state.defaultRouteColor
end

local function ensureTexturedRouteReady()
    local preset = getCurrentPreset()
    if not preset then
        return false
    end

    local textureDict = preset.textureDict
    if type(textureDict) ~= 'string' or textureDict == '' then
        return false
    end

    if state.texturedRouteReady and state.texturedRouteDict == textureDict
        and type(HasStreamedTextureDictLoaded) == 'function'
        and HasStreamedTextureDictLoaded(textureDict) then
        return true
    end

    if type(RequestStreamedTextureDict) ~= 'function' or type(HasStreamedTextureDictLoaded) ~= 'function' then
        return false
    end

    RequestStreamedTextureDict(textureDict, true)
    if HasStreamedTextureDictLoaded(textureDict) then
        state.texturedRouteReady = true
        state.texturedRouteDict = textureDict
    end

    return state.texturedRouteReady
end

local function getWaypointBlipHandle()
    if type(GetFirstBlipInfoId) ~= 'function' or type(DoesBlipExist) ~= 'function' then
        return 0
    end

    local blip = GetFirstBlipInfoId(8)
    if blip and blip ~= 0 and DoesBlipExist(blip) then
        return blip
    end

    return 0
end

local function getWaypointDestination()
    if type(GetBlipInfoIdCoord) ~= 'function' then
        return nil
    end

    local blip = getWaypointBlipHandle()
    if blip == 0 then
        return nil
    end

    local coords = GetBlipInfoIdCoord(blip)
    if not coords then
        return nil
    end

    return vector3(coords.x, coords.y, coords.z)
end

local function updateTrackedBlipDestination()
    if state.trackedBlip == 0 or type(GetBlipInfoIdCoord) ~= 'function' or not DoesBlipExist(state.trackedBlip) then
        state.trackedBlipDestination = nil
        return
    end

    local coords = GetBlipInfoIdCoord(state.trackedBlip)
    if coords then
        state.trackedBlipDestination = vector3(coords.x, coords.y, coords.z)
    else
        state.trackedBlipDestination = nil
    end
end

local function setTrackedBlipState(blip, destination, mode)
    state.trackedBlip = blip or 0
    state.trackedBlipDestination = destination
    state.trackedBlipMode = mode or 'none'
end

local function clearTrackedBlipState()
    setTrackedBlipState(0, nil, 'none')
end

local function getTrackedBlipHandle()
    if state.trackedBlip ~= 0 and (type(DoesBlipExist) ~= 'function' or not DoesBlipExist(state.trackedBlip)) then
        clearTrackedBlipState()
    end

    return state.trackedBlip or 0
end

local function getTrackedBlipDestination()
    local blip = getTrackedBlipHandle()
    if blip == 0 then
        return nil
    end

    updateTrackedBlipDestination()
    return state.trackedBlipDestination
end

local function doesBlipRouteExist(blip)
    if blip == 0 or type(DoesBlipExist) ~= 'function' or not DoesBlipExist(blip) then
        return false
    end

    if type(DoesBlipHaveGpsRoute) ~= 'function' then
        return false
    end

    return DoesBlipHaveGpsRoute(blip)
end

local function findExternalGpsRouteBlip()
    if type(DoesBlipHaveGpsRoute) ~= 'function'
        or type(GetFirstBlipInfoId) ~= 'function'
        or type(GetNextBlipInfoId) ~= 'function'
        or type(DoesBlipExist) ~= 'function'
        or type(GetBlipInfoIdCoord) ~= 'function' then
        return 0, nil
    end

    local waypointBlip = getWaypointBlipHandle()

    for sprite = 1, 826 do
        local blip = GetFirstBlipInfoId(sprite)
        while blip and blip ~= 0 do
            if blip ~= waypointBlip and DoesBlipExist(blip) and DoesBlipHaveGpsRoute(blip) then
                local coords = GetBlipInfoIdCoord(blip)
                if coords then
                    return blip, vector3(coords.x, coords.y, coords.z)
                end
                return blip, nil
            end

            blip = GetNextBlipInfoId(sprite)
        end
    end

    return 0, nil
end

local function refreshExternalTrackedBlip(force)
    if state.trackedBlipMode == 'explicit' then
        if getTrackedBlipHandle() ~= 0 then
            updateTrackedBlipDestination()
        else
            clearTrackedBlipState()
        end
        return
    end

    if Config.enableExternalBlipRouteCapture ~= true then
        if state.trackedBlipMode == 'external' then
            clearTrackedBlipState()
        end
        return
    end

    local now = GetGameTimer()
    if not force and now - (state.lastExternalBlipScan or 0) < (Config.externalBlipRouteScanIntervalMs or 1000) then
        return
    end

    state.lastExternalBlipScan = now

    local blip, destination = findExternalGpsRouteBlip()
    if blip ~= 0 then
        setTrackedBlipState(blip, destination, 'external')
    elseif state.trackedBlipMode == 'external' then
        clearTrackedBlipState()
    end
end

local function hasManualRouteAvailable()
    return getWaypointDestination() ~= nil
end

local function hasBlipRouteAvailable()
    if Config.routeSources.blip ~= true then
        return false
    end

    local blip = getTrackedBlipHandle()
    return blip ~= 0 and doesBlipRouteExist(blip)
end

local function getAvailableRouteSources()
    local sources = {}

    if Config.routeSources.manual ~= false and hasManualRouteAvailable() then
        sources[#sources + 1] = 'manual'
    end

    if Config.routeSources.blip == true and hasBlipRouteAvailable() then
        sources[#sources + 1] = 'blip'
    end

    return sources
end

local function getCurrentRouteMaxDistance()
    local ped = PlayerPedId()
    local speedKmh = 0.0

    local vehicle = getGpsEligibleVehicle(ped)
    if vehicle ~= 0 then
        speedKmh = GetEntitySpeed(vehicle) * 3.6
    end

    if speedKmh >= (Config.highSpeedKmh or 200.0) then
        return Config.highSpeedRouteDistance or 500.0
    end

    if speedKmh >= (Config.mediumSpeedKmh or 100.0) then
        return Config.mediumSpeedRouteDistance or 350.0
    end

    return Config.lowSpeedRouteDistance or 250.0
end

local function getCurrentRouteSampleStep()
    local ped = PlayerPedId()
    local speedKmh = 0.0

    local vehicle = getGpsEligibleVehicle(ped)
    if vehicle ~= 0 then
        speedKmh = GetEntitySpeed(vehicle) * 3.6
    end

    if speedKmh >= (Config.highSpeedKmh or 200.0) then
        return Config.highSpeedSampleStep or 9.0
    end

    if speedKmh >= (Config.mediumSpeedKmh or 100.0) then
        return Config.mediumSpeedSampleStep or 7.5
    end

    return Config.lowSpeedSampleStep or 6.0
end

local function getDynamicUpdateInterval(speedKmh)
    if speedKmh >= (Config.highSpeedKmh or 200.0) then
        return Config.highSpeedUpdateMs or 500
    end

    if speedKmh >= (Config.mediumSpeedKmh or 100.0) then
        return Config.mediumSpeedUpdateMs or 1500
    end

    return Config.lowSpeedUpdateMs or 2500
end

local function getGroundProbeCacheKey(x, y, probeZ)
    local cell = Config.groundProbeCacheCell or 1.0
    if cell <= 0.01 then
        cell = 1.0
    end

    local xi = math.floor((x / cell) + 0.5)
    local yi = math.floor((y / cell) + 0.5)
    local zi = math.floor((probeZ or 1000.0) + 0.5)
    return ('%d:%d:%d'):format(xi, yi, zi)
end

local function cleanupGroundProbeCache(now)
    if now - (state.lastGroundProbeCleanup or 0) < 2000 then
        return
    end

    state.lastGroundProbeCleanup = now

    local ttl = math.max(100, math.floor(Config.groundProbeCacheTtlMs or 1200))
    local maxEntries = math.max(100, math.floor(Config.groundProbeCacheMaxEntries or 1500))
    local cutoff = now - ttl
    local cache = state.groundProbeCache
    local count = 0

    for key, entry in pairs(cache) do
        if not entry or not entry.t or entry.t < cutoff then
            cache[key] = nil
        else
            count = count + 1
        end
    end

    if count <= maxEntries then
        return
    end

    local ordered = {}
    for key, entry in pairs(cache) do
        ordered[#ordered + 1] = {
            key = key,
            t = entry.t or 0,
        }
    end

    table.sort(ordered, function(a, b)
        return a.t > b.t
    end)

    for i = maxEntries + 1, #ordered do
        cache[ordered[i].key] = nil
    end
end

local function resolveGroundZSafe(pos, snapEnabled, probeZ, groundOffset, maxDelta)
    if not snapEnabled or type(GetGroundZFor_3dCoord) ~= 'function' then
        return pos
    end

    local targetProbeZ = probeZ or 1000.0
    local groundZ = nil
    local now = GetGameTimer()
    local useCache = Config.groundProbeCacheEnabled == true

    if useCache then
        cleanupGroundProbeCache(now)
        local key = getGroundProbeCacheKey(pos.x, pos.y, targetProbeZ)
        local entry = state.groundProbeCache[key]
        if entry and entry.z then
            groundZ = entry.z
        else
            local ok, probedZ = GetGroundZFor_3dCoord(pos.x, pos.y, targetProbeZ, false)
            if not ok or not probedZ then
                return pos
            end
            groundZ = probedZ
            state.groundProbeCache[key] = { z = groundZ, t = now }
        end
    else
        local ok, probedZ = GetGroundZFor_3dCoord(pos.x, pos.y, targetProbeZ, false)
        if not ok or not probedZ then
            return pos
        end
        groundZ = probedZ
    end

    local snappedZ = groundZ + (groundOffset or 0.0)
    local allowedDelta = tonumber(maxDelta) or 0.0
    if allowedDelta > 0.0 and math.abs(snappedZ - pos.z) > allowedDelta then
        return pos
    end

    return vector3(pos.x, pos.y, snappedZ)
end

local function getHeightmapZBounds(pos)
    local topZ = nil
    local bottomZ = nil

    if type(GetHeightmapTopZForPosition) == 'function' then
        local value = GetHeightmapTopZForPosition(pos.x, pos.y)
        if value and value == value then
            topZ = value
        end
    end

    if type(GetHeightmapBottomZForPosition) == 'function' then
        local value = GetHeightmapBottomZForPosition(pos.x, pos.y)
        if value and value == value then
            bottomZ = value
        end
    end

    return topZ, bottomZ
end

local function resolveRouteZAssist(pos)
    if not Config.routeHeightAssistEnabled then
        return pos
    end

    local routeZ = pos.z
    local maxDelta = tonumber(Config.routeHeightAssistMaxDelta) or 3.0
    local blend = math.max(0.0, math.min(1.0, tonumber(Config.routeHeightAssistBlend) or 0.45))
    local bestZ = routeZ
    local bestDelta = math.huge

    local topZ, bottomZ = getHeightmapZBounds(pos)
    local candidates = {}

    if topZ then
        candidates[#candidates + 1] = topZ
    end

    if bottomZ then
        candidates[#candidates + 1] = bottomZ
    end

    if Config.routeGroundProbeEnabled then
        local groundPos = resolveGroundZSafe(
            pos,
            true,
            Config.routeGroundProbeZ,
            Config.routeGroundOffset,
            Config.routeGroundMaxDelta
        )
        if groundPos and groundPos.z then
            candidates[#candidates + 1] = groundPos.z
        end
    end

    for i = 1, #candidates do
        local candidateZ = candidates[i]
        local delta = math.abs(candidateZ - routeZ)
        if delta < bestDelta then
            bestDelta = delta
            bestZ = candidateZ
        end
    end

    if bestDelta == math.huge or bestDelta > maxDelta then
        return pos
    end

    local finalZ = routeZ + ((bestZ - routeZ) * blend)
    return vector3(pos.x, pos.y, finalZ)
end

local function resolveGroundZForRoutePoint(pos)
    local resolvedPos = pos

    if Config.routeGroundProbeEnabled then
        resolvedPos = resolveGroundZSafe(
            resolvedPos,
            true,
            Config.routeGroundProbeZ,
            Config.routeGroundOffset,
            Config.routeGroundMaxDelta
        )
    end

    return resolveRouteZAssist(resolvedPos)
end

local function getNodeFlagsAtPosition(pos)
    if type(GetVehicleNodeProperties) ~= 'function' then
        return false, 0
    end

    local ok, _, flags = GetVehicleNodeProperties(pos.x, pos.y, pos.z)
    if not ok then
        return false, 0
    end

    return true, flags or 0
end

local function isJunctionPoint(pos)
    if not Config.ignoreJunctionNodes and not Config.smoothJunctionTransitions then
        return false
    end

    local ok, flags = getNodeFlagsAtPosition(pos)
    if not ok then
        return false
    end

    return (flags & NodeFlags.JUNCTION) ~= 0
end

local function markJunctionPadding(points)
    if (not Config.ignoreJunctionNodes and not Config.smoothJunctionTransitions) or Config.junctionPaddingPoints <= 0 then
        return
    end

    for i = 1, #points do
        if points[i].junction then
            local minIndex = math.max(1, i - Config.junctionPaddingPoints)
            local maxIndex = math.min(#points, i + Config.junctionPaddingPoints)

            for j = minIndex, maxIndex do
                points[j].junctionZone = true
            end
        end
    end
end

local function smoothJunctionTransitions(points)
    if not Config.smoothJunctionTransitions or #points < 4 then
        return points
    end

    local smoothed = {}
    for i = 1, #points do
        smoothed[i] = clonePoint(points[i])
    end

    local index = 1
    while index <= #smoothed do
        if not smoothed[index].junctionZone then
            index = index + 1
        else
            local zoneStart = index
            while index <= #smoothed and smoothed[index].junctionZone do
                index = index + 1
            end

            local zoneEnd = index - 1
            local preIndex = zoneStart - 1
            local postIndex = zoneEnd + 1

            if preIndex >= 1 and postIndex <= #smoothed then
                local startPos = smoothed[preIndex].pos
                local endPos = smoothed[postIndex].pos
                local span = zoneEnd - zoneStart + 1
                local chord = endPos - startPos
                local chordLength = math.sqrt(vecLength2D(chord))

                if chordLength > 0.01 then
                    local entryFallback = vecNormalize2D(chord)
                    local exitFallback = entryFallback
                    local entryDir = getDirection(smoothed, math.max(1, preIndex - 1), preIndex, entryFallback)
                    local exitDir = getDirection(smoothed, postIndex, math.min(#smoothed, postIndex + 1), exitFallback)
                    local handle = math.min(chordLength * Config.junctionCurveStrength, Config.junctionCurveMaxHandle)
                    local control1 = startPos + (entryDir * handle)
                    local control2 = endPos - (exitDir * handle)

                    for pointIndex = zoneStart, zoneEnd do
                        local t = (pointIndex - zoneStart + 1) / (span + 1)
                        smoothed[pointIndex].pos = cubicBezier(startPos, control1, control2, endPos, t)
                    end
                end
            end
        end
    end

    return smoothed
end

local function getCurrentRouteSlotType()
    if state.routeSource == 'blip' then
        return 1
    end

    return 0
end

local function getPosAlongCurrentRoute(distance)
    return GetPosAlongGpsTypeRoute(true, distance, getCurrentRouteSlotType())
end

local function getActiveRouteDestination()
    if state.routeSource == 'blip' then
        return getTrackedBlipDestination()
    end

    return getWaypointDestination()
end

local function didDestinationChange()
    local currentDestination = getActiveRouteDestination()
    return not positionsClose2D(currentDestination, state.destinationPos, 1.0)
end

local function hasRenderableRoute()
    local ok, pos = getPosAlongCurrentRoute(0.0)
    return ok and pos ~= nil
end

local function sampleCurrentRoute()
    local points = {}
    local maxDistance = getCurrentRouteMaxDistance()
    local sampleStep = math.max(1.0, tonumber(getCurrentRouteSampleStep()) or 6.0)
    local targetLength = GetGpsBlipRouteLength()

    if targetLength <= 0 then
        targetLength = maxDistance
    else
        targetLength = math.min(targetLength, maxDistance)
    end

    local distance = 0.0
    while distance <= targetLength do
        local ok, pos = getPosAlongCurrentRoute(distance)
        if not ok or not pos then
            break
        end

        local basePos = vector3(pos.x, pos.y, pos.z)
        local resolvedBasePos = resolveGroundZForRoutePoint(basePos)
        local point = {
            pos = vector3(resolvedBasePos.x, resolvedBasePos.y, resolvedBasePos.z + Config.routeHeight),
            junction = isJunctionPoint(basePos),
            junctionZone = false,
        }

        if #points == 0 then
            points[#points + 1] = point
        else
            local delta = point.pos - points[#points].pos
            if vecLength2(delta) > 0.25 then
                points[#points + 1] = point
            end
        end

        distance = distance + sampleStep
    end

    if #points < 2 then
        return nil
    end

    markJunctionPadding(points)
    points = smoothJunctionTransitions(points)

    return points, targetLength
end

local rebuildRoute

rebuildRoute = function()
    if not state.enabled then
        clearRouteState()
        return
    end

    local activeDestination = getActiveRouteDestination()
    if not activeDestination then
        clearRouteState()
        return
    end

    if not hasRenderableRoute() then
        clearRouteState()
        state.destinationPos = activeDestination
        return
    end

    local points, routeLength = sampleCurrentRoute()
    if not points then
        clearRouteState()
        state.destinationPos = activeDestination
        return
    end

    state.points = points
    state.activeSlot = getCurrentRouteSlotType()
    state.routeLength = routeLength or 0.0
    state.destinationPos = activeDestination
end

local function scheduleRebuildRoute(delayMs)
    CreateThread(function()
        Wait(delayMs or 0)
        if state.enabled then
            clearRouteState()
            rebuildRoute()
        end
    end)
end

local function getNearestRoutePointIndex(playerPos)
    local points = state.points
    if not points or #points == 0 then
        return nil, math.huge
    end

    local nearestIndex = 1
    local nearestDist2 = vecLength2D(points[1].pos - playerPos)
    for i = 2, #points do
        local d2 = vecLength2D(points[i].pos - playerPos)
        if d2 < nearestDist2 then
            nearestDist2 = d2
            nearestIndex = i
        end
    end

    return nearestIndex, math.sqrt(nearestDist2)
end

local function isPointAheadOfVehicle(pointPos, vehiclePos, vehicleForward)
    if not Config.markerDrawAheadOnly then
        return true
    end

    if not vehiclePos or not vehicleForward then
        return true
    end

    local rel = pointPos - vehiclePos
    local forwardDist = (rel.x * vehicleForward.x) + (rel.y * vehicleForward.y)
    return forwardDist >= -(Config.markerBehindCullBuffer or 0.0)
end

local function shouldDrawSegmentAhead(aPos, bPos, vehiclePos, vehicleForward)
    if not Config.markerDrawAheadOnly then
        return true
    end

    if not vehiclePos or not vehicleForward then
        return true
    end

    local mid = vector3(
        (aPos.x + bPos.x) * 0.5,
        (aPos.y + bPos.y) * 0.5,
        (aPos.z + bPos.z) * 0.5
    )

    return isPointAheadOfVehicle(mid, vehiclePos, vehicleForward)
end

local function pruneRouteBehindPlayer(playerPos)
    if not Config.routeTrimBehindEnabled then
        return false
    end

    local points = state.points
    if not points or #points < 4 then
        return false
    end

    local nearestIndex = getNearestRoutePointIndex(playerPos)
    if not nearestIndex then
        return false
    end

    local keepBehind = math.max(0, math.floor(Config.routeTrimKeepBehindPoints or 14))
    local removeCount = math.max(0, nearestIndex - 1 - keepBehind)
    if removeCount <= 0 then
        return false
    end

    local headDistance = vecDistance2D(playerPos, points[1].pos)
    if headDistance < (Config.routeTrimMinHeadDistance or 100.0) then
        return false
    end

    if removeCount >= #points - 1 then
        return false
    end

    local trimmed = {}
    local outIndex = 1
    for i = removeCount + 1, #points do
        trimmed[outIndex] = points[i]
        outIndex = outIndex + 1
    end

    state.points = trimmed
    return true
end

local function shouldExtendRouteNearEnd(playerPos)
    if not Config.routeExtendNearEndEnabled then
        return false
    end

    local points = state.points
    if not points or #points < 3 then
        return false
    end

    local nearestIndex, nearestDist = getNearestRoutePointIndex(playerPos)
    if not nearestIndex then
        return false
    end

    local pointsLeft = #points - nearestIndex
    if pointsLeft > (Config.routeExtendNearEndPoints or 18) then
        return false
    end

    return nearestDist <= (Config.routeExtendNearEndDistance or 65.0)
end

local function tryExtendRouteForward()
    if #state.points < 2 or not hasRenderableRoute() then
        return false
    end

    local points, routeLength = sampleCurrentRoute()
    if not points or #points < 2 then
        return false
    end

    local currentLast = state.points[#state.points].pos
    local joinIndex = nil
    local bestJoinDist = math.huge

    for i = 1, #points do
        local dist = vecDistance2D(currentLast, points[i].pos)
        if dist < bestJoinDist then
            bestJoinDist = dist
            joinIndex = i
        end
    end

    if not joinIndex or bestJoinDist > (Config.routeExtendMaxJoinDistance or 10.0) then
        return false
    end

    local appended = 0
    local lastPos = state.points[#state.points].pos
    for i = joinIndex + 1, #points do
        if vecLength2(points[i].pos - lastPos) > 0.25 then
            state.points[#state.points + 1] = points[i]
            lastPos = points[i].pos
            appended = appended + 1
        end
    end

    if appended > 0 then
        state.routeLength = routeLength or state.routeLength
        return true
    end

    return false
end

local function isPlayerOffRoute(playerPos)
    if not Config.offRouteRebuildEnabled then
        return false
    end

    local points = state.points
    if #points < 2 then
        return false
    end

    local minDist = math.huge
    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        if not Config.ignoreJunctionNodes or (not a.junctionZone and not b.junctionZone) then
            local dist = pointToSegmentDistance2D(playerPos, a.pos, b.pos)
            if dist < minDist then
                minDist = dist
            end
        end
    end

    if minDist == math.huge then
        return false
    end

    return minDist > (Config.offRouteRebuildDistance or 14.0)
end

local function shouldRebuildForOffRoute(playerPos, speedKmh, now)
    if not Config.offRouteRebuildEnabled then
        state.offRouteSince = 0
        return false
    end

    if (speedKmh or 0.0) < (Config.offRouteRebuildMinSpeedKmh or 20.0) then
        state.offRouteSince = 0
        return false
    end

    if not isPlayerOffRoute(playerPos) then
        state.offRouteSince = 0
        return false
    end

    local since = state.offRouteSince or 0
    if since <= 0 then
        state.offRouteSince = now
        return false
    end

    if now - (state.lastOffRouteRebuild or 0) < (Config.offRouteRebuildCooldownMs or 1400) then
        return false
    end

    if now - since >= (Config.offRouteRebuildConfirmMs or 800) then
        state.offRouteSince = 0
        state.lastOffRouteRebuild = now
        return true
    end

    return false
end

local function getRibbonVertices(points, index, width, lift)
    local point = points[index]
    if not point then
        return nil, nil
    end

    local halfWidth = width * 0.5
    local basePos = point.pos + vector3(0.0, 0.0, lift or 0.0)
    local prevDir = nil
    local nextDir = nil

    if index > 1 then
        prevDir = vecNormalize2D(points[index].pos - points[index - 1].pos)
    end

    if index < #points then
        nextDir = vecNormalize2D(points[index + 1].pos - points[index].pos)
    end

    if prevDir and vecLength2D(prevDir) < 0.0001 then
        prevDir = nil
    end

    if nextDir and vecLength2D(nextDir) < 0.0001 then
        nextDir = nil
    end

    if not prevDir and not nextDir then
        return nil, nil
    end

    if not prevDir then
        local side = vector3(-nextDir.y, nextDir.x, 0.0) * halfWidth
        return basePos - side, basePos + side
    end

    if not nextDir then
        local side = vector3(-prevDir.y, prevDir.x, 0.0) * halfWidth
        return basePos - side, basePos + side
    end

    local prevNormal = vector3(-prevDir.y, prevDir.x, 0.0)
    local nextNormal = vector3(-nextDir.y, nextDir.x, 0.0)
    local miter = prevNormal + nextNormal

    if vecLength2D(miter) < 0.0001 then
        local side = prevNormal * halfWidth
        return basePos - side, basePos + side
    end

    miter = vecNormalize2D(miter)

    local denom = (miter.x * nextNormal.x) + (miter.y * nextNormal.y)
    if math.abs(denom) < 0.2 then
        denom = denom < 0.0 and -0.2 or 0.2
    end

    local maxMiterScale = math.max(1.0, tonumber(Config.texturedRoute.maxMiterScale) or 1.35)
    local miterLength = math.min(halfWidth / math.abs(denom), halfWidth * maxMiterScale)
    local side = miter * miterLength

    return basePos - side, basePos + side
end

local function getTexturedRouteSegmentAlpha(visibleDistance, segmentDistance)
    local baseAlpha = getActiveRouteTint().a
    if not Config.texturedRoute.nearFadeEnabled then
        return baseAlpha
    end

    local fadeDistance = math.max(0.0, tonumber(Config.texturedRoute.nearFadeDistance) or 0.0)
    if fadeDistance <= 0.01 then
        return baseAlpha
    end

    local startAlpha = math.max(0.0, math.min(1.0, tonumber(Config.texturedRoute.nearFadeStartAlpha) or 0.0))
    local sampleDistance = visibleDistance + (segmentDistance * 0.5)
    local t = math.max(0.0, math.min(1.0, sampleDistance / fadeDistance))
    local alphaFactor = startAlpha + ((1.0 - startAlpha) * t)

    return math.floor((baseAlpha * alphaFactor) + 0.5)
end

local function drawRouteTexturedSegment(aLeft, aRight, bLeft, bRight, startV, endV, tint, textureName, textureDict, alpha)
    local segmentAlpha = clampColorChannel(alpha, tint.a)

    DrawTexturedPoly(
        aLeft.x, aLeft.y, aLeft.z,
        bLeft.x, bLeft.y, bLeft.z,
        bRight.x, bRight.y, bRight.z,
        tint.r, tint.g, tint.b, segmentAlpha,
        textureDict, textureName,
        0.0, startV, 1.0,
        0.0, endV, 1.0,
        1.0, endV, 1.0
    )

    DrawTexturedPoly(
        aLeft.x, aLeft.y, aLeft.z,
        bRight.x, bRight.y, bRight.z,
        aRight.x, aRight.y, aRight.z,
        tint.r, tint.g, tint.b, segmentAlpha,
        textureDict, textureName,
        0.0, startV, 1.0,
        1.0, endV, 1.0,
        1.0, startV, 1.0
    )
end

local function drawTexturedRoute(points, vehiclePos, vehicleForward)
    if #points < 2 then
        return false
    end

    if type(DrawTexturedPoly) ~= 'function' or not ensureTexturedRouteReady() then
        return false
    end

    local preset = getCurrentPreset()
    if not preset then
        return false
    end

    local tint = getActiveRouteTint()
    local repeatDistance = math.max(Config.texturedRoute.repeatDistance or 1.0, 0.01)
    local accumulatedDistance = 0.0
    local visibleAccumulatedDistance = 0.0

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        local segmentDistance = vecDistance2D(a.pos, b.pos)

        if segmentDistance > 0.01 then
            if (not Config.ignoreJunctionNodes or (not a.junctionZone and not b.junctionZone))
                and shouldDrawSegmentAhead(a.pos, b.pos, vehiclePos, vehicleForward) then
                local aLeft, aRight = getRibbonVertices(points, i, Config.texturedRoute.width, Config.texturedRoute.lift)
                local bLeft, bRight = getRibbonVertices(points, i + 1, Config.texturedRoute.width, Config.texturedRoute.lift)

                if aLeft and aRight and bLeft and bRight then
                    local startV = accumulatedDistance / repeatDistance
                    local endV = (accumulatedDistance + segmentDistance) / repeatDistance
                    local segmentAlpha = getTexturedRouteSegmentAlpha(visibleAccumulatedDistance, segmentDistance)
                    if segmentAlpha > 0 then
                        drawRouteTexturedSegment(
                            aLeft,
                            aRight,
                            bLeft,
                            bRight,
                            startV,
                            endV,
                            tint,
                            preset.textureName,
                            preset.textureDict,
                            segmentAlpha
                        )
                    end
                end

                visibleAccumulatedDistance = visibleAccumulatedDistance + segmentDistance
            end

            accumulatedDistance = accumulatedDistance + segmentDistance
        end
    end

    return true
end

local function drawFallbackRoute(points, vehiclePos, vehicleForward)
    local tint = getActiveRouteTint()

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        if (not Config.ignoreJunctionNodes or (not a.junctionZone and not b.junctionZone))
            and shouldDrawSegmentAhead(a.pos, b.pos, vehiclePos, vehicleForward) then
            DrawLine(a.pos.x, a.pos.y, a.pos.z, b.pos.x, b.pos.y, b.pos.z, tint.r, tint.g, tint.b, tint.a)
        end
    end
end

local function drawRoute()
    if #state.points < 2 then
        return
    end

    local ped = PlayerPedId()
    local vehiclePos = nil
    local vehicleForward = nil
    local vehicle = getGpsEligibleVehicle(ped)
    if vehicle ~= 0 then
        vehiclePos = GetEntityCoords(vehicle)
        vehicleForward = GetEntityForwardVector(vehicle)
    end

    if not drawTexturedRoute(state.points, vehiclePos, vehicleForward) then
        drawFallbackRoute(state.points, vehiclePos, vehicleForward)
    end
end

local function drawWorldText(pos, text, color, scale)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z)
    if not onScreen then
        return
    end

    local tint = color or { r = 255, g = 255, b = 255, a = 220 }
    SetTextScale(scale or 0.32, scale or 0.32)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextColour(tint.r or 255, tint.g or 255, tint.b or 255, tint.a or 220)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function showHintText(text, color)
    if not Config.modeHintEnabled then
        return
    end

    state.modeHintText = text
    state.modeHintColor = copyColor(color or getActiveRouteTint())
    state.modeHintUntil = GetGameTimer() + (Config.modeHintDurationMs or 1800)
end

local function showModeHint(source)
    local text = source == 'blip' and Config.modeHintMissionText or Config.modeHintUserText
    showHintText(text, getActiveRouteTint())
end

local function drawModeHint()
    if not Config.modeHintEnabled or not state.modeHintText or GetGameTimer() > (state.modeHintUntil or 0) then
        return
    end

    local ped = PlayerPedId()
    local vehicle = getGpsEligibleVehicle(ped)
    if vehicle == 0 then
        return
    end

    local vehiclePos = GetEntityCoords(vehicle)
    local anchor = vector3(vehiclePos.x, vehiclePos.y, vehiclePos.z + (Config.modeHintAnchorOffsetZ or 1.1))
    local textPos = vector3(vehiclePos.x, vehiclePos.y, vehiclePos.z + (Config.modeHintTextOffsetZ or 2.0))
    local lineColor = Config.modeHintLineColor or { r = 255, g = 255, b = 255, a = 165 }

    DrawLine(anchor.x, anchor.y, anchor.z, textPos.x, textPos.y, textPos.z - 0.2, lineColor.r, lineColor.g, lineColor.b, lineColor.a)
    drawWorldText(textPos, state.modeHintText, state.modeHintColor, 0.34)
end

local function playModeSwitchFeedback(source)
    showModeHint(source)

    if Config.modeFxEnabled ~= true then
        return
    end

    if type(PlaySound) == 'function' and Config.modeFxSoundName and Config.modeFxSoundSet then
        PlaySound(-1, Config.modeFxSoundName, Config.modeFxSoundSet, 0, 0, 1)
    end

    if type(AnimpostfxPlay) ~= 'function' or type(AnimpostfxStop) ~= 'function' or not Config.modeFxName then
        return
    end

    state.modeFxToken = (state.modeFxToken or 0) + 1
    local token = state.modeFxToken
    local fxName = Config.modeFxName

    AnimpostfxStop(fxName)
    AnimpostfxPlay(fxName, 0, false)

    CreateThread(function()
        Wait(Config.modeFxDurationMs or 900)
        if state.modeFxToken == token then
            AnimpostfxStop(fxName)
        end
    end)
end

local function playActionFeedback(text, color)
    showHintText(text, color)

    if Config.modeFxEnabled ~= true then
        return
    end

    if type(PlaySound) == 'function' and Config.modeFxSoundName and Config.modeFxSoundSet then
        PlaySound(-1, Config.modeFxSoundName, Config.modeFxSoundSet, 0, 0, 1)
    end

    if type(AnimpostfxPlay) ~= 'function' or type(AnimpostfxStop) ~= 'function' or not Config.modeFxName then
        return
    end

    state.modeFxToken = (state.modeFxToken or 0) + 1
    local token = state.modeFxToken
    local fxName = Config.modeFxName

    AnimpostfxStop(fxName)
    AnimpostfxPlay(fxName, 0, false)

    CreateThread(function()
        Wait(Config.modeFxDurationMs or 900)
        if state.modeFxToken == token then
            AnimpostfxStop(fxName)
        end
    end)
end

local function isGeoAnimAvailable()
    return type(L2KGpsGeoAnim) == 'table'
end

local function playGpsGeoAnimation(profileName)
    if state.extraAnimationsEnabled ~= true or not canUseGpsShortcuts() then
        return false
    end

    if not isGeoAnimAvailable() then
        return false
    end

    local ped = PlayerPedId()
    local vehicle = getGpsEligibleVehicle(ped)
    if vehicle == 0 then
        return false
    end

    if type(L2KGpsGeoAnim) == 'table' and type(L2KGpsGeoAnim.PlayProfile) == 'function' then
        local ok, result = pcall(function()
            return L2KGpsGeoAnim.PlayProfile(profileName, vehicle)
        end)

        return ok and result ~= false
    end

    if type(GetCurrentResourceName) ~= 'function' then
        return false
    end

    local resourceName = GetCurrentResourceName()
    local ok, result = pcall(function()
        return exports[resourceName]:PlayProfile(profileName, vehicle)
    end)

    return ok and result ~= false
end

local function playGpsOnAnimation()
    if Config.animationOnEnabled == false then
        return false
    end

    local profileName = nil
    if state.geoAnimIntroPlayed ~= true then
        profileName = Config.geoAnimIntroProfile or 'on'
    else
        profileName = Config.geoAnimQuickOnProfile or Config.geoAnimIntroProfile or 'on'
    end

    local played = playGpsGeoAnimation(profileName)
    if played then
        state.geoAnimIntroPlayed = true
    end

    return played
end

local function playGpsOffAnimation()
    if Config.animationOffEnabled == false then
        return false
    end

    return playGpsGeoAnimation(Config.geoAnimOffProfile or 'off')
end

local function stopGpsGeoAnimations()
    if not isGeoAnimAvailable() then
        return false
    end

    local ok = false

    if type(L2KGpsGeoAnim) == 'table' and type(L2KGpsGeoAnim.StopExtraAnimations) == 'function' then
        ok = pcall(function()
            L2KGpsGeoAnim.StopExtraAnimations()
        end)
    elseif type(GetCurrentResourceName) == 'function' then
        local resourceName = GetCurrentResourceName()
        ok = pcall(function()
            exports[resourceName]:StopExtraAnimations()
        end)
    end

    return ok
end

local function toggleExtraAnimationsShortcut()
    state.extraAnimationsEnabled = state.extraAnimationsEnabled ~= true
    state.geoAnimIntroPlayed = false

    if state.extraAnimationsEnabled then
        playActionFeedback('GPS FX: ON', { r = 90, g = 220, b = 120, a = 220 })
    else
        stopGpsGeoAnimations()
        playActionFeedback('GPS FX: OFF', { r = 255, g = 96, b = 96, a = 220 })
    end
end

local function playNoRouteFeedback()
    if type(PlaySoundFrontend) == 'function' then
        PlaySoundFrontend(
            -1,
            Config.noRouteSoundName or 'ERROR',
            Config.noRouteSoundSet or 'HUD_FRONTEND_DEFAULT_SOUNDSET',
            true
        )
        return
    end

    if type(PlaySound) == 'function' then
        PlaySound(
            -1,
            Config.noRouteSoundName or 'ERROR',
            Config.noRouteSoundSet or 'HUD_FRONTEND_DEFAULT_SOUNDSET',
            0,
            0,
            1
        )
    end
end

local function isControlPressedAny(control)
    return IsControlPressed(0, control) or IsControlPressed(2, control)
end

local function isControlJustPressedAny(control)
    return IsControlJustPressed(0, control) or IsControlJustPressed(2, control)
end

local function isShortcutModifierPressed()
    return isControlPressedAny(Config.shortcutModifierKey or 21)
end

local function describeRouteSource(source)
    if source == 'blip' then
        return 'MISSION'
    end

    return 'USER'
end

local function setActiveRouteSource(source, withFeedback, withChat)
    if source ~= 'manual' and source ~= 'blip' then
        return false, 'Invalid route source.'
    end

    if source == 'manual' then
        if Config.routeSources.manual == false then
            return false, 'Manual route source is disabled.'
        end

        if not hasManualRouteAvailable() then
            return false, 'Manual waypoint route is not active.'
        end
    elseif source == 'blip' then
        if Config.routeSources.blip ~= true then
            return false, 'Mission route source is disabled.'
        end

        refreshExternalTrackedBlip(true)
        if not hasBlipRouteAvailable() then
            return false, 'Mission blip route is not active.'
        end
    end

    local changed = state.routeSource ~= source
    state.routeSource = source
    Config.routeSource = source
    state.lastUpdate = GetGameTimer()

    clearRouteState()
    rebuildRoute()
    scheduleRebuildRoute(120)

    if source == 'blip' then
        scheduleRebuildRoute(300)
    end

    if withFeedback then
        if withChat ~= false then
            notify(('ROTA ATIVA: ^3%s^7'):format(describeRouteSource(source)))
        end
        if changed then
            playModeSwitchFeedback(source)
        else
            showModeHint(source)
        end
    end

    return true
end

local function cycleActiveRoute(direction, withChat, requireAlternative)
    refreshExternalTrackedBlip(true)

    local sources = getAvailableRouteSources()
    if #sources == 0 then
        playNoRouteFeedback()
        return
    end

    local currentIndex = nil
    for i = 1, #sources do
        if sources[i] == state.routeSource then
            currentIndex = i
            break
        end
    end

    if requireAlternative and #sources <= 1 and currentIndex ~= nil then
        playNoRouteFeedback()
        return
    end

    if not currentIndex then
        setActiveRouteSource(sources[1], true, withChat)
        return
    end

    local nextIndex = currentIndex + (direction or 1)
    if nextIndex < 1 then
        nextIndex = #sources
    elseif nextIndex > #sources then
        nextIndex = 1
    end

    setActiveRouteSource(sources[nextIndex], true, withChat)
end

local function applyRoutePreset(index, silent)
    local presetIndex = normalizePresetIndex(index)
    local preset = Config.routePresets[presetIndex]
    if not preset then
        return false, 'Invalid preset.'
    end

    state.routePresetIndex = presetIndex
    Config.currentRoutePreset = presetIndex
    state.texturedRouteReady = false
    state.texturedRouteDict = nil

    if state.enabled then
        clearRouteState()
        rebuildRoute()
    end

    if not silent then
        notify(('Preset ^3%d^7 selected: %s'):format(presetIndex, preset.name))
    end

    return true
end

local function setDefaultRouteColor(r, g, b, a)
    state.defaultRouteColor = {
        r = clampColorChannel(r, state.defaultRouteColor.r),
        g = clampColorChannel(g, state.defaultRouteColor.g),
        b = clampColorChannel(b, state.defaultRouteColor.b),
        a = clampColorChannel(a, state.defaultRouteColor.a),
    }

    if state.enabled and state.routeSource == 'manual' then
        showModeHint('manual')
    end

    return copyColor(state.defaultRouteColor)
end

local function setMissionRouteColor(r, g, b, a)
    state.missionRouteColor = {
        r = clampColorChannel(r, state.missionRouteColor.r),
        g = clampColorChannel(g, state.missionRouteColor.g),
        b = clampColorChannel(b, state.missionRouteColor.b),
        a = clampColorChannel(a, state.missionRouteColor.a),
    }

    if state.enabled and state.routeSource == 'blip' then
        showModeHint('blip')
    end

    return copyColor(state.missionRouteColor)
end

local function cycleCurrentRouteColor(direction)
    local palette = Config.routeColorPalette or {}
    if #palette == 0 then
        playNoRouteFeedback()
        return false
    end

    local currentColor = state.routeSource == 'blip' and state.missionRouteColor or state.defaultRouteColor
    local currentIndex = getRouteColorPaletteIndex(currentColor)
    local nextIndex = currentIndex

    if nextIndex <= 0 then
        nextIndex = direction < 0 and #palette or 1
    else
        nextIndex = nextIndex + (direction or 1)
        if nextIndex < 1 then
            nextIndex = #palette
        elseif nextIndex > #palette then
            nextIndex = 1
        end
    end

    local entry = palette[nextIndex]
    if not entry or not entry.color then
        playNoRouteFeedback()
        return false
    end

    local applied = nil
    if state.routeSource == 'blip' then
        applied = setMissionRouteColor(entry.color.r, entry.color.g, entry.color.b, entry.color.a)
    else
        applied = setDefaultRouteColor(entry.color.r, entry.color.g, entry.color.b, entry.color.a)
    end

    playActionFeedback(('GPS COLOR: %s'):format(entry.name or ('#' .. tostring(nextIndex))), applied)
    return true
end

local function cycleRoutePreset(direction)
    local presetIndices = getRoutePresetIndices()
    if #presetIndices == 0 then
        playNoRouteFeedback()
        return false
    end

    local currentIndex = normalizePresetIndex(state.routePresetIndex)
    local currentPosition = 1
    for i = 1, #presetIndices do
        if presetIndices[i] == currentIndex then
            currentPosition = i
            break
        end
    end

    local nextPosition = currentPosition + (direction or 1)
    if nextPosition < 1 then
        nextPosition = #presetIndices
    elseif nextPosition > #presetIndices then
        nextPosition = 1
    end

    local nextPresetIndex = presetIndices[nextPosition]
    local ok = applyRoutePreset(nextPresetIndex, true)
    if not ok then
        playNoRouteFeedback()
        return false
    end

    local preset = getCurrentPreset()
    playActionFeedback(('GPS PRESET: %s'):format(preset and preset.name or tostring(nextPresetIndex)), getActiveRouteTint())
    return true
end

local function setGpsEnabledState(enabled, withFeedback, withChat)
    local targetEnabled = enabled == true
    local changed = state.enabled ~= targetEnabled

    if changed and targetEnabled and state.extraAnimationsEnabled == true then
        playGpsOnAnimation()
    elseif changed and (not targetEnabled) and state.extraAnimationsEnabled == true then
        playGpsOffAnimation()
    end

    state.enabled = targetEnabled

    if state.enabled then
        refreshExternalTrackedBlip(true)
        rebuildRoute()
    else
        clearRouteState()
    end

    if withFeedback then
        if state.enabled then
            playActionFeedback(state.routeSource == 'blip' and Config.modeHintMissionText or Config.modeHintUserText, getActiveRouteTint())
        else
            playActionFeedback(Config.modeHintOffText or 'GPS MODE: OFF', { r = 255, g = 96, b = 96, a = 220 })
        end
    end

    if withChat ~= false then
        local message = state.enabled and '^2GPS 3D enabled.^7' or '^1GPS 3D disabled.^7'
        notify(message)
    end

    return changed
end

local function toggleGpsShortcut()
    if not canUseGpsShortcuts() then
        return
    end

    local now = GetGameTimer()

    if state.enabled then
        state.gpsToggleCooldownUntil = now + (Config.routeToggleCooldownMs or 10000)
        setGpsEnabledState(false, true, false)
        return
    end

    if now < (state.gpsToggleCooldownUntil or 0) then
        local remainingSeconds = math.ceil(((state.gpsToggleCooldownUntil or 0) - now) / 1000.0)
        playActionFeedback(('GPS COOLDOWN: %ds'):format(math.max(1, remainingSeconds)), { r = 255, g = 180, b = 72, a = 220 })
        return
    end

    setGpsEnabledState(true, true, false)
end

local function setTrackedBlip(blip)
    if not blip or blip == 0 or type(DoesBlipExist) ~= 'function' or not DoesBlipExist(blip) then
        return false, 'Invalid blip.'
    end

    local coords = nil
    if type(GetBlipInfoIdCoord) == 'function' then
        coords = GetBlipInfoIdCoord(blip)
    end

    local destination = nil
    if coords then
        destination = vector3(coords.x, coords.y, coords.z)
    end

    setTrackedBlipState(blip, destination, 'explicit')

    if state.enabled and state.routeSource == 'blip' then
        clearRouteState()
        rebuildRoute()
    end

    return true
end

local function clearTrackedBlip()
    if state.trackedBlipMode == 'explicit' then
        clearTrackedBlipState()
        refreshExternalTrackedBlip(true)

        if state.enabled and state.routeSource == 'blip' then
            clearRouteState()
            rebuildRoute()
        end
    end
end

CreateThread(function()
    while true do
        local waitTime = 500
        local hasActiveHint = Config.modeHintEnabled and GetGameTimer() <= (state.modeHintUntil or 0)

        if state.enabled then
            local ped = PlayerPedId()
            local shouldDraw = Config.drawWhenOnFoot
            if not shouldDraw then
                shouldDraw = getGpsEligibleVehicle(ped) ~= 0
            end

            if shouldDraw or hasActiveHint then
                waitTime = 0
                if shouldDraw then
                    drawRoute()
                end
                drawModeHint()
            end
        elseif hasActiveHint then
            waitTime = 0
            drawModeHint()
        end

        Wait(waitTime)
    end
end)

CreateThread(function()
    while true do
        local waitTime = 100

        if state.enabled then
            local now = GetGameTimer()
            local ped = PlayerPedId()
            local playerPos = ped and ped ~= 0 and GetEntityCoords(ped) or nil
            local speedKmh = 0.0
            local vehicle = getGpsEligibleVehicle(ped)
            local canProcessRoute = Config.drawWhenOnFoot or vehicle ~= 0

            refreshExternalTrackedBlip(false)

            if not canProcessRoute then
                waitTime = 750
            else
                if vehicle ~= 0 then
                    speedKmh = GetEntitySpeed(vehicle) * 3.6
                end

                if state.routeSource == 'manual' and not hasManualRouteAvailable() then
                    clearRouteState()
                elseif state.routeSource == 'blip' and not hasBlipRouteAvailable() then
                    clearRouteState()
                elseif didDestinationChange() then
                    state.lastUpdate = now
                    rebuildRoute()
                elseif playerPos and shouldRebuildForOffRoute(playerPos, speedKmh, now) then
                    state.lastUpdate = now
                    rebuildRoute()
                elseif playerPos and shouldExtendRouteNearEnd(playerPos)
                    and (now - (state.lastExtendAttempt or 0) >= (Config.routeExtendCooldownMs or 700)) then
                    state.lastExtendAttempt = now
                    local extended = tryExtendRouteForward()
                    if not extended then
                        state.lastUpdate = now
                        rebuildRoute()
                    end
                elseif Config.periodicRebuildEnabled and (now - state.lastUpdate >= getDynamicUpdateInterval(speedKmh)) then
                    state.lastUpdate = now
                    rebuildRoute()
                end

                if playerPos then
                    pruneRouteBehindPlayer(playerPos)
                end
            end
        else
            clearRouteState()
            waitTime = 250
        end

        Wait(waitTime)
    end
end)

CreateThread(function()
    while true do
        local waitTime = 250

        if Config.routeSwitchKeysEnabled and not IsPauseMenuActive() and canUseGpsShortcuts() then
            waitTime = 0
            if isShortcutModifierPressed() then
                if state.enabled and Config.shortcutRouteToggleEnabled ~= false and isControlJustPressedAny(Config.routeSwitchKeyUp or 188) then
                    cycleActiveRoute(1, false, true)
                elseif state.enabled and Config.shortcutColorCycleEnabled ~= false and isControlJustPressedAny(Config.routeColorKey or 38) then
                    cycleCurrentRouteColor(1)
                elseif state.enabled and Config.shortcutPresetCycleEnabled ~= false and isControlJustPressedAny(Config.routePresetKeyLeft or 189) then
                    cycleRoutePreset(-1)
                elseif state.enabled and Config.shortcutPresetCycleEnabled ~= false and isControlJustPressedAny(Config.routePresetKeyRight or 190) then
                    cycleRoutePreset(1)
                elseif Config.shortcutAnimationToggleEnabled ~= false and isControlJustPressedAny(Config.routeAnimationToggleKey or 311) then
                    toggleExtraAnimationsShortcut()
                elseif Config.shortcutGpsToggleEnabled ~= false and isControlJustPressedAny(Config.routeToggleKey or 187) then
                    toggleGpsShortcut()
                end
            end
        end

        Wait(waitTime)
    end
end)

RegisterCommand('gps3d', function()
    setGpsEnabledState(not state.enabled, true, true)
end, false)

RegisterCommand('gps3d_route', function(_, args)
    local action = args and args[1] and string.lower(args[1]) or 'toggle'

    if action == 'toggle' then
        cycleActiveRoute(1)
        return
    end

    if action == 'manual' then
        local ok, errorMessage = setActiveRouteSource('manual', true)
        if not ok then
            notify(('^1USER route failed:^7 %s'):format(errorMessage or 'unknown error'))
        end
        return
    end

    if action == 'blip' or action == 'mission' then
        refreshExternalTrackedBlip(true)
        local ok, errorMessage = setActiveRouteSource('blip', true)
        if not ok then
            notify(('^1MISSION route failed:^7 %s'):format(errorMessage or 'unknown error'))
        end
        return
    end

    if action == 'status' then
        refreshExternalTrackedBlip(true)
        local preset = getCurrentPreset()
        local availableSources = table.concat(getAvailableRouteSources(), ', ')
        notify(('Source: ^3%s^7 | Preset: ^5%d - %s^7 | Points: %d | Slot: %s | Available: [%s]'):format(
            describeRouteSource(state.routeSource or 'manual'),
            state.routePresetIndex or 0,
            preset and preset.name or 'unknown',
            #state.points,
            state.activeSlot ~= nil and tostring(state.activeSlot) or 'none',
            availableSources ~= '' and availableSources or 'none'
        ))
        return
    end

    notify('^3Usage:^7 /gps3d_route manual|blip|toggle|status')
end, false)

RegisterCommand('gpspreset', function(_, args)
    local action = args and args[1] and string.lower(args[1]) or 'status'

    if action == 'status' then
        local preset = getCurrentPreset()
        notify(('Preset: ^3%d^7 - %s'):format(state.routePresetIndex or 0, preset and preset.name or 'unknown'))
        return
    end

    if action == 'next' then
        local presetIndices = getRoutePresetIndices()
        local currentIndex = normalizePresetIndex(state.routePresetIndex)
        local nextPosition = 1
        for i = 1, #presetIndices do
            if presetIndices[i] == currentIndex then
                nextPosition = i + 1
                break
            end
        end
        if nextPosition > #presetIndices then
            nextPosition = 1
        end
        applyRoutePreset(presetIndices[nextPosition], false)
        return
    end

    if action == 'prev' or action == 'previous' then
        local presetIndices = getRoutePresetIndices()
        local currentIndex = normalizePresetIndex(state.routePresetIndex)
        local nextPosition = #presetIndices
        for i = 1, #presetIndices do
            if presetIndices[i] == currentIndex then
                nextPosition = i - 1
                break
            end
        end
        if nextPosition < 1 then
            nextPosition = #presetIndices
        end
        applyRoutePreset(presetIndices[nextPosition], false)
        return
    end

    local requestedIndex = tonumber(action)
    if requestedIndex == nil then
        notify('^3Usage:^7 /gpspreset index|next|prev|status')
        return
    end

    if not applyRoutePreset(requestedIndex, false) then
        notify('^1Invalid preset index.^7')
    end
end, false)

RegisterCommand('gpscolordefault', function(_, args, rawCommand)
    local currentTint = state.defaultRouteColor
    local r, g, b, a = parseColorInput(args, rawCommand)

    if r == nil or g == nil or b == nil then
        notify(('^3Usage:^7 /gpscolordefault r g b [a]^7. Current: rgba(%d, %d, %d, %d)'):format(
            currentTint.r, currentTint.g, currentTint.b, currentTint.a
        ))
        return
    end

    local applied = setDefaultRouteColor(r, g, b, a)
    notify(('USER color changed to rgba(%d, %d, %d, %d)'):format(applied.r, applied.g, applied.b, applied.a))
end, false)

RegisterCommand('gpscolormission', function(_, args, rawCommand)
    local currentTint = state.missionRouteColor
    local r, g, b, a = parseColorInput(args, rawCommand)

    if r == nil or g == nil or b == nil then
        notify(('^3Usage:^7 /gpscolormission r g b [a]^7. Current: rgba(%d, %d, %d, %d)'):format(
            currentTint.r, currentTint.g, currentTint.b, currentTint.a
        ))
        return
    end

    local applied = setMissionRouteColor(r, g, b, a)
    notify(('MISSION color changed to rgba(%d, %d, %d, %d)'):format(applied.r, applied.g, applied.b, applied.a))
end, false)

--[[
===============================================================================
 EXPORTS
-----------------------------------------------------------------------------
 SetEnabled(enabled)
 SetActiveRouteSource('manual' | 'blip')
 SetTrackedBlip(blip)
 ClearTrackedBlip()
 SetRoutePreset(index)
 SetDefaultRouteColor(r, g, b, a)
 SetMissionRouteColor(r, g, b, a)
===============================================================================
]]

exports('SetEnabled', function(enabled)
    state.enabled = enabled == true
    if state.enabled then
        refreshExternalTrackedBlip(true)
        rebuildRoute()
    else
        clearRouteState()
    end
    return state.enabled
end)

exports('SetActiveRouteSource', function(source)
    return setActiveRouteSource(source, false)
end)

exports('SetTrackedBlip', setTrackedBlip)
exports('ClearTrackedBlip', clearTrackedBlip)

exports('SetRoutePreset', function(index)
    return applyRoutePreset(index, true)
end)

exports('SetDefaultRouteColor', function(r, g, b, a)
    if type(r) == 'table' then
        return setDefaultRouteColor(r.r, r.g, r.b, r.a)
    end
    return setDefaultRouteColor(r, g, b, a)
end)

exports('SetMissionRouteColor', function(r, g, b, a)
    if type(r) == 'table' then
        return setMissionRouteColor(r.r, r.g, r.b, r.a)
    end
    return setMissionRouteColor(r, g, b, a)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() and Config.modeFxEnabled and type(AnimpostfxStop) == 'function' and Config.modeFxName then
        AnimpostfxStop(Config.modeFxName)
    end
end)

CreateThread(function()
    Wait(1000)
    if type(GetPosAlongGpsTypeRoute) ~= 'function' then
        print('[l2k_gps3d] route sampling native not available in this runtime.')
        return
    end

    refreshExternalTrackedBlip(true)
    ensureTexturedRouteReady()
    rebuildRoute()
end)
