BridgeRegistry.register('progress', 'ox', {
    start = function(settings)
        if type(lib) ~= 'table' or type(lib.progressBar) ~= 'function' then return nil end
        return lib.progressBar({
            duration = settings.duration,
            label = settings.label,
            canCancel = settings.canCancel ~= false,
            useWhileDead = settings.useWhileDead == true,
            position = settings.position,
            disable = settings.disable,
        })
    end,
    cancel = function()
        if type(lib) == 'table' and type(lib.cancelProgress) == 'function' then lib.cancelProgress() end
    end,
    active = function()
        return type(lib) == 'table' and type(lib.progressActive) == 'function' and lib.progressActive() == true
    end,
})
