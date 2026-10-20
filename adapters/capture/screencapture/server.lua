local methods = { snapshot = 'remoteUpload', video = 'startVideoCaptureUpload' }

BridgeRegistry.register('capture', 'screencapture', {
    available = function(kind, resource)
        if GetResourceState(resource) ~= 'started' or not methods[kind] then return false end
        local ok, method = pcall(function() return exports[resource][methods[kind]] end)
        return ok and BridgeRegistry.callable(method)
    end,
    snapshot = function(resource, source, url, options, callback, mode)
        return exports[resource]:remoteUpload(source, url, options, callback, mode or 'blob')
    end,
    video = function(resource, source, url, options, callback)
        return exports[resource]:startVideoCaptureUpload(source, url, options, callback)
    end,
})
