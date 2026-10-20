exports('IsCaptureAvailable', function(kind)
    local owner = GetInvokingResource()
    if owner and not BridgeRegistry.allowed(owner) then return false, 'forbidden_resource' end
    if kind ~= 'snapshot' and kind ~= 'video' then return false, 'invalid_capture_kind' end
    local settings = Config.Capture
    return type(settings) == 'table' and type(settings.resource) == 'string'
        and GetResourceState(settings.resource) == 'started'
end)
