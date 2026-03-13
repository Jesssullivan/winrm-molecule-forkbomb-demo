let Types = ./types/package.dhall

let vmnode852
    : Types.Host
    = { hostname = "vmnode852"
      , fqdn = "vmnode852.bcis.bates.edu"
      , environment = "development"
      , tunnelPort = 15852
      , winrmPort = 5986
      , osVersion = "Windows Server 2022"
      }

in  { vmnode852 }
