lib.callback.register('402studio_bridge:vehicleClasses', function()
    local models = GetAllVehicleModels()
    local classes = {}
    for index = 1, math.min(#models, 32768) do
        local model = models[index]
        local class = GetVehicleClassFromName(model)
        if type(class) == 'number' and class % 1 == 0 and class >= 0 and class <= 22 then
            classes[GetHashKey(model) % 4294967296] = class
        end
    end
    return classes
end)
