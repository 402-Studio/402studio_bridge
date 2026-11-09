local root = arg[1] or '.'
local count = 0

local function test(name, verify)
    verify()
    count = count + 1
    print('PASS ' .. name)
end

local function runtime(resource, provider, configure)
    local services, handlers, states, permissions = {}, {}, {}, {}
    local providers = {}
    if resource then
        providers[resource] = provider
        states[resource] = 'started'
    end
    local env = setmetatable({
        GetConvar = function(_, fallback) return fallback end,
        GetResourceState = function(name) return states[name] or 'missing' end,
        GetPlayerName = function(source) return source == 7 and 'Player' or nil end,
        GetPlayerIdentifierByType = function(source, kind)
            if source == 7 and kind == 'license' then return 'license:test' end
        end,
        GetResourceMetadata = function() return '402-Studio' end,
        GetInvokingResource = function() return '402studio_dyno' end,
        IsPlayerAceAllowed = function(source, name) return source == 7 and permissions[name] == true end,
        AddEventHandler = function(name, handler) handlers[name] = handler end,
        BridgeInventory = { status = function() return { adapter = 'none' } end },
        BridgeVehicles = { status = function() return { adapter = 'none' } end },
        print = function() end,
        exports = setmetatable(providers, {
            __call = function(_, name, callback) services[name] = callback end,
        }),
    }, { __index = _G })
    local function load(path) assert(loadfile(root .. '/' .. path, 't', env))() end
    load('config.lua')
    if configure then configure(env.Config) end
    load('shared/registry.lua')
    for _, name in ipairs({ 'esx', 'qb', 'qbox', 'standalone' }) do
        load('adapters/framework/' .. name .. '/server.lua')
    end
    load('server/main.lua')
    return services, permissions, states, handlers, env, load
end

local function checkPlayer(services, framework, identifier)
    local status = services.GetStatus()
    assert(status.ready and status.framework == framework)
    local player = services.GetPlayer(7)
    assert(player.identifier == identifier and player.source == 7)
    assert(services.HasPermission(7, { mode = 'all' }) == true)
    return player
end

local function checkJob(services)
    local rule = { mode = 'job', jobs = { mechanic = 2 }, onDuty = true }
    assert(services.HasPermission(7, rule) == true)
    rule.jobs.mechanic = 3
    assert(services.HasPermission(7, rule) == false)
end

local function qbPlayer()
    return {
        PlayerData = {
            citizenid = 'char:driver',
            charinfo = { firstname = 'Test', lastname = 'Driver' },
            job = { name = 'mechanic', grade = { level = 2 }, onduty = true },
            money = { cash = 10, bank = 90 },
        },
    }
end

local function mutate(accounts, account, amount)
    local balance = accounts[account]
    if not balance or balance + amount < 0 then return false end
    accounts[account] = balance + amount
    return true
end

test('ESX Legacy uses guarded charge when available and checks older void mutations', function()
    local accounts = { money = { money = 10 }, bank = { money = 90 } }
    local calls = 0
    local player = {
        identifier = 'char1:license',
        job = { name = 'mechanic', grade = '2', onDuty = true },
        getName = function() return 'ESX Driver' end,
        getGroup = function() return 'admin' end,
        getAccount = function(account) return accounts[account] end,
        removeAccountMoney = function(account, amount)
            accounts[account].money = accounts[account].money - amount
        end,
        addAccountMoney = function(account, amount)
            accounts[account].money = accounts[account].money + amount
        end,
    }
    player.chargeAccount = function(account, amount)
        calls = calls + 1
        assert(account == 'money' and amount == 5)
        return false, 'session_closing'
    end
    local provider = { getSharedObject = function()
        return { GetPlayerFromId = function() return player end }
    end }
    local services = runtime('es_extended', provider)
    local identity = checkPlayer(services, 'esx', 'char1:license')
    assert(identity.name == 'ESX Driver' and identity.job.grade == 2)
    checkJob(services)
    assert(services.HasPermission(7, { mode = 'admin', groups = { admin = true } }))
    assert(not services.Charge(7, 5, { 'cash' }))
    assert(calls == 1 and services.GetBalance(7, 'cash') == 10)
    player.chargeAccount = nil
    assert(services.Charge(7, 25, { 'cash', 'bank' }))
    assert(services.GetBalance(7, 'cash') == 0 and services.GetBalance(7, 'bank') == 75)
    assert(services.AddMoney(7, 5, 'cash') and services.GetBalance(7, 'cash') == 5)
end)

test('QBCore identity, duty, permission, split payment and credit', function()
    local player = qbPlayer()
    local accounts = player.PlayerData.money
    player.Functions = {
        RemoveMoney = function(account, amount) return mutate(accounts, account, -amount) end,
        AddMoney = function(account, amount) return mutate(accounts, account, amount) end,
    }
    local provider = { GetCoreObject = function()
        return { Functions = {
            GetPlayer = function() return player end,
            HasPermission = function(source, group) return source == 7 and group == 'admin' end,
        } }
    end }
    local services = runtime('qb-core', provider)
    checkPlayer(services, 'qb', 'char:driver')
    checkJob(services)
    player.PlayerData.job.onduty = false
    assert(not services.HasPermission(7, { mode = 'job', jobs = { mechanic = 2 }, onDuty = true }))
    assert(services.HasPermission(7, { mode = 'admin', groups = { admin = true } }))
    assert(services.Charge(7, 25, { 'cash', 'bank' }))
    assert(accounts.cash == 0 and accounts.bank == 75)
    assert(services.AddMoney(7, 5, 'cash') and accounts.cash == 5)
    accounts.bank = -100
    assert(services.GetBalance(7, 'bank') == 0)
    assert(services.Charge(7, 5, { 'cash', 'bank' }) and accounts.cash == 0 and accounts.bank == -100)
    assert(not services.Charge(7, 1, { 'cash', 'bank' }) and accounts.bank == -100)
    accounts.bank = -math.huge
    local balance, reason = services.GetBalance(7, 'bank')
    assert(balance == nil and reason == 'provider_error')
end)

test('Qbox bound functions use the selected character when source and user IDs differ', function()
    local player = qbPlayer()
    local accounts, other = player.PlayerData.money, { cash = 999, bank = 999 }
    local rawCalls = 0
    player.Functions = {
        GetMoney = function(account) return accounts[account] end,
        RemoveMoney = setmetatable({}, {
            __call = function(_, account, amount) return mutate(accounts, account, -amount) end,
        }),
        AddMoney = function(account, amount) return mutate(accounts, account, amount) end,
    }
    local provider = {
        GetPlayer = function(_, source) assert(source == 7); return player end,
        GetMoney = function(_, _, account) rawCalls = rawCalls + 1; return other[account] end,
        RemoveMoney = function(_, _, account, amount)
            rawCalls = rawCalls + 1
            return mutate(other, account, -amount)
        end,
        AddMoney = function(_, _, account, amount)
            rawCalls = rawCalls + 1
            return mutate(other, account, amount)
        end,
    }
    local services, permissions = runtime('qbx_core', provider)
    checkPlayer(services, 'qbox', 'char:driver')
    checkJob(services)
    local admin = { mode = 'admin', groups = { admin = true } }
    assert(not services.HasPermission(7, admin))
    permissions.admin = true
    assert(services.HasPermission(7, admin))
    assert(services.Charge(7, 25, { 'cash', 'bank' }))
    assert(services.AddMoney(7, 5, 'cash'))
    assert(accounts.cash == 5 and accounts.bank == 75 and rawCalls == 0)
    assert(other.cash == 999 and other.bank == 999)
end)

test('Qbox export-only providers skip missing accounts and reconnect on restart', function()
    local player = qbPlayer()
    local accounts = { bank = 90 }
    local provider = {
        GetPlayer = function() return player end,
        GetMoney = function(_, source, account) assert(source == 7); return accounts[account] end,
        RemoveMoney = function(_, source, account, amount)
            assert(source == 7)
            return mutate(accounts, account, -amount)
        end,
        AddMoney = function(_, source, account, amount)
            assert(source == 7)
            return mutate(accounts, account, amount)
        end,
    }
    local services, _, states, handlers = runtime('qbx_core', provider)
    checkPlayer(services, 'qbox', 'char:driver')
    assert(services.GetBalance(7, 'cash') == 0)
    assert(services.Charge(7, 25, { 'cash', 'bank' }) and accounts.bank == 65)
    assert(services.AddMoney(7, 5, 'bank') and accounts.bank == 70)
    states.qbx_core = 'stopped'
    handlers.onResourceStop('qbx_core')
    assert(not services.GetStatus().ready and not services.Charge(7, 5, { 'bank' }))
    states.qbx_core = 'started'
    handlers.onResourceStart('qbx_core')
    assert(services.GetStatus().ready and services.GetBalance(7, 'bank') == 70)
end)

test('standalone uses the license and ACE without exposing jobs or payment', function()
    local services, permissions = runtime()
    checkPlayer(services, 'standalone', 'license:test')
    permissions['402studio_dyno.admin'] = true
    assert(services.HasPermission(7, { mode = 'ace', ace = '402studio_dyno.admin' }))
    assert(not services.HasPermission(7, { mode = 'job', jobs = { mechanic = true } }))
    assert(not services.GetStatus().economy and not services.Charge(7, 5, { 'cash' }))
end)

test('custom framework uses normalized data and configured account names', function()
    local accounts = { wallet = 25 }
    local services = runtime('custom_framework', {}, function(config)
        config.CustomFramework = {
            enabled = true,
            resource = 'custom_framework',
            accounts = { cash = 'wallet' },
            getCore = function() return {} end,
            getPlayer = function()
                return { identifier = 'custom:driver', job = { name = 'mechanic', grade = 2, onDuty = true } }
            end,
            hasGroup = function(_, _, groups) return groups.admin == true end,
            getBalance = function(_, _, account) return accounts[account] end,
            removeMoney = function(_, _, account, amount) return mutate(accounts, account, -amount) end,
            addMoney = function(_, _, account, amount) return mutate(accounts, account, amount) end,
        }
    end)
    checkPlayer(services, 'custom', 'custom:driver')
    checkJob(services)
    assert(services.HasPermission(7, { mode = 'admin', groups = { admin = true } }))
    assert(services.GetStatus().economy and services.Charge(7, 5, { 'cash' }))
    assert(services.AddMoney(7, 2, 'cash') and accounts.wallet == 22)
end)

test('stock Qbox notifications receive the title and body with native severity', function()
    local args
    local provider = { Notify = function(_, ...) args = table.pack(...) end }
    local _, _, _, _, env, load = runtime('qbx_core', provider)
    load('adapters/notify/qbox/client.lua')
    local notify = env.BridgeRegistry.get('notify', 'qbox').notify
    assert(notify('qbx_core', 'Refund issued', 'info', 5000, 'Dyno'))
    assert(args[1] == 'Dyno' and args[2] == 'inform' and args[3] == 5000 and args[4] == 'Refund issued')
    assert(notify('qbx_core', 'Run aborted', 'warn', 5000))
    assert(args[1] == 'Run aborted' and args[2] == 'warning' and args[4] == nil)
end)

test('stock QBCore notifications receive their caption and warning style', function()
    local args
    local provider = { GetCoreObject = function()
        return { Functions = { Notify = function(...) args = table.pack(...) end } }
    end }
    local _, _, _, _, env, load = runtime('qb-core', provider)
    load('adapters/notify/qb/client.lua')
    local notify = env.BridgeRegistry.get('notify', 'qb').notify
    assert(notify('qb-core', 'Run aborted', 'warn', 5000, 'Dyno'))
    assert(args[1].text == 'Dyno' and args[1].caption == 'Run aborted' and args[2] == 'warning' and args[3] == 5000)
end)

test('ESX notifications report an absent provider and accept older void results', function()
    local result = false
    local provider = { getSharedObject = function()
        return { ShowNotification = function() return result end }
    end }
    local _, _, _, _, env, load = runtime('es_extended', provider)
    load('adapters/notify/esx/client.lua')
    local notify = env.BridgeRegistry.get('notify', 'esx').notify
    assert(not notify('es_extended', 'Refund issued', 'info', 5000, 'Dyno'))
    result = nil
    assert(notify('es_extended', 'Refund issued', 'info', 5000, 'Dyno'))
end)

print(('Passed %d framework checks'):format(count))
