let Prelude = https://prelude.dhall-lang.org/v23.1.0/package.dhall

let benchmarks = ./benchmarks.dhall

let Types = ./types/package.dhall

let connectionPluginToText =
      \(cp : Types.ConnectionPlugin) ->
        merge { WinRM = "winrm", PSRP = "psrp" } cp

let renderProfile =
      \(p : Types.BenchmarkProfile) ->
        { name = p.name
        , description = p.description
        , forks = p.forks
        , connection_plugin = connectionPluginToText p.connectionPlugin
        , serial = p.serial
        , expect_failure = p.expectFailure
        }

in  Prelude.List.map
      Types.BenchmarkProfile
      { name : Text
      , description : Text
      , forks : Natural
      , connection_plugin : Text
      , serial : Optional Natural
      , expect_failure : Bool
      }
      renderProfile
      benchmarks
