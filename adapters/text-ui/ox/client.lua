BridgeRegistry.register('textUI', 'ox', {
    show = function(text, options, resource)
        exports[resource]:showTextUI(text, options)
        return true
    end,
    hide = function(resource)
        exports[resource]:hideTextUI()
        return true
    end,
    isOpen = function(resource)
        return exports[resource]:isTextUIOpen()
    end,
})
