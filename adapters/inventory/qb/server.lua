local function coreResource()
    return Config.Resources.qb
end

BridgeRegistry.register('inventory', 'qb', {
    metadata = true,
    usable = true,
    dependency = coreResource,
    count = function(resource, source, item)
        return exports[resource]:GetItemCount(source, item) or 0
    end,
    remove = function(resource, source, item, count)
        return exports[resource]:RemoveItem(source, item, count, false, GetCurrentResourceName()) == true
    end,
    add = function(resource, source, item, count, metadata)
        return exports[resource]:AddItem(source, item, count, false, metadata, GetCurrentResourceName()) == true
    end,
    canCarry = function(resource, source, item, count)
        return exports[resource]:CanAddItem(source, item, count) == true
    end,
    getSlot = function(resource, source, slot)
        local item = exports[resource]:GetItemBySlot(source, slot)
        if type(item) ~= 'table' then return end
        return {
            name = item.name,
            count = item.amount,
            slot = slot,
            metadata = type(item.info) == 'table' and item.info or nil,
        }
    end,
    registerUse = function(resource, name, handler)
        local dependency = coreResource()
        local core = exports[dependency]
        local existing = core:CanUseItem(name)
        if existing and (type(existing) ~= 'table' or existing.resource ~= GetCurrentResourceName()) then return false end
        core:CreateUseableItem(name, function(source, item)
            if type(item) ~= 'table' or item.name ~= name or type(item.slot) ~= 'number'
                or item.slot % 1 ~= 0 or item.slot < 1 or item.slot > 10000 then return end
            if GetResourceState(resource) ~= 'started' or GetResourceState(dependency) ~= 'started' then return end
            local current = exports[resource]:GetItemBySlot(source, item.slot)
            if type(current) == 'table' and current.name == name then handler(source, item.slot) end
        end)
        return true
    end,
})
