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
end
