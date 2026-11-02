# release-controlplane

schryer's release board. `hourly-board.yml` grades what
[`schryer/release-state`](https://github.com/schryer/release-state) puts on the board and keeps
it in storage, for [release.schryer.eu](https://release.schryer.eu).
`nightly.yml` keeps what the state governs up to date, with pubkit's reusable nightly: one
pull request per repository, which you merge. It sends no Slack message.

The site itself is the same app as Sustenaut's, deployed from
[`Sustenaut/release-controlplane`](https://github.com/Sustenaut/release-controlplane)'s `k8s-schryer/`
into its own namespace on Sustenaut's server, with its own apps, sign-in, Secrets and storage tenant.
This repository holds what is schryer's own:

| What | |
|---|---|
| `apps/` | The manifests `pubkit github-app create` made the reader, state writer, protect and nightly apps from |
| `push-secrets.sh` | Puts the Secret `release-secrets` and the network policy into the namespace |
| `register-client.sh` | Adds the site to `schryer.eu`'s sign-in client, and puts it in the namespace as `release-oidc` |

Who may use the site is an email list, the secret `schryer-release-allowed-emails`, since the family
realm has no access page.
