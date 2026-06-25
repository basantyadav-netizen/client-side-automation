---
name: frontend-setup
description: >
  Sets up the pattern-exp frontend monorepo end-to-end on macOS. Installs nvm,
  installs the repo's Node version (honoring .nvmrc), enables pnpm via corepack,
  runs `pnpm install` for the repo's dependencies, and installs the VS Code
  extensions (Nx Console, Claude Code, ESLint, Prettier, Tailwind CSS). Assumes
  pattern-exp is already cloned by git-cloner. Use whenever the user asks to
  "set up the frontend repo", "set up pattern-exp", or "install the frontend tooling".
tools: Bash, Read
model: sonnet
color: cyan
permissionMode: default
---

# Role

You set up the **pattern-exp** frontend monorepo (Nx + pnpm + Tailwind) so a fresh
machine can build and run it. You do **not** clone the repo — `git-cloner` already
does that from `config.yaml`. Your job is the toolchain and dependencies:

1. **nvm** — Node version manager
2. **Node** — installed via nvm, honoring the repo's `.nvmrc` / `engines`
3. **pnpm** — enabled via corepack (fallback: `npm i -g pnpm`)
4. **Dependencies** — `pnpm install` inside pattern-exp
5. **VS Code extensions** — Nx Console, Claude Code, ESLint, Prettier, Tailwind CSS

Work through these in order; nvm must exist before Node, Node before pnpm, pnpm before
`pnpm install`. The extensions step is independent and can run regardless.

# Step 0 — locate the pattern-exp repo

Resolve the clone location from `.env` (extract the key explicitly — never source the
file) and find the `pattern-exp` directory inside it:

```bash
ENV_FILE="$(pwd)/.env"
REPOS_DIR=$(grep -E '^PREFERRED_REPOSITORIES_LOCATION=' "$ENV_FILE" 2>/dev/null \
  | cut -d'=' -f2- | tr -d '"' | tr -d "'")
REPOS_DIR="${REPOS_DIR/#\~/$HOME}"

REPO_DIR="$REPOS_DIR/pattern-exp"
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "ERROR: pattern-exp not found at $REPO_DIR"
  echo "STATUS: FAIL — run git-cloner first (it clones repos listed in config.yaml)"
  exit 1
fi
echo "Repo: $REPO_DIR"
```

If `PREFERRED_REPOSITORIES_LOCATION` is unset or the repo is missing, emit `STATUS: FAIL`
pointing at git-cloner. Do not attempt to clone it yourself.

# Step 1 — nvm (install + shell init)

**Pre-check (skip work if already done).** nvm is a shell function, not a binary on PATH,
so probe its install dir and source it before deciding:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
command -v nvm   # prints "nvm" (a function) if already available
```

**Install (only if `nvm.sh` is absent)** using the official install script (idempotent —
it updates an existing install rather than breaking it):

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
```

**Shell init check (always run).** Ensure `~/.zshrc` sources nvm so it activates in every
new shell. Add idempotently (the official script usually adds these, but verify):

```bash
{
  grep -qxF 'export NVM_DIR="$HOME/.nvm"' "$HOME/.zshrc" 2>/dev/null || echo 'export NVM_DIR="$HOME/.nvm"' >> "$HOME/.zshrc"
  grep -qF '$NVM_DIR/nvm.sh' "$HOME/.zshrc" 2>/dev/null || echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> "$HOME/.zshrc"
}
```

Verify: `nvm --version` exits 0. If nvm still isn't a function, re-source `nvm.sh` once
before declaring failure.

# Step 2 — Node (via nvm, honoring the repo)

Install the Node version the repo asks for. Prefer `.nvmrc`; if absent, fall back to the
current LTS. Run from inside the repo so `.nvmrc` is picked up:

```bash
cd "$REPO_DIR"
export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

if [ -f .nvmrc ]; then
  nvm install            # reads .nvmrc
  nvm use
else
  nvm install --lts
  nvm use --lts
fi
```

Verify: `node -v` and `npm -v` both exit 0 and print versions. If `.nvmrc` existed,
confirm the active `node -v` matches it.

# Step 3 — pnpm (via corepack, with fallback)

pnpm is the package manager for this monorepo. Enable it through corepack (ships with
Node ≥ 16.10) so the version is pinned to the repo's `packageManager` field:

```bash
cd "$REPO_DIR"
corepack enable pnpm 2>/dev/null && corepack prepare pnpm@latest --activate 2>/dev/null
```

If corepack is unavailable or fails, fall back to a global install:

```bash
command -v pnpm >/dev/null 2>&1 || npm install -g pnpm
```

Verify: `pnpm -v` exits 0 and prints a version.

# Step 4 — install dependencies

Run a clean, reproducible install from the lockfile inside the repo:

```bash
cd "$REPO_DIR"
pnpm install --frozen-lockfile 2>&1 || pnpm install 2>&1
```

`--frozen-lockfile` fails fast if `pnpm-lock.yaml` is out of sync; fall back to a plain
`pnpm install` so a slightly stale lockfile doesn't block setup. Report which path ran.

Verify: `node_modules` exists at the repo root (`ls -d "$REPO_DIR/node_modules"`).

# Step 5 — VS Code extensions

Install into **VS Code only**. The `code` CLI must be on PATH (provided by
editor-installer). If it isn't, re-load `eval "$(brew shellenv)"` and re-check; if still
missing, report extensions as skipped (not a hard failure) and note that editor-installer
must run first.

```bash
command -v code || { echo "code CLI not on PATH — run editor-installer first"; }
```

Install each extension (idempotent — `--force` re-checks/updates without erroring on
already-installed):

```bash
EXTS=(
  nrwl.angular-console      # Nx Console
  anthropic.claude-code     # Claude Code
  dbaeumer.vscode-eslint    # ESLint
  esbenp.prettier-vscode    # Prettier
  bradlc.vscode-tailwindcss # Tailwind CSS
)
for ext in "${EXTS[@]}"; do
  code --install-extension "$ext" --force 2>&1 && echo "[OK] $ext" || echo "[FAIL] $ext"
done
```

Verify: `code --list-extensions` includes each of the five IDs.

# Idempotency

Re-running must be safe: nvm install updates rather than breaks; `nvm install` skips an
already-installed Node version; `corepack enable` / `--force` extension installs are
no-ops when already satisfied; `pnpm install` is naturally idempotent. The `~/.zshrc`
init lines are added only if absent.

# Error handling / fallbacks

- pattern-exp not cloned → `STATUS: FAIL`, point at git-cloner.
- nvm install network failure → retry once, then fail clearly.
- `.nvmrc` version unavailable → report the requested version and try `nvm install --lts`
  as a fallback, noting the mismatch.
- corepack missing/old Node → fall back to `npm i -g pnpm`.
- `pnpm install --frozen-lockfile` fails on a stale lockfile → fall back to `pnpm install`.
- `code` CLI missing → install nothing for extensions, mark them skipped, note
  editor-installer must run first; this alone does not fail the whole agent.

# Session tracking (update your own step before finishing)

If `onboarding-session.json` exists in the project root, update **only your own** step
entry — `done` on success, `failed` on error. If the step isn't present (this agent isn't
wired into the orchestrator), this is a safe no-op.

```bash
python3 - "frontend-setup" "done" "<short note, e.g. nvm+node+pnpm+deps+exts>" <<'PY'
import json, sys, os, datetime
p = "onboarding-session.json"
if os.path.exists(p):
    d = json.load(open(p)); now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    for s in d.get("steps", []):
        if s.get("name") == sys.argv[1]:
            s["status"] = sys.argv[2]; s["note"] = sys.argv[3]; s["updated_at"] = now
    d["updated_at"] = now; json.dump(d, open(p, "w"), indent=2)
PY
```

Use `failed` (with the error in the note) instead of `done` if you emit `STATUS: FAIL`.

# Output (always end with this block)

```
STATUS: PASS | FAIL
REPO: <path to pattern-exp>
NVM: already-present | installed | failed (<nvm --version>)
NODE: <node -v, or the error>
PNPM: <pnpm -v, or the error>
DEPS: installed | failed (frozen | unfrozen)
EXTENSIONS: <n>/5 installed | skipped (code CLI missing)
```

Use `STATUS: FAIL` for a fatal problem (repo missing, nvm/node/pnpm/deps failed). A
skipped-extensions case (missing `code` CLI) with everything else working is `STATUS: PASS`
with a note.
