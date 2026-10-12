# CRS Context Sync

This repository stores the shared context files for the CRS project:

- `AGENTS.md`
- `.agents/`
- `.business-spec/`
- `.specs/`

## Local machine configuration

Create `.env` from the example file:

```bash
cp .env.example .env
```

Then set `PROJECT_DIR` to the absolute path of the `gap-web-backend` project on
the current machine:

```dotenv
PROJECT_DIR=/Users/nexusfrontiertech/projects/gap-web-backend
```

`.env` contains machine-specific configuration and must not be committed.

## Sync from the repository to the project

Run this from the repository:

```bash
./sync-to-project.sh
```

The script copies `AGENTS.md`, `.agents/`, `.business-spec/`, and `.specs/` to
the project configured in `PROJECT_DIR`. It does not delete extra files in the
destination project.

## Sync from the project to the repository

After editing the context files in the backend project, run the export script
from `~/projects`:

```bash
~/projects/sync-crs-context.sh
```

The script copies the context files into this repository, creates a commit, and
pushes it to the `origin` remote on the current branch. If there are no changes,
it does not create an empty commit.

## Set up on a new machine

```bash
cd ~/projects
git clone git@github.com:light-nguyen-0409/sync-crs-context.git sync-crs-context
cd sync-crs-context
cp .env.example .env
```

Set `PROJECT_DIR` in `.env`, then run:

```bash
./sync-to-project.sh
```

The scripts require Bash, Git, and `rsync`.
