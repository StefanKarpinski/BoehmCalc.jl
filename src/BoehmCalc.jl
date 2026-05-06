module BoehmCalc

include("cancel.jl")
include("cr.jl")
include("transcendental.jl")
include("bounded.jl")
include("property.jl")
include("exact.jl")
include("compare.jl")

export with_timeout, CancelException
export MAX_RATIONAL_BITS
export ExactReal, is_rational, is_integer
export is_comparable, definitely_equal

end # module BoehmCalc
