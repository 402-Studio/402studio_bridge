local framework, core, adapter
local connected = false
local frameworkError
local locks = {}

local function customFramework()
    local custom = Config.CustomFramework
    return type(custom) == 'table' and custom.enabled == true and custom or nil
end

local function frameworkResource(name)
    local custom = customFramework()
    if name == 'custom' and custom then return custom.resource end
    return Config.Resources[name]
end

local function frameworkAdapter(name)
    if name == 'custom' then
        local custom = customFramework()
        if not custom then return nil, 'custom_disabled' end
        if type(custom.resource) ~= 'string' or custom.resource == '' then return nil, 'custom_resource_missing' end
        if type(custom.getCore) ~= 'function' then return nil, 'custom_getCore_missing' end
        if type(custom.getPlayer) ~= 'function' then return nil, 'custom_getPlayer_missing' end
        return {
            connect = function(resource) return custom.getCore(resource) end,
            player = function(value, source) return custom.getPlayer(value, source) end,
            data = function(player) return player end,
            group = function(value, player, source, groups)
                if type(custom.hasGroup) ~= 'function' then return false end
                return custom.hasGroup(value, source, groups, player) == true
            end,
            balance = function(value, _, source, account)
                if type(custom.getBalance) ~= 'function' then return 0 end
                return custom.getBalance(value, source, account)
            end,
            remove = function(value, _, source, account, amount, reason)
                if type(custom.removeMoney) ~= 'function' then return false end
                return custom.removeMoney(value, source, account, amount, reason) == true
            end,
            add = function(value, _, source, account, amount, reason)
                if type(custom.addMoney) ~= 'function' then return false end
                return custom.addMoney(value, source, account, amount, reason) == true
            end,
        }
    end
    return BridgeRegistry.get('framework', name)
end

local function adapterStatus(value)
    if type(value) ~= 'table' then return false, 'missing_adapter' end
    for _, method in ipairs({'connect', 'player', 'data', 'group', 'balance', 'remove', 'add'}) do
        if type(value[method]) ~= 'function' then return false, 'missing_method:' .. method end
    end
    return true
end

local function refresh()
    framework = customFramework() and 'custom' or Config.Framework
    if framework == 'auto' then
        framework = 'standalone'
        for _, name in ipairs(Config.Priority) do
            local resource = frameworkResource(name)
            if type(resource) == 'string' and resource ~= '' and GetResourceState(resource) == 'started' then
                framework = name
                break
            end
        end
    end
    adapter, frameworkError = frameworkAdapter(framework)
    core, connected = nil, false
    local valid, validationError = adapterStatus(adapter)
    if not valid then frameworkError = frameworkError or validationError; return end
    local resource = frameworkResource(framework)
    if type(resource) == 'string' and resource ~= '' and GetResourceState(resource) ~= 'started' then
        frameworkError = 'resource_not_started:' .. resource
        return
    end
    local ok, value = pcall(adapter.connect, resource)
    if not ok then frameworkError = framework == 'custom' and 'custom_getCore_failed' or 'connect_failed'; return end
    if not value then frameworkError = framework == 'custom' and 'custom_getCore_returned_nil' or 'connect_failed'; return end
    core, connected, frameworkError = value, true, nil
end

local function validPlayer(src)
    return type(src) == 'number' and src > 0 and src % 1 == 0 and GetPlayerName(src) ~= nil
end

local function player(src)
    if not connected then return nil, 'unavailable' end
    if not validPlayer(src) then return nil, 'invalid_player' end
    local ok, value = pcall(adapter.player, core, src)
    if not ok then return nil, framework == 'custom' and 'custom_getPlayer_failed' or 'provider_error' end
    if not value then return nil, framework == 'custom' and 'custom_getPlayer_returned_nil' or 'player_not_ready' end
    return value
end

local function account(name)
    local custom = customFramework()
    if framework == 'custom' and type(custom.accounts) == 'table' then
        return custom.accounts[name]
    end
    local map = type(name) == 'string' and Config.Accounts[name]
    return map and map[framework]
end

local function customEconomyReady()
    local custom = customFramework()
    if framework ~= 'custom' then return framework ~= 'standalone' end
    return type(custom.accounts) == 'table' and next(custom.accounts) ~= nil
        and type(custom.getBalance) == 'function'
        and type(custom.removeMoney) == 'function'
        and type(custom.addMoney) == 'function'
end

local function amountValid(amount)
    return type(amount) == 'number' and amount == amount and amount > 0
        and amount % 1 == 0 and amount <= Config.MaximumTransaction
end

local function balance(p, src, name)
    local value = adapter.balance(core, p, src, name)
    if type(value) ~= 'number' or value ~= value or value < 0 or value == math.huge then
        error('invalid_balance')
    end
    return math.floor(value)
end

local function permission(src, rule)
    if not validPlayer(src) or type(rule) ~= 'table' then return false end
    if rule.mode == 'all' then return connected end
    if rule.mode == 'ace' then
        return type(rule.ace) == 'string' and IsPlayerAceAllowed(src, rule.ace) == true
    end
    if rule.mode == 'admin' then
        if type(rule.ace) == 'string' and IsPlayerAceAllowed(src, rule.ace) then return true end
        local groups = rule.groups or {}
        if type(groups) ~= 'table' then return false end
        for group, enabled in pairs(groups) do
            if enabled == true and type(group) == 'string' and IsPlayerAceAllowed(src, 'group.' .. group) then return true end
        end
        local p = player(src)
        return p ~= nil and adapter.group(core, p, src, groups) == true
    end
    if rule.mode == 'job' then
        local p = player(src)
        if not p then return false end
        local job = adapter.data(p).job
        local required = job and type(rule.jobs) == 'table' and rule.jobs[job.name]
        return job ~= nil and (required == true or (type(required) == 'number' and job.grade >= required))
            and (not rule.onDuty or job.onDuty == true)
    end
    return false
end

local api = {}

function api.GetStatus()
    local frameworkReady, validationError = adapterStatus(adapter)
    local statusError = frameworkError or validationError
    local inventory = BridgeInventory.status()
    local vehicle = BridgeVehicles.status()
    local custom = customFramework()
    local economyReady = connected and customEconomyReady()
    local permissionsReady = framework ~= 'standalone'
    if framework == 'custom' then permissionsReady = type(custom.hasGroup) == 'function' end
    return {
        apiVersion = BridgeApiVersion,
        framework = framework,
        ready = connected,
        economy = economyReady,
        modules = {
            framework = {
                adapter = framework,
                resource = frameworkResource(framework),
                ready = connected and frameworkReady,
                error = connected and nil or statusError,
                permissions = permissionsReady,
                economy = economyReady,
            },
            inventory = inventory,
            vehicle = vehicle,
        },
    }
end

function api.GetPlayer(src)
    local p, err = player(src)
    if not p then return nil, err end
    local data = adapter.data(p)
    if type(data.identifier) ~= 'string' or data.identifier == '' then
        return nil, framework == 'custom' and 'custom_getPlayer_invalid_identifier' or 'player_not_ready'
    end
    return {source=src, identifier=data.identifier, name=data.name, job=data.job}
end

function api.HasPermission(src, rule)
    return permission(src, rule)
end

function api.GetVehicleId(vehicle)
    return BridgeVehicles.id(vehicle)
end

function api.GetVehicleProperties(vehicle)
    return BridgeVehicles.properties(vehicle)
end

function api.GetVehicleOwner(src, vehicle)
    if not validPlayer(src) then return nil end
    return BridgeVehicles.owner(vehicle)
end

function api.GetItemCount(src, name)
    if not validPlayer(src) or type(name) ~= 'string' then return 0 end
    return BridgeInventory.call('count', src, name) or 0
end

function api.RemoveItem(src, name, count)
    count = count or 1
    if not validPlayer(src) or type(name) ~= 'string' or name == '' or not amountValid(count) then return false end
    return BridgeInventory.call('remove', src, name, count)
end

function api.AddItem(src, name, count)
    count = count or 1
    if not validPlayer(src) or type(name) ~= 'string' or name == '' or not amountValid(count) then return false end
    return BridgeInventory.call('add', src, name, count)
end

function api.GetBalance(src, generic)
    local p, err = player(src)
    if not p then return nil, err end
    local name = account(generic)
    if not name then return nil, 'unsupported_account' end
    return balance(p, src, name)
end

local function transaction(src, action)
    if not validPlayer(src) then return false, 'invalid_player' end
    if locks[src] then return false, 'busy' end
    locks[src] = true
    local ok, result, err = pcall(action)
    locks[src] = nil
    if not ok then return false, 'provider_error' end
    return result, err
end

function api.Charge(src, amount, accounts, reason)
    if not amountValid(amount) then return false, 'invalid_amount' end
    if type(accounts) ~= 'table' or #accounts == 0 or #accounts > 8 then return false, 'invalid_accounts' end
    return transaction(src, function()
        local p, err = player(src)
        if not p then return false, err end
        local plan, seen, left = {}, {}, amount
        for _, generic in ipairs(accounts) do
            local name = account(generic)
            if not name or seen[name] then return false, 'invalid_accounts' end
            seen[name] = true
            local take = math.min(balance(p, src, name), left)
            if take > 0 then plan[#plan+1] = {name=name,amount=take}; left=left-take end
        end
        if left > 0 then return false, 'insufficient_funds' end
        local paid = {}
        for _, entry in ipairs(plan) do
            local ok, result = pcall(adapter.remove, core, p, src, entry.name, entry.amount, reason)
            if not ok or result ~= true then
                local restored = true
                for i=#paid,1,-1 do
                    local debit = paid[i]
                    local success, refunded = pcall(adapter.add, core, p, src, debit.name, debit.amount, reason .. ':refund')
                    if not success or refunded ~= true then restored = false end
                end
                if not restored then
                    print(('[402studio_bridge] Refund failed for player %s, caller %s'):format(src, reason))
                    return false, 'refund_failed'
                end
                return false, 'debit_failed'
            end
            paid[#paid+1] = entry
        end
        return true
    end)
end

function api.AddMoney(src, amount, generic, reason)
    if not amountValid(amount) then return false, 'invalid_amount' end
    return transaction(src, function()
        local p, err = player(src)
        if not p then return false, err end
        local name = account(generic)
        if not name then return false, 'unsupported_account' end
        if adapter.add(core, p, src, name, amount, reason) ~= true then return false, 'credit_failed' end
        return true
    end)
end

for name, method in pairs(api) do
    exports(name, function(...)
        local caller = GetInvokingResource()
        if not caller or not BridgeRegistry.allowed(caller) then return nil, 'forbidden_resource' end
        local args = table.pack(...)
        if name == 'Charge' or name == 'AddMoney' then
            args[4] = caller .. ':' .. tostring(args[4] or name):sub(1,80)
            args.n = 4
        end
        local ok, result, err = pcall(method, table.unpack(args,1,args.n))
        if not ok then return nil, 'provider_error' end
        return result, err
    end)
end

AddEventHandler('onResourceStart', function(resource)
    for _, name in pairs(Config.Resources) do if resource == name then refresh(); return end end
    local custom = customFramework()
    if custom and resource == custom.resource then refresh() end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == frameworkResource(framework) then core, connected = nil, false end
end)

refresh()

local status = api.GetStatus()
print(('[402studio_bridge] framework=%s ready=%s permissions=%s economy=%s inventory=%s vehicle=%s api=%s'):format(
    status.framework,
    tostring(status.ready),
    tostring(status.modules.framework.permissions),
    tostring(status.economy),
    status.modules.inventory.adapter,
    status.modules.vehicle.adapter,
    status.apiVersion
))
if status.modules.framework.error then
    print(('[402studio_bridge] framework error: %s'):format(status.modules.framework.error))
end
