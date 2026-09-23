# Contributing

## Branches
- `main` — released, always stable. Only updated by release PRs from `dev`.
- `dev` — integration branch. All work lands here first.
- `feat/*`, `fix/*`, `chore/*`, `perf/*` — short-lived branches cut from `dev`.

## Pull requests
1. Branch from `dev`, keep the PR focused on one change.
2. Title in [Conventional Commits](https://www.conventionalcommits.org) style, e.g. `feat: meeting detection`.
3. CI (build + tests) must pass before merging.
4. Feature PRs into `dev` are **squash merged**. Release PRs `dev → main` use a **merge commit**.

## Local checks
```sh
make test   # unit + integration tests
make run    # build the .app and launch it
```
