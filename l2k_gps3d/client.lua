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
    routeColor = { r = 64, g = 200, b = 255, a = 180 },
    arrowColor = { r = 0, g = 255, b = 180, a = 220 },
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
}

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

    if not state.enabled then
        return
    end

    if not hasRenderableRoute() then
        return
    end

    for _, slotType in ipairs(Config.slotPriority) do
        local points, routeLength = sampleSlot(slotType)
        if points then
            state.points = points
            state.activeSlot = slotType
            state.routeLength = routeLength
            return
        end
    end
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

local function drawRoute()
    local points = state.points
    if #points < 2 then
        return
    end

    for i = 1, #points - 1 do
        local a = points[i]
        local b = points[i + 1]
        if not Config.ignoreJunctionNodes or (not a.junctionZone and not b.junctionZone) then
            local aPos = a.pos
            local bPos = b.pos
            DrawLine(aPos.x, aPos.y, aPos.z, bPos.x, bPos.y, bPos.z, Config.routeColor.r, Config.routeColor.g, Config.routeColor.b, Config.routeColor.a)
        end
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
            if now - state.lastUpdate >= Config.updateInterval then
                state.lastUpdate = now
                rebuildRoute()
            end
        else
            state.points = {}
            state.activeSlot = nil
            state.routeLength = 0.0
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

    local message = state.enabled and '^2GPS 3D ligado.^7' or '^1GPS 3D desligado.^7'
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

CreateThread(function()
    Wait(1000)
    if type(GetPosAlongGpsTypeRoute) ~= 'function' then
        print('[l2k_gps3d] Native GetPosAlongGpsTypeRoute nao encontrada neste runtime.')
        return
    end

    rebuildRoute()
    print('[l2k_gps3d] pronto. Use /gps3d para ligar/desligar e /gps3d_refresh para forcar um rebuild.')
end)
