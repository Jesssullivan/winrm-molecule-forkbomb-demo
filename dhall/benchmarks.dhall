let Types = ./types/package.dhall

let profiles
    : List Types.BenchmarkProfile
    = [ -- Baseline: serial execution, guaranteed safe
        { name = "serial-safe"
        , description = "Serial execution (serial=1, forks=5) - safe baseline"
        , forks = 5
        , connectionPlugin = Types.ConnectionPlugin.WinRM
        , serial = Some 1
        , expectFailure = False
        }
      , -- Normal parallel: default forks, should work with default quotas
        { name = "parallel-5"
        , description = "Default parallel (forks=5) - should work with default quotas"
        , forks = 5
        , connectionPlugin = Types.ConnectionPlugin.WinRM
        , serial = None Natural
        , expectFailure = False
        }
      , -- Moderate parallel: may hit quota limits
        { name = "parallel-10"
        , description = "Moderate parallel (forks=10) - may hit MaxShellsPerUser"
        , forks = 10
        , connectionPlugin = Types.ConnectionPlugin.WinRM
        , serial = None Natural
        , expectFailure = False
        }
      , -- Heavy parallel: likely to hit quota limits
        { name = "parallel-20"
        , description = "Heavy parallel (forks=20) - likely quota exhaustion"
        , forks = 20
        , connectionPlugin = Types.ConnectionPlugin.WinRM
        , serial = None Natural
        , expectFailure = True
        }
      , -- Forkbomb: guaranteed quota exhaustion with default Windows settings
        { name = "forkbomb-50"
        , description = "FORKBOMB (forks=50) - guaranteed quota exhaustion and potential AD lockout"
        , forks = 50
        , connectionPlugin = Types.ConnectionPlugin.WinRM
        , serial = None Natural
        , expectFailure = True
        }
      , -- PSRP comparison at moderate parallelism
        { name = "psrp-parallel-10"
        , description = "PSRP connection (forks=10) - better connection pooling"
        , forks = 10
        , connectionPlugin = Types.ConnectionPlugin.PSRP
        , serial = None Natural
        , expectFailure = False
        }
      , -- PSRP at high parallelism
        { name = "psrp-parallel-20"
        , description = "PSRP connection (forks=20) - tests PSRP Runspace Pool advantage"
        , forks = 20
        , connectionPlugin = Types.ConnectionPlugin.PSRP
        , serial = None Natural
        , expectFailure = False
        }
      ]

in  profiles
