BridgeVehicles = {}

local function adapter()
    return BridgeRegistry.get('vehicle', Config.Vehicles.adapter)
end

function BridgeVehicles.status()
    local selected = adapter()
    local resource = Config.Vehicles.resource
    return {
        adapter = Config.Vehicles.adapter,
        resource = resource,
        ready = selected ~= nil and (not resource or resource == '' or GetResourceState(resource) == 'started'),
    }
end

function BridgeVehicles.id(vehicle)
    if type(vehicle) ~= 'number' or not DoesEntityExist(vehicle) or GetEntityType(vehicle) ~= 2 then return nil end
    local selected = adapter()
    if not selected then return nil end
    local id = selected.id(vehicle, Config.Vehicles)
    if type(id) ~= 'number' or id < 1 or id % 1 ~= 0 or id == math.huge then return nil end
    return id
end

function BridgeVehicles.owner(vehicle)
    local id = BridgeVehicles.id(vehicle)
    if not id then return nil end
    local selected = adapter()
    local owner = selected.owner(vehicle, id, Config.Vehicles)
    if type(owner) ~= 'string' or owner == '' then return nil end
    return owner
end

function BridgeVehicles.properties(vehicle)
    local id = BridgeVehicles.id(vehicle)
    if not id then return nil end
    return adapter().properties(vehicle, id, Config.Vehicles)
end
