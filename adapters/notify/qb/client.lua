BridgeRegistry.register('notify', 'qb', {
    notify = function(resource, message, kind, duration, title)
        local core = exports[resource]:GetCoreObject()
        local style = kind == 'info' and 'primary' or kind == 'warn' and 'warning' or kind
        local content = title and { text = title, caption = message } or message
        core.Functions.Notify(content, style, duration)
        return true
    end,
})
