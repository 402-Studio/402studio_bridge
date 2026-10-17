local function adapter(provider)
    local owner = GetInvokingResource()
    if not owner or not BridgeRegistry.allowed(owner) then return nil, 'forbidden_resource' end
    if type(provider) ~= 'string' or provider == '' then return nil, 'invalid_cdn_provider' end
    if not BridgeRegistry.status('cdn', provider) then return nil, 'cdn_unavailable' end
    return BridgeRegistry.get('cdn', provider)
end

exports('IsCdnAvailable', function(provider)
    local selected, err = adapter(provider)
    return selected ~= nil, err
end)

exports('CreateCdnUpload', function(provider)
    local selected, err = adapter(provider)
    if not selected then return nil, err end
    local ok, result, requestError = pcall(selected.target)
    if not ok then return nil, 'cdn_request_failed' end
    if not result then return nil, requestError or 'cdn_request_failed' end
    if type(result) ~= 'table' or not BridgeCdn.httpsUrl(result.url)
        or type(result.formField) ~= 'string' or result.formField == ''
        or #result.formField > 128 or result.formField:find('[%c]') then return nil, 'invalid_cdn_response' end
    return { provider = provider, url = result.url, formField = result.formField }
end)

exports('ResolveCdnUpload', function(provider, result)
    local selected, err = adapter(provider)
    if not selected then return nil, err end
    local ok, data, decodeError = pcall(selected.decode, result)
    if not ok then return nil, 'invalid_cdn_response' end
    if not data then return nil, decodeError or 'invalid_cdn_response' end
    if type(data) ~= 'table' or not BridgeCdn.httpsUrl(data.url) then return nil, 'invalid_cdn_response' end
    return { url = data.url, id = type(data.id) == 'string' and data.id or nil }
end)
