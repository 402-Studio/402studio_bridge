Config.CustomFramework = {
    enabled = true,
    resource = 'my_framework',
    accounts = {cash = 'wallet', bank = 'bank'},

    getCore = function(resource)
        return exports[resource]:GetCore()
    end,

    getPlayer = function(core, source)
        local player = core:GetPlayer(source)
        if not player then return end
        return {
            identifier = player.id,
            name = player.name,
            job = player.job,
        }
    end,

    hasGroup = function(core, source, groups)
        local player = core:GetPlayer(source)
        return player and groups[player.group] == true
    end,

    getBalance = function(core, source, account)
        local player = core:GetPlayer(source)
        return player and player:GetMoney(account) or 0
    end,

    removeMoney = function(core, source, account, amount, reason)
        local player = core:GetPlayer(source)
        return player and player:RemoveMoney(account, amount, reason) == true
    end,

    addMoney = function(core, source, account, amount, reason)
        local player = core:GetPlayer(source)
        return player and player:AddMoney(account, amount, reason) == true
    end,

    notify = function(resource, message, kind, duration, title)
        exports[resource]:Notify(message, kind, duration, title)
        return true
    end,
}
