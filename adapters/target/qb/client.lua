local modelLabels = {}

AddEventHandler('onResourceStop', function(resource)
    modelLabels[resource] = nil
end)

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
    addModel = function(models, options, resource)
        if GetResourceState(resource) ~= 'started' then return false end
        local built, distance, namesByLabel, labelsByName = {}, 0, {}, {}
        for index, option in ipairs(options) do
            if namesByLabel[option.label] then return false end
            namesByLabel[option.label], labelsByName[option.name] = option.name, option.label
            built[index] = {
                label = option.label,
                icon = option.icon,
                distance = option.distance,
                canInteract = option.canInteract,
                action = function(entity) option.onSelect(entity) end,
            }
            distance = math.max(distance, option.distance or 2.0)
        end
        local current = modelLabels[resource] or {}
        for _, model in ipairs(models) do
            for name, label in pairs(current[model] or {}) do
                if (namesByLabel[label] and namesByLabel[label] ~= name)
                    or (labelsByName[name] and labelsByName[name] ~= label) then return false end
            end
        end
        if exports[resource]:AddTargetModel(models, { options = built, distance = distance }) == false then return false end
        modelLabels[resource] = current
        for _, model in ipairs(models) do
            local labels = modelLabels[resource][model] or {}
            for _, option in ipairs(options) do labels[option.name] = option.label end
            modelLabels[resource][model] = labels
        end
        return true
    end,
    removeModel = function(models, names, resource)
        if GetResourceState(resource) ~= 'started' then return false end
        for _, model in ipairs(models) do
            local labels = modelLabels[resource] and modelLabels[resource][model]
            if labels then
                local removed = {}
                for _, name in ipairs(names) do
                    if labels[name] then removed[#removed + 1] = labels[name] end
                end
                if #removed > 0 and exports[resource]:RemoveTargetModel(model, removed) == false then return false end
                for _, name in ipairs(names) do labels[name] = nil end
                if not next(labels) then modelLabels[resource][model] = nil end
            end
        end
        return true
    end,
})
