# PS Online Judge

## 1. Problem format

Each problem lives under `problems/<problem-id>/`.

Required / optional files:
- `README.md`: problem statement
- `config.json`: judge configuration (required)
- `user.<ext>`: starter template (at least one supported language per problem)
- `main.<ext>`: judge entry file (optional, if absent use `user.<ext>` as entry)

Example `config.json`:

```json
{
  "title": "W00 - Add",
  "time_limit_ms": 1000,
  "memory_limit_kb": 262144,
  "score_regex": "SCORE:\\s*(\\d+)",
  "languages": {
    "cpp": {
      "template": "user.cpp",
      "judge": "main.cpp",
      "compile": "g++ -O2 -std=c++17 -o /box/app main.cpp user.cpp",
      "execute": "/box/app"
    },
    "py": {
      "template": "user.py",
      "judge": "main.py",
      "execute": "python3 main.py"
    }
  }
}
```

## 2. Submission rules

For each submission PR:
- Exactly one file must be **added** with pattern `user-<name>.<ext>`.
- Template/judge files (`user.<ext>`, `main.<ext>`, files declared in config) must not be modified.
- Other file changes are allowed.

Target problem/language is inferred from the added `user-<name>.<ext>` file path and extension.

## 3. Judge pipeline

Triggers:
- `pull_request`
- `push` (re-judge when users push updates after opening a PR)

Flow:
1. Detect changed files and validate submission rules.
2. Load problem `config.json`.
3. Build temporary judge workspace.
   - Copy problem directory.
   - Replace language template file with the submitted `user-<name>.<ext>` content.
4. Run judge in Docker using isolate.
   - Compile (if configured).
   - Execute with per-problem time/memory limits.
5. Decide result.
   - PASS/FAIL from program exit code.
   - Score parsed from stdout with `SCORE:\s*(\d+)`.
6. Post result comment to PR.
7. Update GitHub Projects leaderboard item (PR-based).

## 4. Verdict

Primary rule:
- `PASS`: exit code is `0`
- `FAIL`: exit code is non-zero

`state` (for PR comment + leaderboard) should use one of:
- `PASS`
- `FAIL`
- `FAIL: COMPILE_ERROR`
- `FAIL: RUNTIME_ERROR`
- `FAIL: TIME_LIMIT_EXCEEDED`
- `FAIL: MEMORY_LIMIT_EXCEEDED`
- `FAIL: INVALID_SUBMISSION` (rule violation)

Notes:
- PASS/FAIL is always derived from exit code.
- Detailed FAIL reason is a best-effort classification from compile/runtime/isolate metadata.
- `score` is still parsed from stdout via `SCORE:\s*(\d+)` even on FAIL when available.

## 5. Docker cache

Cache Docker image tar with `actions/cache`.

- cache hit: `docker load`
- cache miss: build then `docker save`

## 6. GitHub Projects required fields

The project uses PRs as items.

Required fields (recommended types):
- `language` (Text)
- `state` (Text)
- `best-score` (Number)
- `last-score` (Number)
- `last-time` (Number, ms)
- `last-memory` (Number, KB)

Required secrets/variables:
- `PROJECT_ID`
- `FIELD_LANGUAGE_ID`
- `FIELD_STATE_ID`
- `FIELD_BEST_SCORE_ID`
- `FIELD_LAST_SCORE_ID`
- `FIELD_LAST_TIME_ID`
- `FIELD_LAST_MEMORY_ID`

`GITHUB_TOKEN` needs `pull-requests: write`, `issues: write`, `projects: write` permissions.
