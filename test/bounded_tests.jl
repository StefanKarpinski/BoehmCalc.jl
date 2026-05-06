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
end
