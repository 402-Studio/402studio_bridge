local runs, serial = {}, 0

local function caller()
    local resource = GetInvokingResource() or GetCurrentResourceName()
    if resource ~= GetCurrentResourceName() and not BridgeRegistry.allowed(resource) then return nil end
    return resource
end

exports('StartCallback', function(name, delay, ...)
    local owner = caller()
    if not owner then return nil, 'forbidden_resource' end
    if type(name) ~= 'string' or name == '' then return nil, 'invalid_callback' end
    if delay ~= nil and delay ~= false and (type(delay) ~= 'number' or delay < 0) then return nil, 'invalid_delay' end
    if type(lib) ~= 'table' or type(lib.callback) ~= 'table' or type(lib.callback.await) ~= 'function' then
        return nil, 'callback_unavailable'
    end
    local args = table.pack(...)
    serial = serial + 1
    local id = serial
    runs[id] = { owner = owner, done = false }
    CreateThread(function()
        if not runs[id] then return end
        local values = table.pack(pcall(lib.callback.await, name, delay, table.unpack(args, 1, args.n)))
        local run = runs[id]
        if not run then return end
        run.done = true
        if not values[1] then run.error = values[2]; return end
        run.values = { n = values.n - 1 }
        for index = 2, values.n do run.values[index - 1] = values[index] end
    end)
    return id
end)

exports('CallbackResult', function(id)
    local owner = caller()
    if not owner then return true, nil, 'forbidden_resource' end
    local run = runs[id]
    if not run or run.owner ~= owner then return true, nil, 'invalid_callback_handle' end
    if not run.done then return false end
    runs[id] = nil
    return true, run.values, run.error
end)

AddEventHandler('onResourceStop', function(resource)
    for id, run in pairs(runs) do
        if run.owner == resource or resource == GetCurrentResourceName() then runs[id] = nil end
    end
end)
