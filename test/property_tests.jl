using BoehmCalc
using BoehmCalc: Property, make_property, definitely_independent
using Test

# @enum-defined values are module-level bindings in BoehmCalc, not nested
# under the type name. Use BoehmCalc.One, BoehmCalc.Pi, etc.
@testset "Property" begin
    @test Property(BoehmCalc.One, nothing).tag == BoehmCalc.One

    # Sqrt(4) is a perfect square, normalizes to One
    @test make_property(BoehmCalc.Sqrt, Rational{BigInt}(4)).tag == BoehmCalc.One
    # Sqrt(2) stays Sqrt
    @test make_property(BoehmCalc.Sqrt, Rational{BigInt}(2)).tag == BoehmCalc.Sqrt
    # Sqrt(8) = 2 * sqrt(2) — normalizer extracts square factors
    p = make_property(BoehmCalc.Sqrt, Rational{BigInt}(8))
    @test p.tag == BoehmCalc.Sqrt && p.arg == Rational{BigInt}(2)

    # Ln(1) = 0 (normalizes to One/zero)
    @test make_property(BoehmCalc.Ln, Rational{BigInt}(1)).tag == BoehmCalc.One

    # Independence: Pi vs Sqrt(2) are independent
    @test definitely_independent(Property(BoehmCalc.Pi, nothing),
                                  make_property(BoehmCalc.Sqrt, Rational{BigInt}(2)))
    # Same property is NOT independent
    @test !definitely_independent(Property(BoehmCalc.Pi, nothing),
                                   Property(BoehmCalc.Pi, nothing))

    # _extract_square handles large square factors (prime > 1000)
    big_prime = BigInt(1_000_003)
    @test make_property(BoehmCalc.Sqrt, Rational{BigInt}(big_prime^2)).tag == BoehmCalc.One
    @test make_property(BoehmCalc.Sqrt, Rational{BigInt}(big_prime^2 * 2)) ==
          Property(BoehmCalc.Sqrt, Rational{BigInt}(2))

    # Ln domain: requires arg > 1
    @test_throws DomainError make_property(BoehmCalc.Ln, Rational{BigInt}(1, 2))
    @test_throws DomainError make_property(BoehmCalc.Ln, Rational{BigInt}(0))
    @test_throws DomainError make_property(BoehmCalc.Ln, Rational{BigInt}(-1))

    # Sqrt domain: requires arg > 0
    @test_throws DomainError make_property(BoehmCalc.Sqrt, Rational{BigInt}(0))
    @test_throws DomainError make_property(BoehmCalc.Sqrt, Rational{BigInt}(-1))

    @testset "coverage" begin
        # make_property One/Pi/Irrational path (returns Property with nothing arg)
        @test make_property(BoehmCalc.One, nothing).tag == BoehmCalc.One
        @test make_property(BoehmCalc.Pi, nothing).tag == BoehmCalc.Pi
        @test make_property(BoehmCalc.Irrational, nothing).tag == BoehmCalc.Irrational

        # Property constructor: arg !== nothing for One/Pi/Irrational throws
        @test_throws ArgumentError Property(BoehmCalc.One, Rational{BigInt}(1))
        @test_throws ArgumentError Property(BoehmCalc.Pi, Rational{BigInt}(1))

        # Property constructor: arg === nothing for a tag that requires arg throws
        @test_throws ArgumentError Property(BoehmCalc.Sqrt, nothing)
        @test_throws ArgumentError Property(BoehmCalc.Exp, nothing)
        @test_throws ArgumentError Property(BoehmCalc.Ln, nothing)

        # _extract_square with denominator having square factors: e.g. 1//8 = 1/8
        # 8 = 4*2, so sqrt(1//8) has sq_d = 2 and rem_d = 2
        p_1_8 = make_property(BoehmCalc.Sqrt, Rational{BigInt}(1, 8))
        @test p_1_8.tag == BoehmCalc.Sqrt
        # The square-free remainder should be 1//2 (= 1/2 after extracting 2^2 from 8)
        @test p_1_8.arg == Rational{BigInt}(1, 2)

        # make_property Log: positive arg, not 1 → Log
        p_log2 = make_property(BoehmCalc.Log, Rational{BigInt}(2))
        @test p_log2.tag == BoehmCalc.Log && p_log2.arg == Rational{BigInt}(2)
        # Log(1) → One
        @test make_property(BoehmCalc.Log, Rational{BigInt}(1)).tag == BoehmCalc.One
        # Log domain: arg <= 0
        @test_throws DomainError make_property(BoehmCalc.Log, Rational{BigInt}(0))
        @test_throws DomainError make_property(BoehmCalc.Log, Rational{BigInt}(-1))

        # make_property SinPi and TanPi
        p_sin = make_property(BoehmCalc.SinPi, Rational{BigInt}(1, 5))
        @test p_sin.tag == BoehmCalc.SinPi && p_sin.arg == Rational{BigInt}(1, 5)
        p_tan = make_property(BoehmCalc.TanPi, Rational{BigInt}(1, 5))
        @test p_tan.tag == BoehmCalc.TanPi && p_tan.arg == Rational{BigInt}(1, 5)

        # make_property Asin(0) → One; Asin(non-zero) → Asin
        @test make_property(BoehmCalc.Asin, Rational{BigInt}(0)).tag == BoehmCalc.One
        p_asin = make_property(BoehmCalc.Asin, Rational{BigInt}(1, 3))
        @test p_asin.tag == BoehmCalc.Asin && p_asin.arg == Rational{BigInt}(1, 3)

        # make_property Atan(0) → One; Atan(non-zero) → Atan
        @test make_property(BoehmCalc.Atan, Rational{BigInt}(0)).tag == BoehmCalc.One
        p_atan = make_property(BoehmCalc.Atan, Rational{BigInt}(1, 3))
        @test p_atan.tag == BoehmCalc.Atan && p_atan.arg == Rational{BigInt}(1, 3)

        # definitely_independent: algebraic vs transcendental
        sqrt2_prop = make_property(BoehmCalc.Sqrt, Rational{BigInt}(2))
        exp1_prop  = make_property(BoehmCalc.Exp, Rational{BigInt}(1))
        @test definitely_independent(sqrt2_prop, exp1_prop)   # algebraic vs transcendental
        @test definitely_independent(exp1_prop, sqrt2_prop)   # symmetric

        # definitely_independent: same family (Exp) different args
        exp1  = make_property(BoehmCalc.Exp, Rational{BigInt}(1))
        exp2  = make_property(BoehmCalc.Exp, Rational{BigInt}(2))
        @test definitely_independent(exp1, exp2)

        # definitely_independent: same family (Ln) different args
        ln2_prop = make_property(BoehmCalc.Ln, Rational{BigInt}(2))
        ln3_prop = make_property(BoehmCalc.Ln, Rational{BigInt}(3))
        @test definitely_independent(ln2_prop, ln3_prop)

        # definitely_independent: same property returns false
        @test !definitely_independent(exp1, exp1)
        @test !definitely_independent(sqrt2_prop, sqrt2_prop)

        # definitely_independent: Sqrt vs Pi
        pi_prop = Property(BoehmCalc.Pi, nothing)
        @test definitely_independent(pi_prop, sqrt2_prop)
        @test definitely_independent(sqrt2_prop, pi_prop)
    end
end
