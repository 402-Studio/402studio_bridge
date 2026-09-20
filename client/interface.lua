BridgeInterface = {}

local blank = {progress = 'standalone', target = 'none'}

function BridgeInterface.custom()
    local custom = Config.CustomFramework
    return type(custom) == 'table' and custom.enabled == true and custom or nil
end

function BridgeInterface.framework()
    if BridgeInterface.custom() then return 'custom' end
    if Config.Framework ~= 'auto' then return Config.Framework end
    for _, name in ipairs(Config.Priority) do
        local resource = Config.Resources[name]
        if resource and GetResourceState(resource) == 'started' then return name end
    end
    return 'standalone'
end

local function pick(kind)
    local value = Config[kind:sub(1, 1):upper() .. kind:sub(2)]
    if type(value) ~= 'table' then return nil end
    local resources = type(value.resources) == 'table' and value.resources or {}
    if value.adapter ~= 'auto' then return value.adapter, value.resource or resources[value.adapter] end
    for _, name in ipairs(value.priority or {}) do
        local resource = resources[name]
        if type(resource) == 'string' and GetResourceState(resource) == 'started' then return name, resource end
    end
    return blank[kind], nil
end

local function resolveNotify()
    local custom = BridgeInterface.custom()
    local selected = BridgeInterface.framework()
    if selected == 'custom' then
        if type(custom.notify) == 'function' then
            return {notify = custom.notify}, 'custom', custom.resource, false
        end
        return BridgeRegistry.get('notify', 'standalone'), 'standalone', nil, true
    end
    local name = Config.Notify.adapter == 'auto' and selected or Config.Notify.adapter
    return BridgeRegistry.get('notify', name), name, Config.Notify.resource or Config.Resources[selected], false
end

function BridgeInterface.resolve(kind)
    if kind == 'notify' then return resolveNotify() end
    local name, resource = pick(kind)
    if not name then return nil end
    return BridgeRegistry.get(kind, name), name, resource, false, name ~= blank[kind]
end

function BridgeInterface.status(kind)
    local adapter, name, resource, fallback = BridgeInterface.resolve(kind)
    local ready = adapter ~= nil
    if ready and type(resource) == 'string' and resource ~= '' then
        ready = GetResourceState(resource) == 'started'
    end
    local status = {adapter = name, resource = resource, ready = ready}
    if kind == 'notify' then status.fallback = fallback end
    return status
end

function BridgeInterface.available(kind)
    local adapter, _, resource, _, present = BridgeInterface.resolve(kind)
    if not adapter or not present then return false end
    return not resource or GetResourceState(resource) == 'started'
end
