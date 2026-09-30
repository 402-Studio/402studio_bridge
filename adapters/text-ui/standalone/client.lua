local text

BridgeRegistry.register('textUI', 'standalone', {
    show = function(value)
        text = value
        AddTextEntry('402studio_bridge_text_ui', value)
        return true
    end,
    hide = function()
        text = nil
        return true
    end,
    isOpen = function() return text ~= nil, text end,
})

CreateThread(function()
    while true do
        if text then
            DisplayHelpTextThisFrame('402studio_bridge_text_ui', false)
        end
        Wait(text and 0 or 200)
    end
end)
