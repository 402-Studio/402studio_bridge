BridgeApiVersion = 1
BridgeRegistry = BridgeRegistry or {
    framework = {},
    inventory = {},
    vehicle = {},
    notify = {},
    progress = {},
    target = {},
}

local contracts = {
    framework = {'connect', 'player', 'data', 'group', 'balance', 'remove', 'add'},
    inventory = {'count', 'remove', 'add'},
    vehicle = {'id', 'owner', 'properties'},
    notify = {'notify'},
    progress = {'start', 'cancel', 'active'},
    target = {'addVehicle', 'removeVehicle'},
}

function BridgeRegistry.register(kind, name, adapter)
    if type(contracts[kind]) ~= 'table' then error(('unknown adapter kind: %s'):format(tostring(kind))) end
    if type(name) ~= 'string' or name == '' then error('adapter name must be a non-empty string') end
    if type(adapter) ~= 'table' then error(('%s adapter %s must be a table'):format(kind, name)) end
    for _, method in ipairs(contracts[kind]) do
        if type(adapter[method]) ~= 'function' then
            error(('%s adapter %s missing method: %s'):format(kind, name, method))
        end
    end
    BridgeRegistry[kind][name] = adapter
    return adapter
end

function BridgeRegistry.get(kind, name)
    local adapters = BridgeRegistry[kind]
    return type(adapters) == 'table' and adapters[name] or nil
end

function BridgeRegistry.status(kind, name)
    if type(contracts[kind]) ~= 'table' then return false, 'unknown_adapter_kind' end
    if type(name) ~= 'string' or name == '' then return false, 'invalid_adapter' end
    local adapter = BridgeRegistry.get(kind, name)
    if type(adapter) ~= 'table' then return false, 'missing_adapter' end
    for _, method in ipairs(contracts[kind]) do
        if type(adapter[method]) ~= 'function' then return false, 'missing_method:' .. method end
    end
    return true
end

function BridgeRegistry.allowed(resource)
    if type(resource) ~= 'string' or resource == '' then return false end
    if Config.AllowedResources[resource] == true then return true end
    local firstParty = Config.FirstParty
    if type(firstParty) ~= 'table' or type(firstParty.prefix) ~= 'string'
        or type(firstParty.author) ~= 'string' then return false end
    return resource:sub(1, #firstParty.prefix) == firstParty.prefix
        and GetResourceMetadata(resource, 'author', 0) == firstParty.author
end
