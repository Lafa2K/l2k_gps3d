local DebugConfig = {
    enabled = false,
    sampleDistances = { 8.0, 16.0, 24.0, 32.0 },
    probeZ = 1000.0,
    markerScale = 0.35,
    lineHeightOffset = 0.05,
}

local function drawDebugWorldText(x, y, z, text)
    local onScreen, screenX, screenY = GetScreenCoordFromWorldCoord(x, y, z)
    if not onScreen then
        return
    end

    SetTextScale(0.28, 0.28)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextOutline()
    SetTextCentre(true)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(screenX, screenY)
end

local function drawDebugPointMarker(pos, r, g, b, a)
    DrawMarker(
        28,
        pos.x, pos.y, pos.z,
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        DebugConfig.markerScale, DebugConfig.markerScale, DebugConfig.markerScale,
        r, g, b, a,
        false,
        false,
        2,
        false,
        nil,
        nil,
        false
    )
end

local function tryGetDebugGroundZ(x, y)
    if type(GetGroundZFor_3dCoord) ~= 'function' then
        return nil
    end

    local ok, z = GetGroundZFor_3dCoord(x, y, DebugConfig.probeZ, false)
    if ok and z then
        return z
    end

    return nil
end

local function tryGetDebugHeightTopZ(x, y)
    if type(GetHeightmapTopZForPosition) ~= 'function' then
        return nil
    end

    local z = GetHeightmapTopZForPosition(x, y)
    if z and z == z then
        return z
    end

    return nil
end

local function tryGetDebugHeightBottomZ(x, y)
    if type(GetHeightmapBottomZForPosition) ~= 'function' then
        return nil
    end

    local z = GetHeightmapBottomZForPosition(x, y)
    if z and z == z then
        return z
    end

    return nil
end

local function tryGetDebugClosestVehicleNode(x, y, z)
    if type(GetClosestVehicleNodeWithHeading) ~= 'function' then
        return nil, nil
    end

    local ok, outPos, heading = GetClosestVehicleNodeWithHeading(x, y, z, 1, 3.0, 0)
    if ok and outPos then
        return vector3(outPos.x, outPos.y, outPos.z), heading
    end

    return nil, nil
end

local function drawDebugSample(samplePos, distance)
    local groundZ = tryGetDebugGroundZ(samplePos.x, samplePos.y)
    local topZ = tryGetDebugHeightTopZ(samplePos.x, samplePos.y)
    local bottomZ = tryGetDebugHeightBottomZ(samplePos.x, samplePos.y)
    local nodePos, heading = tryGetDebugClosestVehicleNode(samplePos.x, samplePos.y, samplePos.z)

    local routePos = vector3(samplePos.x, samplePos.y, samplePos.z + DebugConfig.lineHeightOffset)
    drawDebugPointMarker(routePos, 255, 255, 0, 210) -- yellow = route/base sample

    if bottomZ and topZ then
        DrawLine(samplePos.x, samplePos.y, bottomZ, samplePos.x, samplePos.y, topZ, 255, 255, 255, 130)
    end

    if groundZ then
        local groundPos = vector3(samplePos.x, samplePos.y, groundZ + DebugConfig.lineHeightOffset)
        drawDebugPointMarker(groundPos, 0, 255, 0, 220) -- green = ground native
    end

    if topZ then
        local topPos = vector3(samplePos.x, samplePos.y, topZ + DebugConfig.lineHeightOffset)
        drawDebugPointMarker(topPos, 255, 0, 0, 220) -- red = heightmap top
    end

    if bottomZ then
        local bottomPos = vector3(samplePos.x, samplePos.y, bottomZ + DebugConfig.lineHeightOffset)
        drawDebugPointMarker(bottomPos, 0, 120, 255, 220) -- blue = heightmap bottom
    end

    if nodePos then
        drawDebugPointMarker(vector3(nodePos.x, nodePos.y, nodePos.z + DebugConfig.lineHeightOffset), 255, 140, 0, 220) -- orange = closest vehicle node
    end

    local textLines = {
        ('d=%.0f'):format(distance),
        ('route=%.2f'):format(samplePos.z),
    }

    if groundZ then
        textLines[#textLines + 1] = ('ground=%.2f'):format(groundZ)
    end
    if topZ then
        textLines[#textLines + 1] = ('top=%.2f'):format(topZ)
    end
    if bottomZ then
        textLines[#textLines + 1] = ('bottom=%.2f'):format(bottomZ)
    end
    if nodePos then
        textLines[#textLines + 1] = ('node=%.2f'):format(nodePos.z)
    end
    if heading then
        textLines[#textLines + 1] = ('hdg=%.1f'):format(heading)
    end

    drawDebugWorldText(samplePos.x, samplePos.y, samplePos.z + 1.2, table.concat(textLines, ' | '))
end

CreateThread(function()
    while true do
        local waitTime = 500

        if DebugConfig.enabled then
            local ped = PlayerPedId()
            if ped and ped ~= 0 and IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle and vehicle ~= 0 then
                    waitTime = 0
                    local vehiclePos = GetEntityCoords(vehicle)
                    local forward = GetEntityForwardVector(vehicle)

                    for i = 1, #DebugConfig.sampleDistances do
                        local distance = DebugConfig.sampleDistances[i]
                        local samplePos = vector3(
                            vehiclePos.x + (forward.x * distance),
                            vehiclePos.y + (forward.y * distance),
                            vehiclePos.z + (forward.z * distance)
                        )
                        drawDebugSample(samplePos, distance)
                    end
                end
            end
        end

        Wait(waitTime)
    end
end)

RegisterCommand('gps3ddebug', function()
    DebugConfig.enabled = not DebugConfig.enabled

    local message = DebugConfig.enabled and '^2Z debug enabled.^7' or '^1Z debug disabled.^7'
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 255 },
        multiline = false,
        args = { 'l2k_gps3d', message }
    })
end, false)
