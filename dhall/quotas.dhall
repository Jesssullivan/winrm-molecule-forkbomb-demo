let Types = ./types/package.dhall

-- Windows default WinRM quotas (the values that cause the forkbomb)
let windowsDefault
    : Types.WinRMQuota
    = { name = "windows-default"
      , description = "Factory Windows WinRM defaults - will cause forkbomb at forks>30"
      , maxShellsPerUser = 30
      , maxConcurrentUsers = 10
      , maxProcessesPerShell = 25
      , idleTimeoutMs = 7200000
      , maxMemoryPerShellMB = 1024
      , maxConcurrentOperationsPerUser = 1500
      }

-- Safe elevated quotas for normal automation
let safe
    : Types.WinRMQuota
    = { name = "safe"
      , description = "Elevated quotas for safe parallel Ansible automation"
      , maxShellsPerUser = 100
      , maxConcurrentUsers = 25
      , maxProcessesPerShell = 50
      , idleTimeoutMs = 300000
      , maxMemoryPerShellMB = 2048
      , maxConcurrentOperationsPerUser = 4294967295
      }

-- Stress test quotas for benchmarking maximum parallelism
let stress
    : Types.WinRMQuota
    = { name = "stress"
      , description = "Maximum quotas for stress testing - use with caution"
      , maxShellsPerUser = 2147483647
      , maxConcurrentUsers = 100
      , maxProcessesPerShell = 2000000000
      , idleTimeoutMs = 600000
      , maxMemoryPerShellMB = 4096
      , maxConcurrentOperationsPerUser = 4294967295
      }

in  { windowsDefault, safe, stress }
