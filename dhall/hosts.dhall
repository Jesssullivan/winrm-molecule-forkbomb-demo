let Types = ./types/package.dhall

-- Example target host. Customize for your environment.
let target
    : Types.Host
    = { hostname = "win-target"
      , fqdn = "win-target.example.com"
      , environment = "development"
      , tunnelPort = 15986
      , winrmPort = 5986
      , osVersion = "Windows Server 2022"
      }

in  { target }
