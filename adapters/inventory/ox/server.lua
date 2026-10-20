BridgeRegistry.register('inventory', 'ox', {
    count = function(resource, source, item)
        return exports[resource]:GetItemCount(source, item) or 0
    end,
    remove = function(resource, source, item, count)
        return exports[resource]:RemoveItem(source, item, count) == true
    end,
    add = function(resource, source, item, count)
        return exports[resource]:AddItem(source, item, count) == true
    end,
    canCarry = function(resource, source, item, count)
        return exports[resource]:CanCarryItem(source, item, count) == true
    end,
    drop = function(resource, source, item, count)
        local ped = GetPlayerPed(source)
        if ped == 0 or not DoesEntityExist(ped) then return false end
        return exports[resource]:CustomDrop(item, { { item, count } },
            GetEntityCoords(ped), nil, nil, Player(source).state.instance)
    end,
})
