local root = arg[1] or '.'
local passed = 0

local function test(name, callback)
    callback()
    passed = passed + 1
    print('PASS ' .. name)
end

local function runtime(kind)
    local result = { owner = '402studio_dyno', calls = {}, exported = {}, handlers = {}, started = true }
    local env = setmetatable({}, { __index = _G })
    env.Config = { AllowedResources = {}, FirstParty = { prefix = '402studio_', author = '402-Studio' },
        Target = { adapter = 'auto', resources = kind ~= 'none' and { [kind] = 'provider' } or {}, priority = { kind } } }
    env.GetInvokingResource = function() return result.owner end
    env.GetCurrentResourceName = function() return '402studio_bridge' end
    env.GetResourceMetadata = function() return '402-Studio' end
    env.GetResourceState = function() return result.started and 'started' or 'stopped' end
    env.GetHashKey = function(value) return value == 'printer' and 100 or 200 end
    env.CreateThread = function() end
    env.AddEventHandler = function(event, callback)
        result.handlers[event] = result.handlers[event] or {}
        table.insert(result.handlers[event], callback)
    end
    env.exports = setmetatable({}, { __call = function(_, name, callback) result.exported[name] = callback end })
    env.exports.provider = setmetatable({}, { __index = function(_, method)
        return function(_, ...)
            if result.fail then error('provider failed') end
            result.calls[#result.calls + 1] = { method = method, args = table.pack(...) }
            if result.rejected then return false end
        end
    end })
    function result.load(file) assert(loadfile(root .. '/' .. file, 't', env))() end
    function result.stop(resource)
        for _, callback in ipairs(result.handlers.onResourceStop or {}) do callback(resource) end
    end
    result.load('shared/registry.lua')
    result.load('adapters/target/' .. kind .. '/client.lua')
    result.load('client/interface.lua')
    result.load('client/main.lua')
    result.env = env
    return result
end

local function option(selected)
    return { name = 'collect', label = 'Collect report', icon = 'fa-file', distance = 1.5,
        canInteract = function(entity) return entity == 42 end,
        onSelect = selected or function() end }
end

test('ox receives deduplicated model hashes and preserves callbacks', function()
    local mock, selected = runtime('ox')
    local options = { option(function(entity) selected = entity end) }
    assert(mock.exported.AddModelTarget({ 'printer', 100 }, options))
    local call = mock.calls[1]
    assert(call.method == 'addModel' and #call.args[1] == 1 and call.args[1][1] == 100)
    local built = call.args[2][1]
    assert(built.name == '402studio_dyno:collect' and options[1].name == 'collect')
    assert(built.label == 'Collect report' and built.distance == 1.5 and built.icon == 'fa-file')
    assert(built.canInteract(42) and not built.canInteract(7))
    built.onSelect({ entity = 42 })
    assert(selected == 42)
    assert(mock.exported.RemoveModelTarget(100, 'collect'))
    assert(mock.calls[2].method == 'removeModel' and mock.calls[2].args[2][1] == '402studio_dyno:collect')
end)

test('qb removes by display label and retains per-option distance', function()
    local mock, selected = runtime('qb')
    assert(mock.exported.AddModelTarget('printer', { option(function(entity) selected = entity end) }))
    local call = mock.calls[1]
    assert(call.method == 'AddTargetModel' and call.args[1][1] == 100)
    local built = call.args[2]
    assert(built.distance == 1.5 and built.options[1].distance == 1.5)
    assert(built.options[1].canInteract(42))
    built.options[1].action(42)
    assert(selected == 42)
    assert(mock.exported.RemoveModelTarget('printer', { 'collect' }))
    assert(mock.calls[2].method == 'RemoveTargetModel' and mock.calls[2].args[1] == 100)
    assert(mock.calls[2].args[2][1] == 'Collect report')
end)

test('caller cannot remove another resource model options', function()
    local mock = runtime('ox')
    assert(mock.exported.AddModelTarget('printer', { option() }))
    mock.owner = '402studio_other'
    assert(mock.exported.RemoveModelTarget('printer', 'collect'))
    assert(#mock.calls == 1)
    assert(mock.exported.AddModelTarget('printer', { option() }))
    assert(mock.calls[2].args[2][1].name == '402studio_other:collect')
end)

test('qb labels cannot overwrite another bridge caller on the same model', function()
    local mock = runtime('qb')
    assert(mock.exported.AddModelTarget('printer', { option() }))
    mock.owner = '402studio_other'
    assert(not mock.exported.AddModelTarget('printer', { option() }))
    assert(mock.exported.AddModelTarget(200, { option() }))
    assert(#mock.calls == 2)
    mock.started = false
    mock.stop('provider')
    mock.started = true
    assert(mock.exported.AddModelTarget('printer', { option() }))
end)

test('owner stop removes model options', function()
    local mock = runtime('ox')
    assert(mock.exported.AddModelTarget('printer', { option() }))
    mock.stop('402studio_dyno')
    assert(#mock.calls == 2 and mock.calls[2].method == 'removeModel')
    assert(mock.exported.RemoveModelTarget('printer', 'collect') and #mock.calls == 2)
end)

test('bridge stop removes model options for all callers', function()
    local mock = runtime('qb')
    assert(mock.exported.AddModelTarget({ 'printer', 200 }, { option() }))
    mock.stop('402studio_bridge')
    assert(#mock.calls == 3 and mock.calls[2].method == 'RemoveTargetModel')
end)

test('provider stop forgets registrations without calling stopped exports', function()
    local mock = runtime('ox')
    assert(mock.exported.AddModelTarget('printer', { option() }))
    mock.started = false
    mock.stop('provider')
    assert(#mock.calls == 1)
    mock.started = true
    assert(mock.exported.AddModelTarget('printer', { option() }))
    assert(#mock.calls == 2)
end)

test('invalid arguments and forbidden caller never reach provider', function()
    local mock = runtime('ox')
    for _, models in ipairs({ {}, { false }, { '' }, { 0 / 0 }, { math.huge } }) do
        assert(not mock.exported.AddModelTarget(models, { option() }))
    end
    for _, options in ipairs({ {}, { false }, { { name = '', label = 'x', onSelect = function() end } },
        { { name = 'x', label = 'x', onSelect = false } } }) do
        assert(not mock.exported.AddModelTarget('printer', options))
    end
    local invalid = option()
    invalid.distance = 0 / 0
    assert(not mock.exported.AddModelTarget('printer', { invalid }))
    invalid = option()
    invalid.canInteract = true
    assert(not mock.exported.AddModelTarget('printer', { invalid }))
    mock.owner = 'untrusted'
    assert(not mock.exported.AddModelTarget('printer', { option() }))
    assert(not mock.exported.RemoveModelTarget('printer', 'collect'))
    assert(#mock.calls == 0)
end)

test('callable export references are accepted', function()
    local mock = runtime('ox')
    local value = option()
    value.onSelect = setmetatable({}, { __call = function() end })
    value.canInteract = setmetatable({}, { __call = function() return true end })
    assert(mock.exported.AddModelTarget('printer', { value }))
end)

test('missing or failed provider returns false for E fallback', function()
    local mock = runtime('none')
    assert(not mock.exported.AddModelTarget('printer', { option() }))
    mock = runtime('ox')
    mock.started = false
    assert(not mock.exported.AddModelTarget('printer', { option() }))
    mock.started, mock.fail = true, true
    assert(not mock.exported.AddModelTarget('printer', { option() }))
    assert(#mock.calls == 0)
end)

test('provider rejection enables E fallback', function()
    for _, kind in ipairs({ 'ox', 'qb' }) do
        local mock = runtime(kind)
        mock.rejected = true
        assert(not mock.exported.AddModelTarget('printer', { option() }))
        mock.rejected = false
        assert(mock.exported.AddModelTarget('printer', { option() }))
    end
end)

test('failed removal retains registration for retry', function()
    local mock = runtime('ox')
    assert(mock.exported.AddModelTarget('printer', { option() }))
    mock.fail = true
    assert(not mock.exported.RemoveModelTarget('printer', 'collect'))
    mock.fail = false
    assert(mock.exported.RemoveModelTarget('printer', 'collect'))
    assert(#mock.calls == 2)
end)

print(('Passed %d model target tests'):format(passed))
