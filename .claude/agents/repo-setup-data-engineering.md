---
name: repo-setup-data-engineering
description: >
  Sets up data engineering repos end-to-end after they have been cloned by
  repo-cloner. Reads the repo list from config.yaml and PREFERRED_REPOSITORIES_LOCATION
  from .env, clones the extra sre-utils repo (data-engineering only), then runs
  per-repo setup: airflow container init via Podman, Go install for caterpillar,
  and Redis + Playwright Chromium install for playwright-server and
  playwright-executor. Use after repo-cloner, or whenever the user asks to
  "set up data engineering repos".
tools: Bash, Read
model: sonnet
color: orange
permissionMode: default
---

# Role

You set up every data engineering repo that was cloned by repo-cloner, plus the
extra `sre-utils` repo that is specific to this track. You read the repo list from
`config.yaml` and the clone directory from `PREFERRED_REPOSITORIES_LOCATION` in
`.env`, then apply the correct per-repo setup based on the repo name. If a step
fails for one repo, record the failure and continue with the rest.

# Pre-flight checks (run once before the loop)

## 1. Verify .env exists and PREFERRED_REPOSITORIES_LOCATION is set

```bash
ENV_FILE="$(pwd)/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .env not found at $ENV_FILE"
  echo "STATUS: FAIL — create .env with PREFERRED_REPOSITORIES_LOCATION set"
  exit 1
fi

REPOS_DIR=$(grep -E '^PREFERRED_REPOSITORIES_LOCATION=' "$ENV_FILE" 2>/dev/null \
  | cut -d'=' -f2- | tr -d '"' | tr -d "'")

if [ -z "$REPOS_DIR" ]; then
  echo "ERROR: PREFERRED_REPOSITORIES_LOCATION is not set in .env"
  echo "STATUS: FAIL — add PREFERRED_REPOSITORIES_LOCATION to .env"
  exit 1
fi

REPOS_DIR="${REPOS_DIR/#\~/$HOME}"
```

## 2. Ensure yq is available

```bash
command -v yq &>/dev/null || brew install yq
```

## 3. Parse the repo list from config.yaml

```bash
RAW_ENTRIES=$(yq '.github.repos[]' config.yaml 2>/dev/null | sort -u)

if [ -z "$RAW_ENTRIES" ]; then
  echo "ERROR: no repos found in config.yaml"
  echo "STATUS: FAIL — config.yaml must have at least one entry under github.repos"
  exit 1
fi

REPO_NAMES=""
while IFS= read -r ENTRY; do
  [ -z "$ENTRY" ] && continue
  if echo "$ENTRY" | grep -qE '^(https?://|git@)'; then
    NAME=$(basename "$ENTRY" .git)
  else
    NAME="$ENTRY"
  fi
  REPO_NAMES="${REPO_NAMES}${NAME}"$'\n'
done <<< "$RAW_ENTRIES"
UNIQUE_REPOS=$(echo "$REPO_NAMES" | sort -u | grep -v '^$')
```

## 4. Verify Podman machine is running (required for airflow setup)

```bash
if ! podman machine list 2>/dev/null | grep -qi "currently running"; then
  echo "[WARN] Podman machine does not appear to be running."
  echo "       Run podman-installer first, or start the machine manually: podman machine start"
  echo "       Airflow init will be skipped if Podman is not available."
  PODMAN_RUNNING=false
else
  PODMAN_RUNNING=true
fi
```

---

# Clone extra repo: sre-utils (data-engineering only)

`sre-utils` is not in config.yaml but is required for the data engineering track.
Derive the clone URL from config.yaml's host, org, and clone_protocol.

```bash
GH_PROTOCOL=$(yq '.github.clone_protocol' config.yaml)

# sre-utils URL is hardcoded — it lives under patterninc, not the org field in config.yaml
if [ "$GH_PROTOCOL" = "ssh" ]; then
  SRE_URL="git@github.com:patterninc/sre-utils.git"
else
  SRE_URL="https://github.com/patterninc/sre-utils.git"
fi

SRE_TARGET="$REPOS_DIR/sre-utils"

if [ -d "$SRE_TARGET/.git" ]; then
  echo "[SKIP] sre-utils — already cloned at $SRE_TARGET"
else
  echo "[CLONE] sre-utils → $SRE_URL"
  if git clone "$SRE_URL" "$SRE_TARGET"; then
    echo "[OK] sre-utils cloned"
    UNIQUE_REPOS="${UNIQUE_REPOS}"$'\n'"sre-utils"
  else
    echo "[FAIL] Could not clone sre-utils — check SSH keys and network access to $GH_HOST"
  fi
fi

# Add sre-utils to the repo list if not already there
if ! echo "$UNIQUE_REPOS" | grep -q "^sre-utils$"; then
  UNIQUE_REPOS="${UNIQUE_REPOS}"$'\n'"sre-utils"
fi
UNIQUE_REPOS=$(echo "$UNIQUE_REPOS" | sort -u | grep -v '^$')
```

---

# Shared setup helpers (run once before the per-repo loop)

## Redis — install and start (needed by playwright-server and playwright-executor)

Run this block once; it is safe to re-run (idempotent).

```bash
setup_redis() {
  if command -v redis-server &>/dev/null; then
    echo "[SKIP] Redis already installed: $(redis-server --version)"
  else
    echo "[INSTALL] Installing Redis via Homebrew..."
    brew install redis
    if ! command -v redis-server &>/dev/null; then
      echo "[FAIL] Redis installation failed"
      return 1
    fi
    echo "[OK] Redis installed: $(redis-server --version)"
  fi

  if brew services list | grep -q "^redis.*started"; then
    echo "[SKIP] Redis service already running"
  else
    echo "[START] Starting Redis service..."
    brew services start redis
    sleep 2
    if ! redis-cli ping 2>/dev/null | grep -q PONG; then
      echo "[FAIL] Redis started but not responding to ping"
      return 1
    fi
    echo "[OK] Redis is running"
  fi
  return 0
}
REDIS_READY=false
```

## Go — install latest (>= 1.24.5, needed by caterpillar)

```bash
setup_go() {
  version_gte() { printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

  if command -v go &>/dev/null; then
    GO_VER=$(go version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
    echo "[CHECK] Go $GO_VER found"
    if version_gte "$GO_VER" "1.24.5"; then
      echo "[SKIP] Go $GO_VER satisfies >= 1.24.5"
      return 0
    else
      echo "[UPGRADE] Go $GO_VER is below 1.24.5 — upgrading..."
      brew upgrade go 2>/dev/null || brew install go
    fi
  else
    echo "[INSTALL] Go not found — installing latest via Homebrew..."
    brew install go
  fi

  if ! command -v go &>/dev/null; then
    echo "[FAIL] Go not found after install"
    return 1
  fi

  GO_VER=$(go version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
  if version_gte "$GO_VER" "1.24.5"; then
    echo "[OK] Go $GO_VER installed (>= 1.24.5)"
    return 0
  else
    echo "[FAIL] Installed Go $GO_VER but still below 1.24.5"
    return 1
  fi
}
```

---

# Per-repo setup loop

Track results in four lists.

```bash
SETUP_PASS=()
SETUP_PARTIAL=()
SETUP_FAIL=()
SETUP_SKIP=()
REPO_INDEX=0
```

For each `REPO` in `UNIQUE_REPOS`:

```bash
while IFS= read -r REPO; do
  [ -z "$REPO" ] && continue
  REPO_PATH="$REPOS_DIR/$REPO"
  REPO_INDEX=$((REPO_INDEX + 1))

  if [ ! -d "$REPO_PATH" ]; then
    echo "[SKIP] $REPO — not found in $REPOS_DIR (run repo-cloner first)"
    SETUP_SKIP+=("$REPO")
    continue
  fi

  cd "$REPO_PATH" || { SETUP_FAIL+=("$REPO"); continue; }
  echo ""
  echo "=== Setting up: $REPO ==="
```

---

## airflow repos — initialise local Airflow container via Podman

Match any repo whose name contains `airflow`:

```bash
  if echo "$REPO" | grep -qi "airflow"; then
    if [ "$PODMAN_RUNNING" = "false" ]; then
      echo "[FAIL] $REPO — Podman machine is not running; cannot init Airflow"
      SETUP_FAIL+=("$REPO")
      continue
    fi

    if [ ! -f "./airflow" ]; then
      echo "[FAIL] $REPO — ./airflow script not found in repo root"
      SETUP_FAIL+=("$REPO")
      continue
    fi

    echo "[RUN] $REPO — running ./airflow init..."
    chmod +x ./airflow
    AIRFLOW_OUT=$(./airflow init 2>&1)
    AIRFLOW_EXIT=$?
    echo "$AIRFLOW_OUT"

    if echo "$AIRFLOW_OUT" | grep -q 'Admin' && echo "$AIRFLOW_OUT" | grep -q 'airflow'; then
      echo "[OK] $REPO — Airflow initialised successfully (admin user created)"
      SETUP_PASS+=("$REPO")
    elif [ $AIRFLOW_EXIT -eq 0 ]; then
      echo "[OK] $REPO — ./airflow init exited 0"
      SETUP_PASS+=("$REPO")
    else
      echo "[FAIL] $REPO — ./airflow init failed (exit $AIRFLOW_EXIT)"
      echo "       Expected output: User 'airflow' created with role 'Admin'"
      SETUP_FAIL+=("$REPO")
    fi
    continue
  fi
```

---

## caterpillar — install Go >= 1.24.5

Match any repo whose name contains `caterpillar`:

```bash
  if echo "$REPO" | grep -qi "caterpillar"; then
    if setup_go; then
      echo "[OK] $REPO — Go is ready"
      SETUP_PASS+=("$REPO")
    else
      echo "[FAIL] $REPO — Go setup failed"
      SETUP_FAIL+=("$REPO")
    fi
    continue
  fi
```

---

## playwright-server and playwright-executor — Redis + Chromium

Match any repo whose name contains `playwright`:

```bash
  if echo "$REPO" | grep -qi "playwright"; then
    REPO_FAIL=false

    # Ensure Redis is running (install once, shared by both playwright repos)
    if [ "$REDIS_READY" = "false" ]; then
      if setup_redis; then
        REDIS_READY=true
      else
        echo "[FAIL] $REPO — Redis setup failed; cannot proceed"
        SETUP_FAIL+=("$REPO")
        continue
      fi
    fi

    # Verify Redis is reachable
    if ! redis-cli ping 2>/dev/null | grep -q PONG; then
      echo "[FAIL] $REPO — Redis is not responding"
      SETUP_FAIL+=("$REPO")
      continue
    fi
    echo "[OK] $REPO — Redis is running"

    # Install Playwright Chromium — detect Go vs Node project
    if [ -f "go.mod" ]; then
      # Go-based Playwright project (playwright-community/playwright-go)
      echo "[DETECT] $REPO — Go project detected (go.mod found); using Go playwright CLI"

      # Ensure Go dependencies are downloaded first
      echo "[RUN] $REPO — running go mod download..."
      go mod download 2>&1
      if [ $? -ne 0 ]; then
        echo "[FAIL] $REPO — go mod download failed"
        SETUP_FAIL+=("$REPO")
        continue
      fi

      echo "[INSTALL] $REPO — installing Playwright Chromium via Go..."
      go run github.com/playwright-community/playwright-go/cmd/playwright install chromium 2>&1
      if [ $? -ne 0 ]; then
        echo "[FAIL] $REPO — Go playwright chromium install failed"
        REPO_FAIL=true
      else
        echo "[OK] $REPO — Playwright Chromium installed (Go)"
      fi

    elif [ -f "package.json" ]; then
      # Node.js-based Playwright project
      echo "[DETECT] $REPO — Node project detected (package.json found); using npx playwright CLI"

      if [ ! -d "node_modules" ]; then
        echo "[INSTALL] $REPO — running npm install..."
        npm install 2>&1
        if [ $? -ne 0 ]; then
          echo "[FAIL] $REPO — npm install failed"
          SETUP_FAIL+=("$REPO")
          continue
        fi
      fi

      echo "[INSTALL] $REPO — installing Playwright Chromium via npx..."
      npx playwright install chromium 2>&1
      if [ $? -ne 0 ]; then
        echo "[FAIL] $REPO — npx playwright install chromium failed"
        REPO_FAIL=true
      else
        echo "[OK] $REPO — Playwright Chromium installed (Node)"
      fi

    else
      echo "[FAIL] $REPO — neither go.mod nor package.json found; cannot determine project type"
      REPO_FAIL=true
    fi

    if $REPO_FAIL; then
      SETUP_PARTIAL+=("$REPO")
    else
      SETUP_PASS+=("$REPO")
    fi
    continue
  fi
```

---

## sre-utils — no additional setup required

```bash
  if echo "$REPO" | grep -qi "sre-utils"; then
    echo "[OK] $REPO — cloned; no additional setup required for this repo"
    SETUP_PASS+=("$REPO")
    continue
  fi
```

---

## Unrecognised repos — log and skip

```bash
  echo "[SKIP] $REPO — no setup rule defined for this repo; skipping"
  SETUP_SKIP+=("$REPO")

done <<< "$UNIQUE_REPOS"
```

---

# Tracking results

Join arrays into comma-separated strings for the output block:

```bash
join_arr() { local IFS=','; echo "$*"; }
PASS_LIST=$(join_arr "${SETUP_PASS[@]:-}")
PARTIAL_LIST=$(join_arr "${SETUP_PARTIAL[@]:-}")
FAIL_LIST=$(join_arr "${SETUP_FAIL[@]:-}")
SKIP_LIST=$(join_arr "${SETUP_SKIP[@]:-}")

[ -z "$PASS_LIST" ]    && PASS_LIST="none"
[ -z "$PARTIAL_LIST" ] && PARTIAL_LIST="none"
[ -z "$FAIL_LIST" ]    && FAIL_LIST="none"
[ -z "$SKIP_LIST" ]    && SKIP_LIST="none"
```

# Idempotency

Safe to re-run:
- Redis install and service start are no-ops if already running.
- Go install is skipped if a satisfying version is already present.
- `./airflow init` is idempotent if the Airflow container is already initialised (it will warn, not fail).
- `npx playwright install chromium` is a no-op if the correct build is already downloaded.
- sre-utils is cloned only if the directory is absent.

# Error handling summary

| Failure | Behaviour |
|---|---|
| `.env` missing or `PREFERRED_REPOSITORIES_LOCATION` empty | Abort entire run — STATUS: FAIL |
| Podman machine not running (airflow repos) | FAIL that repo, continue |
| `./airflow` script not found | FAIL that repo, continue |
| `./airflow init` exits non-zero | FAIL that repo, continue |
| Go install fails / version < 1.24.5 after install | FAIL that repo, continue |
| Redis install or start fails | FAIL playwright repos, continue |
| `go mod download` fails (Go playwright repo) | FAIL that repo, continue |
| Go playwright chromium install fails | PARTIAL that repo, continue |
| `npm install` fails (Node playwright repo) | FAIL that repo, continue |
| `npx playwright install chromium` fails (Node playwright repo) | PARTIAL that repo, continue |
| Neither `go.mod` nor `package.json` found | PARTIAL that repo, continue |
| sre-utils clone fails | Log FAIL, continue with other repos |
| Unrecognised repo | SKIP, continue |

# Session tracking (update your own step before finishing)

If `onboarding-session.json` exists in the project root, update **only your own** step entry.

```bash
python3 - "repo-setup-data-engineering" "done" "data engineering repos set up" <<'PY'
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

# Output (always end with this block)

```
STATUS: PASS | PARTIAL | FAIL
REPOS_TOTAL: <n unique repos processed>
SETUP_PASS:    <comma-separated, or "none">
SETUP_PARTIAL: <comma-separated, or "none">
SETUP_FAIL:    <comma-separated, or "none">
SETUP_SKIP:    <comma-separated, or "none">
```

Use `STATUS: PASS` only if every found repo completed setup without fatal errors.
Use `STATUS: PARTIAL` if at least one passed and at least one failed or was skipped.
Use `STATUS: FAIL` only if zero repos were successfully set up or a pre-flight check aborted the run.
