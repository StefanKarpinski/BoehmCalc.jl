# Contributing to BoehmCalc.jl

## Branches and pull requests

`main` is protected — direct pushes are rejected. All changes land via pull
request:

```bash
# Start work on a topic branch
git checkout -b feat/<short-name>

# … commit work …

git push -u origin feat/<short-name>
gh pr create --fill        # or open the PR via the GitHub UI
```

CI must be green before merging. Branch names follow the conventional-commit
type: `feat/`, `fix/`, `test/`, `refactor/`, `docs/`, `chore/`.

## Development workflow

```bash
# Run tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Run a single test file (file uses `using BoehmCalc, Test` at top)
julia --project=. test/exact_tests.jl

# Coverage report (locally)
bin/coverage
```

## Commit conventions

We use conventional commits: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`.
Each commit should be one logical change. Each TDD cycle (failing test →
implementation → passing test) is one commit.

## Coverage target

We aim for ≥95% line coverage in `src/`. PRs that drop coverage by more than
2 points need justification (e.g. a test platform doesn't support a feature).

## Adding a new operation

1. Add a Property tag in `src/property.jl` if it needs symbolic identity.
2. Add a `*CR` op subtype in `src/cr.jl` or `src/transcendental.jl`.
3. Add the user-facing function in `src/exact.jl` with the tag-dispatch case-split.
4. Add tests in `test/exact_tests.jl`.

## Reading order for new contributors

1. `SPEC.md` — design rationale.
2. `src/cr.jl` — the lower CR layer.
3. `src/exact.jl` — the upper ExactReal layer.
4. The Boehm paper (linked in `ATTRIBUTION.md`).
