local allowedResources = {}
for resource in GetConvar('402studio_bridge:allowedResources', ''):gmatch('[^,%s]+') do
    allowedResources[resource] = true
end

Config = {
    Framework = 'auto',
    Resources = {
        esx = 'es_extended',
        qb = 'qb-core',
        qbox = 'qbx_core',
    },
    Priority = { 'qbox', 'qb', 'esx' },
    CustomFramework = { enabled = false },
    FirstParty = { prefix = '402studio_', author = '402-Studio' },
    AllowedResources = allowedResources,
    Notify = { adapter = 'auto' },
    Progress = {
        adapter = 'auto',
        resources = { ox = 'ox_lib', qb = 'progressbar' },
        priority = { 'ox', 'qb' },
    },
    Target = {
        adapter = 'auto',
        resources = { ox = 'ox_target', qb = 'qb-target' },
        priority = { 'ox', 'qb' },
    },
    Inventory = { adapter = 'ox', resource = 'ox_inventory' },
    Vehicles = {
        adapter = 'qbox',
        resource = 'qbx_vehicles',
        stateKey = 'vehicleid',
        ownerField = 'citizenid',
    },
    Accounts = {
        cash = { esx = 'money', qb = 'cash', qbox = 'cash' },
        bank = { esx = 'bank', qb = 'bank', qbox = 'bank' },
    },
    MaximumTransaction = 10000000,
}
