let ConnectionPlugin = < WinRM | PSRP >

let BenchmarkProfile =
      { name : Text
      , description : Text
      , forks : Natural
      , connectionPlugin : ConnectionPlugin
      , serial : Optional Natural
      , expectFailure : Bool
      }

in  { BenchmarkProfile, ConnectionPlugin }
