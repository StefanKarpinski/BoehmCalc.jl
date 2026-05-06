# Working in BoehmCalc.jl

This file is for Claude Code (and other AI assistants). Read this first.
For the design, read `SPEC.md`. For the contributor workflow, read
`CONTRIBUTING.md`.

## What this package is

A Julia implementation of Hans Boehm's "Towards an API for the Real Numbers"
(PLDI 2020). Three internal layers — `CR` (lazy approximator) →
`BoundedRational` helpers → `ExactReal <: Real` (upper symbolic layer with a
`Property` tag). Full design rationale in `SPEC.md`.

## Hard rules

- **`main` is branch-protected.** Never `git push` directly to it. Always
  branch (`feat/<name>`, `fix/<name>`, etc.), push the branch, open a PR
  with `gh pr create`. Don't merge your own PRs without the user asking —
  surface the PR URL and let them decide.
- **Don't bypass hooks.** No `--no-verify`, no `--no-gpg-sign`. If a hook
  fails, fix the underlying cause.
- **One TDD cycle = one commit.** Write the failing test, run it to confirm
  failure, implement the minimum to pass, run again, commit. Don't bundle
  multiple unrelated changes.
- **No emojis in code or commits** unless the user explicitly asks.

## Workflow

1. Read `SPEC.md` for the architectural picture before touching code.
2. For new features, follow the spec's "Open questions for follow-up" list —
   it's the v1.x roadmap. Don't invent scope.
3. TDD: red → green → commit. Use conventional-commit messages
   (`feat`, `fix`, `test`, `refactor`, `docs`, `chore`).
4. Run the full suite (`julia --project=. -e 'using Pkg; Pkg.test()'`)
   before opening a PR. The full suite is fast (~2 s).
5. Open a PR. Mention which `SPEC.md` section or v1.x deferral the change
   addresses, and call out any algorithm bugs you found in the existing
   code (be transparent — those notes have caught real issues).

## File layout

```
src/
├── BoehmCalc.jl        # module root + exports + include order
├── cancel.jl           # CancelException, with_timeout, check_cancellation
├── cr.jl               # abstract CR + IntCR, ShiftedCR, NegCR, AddCR, MulCR,
│                       #   InvCR, SelectCR, _shift, _make_cache, get_approx, msd
├── transcendental.jl   # BigFloatCR + SqrtCR, ExpCR, LnCR, CosCR, AtanCR,
│                       #   AsinCR, PiCR (all MPFR-backed)
├── bounded.jl          # MAX_RATIONAL_BITS, fits, try_*
├── property.jl         # Tag enum, Property, make_property, definitely_independent
├── exact.jl            # ExactReal struct + arithmetic + transcendentals + helpers
├── compare.jl          # is_comparable, ==, isless, definitely_equal/less,
│                       #   Base.decompose, Base.hash
├── convert.jl          # promote_rule + convert (in/out)
└── show.jl             # symbolic-aware show, text/latex MIME, string_decimal
```

The `include` order in `src/BoehmCalc.jl` matters — later files use names
from earlier ones. If you add a new file, slot it in dependency order.

Tests mirror the source: one `<name>_tests.jl` per `<name>.jl`, plus
`test/cr_test_corpus.jl` (CRTest.java port), `test/reals_doctest_corpus.jl`
(reals-crate doc-tests), `test/interop_tests.jl`. `test/runtests.jl` is just
the aggregator.

## Gotchas

These are real things that bit us during the v1 implementation. Future you
will be glad you read this section.

### `Tag.Irrational` shadows `Base.Irrational` in module scope

`Tag` (in `src/property.jl`) is `@enum Tag::UInt8 begin One Pi … Irrational end`.
The enum values become module-level bindings, so inside the `BoehmCalc`
module bare `Irrational` refers to the enum value, **not** `Base.Irrational`.

When you need the Julia abstract type for a method signature or constructor:

```julia
# WRONG — refers to the enum value, gives a TypeError
function ExactReal(x::Irrational{:π})
    ...
end

# RIGHT
function ExactReal(x::Base.Irrational{:π})
    ...
end
```

Bare `Property(Irrational, nothing)` is fine and intended — that's the enum.

### Julia's `_shift` vs Java's `BigInteger.shiftLeft(n)`

CR.java uses Java's convention where `shiftLeft(negative)` is a right-shift.
Our `_shift(x, n)` (in `src/cr.jl`) uses **positive `n` = right shift, negative
`n` = left shift**. Two real bugs were caught in the v1 work because the plan
transliterated CR.java directly. When porting algorithms from `CR.java`,
flip the sign of any shift count.

### Cancellation needs `yield()` after MPFR calls

Julia's `Timer` callback is Julia code. MPFR computations run in C with no
Julia yield points, so the timer never gets to flip the cancel flag. The fix
is in `src/transcendental.jl`'s `approximate(BigFloatCR, p)` — `yield()` then
`check_cancellation()` after `x.f(op_bf)`. If you add a new long-running
inner kernel, do the same.

### `inv()` only preserves Sqrt and Exp tags

`1/√r = √(1/r)` and `1/e^a = e^(-a)`, so `Sqrt` and `Exp` survive inversion.
For all other tags (Pi, Ln, etc.) we don't have a "1/X" tag, so `inv` drops
the tag to `Irrational`. This means e.g. `inv(π) * π == 1` returns `false`
under our conservative `==`. That's per spec; if it bothers you, the fix
would be a new `IrrationalConst`-style tag — see SPEC.md "Open questions".

### `==` is conservative

`==` returns `false` when the symbolic layer can't prove equality. This is
intentional. Cases that exercise this (and are documented in tests):
- `(√2 + 1)(√2 - 1) == 1` — would need symbolic polynomial expansion.
- `π + ℯ` computed two ways — the sums get `Irrational` tag and lose
  structural identity.

If you want a numeric-fallback comparison, build it as a separate function;
don't change the `==` semantics without updating SPEC.md and the spec tests.

### `==` requires field-level checks during arithmetic-only TDD

If you add new arithmetic before `compare.jl` is wired up (or in a branch
where `==` is stubbed out), use field-level assertions (`x.rat_factor == ...`,
`x.prop.tag == ...`) rather than `ExactReal == ExactReal` in tests.

## Debugging tips

- The CR layer has an approximation contract `|a · 2^p − x| < 2^p`. If a
  result is off, check that `_shift` is being used with the right sign and
  that the surrounding op subtype's `approximate` method preserves the
  contract. The `BigFloat`-comparison tests in `test/exact_tests.jl`
  ("numerical agreement with BigFloat") are good smoke tests.
- For a single failing test, run just that file:
  `julia --project=. test/<file>_tests.jl`. The aggregator wraps everything
  in one `@testset` but the per-file files stand alone.
- `bin/coverage` regenerates the local coverage report. Expect ~77% line
  coverage in v1; the gap is mostly error paths and rare-case branches.

## Don't

- Don't introduce hyperbolics, parser, or algebraic-number support without
  reading the v1.x deferral list in `SPEC.md`. Those need design discussion.
- Don't change `MAX_RATIONAL_BITS[]` default without measuring impact on the
  test suite — too low and rational arithmetic falls back to CR too eagerly,
  hurting symbolic equality; too high and pathological inputs build huge
  rationals.
- Don't merge `Base.Irrational{:γ}` (or any other irrational constant beyond
  π and ℯ) into a non-Irrational tag without a Lindemann–Weierstrass-grade
  independence proof against every existing tag. The bar for adding a tag
  is high; see SPEC.md §"Property normalization rules".

## When in doubt

Ask the user. The user has owned every architectural decision so far —
they'll tell you if a deviation is acceptable. Surface the trade-off; don't
silently choose for them.
