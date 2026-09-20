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

BridgeRegistry.register('framework', 'qbox', {
    connect = function(resource) return exports[resource] end,
    player = function(core, source) return core:GetPlayer(source) end,
    data = playerData,
    group = function(_, _, source, groups)
        for group, enabled in pairs(groups) do
            if enabled == true and IsPlayerAceAllowed(source, 'group.' .. group) then return true end
        end
        return false
    end,
    balance = function(core, _, source, account) return core:GetMoney(source, account) end,
    remove = function(core, _, source, account, amount, reason)
        return core:RemoveMoney(source, account, amount, reason) == true
    end,
    add = function(core, _, source, account, amount, reason)
        return core:AddMoney(source, account, amount, reason) == true
    end,
})
