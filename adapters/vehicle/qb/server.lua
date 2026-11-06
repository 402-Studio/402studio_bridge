local identities = {}
local generation = 0

local function plate(value)
    return type(value) == 'string' and value:match('^%s*(.-)%s*$') or ''
end

local function hash(value)
    value = tonumber(value)
    if not value or value % 1 ~= 0 or value < -2147483648 or value > 4294967295 then return nil end
    return value % 4294967296
end

local function identity(vehicle, settings)
    if GetResourceState(settings.resource) ~= 'started' or not DoesEntityExist(vehicle)
        or GetEntityType(vehicle) ~= 2 then return nil end
    local registration = plate(GetVehicleNumberPlateText(vehicle))
    if registration == '' then return nil end
    local model = hash(GetEntityModel(vehicle))
    if not model then return nil end
    local entry = identities[vehicle]
    if not entry or entry.plate ~= registration or entry.model ~= model then
        entry = { plate = registration, model = model, expires = 0 }
        identities[vehicle] = entry
    end
    return entry
end

local function readRow(vehicle, settings, entry, id)
    local requestGeneration = generation
    local condition = id and '`id` = ?' or '`plate` = ?'
    local ok, row = pcall(function()
        return exports[settings.resource]:single_async(
            'SELECT `id`, `citizenid`, `vehicle`, `hash`, `mods`, `plate` FROM `player_vehicles` WHERE '
                .. condition .. ' LIMIT 1',
            { id or entry.plate }
        )
    end)
    if not ok then
        if identities[vehicle] == entry then identities[vehicle] = nil end
        error(row, 0)
    end
    if requestGeneration ~= generation or identities[vehicle] ~= entry then return nil end
    if identity(vehicle, settings) ~= entry then
        if identities[vehicle] == entry then identities[vehicle] = nil end
        return nil
    end
    if type(row) ~= 'table' or plate(row.plate) ~= entry.plate then return nil end
    local rowId = tonumber(row.id)
    if not rowId or rowId < 1 or rowId % 1 ~= 0 or id and rowId ~= id then return nil end
    local model = type(row.vehicle) == 'string' and row.vehicle ~= ''
        and hash(joaat(row.vehicle)) or hash(row.hash)
    if model ~= entry.model then return nil end
    return row, rowId
end

local function savedRow(vehicle, id, settings)
    local entry = identity(vehicle, settings)
    if not entry then return nil end
    local row = readRow(vehicle, settings, entry, id)
    if not row and identities[vehicle] == entry then identities[vehicle] = nil end
    return row
end

BridgeRegistry.register('vehicle', 'qb', {
    id = function(vehicle, settings)
        local entry = identity(vehicle, settings)
        if not entry then return nil end
        if entry.pending then
            local result = Citizen.Await(entry.pending)
            if not result.ok then error(result.value, 0) end
            if identities[vehicle] ~= entry or identity(vehicle, settings) ~= entry then return nil end
            return result.value
        end
        if GetGameTimer() < entry.expires then return entry.id or nil end
        local pending = promise.new()
        entry.pending = pending
        local ok, id = pcall(function()
            local _, result = readRow(vehicle, settings, entry)
            return result
        end)
        entry.pending = nil
        if ok and identities[vehicle] == entry then
            entry.id = id or false
            entry.expires = GetGameTimer() + (id and 60000 or 15000)
        elseif ok then
            id = nil
        end
        pending:resolve({ ok = ok, value = id })
        if not ok then error(id, 0) end
        return id
    end,
    owner = function(vehicle, id, settings)
        local row = savedRow(vehicle, id, settings)
        if row and type(row.citizenid) == 'string' and row.citizenid ~= '' then return row.citizenid end
    end,
    properties = function(vehicle, id, settings)
        local row = savedRow(vehicle, id, settings)
        if not row then return nil end
        if row.mods == nil or row.mods == '' then return {} end
        local ok, properties = pcall(json.decode, row.mods)
        if ok and type(properties) == 'table' then return properties end
    end,
})

AddEventHandler('entityRemoved', function(vehicle)
    identities[vehicle] = nil
end)

AddEventHandler('onResourceStop', function(resource)
    if Config.Vehicles.adapter == 'qb' and resource == Config.Vehicles.resource then
        generation = generation + 1
        identities = {}
    end
end)
