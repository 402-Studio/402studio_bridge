BridgeRegistry.register('context', 'ox', {
    register = function(context, resource)
        exports[resource]:registerContext(context)
        return true
    end,
    show = function(id, resource)
        exports[resource]:showContext(id)
        return true
    end,
    hide = function(onExit, resource)
        exports[resource]:hideContext(onExit)
        return true
    end,
    getOpen = function(resource)
        return exports[resource]:getOpenContextMenu()
    end,
})
