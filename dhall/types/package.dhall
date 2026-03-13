let Host = ./Host.dhall

let WinRMQuota = ./WinRMQuota.dhall

let Benchmark = ./BenchmarkProfile.dhall

let RoleManifest = ./RoleManifest.dhall

in  { Host
    , WinRMQuota
    , BenchmarkProfile = Benchmark.BenchmarkProfile
    , ConnectionPlugin = Benchmark.ConnectionPlugin
    , RoleManifest
    }
