# Sourced by scripts that build Xray *client* configs. Needs .env.local already loaded into the environment.
# vless_outbound <host> <universal|xhttp> <tag>  -> prints one Xray outbound as JSON.
# Secrets go through the environment, never through argv.
vless_outbound() {
  local host="$1" transport="$2" tag="$3" n addr_v pub_v sid_v v
  n="$(printf '%s' "$host" | tr '[:lower:]' '[:upper:]')"; addr_v="${n}_ADDR"; pub_v="${n}_REALITY_PUBLIC_KEY"; sid_v="${n}_SHORT_ID"
  for v in "$addr_v" "$pub_v" "$sid_v" VLESS_UUID REALITY_SERVER_NAME UNIVERSAL_PORT XHTTP_PORT XHTTP_PATH; do
    [[ -n "${!v:-}" ]] || { echo "$host: missing $v in .env.local" >&2; return 1; }
  done
  P_TAG="$tag" P_ADDR="${!addr_v}" P_PUB="${!pub_v}" P_SID="${!sid_v}" P_TRANSPORT="$transport" \
  P_UUID="$VLESS_UUID" P_SNI="$REALITY_SERVER_NAME" P_UPORT="$UNIVERSAL_PORT" P_XPORT="$XHTTP_PORT" P_XPATH="$XHTTP_PATH" \
  jq -n '
    (env.P_TRANSPORT == "xhttp") as $x
    | {
      tag: env.P_TAG,
      protocol: "vless",
      settings: ({
        address: env.P_ADDR,
        port: ((if $x then env.P_XPORT else env.P_UPORT end) | tonumber),
        id: env.P_UUID,
        encryption: "none"
      } + (if $x then {} else {flow: "xtls-rprx-vision"} end)),
      streamSettings: ({
        network: (if $x then "xhttp" else "raw" end),
        security: "reality",
        realitySettings: {serverName: env.P_SNI, fingerprint: "chrome", publicKey: env.P_PUB, shortId: env.P_SID, spiderX: ""}
      } + (if $x then {xhttpSettings: {path: env.P_XPATH, mode: "auto"}} else {} end))
    }'
}
