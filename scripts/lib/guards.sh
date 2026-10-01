# Sourced by scripts that touch a server address.
# refuse_placeholder <addr-or-user@addr>: fails for RFC 5737 documentation addresses (the .env.example defaults).
refuse_placeholder() {
  local addr="${1#*@}"
  case "$addr" in
    203.0.113.*|198.51.100.*|192.0.2.*) echo "Refusing documentation/placeholder address: $addr (set the real address in .env.local)" >&2; return 1 ;;
  esac
}
