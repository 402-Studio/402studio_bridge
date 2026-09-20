BridgeRegistry.register('vehicle', 'qbox', {
    properties = function(vehicle, id, settings)
        if GetResourceState(settings.resource) ~= 'started' then return nil end
        local row = exports[settings.resource]:GetPlayerVehicle(id)
        if not row or not row.modelName or joaat(row.modelName) ~= GetEntityModel(vehicle) then return nil end
        return row.props and json.decode(json.encode(row.props)) or {}
    end,
    id = function(vehicle, settings)
        return Entity(vehicle).state[settings.stateKey]
    end,
    owner = function(vehicle, id, settings)
        if GetResourceState(settings.resource) ~= 'started' then return nil end
        local row = exports[settings.resource]:GetPlayerVehicle(id)
        if not row or not row[settings.ownerField] or not row.modelName
            or joaat(row.modelName) ~= GetEntityModel(vehicle) then return nil end
        return tostring(row[settings.ownerField])
    end,
})
