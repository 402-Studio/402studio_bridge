BridgeRegistry.register('framework', 'esx', {
    connect = function(resource) return exports[resource]:getSharedObject() end,
    player = function(core, source) return core.GetPlayerFromId(source) end,
    data = function(player)
        local job = player.job
        return {
            identifier = player.identifier,
            name = player.getName(),
            job = job and {
                name = job.name,
                label = job.label,
                grade = tonumber(job.grade) or 0,
                onDuty = job.onDuty,
            },
        }
    end,
    group = function(_, player, _, groups) return groups[player.getGroup()] == true end,
    balance = function(_, player, _, account)
        local data = player.getAccount(account)
        return data and data.money or 0
    end,
    remove = function(_, player, _, account, amount, reason)
        local before = player.getAccount(account)
        if not before or before.money < amount then return false end
        local balance = before.money
        player.removeAccountMoney(account, amount, reason)
        return player.getAccount(account).money == balance - amount
    end,
    add = function(_, player, _, account, amount, reason)
        local before = player.getAccount(account)
        if not before then return false end
        local balance = before.money
        player.addAccountMoney(account, amount, reason)
        return player.getAccount(account).money == balance + amount
    end,
})
