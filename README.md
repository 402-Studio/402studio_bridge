# 402STUDIO Bridge

Shared services for ESX, QBCore, Qbox, and standalone resources. Provides notifications, player identity, character name, primary job, permissions, balances, charging, and payouts through one versioned API.

## Install

Start the selected framework, then `402studio_bridge`, then the resources using it. Set framework providers in `config.lua` and add `dependency '402studio_bridge'` to consumer manifests. Resources named `402studio_*` with manifest author `402-Studio` are trusted automatically. Other resources use the replicated `402studio_bridge:allowedResources` convar.

```cfg
setr 402studio_bridge:allowedResources "my_resource,another_resource"
ensure 402studio_bridge
ensure my_resource
```

Auto detection prioritizes Qbox, QBCore, then ESX. Framework connections are cached. Player data and permissions are read when requested. Resource lifecycle events invalidate connections; a stopped provider blocks economy operations until available again. The bridge runs on demand.

Custom frameworks use one object in `config.lua`. Enabling it overrides built-in framework selection. No adapter or manifest changes are needed.

```lua
Config.CustomFramework = {
    enabled = true,
    resource = 'my_framework',
    accounts = {cash = 'wallet', bank = 'bank'},

    getCore = function(resource)
        return exports[resource]:GetCore()
    end,

    getPlayer = function(core, source)
        local player = core:GetPlayer(source)
        if not player then return end
        return {
            identifier = player.id,
            name = player.name,
            job = player.job,
        }
    end,

    hasGroup = function(core, source, groups)
        local player = core:GetPlayer(source)
        return player and groups[player.group] == true
    end,

    getBalance = function(core, source, account)
        local player = core:GetPlayer(source)
        return player and player:GetMoney(account) or 0
    end,

    removeMoney = function(core, source, account, amount, reason)
        local player = core:GetPlayer(source)
        return player and player:RemoveMoney(account, amount, reason) == true
    end,

    addMoney = function(core, source, account, amount, reason)
        local player = core:GetPlayer(source)
        return player and player:AddMoney(account, amount, reason) == true
    end,

    notify = function(resource, message, kind, duration, title)
        exports[resource]:Notify(message, kind, duration, title)
        return true
    end,
}
```

Only `resource`, `getCore`, and `getPlayer` are required. `getPlayer` returns normalized player data directly. Missing `hasGroup` denies framework groups. Missing money callbacks disable the custom economy. Missing `notify` uses the GTA feed. Copy the complete block from `examples/custom-framework/config.lua`.

Standalone provides license identity and ACE permissions. Resources offering free services explicitly disable their economy feature. Money requires an economy adapter.

## Server API, version 1

Exports return `result, errorCode`. Check explicit `true` for mutations and permissions. A denied caller receives `nil, 'forbidden_resource'`. Provider failures return an error instead of granting access or payment success.

| Export | Result |
| --- | --- |
| `GetStatus()` | Framework state plus status for framework, inventory, and vehicle modules |
| `GetPlayer(source)` | `{source, identifier, name, job}`; job includes `name`, `label`, `grade`, `onDuty` |
| `HasPermission(source, rule)` | Boolean |
| `GetBalance(source, account)` | Integer balance |
| `Charge(source, amount, accounts, reason)` | Boolean; debits accounts in order |
| `AddMoney(source, amount, account, reason)` | Boolean |
| `GetVehicleId(vehicle)` | Persistent numeric vehicle ID |
| `GetVehicleOwner(source, vehicle)` | Raw owner identifier, matching `GetPlayer().identifier` |
| `GetVehicleProperties(vehicle)` | Saved vehicle properties |
| `GetItemCount(source, item)` | Inventory item count |
| `RemoveItem(source, item, count)` | Boolean; quantity defaults to one |
| `AddItem(source, item, count)` | Boolean; quantity defaults to one |

```lua
local bridge = exports['402studio_bridge']
local allowed = bridge:HasPermission(source, {
    mode='admin', ace='my_resource.admin', groups={admin=true},
})
if allowed ~= true then return end

local paid, err = bridge:Charge(source, 500, {'cash', 'bank'}, 'service')
if paid ~= true then return end
```

Permission modes are `all`, `ace`, `admin`, and `job`. Admin accepts a specific ACE or enabled permission groups. Qbox admin groups use ACE `group.<name>`; job and gang membership are separate from admin access. Job rules accept `{jobs={mechanic=true}}` or minimum grades such as `{jobs={mechanic=2}, onDuty=true}`.

Account names are mapped in `Config.Accounts`. Amounts must be positive integers within `MaximumTransaction`. Duplicate accounts are rejected. Charges check the whole balance before debiting and refund earlier successful debits if a later debit fails. A failed refund returns `refund_failed` and records a server log for reconciliation. Framework money APIs and server crashes determine the limits of cross-account compensation.

Only allowlisted server resources can call exports. Each product must validate its own network requests, permission, distance, ownership, price, and request frequency before calling the bridge. Server code sets payment amounts. Money mutations are serialized per player across callers. Reasons include the invoking resource name.

## Adapters

Adapters follow one path pattern:

```text
adapters/<module>/<provider>/<context>.lua
```

Built-in providers use `adapters/framework`, `adapters/inventory`, `adapters/vehicle`, `adapters/notify`, `adapters/progress`, and `adapters/target`. Custom frameworks use only `Config.CustomFramework`.

Register every adapter through `BridgeRegistry.register(kind, name, adapter)`. Supported kinds are `framework`, `inventory`, `vehicle`, `notify`, `progress`, and `target`. The registry validates each contract during resource startup.

Each adapter implements `connect(resource)`, `player(core, source)`, `data(player)`, `group(core, player, source, groups)`, `balance(core, player, source, account)`, `remove(core, player, source, account, amount, reason)`, and `add` with the same arguments as `remove`. Operations must finish synchronously. Mutations return true only after applying the exact amount; false must leave the account unchanged. Return fresh normalized data from `data`.

`Config.Inventory` selects an adapter and resource name. The supplied `ox` adapter supports Ox Inventory and renamed installations. Inventory adapters implement `count(resource, source, item)`, `remove(resource, source, item, count)`, and `add(resource, source, item, count)`.

`Config.Vehicles` selects the vehicle adapter, resource, server state key, and owner field. The supplied `qbox` adapter reads `GetPlayerVehicle(id)` and validates the saved model against the entity. Vehicle adapters implement `id(vehicle, settings)`, `owner(vehicle, id, settings)`, and `properties(vehicle, id, settings)`. Owner identifiers use the same format as `GetPlayer().identifier`.

`Config.Notify` selects a notification adapter. `auto` follows the active framework. Set `adapter` and optional `resource` to use any notification resource independently.

`Config.Progress` selects the progress adapter. `auto` picks the first started resource in `priority`, falling back to `standalone`, which shows nothing. Supplied adapters are `ox` for `ox_lib` and `qb` for `progressbar`. Progress adapters implement `start(settings, resource)`, `cancel(id, resource)`, and `active()`. `start` blocks inside the bridge and returns true when the bar finished, false when the player cancelled, and nil when no bar was shown.

`Config.Target` selects the targeting adapter. `auto` picks the first started resource in `priority`, falling back to `none`. Supplied adapters are `ox` for `ox_target` and `qb` for `qb-target`. Target adapters implement `addVehicle(options, resource)` and `removeVehicle(names, resource)`. Each option carries `name`, `label`, `icon`, `distance`, `bones`, `canInteract(entity)`, and `onSelect(entity)`. Adapters that cannot filter by bone ignore that field and target the whole vehicle.

Resources own their schemas, persistence, item definitions, and gameplay rules. Database dependencies belong in the resource that stores the data.

## Client API

`Notify(message, type, duration, title)` uses the active framework notification system. Standalone mode uses the GTA feed.

`StartProgress(settings)` returns a handle, or nil when no progress provider is available. Settings take `duration`, `label`, `canCancel`, `useWhileDead`, `position`, and `disable`. Exports cannot yield, so the bar runs inside the bridge and the caller polls `ProgressResult(handle)`, which returns `done, cancelled`. `CancelProgress(handle)` stops a running bar and `ProgressActive()` reports whether any bar is on screen.

`AddVehicleTarget(options)` registers vehicle target options through the active targeting resource and `RemoveVehicleTarget(names)` removes them. `TargetAvailable()` reports whether a targeting provider is present, so callers can skip registration.

Client `GetStatus()` returns the API version, active framework, and the notification, progress, and target module states.

## License

MIT. See `LICENSE`.
