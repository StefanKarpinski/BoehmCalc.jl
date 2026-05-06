module BoehmCalc

include("cancel.jl")
include("cr.jl")
include("transcendental.jl")
include("bounded.jl")

export with_timeout, CancelException
export MAX_RATIONAL_BITS

end # module BoehmCalc
