module BoehmCalc

include("cancel.jl")
include("cr.jl")
include("transcendental.jl")
include("bounded.jl")
include("property.jl")
include("exact.jl")

export with_timeout, CancelException
export MAX_RATIONAL_BITS
export ExactReal, is_rational, is_integer

end # module BoehmCalc
