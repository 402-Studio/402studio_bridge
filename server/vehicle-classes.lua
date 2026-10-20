BridgeVehicleClasses = {}

local classes = {}
local requested = true
local active
local sequence = 0
local nextRequest = 0
local playerIndex = 0

local function hash(value)
    if type(value) == 'string' and value ~= '' then value = GetHashKey(value) end
    if type(value) ~= 'number' or value % 1 ~= 0 or value < -2147483648 or value > 4294967295 then return nil end
    return value % 4294967296
end

local function parse(response)
    if type(response) ~= 'table' then return nil end
    local parsed = {}
    local count = 0
    for model, class in pairs(response) do
        count = count + 1
        if count > 32768 or type(model) ~= 'number' then return nil end
        local key = hash(model)
        if not key or type(class) ~= 'number' or class % 1 ~= 0 or class < 0 or class > 22 then return nil end
        if parsed[key] ~= nil and parsed[key] ~= class then return nil end
        parsed[key] = class
    end
    return count > 0 and parsed or nil
end

function BridgeVehicleClasses.get(model)
    local key = hash(model)
    if not key then return nil end
    local class = classes[key]
    if class == nil then requested = true end
    return class
end

AddEventHandler('playerJoining', function()
    requested = true
end)

CreateThread(function()
    while true do
        local now = GetGameTimer()
        if active and now >= active.deadline then
            active = nil
            requested = true
        end
        if requested and not active and now >= nextRequest then
            local players = GetPlayers()
            if #players > 0 then
                playerIndex = playerIndex % #players + 1
                local player = tonumber(players[playerIndex])
                if player then
                    sequence = sequence + 1
                    local current = sequence
                    active = { sequence = current, deadline = now + 10000 }
                    requested = false
                    nextRequest = now + 15000
                    local ok = pcall(lib.callback, '402studio_bridge:vehicleClasses', player, function(response)
                        if not active or active.sequence ~= current then return end
                        if GetGameTimer() >= active.deadline then
                            active = nil
                            requested = true
                            return
                        end
                        active = nil
                        local parsed = parse(response)
                        if parsed then classes = parsed else requested = true end
                    end)
                    if not ok then
                        active = nil
                        requested = true
                    end
                end
            end
        end
        Wait(1000)
    end
end)
