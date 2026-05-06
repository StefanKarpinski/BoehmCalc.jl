using BoehmCalc
using BoehmCalc: ExactReal, is_rational, is_integer
using Test

@testset "ExactReal construction" begin
    a = ExactReal(0)
    @test iszero(a) && is_rational(a) && is_integer(a)

    b = ExactReal(3)
    @test is_integer(b)

    c = ExactReal(1//2)
    @test is_rational(c) && !is_integer(c)
end
