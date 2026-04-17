local Config = {
    -- General
    enabled = true,
    drawWhenOnFoot = false,

    -- Route sampling
    sampleStep = 6.0,
    maxDistance = 500.0,
    maxDistanceMedium = 350.0,
    maxDistanceSlow = 250.0,
    maxDistanceMediumKmh = 100.0,
    maxDistanceFastKmh = 200.0,

    -- Junction smoothing
    ignoreJunctionNodes = false,
    smoothJunctionTransitions = true,
    junctionPaddingPoints = 1,
    junctionCurveStrength = 0.22,
    junctionCurveMaxHandle = 6.2,

    -- Marker spacing and shape
    arrowSpacing = 1.0,
    arrowLength = 1.5,
    arrowWidth = 0.8,
    routeHeight = 0.22,

    -- Calculate draw speed by velocity
    updateInterval = 1500,
    updateIntervalSlow = 2500,
    updateIntervalFast = 500,
    updateIntervalMediumKmh = 100.0,
    updateIntervalFastKmh = 300.0,
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

    -- Calculate out of route
    offRouteRebuildEnabled = true,
    offRouteRebuildDistance = 14.0,
    offRouteRebuildConfirmMs = 500,
    offRouteRebuildCooldownMs = 1400,
    offRouteRebuildMinSpeedKmh = 100.0,

    -- Route selection
    slotPriority = { 0, 1, 2 },

    -- Route render mode
    routeRenderType = 2, -- 1 = lines, 2 = rect + uvmap
    routeColor = { r = 64, g = 200, b = 255, a = 180 },
    arrowColor = { r = 0, g = 255, b = 180, a = 220 },

    -- Build rect
    texturedRoute = {
        enabled = true,
        textureDict = 'chevrons',
        textureName = 'chevrons',
        width = 1.35,
        lift = 0.03,
        repeatDistance = 4.0,
        maxMiterScale = 1.35,
        color = { r = 255, g = 255, b = 255, a = 205 },
        drawArrowOverlay = false,
        disableBackfaceCulling = true,
    },

    -- Ground probe
    routeHeightAssistEnabled = true,
    routeHeightAssistBlend = 0.45,
    routeHeightAssistMaxDelta = 3.0,
    routeGroundProbeEnabled = true,
    routeGroundProbeZ = 1000.0,
    routeGroundOffset = 0.0,
    routeGroundMaxDelta = 2.5,
    groundProbeCacheEnabled = true,
    groundProbeCacheCell = 1.0,
    groundProbeCacheTtlMs = 1200,
    groundProbeCacheMaxEntries = 1500,
}

local NodeFlags = {
    JUNCTION = 128,
}

local state = {
    enabled = Config.enabled,
    points = {},
    activeSlot = nil,
    lastUpdate = 0,
    routeLength = 0.0,
    destinationPos = nil,
    texturedRouteReady = false,
    routeRenderType = Config.routeRenderType,
    groundProbeCache = {},
    lastGroundProbeCleanup = 0,
    lastExtendAttempt = 0,
    markerPhaseOffset = 0.0,
    offRouteSince = 0,
    lastOffRouteRebuild = 0,
}

local function clearRouteState()
    state.points = {}
    state.activeSlot = nil
    state.routeLength = 0.0
    state.destinationPos = nil
    state.lastExtendAttempt = 0
    state.markerPhaseOffset = 0.0
    state.offRouteSince = 0
end

local function clampColorChannel(value, fallback)
    local numeric = tonumber(value)
    if numeric == nil then
        return fallback
    end

    return math.floor(math.max(0, math.min(255, numeric)))
end

local function getCurrentRouteTint()
    local tint = Config.routeColor or {}
    return {
        r = clampColorChannel(tint.r, 255),
        g = clampColorChannel(tint.g, 255),
        b = clampColorChannel(tint.b, 255),
        a = clampColorChannel(tint.a, 255),
    }
end

local function setRouteTint(r, g, b, a)
    local current = getCurrentRouteTint()
    local tint = {
        r = clampColorChannel(r, current.r),
        g = clampColorChannel(g, current.g),
        b = clampColorChannel(b, current.b),
        a = clampColorChannel(a, current.a),
    }

    Config.routeColor = {
        r = tint.r,
        g = tint.g,
        b = tint.b,
        a = tint.a,
    }

    Config.arrowColor = {
        r = tint.r,
        g = tint.g,
        b = tint.b,
        a = tint.a,
    }

    Config.texturedRoute.color = {
        r = tint.r,
        g = tint.g,
        b = tint.b,
        a = tint.a,
    }

    return tint
end

local function parseRouteTintInput(args, rawCommand)
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

local function vecNormalize2D(v)
    local mag = math.sqrt((v.x * v.x) + (v.y * v.y))
    if mag < 0.0001 then
        return vector3(0.0, 0.0, 0.0)
    end

    return vector3(v.x / mag, v.y / mag, 0.0)
end

local function vecLength2D(v)
    return (v.x * v.x) + (v.y * v.y)
end

local function vecDistance2D(a, b)
    if not a or not b then
        return 0.0
    end

    local delta = a - b
    return math.sqrt((delta.x * delta.x) + (delta.y * delta.y))
end

local function getEffectiveArrowSpacing()
    return math.max(0.1, tonumber(Config.arrowSpacing) or 1.0)
end

local function normalizePhase(phase, spacing)
    if spacing <= 0.0001 then
        return 0.0
    end

    local normalized = phase % spacing
    if normalized < 0.0 then
        normalized = normalized + spacing
    end
    return normalized
end

local function shiftMarkerPhaseByDistance(distance)
    local spacing = getEffectiveArrowSpacing()
    state.markerPhaseOffset = normalizePhase((state.markerPhaseOffset or 0.0) - distance, spacing)
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

local function ensureTexturedRouteReady()
    if not Config.texturedRoute.enabled then
        return false
    end

    if state.texturedRouteReady then
        return true
    end

    local textureDict = Config.texturedRoute.textureDict
    if type(textureDict) ~= 'string' or textureDict == '' then
        return false
    end

    if type(RequestStreamedTextureDict) ~= 'function' or type(HasStreamedTextureDictLoaded) ~= 'function' then
        return false
    end

    RequestStreamedTextureDict(textureDict, true)
    if HasStreamedTextureDictLoaded(textureDict) then
        state.texturedRouteReady = true
    end

    return state.texturedRouteReady
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

local function getWaypointDestination()
    if type(GetFirstBlipInfoId) ~= 'function'
        or type(DoesBlipExist) ~= 'function'
        or type(GetBlipInfoIdCoord) ~= 'function' then
        return nil
    end

    local blip = GetFirstBlipInfoId(8)
    if not blip or blip == 0 or not DoesBlipExist(blip) then
        return nil
    end

    local coords = GetBlipInfoIdCoord(blip)
    if not coords then
        return nil
    end

    return vector3(coords.x, coords.y, coords.z)
end

local function getCurrentRouteMaxDistance()
    local ped = PlayerPedId()
    if not ped or ped == 0 or not IsPedInAnyVehicle(ped, false) then
        return Config.maxDistanceSlow or Config.maxDistance or 250.0
    end

    local vehicle = GetVehiclePedIsIn(ped, false)
    if not vehicle or vehicle == 0 then
        return Config.maxDistanceSlow or Config.maxDistance or 250.0
    end

    local speedKmh = GetEntitySpeed(vehicle) * 3.6
    if speedKmh >= (Config.maxDistanceFastKmh or 200.0) then
        return Config.maxDistance or 500.0
    end

    if speedKmh >= (Config.maxDistanceMediumKmh or 100.0) then
        return Config.maxDistanceMedium or 350.0
    end

    return Config.maxDistanceSlow or 250.0
end

local function getDynamicUpdateInterval(speedKmh)
    local speed = speedKmh or 0.0
    if speed >= (Config.updateIntervalFastKmh or 200.0) then
        return Config.updateIntervalFast or 500
    end

    if speed >= (Config.updateIntervalMediumKmh or 100.0) then
        return Config.updateInterval or 1500
    end

    return Config.updateIntervalSlow or 2500
end

local function didDestinationChange()
    local currentDestination = getWaypointDestination()
    return not positionsClose2D(currentDestination, state.destinationPos, 1.0)
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
    local kept = {}
    local count = 0

    for key, entry in pairs(state.groundProbeCache) do
        if entry and entry.t and entry.t >= cutoff then
            kept[key] = entry
            count = count + 1
            if count >= maxEntries then
                break
            end
        end
    end

    state.groundProbeCache = kept
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

local function applyGroundProbeEnabled(enabled)
    local value = enabled == true
    Config.routeGroundProbeEnabled = value
    state.groundProbeCache = {}
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

    -- Bridge contiguous junction samples instead of dropping them, which keeps the 3D route continuous.
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

local function hasRenderableRoute()
    if GetGpsBlipRouteFound() then
        return true
    end

    for _, slotType in ipairs(Config.slotPriority) do
        local ok, pos = GetPosAlongGpsTypeRoute(true, 0.0, slotType)
        if ok and pos then
            return true
        end
    end

    return false
end

local function sampleSlot(slotType)
    local points = {}
    local maxDistance = getCurrentRouteMaxDistance()
    local targetLength = GetGpsBlipRouteLength()

    if targetLength <= 0 then
        targetLength = maxDistance
    else
        targetLength = math.min(targetLength, maxDistance)
    end

    local distance = 0.0
    while distance <= targetLength do
        local ok, pos = GetPosAlongGpsTypeRoute(true, distance, slotType)
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

        distance = distance + Config.sampleStep
    end

    if #points < 2 then
        return nil
    end

    markJunctionPadding(points)
    points = smoothJunctionTransitions(points)

    return points, targetLength
end

local function rebuildRoute()
    if not state.enabled then
        clearRouteState()
        return
    end

    if not getWaypointDestination() then
        clearRouteState()
        return
    end

    if not hasRenderableRoute() then
        clearRouteState()
        return
    end

    local nextPoints = nil
    local nextSlot = nil
    local nextRouteLength = 0.0

    for _, slotType in ipairs(Config.slotPriority) do
        local points, routeLength = sampleSlot(slotType)
        if points then
            nextPoints = points
            nextSlot = slotType
            nextRouteLength = routeLength
            break
        end
    end

    if nextPoints then
        state.points = nextPoints
        state.activeSlot = nextSlot
        state.routeLength = nextRouteLength
        state.destinationPos = getWaypointDestination()
        state.markerPhaseOffset = 0.0
    else
        clearRouteState()
    end
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
    local forwardDist = (rel.x * vehicleForward.x) + (rel.y * vehicleForward.y) + (rel.z * vehicleForward.z)
    return forwardDist >= -(Config.markerBehindCullBuffer or 2.0)
end

local function buildVisibleRoutePoints(points, vehiclePos, vehicleForward)
    if not Config.markerDrawAheadOnly or not vehiclePos or not vehicleForward then
        return points, 0.0
    end

    local firstAhead = nil
    for i = 1, #points do
        if isPointAheadOfVehicle(points[i].pos, vehiclePos, vehicleForward) then
            firstAhead = i
            break
        end
    end

    if not firstAhead then
        return {}, 0.0
    end

    local startIndex = math.max(1, firstAhead - 1)
    local skippedDistance = 0.0
    for i = 1, startIndex - 1 do
        skippedDistance = skippedDistance + math.sqrt(vecLength2(points[i + 1].pos - points[i].pos))
    end

    local visible = {}
    for i = startIndex, #points do
        visible[#visible + 1] = points[i]
    end

    return visible, skippedDistance
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
    local removedDistance = 0.0
    for i = 1, removeCount do
        removedDistance = removedDistance + math.sqrt(vecLength2(points[i + 1].pos - points[i].pos))
    end
    for i = removeCount + 1, #points do
        trimmed[outIndex] = points[i]
        outIndex = outIndex + 1
    end

    state.points = trimmed
    shiftMarkerPhaseByDistance(removedDistance)
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

    local currentLast = state.points[#state.points].pos
    local bestPoints = nil
    local bestLength = 0.0

    for _, slotType in ipairs(Config.slotPriority) do
        local points, routeLength = sampleSlot(slotType)
        if points and #points >= 2 then
            bestPoints = points
            bestLength = routeLength or 0.0
            break
        end
    end

    if not bestPoints then
        return false
    end

    local joinIndex = nil
    local bestJoinDist = math.huge
    for i = 1, #bestPoints do
        local dist = vecDistance2D(currentLast, bestPoints[i].pos)
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
    for i = joinIndex + 1, #bestPoints do
        if vecLength2(bestPoints[i].pos - lastPos) > 0.25 then
            state.points[#state.points + 1] = bestPoints[i]
            lastPos = bestPoints[i].pos
            appended = appended + 1
        end
    end

    if appended > 0 then
        state.routeLength = bestLength
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

local function drawArrow(prevPos, pos, nextPos)
    local forward = vecNormalize2D(nextPos - prevPos)
    if vecLength2(forward) < 0.0001 then
        return
    end

    local side = vector3(-forward.y, forward.x, 0.0)
    local tip = pos + (forward * Config.arrowLength)
    local left = pos - (forward * (Config.arrowLength * 0.55)) + (side * Config.arrowWidth)
    local right = pos - (forward * (Config.arrowLength * 0.55)) - (side * Config.arrowWidth)

    DrawLine(left.x, left.y, left.z, tip.x, tip.y, tip.z, Config.arrowColor.r, Config.arrowColor.g, Config.arrowColor.b, Config.arrowColor.a)
    DrawLine(right.x, right.y, right.z, tip.x, tip.y, tip.z, Config.arrowColor.r, Config.arrowColor.g, Config.arrowColor.b, Config.arrowColor.a)
end

local function getRibbonTangent(points, index)
    if index < 1 or index > #points then
        return vector3(0.0, 0.0, 0.0)
    end

    local tangent = vector3(0.0, 0.0, 0.0)

    if index > 1 then
        tangent = tangent + vecNormalize2D(points[index].pos - points[index - 1].pos)
    end

    if index < #points then
        tangent = tangent + vecNormalize2D(points[index + 1].pos - points[index].pos)
    end

    if vecLength2D(tangent) < 0.0001 then
        if index < #points then
            tangent = vecNormalize2D(points[index + 1].pos - points[index].pos)
        elseif index > 1 then
            tangent = vecNormalize2D(points[index].pos - points[index - 1].pos)
        end
    else
        tangent = vecNormalize2D(tangent)
    end

    return tangent
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

local function drawRouteTexturedSegment(aLeft, aRight, bLeft, bRight, startV, endV)
    local texture = Config.texturedRoute
    local color = texture.color

    DrawTexturedPoly(
        aLeft.x, aLeft.y, aLeft.z,
        bLeft.x, bLeft.y, bLeft.z,
        bRight.x, bRight.y, bRight.z,
        color.r, color.g, color.b, color.a,
        texture.textureDict, texture.textureName,
        0.0, startV, 1.0,
        0.0, endV, 1.0,
        1.0, endV, 1.0
    )

    DrawTexturedPoly(
        aLeft.x, aLeft.y, aLeft.z,
        bRight.x, bRight.y, bRight.z,
        aRight.x, aRight.y, aRight.z,
        color.r, color.g, color.b, color.a,
        texture.textureDict, texture.textureName,
        0.0, startV, 1.0,
        1.0, endV, 1.0,
        1.0, startV, 1.0
    )
end

local function drawTexturedRoute(points, vehiclePos, vehicleForward)
    if not Config.texturedRoute.enabled or #points < 2 then
        return false
    end

    if type(DrawTexturedPoly) ~= 'function' or not ensureTexturedRouteReady() then
        return false
    end

    local texture = Config.texturedRoute
    local repeatDistance = math.max(texture.repeatDistance or 1.0, 0.01)
    local accumulatedDistance = 0.0
    local cullingChanged = false

    if texture.disableBackfaceCulling and type(SetBackfaceculling) == 'function' then
        SetBackfaceculling(false)
        cullingChanged = true
    end

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        local segmentDistance = vecDistance2D(a.pos, b.pos)

        if segmentDistance > 0.01 then
            if (not Config.ignoreJunctionNodes or (not a.junctionZone and not b.junctionZone))
                and shouldDrawSegmentAhead(a.pos, b.pos, vehiclePos, vehicleForward) then
                local aLeft, aRight = getRibbonVertices(points, i, texture.width, texture.lift)
                local bLeft, bRight = getRibbonVertices(points, i + 1, texture.width, texture.lift)

                if aLeft and aRight and bLeft and bRight then
                    local startV = accumulatedDistance / repeatDistance
                    local endV = (accumulatedDistance + segmentDistance) / repeatDistance
                    drawRouteTexturedSegment(aLeft, aRight, bLeft, bRight, startV, endV)
                end
            end

            accumulatedDistance = accumulatedDistance + segmentDistance
        end
    end

    if cullingChanged and type(SetBackfaceculling) == 'function' then
        SetBackfaceculling(true)
    end

    return true
end

local function drawRoute()
    local points = state.points
    if #points < 2 then
        return
    end

    local ped = PlayerPedId()
    local vehiclePos = nil
    local vehicleForward = nil
    if ped and ped ~= 0 and IsPedInAnyVehicle(ped, false) then
        local vehicle = GetVehiclePedIsIn(ped, false)
        if vehicle and vehicle ~= 0 then
            vehiclePos = GetEntityCoords(vehicle)
            vehicleForward = GetEntityForwardVector(vehicle)
        end
    end

    local renderPoints = points

    local drewTexturedRoute = false
    if state.routeRenderType == 2 and #renderPoints >= 2 then
        drewTexturedRoute = drawTexturedRoute(renderPoints, vehiclePos, vehicleForward)
    end

    if state.routeRenderType == 1 or not drewTexturedRoute then
        for i = 1, #renderPoints - 1 do
            local a = renderPoints[i]
            local b = renderPoints[i + 1]
            if (not Config.ignoreJunctionNodes or (not a.junctionZone and not b.junctionZone))
                and shouldDrawSegmentAhead(a.pos, b.pos, vehiclePos, vehicleForward) then
                local aPos = a.pos
                local bPos = b.pos
                DrawLine(aPos.x, aPos.y, aPos.z, bPos.x, bPos.y, bPos.z, Config.routeColor.r, Config.routeColor.g, Config.routeColor.b, Config.routeColor.a)
            end
        end
    end

    if state.routeRenderType == 2 and drewTexturedRoute and not Config.texturedRoute.drawArrowOverlay then
        return
    end

    local effectiveSpacing = getEffectiveArrowSpacing()
    local carryDistance = normalizePhase(state.markerPhaseOffset or 0.0, effectiveSpacing)
    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        if not Config.ignoreJunctionNodes or (not a.junctionZone and not b.junctionZone) then
            local aPos = a.pos
            local bPos = b.pos
            local seg = bPos - aPos
            local segLen = math.sqrt(vecLength2(seg))
            if segLen > 0.001 then
                local dir = seg / segLen
                local distOnSeg = carryDistance
                while distOnSeg <= segLen do
                    local pos = aPos + (dir * distOnSeg)
                    local hintDist = math.max(0.5, effectiveSpacing * 0.5)
                    local prevPos = pos - (dir * hintDist)
                    local nextPos = pos + (dir * hintDist)
                    if isPointAheadOfVehicle(pos, vehiclePos, vehicleForward) then
                        drawArrow(prevPos, pos, nextPos)
                    end
                    distOnSeg = distOnSeg + effectiveSpacing
                end

                carryDistance = distOnSeg - segLen
                if carryDistance >= effectiveSpacing then
                    carryDistance = carryDistance % effectiveSpacing
                end
            else
                carryDistance = 0.0
            end
        end
    end
end

CreateThread(function()
    while true do
        local waitTime = 500

        if state.enabled then
            local ped = PlayerPedId()
            if Config.drawWhenOnFoot or IsPedInAnyVehicle(ped, false) then
                waitTime = 0
                drawRoute()
            end
        end

        Wait(waitTime)
    end
end)

CreateThread(function()
    while true do
        if state.enabled then
            local now = GetGameTimer()
            local ped = PlayerPedId()
            local playerPos = ped and ped ~= 0 and GetEntityCoords(ped) or nil
            local speedKmh = 0.0
            if ped and ped ~= 0 and IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle and vehicle ~= 0 then
                    speedKmh = GetEntitySpeed(vehicle) * 3.6
                end
            end
            if didDestinationChange() then
                state.lastUpdate = now
                rebuildRoute()
            elseif playerPos and shouldRebuildForOffRoute(playerPos, speedKmh, now) then
                state.lastUpdate = now
                rebuildRoute()
            elseif playerPos and shouldExtendRouteNearEnd(playerPos) and (now - (state.lastExtendAttempt or 0) >= (Config.routeExtendCooldownMs or 700)) then
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
        else
            state.points = {}
            state.activeSlot = nil
            state.routeLength = 0.0
            state.lastExtendAttempt = 0
            state.groundProbeCache = {}
            state.markerPhaseOffset = 0.0
            state.offRouteSince = 0
            state.lastOffRouteRebuild = 0
        end

        Wait(100)
    end
end)

RegisterCommand('gps3d', function()
    state.enabled = not state.enabled
    if state.enabled then
        rebuildRoute()
    else
        state.points = {}
        state.activeSlot = nil
        state.routeLength = 0.0
        state.lastExtendAttempt = 0
        state.groundProbeCache = {}
        state.markerPhaseOffset = 0.0
        state.offRouteSince = 0
        state.lastOffRouteRebuild = 0
    end

    local message = state.enabled and '^2GPS 3D enabled.^7' or '^1GPS 3D disabled.^7'
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 255 },
        multiline = false,
        args = { 'l2k_gps3d', message }
    })
end, false)

RegisterCommand('gps3d_refresh', function()
    rebuildRoute()

    local slotText = state.activeSlot ~= nil and tostring(state.activeSlot) or 'none'
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 255 },
        multiline = false,
        args = { 'l2k_gps3d', ('^5Refresh.^7 slot=%s points=%d length=%.1f'):format(slotText, #state.points, state.routeLength) }
    })
end, false)

RegisterCommand('gps3d_groundprobe', function(_, args)
    local action = args and args[1] and string.lower(args[1]) or 'toggle'

    if action == 'on' then
        applyGroundProbeEnabled(true)
    elseif action == 'off' then
        applyGroundProbeEnabled(false)
    elseif action == 'toggle' then
        applyGroundProbeEnabled(not Config.routeGroundProbeEnabled)
    elseif action ~= 'status' then
        TriggerEvent('chat:addMessage', {
            color = { 255, 255, 255 },
            multiline = false,
            args = { 'l2k_gps3d', '^3Usage:^7 /gps3d_groundprobe on|off|toggle|status' }
        })
        return
    end

    if action ~= 'status' then
        rebuildRoute()
    end

    local statusText = Config.routeGroundProbeEnabled and '^2aktiv^7' or '^1inaktiv^7'
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 255 },
        multiline = false,
        args = { 'l2k_gps3d', ('Ground-Z-Probe ist %s.'):format(statusText) }
    })
end, false)

RegisterCommand('gps3dtype', function(_, args)
    local requestedType = tonumber(args and args[1] or '')
    if requestedType ~= 1 and requestedType ~= 2 then
        local currentType = state.routeRenderType == 2 and '2 (Rect+Uvmap)' or '1 (Lines)'
        TriggerEvent('chat:addMessage', {
            color = { 255, 255, 255 },
            multiline = false,
            args = { 'l2k_gps3d', ('^3Usage:^7 /gps3dtype 1^7 or ^2/gps3dtype 2^7. Current: %s'):format(currentType) }
        })
        return
    end

    state.routeRenderType = requestedType
    if requestedType == 2 then
        ensureTexturedRouteReady()
    end

    local modeLabel = requestedType == 2 and '^2Rect+Uvmap^7' or '^5Lines^7'
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 255 },
        multiline = false,
        args = { 'l2k_gps3d', ('3D GPS mode changed to %s'):format(modeLabel) }
    })
end, false)

RegisterCommand('gps3dcolor', function(_, args, rawCommand)
    local currentTint = getCurrentRouteTint()
    local r, g, b, a = parseRouteTintInput(args, rawCommand)

    if r == nil or g == nil or b == nil then
        TriggerEvent('chat:addMessage', {
            color = { 255, 255, 255 },
            multiline = false,
            args = {
                'l2k_gps3d',
                ('^3Usage:^7 /gps3color r g b [a]^7 or ^3/gps3color r,g,b,a^7. Current: rgba(%d, %d, %d, %d)'):format(currentTint.r, currentTint.g, currentTint.b, currentTint.a)
            }
        })
        return
    end

    local appliedTint = setRouteTint(r, g, b, a)
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 255 },
        multiline = false,
        args = {
            'l2k_gps3d',
            ('3D GPS color changed to rgba(%d, %d, %d, %d)'):format(appliedTint.r, appliedTint.g, appliedTint.b, appliedTint.a)
        }
    })
end, false)

CreateThread(function()
    Wait(1000)
    if type(GetPosAlongGpsTypeRoute) ~= 'function' then
        print('[l2k_gps3d] Native GetPosAlongGpsTypeRoute was not found in this runtime.')
        return
    end

    ensureTexturedRouteReady()
    rebuildRoute()
    print(('[l2k_gps3d] ready. Use /gps3d, /gps3d_refresh, /gps3d_groundprobe, /gps3dtype 1|2, and /gps3color r g b [a]. Current type: %s'):format(state.routeRenderType))
end)
