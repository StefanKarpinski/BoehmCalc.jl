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

@testset "string with digits" begin
    @test BoehmCalc.string_decimal(ExactReal(π); digits=5)[1:5] == "3.141"
    @test startswith(BoehmCalc.string_decimal(ExactReal(1//3); digits=10), "0.333333333")
end

@testset "coverage" begin
    # _symbolic_string: Exp with arg != 1 (but rat_factor == 1) → "ℯ^arg"
    e2 = exp(ExactReal(2))
    @test sprint(show, e2) == "ℯ^2"

    # _symbolic_string: Ln with rat_factor == 1 → "ln(arg)"
    ln2 = log(ExactReal(2))
    @test sprint(show, ln2) == "ln(2)"

    # _symbolic_string: Irrational (no symbolic form) → decimal fallback
    irr = ExactReal(π) + sqrt(ExactReal(2))
    s = sprint(show, irr)
    @test occursin(".", s)

    # _wrap_rational: n == -1 with d != 1 → "-sym/d"
    neg_pi_over4 = -(ExactReal(π) / ExactReal(4))
    @test sprint(show, neg_pi_over4) == "-π/4"

    # _wrap_rational: n != ±1 and d != 1 → "n*sym/d"
    three_pi_over4 = ExactReal(3) * ExactReal(π) / ExactReal(4)
    @test sprint(show, three_pi_over4) == "3π/4"

    # _arg_string: rational (not integer) → "(n/d)"
    ln_2_3 = log(ExactReal(2//3 + 1))  # log(5//3) — arg is a rational with d != 1
    # Actually we need a Ln property: log(5//3) would need arg > 1
    ln_5_3 = log(ExactReal(5//3))
    s2 = sprint(show, ln_5_3)
    @test startswith(s2, "ln(") || occursin(".", s2)  # either symbolic or decimal fallback

    # _truncated_decimal: negative number
    s_neg = BoehmCalc.string_decimal(-ExactReal(π); digits=10)
    @test startswith(s_neg, "-3.14159")

    # _truncated_decimal: integer-valued result (no dot in BigFloat string)
    s_int = BoehmCalc.string_decimal(ExactReal(42))
    @test s_int == "42" || startswith(s_int, "42")

    # text/plain MIME: non-symbolic irrational shows "sym ≈ decimal"
    pi_val = ExactReal(π)
    s_plain = sprint(show, MIME"text/plain"(), pi_val)
    @test occursin("≈", s_plain)

    # text/plain MIME: rational shows just the number (calls show(io, x) path)
    s_rat = sprint(show, MIME"text/plain"(), ExactReal(1//3))
    @test s_rat == "1//3"

    # _latex_string: rational with d != 1 → \\frac
    @test sprint(show, MIME"text/latex"(), ExactReal(1//3)) == "\$\\frac{1}{3}\$"

    # _latex_string: rational integer
    @test sprint(show, MIME"text/latex"(), ExactReal(5)) == "\$5\$"

    # _latex_string: Exp with arg == 1 and rat_factor == 1 → "e"
    @test sprint(show, MIME"text/latex"(), ExactReal(ℯ)) == "\$e\$"

    # _latex_string: Irrational fallback → decimal
    s_lat_irr = sprint(show, MIME"text/latex"(), ExactReal(π) + sqrt(ExactReal(2)))
    @test startswith(s_lat_irr, "\$") && occursin(".", s_lat_irr)

    # _latex_wrap_rat: r == -1 → "-sym"
    @test sprint(show, MIME"text/latex"(), -ExactReal(π)) == "\$-\\pi\$"

    # _latex_wrap_rat: n == 1, d != 1 → "\\frac{sym}{d}"
    @test sprint(show, MIME"text/latex"(), ExactReal(π) / ExactReal(4)) == "\$\\frac{\\pi}{4}\$"

    # _latex_wrap_rat: n == int (not 1/-1), d != 1 → "\\frac{n*sym}{d}"
    s_3pi4 = sprint(show, MIME"text/latex"(), ExactReal(3) * ExactReal(π) / ExactReal(4))
    @test s_3pi4 == "\$\\frac{3\\pi}{4}\$"

    # string_decimal with non-default digits
    s_5dig = BoehmCalc.string_decimal(ExactReal(π); digits=5)
    @test startswith(s_5dig, "3.141")
end
