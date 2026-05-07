# Commit Workflow

KeepMirror uses tracked git hooks to keep commits focused and messages consistent.

## One-time setup

```bash
./script/setup-git-hooks.sh
```

This sets `core.hooksPath` to `.githooks` for your clone.

## Rules enforced by hooks

- Conventional Commit format:
  - `type(scope): summary`
- Default staged-size limits:
  - max files: `12`
  - max changed lines (adds + deletes): `240`

Examples:

```text
feat(capture): add heif export fallback
fix(popover): stop camera before close animation
docs(readme): refresh usage and permissions
```

## One-off bypass

If you intentionally need a larger commit:

```bash
ALLOW_LARGE_COMMIT=1 git commit -m "chore(scope): summary"
```

Use bypasses sparingly and return to small commits.
