local callbacks, registered = {}, {}

exports('RegisterCallback', function(name, callback)
    local owner = GetInvokingResource()
    if not owner or not BridgeRegistry.allowed(owner) then return false, 'forbidden_resource' end
    if type(name) ~= 'string' or name == '' or not BridgeRegistry.callable(callback) then return false, 'invalid_callback' end
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.register) ~= 'function' then
        return false, 'callback_unavailable'
    end
    if callbacks[name] and callbacks[name].owner ~= owner then return false, 'callback_in_use' end
    callbacks[name] = { owner = owner, callback = callback }
    if not registered[name] then
        lib.callback.register(name, function(...)
            local current = callbacks[name]
            if not current then return nil end
            return current.callback(...)
        end)
        registered[name] = true
    elseif type(lib.setValidCallback) == 'function' then
        lib.setValidCallback(name, true)
    end
    return true
end)

AddEventHandler('onResourceStop', function(resource)
    for name, entry in pairs(callbacks) do
        if entry.owner == resource then
            callbacks[name] = nil
            if type(lib.setValidCallback) == 'function' then lib.setValidCallback(name, false) end
        end
    end
end)
