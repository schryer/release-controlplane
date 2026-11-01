#!/usr/bin/env bash
# Adds release.schryer.eu to schryer.eu's sign-in client in auth.sustenaut.eu's family realm,
# and puts the client into the cluster as the Secret release-oidc (namespace
# release-schryer), which oauth2-proxy signs in with. schryer.eu has one client, kept on
# the photos server (schryer-eu-infra's scripts/photos/share/portal/register.py), and
# each site on the domain adds its redirect URIs to it. Its secret goes from that server to
# this cluster's through this script's pipe: it is never printed or written here.
#
# Run it from the repository root, signed in to Sustenaut's tailnet, as often as you like:
#
#   ./register-client.sh
#
# Then restart oauth2-proxy if the client changed (the script says how).
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
host=release.schryer.eu
state=/root/.config/share-portal
server=${SUSTENAUT_SERVER:-sustenaut}
# Beside this repository, or AUTH= and SCHRYER_EU_INFRA= their paths.
register_app="${AUTH:-$root/../auth}/register-app.py"
infra="${SCHRYER_EU_INFRA:-$root/../schryer-eu-infra}"
[ -f "$register_app" ] || { echo "no $register_app: clone Sustenaut/auth beside this repository or set AUTH" >&2; exit 1; }
photos=${PHOTOS_IP:-$(terraform -chdir="$infra" output -raw photos_server_ipv4)}

registration="$(ssh "root@$photos" "python3 -I - --state-dir $state --auth https://auth.sustenaut.eu/realms/family \
  --domain schryer.eu --redirect https://$host/oauth2/callback --logout https://$host/" < "$register_app")"
status="$(jq -r .status <<<"$registration")"
if [ "$status" != ok ] && [ "$status" != registered ]; then
  echo "schryer.eu's client didn't take $host: $(jq -r '.message // .status' <<<"$registration")" >&2
  exit 1
fi

# Read on the photos server, and applied on Sustenaut's: the secret stays in the pipe.
# shellcheck disable=SC2029
ssh "root@$photos" "python3 -I - $state/client.json" <<'PY' | ssh "root@$server" 'k3s kubectl apply -f -'
import base64, json, sys
client = json.load(open(sys.argv[1]))
b64 = lambda v: base64.b64encode(v.encode()).decode()
print(f"""apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: release-oidc
  namespace: release-schryer
data:
  client-id: {b64(client["client_id"])}
  client-secret: {b64(client["client_secret"])}""")
PY
echo "If it changed, restart oauth2-proxy:"
echo "  ssh root@$server k3s kubectl -n release-schryer rollout restart deployment/oauth2-proxy"
