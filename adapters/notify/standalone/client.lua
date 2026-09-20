BridgeRegistry.register('notify', 'standalone', {
    notify = function(_, message, _, _, title)
        BeginTextCommandThefeedPost('STRING')
        AddTextComponentSubstringPlayerName(title and (title .. ': ' .. message) or message)
        EndTextCommandThefeedPostTicker(false, false)
        return true
    end,
})
