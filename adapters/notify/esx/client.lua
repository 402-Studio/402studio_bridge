BridgeRegistry.register('notify', 'esx', {
    notify = function(resource, message, kind, duration, title)
        local core = exports[resource]:getSharedObject()
        core.ShowNotification(message, kind, duration, title)
        return true
    end,
})
