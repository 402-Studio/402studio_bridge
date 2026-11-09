BridgeRegistry.register('notify', 'qbox', {
    notify = function(resource, message, kind, duration, title)
        local style = kind == 'warn' and 'warning' or kind == 'info' and 'inform' or kind
        exports[resource]:Notify(title or message, style, duration, title and message or nil)
        return true
    end,
})
