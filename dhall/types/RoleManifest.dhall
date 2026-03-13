let RoleManifest =
      { name : Text
      , phase : Natural
      , description : Text
      , tags : List Text
      , dependsOn : List Text
      , safeToRunParallel : Bool
      }

in  RoleManifest
