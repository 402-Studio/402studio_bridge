BridgeRegistry.register('target', 'ox', {
    addVehicle = function(options, resource)
        if GetResourceState(resource) ~= 'started' then return false end
        local built = {}
        for index, option in ipairs(options) do
            built[index] = {
                name = option.name,
                label = option.label,
                icon = option.icon,
                distance = option.distance,
                bones = option.bones,
                canInteract = option.canInteract,
                onSelect = function(data) option.onSelect(data.entity) end,
            }
        end
        exports[resource]:addGlobalVehicle(built)
        return true
    end,
    removeVehicle = function(names, resource)
        if GetResourceState(resource) ~= 'started' then return false end
        exports[resource]:removeGlobalVehicle(names)
        return true
    end,
})
