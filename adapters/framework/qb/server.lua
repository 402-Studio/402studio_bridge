local function playerData(player)
    local data = player.PlayerData
    local info = data.charinfo or {}
    local job = data.job
    return {
        identifier = data.citizenid,
        name = (info.firstname or '') .. ' ' .. (info.lastname or ''),
        job = job and {
            name = job.name,
            label = job.label,
            grade = type(job.grade) == 'table' and job.grade.level or tonumber(job.grade) or 0,
            onDuty = job.onduty == true,
        },
    }
end

BridgeRegistry.register('framework', 'qb', {
    connect = function(resource) return exports[resource]:GetCoreObject() end,
    player = function(core, source) return core.Functions.GetPlayer(source) end,
    data = playerData,
    group = function(core, _, source, groups)
        for group, enabled in pairs(groups) do
            if enabled == true and core.Functions.HasPermission(source, group) then return true end
        end
        return false
    end,
    balance = function(_, player, _, account) return player.PlayerData.money[account] or 0 end,
    remove = function(_, player, _, account, amount, reason)
        return player.Functions.RemoveMoney(account, amount, reason) == true
    end,
    add = function(_, player, _, account, amount, reason)
        return player.Functions.AddMoney(account, amount, reason) == true
    end,
})
