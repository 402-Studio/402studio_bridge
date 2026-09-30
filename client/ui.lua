local textOwner, textProvider, contextOwner, contextProvider, openContext
local contexts, dialogs, serial = {}, {}, 0

local function caller()
    local resource = GetInvokingResource() or GetCurrentResourceName()
    if resource ~= GetCurrentResourceName() and not BridgeRegistry.allowed(resource) then return nil end
    return resource
end

local function provider(kind)
    if not BridgeInterface.status(kind).ready then return nil end
    local adapter, _, resource = BridgeInterface.resolve(kind)
    return adapter and {adapter = adapter, resource = resource}
end

local function invoke(selected, method, ...)
    if not selected then return false end
    if selected.resource and GetResourceState(selected.resource) ~= 'started' then return false end
    local args = table.pack(...)
    args.n = args.n + 1
    args[args.n] = selected.resource
    local ok, result, extra = pcall(selected.adapter[method], table.unpack(args, 1, args.n))
    return ok and result ~= false, result, extra
end

exports('ShowTextUI', function(text, options)
    local owner = caller()
    if not owner then return false, 'forbidden_resource' end
    if type(text) ~= 'string' or text == '' or (options ~= nil and type(options) ~= 'table') then return false, 'invalid_text' end
    if textOwner and textOwner ~= owner then return false, 'ui_in_use' end
    local selected = provider('textUI')
    if not invoke(selected, 'show', text, options) then return false, 'provider_unavailable' end
    textOwner, textProvider = owner, selected
    return true
end)

exports('HideTextUI', function()
    if not caller() or caller() ~= textOwner then return false end
    local ok = invoke(textProvider, 'hide')
    textOwner, textProvider = nil, nil
    return ok
end)

exports('IsTextUIOpen', function()
    if caller() ~= textOwner then return false end
    local ok, opened, text = invoke(textProvider, 'isOpen')
    return ok and opened == true, text
end)

exports('RegisterContext', function(menu)
    local owner = caller()
    if not owner then return false, 'forbidden_resource' end
    if type(menu) ~= 'table' or type(menu.id) ~= 'string' or menu.id == ''
        or type(menu.title) ~= 'string' or type(menu.options) ~= 'table' then return false, 'invalid_context' end
    local copy = {}
    for key, value in pairs(menu) do copy[key] = value end
    copy.id, copy.options = owner .. ':' .. menu.id, {}
    if menu.menu then copy.menu = owner .. ':' .. menu.menu end
    for i, option in ipairs(menu.options) do
        if type(option) ~= 'table' or type(option.title) ~= 'string'
            or (option.onSelect ~= nil and not BridgeRegistry.callable(option.onSelect)) then return false, 'invalid_option' end
        local entry = {}
        for key, value in pairs(option) do entry[key] = value end
        if entry.menu then entry.menu = owner .. ':' .. entry.menu end
        copy.options[i] = entry
    end
    contexts[copy.id] = {owner = owner, menu = copy}
    return true
end)

exports('ShowContext', function(id)
    local owner = caller()
    if not owner or type(id) ~= 'string' then return false end
    if contextOwner and contextOwner ~= owner then
        local ok, value = invoke(contextProvider, 'getOpen')
        if ok and value then return false, 'ui_in_use' end
        contextOwner, contextProvider, openContext = nil, nil, nil
    end
    local item = contexts[owner .. ':' .. id]
    if not item then return false, 'unknown_context' end
    local selected = provider('context')
    for _, context in pairs(contexts) do
        if context.owner == owner and not invoke(selected, 'register', context.menu) then return false, 'provider_unavailable' end
    end
    if not invoke(selected, 'show', item.menu.id) then return false, 'provider_unavailable' end
    contextOwner, contextProvider, openContext = owner, selected, id
    return true
end)

exports('HideContext', function(onExit)
    if not caller() or caller() ~= contextOwner then return false end
    local ok = invoke(contextProvider, 'hide', onExit == true)
    contextOwner, contextProvider, openContext = nil, nil, nil
    return ok
end)

exports('GetOpenContextMenu', function()
    if caller() ~= contextOwner then return nil end
    local ok, value = invoke(contextProvider, 'getOpen')
    if not ok or not value then return nil end
    local prefix = contextOwner .. ':'
    return type(value) == 'string' and value:sub(1, #prefix) == prefix and value:sub(#prefix + 1) or openContext
end)

exports('StartInputDialog', function(heading, rows, options)
    local owner = caller()
    if not owner or type(heading) ~= 'string' or type(rows) ~= 'table' or #rows == 0 then return nil end
    local _, name, resource = BridgeInterface.resolve('context')
    if name ~= 'ox' or not resource or GetResourceState(resource) ~= 'started' then return nil end
    for _, dialog in pairs(dialogs) do if not dialog.done then return nil end end
    serial = serial + 1
    local id = serial
    dialogs[id] = {owner = owner, resource = resource, done = false}
    CreateThread(function()
        local ok, result = pcall(function() return exports[resource]:inputDialog(heading, rows, options) end)
        if dialogs[id] then
            dialogs[id].done = true
            dialogs[id].result = ok and type(result) == 'table' and result or nil
        end
    end)
    return id
end)

exports('InputDialogResult', function(id)
    local dialog = dialogs[id]
    if not dialog or dialog.owner ~= caller() then return true, nil end
    if not dialog.done then return false, nil end
    dialogs[id] = nil
    return true, dialog.result
end)

AddEventHandler('onResourceStop', function(resource)
    local stopping = resource == GetCurrentResourceName()
    if textOwner == resource or stopping or (textProvider and textProvider.resource == resource) then
        if stopping or textOwner == resource then invoke(textProvider, 'hide') end
        textOwner, textProvider = nil, nil
    end
    if contextOwner == resource or stopping or (contextProvider and contextProvider.resource == resource) then
        if stopping or contextOwner == resource then invoke(contextProvider, 'hide', false) end
        contextOwner, contextProvider, openContext = nil, nil, nil
    end
    for id, context in pairs(contexts) do
        if context.owner == resource or stopping then
            invoke(provider('context'), 'register', {id = id, title = context.menu.title, options = {}})
            contexts[id] = nil
        end
    end
    for id, dialog in pairs(dialogs) do
        if dialog.owner == resource or stopping then
            if not dialog.done and GetResourceState(dialog.resource) == 'started' then
                pcall(function() exports[dialog.resource]:closeInputDialog() end)
            end
            dialogs[id] = nil
        elseif dialog.resource == resource then dialog.done, dialog.result = true, nil end
    end
end)
