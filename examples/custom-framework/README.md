# Custom framework example

Copy the `Config.CustomFramework` block from `config.lua` into the bridge configuration.

Set the resource name. Replace callback bodies with the custom framework API. Only `resource`, `getCore`, and `getPlayer` are required. Remove unused optional callbacks. Missing permission, economy, and notification callbacks use safe fallbacks.
