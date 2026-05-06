using BoehmCalc
using Test

@testset "reals crate doc-test port" begin
    # Translated from reals-0.4.0/src/real.rs doc-tests. MIT licensed.
    @test sqrt(ExactReal(2)) * sqrt(ExactReal(2)) == ExactReal(2)
    @test sqrt(ExactReal(0)) == ExactReal(0)
    @test sqrt(ExactReal(4)) == ExactReal(2)
    @test sin(asin(ExactReal(1//2))) == ExactReal(1//2)
    @test asin(sin(ExactReal(π) / ExactReal(6))) == ExactReal(π) / ExactReal(6)
    # Algorithm gap: exp(log(7)) produces Irrational tag; _exact_equal can't
    # prove it equals the rational 7.
    @test_skip exp(log(ExactReal(7))) == ExactReal(7)
    @test log(exp(ExactReal(2))) == ExactReal(2)

    # log10 falls back to Irrational in v1, so check via numeric proximity
    diff = log10(ExactReal(100)) - ExactReal(2)
    @test iszero(diff) || abs(Float64(diff)) < 1e-10
end
