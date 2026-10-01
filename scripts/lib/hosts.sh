# Sourced by scripts that read per-host values from .env.local.
# Host names in hosts/hosts.json look like <datacenter>-<country>-n-<number> (aeza-de-n-1);
# their variables are the upper-cased name with "-" replaced by "_" (AEZA_DE_N_1_ADDR).
host_prefix() { printf '%s' "$1" | tr 'a-z-' 'A-Z_'; }
