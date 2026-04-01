local Config = {
    enabled = true,
    drawWhenOnFoot = true,
    sampleStep = 6.0,
    maxDistance = 220.0,
    arrowSpacing = 18.0,
    arrowLength = 1.5,
    arrowWidth = 0.8,
    routeHeight = 0.12,
    updateInterval = 250,
    slotPriority = { 0, 1, 2 },
    routeColor = { r = 64, g = 200, b = 255, a = 180 },
    arrowColor = { r = 0, g = 255, b = 180, a = 220 },
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

        pos = vector3(pos.x, pos.y, pos.z + Config.routeHeight)

        if #points == 0 then
            points[#points + 1] = pos
        else
            local delta = pos - points[#points]
            if vecLength2(delta) > 0.25 then
                points[#points + 1] = pos
            end
        end

        distance = distance + Config.sampleStep
    end

    if #points < 2 then
        return nil
    end

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
        DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, Config.routeColor.r, Config.routeColor.g, Config.routeColor.b, Config.routeColor.a)
    end

    local spacingCount = math.max(1, math.floor(Config.arrowSpacing / Config.sampleStep))
    for i = 2, #points - 1, spacingCount do
        drawArrow(points[i - 1], points[i], points[i + 1])
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
