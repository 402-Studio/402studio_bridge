BridgeRegistry.register('notify', 'esx', {
    notify = function(resource, message, kind, duration, title)
        local core = exports[resource]:getSharedObject()
        return core.ShowNotification(message, kind, duration, title) ~= false
    end,
})
