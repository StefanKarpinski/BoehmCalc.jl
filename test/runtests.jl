using BoehmCalc
using Test

@testset "BoehmCalc" begin
    include("cancel_tests.jl")
    include("cr_tests.jl")
    include("transcendental_tests.jl")
    include("bounded_tests.jl")
    include("property_tests.jl")
    include("exact_tests.jl")
    include("compare_tests.jl")
    include("convert_tests.jl")
    include("show_tests.jl")
    include("interop_tests.jl")
    include("cr_test_corpus.jl")
    include("reals_doctest_corpus.jl")
end
