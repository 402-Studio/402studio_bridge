BridgeRegistry.register('cdn', 'qbox', {
    target = function()
        return BridgeCdn.presigned('https://api.qbox.re/v1/file/presigned-url', '402studio_bridge:qboxKey', {
            ['api.qbox.re'] = true,
        }, '^/v1/file/presigned%-url/[%w._%-]+$')
    end,
    decode = BridgeCdn.decode,
})
