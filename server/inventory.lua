BridgeInventory = {}
local itemUses = {}

local function selectedInventory()
    local name, resource = BridgeRegistry.resolveInventory()
    local selected = BridgeRegistry.get('inventory', name)
    if not selected or type(resource) ~= 'string' or resource == '' or GetResourceState(resource) ~= 'started' then
        return nil, name, resource
    end
    local dependency
    if type(selected.dependency) == 'function' then
        dependency = selected.dependency()
        if type(dependency) ~= 'string' or dependency == '' or GetResourceState(dependency) ~= 'started' then
            return nil, name, resource
        end
    end
    return selected, name, resource, dependency
end

function BridgeInventory.status()
    local selected, name, resource = selectedInventory()
    local ready = selected ~= nil
    return {
        adapter = name,
        resource = resource,
        ready = ready,
        metadata = ready and selected.metadata == true,
        slots = ready and type(selected.getSlot) == 'function',
        usable = ready and selected.usable == true,
        serverUse = ready and type(selected.registerUse) == 'function',
        error = not ready and 'inventory_unavailable' or nil,
    }
end

function BridgeInventory.call(action, source, item, count, metadata)
    local selected, _, resource = selectedInventory()
    if not selected then return nil, 'inventory_unavailable' end
    if type(selected[action]) ~= 'function' then return nil, 'inventory_action_unavailable' end
    if metadata ~= nil and selected.metadata ~= true then return nil, 'inventory_metadata_unavailable' end
    return selected[action](resource, source, item, count, metadata)
end

local function matches(binding, selected, resource, dependency)
    return binding and binding.adapter == selected and binding.resource == resource and binding.dependency == dependency
end

local function bindUse(name, registration, selected, resource, dependency)
    if matches(registration.binding, selected, resource, dependency) then return end
    registration.binding = nil
    if not selected or type(selected.registerUse) ~= 'function' then return end
    local binding = { adapter = selected, resource = resource, dependency = dependency }
    local ok, accepted = pcall(selected.registerUse, resource, name, function(source, slot)
        if itemUses[name] ~= registration or registration.binding ~= binding then return end
        local current, _, currentResource, currentDependency = selectedInventory()
        if matches(binding, current, currentResource, currentDependency) then registration.handler(source, slot) end
    end)
    if ok and accepted == true then registration.binding = binding end
end

local function refreshUses()
    local selected, _, resource, dependency = selectedInventory()
    for name, registration in pairs(itemUses) do
        bindUse(name, registration, selected, resource, dependency)
    end
end

function BridgeInventory.registerUse(owner, name, handler)
    local registration = itemUses[name]
    if registration and registration.owner ~= owner then return false, 'item_in_use' end
    registration = registration or { owner = owner }
    registration.handler = handler
    itemUses[name] = registration
    local selected, _, resource, dependency = selectedInventory()
    bindUse(name, registration, selected, resource, dependency)
    return true
end

function BridgeInventory.itemUseAvailable(owner, name)
    local selected, _, resource, dependency = selectedInventory()
    if not selected or selected.usable ~= true then return false end
    if type(selected.registerUse) ~= 'function' then return true end
    local registration = itemUses[name]
    return registration ~= nil and registration.owner == owner
        and matches(registration.binding, selected, resource, dependency) == true
end

AddEventHandler('onResourceStart', refreshUses)
AddEventHandler('onResourceStop', function(resource)
    for name, registration in pairs(itemUses) do
        local binding = registration.binding
        if registration.owner == resource then
            itemUses[name] = nil
        elseif binding and (binding.resource == resource or binding.dependency == resource) then
            registration.binding = nil
        end
    end
    if next(itemUses) then SetTimeout(0, refreshUses) end
end)
