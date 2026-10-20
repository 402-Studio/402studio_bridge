local root = arg[1] or '.'
local count = 0

local function test(name, callback)
    callback()
    count = count + 1
    print('PASS ' .. name)
end

local function runtime()
    local result = { owner = '402studio_test', exported = {}, handlers = {}, threads = {}, registered = {}, validations = {} }
    local env = setmetatable({}, { __index = _G })
    env.Config = {
        Capture = { adapter = 'screencapture', resource = 'capture_provider' },
        Vehicles = { adapter = 'qbox', resource = 'vehicle_provider', classResource = 'class_provider' },
        AllowedResources = { other_allowed = true },
        FirstParty = { prefix = '402studio_', author = '402-Studio' },
    }
    env.GetInvokingResource = function() return result.owner end
    env.GetCurrentResourceName = function() return '402studio_bridge' end
    env.GetResourceMetadata = function() return '402-Studio' end
    env.GetResourceState = function() return result.stopped and 'stopped' or 'started' end
    env.CreateThread = function(callback) result.threads[#result.threads + 1] = callback end
    env.AddEventHandler = function(event, callback)
        result.handlers[event] = result.handlers[event] or {}
        table.insert(result.handlers[event], callback)
    end
    env.exports = setmetatable({}, { __call = function(_, name, callback) result.exported[name] = callback end })
    env.lib = {
        callback = {
            register = function(name, callback)
                result.registrations = (result.registrations or 0) + 1
                result.registered[name] = callback
            end,
            await = function(...) result.request = table.pack(...); return false, nil, 'tail', nil end,
        },
        setValidCallback = function(name, valid) result.validations[name] = valid end,
    }
    result.env = env
    function result.load(file) assert(loadfile(root .. '/' .. file, 't', env))() end
    function result.stop(owner) for _, callback in ipairs(result.handlers.onResourceStop or {}) do callback(owner) end end
    result.load('shared/registry.lua')
    return result
end

test('callback results retain false, interior nil, trailing nil, and request args', function()
    local mock = runtime()
    mock.load('client/callback.lua')
    local id = assert(mock.exported.StartCallback('test:event', false, nil, 'arg', nil))
    assert(mock.exported.CallbackResult(id) == false)
    mock.owner = nil
    mock.threads[1]()
    assert(mock.request.n == 5 and mock.request[1] == 'test:event' and mock.request[2] == false)
    assert(mock.request[3] == nil and mock.request[4] == 'arg' and mock.request[5] == nil)
    mock.owner = '402studio_test'
    local done, values, err = mock.exported.CallbackResult(id)
    assert(done and not err and values.n == 4)
    assert(values[1] == false and values[2] == nil and values[3] == 'tail' and values[4] == nil)
    local _, _, invalid = mock.exported.CallbackResult(id)
    assert(invalid == 'invalid_callback_handle')
end)

test('callback handles reject different owners and survive rejected read', function()
    local mock = runtime()
    mock.load('client/callback.lua')
    local id = mock.exported.StartCallback('test:event', false)
    mock.owner = 'other_allowed'
    local done, _, err = mock.exported.CallbackResult(id)
    assert(done and err == 'invalid_callback_handle')
    mock.owner = '402studio_test'
    assert(mock.exported.CallbackResult(id) == false)
end)

test('callback errors preserve original error value', function()
    local mock = runtime()
    local providerError = { reason = 'timeout' }
    mock.env.lib.callback.await = function() error(providerError) end
    mock.load('client/callback.lua')
    local id = mock.exported.StartCallback('test:event', false)
    mock.threads[1]()
    local done, values, err = mock.exported.CallbackResult(id)
    assert(done and not values and err == providerError)
end)

test('callback resource stop drops pending handles before requests', function()
    local mock = runtime()
    mock.load('client/callback.lua')
    local id = mock.exported.StartCallback('test:event', false)
    mock.stop('402studio_test')
    mock.threads[1]()
    assert(not mock.request)
    local _, _, err = mock.exported.CallbackResult(id)
    assert(err == 'invalid_callback_handle')
end)

test('callback registration preserves names, callable references, and single handler after restart', function()
    local mock = runtime()
    mock.load('server/callback.lua')
    local callback = setmetatable({}, { __call = function(_, source, value) return source, value end })
    assert(mock.exported.RegisterCallback('test:event', callback))
    local source, value = mock.registered['test:event'](7, 'result')
    assert(source == 7 and value == 'result')
    mock.owner = 'other_allowed'
    local ok, err = mock.exported.RegisterCallback('test:event', function() end)
    assert(not ok and err == 'callback_in_use')
    mock.stop('402studio_test')
    assert(mock.validations['test:event'] == false and mock.registered['test:event'](7) == nil)
    mock.owner = '402studio_test'
    assert(mock.exported.RegisterCallback('test:event', function() return 'new' end))
    assert(mock.registrations == 1 and mock.validations['test:event'] == true)
    assert(mock.registered['test:event'](7) == 'new')
end)

test('callbacks reject untrusted callers before registration or request', function()
    local mock = runtime()
    mock.load('server/callback.lua')
    mock.load('client/callback.lua')
    mock.owner = 'untrusted'
    local ok, err = mock.exported.RegisterCallback('test:event', function() end)
    assert(not ok and err == 'forbidden_resource' and not mock.registrations)
    local id, requestError = mock.exported.StartCallback('test:event', false)
    assert(not id and requestError == 'forbidden_resource' and #mock.threads == 0)
end)

test('capture forwards original options, callback responses, mode, return values, and errors', function()
    local mock = runtime()
    local response, callbackValues = { status = 'success', data = 'original' }
    local options = { quality = 0.85, formField = 'files[0]' }
    mock.env.exports.capture_provider = {
        remoteUpload = function(_, source, url, value, callback, mode)
            assert(source == 4 and url == 'https://example.test' and value == options and mode == 'blob')
            callback(response, nil, 'extra')
            return 'snapshot-id', nil, 'extra-return'
        end,
        startVideoCaptureUpload = function(_, source, url, value, callback)
            assert(source == 4 and url == 'https://example.test' and value == options)
            callback(response)
            return 'video-id'
        end,
    }
    mock.load('adapters/capture/screencapture/server.lua')
    mock.load('server/capture.lua')
    assert(mock.exported.IsCaptureAvailable('snapshot') and mock.exported.IsCaptureAvailable('video'))
    local id, second, third = mock.exported.CaptureSnapshotUpload(4, 'https://example.test', options,
        function(...) callbackValues = table.pack(...) end)
    assert(id == 'snapshot-id' and second == nil and third == 'extra-return')
    assert(callbackValues[1] == response and callbackValues.n == 3 and callbackValues[3] == 'extra')
    assert(mock.exported.StartVideoCaptureUpload(4, 'https://example.test', options, function(value) assert(value == response) end) == 'video-id')
    local providerError = { error = 'capture refused' }
    mock.env.exports.capture_provider.startVideoCaptureUpload = function() error(providerError) end
    local ok, err = pcall(mock.exported.StartVideoCaptureUpload, 4, 'https://example.test', options, function() end)
    assert(not ok and err == providerError)
    mock.stopped = true
    assert(not mock.exported.IsCaptureAvailable('snapshot'))
end)

test('client capture availability checks started resource and caller permission', function()
    local mock = runtime()
    mock.load('client/capture.lua')
    assert(mock.exported.IsCaptureAvailable('snapshot') and mock.exported.IsCaptureAvailable('video'))
    mock.stopped = true
    assert(not mock.exported.IsCaptureAvailable('snapshot'))
    mock.stopped, mock.owner = false, 'untrusted'
    assert(not mock.exported.IsCaptureAvailable('video'))
end)

print(('Passed %d service checks'):format(count))
