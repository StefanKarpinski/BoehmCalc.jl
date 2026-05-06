struct CancelException <: Exception end

mutable struct CancelToken
    cancelled::Threads.Atomic{Bool}
    CancelToken() = new(Threads.Atomic{Bool}(false))
end

cancel!(tok::CancelToken) = (tok.cancelled[] = true; nothing)

# Use ScopedValue on Julia 1.11+, task_local_storage on 1.10.
@static if isdefined(Base, :ScopedValue)
    const _current_token = Base.ScopedValue{Union{CancelToken,Nothing}}(nothing)

    _with_token(f, tok::CancelToken) = Base.with(f, _current_token => tok)
    current_token() = _current_token[]
else
    function _with_token(f, tok::CancelToken)
        prev = get(task_local_storage(), :_boehmcalc_cancel_token, nothing)
        task_local_storage()[:_boehmcalc_cancel_token] = tok
        try
            return f()
        finally
            task_local_storage()[:_boehmcalc_cancel_token] = prev
        end
    end
    current_token() = get(task_local_storage(), :_boehmcalc_cancel_token, nothing)
end

@inline function check_cancellation()
    tok = current_token()
    tok === nothing && return nothing
    tok.cancelled[] && throw(CancelException())
    return nothing
end

function with_timeout(f::Function, secs::Real)
    tok = CancelToken()
    timer = Timer(_ -> cancel!(tok), secs)
    try
        return _with_token(f, tok)
    finally
        close(timer)
    end
end
