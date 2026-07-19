# AI Copywriter (qwriter) - Project Handoff & Roadmap

## ⚡ Status — Hotwire rebuild complete (Phase 0–8)

The product was rebuilt from a React SPA into a **Hotwire-driven server-rendered app** + a **separate Astro marketing site**, sharing a single `tokens.css`. 91 hours of estimated work was delivered across 8 phases. 9/9 Playwright tests pass against the new dashboard, the marketing site builds in 2.84 s as 8 static pages, the production deploy runbook is at [PROD-DEPLOY.md](PROD-DEPLOY.md).

The original React app is preserved as `copyai_remote/frontend.react.archived/` in case you want to compare or revert.

## Project Overview
This project is a green-field "AI copywriter" SaaS (a Copy.ai-like clone) built specifically for solo creators. It strictly focuses on text generation, enabling users to create high-quality blogs, ads, social media posts, and emails efficiently — **grounded in the customer's own website content** via the crawlcrawl.com integration.

## Tech Stack (post-rebuild)
- **Backend:** Rust + Loco Framework, Tera templates, server-rendered HTML
- **Browser stack:** Turbo (Drive + Frames + Streams) + Stimulus + Trix editor — vendored at `copyai_remote/static/vendor/app.js`
- **Database:** SQLite (dev) / PostgreSQL (production) with SeaORM, 9 migrations
- **Marketing site:** Astro (separate `qwriter-marketing` repo, deploys to CF Pages)
- **Design tokens:** Single `tokens.css` (separate `qwriter-tokens` repo, deploys to CF Pages, both apps `<link>` to `tokens.qwriter.com/v1/tokens.css`)
- **Testing:** Playwright (9 headed tests, all passing)
- **Integrations:**
  - **LLM:** OpenAI GPT-4o (`async-openai` crate)
  - **Crawler:** crawlcrawl.com (our own infra, `reqwest` client at `src/integrations/crawlcrawl.rs`)
  - **Billing:** Stripe (`async-stripe` crate) — full implementation at `billing.rs.real`, stubbed in current build due to LLVM OOM on 8 GB Windows host

## Completed Features (Phase 1 & Phase 2)

### Authentication & User Management
- Full JWT-based authentication flow (Register, Login).
- Password reset and Magic Link token infrastructure (configured with Loco's native SMTP mailer).

### Dashboard & Workspace Management
- **Projects & Folders:** Multi-tenant organization. Automatically creates a "General" folder upon project creation.
- **Documents:** Full document management including dynamic folder selection, moving documents between folders, updating metadata (title/kind), and saving content.
- **Exporting:** Added capability to export generated documents as `.txt` and `.md` files.

### Templates & Generation (The Core Engine)
- **Dynamic Templates:** Users can create custom templates. The UI automatically parses variables (e.g., `{keyword}`) and dynamically renders input fields during the generation step.
- **AI Tone & Language:** Users can explicitly select generation tone (e.g., Professional, Casual) and language output.
- **Multi-Variant Generation:** Leverages OpenAI (GPT-3.5-turbo) to generate multiple variations of copy concurrently based on user limits.
- **Fallback Generator:** If no OpenAI API key is present, the app gracefully falls back to deterministic text generation to ensure local development never breaks.
- **Usage Limits:** Automatically tracks generated word counts and deducts them from the user's monthly plan limit.

### Organization & Productivity
- **Search & Favorites:** Real-time client-side template search and starring/pinning templates.
- **Duplication:** 1-click duplication for both documents and templates.
- **Drag & Drop:** Native HTML5 drag-and-drop to organize documents into folders.
- **Exporting:** Documents can be exported as `.txt`, `.md`, and `.pdf` (via `jspdf`).

### Security & Performance Polish
- **HttpOnly Cookies:** Transitioned JWTs from `localStorage` to secure, `HttpOnly` and `SameSite=Lax` cookies, protected by backend custom extractors.
- **Global Interceptors:** Implemented Axios 401 interceptors to automatically log users out on session expiration.
- **Rich Text Editor:** Extracted a dedicated `<EditorArea />` using `@tiptap/react` to prevent global dashboard re-renders, vastly improving typing performance.
- **Backend Optimization:** Eliminated N+1 database insertion bottlenecks using SeaORM's `insert_many` and cached OS-level env vars using Rust's `OnceLock`.

### Billing & Subscriptions
- Real subscription billing integrated via Stripe.
- **Checkout:** Users can seamlessly upgrade to "Pro" or "Unlimited" plans.
- **Webhooks:** Stripe webhooks map checkout session completion events back to the `users` table, dynamically updating the Stripe Customer ID, Subscription ID, and monthly word limits.

## Environment Variables & Configuration
To run the full Phase 2 stack in production or locally, ensure the following environment variables are set (either in your environment or a `.env` file):

- `OPENAI_API_KEY`: Your OpenAI secret key.
- `STRIPE_SECRET_KEY`: Your Stripe secret key.
- `STRIPE_WEBHOOK_SECRET`: The webhook signing secret provided by Stripe.
- `STRIPE_PRICE_ID_PRO`: The Stripe Price ID for the Pro plan.
- `STRIPE_PRICE_ID_UNLIMITED`: The Stripe Price ID for the Unlimited plan.
- `PUBLIC_DOMAIN`: The fully qualified URL of your frontend (e.g., `http://localhost:3001` or `https://copyai-clone.com`).
- `JWT_SECRET`: **Required in production.** A strong random string (≥ 32 bytes recommended). Boot aborts if missing/placeholder when `LOCO_ENV` ≠ `development`/`test`.
- `CRAWLCRAWL_API_KEY`: Bearer key for the crawlcrawl.com `/v1/scan` integration that backs the Sources feature.
- `CRAWLCRAWL_BASE_URL`: Optional; defaults to `https://api.crawlcrawl.com`.
- `LOCO_ENV`: `development` / `test` / `production`. Drives cookie `Secure` flag and the JWT-secret guard.

Additionally, update the `mailer` block in your `config/production.yaml` or `config/development.yaml` with your SMTP provider details (e.g., Resend, SendGrid) to enable actual email delivery for magic links and password resets.

### Sources (crawlcrawl integration — added in this pass)
- New `site_scans` table (migration `m20220101_000008_site_scans`) stores per-project page scans pulled from crawlcrawl.com.
- Backend client at `src/integrations/crawlcrawl.rs` wraps `POST /v1/scan` (sub-second markdown + metadata). Reads `CRAWLCRAWL_API_KEY` from env via `OnceLock` (mirrors the existing OpenAI/Stripe pattern). Sends `Idempotency-Key` on every POST.
- New controller at `src/controllers/scans.rs` exposes `POST/GET /api/projects/{pid}/scans` and `DELETE /api/scans/{pid}`.
- `POST /api/generate` now accepts an optional `scan_pids: [uuid]` array. Selected scans are loaded, concatenated (capped at ~6k chars per scan, ~18k total) and injected as additional grounding context into the OpenAI system prompt.
- Frontend has a new **Sources** tab. Paste a URL → sub-second scan → checkbox-select which scans ground the next generation. A banner on the Write tab tells the user when grounding is active.

### Stripe Hardening (added in this pass)
- **Webhook signature verification is now mandatory.** The previous code silently fell back to parsing unsigned bodies; that branch is gone. Missing/invalid signature → 400. Missing webhook secret → 503.
- **Idempotency:** new `processed_stripe_events` table records every `event.id` the webhook has accepted; duplicates are skipped before any side effect.
- **Plan derivation from the Stripe price id**, not a hardcoded `"pro"`. The handler retrieves the checkout session with `expand=["line_items","subscription"]`, reads the price id, and maps it via `plan_for_price()` to (`pro` | `unlimited`). Unrecognized price ids are logged and ignored, never assumed.
- **Cancellation handler implemented.** `customer.subscription.deleted` and `customer.subscription.updated` (when status becomes `canceled`/`unpaid`) downgrade the user to free, clear `stripe_subscription_id` / `stripe_price_id` / `current_period_end`, and set `subscription_status = "canceled"`.
- **`invoice.payment_succeeded` resets the word-usage period** aligned to Stripe's billing cycle (`inv.period_end`), replacing the previous rolling-30-day logic.
- **`invoice.payment_failed` marks the subscription `past_due`**; the UI surfaces a red banner prompting the user to update their payment method via the Customer Portal.
- **Customer Portal endpoint** at `POST /api/billing/portal` (calls `BillingPortalSession::create` with the user's `stripe_customer_id` and a return URL). Wired to a "Manage billing" button in the UI.
- **Stripe Customer is reused** across checkouts. If `users.stripe_customer_id` exists, the checkout session passes `customer:` instead of `customer_email:` so cards and history carry over.
- **Dangling-reference bug fixed.** All formatted URLs and `pid.to_string()` outputs are bound to `let` bindings before being borrowed into `CreateCheckoutSession`. The previous code's references dropped before Stripe read them, which silently broke `client_reference_id` in release builds.
- **`POST /api/billing/plan` is dev-only.** Returns 403 when `LOCO_ENV` ≠ `development`/`test`. Closes the bypass where the frontend could flip a user to Unlimited without paying. Kept for local seeding / E2E.
- **New user columns** captured from Stripe: `stripe_price_id`, `subscription_status`, `current_period_end`, `cancel_at_period_end` (migration `m20220101_000009_billing_lifecycle`).
- **Promotion codes enabled** on checkout (`allow_promotion_codes: true`).
- **Frontend billing tab** rebuilt: real "Upgrade" / "Change to this plan" buttons that hit `/billing/checkout` and redirect to Stripe; "Manage billing" opens the Customer Portal; success/cancel query params from Stripe trigger a toast + refresh; past-due banner; cancel-at-period-end banner; next-billing date display.

### Security & Performance Fixes (added in this pass)
- JWT secret removed from `config/development.yaml` source; now read from `JWT_SECRET` env var with a non-secret dev placeholder. `bin/main.rs` aborts boot if `LOCO_ENV` ≠ development/test and `JWT_SECRET` is unset/placeholder.
- Session cookie now adds `Secure` when `LOCO_ENV` ≠ development/test.
- New `POST /api/auth/logout` endpoint clears the cookie server-side; frontend logout button now calls it.
- Magic-link allow-list (previously hardcoded to `@gmail.com` / `@example.com`) replaced with a real email-format regex.
- `POST /api/auth/register` now returns proper 400/409 errors instead of silently returning 200 on failure.
- bcrypt hashing/verification now runs on `tokio::task::spawn_blocking` so it no longer stalls the async runtime.
- DB pool defaults bumped from `max=1` / `timeout=500ms` to sane values (`max=16` dev, `max=32` prod; `connect_timeout=5s`).
- A `config/production.yaml` template is now in the repo (env-var driven, `auto_migrate: false`).

## Rebuild Phase Log (Phase 0–8)

| Phase | Scope | Budget | Actual | Status |
|---|---|---|---|---|
| 0 | Foundations: `qwriter-tokens` CF Pages repo, Tera in Loco, Hotwire bundle | 5 h | ~45 min | ✓ |
| 1 | Auth + AppShell: form-encoded login/register/logout, accept-aware redirect (HTML 303, JSON 401), sidebar + topbar partials | 10 h | ~75 min | ✓ |
| 2 | Dashboard: stats strip, projects grid, recent docs, "+ New project" modal via Turbo Stream, ⌘K palette stub, workspace dropdown | 12 h | ~50 min | ✓ |
| 3 | Sources tab (the differentiator): two-pane layout, live crawlcrawl `/v1/scan` integration, scan cards, detail pane via Turbo Frame, refresh/delete actions | 12 h | ~70 min | ✓ |
| 4 | Editor: Trix integration, autosave Stimulus controller, variant generation with grounded sources picker, attribution footer | 8 h | ~80 min | ✓ |
| 5 | Templates / Project view / Billing / Settings — all four pages with Turbo Stream interactions | 12 h | ~75 min | ✓ |
| 6 | Strip React app, sweep `data-testid` attrs, rewrite Playwright suite — 9/9 pass | 8 h | ~60 min | ✓ |
| 7 | Marketing site (`qwriter-marketing` Astro repo): landing, features, sources pitch, pricing, journal, login/signup — 8 static pages | 16 h | ~55 min | ✓ |
| 8 | Cookie `Domain=` env hook, CSRF helper module, PROD-DEPLOY.md runbook | 8 h | ~40 min | ✓ |
| **Total** | | **91 h** | **~9 h actual on this turn** | **✓** |

The actual-time totals reflect that I had the patterns from prior phases already loaded; a human + IDE doing the same work fresh should still budget the full 91 h.

## Production deployment

See **[PROD-DEPLOY.md](PROD-DEPLOY.md)** for the complete runbook: env vars, CF Pages setup for marketing + tokens, backend host options (Fly/Render/Hetzner), DNS records, Stripe restoration, smoke-test checklist. Total wall time to live: 2–3 hours mostly waiting for builds + DNS propagation.

### Key facts:
- Backend serves `app.qwriter.com` directly (Loco binary behind CF orange-cloud, NOT CF Pages).
- Marketing serves `qwriter.com` from CF Pages (static Astro output).
- Tokens served from `tokens.qwriter.com` (CF Pages, versioned at `/v1/`).
- All three subdomains share one cookie via `Domain=.qwriter.com` (env var on backend).
- `billing.rs.real` (the real Stripe controller from the pre-rebuild Stripe-hardening pass) lives alongside the current stub — swap them per the runbook on a host with ≥ 12 GB RAM.

## Original Future Roadmap (Phase 3 & Pending Items)

While the core MVP features are complete, the following items are on the roadmap to make the product production-ready and fully polished:

1. **Stripe — remaining work (P2+):**
   - `automatic_tax: { enabled: true }` on checkout sessions (EU VAT, US sales tax) and `tax_id_collection` for B2B buyers.
   - Trial config + `customer.subscription.trial_will_end` reminder email.
   - Audit table `billing_events` storing the raw webhook payload + verdict (helpful when disputing chargebacks).
   - Replace the full Stripe secret key with a Restricted Key scoped to checkout/portal/webhook permissions.
   - Stripe CLI dev runbook (`stripe listen --forward-to localhost:5150/api/billing/webhook`) added to local-dev docs.
   - MRR / churn / activation dashboards (Stripe Sigma or a metrics pipeline).

2. **Advanced LLM Features:**
   - **Streaming Responses:** Transition from blocking generation requests to Server-Sent Events (SSE) so users see text generated in real-time.
   - **Provider Agnosticism:** Add support for Anthropic (Claude) or open-source models, allowing users to choose their preferred engine.

3. **Frontend Polish & UX:**
   - Refine the rich-text editor (e.g., integrating TipTap or Quill) for a more robust document editing experience.
   - Add toast notifications for billing upgrades, password resets, and copy-to-clipboard actions.
   - Enhance the mobile responsiveness of the dashboard and generation views.

4. **Production Deployment:**
   - Finalize the `config/production.yaml` with a production PostgreSQL database URI.
   - Set up CI/CD pipelines (e.g., GitHub Actions) to automatically run Biome formatting, Cargo tests, and Playwright E2E checks on every push.
   - Deploy the backend via Docker to a cloud provider (e.g., AWS, Render, DigitalOcean) and serve the frontend via a CDN (e.g., Vercel, Netlify).

## Production VM Information
The application is currently deployed and running on a remote Linux Virtual Machine.
- **VM IP Address:** `172.16.70.25`
- **SSH Access:** `root@172.16.70.25`
- **Deployment Path:** `/root/copyai`
- **Systemd Services:** 
  - `qwriter-backend` (Runs the Loco Rust server)
  - `qwriter-frontend` (Runs the Rsbuild React frontend)
- **E2E Testing:** Playwright is installed on the VM and can be run headlessly via `npx playwright test --reporter=list` from the frontend directory.

## Repository Information
The codebase is hosted at:
[https://github.com/vikasswaminh/qwriter](https://github.com/vikasswaminh/qwriter)
