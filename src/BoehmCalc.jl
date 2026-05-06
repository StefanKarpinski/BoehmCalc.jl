module BoehmCalc

include("cancel.jl")
include("cr.jl")
include("transcendental.jl")

export with_timeout, CancelException

end # module BoehmCalc
