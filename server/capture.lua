local function selected(kind)
    local settings = Config.Capture
    if type(settings) ~= 'table' or type(settings.resource) ~= 'string' then return nil end
    local adapter = BridgeRegistry.get('capture', settings.adapter)
    if not adapter or not adapter.available(kind, settings.resource) then return nil end
    return adapter, settings.resource
end

local function allowed()
    local owner = GetInvokingResource()
    return owner and BridgeRegistry.allowed(owner)
end

exports('IsCaptureAvailable', function(kind)
    if not allowed() then return false, 'forbidden_resource' end
    if kind ~= 'snapshot' and kind ~= 'video' then return false, 'invalid_capture_kind' end
    return selected(kind) ~= nil
end)

local function upload(kind, source, url, options, callback, mode)
    if not allowed() then error('forbidden_resource') end
    if type(source) ~= 'number' or source < 1 or source % 1 ~= 0 then error('invalid_player') end
    if type(url) ~= 'string' or url == '' or type(options) ~= 'table' or not BridgeRegistry.callable(callback) then
        error('invalid_capture_options')
    end
    local adapter, resource = selected(kind)
    if not adapter then error('capture_unavailable') end
    return adapter[kind](resource, source, url, options, callback, mode)
end

exports('CaptureSnapshotUpload', function(source, url, options, callback, mode)
    return upload('snapshot', source, url, options, callback, mode)
end)

exports('StartVideoCaptureUpload', function(source, url, options, callback)
    return upload('video', source, url, options, callback)
end)
