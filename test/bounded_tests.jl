using BoehmCalc
using BoehmCalc: MAX_RATIONAL_BITS, fits, try_add, try_sub, try_mul, try_div
using Test

@testset "BoundedRational helpers" begin
    @test fits(Rational{BigInt}(1, 2))
    @test fits(Rational{BigInt}(BigInt(2)^9000, 1))
    @test !fits(Rational{BigInt}(BigInt(2)^11000, 1))   # > MAX_RATIONAL_BITS

    @test try_add(Rational{BigInt}(1, 2), Rational{BigInt}(1, 3)) == Rational{BigInt}(5, 6)
    huge = Rational{BigInt}(BigInt(2)^9000, 1)
    @test try_mul(huge, huge) === nothing               # would exceed cap

    @test try_sub(Rational{BigInt}(2, 3), Rational{BigInt}(1, 3)) == Rational{BigInt}(1, 3)
    @test try_div(Rational{BigInt}(1, 2), Rational{BigInt}(1, 3)) == Rational{BigInt}(3, 2)
    @test try_div(Rational{BigInt}(1, 2), Rational{BigInt}(0)) === nothing   # divide by zero

    # try_pow
    @test BoehmCalc.try_pow(Rational{BigInt}(2), 10) == Rational{BigInt}(1024)
    @test BoehmCalc.try_pow(Rational{BigInt}(1, 2), 3) == Rational{BigInt}(1, 8)
    @test BoehmCalc.try_pow(Rational{BigInt}(2), 0) == Rational{BigInt}(1)
    @test BoehmCalc.try_pow(Rational{BigInt}(2), -3) == Rational{BigInt}(1, 8)
    # Overflow bail-out: 2^15000 exceeds MAX_RATIONAL_BITS = 10000
    @test BoehmCalc.try_pow(Rational{BigInt}(2), 15000) === nothing

    # try_sqrt_exact
    @test BoehmCalc.try_sqrt_exact(Rational{BigInt}(0)) == Rational{BigInt}(0)
    @test BoehmCalc.try_sqrt_exact(Rational{BigInt}(4)) == Rational{BigInt}(2)
    @test BoehmCalc.try_sqrt_exact(Rational{BigInt}(9, 4)) == Rational{BigInt}(3, 2)
    @test BoehmCalc.try_sqrt_exact(Rational{BigInt}(2)) === nothing      # not a perfect square
    @test BoehmCalc.try_sqrt_exact(Rational{BigInt}(-1)) === nothing     # negative
end
