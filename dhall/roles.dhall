let Types = ./types/package.dhall

let roles
    : List Types.RoleManifest
    = [ { name = "winrm_quota_config"
        , phase = 1
        , description = "Configure WinRM shell quotas on Windows targets (admin toggle)"
        , tags = [ "winrm-quota", "admin-toggle", "phase-1" ]
        , dependsOn = [] : List Text
        , safeToRunParallel = False
        }
      , { name = "winrm_session_cleanup"
        , phase = 2
        , description = "Detect and terminate stale WinRM sessions with scheduled cleanup"
        , tags = [ "winrm-cleanup", "session-monitor", "phase-2" ]
        , dependsOn = [ "winrm_quota_config" ]
        , safeToRunParallel = False
        }
      , { name = "winrm_monitoring"
        , phase = 2
        , description = "WinRM observability: shell enumeration metrics, event log forwarding, Grafana dashboard"
        , tags = [ "winrm-monitoring", "observability", "phase-2" ]
        , dependsOn = [ "winrm_quota_config" ]
        , safeToRunParallel = False
        }
      , { name = "firewall_rules"
        , phase = 3
        , description = "Configure Windows firewall rules for IIS and WinRM access"
        , tags = [ "firewall", "network", "phase-3" ]
        , dependsOn = [] : List Text
        , safeToRunParallel = True
        }
      , { name = "iis_site"
        , phase = 3
        , description = "Deploy IIS site with SPA displaying repo contents from GitHub"
        , tags = [ "iis-site", "demo-payload", "phase-3" ]
        , dependsOn = [ "firewall_rules" ]
        , safeToRunParallel = True
        }
      ]

in  roles
