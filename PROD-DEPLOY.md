# qwriter — Production Deploy Playbook

End-to-end runbook for getting the rebuild live on Cloudflare + a real
backend host. Cumulative work across Phases 0–7 is already in the repo;
Phase 8 is *almost entirely deploy work* — the only code changes are the
cookie `Domain=` env hook (already in `auth.rs`) and the CSRF helper module
(`controllers/csrf.rs`).

---

## Topology

```
                              ┌─────────────────────────────────┐
                              │       Cloudflare DNS/CDN        │
                              │       (orange-cloud all)        │
                              └─────────────────────────────────┘
                                          │
       ┌──────────────────────────────────┼──────────────────────────────────┐
       │                                  │                                  │
       ▼                                  ▼                                  ▼
┌──────────────┐                  ┌──────────────────┐              ┌────────────────┐
│  qwriter.com │                  │ app.qwriter.com  │              │ tokens.qwriter │
│              │                  │                  │              │     .com       │
│  CF Pages    │                  │  Loco backend    │              │  CF Pages      │
│  (Astro      │                  │  (Rust binary)   │              │  (tokens.css)  │
│   static)    │                  │  + Postgres      │              │                │
│              │                  │  + SMTP          │              │                │
│ qwriter-     │                  │  qwriter repo,   │              │ qwriter-tokens │
│ marketing    │                  │  same one we've  │              │ repo           │
│ repo         │                  │  been building   │              │                │
└──────────────┘                  └──────────────────┘              └────────────────┘
```

Three repos, three CF projects (two CF Pages, one origin behind CF proxy),
one shared `tokens.css` URL consumed by both consumer apps.

---

## Required environment variables (backend)

Set these on the backend host. **No defaults are usable in prod.**

| Var | Example | Purpose |
|---|---|---|
| `LOCO_ENV` | `production` | Activates Secure cookies + JWT secret guard |
| `JWT_SECRET` | `openssl rand -base64 64 \| tr -d '\n'` | Token signing — MUST be base64-decodable |
| `COOKIE_DOMAIN` | `.qwriter.com` | Cross-subdomain cookie (omit in dev) |
| `DATABASE_URL` | `postgres://qw:pw@db:5432/qwriter` | Postgres in prod (SQLite for dev only) |
| `PUBLIC_DOMAIN` | `https://app.qwriter.com` | Used in Stripe success/cancel URLs |
| `OPENAI_API_KEY` | `sk-…` | Generation. Without it, fallback is used. |
| `CRAWLCRAWL_API_KEY` | `crk_…` | Sources feature. Without it, /sources scans return errors. |
| `STRIPE_SECRET_KEY` | `sk_live_…` | Billing |
| `STRIPE_WEBHOOK_SECRET` | `whsec_…` | Webhook signature verification (mandatory) |
| `STRIPE_PRICE_ID_PRO` | `price_…` | Pro tier price id |
| `STRIPE_PRICE_ID_UNLIMITED` | `price_…` | Unlimited tier price id |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASSWORD` | Resend / SendGrid creds | Magic links + password resets |
| `RUST_LOG` | `info` | Trace level (use `info,copyai=debug` to see app-level details) |

Boot will abort if `LOCO_ENV != development/test` and `JWT_SECRET` is missing
or contains the dev placeholder — see [`src/bin/main.rs`](copyai_remote/src/bin/main.rs).

---

## Order of operations

Eight steps; the first three are independent and can run in parallel.

### 1. Deploy `qwriter-tokens` to CF Pages (10 min)

```bash
cd qwriter-tokens
git init && git add -A && git commit -m "v1 tokens"
# push to GitHub
```

CF dashboard → Pages → Create project → Connect repo → Build settings:

- **Build command:** *(none)*
- **Build output directory:** `/`
- **Custom domain:** `tokens.qwriter.com`

Page rules (already in `_headers`): immutable cache on `/v*/*`.

Smoke: `curl -I https://tokens.qwriter.com/v1/tokens.css` should return
`Cache-Control: public, max-age=31536000, immutable`.

### 2. Deploy `qwriter-marketing` to CF Pages (10 min)

```bash
cd qwriter-marketing
git init && git add -A && git commit -m "Initial marketing site"
# push to GitHub
```

CF Pages settings:

- **Build command:** `npm run build`
- **Output directory:** `dist`
- **Node version:** `20` (via env var `NODE_VERSION=20`)
- **Env vars:** `PUBLIC_APP_BASE=https://app.qwriter.com`
- **Custom domains:** `qwriter.com` (primary), `www.qwriter.com` (redirect to apex)

Smoke: `curl -I https://qwriter.com/` returns 200; `/login` posts to
`https://app.qwriter.com/auth/login` (view source).

### 3. Provision the backend host (30 min)

The Loco binary is a single static executable + the `templates/`,
`static/`, and `config/` directories. Choose one:

| Host | Pros | Cons |
|---|---|---|
| **Fly.io** | Easiest, edge regions, free tier | Volume mount for SQLite ($) |
| **Render** | Postgres add-on, push-to-deploy | $7/mo minimum |
| **Hetzner CX11** | $4/mo, full control | You manage TLS + systemd |
| **Existing VM** (`172.16.70.25`) | Already running | Replace what's there |

Recommended for the next 12 months: **Fly.io + Fly Postgres**. After that
move to a beefier VM when MRR justifies.

#### Build the release binary

```bash
cd qwriter/copyai_remote
# Restore the real Stripe controller (see step 6 below) before this build.
cargo build --release
# Output: target/release/copyai-cli (statically linked + templates need to ship alongside)
```

`Dockerfile.prod` for Fly/Render:

```dockerfile
FROM rust:1.83 AS build
WORKDIR /app
COPY . .
RUN cargo build --release --bin copyai-cli

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /app/target/release/copyai-cli ./
COPY config/ ./config/
COPY templates/ ./templates/
COPY static/ ./static/
ENV LOCO_ENV=production
EXPOSE 5150
CMD ["./copyai-cli", "start"]
```

### 4. Run migrations on the prod database (5 min)

```bash
DATABASE_URL=postgres://… ./copyai-cli db migrate
```

All eight migrations apply cleanly. Verify with `SELECT name FROM sea_orm_migrations`.

### 5. Configure CF DNS + orange-cloud the backend (10 min)

```
qwriter.com         CNAME → qwriter-marketing.pages.dev   (Proxied)
www.qwriter.com     CNAME → qwriter-marketing.pages.dev   (Proxied)
app.qwriter.com     A     → <backend public IP>          (Proxied — CF as CDN/WAF)
tokens.qwriter.com  CNAME → qwriter-tokens.pages.dev      (Proxied)
api.qwriter.com     (optional, future external API)
```

Page rules on `app.qwriter.com`:

| Path | Cache | TTL |
|---|---|---|
| `/static/*` | Cache everything | 1 year |
| `/billing/webhook` | Bypass cache | — |
| `/*` | Standard (CF default) | — |

CF Pages auto-issues TLS for all four hostnames. For the backend, get a CF
Origin Certificate (Dashboard → SSL/TLS → Origin Server) and install it on
the backend host with TLS mode = "Full (strict)".

### 6. Restore the real Stripe controller (15 min)

The repo currently ships a stub `billing.rs` because async-stripe wouldn't
compile on the 8GB Windows dev box. The real implementation is preserved
verbatim at `src/controllers/billing.rs.real`.

```bash
cd qwriter/copyai_remote/src/controllers
mv billing.rs billing.rs.stub
mv billing.rs.real billing.rs
```

Re-enable the dep in `Cargo.toml`:

```toml
async-stripe = { version = "0.41.0", features = ["webhook-events", "checkout", "runtime-tokio-hyper"] }
```

Build on a host with ≥ 12 GB RAM (Linux is happiest — the LLVM OOM was
Windows-specific). `cargo build --release` takes ~6 min on a c7g.large.

### 7. Wire the Stripe webhook (10 min)

In the Stripe Dashboard → Developers → Webhooks → Add endpoint:

- **URL:** `https://app.qwriter.com/billing/webhook`
- **Events:** `checkout.session.completed`, `customer.subscription.updated`,
  `customer.subscription.deleted`, `invoice.payment_succeeded`,
  `invoice.payment_failed`
- Copy the signing secret into `STRIPE_WEBHOOK_SECRET` on the backend.

Verify locally with the Stripe CLI before going live:

```bash
stripe login
stripe listen --forward-to https://app.qwriter.com/billing/webhook
stripe trigger checkout.session.completed
# Watch backend logs for: "checkout.session.completed: applied subscription"
```

### 8. Final smoke (10 min)

From a fresh laptop, no cookies:

1. Visit `https://qwriter.com/` — marketing landing.
2. Click `Start free` → `/signup` → fill the form → submit.
3. Browser is redirected to `https://app.qwriter.com/` — dashboard renders
   with "Morning, …" greeting.
4. Open DevTools → Application → Cookies: `token` cookie present with
   `Domain=.qwriter.com; HttpOnly; Secure; SameSite=Lax`.
5. `/sources` → paste a real URL → scan card streams in.
6. `/billing` → Click `Upgrade Pro` → land on Stripe Checkout.
7. Complete checkout with `stripe trigger` or a test card.
8. Back on `app.qwriter.com/billing` — plan now shows `Pro`, with a
   "Next billing" date and a "Manage billing" portal button.

If any of those fails, the runbook below has the diagnostic curl one-liners.

---

## Diagnostics

### Cookie not crossing subdomains

```bash
curl -s -i https://app.qwriter.com/auth/login \
  -d 'email=…&password=…' \
  -H 'Content-Type: application/x-www-form-urlencoded'
# Look at Set-Cookie. Must include Domain=.qwriter.com
```

If not: `COOKIE_DOMAIN` is unset on the backend.

### Stripe webhook signature failing

```bash
# Watch the backend log while a webhook fires
stripe listen --print-secret
# Compare to what's in STRIPE_WEBHOOK_SECRET on the backend
```

If they differ, the webhook will return 400 (intentionally — the prior
silent-fallback bypass was the worst bug in the original codebase).

### JWT decode failing

Most likely: `JWT_SECRET` is not valid base64. Loco uses
`EncodingKey::from_base64_secret`. Regenerate:

```bash
openssl rand -base64 64 | tr -d '\n'
```

Set that as `JWT_SECRET` and restart the backend. Existing sessions are
invalidated; users sign in again.

---

## CSRF (P1 follow-up)

A `controllers/csrf.rs` module is wired with a double-submit cookie helper
but it's NOT yet enforced on every state-mutating handler. Quick adoption:

```rust
use crate::controllers::csrf;
use axum_extra::extract::cookie::CookieJar;

#[debug_handler]
async fn create_thing(
    auth: CookieAuth,
    jar: CookieJar,
    State(ctx): State<AppContext>,
    Form(form): Form<MyForm>,
) -> Result<Response> {
    csrf::verify(&jar, &form.csrf_token)?;
    // … normal logic
}
```

And in every form:

```html
<input type="hidden" name="csrf_token" value="{{ csrf_token }}">
```

For now, `SameSite=Lax` on the session cookie blocks the common attack
classes (cross-site form POST from another origin). The CSRF token closes
the gap for endpoints reachable from the same site via XSS-driven posts —
which is itself a defense-in-depth layer that requires another vuln to
exploit. Phase 9 work.

---

## Backup + monitoring

- **Backups:** point Fly Postgres / Render Postgres at a daily snapshot
  policy. Verify monthly.
- **Logs:** ship `RUST_LOG=info` to a sink (Logtail, Better Stack, or
  Vercel Log Drains). Alert on `controller_error` events.
- **Uptime:** `/health` route returns 200 from Loco by default — pop it
  into UptimeRobot.
- **Stripe webhook health:** CF dashboard shows delivery stats; alert on
  > 5 % failure rate.

---

## Rollback plan

1. CF Pages projects keep deploy history — one-click rollback to the prior
   green build.
2. Backend: keep the previous Docker image tagged `:prev`. `fly deploy
   --image qwriter:prev` rolls back in ~30 s.
3. Database: migrations are forward-only in this build. For rollback
   beyond a migration, restore from the daily snapshot.

---

## What you actually have to do

1. Push the three repos to GitHub.
2. Open CF dashboard, create two Pages projects (point at repos).
3. Spin up the backend (Fly app + Postgres, or container of your choice).
4. Set the env vars from the table above.
5. Add DNS records.
6. Run `cargo build --release` on a beefy enough host, deploy.
7. Run through the final smoke (8 steps).

Total wall time: **2–3 hours**, mostly waiting for builds + DNS propagation.

---

## Phase 14.5 · auto_migrate safety contract

`config/production.yaml` keeps `auto_migrate: true` deliberately. That
means **every binary startup applies any pending DB migrations before
listening on :5150**. To make that safe:

* **`start.ps1` takes a pre-migrate snapshot** of the live SQLite file
  (plus `-wal` / `-shm` siblings) into
  `%USERPROFILE%\OllaSuper-backups\<name>-pre-migrate-<UTC-stamp>.sqlite`
  BEFORE handing off to `copyai-cli.exe`.
* If the snapshot fails (disk full, permission denied) **the launch
  aborts**. A server that won't start is safer than running an
  irreversible migration against an unsnapshot'd DB. Override with
  `-SkipBackup` only when you know what you're doing.
* The pool keeps **30 rolling snapshots per DB**. Older ones are auto-
  pruned. WAL+SHM siblings are pruned alongside their parent.
* Every backup AND every restore writes a one-line audit entry to
  `OllaSuper-backups\audit.log`.
* `start.ps1 -Env production` now also auto-selects the `release`
  binary (was always `debug` before — a separate Phase 14.5 fix).

### Recovery from a bad migration

```powershell
# See what snapshots are available.
.\Restore-LastBackup.ps1 -List

# Roll the live DB back to the most recent snapshot.
# Stops copyai-cli, preserves the current state as
# <name>-before-restore-<stamp>.sqlite, restores, audits.
.\Restore-LastBackup.ps1

# Or pick a specific snapshot:
.\Restore-LastBackup.ps1 -Stamp 20260613-034417Z

# Then restart.
.\start.ps1 -Background -Env production
```

### Destructive migration discipline

When a future migration does `DROP COLUMN`, `DROP TABLE`, `TRUNCATE`,
`ALTER COLUMN TYPE`, or a backfill that mutates existing rows, the
commit message must lead with `BREAKING:` and the deploy must:

1. Notify the operator in advance.
2. Take an extra manual snapshot:
   `Copy-Item copyai_production.sqlite "$env:USERPROFILE\OllaSuper-backups\manual-pre-<reason>-<stamp>.sqlite"`
3. Run `start.ps1` from a foreground window so the migration output is
   visible. Do not background it on this kind of deploy.

This stays a discipline, not a config: `auto_migrate` remains `true`
unless and until there's a staging environment + deploy script that
can sequence (backup → migrate → smoke → restart) atomically.
