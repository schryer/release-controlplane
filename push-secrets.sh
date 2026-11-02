#!/usr/bin/env bash
# Puts the site's secrets into the cluster on Sustenaut's k3s server: the Secret
# release-secrets and the network policy (admin/), in namespace release-schryer. Run it
# from the repository root through with-secrets, whenever one of them changes:
#
#   ./with-secrets ./push-secrets.sh
#
# From Bitwarden (which with-secrets exports in upper case):
#   schryer-release-reader-app-id, -app-key, -installation-id         the reader app
#   schryer-release-state-writer-app-id, -app-key, -installation-id   the state writer app
#   schryer-release-cookie-secret   oauth2-proxy's cookie secret: openssl rand -base64 32 | tr '+/' '-_'
#   schryer-release-allowed-emails  who may use the site, separated by commas
# Not here: the sign-in client (the Secret release-oidc), which register-client.sh puts in.
# They travel to the server inside the SSH connection, never on a command line. The
# pods read them at start: after a change, restart them with
#   ssh root@sustenaut k3s kubectl -n release-schryer rollout restart deployment/app deployment/oauth2-proxy
set -euo pipefail
root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
server=${SUSTENAUT_SERVER:-sustenaut}

for name in SCHRYER_RELEASE_READER_APP_ID SCHRYER_RELEASE_READER_APP_KEY SCHRYER_RELEASE_READER_INSTALLATION_ID \
  SCHRYER_RELEASE_STATE_WRITER_APP_ID SCHRYER_RELEASE_STATE_WRITER_APP_KEY SCHRYER_RELEASE_STATE_WRITER_INSTALLATION_ID \
  SCHRYER_RELEASE_COOKIE_SECRET SCHRYER_RELEASE_ALLOWED_EMAILS; do
  if [ -z "${!name:-}" ]; then
    echo "$name is not set: run this through ./with-secrets, and check the secret is in Bitwarden." >&2
    exit 1
  fi
done

# oauth2-proxy takes URL-safe base64 of 16, 24 or 32 bytes, or a value that long as it
# stands, and otherwise crashes at start.
cookie_bytes=$(printf '%s' "$SCHRYER_RELEASE_COOKIE_SECRET" | tr -d '=' | tr -- '-_' '+/' | { base64 -d 2>/dev/null || true; } | wc -c)
case "$SCHRYER_RELEASE_COOKIE_SECRET" in
  *[+/]*) cookie_bytes=0 ;;
esac
if [ "$cookie_bytes" != 16 ] && [ "$cookie_bytes" != 24 ] && [ "$cookie_bytes" != 32 ]; then
  case "${#SCHRYER_RELEASE_COOKIE_SECRET}" in
    16 | 24 | 32) ;;
    *)
      echo "schryer-release-cookie-secret won't work: make it with: openssl rand -base64 32 | tr '+/' '-_'" >&2
      exit 1
      ;;
  esac
fi

emails_file=$(printf '%s' "$SCHRYER_RELEASE_ALLOWED_EMAILS" | tr ',' '\n' | tr -d ' ' | tr '[:upper:]' '[:lower:]')
b64() { printf '%s' "$1" | base64 -w0; }

# shellcheck disable=SC2087 # expanded here on purpose: the values go in the SSH stream
ssh "root@$server" 'k3s kubectl apply -f -' <<YAML
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: release-secrets
  namespace: release-schryer
data:
  reader-app-id: $(b64 "$SCHRYER_RELEASE_READER_APP_ID")
  reader-app-key: $(b64 "$SCHRYER_RELEASE_READER_APP_KEY")
  reader-installation-id: $(b64 "$SCHRYER_RELEASE_READER_INSTALLATION_ID")
  writer-app-id: $(b64 "$SCHRYER_RELEASE_STATE_WRITER_APP_ID")
  writer-app-key: $(b64 "$SCHRYER_RELEASE_STATE_WRITER_APP_KEY")
  writer-installation-id: $(b64 "$SCHRYER_RELEASE_STATE_WRITER_INSTALLATION_ID")
  cookie-secret: $(b64 "$SCHRYER_RELEASE_COOKIE_SECRET")
  allowed-emails: $(b64 "$SCHRYER_RELEASE_ALLOWED_EMAILS")
  allowed-emails-file: $(b64 "$emails_file")
---
$(cat "$root/admin/network-policy.yaml")
YAML
