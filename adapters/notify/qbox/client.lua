BridgeRegistry.register('notify', 'qbox', {
    notify = function(resource, message, kind, duration, title)
        local content = title and {title = title, description = message} or message
        exports[resource]:Notify(content, kind == 'warn' and 'warning' or kind, duration)
        return true
    end,
})
