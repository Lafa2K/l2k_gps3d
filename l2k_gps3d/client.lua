local Config = {
    enabled = true,
    drawWhenOnFoot = true,
    sampleStep = 6.0,
    maxDistance = 520.0,
    ignoreJunctionNodes = false,
    smoothJunctionTransitions = true,
    junctionPaddingPoints = 1,
    junctionCurveStrength = 0.55,
    junctionCurveMaxHandle = 6.0,
    arrowSpacing = 1.0,
    arrowLength = 1.5,
    arrowWidth = 0.8,
    routeHeight = 0.22,
    updateInterval = 2500,
    slotPriority = { 0, 1, 2 },
    routeRenderType = 2, -- 1 = lines, 2 = rect + uvmap
    routeColor = { r = 64, g = 200, b = 255, a = 180 },
    arrowColor = { r = 0, g = 255, b = 180, a = 220 },
    texturedRoute = {
        enabled = true,
        textureDict = 'chevrons',
        textureName = 'chevrons',
        width = 1.35,
        lift = 0.03,
        repeatDistance = 4.0,
        color = { r = 255, g = 255, b = 255, a = 205 },
        drawArrowOverlay = false,
        disableBackfaceCulling = true,
    },
    destinationMarkerEnabled = true,
    destinationMarkerType = 2, -- MarkerTypeThickChevronUp
    destinationMarkerLift = 2.0,
    destinationMarkerGroundProbeZ = 1000.0,
    destinationMarkerGroundOffset = 0.15,
    destinationMarkerScale = { x = 3.0, y = 3.0, z = 2.9 },
    destinationMarkerColor = { r = 0, g = 255, b = 180, a = 190 },
    destinationChangeThreshold = 1.0,
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
    destinationMarkerPos = nil,
    texturedRouteReady = false,
    routeRenderType = Config.routeRenderType,
}

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

local function resolveDestinationMarkerPos(destinationPos, fallbackPos)
    if not destinationPos then
        if not fallbackPos then
            return nil
        end

        return vector3(fallbackPos.x, fallbackPos.y, fallbackPos.z + Config.destinationMarkerLift)
    end

    local markerZ = destinationPos.z
    if type(GetGroundZFor_3dCoord) == 'function' then
        local foundGround, groundZ = GetGroundZFor_3dCoord(
            destinationPos.x,
            destinationPos.y,
            Config.destinationMarkerGroundProbeZ,
            false
        )

        if foundGround then
            markerZ = groundZ + Config.destinationMarkerGroundOffset
        end
    end

    if fallbackPos and markerZ <= 0.01 then
        markerZ = fallbackPos.z - Config.routeHeight
    end

    return vector3(destinationPos.x, destinationPos.y, markerZ + Config.destinationMarkerLift)
end

local function updateDestinationMarker(points)
    local fallbackPos = nil
    if points and #points > 0 then
        fallbackPos = points[#points].pos
    end

    state.destinationPos = getWaypointDestination()
    state.destinationMarkerPos = resolveDestinationMarkerPos(state.destinationPos, fallbackPos)
end

local function didDestinationChange()
    local currentDestination = getWaypointDestination()
    return not positionsClose2D(currentDestination, state.destinationPos, Config.destinationChangeThreshold)
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
    local targetLength = GetGpsBlipRouteLength()

    if targetLength <= 0 then
        targetLength = Config.maxDistance
    else
        targetLength = math.min(targetLength, Config.maxDistance)
    end

    local distance = 0.0
    while distance <= targetLength do
        local ok, pos = GetPosAlongGpsTypeRoute(true, distance, slotType)
        if not ok or not pos then
            break
        end

        local basePos = vector3(pos.x, pos.y, pos.z)
        local point = {
            pos = vector3(basePos.x, basePos.y, basePos.z + Config.routeHeight),
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
    state.points = {}
    state.activeSlot = nil
    state.routeLength = 0.0
    state.destinationMarkerPos = nil

    if not state.enabled then
        state.destinationPos = nil
        return
    end

    if not hasRenderableRoute() then
        updateDestinationMarker(nil)
        return
    end

    for _, slotType in ipairs(Config.slotPriority) do
        local points, routeLength = sampleSlot(slotType)
        if points then
            state.points = points
            state.activeSlot = slotType
            state.routeLength = routeLength
            updateDestinationMarker(points)
            return
        end
    end

    updateDestinationMarker(nil)
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

    local tangent = getRibbonTangent(points, index)
    if vecLength2D(tangent) < 0.0001 then
        return nil, nil
    end

    local halfWidth = width * 0.5
    local side = vector3(-tangent.y, tangent.x, 0.0) * halfWidth
    local basePos = point.pos + vector3(0.0, 0.0, lift or 0.0)

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

local function drawTexturedRoute(points)
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
            if not Config.ignoreJunctionNodes or (not a.junctionZone and not b.junctionZone) then
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

    local drewTexturedRoute = false
    if state.routeRenderType == 2 then
        drewTexturedRoute = drawTexturedRoute(points)
    end

    if state.routeRenderType == 1 or not drewTexturedRoute then
        for i = 1, #points - 1 do
            local a = points[i]
            local b = points[i + 1]
            if not Config.ignoreJunctionNodes or (not a.junctionZone and not b.junctionZone) then
                local aPos = a.pos
                local bPos = b.pos
                DrawLine(aPos.x, aPos.y, aPos.z, bPos.x, bPos.y, bPos.z, Config.routeColor.r, Config.routeColor.g, Config.routeColor.b, Config.routeColor.a)
            end
        end
    end

    if state.routeRenderType == 2 and drewTexturedRoute and not Config.texturedRoute.drawArrowOverlay then
        return
    end

    local spacingCount = math.max(1, math.floor(Config.arrowSpacing / Config.sampleStep))
    for i = 2, #points - 1, spacingCount do
        local prevPoint = points[i - 1]
        local currPoint = points[i]
        local nextPoint = points[i + 1]

        if not Config.ignoreJunctionNodes or (not prevPoint.junctionZone and not currPoint.junctionZone and not nextPoint.junctionZone) then
            drawArrow(prevPoint.pos, currPoint.pos, nextPoint.pos)
        end
    end
end

local function drawDestinationMarker()
    if not Config.destinationMarkerEnabled or not state.destinationMarkerPos then
        return
    end

    local pos = state.destinationMarkerPos
    local scale = Config.destinationMarkerScale
    local color = Config.destinationMarkerColor

    DrawMarker(
        Config.destinationMarkerType,
        pos.x, pos.y, pos.z+1,
        0.0, 0.0, 0.0,
        180.0, 0.0, 0.0,
        scale.x, scale.y, scale.z,
        color.r, color.g, color.b, color.a,
        false,
        false,
        2,
        false,
        nil,
        nil,
        false
    )
end

CreateThread(function()
    while true do
        local waitTime = 500

        if state.enabled then
            local ped = PlayerPedId()
            if Config.drawWhenOnFoot or IsPedInAnyVehicle(ped, false) then
                waitTime = 0
                drawRoute()
                drawDestinationMarker()
            end
        end

        Wait(waitTime)
    end
end)

CreateThread(function()
    while true do
        if state.enabled then
            local now = GetGameTimer()
            if didDestinationChange() then
                state.lastUpdate = now
                rebuildRoute()
            elseif now - state.lastUpdate >= Config.updateInterval then
                state.lastUpdate = now
                rebuildRoute()
            end
        else
            state.points = {}
            state.activeSlot = nil
            state.routeLength = 0.0
            state.destinationPos = nil
            state.destinationMarkerPos = nil
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
    print(('[l2k_gps3d] ready. Use /gps3d, /gps3d_refresh, /gps3dtype 1|2, and /gps3color r g b [a]. Current type: %s'):format(state.routeRenderType))
end)
