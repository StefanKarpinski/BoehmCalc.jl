using BoehmCalc
using Test

@testset "show" begin
    @test sprint(show, ExactReal(1)) == "1"
    @test sprint(show, ExactReal(1//2)) == "1//2"
    @test sprint(show, ExactReal(0)) == "0"
    @test sprint(show, ExactReal(π)) == "π"
    @test sprint(show, ExactReal(2) * ExactReal(π)) == "2π"
    @test sprint(show, ExactReal(π) / ExactReal(4)) == "π/4"
    @test sprint(show, ExactReal(ℯ)) == "ℯ"
    @test sprint(show, sqrt(ExactReal(2))) == "√2"
    @test sprint(show, ExactReal(2) * sqrt(ExactReal(3))) == "2√3"

    # Decimal fallback for opaque values
    s = sprint(show, ExactReal(π) + sqrt(ExactReal(2)))
    @test occursin("…", s) || occursin(".", s)
end

@testset "text/latex" begin
    @test sprint(show, MIME"text/latex"(), ExactReal(π)) == "\$\\pi\$"
    @test sprint(show, MIME"text/latex"(), sqrt(ExactReal(2))) == "\$\\sqrt{2}\$"
    @test sprint(show, MIME"text/latex"(), ExactReal(π) / ExactReal(4)) == "\$\\frac{\\pi}{4}\$"
end
