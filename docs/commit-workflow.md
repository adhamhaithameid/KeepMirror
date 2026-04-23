# Commit Workflow

KeepMirror uses tracked git hooks to enforce small, clean commits and Conventional Commit messages.

## One-time setup

Run:

```bash
./script/setup-git-hooks.sh
```

This sets `core.hooksPath` to `.githooks` for your local clone.

## Commit rules

- Use Conventional Commits: `type(scope): summary`
- Keep changes focused and small
- Default staged-change limits:
  - maximum staged files: `12`
  - maximum changed lines (adds + deletes): `240`

Examples:

```text
feat(menu): add pinned duration quick actions
fix(settings): persist default duration id correctly
docs(readme): update installation steps
```

## Temporary bypass

If a one-off larger commit is absolutely required:

```bash
ALLOW_LARGE_COMMIT=1 git commit -m "chore(scope): summary"
```

Use bypasses sparingly and return to small commits immediately.
