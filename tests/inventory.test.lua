local root = arg[1] or '.'
local total = 0

local function runtime(options)
    options = options or {}
    local result = { calls = {} }
    local env = setmetatable({}, { __index = _G })
    env.Config = {
        Inventory = { adapter = 'ox', resource = 'test_inventory' },
        AllowedResources = {},
        FirstParty = { prefix = '402studio_', author = '402-Studio' },
    }
    env.GetResourceState = function() return options.stopped and 'stopped' or 'started' end
    env.GetResourceMetadata = function() return options.author or '402-Studio' end
    env.GetPlayerPed = function(src) return options.missingPed and 0 or src + 100 end
    env.DoesEntityExist = function() return true end
    env.GetEntityCoords = function(ped) return { x = ped, y = 2, z = 3 } end
    env.Player = function() return { state = { instance = 7 } } end
    local inventory = {}
    for _, name in ipairs({ 'GetItemCount', 'RemoveItem', 'AddItem', 'CanCarryItem', 'CustomDrop' }) do
        inventory[name] = function(_, ...)
            result.calls[#result.calls + 1] = { name = name, args = table.pack(...) }
            if name == 'GetItemCount' then return 2 end
            if name == 'CustomDrop' then
                if options.dropFails then return false end
                return 'drop-1'
            end
            return not options.full
        end
    end
    env.exports = { test_inventory = inventory }
    assert(loadfile(root .. '/shared/registry.lua', 't', env))()
    assert(loadfile(root .. '/adapters/inventory/ox/server.lua', 't', env))()
    assert(loadfile(root .. '/server/inventory.lua', 't', env))()
    result.env = env
    result.inventory = env.BridgeInventory
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

print(('Passed %d inventory bridge tests.'):format(total))
