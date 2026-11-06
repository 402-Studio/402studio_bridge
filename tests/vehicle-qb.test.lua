local root = arg[1] or '.'
local passed = 0

local function test(name, callback)
    callback()
    passed = passed + 1
    print('PASS ' .. name)
end

local function runtime()
    local result = {
        row = { id = 42, citizenid = 'CHAR1', vehicle = 'adder', hash = '-1', plate = 'ABC123', mods = 'valid' },
        plate = 'ABC123', model = -1, entityType = 2, exists = true, started = true,
        now = 0, queries = {}, handlers = {},
    }
    local env = setmetatable({}, { __index = _G })
    env.Config = { Vehicles = { adapter = 'qb', resource = 'database' } }
    env.GetResourceState = function(resource)
        return resource == 'database' and result.started and 'started' or 'stopped'
    end
    env.DoesEntityExist = function(vehicle) return vehicle == 10 and result.exists end
    env.GetEntityType = function() return result.entityType end
    env.GetEntityModel = function() return result.model end
    env.GetVehicleNumberPlateText = function() return result.plate end
    env.GetGameTimer = function() return result.now end
    env.promise = { new = function()
        return { resolve = function(self, value) self.resolved, self.value = true, value end }
    end }
    env.Citizen = { Await = function(pending)
        if not pending.resolved then coroutine.yield() end
        assert(pending.resolved)
        return pending.value
    end }
    env.Entity = function() error('QBCore must not depend on Qbox vehicle state') end
    env.joaat = function(model)
        return assert(({ adder = -1, sultan = 123 })[model], 'unexpected model name')
    end
    env.AddEventHandler = function(name, callback) result.handlers[name] = callback end
    env.BridgeVehicleClasses = { get = function(model) return model == -1 and 7 or nil end }
    env.json = { decode = function(value)
        if value == 'valid' then return { modEngine = result.modEngine or 2, plate = 'ABC123' } end
        if value == '{}' then return {} end
        if value == 'null' then return nil end
        if value == 'false' then return false end
        error('invalid JSON')
    end }
    env.exports = { database = { single_async = function(_, query, parameters)
        result.queries[#result.queries + 1] = { query = query, parameters = parameters }
        if result.onQuery then result.onQuery() end
        if result.queryError then error(result.queryError) end
        local row = result.row
        if not row then return nil end
        if query:find('WHERE `id` = ?', 1, true) then
            if tonumber(row.id) ~= parameters[1] then return nil end
        else
            assert(query:find('WHERE `plate` = ?', 1, true))
            if row.plate ~= parameters[1] then return nil end
        end
        local copy = {}
        for key, value in pairs(row) do copy[key] = value end
        return copy
    end } }
    assert(loadfile(root .. '/shared/registry.lua', 't', env))()
    assert(loadfile(root .. '/adapters/vehicle/qb/server.lua', 't', env))()
    assert(loadfile(root .. '/server/vehicle.lua', 't', env))()
    result.env, result.service = env, env.BridgeVehicles
    return result
end

test('QBCore vehicle IDs use the database row and cache repeated polling', function()
    local mock = runtime()
    mock.row.id = '42'
    assert(mock.service.id(10) == 42 and mock.service.id(10) == 42)
    assert(#mock.queries == 1 and mock.queries[1].parameters[1] == 'ABC123')
    assert(mock.service.status().ready and mock.service.class(-1) == 7)
end)

test('vehicle owner reads reflect character ownership transfers', function()
    local mock = runtime()
    assert(mock.service.owner(10) == 'CHAR1')
    mock.row.citizenid = 'CHAR2'
    assert(mock.service.owner(10) == 'CHAR2')
    assert(#mock.queries == 3 and mock.queries[3].parameters[1] == 42)
end)

test('saved properties return fresh decoded tables', function()
    local mock = runtime()
    local first = assert(mock.service.properties(10))
    first.modEngine = 99
    assert(mock.service.properties(10).modEngine == 2)
    mock.modEngine = 3
    assert(mock.service.properties(10).modEngine == 3)
end)

test('freshly bought vehicles accept empty saved properties', function()
    local mock = runtime()
    for _, value in ipairs({ '{}', '' }) do
        mock.row.mods = value
        assert(next(mock.service.properties(10)) == nil)
    end
    mock.row.mods = nil
    assert(next(mock.service.properties(10)) == nil)
end)

test('malformed property JSON is rejected without throwing', function()
    local mock = runtime()
    for _, value in ipairs({ 'broken', 'null', 'false' }) do
        mock.row.mods = value
        assert(mock.service.properties(10) == nil)
    end
end)

test('plate lookup trims native padding and binds SQL parameters', function()
    local mock = runtime()
    mock.plate, mock.row.plate = "  A'BC12  ", "A'BC12"
    assert(mock.service.id(10) == 42)
    assert(mock.queries[1].parameters[1] == "A'BC12")
    assert(not mock.queries[1].query:find("A'BC12", 1, true))
end)

test('unregistered vehicles retry after the miss cooldown', function()
    local mock = runtime()
    local row = mock.row
    mock.row = nil
    assert(mock.service.id(10) == nil and mock.service.id(10) == nil)
    assert(#mock.queries == 1)
    mock.row = row
    mock.now = 15000
    assert(mock.service.id(10) == 42 and #mock.queries == 2)
end)

test('positive ID cache expires and resolves replacement rows', function()
    local mock = runtime()
    assert(mock.service.id(10) == 42)
    mock.row.id = 84
    mock.now = 60000
    assert(mock.service.id(10) == 84 and #mock.queries == 2)
end)

test('plate changes invalidate the entity ID cache immediately', function()
    local mock = runtime()
    assert(mock.service.id(10) == 42)
    mock.plate, mock.row.plate, mock.row.id = 'NEW123', 'NEW123', 84
    assert(mock.service.id(10) == 84 and #mock.queries == 2)
end)

test('model changes reject a cached identity', function()
    local mock = runtime()
    assert(mock.service.id(10) == 42)
    mock.model = 123
    assert(mock.service.id(10) == nil)
    assert(mock.service.owner(10) == nil and mock.service.properties(10) == nil)
end)

test('invalid numeric database IDs are rejected', function()
    for _, id in ipairs({ 0, -1, 1.5, math.huge, 0 / 0, 'invalid' }) do
        local mock = runtime()
        mock.row.id = id
        assert(mock.service.id(10) == nil)
    end
end)

test('numeric model hashes support signed and unsigned storage', function()
    local mock = runtime()
    mock.row.vehicle, mock.row.hash = nil, '4294967295'
    assert(mock.service.id(10) == 42)
    mock.model = 4294967295
    assert(mock.service.owner(10) == 'CHAR1')
end)

test('missing and mismatched saved model hashes are rejected', function()
    for _, value in ipairs({ '123', 'invalid' }) do
        local mock = runtime()
        mock.row.vehicle, mock.row.hash = nil, value
        assert(mock.service.id(10) == nil)
    end
end)

test('blank plates and invalid entities never query the database', function()
    local mock = runtime()
    mock.plate = '   '
    assert(mock.service.id(10) == nil)
    mock.plate, mock.exists = 'ABC123', false
    assert(mock.service.id(10) == nil)
    mock.exists, mock.entityType = true, 1
    assert(mock.service.id(10) == nil)
    assert(mock.service.id('10') == nil and #mock.queries == 0)
end)

test('stopped databases block cached IDs and fresh reads', function()
    local mock = runtime()
    assert(mock.service.id(10) == 42)
    mock.started = false
    assert(mock.service.id(10) == nil and mock.service.owner(10) == nil)
    assert(mock.service.properties(10) == nil and not mock.service.status().ready)
    assert(#mock.queries == 1)
end)

test('database errors allow an immediate retry', function()
    local mock = runtime()
    mock.queryError = 'database unavailable'
    assert(pcall(mock.service.id, 10) == false)
    mock.queryError = nil
    assert(mock.service.id(10) == 42 and #mock.queries == 2)
end)

test('entity removal invalidates an ID before the handle is reused', function()
    local mock = runtime()
    assert(mock.service.id(10) == 42)
    mock.handlers.entityRemoved(10)
    mock.row.id = 84
    assert(mock.service.id(10) == 84 and #mock.queries == 2)
end)

local function pendingLookup(mock, callback)
    mock.onQuery = coroutine.yield
    local thread = coroutine.create(callback or function() return mock.service.id(10) end)
    assert(coroutine.resume(thread))
    assert(coroutine.status(thread) == 'suspended')
    mock.onQuery = nil
    return function()
        local ok, value = coroutine.resume(thread)
        assert(ok, value)
        assert(coroutine.status(thread) == 'dead')
        return value
    end
end

test('entity removal during a database wait discards the old response', function()
    local mock = runtime()
    local finish = pendingLookup(mock)
    mock.handlers.entityRemoved(10)
    assert(finish() == nil)
    mock.row.id = 84
    assert(mock.service.id(10) == 84)
end)

test('database restart during a wait discards the old response', function()
    local mock = runtime()
    local finish = pendingLookup(mock)
    mock.handlers.onResourceStop('database')
    assert(finish() == nil)
    mock.row.id = 84
    assert(mock.service.id(10) == 84)
end)

test('plate changes during a database wait discard the old identity', function()
    local mock = runtime()
    local finish = pendingLookup(mock)
    mock.plate = 'NEW123'
    assert(finish() == nil)
    mock.row.plate, mock.row.id = 'NEW123', 84
    assert(mock.service.id(10) == 84)
end)

test('a pending lookup coalesces repeated ID requests', function()
    local mock = runtime()
    local finish = pendingLookup(mock)
    local second = coroutine.create(function() return mock.service.id(10) end)
    assert(coroutine.resume(second))
    assert(coroutine.status(second) == 'suspended' and #mock.queries == 1)
    assert(finish() == 42 and mock.service.id(10) == 42)
    local ok, id = coroutine.resume(second)
    assert(ok and id == 42 and coroutine.status(second) == 'dead')
    assert(#mock.queries == 1)
end)

test('concurrent owner reads wait for a pending identity', function()
    local mock = runtime()
    local finish = pendingLookup(mock)
    local owner = coroutine.create(function() return mock.service.owner(10) end)
    assert(coroutine.resume(owner))
    assert(coroutine.status(owner) == 'suspended')
    assert(finish() == 42)
    local ok, citizenid = coroutine.resume(owner)
    assert(ok and citizenid == 'CHAR1' and #mock.queries == 2)
end)

test('waiting callers reject an entity removed after query completion', function()
    local mock = runtime()
    local finish = pendingLookup(mock)
    local second = coroutine.create(function() return mock.service.id(10) end)
    assert(coroutine.resume(second))
    assert(finish() == 42)
    mock.handlers.entityRemoved(10)
    local ok, id = coroutine.resume(second)
    assert(ok and id == nil)
end)

test('concurrent lookup errors reach every waiting caller', function()
    local mock = runtime()
    local finish = pendingLookup(mock, function() return pcall(mock.service.id, 10) end)
    local second = coroutine.create(function() return pcall(mock.service.id, 10) end)
    assert(coroutine.resume(second))
    mock.queryError = 'query failed'
    assert(finish() == false)
    local resumed, ok, problem = coroutine.resume(second)
    assert(resumed and ok == false and problem:find('query failed', 1, true))
    mock.queryError = nil
    assert(mock.service.id(10) == 42)
end)

test('deleted owner rows invalidate the cached ID', function()
    local mock = runtime()
    assert(mock.service.id(10) == 42)
    local row = mock.row
    mock.row = nil
    assert(mock.service.owner(10) == nil)
    mock.row, row.id = row, 84
    assert(mock.service.id(10) == 84)
end)

test('missing character owners are rejected', function()
    local mock = runtime()
    mock.row.citizenid = ''
    assert(mock.service.owner(10) == nil)
    mock.row.citizenid = nil
    assert(mock.service.owner(10) == nil)
end)

test('database lookup errors propagate through a yielding caller', function()
    local mock = runtime()
    local finish = pendingLookup(mock, function() return pcall(mock.service.id, 10) end)
    mock.queryError = 'query failed'
    assert(finish() == false)
    mock.queryError = nil
    assert(mock.service.id(10) == 42)
end)

print(('Passed %d QBCore vehicle tests.'):format(passed))
