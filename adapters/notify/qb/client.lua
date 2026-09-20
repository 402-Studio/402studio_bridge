BridgeRegistry.register('notify', 'qb', {
    notify = function(resource, message, kind, duration)
        local core = exports[resource]:GetCoreObject()
        core.Functions.Notify(message, kind == 'info' and 'primary' or kind, duration)
        return true
    end,
})
