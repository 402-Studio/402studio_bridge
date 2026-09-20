BridgeRegistry.register('progress', 'standalone', {
    start = function() return nil end,
    cancel = function() end,
    active = function() return false end,
})
