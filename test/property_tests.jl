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
end
