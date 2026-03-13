let WinRMQuota =
      { name : Text
      , description : Text
      , maxShellsPerUser : Natural
      , maxConcurrentUsers : Natural
      , maxProcessesPerShell : Natural
      , idleTimeoutMs : Natural
      , maxMemoryPerShellMB : Natural
      , maxConcurrentOperationsPerUser : Natural
      }

in  WinRMQuota
