local root = arg[1] or '.'
local count = 0

local function test(name, callback)
    callback()
    count = count + 1
    print('PASS ' .. name)
end

local function runtime()
    local result = { now = 0, players = {}, requests = {}, events = {} }
    local env = setmetatable({}, { __index = _G })
    env.GetHashKey = function(value)
        assert(value == 'testmodel')
        return -1
    end
    env.GetGameTimer = function() return result.now end
    env.GetPlayers = function() return result.players end
    env.AddEventHandler = function(name, callback) result.events[name] = callback end
    env.CreateThread = function(callback) result.worker = coroutine.create(callback) end
    env.Wait = function() coroutine.yield() end
    env.lib = { callback = setmetatable({}, { __call = function(_, name, player, callback)
        assert(name == '402studio_bridge:vehicleClasses')
        if result.unavailable then error('provider unavailable') end
        result.requests[#result.requests + 1] = { player = player, callback = callback }
    end }) }
    assert(loadfile(root .. '/server/vehicle-classes.lua', 't', env))()
    result.env = env
    result.get = env.BridgeVehicleClasses.get
    function result.step(time)
        result.now = time
        local ok, problem = coroutine.resume(result.worker)
        assert(ok, problem)
    end
    return result
end

test('startup waits for players and warms automatically after joining', function()
    local mock = runtime()
    mock.step(0)
    assert(#mock.requests == 0)
    mock.players = { '9' }
    mock.events.playerJoining()
    mock.step(1000)
    assert(#mock.requests == 1 and mock.requests[1].player == 9)
    mock.requests[1].callback({ [4294967295] = 6 })
    assert(mock.get(-1) == 6)
end)

test('vehicle service reads native classes without the configured Qbox provider', function()
    local mock = runtime()
    mock.env.Config = { Vehicles = { adapter = 'qbox', resource = 'missing_provider' } }
    mock.env.BridgeRegistry = { get = function() error('framework provider must not be used') end }
    mock.players = { '7' }
    mock.step(0)
    mock.requests[1].callback({ [4294967295] = 6 })
    assert(loadfile(root .. '/server/vehicle.lua', 't', mock.env))()
    assert(mock.env.BridgeVehicles.class(-1) == 6)
    assert(mock.env.BridgeVehicles.class(123) == nil)
end)

test('bridge restart warms from players already connected', function()
    local mock = runtime()
    mock.players = { '7' }
    mock.step(0)
    assert(#mock.requests == 1)
end)

test('native class values survive signed unsigned and model name lookup', function()
    local mock = runtime()
    mock.players = { '7' }
    mock.step(0)
    mock.requests[1].callback({ [-1] = 0, [123] = 22, [456] = 8, [789] = 16 })
    assert(mock.get(4294967295) == 0 and mock.get(-1) == 0 and mock.get('testmodel') == 0)
    assert(mock.get(123) == 22 and mock.get(456) == 8 and mock.get(789) == 16)
    assert(mock.get(555) == nil)
end)

test('synchronous lookup never yields or sends requests', function()
    local mock = runtime()
    mock.env.Wait = function() error('sync lookup yielded') end
    mock.players = { '7' }
    for _, value in ipairs({ 123, -1, 'testmodel', '', 0 / 0, math.huge, -2147483649, 4294967296, 1.5 }) do
        assert(mock.get(value) == nil)
    end
    assert(#mock.requests == 0)
end)

test('missing provider retries with cooldown and keeps unknown models closed', function()
    local mock = runtime()
    mock.players = { '7' }
    mock.unavailable = true
    mock.step(0)
    assert(mock.get(123) == nil)
    mock.unavailable = false
    mock.step(1000)
    assert(#mock.requests == 0)
    mock.step(15000)
    assert(#mock.requests == 1)
end)

test('expired requests rotate players and late responses cannot replace cache', function()
    local mock = runtime()
    mock.players = { '7', '9' }
    mock.step(0)
    mock.step(10000)
    mock.step(15000)
    assert(#mock.requests == 2 and mock.requests[2].player == 9)
    mock.requests[2].callback({ [123] = 6 })
    mock.requests[1].callback({ [123] = 8 })
    assert(mock.get(123) == 6)
end)

test('response deadline applies before next worker tick', function()
    local mock = runtime()
    mock.players = { '7' }
    mock.step(0)
    mock.now = 10000
    mock.requests[1].callback({ [123] = 6 })
    assert(mock.get(123) == nil)
    mock.step(15000)
    assert(#mock.requests == 2)
end)

test('malformed or oversized responses never replace valid cache', function()
    local oversized = {}
    for index = 1, 32769 do oversized[index] = 6 end
    for _, response in ipairs({ false, {}, { [123] = 23 }, { [123] = -1 }, { [123] = 1.5 },
        { [123] = '6' }, { testmodel = 6 }, { [4294967296] = 6 }, { [-1] = 6, [4294967295] = 8 }, oversized }) do
        local mock = runtime()
        mock.players = { '7' }
        mock.step(0)
        mock.requests[1].callback({ [123] = 6 })
        assert(mock.get(456) == nil)
        mock.step(15000)
        mock.requests[2].callback(response)
        assert(mock.get(123) == 6 and mock.get(456) == nil)
        mock.step(30000)
        assert(#mock.requests == 3)
    end
end)

test('cache miss and later joins refresh only after cooldown', function()
    local mock = runtime()
    mock.players = { '7' }
    mock.step(0)
    mock.requests[1].callback({ [123] = 6 })
    mock.step(15000)
    assert(#mock.requests == 1)
    assert(mock.get(456) == nil)
    mock.step(16000)
    assert(#mock.requests == 2)
    mock.requests[2].callback({ [123] = 6, [456] = 8 })
    mock.events.playerJoining()
    mock.step(17000)
    assert(#mock.requests == 2)
    mock.step(31000)
    assert(#mock.requests == 3)
end)

test('client callback reads native model classes only when requested', function()
    local handler
    local reads = 0
    local env = setmetatable({
        lib = { callback = { register = function(name, callback)
            assert(name == '402studio_bridge:vehicleClasses')
            handler = callback
        end } },
        GetAllVehicleModels = function() reads = reads + 1; return { 'first', 'second', 'invalid' } end,
        GetVehicleClassFromName = function(model) return ({ first = 0, second = 22, invalid = 23 })[model] end,
        GetHashKey = function(model) return model == 'first' and -1 or 123 end,
    }, { __index = _G })
    assert(loadfile(root .. '/client/vehicle-classes.lua', 't', env))()
    assert(reads == 0)
    local response = handler()
    assert(reads == 1 and response[4294967295] == 0 and response[123] == 22)
end)

print(('Passed %d vehicle class tests'):format(count))
