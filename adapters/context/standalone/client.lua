local menus, current, selected = {}, nil, 1

local function hide(onExit)
    local menu = menus[current]
    current = nil
    if onExit and menu and BridgeRegistry.callable(menu.onExit) then menu.onExit() end
    return true
end

BridgeRegistry.register('context', 'standalone', {
    register = function(menu) menus[menu.id] = menu; return true end,
    show = function(id)
        if not menus[id] then return false end
        current, selected = id, 1
        return true
    end,
    hide = hide,
    getOpen = function() return current end,
})

local function draw(text, y)
    SetTextFont(0)
    SetTextScale(0.0, 0.35)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(0.05, y)
end

CreateThread(function()
    while true do
        local menu = menus[current]
        if menu then
            DisableControlAction(0, 172, true)
            DisableControlAction(0, 173, true)
            DisableControlAction(0, 191, true)
            DisableControlAction(0, 177, true)
            draw(menu.title, 0.15)
            local first = math.max(1, selected - 5)
            for i = first, math.min(#menu.options, first + 9) do
                local option = menu.options[i]
                draw((i == selected and '> ' or '  ') .. (option.disabled and '~c~' or '') .. option.title, 0.19 + (i - first) * 0.035)
            end
            local option = menu.options[selected]
            if option and option.description then draw(option.description, 0.57) end
            if IsDisabledControlJustPressed(0, 172) then selected = math.max(1, selected - 1) end
            if IsDisabledControlJustPressed(0, 173) then selected = math.min(#menu.options, selected + 1) end
            if IsDisabledControlJustPressed(0, 177) and menu.canClose ~= false then hide(true) end
            if IsDisabledControlJustPressed(0, 191) and option and not option.disabled and not option.readOnly then
                if option.menu then current, selected = option.menu, 1
                else
                    hide(false)
                    if BridgeRegistry.callable(option.onSelect) then option.onSelect(option.args) end
                    if option.event then TriggerEvent(option.event, option.args) end
                    if option.serverEvent then TriggerServerEvent(option.serverEvent, option.args) end
                end
            end
        end
        Wait(menu and 0 or 200)
    end
end)
