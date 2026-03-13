let quotas = ./quotas.dhall

in  { windows_default = quotas.windowsDefault
    , safe = quotas.safe
    , stress = quotas.stress
    }
