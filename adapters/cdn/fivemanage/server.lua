BridgeRegistry.register('cdn', 'fivemanage', {
    target = function()
        local url = ('https://api.fivemanage.com/api/v3/file/presigned-url?expiresAt=%d'):format(os.time() + 300)
        return BridgeCdn.presigned(url, '402studio_bridge:fivemanageKey', {
            ['api.fivemanage.com'] = true,
            ['fmapi.net'] = true,
        }, '^/api/v3/file/presigned%-url/[%w._%-]+$')
    end,
    decode = BridgeCdn.decode,
})
