function is_comparable(a::ExactReal, b::ExactReal)
    iszero(a) && iszero(b) && return true
    a.prop == b.prop && return true
    a.prop.tag == Sqrt && b.prop.tag == Sqrt && return true
    if definitely_independent(a.prop, b.prop)
        if _magnitude_ge(a, -5000) || _magnitude_ge(b, -5000) || iszero(a) || iszero(b)
            return true
        end
    end
    diff = (a - b).cr_factor
    delta = get_approx(diff, -100)
    abs(delta) > 2 && return true
    return false
end

function definitely_equal(a::ExactReal, b::ExactReal)
    is_comparable(a, b) || return false
    return _exact_equal(a, b)
end

function _exact_equal(a::ExactReal, b::ExactReal)
    iszero(a) && iszero(b) && return true
    iszero(a) != iszero(b) && return false
    if a.prop == b.prop
        return a.rat_factor == b.rat_factor
    end
    if a.prop.tag == Sqrt && b.prop.tag == Sqrt
        # Compare squared values: rat_factor^2 * arg, with sign tracking.
        sq_a = a.rat_factor^2 * a.prop.arg
        sq_b = b.rat_factor^2 * b.prop.arg
        sign_a = sign(a.rat_factor); sign_b = sign(b.rat_factor)
        return sq_a == sq_b && sign_a == sign_b
    end
    return false
end

# True iff |x| >= 2^p (cheap CR-level magnitude check).
function _magnitude_ge(x::ExactReal, p::Int)
    iszero(x) && return false
    a = get_approx(x.cr_factor, p)
    return abs(a) > 1
end

Base.:(==)(a::ExactReal, b::ExactReal) = definitely_equal(a, b)
