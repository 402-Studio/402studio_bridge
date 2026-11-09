local root = arg[1] or '.'
local total = 0

local function runtime(options)
    options = options or {}
    local result = { calls = {}, exported = {}, events = {}, owner = '402studio_dyno' }
    local env = setmetatable({}, { __index = _G })
    env.Config = {
        Inventory = { adapter = 'ox', resource = 'test_inventory' },
        AllowedResources = {},
        FirstParty = { prefix = '402studio_', author = '402-Studio' },
        Framework = 'standalone',
        Resources = {},
        Accounts = {},
        MaximumTransaction = 10000000,
    }
    env.GetResourceState = function() return options.stopped and 'stopped' or 'started' end
    env.GetResourceMetadata = function() return options.author or '402-Studio' end
    env.GetInvokingResource = function() return result.owner end
    env.GetCurrentResourceName = function() return '402studio_bridge' end
    env.GetPlayerName = function(src) return src == 1 and 'Test player' or nil end
    env.AddEventHandler = function(name, handler)
        result.events[name] = result.events[name] or {}
        table.insert(result.events[name], handler)
    end
    env.SetTimeout = function(_, callback) callback() end
    env.print = function() end
    env.BridgeVehicles = { status = function() return { adapter = 'none' } end }
    env.GetPlayerPed = function(src) return options.missingPed and 0 or src + 100 end
    env.DoesEntityExist = function() return true end
    env.GetEntityCoords = function(ped) return { x = ped, y = 2, z = 3 } end
    env.Player = function() return { state = { instance = 7 } } end
    local inventory = {}
    for _, name in ipairs({ 'GetItemCount', 'RemoveItem', 'AddItem', 'CanCarryItem', 'CustomDrop', 'GetSlot' }) do
        inventory[name] = function(_, ...)
            result.calls[#result.calls + 1] = { name = name, args = table.pack(...) }
            if name == 'GetItemCount' then return 2 end
            if name == 'GetSlot' then return options.slot end
            if name == 'CustomDrop' then
                if options.dropFails then return false end
                return 'drop-1'
            end
            return not options.full
        end
    end
    env.exports = setmetatable({ test_inventory = inventory }, {
        __call = function(_, name, callback) result.exported[name] = callback end,
    })
    assert(loadfile(root .. '/shared/registry.lua', 't', env))()
    assert(loadfile(root .. '/adapters/inventory/ox/server.lua', 't', env))()
    assert(loadfile(root .. '/server/inventory.lua', 't', env))()
    result.env = env
    result.inventory = env.BridgeInventory
    function result.load(file) assert(loadfile(root .. '/' .. file, 't', env))() end
    function result.emit(name, ...) for _, handler in ipairs(result.events[name] or {}) do handler(...) end end
    return result
end

local function test(name, fn)
    fn()
    total = total + 1
    print('PASS ' .. name)
end

test('inventory count and mutations use configured provider', function()
    local mock = runtime()
    assert(mock.inventory.call('count', 1, 'gapcam') == 2)
    assert(mock.inventory.call('remove', 1, 'gapcam', 1) == true)
    assert(mock.inventory.call('add', 1, 'gapcam', 1) == true)
    assert(mock.calls[2].args[1] == 1 and mock.calls[2].args[2] == 'gapcam' and mock.calls[2].args[3] == 1)
end)

test('carry checks preserve full inventory rejection', function()
    assert(runtime().inventory.call('canCarry', 1, 'gapcam', 1) == true)
    assert(runtime({ full = true }).inventory.call('canCarry', 1, 'gapcam', 1) == false)
end)

test('metadata and slot reads use configured provider', function()
    local metadata = { dynoReport = { ps = 300 } }
    local slot = { name = 'dyno_report', count = 1, metadata = metadata }
    local mock = runtime({ slot = slot })
    assert(mock.inventory.call('add', 1, 'dyno_report', 1, metadata) == true)
    assert(mock.calls[1].args[4] == metadata)
    assert(mock.inventory.call('canCarry', 1, 'dyno_report', 1, metadata) == true)
    assert(mock.calls[2].args[4] == metadata)
    assert(mock.inventory.call('getSlot', 1, 4) == slot)
    assert(mock.calls[3].args[1] == 1 and mock.calls[3].args[2] == 4)
    local status = mock.inventory.status()
    assert(status.ready and status.metadata and status.slots and status.usable)
end)

test('metadata is rejected by adapters without support', function()
    local mock = runtime()
    mock.env.BridgeRegistry.inventory.ox.metadata = nil
    local value, reason = mock.inventory.call('add', 1, 'dyno_report', 1, {})
    assert(value == nil and reason == 'inventory_metadata_unavailable')
    assert(#mock.calls == 0 and not mock.inventory.status().metadata)
    assert(mock.inventory.call('add', 1, 'gapcam', 1) == true)
end)

test('unknown inventories stay unavailable across framework choices', function()
    for _, name in ipairs({ 'qb', 'qs', 'esx', 'custom', 'standalone' }) do
        local mock = runtime()
        mock.env.Config.Inventory.adapter = name
        local status = mock.inventory.status()
        assert(not status.ready and status.error == 'inventory_unavailable')
        assert(not status.metadata and not status.slots and not status.usable)
        local value, reason = mock.inventory.call('add', 1, 'dyno_report', 1, {})
        assert(value == nil and reason == 'inventory_unavailable' and #mock.calls == 0)
    end
end)

test('drop refund keeps item count position and instance', function()
    local mock = runtime()
    assert(mock.inventory.call('drop', 1, 'gapcam', 1) == 'drop-1')
    local call = mock.calls[1]
    assert(call.name == 'CustomDrop')
    assert(call.args[2][1][1] == 'gapcam' and call.args[2][1][2] == 1)
    assert(call.args[3].x == 101 and call.args[6] == 7)
end)

test('drop failures and absent player ped preserve failure', function()
    assert(runtime({ dropFails = true }).inventory.call('drop', 1, 'gapcam', 1) == false)
    local mock = runtime({ missingPed = true })
    assert(mock.inventory.call('drop', 1, 'gapcam', 1) == false)
    assert(#mock.calls == 0)
end)

test('stopped inventory rejects calls before provider access', function()
    local mock = runtime({ stopped = true })
    local value, reason = mock.inventory.call('canCarry', 1, 'gapcam', 1)
    assert(value == nil and reason == 'inventory_unavailable')
    assert(#mock.calls == 0)
end)

test('optional actions fail safely on older adapters', function()
    local mock = runtime()
    mock.env.BridgeRegistry.inventory.ox.canCarry = nil
    local value, reason = mock.inventory.call('canCarry', 1, 'gapcam', 1)
    assert(value == nil and reason == 'inventory_action_unavailable')
end)

test('GapCam prefix case is accepted with matching author', function()
    local registry = runtime().env.BridgeRegistry
    assert(registry.allowed('402Studio_gapcam') == true)
    assert(registry.allowed('402studio_plateflipper') == true)
    assert(registry.allowed('other_gapcam') == false)
    assert(runtime({ author = 'other' }).env.BridgeRegistry.allowed('402Studio_gapcam') == false)
end)

test('server inventory exports retain metadata and validate caller player and slot', function()
    local metadata = { dynoReport = { ps = 300 } }
    local slot = { name = 'dyno_report', count = 1, metadata = metadata }
    local mock = runtime({ slot = slot })
    mock.load('adapters/framework/standalone/server.lua')
    mock.load('server/main.lua')
    assert(mock.exported.AddItem(1, 'dyno_report', 1, metadata))
    assert(mock.calls[1].args[4] == metadata)
    assert(mock.exported.CanCarryItem(1, 'dyno_report', 1, metadata))
    assert(mock.calls[2].args[4] == metadata)
    assert(mock.exported.GetInventoryItem(1, 5) == slot and mock.calls[3].args[2] == 5)
    local count = #mock.calls
    assert(mock.exported.AddItem(1, 'dyno_report', 1, 'forged') == false)
    assert(mock.exported.GetInventoryItem(2, 1) == nil)
    for _, invalid in ipairs({ 0, -1, 1.5, math.huge, '1', {} }) do
        assert(mock.exported.GetInventoryItem(1, invalid) == nil)
    end
    mock.owner = 'untrusted'
    local item, reason = mock.exported.GetInventoryItem(1, 1)
    assert(item == nil and reason == 'forbidden_resource' and #mock.calls == count)
end)

local function client(options)
    options = options or {}
    local mock = runtime(options)
    mock.env.exports.test_inventory.useItem = function(_, data, callback)
        if options.fail then error('provider failure') end
        mock.calls[#mock.calls + 1] = { name = 'useItem', data = data }
        callback(options.result)
        callback(true)
    end
    mock.load('adapters/inventory/ox/client.lua')
    mock.load('client/main.lua')
    return mock
end

test('client item use keeps provider result and only calls once', function()
    for _, result in ipairs({ false, true, { name = 'dyno_report' } }) do
        local mock, called, used = client({ result = result }), 0, nil
        local data = { slot = 3 }
        assert(mock.exported.UseItem(data, function(value) called = called + 1; used = value end))
        assert(called == 1 and used == (result ~= false))
        assert(#mock.calls == 1 and mock.calls[1].data == data)
    end
end)

test('client item use rejects invalid callers slots stopped and missing adapters', function()
    local mock = client()
    local callback = function() error('callback must stay unused') end
    for _, slot in ipairs({ 0, -1, 1.5, math.huge, '1', {} }) do
        assert(mock.exported.UseItem({ slot = slot }, callback) == false)
    end
    mock.owner = 'untrusted'
    local used, reason = mock.exported.UseItem({ slot = 1 }, callback)
    assert(not used and reason == 'forbidden_resource' and #mock.calls == 0)
    mock = client({ stopped = true })
    used, reason = mock.exported.UseItem({ slot = 1 }, callback)
    assert(not used and reason == 'inventory_unavailable' and #mock.calls == 0)
    mock = client()
    mock.env.Config.Inventory.adapter = 'custom'
    used, reason = mock.exported.UseItem({ slot = 1 }, callback)
    assert(not used and reason == 'inventory_unavailable' and #mock.calls == 0)
    mock = client({ fail = true })
    used, reason = mock.exported.UseItem({ slot = 1 }, callback)
    assert(not used and reason == 'provider_error' and #mock.calls == 0)
end)

local function qbRuntime()
    local mock = runtime()
    mock.states = { test_core = true, test_qb = true }
    mock.env.GetResourceState = function(name) return mock.states[name] and 'started' or 'missing' end
    mock.env.Config.Resources.qb = 'test_core'
    mock.env.Config.Inventory = {
        adapter = 'auto',
        resources = { ox = 'test_inventory', qb = 'test_qb' },
        priority = { 'ox', 'qb' },
    }
    mock.items, mock.usables = {}, {}
    mock.env.exports.test_qb = {
        GetItemCount = function(_, _, name) return name == 'dyno_report' and 2 or nil end,
        RemoveItem = function(_, source, name, count, slot, reason)
            return source == 1 and name == 'dyno_report' and count == 1 and slot == false and reason == '402studio_bridge'
        end,
        AddItem = function(_, source, name, count, slot, info, reason)
            assert(source == 1 and name == 'dyno_report' and count == 1 and slot == false and reason == '402studio_bridge')
            if mock.full then return false end
            mock.items[3] = { name = name, amount = count, info = info, slot = 3 }
            return true
        end,
        GetItemBySlot = function(_, source, slot) return source == 1 and mock.items[slot] or nil end,
        CanAddItem = function(_, _, _, _) return not mock.full end,
    }
    mock.env.exports.test_core = {
        CanUseItem = function(_, name) return mock.usables[name] end,
        CreateUseableItem = function(_, name, handler)
            mock.usables[name] = { resource = '402studio_bridge', func = handler }
        end,
    }
    mock.load('adapters/inventory/qb/server.lua')
    return mock
end

test('QB adapter translates inventory capacity, slot data and metadata', function()
    local mock = qbRuntime()
    local status = mock.inventory.status()
    assert(status.ready and status.adapter == 'qb' and status.resource == 'test_qb')
    assert(status.metadata and status.slots and status.usable and status.serverUse)
    assert(mock.inventory.call('count', 1, 'dyno_report') == 2)
    assert(mock.inventory.call('remove', 1, 'dyno_report', 1) == true)
    local metadata = { dynoReport = { ps = 310 } }
    assert(mock.inventory.call('canCarry', 1, 'dyno_report', 1, metadata) == true)
    assert(mock.inventory.call('add', 1, 'dyno_report', 1, metadata) == true)
    local item = mock.inventory.call('getSlot', 1, 3)
    assert(item.name == 'dyno_report' and item.count == 1 and item.slot == 3 and item.metadata == metadata)
    assert(mock.inventory.call('getSlot', 1, 8) == nil)
    mock.full = true
    assert(mock.inventory.call('canCarry', 1, 'dyno_report', 1, metadata) == false)
    assert(mock.inventory.call('add', 1, 'dyno_report', 1, metadata) == false)
    mock.states.test_core = nil
    assert(not mock.inventory.status().ready)
    local value, reason = mock.inventory.call('getSlot', 1, 3)
    assert(value == nil and reason == 'inventory_unavailable')
end)

test('auto chooses Ox first, then QB, while explicit inventory settings stay pinned', function()
    local mock = qbRuntime()
    mock.states.test_inventory = true
    assert(mock.inventory.status().adapter == 'ox' and not mock.inventory.status().serverUse)
    mock.states.test_inventory = nil
    assert(mock.inventory.status().adapter == 'qb' and mock.inventory.status().serverUse)
    mock.env.Config.Inventory.adapter = 'ox'
    assert(mock.inventory.status().adapter == 'ox' and not mock.inventory.status().ready)
    mock.states.test_inventory = true
    assert(mock.inventory.status().ready)
    mock.env.Config.Inventory = { adapter = 'ox', resource = 'old_resource' }
    mock.states.old_resource = true
    assert(mock.inventory.status().ready and mock.inventory.status().resource == 'old_resource')
end)

test('QB usable registration waits for core, follows provider restarts and validates slots', function()
    local mock, calls = qbRuntime(), {}
    mock.states.test_core = nil
    local function handler(source, slot) calls[#calls + 1] = { source, slot } end
    assert(mock.inventory.registerUse('402studio_dyno', 'dyno_report', handler))
    assert(not mock.inventory.itemUseAvailable('402studio_dyno', 'dyno_report') and not mock.usables.dyno_report)
    mock.states.test_core = true
    mock.emit('onResourceStart', 'test_core')
    assert(mock.inventory.itemUseAvailable('402studio_dyno', 'dyno_report'))
    local stale = mock.usables.dyno_report.func
    local accepted, reason = mock.inventory.registerUse('402studio_other', 'dyno_report', handler)
    assert(not accepted and reason == 'item_in_use')
    assert(not mock.inventory.itemUseAvailable('402studio_other', 'dyno_report'))
    mock.inventory.call('add', 1, 'dyno_report', 1, {})
    stale(1, { name = 'dyno_report', slot = 6 })
    stale(2, { name = 'dyno_report', slot = 3 })
    stale(1, { name = 'other', slot = 3 })
    stale(1, { name = 'dyno_report', slot = 3.5 })
    assert(#calls == 0)
    stale(1, mock.items[3])
    assert(#calls == 1 and calls[1][1] == 1 and calls[1][2] == 3 and #calls[1] == 2)
    mock.states.test_core = nil
    mock.emit('onResourceStop', 'test_core')
    mock.usables.dyno_report = nil
    assert(not mock.inventory.itemUseAvailable('402studio_dyno', 'dyno_report'))
    mock.states.test_core = true
    mock.emit('onResourceStart', 'test_core')
    local active = mock.usables.dyno_report.func
    assert(active ~= stale and mock.inventory.itemUseAvailable('402studio_dyno', 'dyno_report'))
    stale(1, mock.items[3])
    active(1, mock.items[3])
    assert(#calls == 2)
    mock.emit('onResourceStop', '402studio_dyno')
    active(1, mock.items[3])
    assert(#calls == 2 and not mock.inventory.itemUseAvailable('402studio_dyno', 'dyno_report'))
    assert(mock.inventory.registerUse('402studio_other', 'dyno_report', handler))
    assert(mock.inventory.itemUseAvailable('402studio_other', 'dyno_report'))
end)

test('QB callbacks go inactive while Ox is selected and rebind on fallback', function()
    local mock, calls = qbRuntime(), 0
    local function handler() calls = calls + 1 end
    assert(mock.inventory.registerUse('402studio_dyno', 'dyno_report', handler))
    assert(mock.inventory.call('add', 1, 'dyno_report', 1, {}))
    local previous = mock.usables.dyno_report.func
    mock.states.test_inventory = true
    mock.emit('onResourceStart', 'test_inventory')
    assert(mock.inventory.itemUseAvailable('402studio_dyno', 'dyno_report'))
    previous(1, mock.items[3])
    assert(calls == 0)
    mock.states.test_inventory = nil
    mock.emit('onResourceStop', 'test_inventory')
    local active = mock.usables.dyno_report.func
    assert(active ~= previous and mock.inventory.itemUseAvailable('402studio_dyno', 'dyno_report'))
    previous(1, mock.items[3])
    active(1, mock.items[3])
    assert(calls == 1)
end)

test('usable item exports derive ownership and respect a preexisting QB handler', function()
    local mock = qbRuntime()
    mock.load('adapters/framework/standalone/server.lua')
    mock.load('server/main.lua')
    local existing = { resource = 'other_resource', func = function() end }
    mock.usables.dyno_report = existing
    assert(mock.exported.RegisterUsableItem('dyno_report', function() end, 'untrusted'))
    assert(mock.usables.dyno_report == existing and not mock.exported.IsInventoryItemUseAvailable('dyno_report'))
    mock.usables.dyno_report = nil
    mock.emit('onResourceStart', 'test_qb')
    assert(mock.exported.IsInventoryItemUseAvailable('dyno_report'))
    mock.owner = '402studio_other'
    assert(not mock.exported.IsInventoryItemUseAvailable('dyno_report', '402studio_dyno'))
    assert(not mock.exported.RegisterUsableItem('dyno_report', function() end, '402studio_dyno'))
    mock.owner = 'untrusted'
    assert(mock.exported.RegisterUsableItem('other_item', function() end) == nil)
end)

print(('Passed %d inventory bridge tests.'):format(total))
