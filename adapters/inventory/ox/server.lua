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
})
