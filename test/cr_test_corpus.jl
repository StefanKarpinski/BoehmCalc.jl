using BoehmCalc
using Test

@testset "CRTest.java port" begin
    # Translation of HP creals CRTest.java assertions.
    # License: HP/SGI permissive (preserved in ATTRIBUTION.md).

    # Basic arithmetic
    @test ExactReal(1) + ExactReal(2) == ExactReal(3)
    @test ExactReal(1) - ExactReal(2) == ExactReal(-1)
    @test ExactReal(2) * ExactReal(3) == ExactReal(6)
    @test ExactReal(6) / ExactReal(2) == ExactReal(3)

    # Sqrt
    @test sqrt(ExactReal(4)) == ExactReal(2)
    @test sqrt(ExactReal(2)) * sqrt(ExactReal(2)) == ExactReal(2)
    # Algorithm gap: (√2+1)(√2-1) creates an Irrational-tagged sum whose
    # _exact_equal path does not fall back to CR approximation for equality.
    # v1.x: requires symbolic polynomial expansion
    @test_broken (sqrt(ExactReal(2)) + ExactReal(1)) * (sqrt(ExactReal(2)) - ExactReal(1)) == ExactReal(1)

    # Trig
    @test sin(ExactReal(0)) == ExactReal(0)
    @test cos(ExactReal(0)) == ExactReal(1)
    @test sin(ExactReal(π) / ExactReal(6)) == ExactReal(1//2)
    @test cos(ExactReal(π) / ExactReal(3)) == ExactReal(1//2)

    # Exp/log
    @test log(exp(ExactReal(1))) == ExactReal(1)
    @test exp(log(ExactReal(2))) == ExactReal(2)
    @test log(ExactReal(ℯ)) == ExactReal(1)

    # Atan
    @test atan(ExactReal(1)) == ExactReal(π) / ExactReal(4)
    @test ExactReal(4) * atan(ExactReal(1)) == ExactReal(π)

    # Asin
    @test asin(ExactReal(1)) == ExactReal(π) / ExactReal(2)
    @test asin(ExactReal(0)) == ExactReal(0)
    @test asin(ExactReal(1//2)) == ExactReal(π) / ExactReal(6)
end
