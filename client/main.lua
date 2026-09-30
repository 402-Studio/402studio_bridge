local runs, serial = {}, 0

local function progressOwner()
    return GetInvokingResource() or GetCurrentResourceName()
end

local function allowed()
    local caller = GetInvokingResource()
    return not caller or BridgeRegistry.allowed(caller)
end

exports('Notify', function(message, kind, duration, title)
    if not allowed() then return false, 'forbidden_resource' end
    if type(message) ~= 'string' or message == '' then return false, 'invalid_message' end
    local adapter, _, resource = BridgeInterface.resolve('notify')
    if type(adapter) ~= 'table' or type(adapter.notify) ~= 'function' then return false, 'notify_unavailable' end
    local ok, result = pcall(adapter.notify, resource, message, kind or 'info', tonumber(duration) or 5000, title)
    if not ok then return false, 'provider_error' end
    return result == true
end)

exports('StartProgress', function(value)
    if not allowed() or type(value) ~= 'table' or type(value.duration) ~= 'number' or value.duration <= 0 then
        return nil
    end
    if not BridgeInterface.available('progress') then return nil end
    for _, run in pairs(runs) do if not run.done then return nil end end
    local adapter, _, resource = BridgeInterface.resolve('progress')
    serial = serial + 1
    local id = serial
    runs[id] = {done = false, cancelled = false, owner = progressOwner(), adapter = adapter, resource = resource}
    CreateThread(function()
        if not runs[id] then return end
        local ok, result = pcall(adapter.start, value, resource)
        local run = runs[id]
        if not run then return end
        run.done, run.cancelled = true, not ok or result ~= true
    end)
    return id
end)

exports('ProgressResult', function(id)
    local run = runs[id]
    if not allowed() or not run or run.owner ~= progressOwner() then return true, true end
    if not run.done then return false, false end
    runs[id] = nil
    return true, run.cancelled == true
end)

exports('CancelProgress', function(id)
    if not allowed() then return false end
    local run = runs[id]
    if not run or run.done or run.owner ~= progressOwner() then return false end
    local ok = pcall(run.adapter.cancel, id, run.resource)
    runs[id] = nil
    return ok
end)

exports('ProgressActive', function()
    local adapter, _, resource = BridgeInterface.resolve('progress')
    for _, run in pairs(runs) do
        if not run.done then adapter, resource = run.adapter, run.resource; break end
    end
    if not adapter then return false end
    local ok, result = pcall(adapter.active, resource)
    return ok and result == true
end)

AddEventHandler('onResourceStop', function(resource)
    for id, run in pairs(runs) do
        if run.owner == resource or run.resource == resource or resource == GetCurrentResourceName() then
            if not run.done and run.resource ~= resource then pcall(run.adapter.cancel, id, run.resource) end
            runs[id] = nil
        end
    end
end)

exports('AddVehicleTarget', function(options)
    if not allowed() or type(options) ~= 'table' or #options == 0 then return false end
    for _, option in ipairs(options) do
        if type(option.name) ~= 'string' or type(option.label) ~= 'string'
            or not BridgeRegistry.callable(option.onSelect) then return false end
    end
    if not BridgeInterface.available('target') then return false end
    local adapter, _, resource = BridgeInterface.resolve('target')
    local ok, result = pcall(adapter.addVehicle, options, resource)
    return ok and result == true
end)

exports('RemoveVehicleTarget', function(names)
    if not allowed() then return false end
    if type(names) == 'string' then names = {names} end
    if type(names) ~= 'table' then return false end
    local adapter, _, resource = BridgeInterface.resolve('target')
    if not adapter then return false end
    local ok, result = pcall(adapter.removeVehicle, names, resource)
    return ok and result == true
end)

exports('TargetAvailable', function()
    return BridgeInterface.available('target')
end)

exports('GetStatus', function()
    return {
        apiVersion = BridgeApiVersion,
        framework = BridgeInterface.framework(),
        modules = {
            notify = BridgeInterface.status('notify'),
            progress = BridgeInterface.status('progress'),
            target = BridgeInterface.status('target'),
            textUI = BridgeInterface.status('textUI'),
            context = BridgeInterface.status('context'),
        },
    }
end)
