BridgeRegistry.register('target', 'qb', {
    addVehicle = function(options, resource)
        if GetResourceState(resource) ~= 'started' then return false end
        local built, distance = {}, nil
        for index, option in ipairs(options) do
            built[index] = {
                label = option.label,
                icon = option.icon,
                canInteract = option.canInteract,
                action = function(entity) option.onSelect(entity) end,
            }
            distance = math.max(distance or 0, option.distance or 2.0)
        end
        exports[resource]:AddGlobalVehicle({options = built, distance = distance or 2.0})
        return true
    end,
    removeVehicle = function(names, resource)
        if GetResourceState(resource) ~= 'started' then return false end
        for _, name in ipairs(names) do exports[resource]:RemoveGlobalVehicle(name) end
        return true
    end,
})
