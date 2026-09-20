BridgeRegistry.register('framework', 'standalone', {
    connect = function() return true end,
    player = function(_, source)
        if not GetPlayerName(source) then return end
        return {identifier = GetPlayerIdentifierByType(source, 'license'), name = GetPlayerName(source)}
    end,
    data = function(player) return player end,
    group = function() return false end,
    balance = function() return 0 end,
    remove = function() return false end,
    add = function() return false end,
})
