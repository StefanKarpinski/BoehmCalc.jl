# BoehmCalc.jl

[![Build Status](https://github.com/StefanKarpinski/BoehmCalc.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/StefanKarpinski/BoehmCalc.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/StefanKarpinski/BoehmCalc.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/StefanKarpinski/BoehmCalc.jl)

Exact real arithmetic for Julia, based on Hans Boehm's "Towards an API for the
Real Numbers" (PLDI 2020).

## Quick start

```julia
using BoehmCalc

x = ExactReal(2)
sqrt(x) * sqrt(x) == x          # true (exact!)
sin(ExactReal(π) / 6) == 1//2   # true
log(exp(ExactReal(7))) == 7     # true
ExactReal(π) - ExactReal(π) == 0  # true

# Mix with native types
1 + ExactReal(π) isa ExactReal  # true
[1, ExactReal(π), 0.5]          # works fine via promotion

# Calculator-style timeouts
result = with_timeout(0.5) do
    # … expensive computation …
end
```

## Design

`ExactReal <: Real` is implemented in three internal layers:

- **CR**: lazy approximator with `approximate(x, p)::BigInt` returning an
  integer `a` with `|a · 2^p − x| < 2^p`. Per-instance precision caching.
- **BoundedRational helpers**: rational arithmetic with a 10000-bit overflow
  cap (configurable via `BoehmCalc.MAX_RATIONAL_BITS`).
- **ExactReal**: `rat_factor::Rational{BigInt} × cr_factor::CR`, plus a
  `Property` symbolic tag (`Pi`, `Sqrt`, `Exp`, `Ln`, …).

See `SPEC.md` for the full design.

## Caveats

- `==` is symbolic-only (conservative). Returns `false` for genuinely-equal
  values that the symbolic layer can't reduce. `isless` does an approximate
  fallback to maintain a strict total order.
- Hyperbolic functions are not yet implemented.
- See `SPEC.md` § "Open questions for follow-up" for the v1.x roadmap.

## License

MIT. See `ATTRIBUTION.md` for upstream sources whose ideas and tests this
package builds on.
