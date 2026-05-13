## OIDC Example

This is a minimal onboarding app for the local ESS cluster. The app is a MAS
OAuth client. MAS is the Google OIDC relying party and the Matrix token issuer.

The proof of concept stays isolated in this directory.

### Google setup

Create a Google Cloud OAuth client:

- Application type: `Web application`
- Authorized JavaScript origins: `https://account.ess.localhost`
- Authorized redirect URI:
  - `https://account.ess.localhost/upstream/callback/01HFS6S2SVAR7Y7QYMZJ53ZAGZ`

Google redirects only to MAS. `oidc-example` never receives Google tokens.

### Run with Tilt

Add this host entry if it is not already present:

```text
127.0.0.1 oidc.ess.localhost
```

Create a local ignored `.env` file, then run Tilt from this directory:

```bash
cp .env.example .env
# edit .env with your Google OAuth client id/secret
tilt up
```

The app is available at `https://oidc.ess.localhost/`.

### Flow

1. User opens `oidc-example`.
2. `oidc-example` redirects to MAS `/oauth2/authorize`.
3. MAS authenticates the user through Google / Cloud Identity.
4. MAS creates or links the Matrix account according to its upstream OIDC config.
5. MAS redirects back to `https://oidc.ess.localhost/callback` with an authorization code.
6. `oidc-example` exchanges that code with MAS for a MAS-issued Matrix access token.
7. `oidc-example` calls Synapse `/_matrix/client/v3/account/whoami` with that token and displays the response.

This validates the production-style chain:

```text
oidc-example -> MAS -> Google -> MAS -> oidc-example -> Synapse
```

### MAS behavior

The Tilt-managed MAS overlay:

- disables MAS password auth
- configures Google as the only upstream identity provider
- registers `oidc-example` as a confidential MAS OAuth client
- authorizes the app callback `https://oidc.ess.localhost/callback`

No MAS Admin API token is used in the normal app flow.
