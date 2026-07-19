# AI Copywriter (qwriter) - Project Handoff & Roadmap

## Project Overview
This project is a green-field "AI copywriter" SaaS (a Copy.ai-like clone) built specifically for solo creators. It strictly focuses on text generation, enabling users to create high-quality blogs, ads, social media posts, and emails efficiently. 

## Tech Stack
- **Backend:** Rust + Loco Framework (MVC)
- **Database:** SQLite (dev) / PostgreSQL (production) with SeaORM
- **Frontend:** React + TypeScript + Rsbuild (proxying to backend) + TailwindCSS v4
- **Testing:** Playwright (E2E testing)
- **Code Quality:** Biome (Frontend Lint/Format), Zod (Validation)
- **Integrations:** 
  - **LLM:** OpenAI (`async-openai` crate)
  - **Billing:** Stripe (`async-stripe` crate)

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

Additionally, update the `mailer` block in your `config/production.yaml` or `config/development.yaml` with your SMTP provider details (e.g., Resend, SendGrid) to enable actual email delivery for magic links and password resets.

## Future Roadmap (Phase 3 & Pending Items)

While the core MVP features are complete, the following items are on the roadmap to make the product production-ready and fully polished:

1. **Stripe Webhook Hardening:**
   - Handle subscription cancellations, downgrades, and payment failures in the `/api/billing/webhook` endpoint.
   - Set up Stripe Customer Portal so users can manage their own billing and payment methods.

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
