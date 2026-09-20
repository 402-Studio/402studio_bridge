local running = false

BridgeRegistry.register('progress', 'qb', {
    start = function(settings, resource)
        if GetResourceState(resource) ~= 'started' then return nil end
        local finished, cancelled = false, false
        running = true
        exports[resource]:Progress({
            name = 'bridge_progress',
            duration = settings.duration,
            label = settings.label,
            useWhileDead = settings.useWhileDead == true,
            canCancel = settings.canCancel ~= false,
            controlDisables = settings.disable or {},
        }, function(wasCancelled)
            finished, cancelled = true, wasCancelled == true
        end)
        while not finished do Wait(0) end
        running = false
        return not cancelled
    end,
    cancel = function(_, resource)
        if GetResourceState(resource) == 'started' then TriggerEvent('progressbar:client:cancel') end
    end,
    active = function()
        return running
    end,
})
