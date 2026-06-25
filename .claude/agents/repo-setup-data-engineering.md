---
name: repo-setup-data-engineering
description: >
  Sets up data engineering repos end-to-end after they have been cloned by
  repo-cloner. TBD — implementation to be added.
tools: Bash, Read
model: sonnet
color: orange
permissionMode: default
---

# Role

[TODO] This agent will set up data engineering repositories after cloning.
Implementation to be added.

# Session tracking (update your own step before finishing)

If `onboarding-session.json` exists in the project root, update **only your own** step entry.

```bash
python3 - "repo-setup-data-engineering" "done" "<short note>" <<'PY'
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

# Output

```
STATUS: PASS | FAIL
SUMMARY: <one line>
```
