BridgeRegistry.register('inventoryUse', 'ox', {
    use = function(resource, data, callback)
        exports[resource]:useItem(data, callback)
        return true
    end,
})
