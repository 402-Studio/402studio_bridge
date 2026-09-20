BridgeInventory = {}

local function adapter()
    return BridgeRegistry.get('inventory', Config.Inventory.adapter)
end

function BridgeInventory.status()
    local ready = adapter() ~= nil and GetResourceState(Config.Inventory.resource) == 'started'
    return {
        adapter = Config.Inventory.adapter,
        resource = Config.Inventory.resource,
        ready = ready,
    }
end

function BridgeInventory.call(action, source, item, count)
    local selected = adapter()
    if not selected or GetResourceState(Config.Inventory.resource) ~= 'started' then
        return nil, 'inventory_unavailable'
    end
    return selected[action](Config.Inventory.resource, source, item, count)
end
