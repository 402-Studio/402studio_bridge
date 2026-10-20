fx_version 'cerulean'
game 'gta5'

name '402studio_bridge'
author '402-Studio'
description 'Shared framework services for 402STUDIO resources'
version '1.2.1'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/registry.lua',
}

client_scripts {
    'adapters/notify/**/client.lua',
    'adapters/progress/**/client.lua',
    'adapters/target/**/client.lua',
    'adapters/text-ui/**/client.lua',
    'adapters/context/**/client.lua',
    'client/interface.lua',
    'client/main.lua',
    'client/ui.lua',
    'client/callback.lua',
    'client/capture.lua',
    'client/vehicle-classes.lua',
}

server_scripts {
    'server/cdn-support.lua',
    'adapters/framework/**/server.lua',
    'adapters/inventory/**/server.lua',
    'adapters/vehicle/**/server.lua',
    'adapters/capture/**/server.lua',
    'adapters/cdn/**/server.lua',
    'server/inventory.lua',
    'server/vehicle-classes.lua',
    'server/vehicle.lua',
    'server/callback.lua',
    'server/capture.lua',
    'server/main.lua',
    'server/cdn.lua',
}

dependencies {
    'ox_lib',
}

escrow_ignore {
    '*',
    '**/*',
}
