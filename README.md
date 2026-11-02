# Roz Kharcha

Mobile-friendly personal order tracker in Indian rupees. Add a final paid amount, date, store, category and note. View monthly totals, search entries, edit/delete, mark statement matches, and download CSV or a JSON backup.

## How it works

- `docs/`: HTML/CSS/JavaScript frontend hosted on GitHub Pages. No build step.
- `backend/`: Julia 1.10 + HTTP.jl 1.x API hosted separately on a server that supports Julia or Docker.
- A separate **private GitHub repository** stores `expenses.json`. Every successful change creates a commit. GitHub's file SHA prevents lost updates; conflicting writes are retried against the latest ledger.
- The GitHub token is a server environment variable, never browser code. Your app password is entered on your phone and kept only in memory; reconnect after reopening/reloading the page.

**Pushing this project alone does not enable online saving. GitHub Pages cannot run the Julia backend. Complete the backend setup below.** No accounts, tokens, repositories or hosting have been created for this project.

## 1. Push the project

Extract the ZIP, open a terminal in this folder, create an empty GitHub repository (for example `roz-kharcha`), then run:

```bash
git init
git add .
git commit -m "Add Roz Kharcha expense tracker"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/roz-kharcha.git
git push -u origin main
```

The app source can be public; **never commit actual expense records or credentials to that repository**. Only the `docs/` folder should be published through Pages.

## 2. Create the private data repository

Create a different private repository, for example `roz-kharcha-data`, and initialize it with a README so that its `main` branch exists. Do not enable Pages for this repository. The API will create `expenses.json` on the first save.

Create a fine-grained GitHub personal access token restricted to that private repository, with **Contents: Read and write**. If an organization owns the repository, its approval rules may apply. Store the token only in the backend hosting secret settings. Rotate it when it expires.

## 3. Host the Julia backend

Use a Julia-capable server or Docker hosting with HTTPS. Set the build context/root directory to `backend`, Dockerfile `Dockerfile`, and health check `/health`. Set these environment variables in the host's dashboard:

| Variable | Example / meaning |
|---|---|
| `GITHUB_TOKEN` | Fine-grained token; secret |
| `GITHUB_REPO` | `YOUR_USERNAME/roz-kharcha-data` |
| `GITHUB_BRANCH` | `main` |
| `APP_PASSWORD` | Random secret, at least 24 characters; secret |
| `ALLOWED_ORIGIN` | `https://YOUR_USERNAME.github.io` (no trailing slash or repository path) |
| `PORT` | `8080`, or the port required by your host |

Generate a password with a password manager. This is a single-owner shared-secret app, not GitHub OAuth. HTTPS is required on the hosted backend. Failed sign-ins have a basic global rate limit; for an Internet-facing deployment, use your host's request/body limits and rate limiting as well.

Docker local example (copy `.env.example` to `.env` inside `backend` and replace placeholders first):

```bash
cd backend
docker build -t roz-kharcha-api .
docker run --rm --env-file .env -p 8080:8080 roz-kharcha-api
```

Without Docker, install Julia 1.10+, instantiate packages, set the environment variables in your shell, then run:

```bash
julia --project=backend -e 'using Pkg; Pkg.instantiate()'
julia --project=backend backend/server.jl
```

`.env` is a Docker input here; the Julia script does not automatically load it. Never paste tokens or passwords into `docs/config.js`.

## 4. Publish GitHub Pages

In your source repository: **Settings → Pages → Deploy from a branch → main → /docs → Save**.

For repository `roz-kharcha`, the app normally lives at `https://YOUR_USERNAME.github.io/roz-kharcha/`. To use exactly `https://YOUR_USERNAME.github.io/`, name your repository `YOUR_USERNAME.github.io` and select `/docs` there.

Open the app and enter your hosted backend's HTTPS origin plus `APP_PASSWORD`. You can optionally set the public backend address in `docs/config.js` to avoid typing it. Only the backend URL is remembered on the device, not the password or expense records.

## 5. Use from your phone

1. Open the Pages link in your mobile browser.
2. Connect using the backend URL and app password.
3. Enter each order's **final paid amount**, including fees and after discounts.
4. Wait for **Saved to GitHub** before leaving the page.
5. At month-end, compare entries with your statement and tick Checked.
6. Use CSV for a monthly spreadsheet or Backup for all loaded records.
7. Add a browser home-screen shortcut for quick access.

The same private ledger is loaded on mobile and laptop. Tap Refresh before reviewing changes made on another device. Offline edits are not queued. If a request times out, refresh to see whether it completed before adding the order again. Editing resets Checked. Delete removes the current entry, but previous GitHub commits retain history.

## Tests and verification

```bash
node --check docs/app.js
julia --project=backend test/runtests.jl
```

The included GitHub Actions workflow runs Julia ledger validation/auth/CORS unit tests and a JavaScript syntax check after push. Unit tests make no real GitHub writes.

At delivery: JavaScript syntax and static markup checks passed. This creation environment has no Julia runtime, so Julia tests, real GitHub saving, and hosted mobile behavior **have not been executed here**. After deployment, add a small test entry, refresh on another device, edit it, tick Checked, export CSV, and delete it. Verify the resulting private-repository commits before relying on the ledger.

## Troubleshooting

- Connection fails: verify backend HTTPS, availability, and exact `ALLOWED_ORIGIN`.
- 401: use `APP_PASSWORD`, not your GitHub password/token.
- 502: check token expiry, selected repository permission, existing branch and repository spelling. Backend intentionally returns a generic error without exposing secrets.
- 429: wait one minute after repeated failed sign-ins.
- Changes not visible: select the correct month, remove search filters, Refresh.

Keep the data repository private. Never add the GitHub token to browser storage, the source repo, a URL or frontend code. GitHub is a small personal ledger store here, not a high-volume database. Hosting and GitHub availability/limits still apply.

## Dependencies

- https://juliaweb.github.io/HTTP.jl/v1.0.2/server/
- https://docs.github.com/en/rest/repos/contents
- https://docs.github.com/en/pages/getting-started-with-github-pages
