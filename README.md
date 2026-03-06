# github-online-judge

PS(Problem Solving) practice repository with an automated Online Judge pipeline on GitHub Actions.

This README is a quick usage guide. For full technical details, see [docs/ONLINE_JUDGE.md](docs/ONLINE_JUDGE.md).

## Overview

- Each problem is stored under `problems/<problem-id>/`.
- Participants submit solutions via Pull Request.
- The judge runs automatically on PR and posts result comments.
- Result is also synced to GitHub Project fields (leaderboard-like tracking).

## Repository Structure

```text
.
├── docs/
│   └── ONLINE_JUDGE.md
└── problems/
    └── <problem-id>/
        ├── README.md      # problem statement
        ├── config.json    # judge config (required)
        ├── user.<ext>     # starter template
        ├── main.<ext>     # judge entry (optional)
        └── user-<name>.<ext> # participant submission file (PR)
```

## Quick Start (Participant)

### 1. Choose a problem

Pick a problem directory, e.g. `problems/w00-add/`.

Read:

- `problems/w00-add/README.md` (problem statement)
- `problems/w00-add/config.json` (supported languages)

For `w00-add`, available languages are:

- `cpp`
- `py`

### 2. Create exactly one submission file

In your PR, you must add exactly one new file with this pattern:

```text
problems/<problem-id>/user-<name>.<ext>
```

Examples:

- `problems/w00-add/user-alice.cpp`
- `problems/w00-add/user-bob.py`

### 3. Follow submission rules

- Exactly **one** file must be **added**: `user-<name>.<ext>`
- Do **not** modify template/judge files such as:
  - `user.<ext>`
  - `main.<ext>`
  - files declared in `config.json`

If rules are violated, the run fails as `FAIL: INVALID_SUBMISSION`.

### 4. Open Pull Request

After pushing your branch and opening a PR:

1. Workflow validates changed files.
2. Judge builds runtime in Docker.
3. Your submission replaces `user.<ext>` in temporary workspace.
4. Compile/execute runs with problem limits.
5. PR comment is posted with verdict/score/time/memory.

## Result Semantics

Primary verdict rule:

- `PASS`: exit code `0`
- `FAIL`: non-zero exit code

Detailed states may include:

- `FAIL: COMPILE_ERROR`
- `FAIL: RUNTIME_ERROR`
- `FAIL: TIME_LIMIT_EXCEEDED`
- `FAIL: MEMORY_LIMIT_EXCEEDED`
- `FAIL: INVALID_SUBMISSION`

Score is parsed from stdout using:

```text
SCORE:\s*(\d+)
```

## Quick Start (Maintainer)

To operate leaderboard/project updates, configure:

- Repository variable: `PROJECT_ID` (ProjectV2 node id: `PVT_...`)
- Secret (recommended): `PROJECTS_TOKEN` with `project` scope

`GITHUB_TOKEN` should have permissions for PR comment and project update flows.

### GitHub Project Field Setup

Create (or verify) the following fields in your ProjectV2.

- `problem` (Text)
- `language` (Single select: `cpp`, `py`)
- `state` (Single select: `PASS`, `FAIL`)
- `min-score` (Number)
- `max-score` (Number)
- `last-state` (Text)
- `last-score` (Number)
- `last-time` (Number, ms)
- `last-memory` (Number, KB)

Automation files are under:

- `.github/workflows/judge.yml`
- `.github/judge/scripts/*`

## More Details

- Full spec and pipeline design: [docs/ONLINE_JUDGE.md](docs/ONLINE_JUDGE.md)
