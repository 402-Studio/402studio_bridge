fx_version 'cerulean'
game 'gta5'

name '402studio_bridge'
author '402-Studio'
description 'Shared framework services for 402STUDIO resources'
version '1.0.0'

shared_scripts {
    'config.lua',
    'shared/registry.lua',
}

client_scripts {
    'adapters/notify/**/client.lua',
    'adapters/progress/**/client.lua',
    'adapters/target/**/client.lua',
    'client/interface.lua',
    'client/main.lua',
}

server_scripts {
    'adapters/framework/**/server.lua',
    'adapters/inventory/**/server.lua',
    'adapters/vehicle/**/server.lua',
    'server/inventory.lua',
    'server/vehicle.lua',
    'server/main.lua',
}

escrow_ignore {
    '*',
    '**/*',
}
