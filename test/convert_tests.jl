using BoehmCalc
using Test

@testset "convert + promote" begin
    @test 1 + ExactReal(π) isa ExactReal
    @test ExactReal(2) + 0.5 isa ExactReal
    @test 1//3 + ExactReal(1) isa ExactReal

    # Conversion preserves exact value
    @test ExactReal(0.1) == convert(ExactReal, 0.1)
    @test ExactReal(0.1) != ExactReal(1//10)         # Float64 0.1 != 1/10 exactly

    # Float64 → ExactReal: literal binary value
    bf = Rational{BigInt}(0.1)   # the exact binary rational
    @test ExactReal(0.1).rat_factor == bf

    @testset "conversion out" begin
        @test Float64(ExactReal(0)) == 0.0
        @test Float64(ExactReal(1//4)) == 0.25
        @test Float64(ExactReal(π)) === Float64(π)

        bf = BigFloat(ExactReal(π); precision=128)
        @test abs(BigFloat(π; precision=128) - bf) < BigFloat(2)^-126

        @test Rational{BigInt}(ExactReal(0)) == 0//1
        @test Rational{BigInt}(ExactReal(3//7)) == 3//7
        @test_throws InexactError Rational{BigInt}(ExactReal(π))

        @test BigInt(ExactReal(42)) == 42
        @test_throws InexactError BigInt(ExactReal(1//2))

        # Float32 and Float16 conversions
        @test Float32(ExactReal(1//4)) === 0.25f0
        @test Float16(ExactReal(1//4)) === Float16(0.25)

        # Float32/Float16 of irrational
        @test Float32(ExactReal(π)) ≈ Float32(π)
        @test Float16(ExactReal(π)) ≈ Float16(π)

        # BigFloat with explicit non-default precision
        bf_low  = BigFloat(ExactReal(π); precision=32)
        bf_high = BigFloat(ExactReal(π); precision=256)
        @test abs(BigFloat(π; precision=256) - bf_high) < BigFloat(2)^-254

        # BigInt of a non-integer ExactReal (InexactError)
        @test_throws InexactError BigInt(ExactReal(π))
    end
end
