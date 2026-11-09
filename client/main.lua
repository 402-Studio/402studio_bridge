local runs, serial = {}, 0

local function progressOwner()
    return GetInvokingResource() or GetCurrentResourceName()
end

local function allowed()
    local caller = GetInvokingResource()
    return not caller or BridgeRegistry.allowed(caller)
end

exports('UseItem', function(data, callback)
    if not allowed() then return false, 'forbidden_resource' end
    if type(data) ~= 'table' or type(data.slot) ~= 'number' or data.slot % 1 ~= 0
        or data.slot < 1 or data.slot > 10000 or not BridgeRegistry.callable(callback) then
        return false, 'invalid_item'
    end
    local name, resource = BridgeRegistry.resolveInventory()
    local adapter = BridgeRegistry.get('inventoryUse', name)
    if not adapter or type(resource) ~= 'string' or resource == ''
        or GetResourceState(resource) ~= 'started' then return false, 'inventory_unavailable' end
    local called = false
    local ok, result = pcall(adapter.use, resource, data, function(used)
        if called then return end
        called = true
        callback(used == true or type(used) == 'table')
    end)
    if not ok then return false, 'provider_error' end
    return result == true
end)

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

local modelTargets = {}

local function modelList(models)
    if type(models) == 'string' or type(models) == 'number' then models = { models } end
    if type(models) ~= 'table' or #models == 0 then return end
    local result, seen = {}, {}
    for _, model in ipairs(models) do
        if type(model) == 'string' and model ~= '' then model = GetHashKey(model) end
        if type(model) ~= 'number' or model ~= model or model % 1 ~= 0
            or model < -2147483648 or model > 4294967295 then return end
        if not seen[model] then result[#result + 1], seen[model] = model, true end
    end
    return result
end

exports('AddModelTarget', function(models, options)
    if not allowed() then return false end
    models = modelList(models)
    if not models or type(options) ~= 'table' or #options == 0 then return false end
    local seen = {}
    for _, option in ipairs(options) do
        if type(option) ~= 'table' or type(option.name) ~= 'string' or option.name == '' or seen[option.name]
            or type(option.label) ~= 'string' or option.label == ''
            or not BridgeRegistry.callable(option.onSelect)
            or (option.canInteract ~= nil and not BridgeRegistry.callable(option.canInteract)) then return false end
        local distance = option.distance
        if distance ~= nil and (type(distance) ~= 'number' or distance ~= distance
            or distance <= 0 or distance == math.huge) then return false end
        seen[option.name] = true
    end
    if not BridgeInterface.available('target') then return false end
    local adapter, _, resource = BridgeInterface.resolve('target')
    if type(adapter.addModel) ~= 'function' or type(adapter.removeModel) ~= 'function' then return false end
    local owner = progressOwner()
    local built = {}
    for index, option in ipairs(options) do
        local copy = {}
        for key, value in pairs(option) do copy[key] = value end
        copy.name = owner .. ':' .. option.name
        built[index] = copy
    end
    local ok, result = pcall(adapter.addModel, models, built, resource)
    if not ok or result ~= true then return false end
    modelTargets[owner] = modelTargets[owner] or {}
    for _, model in ipairs(models) do
        local entries = modelTargets[owner][model] or {}
        for index, option in ipairs(options) do
            entries[option.name] = { name = built[index].name, adapter = adapter, resource = resource }
        end
        modelTargets[owner][model] = entries
    end
    return true
end)

exports('RemoveModelTarget', function(models, names)
    if not allowed() then return false end
    models = modelList(models)
    if type(names) == 'string' then names = { names } end
    if not models or type(names) ~= 'table' or #names == 0 then return false end
    for _, name in ipairs(names) do if type(name) ~= 'string' or name == '' then return false end end
    local owned = modelTargets[progressOwner()]
    if not owned then return true end
    local success = true
    for _, model in ipairs(models) do
        local entries = owned[model]
        if entries then
            for _, name in ipairs(names) do
                local entry = entries[name]
                if entry then
                    local ok, result = pcall(entry.adapter.removeModel, { model }, { entry.name }, entry.resource)
                    if ok and result == true then entries[name] = nil else success = false end
                end
            end
            if not next(entries) then owned[model] = nil end
        end
    end
    return success
end)

AddEventHandler('onResourceStop', function(resource)
    for owner, models in pairs(modelTargets) do
        for model, entries in pairs(models) do
            for name, entry in pairs(entries) do
                if resource == owner or resource == entry.resource or resource == GetCurrentResourceName() then
                    if resource ~= entry.resource then
                        pcall(entry.adapter.removeModel, { model }, { entry.name }, entry.resource)
                    end
                    entries[name] = nil
                end
            end
            if not next(entries) then models[model] = nil end
        end
        if not next(models) then modelTargets[owner] = nil end
    end
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
