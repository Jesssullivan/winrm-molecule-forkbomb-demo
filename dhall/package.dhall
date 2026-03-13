let Types = ./types/package.dhall

let hosts = ./hosts.dhall

let quotas = ./quotas.dhall

let benchmarks = ./benchmarks.dhall

let roles = ./roles.dhall

in  { Types, hosts, quotas, benchmarks, roles }
