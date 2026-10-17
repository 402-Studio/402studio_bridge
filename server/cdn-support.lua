BridgeCdn = {}

function BridgeCdn.httpsUrl(value)
    if type(value) ~= 'string' or #value > 4096 or value:find('[%c%s\\]') then return nil end
    local authority, path = value:match('^https://([^/?#]+)(.*)$')
    if not authority then return nil end
    local host, port = authority:match('^([%w.-]+):(%d+)$')
    host = host or authority:match('^([%w.-]+)$')
    if not host or not host:match('^[%w]') or not host:match('[%w]$') then return nil end
    if port and (tonumber(port) < 1 or tonumber(port) > 65535) then return nil end
    return host:lower(), path
end

function BridgeCdn.object(value)
    if type(value) == 'string' then
        local ok, decoded = pcall(json.decode, value)
        if not ok then return nil end
        value = decoded
    end
    return type(value) == 'table' and value or nil
end

function BridgeCdn.request(url, headers)
    local pending = promise.new()
    local finished = false
    local function finish(value, err)
        if finished then return end
        finished = true
        pending:resolve({ value = value, error = err })
    end

    SetTimeout(10000, function() finish(nil, 'cdn_timeout') end)
    local ok = pcall(function()
        PerformHttpRequest(url, function(status, body)
            if finished then return end
            if type(status) ~= 'number' or status < 200 or status >= 300 then
                return finish(nil, 'cdn_request_failed')
            end
            local response = BridgeCdn.object(body)
            if not response then return finish(nil, 'invalid_cdn_response') end
            finish(response)
        end, 'GET', '', headers)
    end)
    if not ok then finish(nil, 'cdn_request_failed') end

    local result = Citizen.Await(pending)
    return result.value, result.error
end

function BridgeCdn.presigned(url, convar, hosts, pattern)
    local key = GetConvar(convar, '')
    if key == '' or key:find('[%c]') then return nil, 'cdn_key_missing' end
    local response, err = BridgeCdn.request(url, { Authorization = key })
    if not response then return nil, err end
    local data = response.status == 'ok' and BridgeCdn.object(response.data)
    local uploadUrl = data and data.presignedUrl
    local host, path = BridgeCdn.httpsUrl(uploadUrl)
    if not host or not hosts[host] or not path:match(pattern) then return nil, 'invalid_cdn_response' end
    return { url = uploadUrl, formField = 'file' }
end

function BridgeCdn.decode(result)
    if type(result) ~= 'table' or result.status ~= 'success' then return nil, 'invalid_cdn_response' end
    local response = BridgeCdn.object(result.response)
    local data = response and response.status == 'ok' and BridgeCdn.object(response.data)
    if not data or not BridgeCdn.httpsUrl(data.url) then return nil, 'invalid_cdn_response' end
    return { url = data.url, id = type(data.id) == 'string' and data.id or nil }
end
