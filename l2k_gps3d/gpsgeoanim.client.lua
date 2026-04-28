--[[
===============================================================================
 l2k_gps3d geoanim module
-----------------------------------------------------------------------------
 Commands:
 - /geoanim
 - /geoanim on
 - /geoanim off
 - /geoanim status

 Main exports:
 - StartInstall(vehicle, options)
 - StartGarageInstall(vehicle, options)
 - PlayInstall(vehicle, options)
 - StopInstall()
 - IsInstallRunning()
===============================================================================
]]

local Config = L2KGpsGeoAnimConfig or {}

local BOX_EDGES = {
    { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
    { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
    { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
}

local VEHICLE_BONE_LINES = {
    { 'wheel_lf', 'wheel_rf', 0.95 },
    { 'wheel_lr', 'wheel_rr', 0.95 },
    { 'wheel_lf', 'wheel_lr', 0.55 },
    { 'wheel_rf', 'wheel_rr', 0.55 },
    { 'wheel_lf', 'chassis_dummy', 0.45 },
    { 'wheel_rf', 'chassis_dummy', 0.45 },
    { 'wheel_lr', 'chassis_dummy', 0.45 },
    { 'wheel_rr', 'chassis_dummy', 0.45 },
    { 'bonnet', 'chassis_dummy', 0.65 },
    { 'boot', 'chassis_dummy', 0.65 },
    { 'door_dside_f', 'door_pside_f', 0.45 },
    { 'door_dside_r', 'door_pside_r', 0.35 },
}

local state = {
    enabled = Config.enabled ~= false,
    elapsed = 0.0,
    timeScale = Config.timeScale or 1.0,
    autoDisableAfter = Config.autoDisableAfter,
    targetVehicle = 0,
    outlined = {},
    frameOutlined = {},
    audioBankLoaded = false,
    activeProfileName = Config.defaultProfile or 'on',
    activeProfile = nil,
    modelDimensionCache = {},
    modelBoneIndexCache = {},
}

local function notify(message)
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 255 },
        multiline = false,
        args = { 'l2k_gps3d', message }
    })
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function lerpVector(a, b, t)
    a = a or vector3(0.0, 0.0, 0.0)
    b = b or a
    return vector3(lerp(a.x, b.x, t), lerp(a.y, b.y, t), lerp(a.z, b.z, t))
end

local function lerpColor(a, b, t)
    a = a or { r = 255, g = 255, b = 255, a = 255 }
    b = b or a
    return {
        r = math.floor(lerp(a.r or 255, b.r or 255, t) + 0.5),
        g = math.floor(lerp(a.g or 255, b.g or 255, t) + 0.5),
        b = math.floor(lerp(a.b or 255, b.b or 255, t) + 0.5),
        a = math.floor(lerp(a.a or 255, b.a or 255, t) + 0.5),
    }
end

local function clearTable(target)
    for key in pairs(target) do
        target[key] = nil
    end
end

local function rotateVector(v, rot)
    rot = rot or vector3(0.0, 0.0, 0.0)
    local rx = math.rad(rot.x or 0.0)
    local ry = math.rad(rot.y or 0.0)
    local rz = math.rad(rot.z or 0.0)

    local cx, sx = math.cos(rx), math.sin(rx)
    local cy, sy = math.cos(ry), math.sin(ry)
    local cz, sz = math.cos(rz), math.sin(rz)

    local y1 = v.y * cx - v.z * sx
    local z1 = v.y * sx + v.z * cx
    local x1 = v.x

    local x2 = x1 * cy + z1 * sy
    local z2 = -x1 * sy + z1 * cy
    local y2 = y1

    local x3 = x2 * cz - y2 * sz
    local y3 = x2 * sz + y2 * cz

    return vector3(x3, y3, z2)
end

local function ease(name, t)
    if name == 'smooth' then
        return t * t * (3.0 - 2.0 * t)
    end

    if name == 'inOutQuad' then
        if t < 0.5 then
            return 2.0 * t * t
        end
        return 1.0 - ((-2.0 * t + 2.0) ^ 2) / 2.0
    end

    return t
end

local function sortedKeyframes(object)
    if object._sortedKeyframes then
        return object._sortedKeyframes
    end

    local keyframes = {}
    for _, keyframe in ipairs(object.keyframes or {}) do
        keyframes[#keyframes + 1] = keyframe
    end

    table.sort(keyframes, function(a, b)
        return (a.t or 0.0) < (b.t or 0.0)
    end)

    object._sortedKeyframes = keyframes
    return keyframes
end

local function getLocalTime(object)
    local duration = object.duration or Config.duration or 1.0
    local delay = object.delay or 0.0
    local localTime = state.elapsed - delay

    if localTime < 0.0 then
        return nil
    end

    if object.loop ~= false then
        return localTime % duration
    end

    if localTime > duration then
        return nil
    end

    return localTime
end

local function sampleObject(object)
    local keyframes = sortedKeyframes(object)
    if #keyframes == 0 then
        return nil
    end

    local localTime = getLocalTime(object)
    if not localTime then
        return nil
    end

    local first = keyframes[1]
    local last = keyframes[#keyframes]

    if localTime < (first.t or 0.0) or localTime > (last.t or 0.0) then
        return nil
    end

    local from = first
    local to = last

    for i = 1, #keyframes - 1 do
        local a = keyframes[i]
        local b = keyframes[i + 1]
        if localTime >= (a.t or 0.0) and localTime <= (b.t or 0.0) then
            from = a
            to = b
            break
        end
    end

    local span = math.max((to.t or 0.0) - (from.t or 0.0), 0.0001)
    local t = clamp((localTime - (from.t or 0.0)) / span, 0.0, 1.0)
    t = ease(object.ease or to.ease or from.ease or 'linear', t)

    return {
        pos = lerpVector(from.pos, to.pos, t),
        endPos = lerpVector(from.endPos, to.endPos, t),
        rot = lerpVector(from.rot, to.rot, t),
        size = lerpVector(from.size, to.size, t),
        color = lerpColor(from.color, to.color, t),
        text = to.text or from.text or object.text,
        localTime = localTime,
        progress = localTime / math.max(object.duration or Config.duration or 1.0, 0.0001),
    }
end

local findClosestVehicle

local function getTargetVehicle(searchPos, radius)
    if state.targetVehicle ~= 0 and DoesEntityExist(state.targetVehicle) then
        return state.targetVehicle
    end

    return findClosestVehicle(searchPos, radius or Config.defaultSearchRadius or 32.0)
end

local function attachSampleToVehicle(object, sample)
    if object.attachToVehicle ~= true then
        return sample
    end

    local searchPos = object.vehicleSearchPos or sample.pos
    local vehicle = getTargetVehicle(searchPos, object.vehicleRadius or object.radius)
    if vehicle == 0 then
        return nil
    end

    local pos = sample.pos or vector3(0.0, 0.0, 0.0)
    local endPos = sample.endPos or pos
    sample.pos = GetOffsetFromEntityInWorldCoords(vehicle, pos.x, pos.y, pos.z)
    sample.endPos = GetOffsetFromEntityInWorldCoords(vehicle, endPos.x, endPos.y, endPos.z)

    if sample.rot then
        sample.rot = vector3(sample.rot.x, sample.rot.y, sample.rot.z + GetEntityHeading(vehicle))
    end

    sample.attachedVehicle = vehicle
    return sample
end

local function drawBoxShape(object, sample)
    local half = sample.size * 0.5

    if object.solid == true then
        DrawBox(
            sample.pos.x - half.x, sample.pos.y - half.y, sample.pos.z - half.z,
            sample.pos.x + half.x, sample.pos.y + half.y, sample.pos.z + half.z,
            sample.color.r, sample.color.g, sample.color.b, sample.color.a
        )
        return
    end

    local corners = {
        sample.pos + rotateVector(vector3(-half.x, -half.y, -half.z), sample.rot),
        sample.pos + rotateVector(vector3( half.x, -half.y, -half.z), sample.rot),
        sample.pos + rotateVector(vector3( half.x,  half.y, -half.z), sample.rot),
        sample.pos + rotateVector(vector3(-half.x,  half.y, -half.z), sample.rot),
        sample.pos + rotateVector(vector3(-half.x, -half.y,  half.z), sample.rot),
        sample.pos + rotateVector(vector3( half.x, -half.y,  half.z), sample.rot),
        sample.pos + rotateVector(vector3( half.x,  half.y,  half.z), sample.rot),
        sample.pos + rotateVector(vector3(-half.x,  half.y,  half.z), sample.rot),
    }

    local edges = {
        { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
        { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
        { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
    }

    for _, edge in ipairs(edges) do
        local a = corners[edge[1]]
        local b = corners[edge[2]]
        DrawLine(a.x, a.y, a.z, b.x, b.y, b.z, sample.color.r, sample.color.g, sample.color.b, sample.color.a)
    end
end

local function drawLineShape(_, sample)
    DrawLine(
        sample.pos.x, sample.pos.y, sample.pos.z,
        sample.endPos.x, sample.endPos.y, sample.endPos.z,
        sample.color.r, sample.color.g, sample.color.b, sample.color.a
    )
end

local function drawText3DShape(object, sample)
    if not sample.text then
        return
    end

    local text = sample.text
    if object.typewriter == true then
        local count = math.floor(#text * clamp(sample.progress * (object.typeSpeed or 2.0), 0.0, 1.0))
        text = text:sub(1, math.max(1, count))
    end

    local onScreen, x, y = World3dToScreen2d(sample.pos.x, sample.pos.y, sample.pos.z)
    if not onScreen then
        return
    end

    SetTextScale(object.scale or 0.34, object.scale or 0.34)
    SetTextFont(object.font or 4)
    SetTextProportional(true)
    SetTextCentre(true)
    SetTextColour(sample.color.r, sample.color.g, sample.color.b, sample.color.a)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function drawWorldText(pos, text, color, scale)
    local onScreen, x, y = World3dToScreen2d(pos.x, pos.y, pos.z)
    if not onScreen then
        return
    end

    SetTextScale(scale or 0.34, scale or 0.34)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextCentre(true)
    SetTextColour(color.r, color.g, color.b, color.a)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function getProfileConfig(profileName)
    local profiles = Config.profiles or {}

    if type(profileName) == 'string' and profiles[profileName] then
        return profiles[profileName], profileName
    end

    local defaultProfile = Config.defaultProfile
    if type(defaultProfile) == 'string' and profiles[defaultProfile] then
        return profiles[defaultProfile], defaultProfile
    end

    if Config.objects then
        return {
            timeScale = Config.timeScale,
            autoDisableAfter = Config.autoDisableAfter,
            objects = Config.objects,
        }, profileName or 'legacy'
    end

    return nil, nil
end

local function getActiveObjects()
    local profile = state.activeProfile
    if profile and type(profile.objects) == 'table' then
        return profile.objects
    end

    return Config.objects or {}
end

function findClosestVehicle(coords, radius)
    local vehicles = GetGamePool('CVehicle')
    local closest = 0
    local closestDistance = radius or 25.0

    for _, vehicle in ipairs(vehicles) do
        if DoesEntityExist(vehicle) then
            local dist = #(GetEntityCoords(vehicle) - coords)
            if dist < closestDistance then
                closest = vehicle
                closestDistance = dist
            end
        end
    end

    return closest
end

local function setOutline(entity, enabled, color)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return
    end

    if enabled then
        SetEntityDrawOutlineColor(color.r, color.g, color.b, color.a)
        SetEntityDrawOutlineShader(1)
        SetEntityDrawOutline(entity, true)
        state.outlined[entity] = true
        state.frameOutlined[entity] = true
    else
        SetEntityDrawOutline(entity, false)
        state.outlined[entity] = nil
    end
end

local function cleanupOutlines()
    if next(state.outlined) == nil then
        return
    end

    for entity in pairs(state.outlined) do
        if DoesEntityExist(entity) then
            SetEntityDrawOutline(entity, false)
        end
        state.outlined[entity] = nil
    end
end

local function cleanupUnusedOutlines()
    if next(state.outlined) == nil then
        return
    end

    for entity in pairs(state.outlined) do
        if not state.frameOutlined[entity] then
            if DoesEntityExist(entity) then
                SetEntityDrawOutline(entity, false)
            end
            state.outlined[entity] = nil
        end
    end
end

local function getModelDimensionsCached(model)
    local cached = state.modelDimensionCache[model]
    if cached then
        return cached.minDim, cached.maxDim
    end

    local minDim, maxDim = GetModelDimensions(model)
    state.modelDimensionCache[model] = {
        minDim = minDim,
        maxDim = maxDim,
    }

    return minDim, maxDim
end

local function getEntityBoxCorners(entity, expand)
    local model = GetEntityModel(entity)
    local minDim, maxDim = getModelDimensionsCached(model)
    expand = expand or 0.0

    minDim = vector3(minDim.x - expand, minDim.y - expand, minDim.z - expand)
    maxDim = vector3(maxDim.x + expand, maxDim.y + expand, maxDim.z + expand)

    return {
        GetOffsetFromEntityInWorldCoords(entity, minDim.x, minDim.y, minDim.z),
        GetOffsetFromEntityInWorldCoords(entity, maxDim.x, minDim.y, minDim.z),
        GetOffsetFromEntityInWorldCoords(entity, maxDim.x, maxDim.y, minDim.z),
        GetOffsetFromEntityInWorldCoords(entity, minDim.x, maxDim.y, minDim.z),
        GetOffsetFromEntityInWorldCoords(entity, minDim.x, minDim.y, maxDim.z),
        GetOffsetFromEntityInWorldCoords(entity, maxDim.x, minDim.y, maxDim.z),
        GetOffsetFromEntityInWorldCoords(entity, maxDim.x, maxDim.y, maxDim.z),
        GetOffsetFromEntityInWorldCoords(entity, minDim.x, maxDim.y, maxDim.z),
    }
end

local function drawPartialLine(a, b, color, amount, alphaScale)
    amount = clamp(amount or 1.0, 0.0, 1.0)
    if amount <= 0.0 then
        return
    end

    local p = a + ((b - a) * amount)
    DrawLine(a.x, a.y, a.z, p.x, p.y, p.z, color.r, color.g, color.b, math.floor(color.a * (alphaScale or 1.0)))
end

local function drawEntityBoxProgress(entity, color, expand, progress)
    local corners = getEntityBoxCorners(entity, expand)
    local total = #BOX_EDGES
    local scaled = clamp(progress or 1.0, 0.0, 1.0) * total

    for i, edge in ipairs(BOX_EDGES) do
        local edgeProgress = clamp(scaled - (i - 1), 0.0, 1.0)
        drawPartialLine(corners[edge[1]], corners[edge[2]], color, edgeProgress)
    end
end

local function drawVehicleAxesProgress(entity, color, progress, alphaScale)
    local model = GetEntityModel(entity)
    local minDim, maxDim = getModelDimensionsCached(model)
    local z = (minDim.z + maxDim.z) * 0.5
    local a = alphaScale or 1.0

    local center = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, z)
    local front = GetOffsetFromEntityInWorldCoords(entity, 0.0, maxDim.y + 0.65, z)
    local back = GetOffsetFromEntityInWorldCoords(entity, 0.0, minDim.y - 0.65, z)
    local left = GetOffsetFromEntityInWorldCoords(entity, minDim.x - 0.45, 0.0, z)
    local right = GetOffsetFromEntityInWorldCoords(entity, maxDim.x + 0.45, 0.0, z)
    local top = GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, maxDim.z + 0.55)
    local noseL = GetOffsetFromEntityInWorldCoords(entity, -0.35, maxDim.y + 0.25, z)
    local noseR = GetOffsetFromEntityInWorldCoords(entity, 0.35, maxDim.y + 0.25, z)

    local scaled = clamp(progress or 1.0, 0.0, 1.0) * 5.0
    local white = { r = 255, g = 255, b = 255, a = color.a }

    drawPartialLine(back, front, color, clamp(scaled - 0.0, 0.0, 1.0), a)
    drawPartialLine(left, right, white, clamp(scaled - 1.0, 0.0, 1.0), a)
    drawPartialLine(center, top, color, clamp(scaled - 2.0, 0.0, 1.0), a)
    drawPartialLine(front, noseL, color, clamp(scaled - 3.0, 0.0, 1.0), a)
    drawPartialLine(front, noseR, color, clamp(scaled - 4.0, 0.0, 1.0), a)
end

local function drawVehicleRibsBuild(entity, color, progress, count)
    local model = GetEntityModel(entity)
    local minDim, maxDim = getModelDimensionsCached(model)
    count = count or 7

    local build = clamp(progress or 1.0, 0.0, 1.0)
    local maxZ = lerp(minDim.z + 0.10, maxDim.z + 0.35, build)

    for i = 0, count - 1 do
        local p = i / math.max(count - 1, 1)
        local y = lerp(minDim.y, maxDim.y, p)
        local z = lerp(minDim.z + 0.12, maxZ, 0.55 + math.sin((progress + p) * math.pi * 2.0) * 0.20)
        local left = GetOffsetFromEntityInWorldCoords(entity, minDim.x - 0.16, y, z)
        local right = GetOffsetFromEntityInWorldCoords(entity, maxDim.x + 0.16, y, z)
        local lineProgress = clamp((build * count) - i, 0.0, 1.0)

        drawPartialLine(left, right, color, lineProgress, 1.0 - math.abs(p - 0.5) * 0.45)
    end
end

local function drawVehicleProgressRing(entity, color, progress, segments)
    local model = GetEntityModel(entity)
    local minDim, maxDim = getModelDimensionsCached(model)
    segments = math.max(24, math.floor(segments or 160))
    local fill = clamp(progress or 0.0, 0.0, 1.0)
    local activeSegments = math.floor(segments * fill)
    local radiusX = math.max(math.abs(minDim.x), math.abs(maxDim.x)) + 0.85
    local radiusY = math.max(math.abs(minDim.y), math.abs(maxDim.y)) + 0.85
    local z = minDim.z + 0.08
    local labelAngle = -math.pi * 0.5 + (fill * math.pi * 2.0)
    local labelPos = GetOffsetFromEntityInWorldCoords(entity, math.cos(labelAngle) * radiusX * 1.08, math.sin(labelAngle) * radiusY * 1.08, z + 0.22)

    for i = 0, segments - 1 do
        local p0 = i / segments
        local p1 = (i + 1) / segments
        local a0 = -math.pi * 0.5 + (p0 * math.pi * 2.0)
        local a1 = -math.pi * 0.5 + (p1 * math.pi * 2.0)
        local isActive = i < activeSegments
        local alpha = isActive and color.a or math.floor(color.a * 0.16)
        local r = isActive and 1.0 or 0.96

        local from = GetOffsetFromEntityInWorldCoords(entity, math.cos(a0) * radiusX * r, math.sin(a0) * radiusY * r, z)
        local to = GetOffsetFromEntityInWorldCoords(entity, math.cos(a1) * radiusX * r, math.sin(a1) * radiusY * r, z)
        DrawLine(from.x, from.y, from.z, to.x, to.y, to.z, color.r, color.g, color.b, alpha)

        if isActive and i % 7 == 0 then
            local tick = GetOffsetFromEntityInWorldCoords(entity, math.cos(a1) * radiusX * 0.86, math.sin(a1) * radiusY * 0.86, z)
            DrawLine(to.x, to.y, to.z, tick.x, tick.y, tick.z, color.r, color.g, color.b, math.floor(alpha * 0.7))
        end
    end

    return labelPos
end

local function getVehicleBonePosition(entity, boneName)
    local model = GetEntityModel(entity)
    local modelCache = state.modelBoneIndexCache[model]
    if not modelCache then
        modelCache = {}
        state.modelBoneIndexCache[model] = modelCache
    end

    local boneIndex = modelCache[boneName]
    if boneIndex == nil then
        boneIndex = GetEntityBoneIndexByName(entity, boneName) or -1
        modelCache[boneName] = boneIndex
    end

    if boneIndex == -1 then
        return nil
    end

    return GetWorldPositionOfEntityBone(entity, boneIndex)
end

local function drawBoneLineProgress(entity, fromBone, toBone, color, progress, alphaScale)
    local a = getVehicleBonePosition(entity, fromBone)
    local b = getVehicleBonePosition(entity, toBone)
    if not a or not b then
        return false
    end

    drawPartialLine(a, b, color, progress, alphaScale)
    return true
end

local function drawBonePoint(entity, boneName, color, radius, intensity)
    local pos = getVehicleBonePosition(entity, boneName)
    if not pos then
        return false
    end

    DrawGlowSphere(pos.x, pos.y, pos.z, radius or 0.08, color.r, color.g, color.b, intensity or 0.15, false, false)
    return true
end

local function drawVehicleBoneRigProgress(entity, color, progress)
    local scaled = clamp(progress or 1.0, 0.0, 1.0) * #VEHICLE_BONE_LINES
    for i, line in ipairs(VEHICLE_BONE_LINES) do
        drawBoneLineProgress(entity, line[1], line[2], color, clamp(scaled - (i - 1), 0.0, 1.0), line[3])
    end

    if progress > 0.82 then
        local pulse = 0.08 + math.sin(progress * math.pi * 2.0) * 0.025
        drawBonePoint(entity, 'wheel_lf', color, pulse, 0.18)
        drawBonePoint(entity, 'wheel_rf', color, pulse, 0.18)
        drawBonePoint(entity, 'wheel_lr', color, pulse, 0.18)
        drawBonePoint(entity, 'wheel_rr', color, pulse, 0.18)
        drawBonePoint(entity, 'chassis_dummy', color, 0.12, 0.22)
        drawBonePoint(entity, 'bonnet', color, 0.08, 0.15)
        drawBonePoint(entity, 'boot', color, 0.08, 0.15)
    end
end


local function loadAudioFile()
    if state.audioBankLoaded then
        return true
    end

    if not RequestScriptAudioBank("audiodirectory/custom_sounds", false) then
        while not RequestScriptAudioBank("audiodirectory/custom_sounds", false) do
            Wait(0)
        end
    end

    state.audioBankLoaded = true
    return true
end

local function playsoundcar(soundName, soundSet)
    if not loadAudioFile() then return end

    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if vehicle ~= 0 then
        local soundId = GetSoundId()

        PlaySoundFromEntity(
            soundId,
            soundName or "signal-power-up",
            vehicle,
            soundSet or "special_soundset",
            0,
            0
        )

        CreateThread(function()
            while not HasSoundFinished(soundId) do
                Wait(100)
            end
            ReleaseSoundId(soundId)
        end)
    end
end


local function drawVehicleScanShape(object, sample)
    local vehicle = sample.attachedVehicle or getTargetVehicle(sample.pos, object.radius)
    if vehicle == 0 then
        return
    end

    local color = sample.color
    local buildProgress = object.build == false and 1.0 or clamp((sample.progress - (object.buildDelay or 0.0)) / (object.buildWindow or 0.72), 0.0, 1.0)
    setOutline(vehicle, object.outline ~= false, color)
    drawEntityBoxProgress(vehicle, color, object.boxExpand or 0.08, buildProgress)
    drawVehicleAxesProgress(vehicle, color, buildProgress, object.axisAlpha or 0.9)
    drawVehicleRibsBuild(vehicle, color, buildProgress, object.ribs or 8)
    if object.bones ~= false then
        drawVehicleBoneRigProgress(vehicle, color, buildProgress)
    end

    if object.percent ~= false then
        local labelPos
        if object.percentRing ~= false then
            labelPos = drawVehicleProgressRing(vehicle, color, buildProgress, object.progressRingSegments)
        else
            labelPos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, -2.35, 0.38)
        end

        local percent = math.floor(buildProgress * 100.0 + 0.5)
        drawWorldText(labelPos, ('%03d%%'):format(percent), color, object.percentScale or 0.32)
    end

    if object.scanMarker == true then
        local coords = GetEntityCoords(vehicle)
        local scanHeight = lerp(-0.4, 1.8, (math.sin(sample.progress * math.pi * 2.0) + 1.0) * 0.5)
        DrawMarker(
            object.markerType or 25,
            coords.x, coords.y, coords.z + scanHeight,
            0.0, 0.0, 0.0,
            0.0, 0.0, GetEntityHeading(vehicle),
            sample.size.x, sample.size.y, sample.size.z,
            color.r, color.g, color.b, math.floor(color.a * 0.75),
            false, false, 2, false, nil, nil, false
        )
    end
end

local function stopInstall()
    state.enabled = false
    state.elapsed = 0.0
    state.autoDisableAfter = Config.autoDisableAfter
    state.targetVehicle = 0
    state.activeProfile = nil
    state.activeProfileName = Config.defaultProfile or 'on'
    cleanupOutlines()
end

local function startInstall(vehicle, options)
    options = options or {}
    local profileConfig, profileName = getProfileConfig(options.profile)
    if not profileConfig then
        return false
    end

    if options.playSound ~= false and profileConfig.playSound ~= false then
        playsoundcar(profileConfig.soundName, profileConfig.soundSet)
    end

    if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
        state.targetVehicle = vehicle
    else
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        state.targetVehicle = findClosestVehicle(coords, options.radius or Config.defaultSearchRadius or 32.0)
    end

    if state.targetVehicle == 0 then
        return false
    end

    state.activeProfileName = profileName or Config.defaultProfile or 'on'
    state.activeProfile = profileConfig
    state.timeScale = options.timeScale or profileConfig.timeScale or Config.timeScale or 1.0
    state.autoDisableAfter = options.autoDisableAfter or profileConfig.autoDisableAfter or Config.autoDisableAfter
    state.elapsed = 0.0
    state.enabled = true

    for _, object in ipairs(getActiveObjects()) do
        sortedKeyframes(object)
    end

    return true
end

local function drawObject(object)
    if object.enabled == false then
        return
    end

    local sample = sampleObject(object)
    if not sample then
        return
    end

    sample = attachSampleToVehicle(object, sample)
    if not sample then
        return
    end

    if object.shape == 'box' then
        drawBoxShape(object, sample)
    elseif object.shape == 'line' then
        drawLineShape(object, sample)
    elseif object.shape == 'text3d' then
        drawText3DShape(object, sample)
    elseif object.shape == 'vehicleScan' then
        drawVehicleScanShape(object, sample)
    end
end

CreateThread(function()
    while true do
        if state.enabled then
            local dt = math.min(GetFrameTime(), 1.0 / 15.0)
            state.elapsed = state.elapsed + (dt * (state.timeScale or 1.0))
            clearTable(state.frameOutlined)

            for _, object in ipairs(getActiveObjects()) do
                drawObject(object)
            end

            cleanupUnusedOutlines()

            if state.autoDisableAfter and state.elapsed >= state.autoDisableAfter then
                stopInstall()
            end

            Wait(0)
        else
            cleanupOutlines()
            Wait(250)
        end
    end
end)

RegisterCommand('geoanim', function(_, args)
    local action = args[1] or 'toggle'

    if action == 'on' then
        if not startInstall(0, { profile = 'on' }) then
            notify('^1No nearby vehicle found for the animation.^7')
        end
    elseif action == 'shutdown' or action == 'offfx' then
        if not startInstall(0, { profile = 'off' }) then
            notify('^1No nearby vehicle found for the animation.^7')
        end
    elseif action == 'off' then
        stopInstall()
    elseif action == 'status' then
        notify(('running=%s profile=%s speed=%.2f'):format(tostring(state.enabled), tostring(state.activeProfileName or 'none'), state.timeScale or 1.0))
    else
        if state.enabled then
            stopInstall()
        else
            if not startInstall(0, { profile = 'on' }) then
                notify('^1No nearby vehicle found for the animation.^7')
            end
        end
    end
end, false)

RegisterNetEvent('l2k_geoanim:client:startInstall', function(vehicleNetId, options)
    local vehicle = vehicleNetId and NetToVeh(vehicleNetId) or 0
    startInstall(vehicle, options)
end)

RegisterNetEvent('l2k_geoanim:client:playProfile', function(profileName, vehicleNetId, options)
    local vehicle = vehicleNetId and NetToVeh(vehicleNetId) or 0
    options = options or {}
    options.profile = profileName
    startInstall(vehicle, options)
end)

RegisterNetEvent('l2k_geoanim:client:stopInstall', stopInstall)

--[[
===============================================================================
 EXPORTS
-----------------------------------------------------------------------------
 StartInstall(vehicle, options)
 StartGarageInstall(vehicle, options)
 PlayInstall(vehicle, options)
 StopInstall()
 IsInstallRunning()
===============================================================================
]]

exports('StartInstall', startInstall)
exports('StartGarageInstall', startInstall)
exports('PlayInstall', startInstall)
exports('PlayProfile', function(profileName, vehicle, options)
    options = options or {}
    options.profile = profileName
    return startInstall(vehicle, options)
end)
exports('PlayOn', function(vehicle, options)
    options = options or {}
    options.profile = 'on'
    return startInstall(vehicle, options)
end)
exports('PlayOff', function(vehicle, options)
    options = options or {}
    options.profile = 'off'
    return startInstall(vehicle, options)
end)
exports('StopInstall', stopInstall)
exports('StopExtraAnimations', stopInstall)
exports('IsInstallRunning', function()
    return state.enabled
end)

L2KGpsGeoAnim = {
    StartInstall = startInstall,
    StartGarageInstall = startInstall,
    PlayInstall = startInstall,
    PlayProfile = function(profileName, vehicle, options)
        options = options or {}
        options.profile = profileName
        return startInstall(vehicle, options)
    end,
    PlayOn = function(vehicle, options)
        options = options or {}
        options.profile = 'on'
        return startInstall(vehicle, options)
    end,
    PlayOff = function(vehicle, options)
        options = options or {}
        options.profile = 'off'
        return startInstall(vehicle, options)
    end,
    StopInstall = stopInstall,
    StopExtraAnimations = stopInstall,
    IsInstallRunning = function()
        return state.enabled
    end,
}

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        cleanupOutlines()
    end
end)
