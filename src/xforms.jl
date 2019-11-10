#
# xforms.jl --
#
# Implementation of affine transforms which are notably useful for coordinate
# transforms.
#
#------------------------------------------------------------------------------
#
# This file if part of the TwoDimensional Julia package licensed under the MIT
# license (https://github.com/emmt/TwoDimensional.jl).
#
# Copyright (C) 2016-2019, Éric Thiébaut.
#

module AffineTransforms

export
    AffineTransform,
    compose,
    intercept,
    jacobian,
    rotate,
    scale,
    translate

# Imports for extension.
import Base: +, *, ∘, /, \, inv, eltype
import LinearAlgebra: ⋅, det

"""
# Affine 2D Transforms

An affine 2D transform `C` is defined by 6 real coefficients, `Cxx`, `Cxy`,
`Cx`, `Cyx`, `Cyy` and `Cy`.  Such a transform maps `(x,y)` as `(xp,yp)` given
by:

```julia
xp = Cxx*x + Cxy*y + Cx
yp = Cyx*x + Cyy*y + Cy
```

The immutable type `AffineTransform` is used to store an affine 2D transform
`C`, it can be created by:

```julia
I = AffineTransform{T}() # yields the identity with type T
C = AffineTransform{T}(Cxx, Cxy, Cx, Cyx, Cyy, Cy)
```

The `{T}` above is used to specify the floating-point type for the
coefficients; if omitted, `T = Float64` is assumed.


## Operations with affine 2D transforms

Many operations are available to manage or apply affine transforms:

```julia
(xp, yp) = A(x,y)       # idem
(xp, yp) = A*(x,y)      # idem
(xp, yp) = A(v)         # idem, with v = (x,y)
(xp, yp) = A*v          # idem

B = T(A)  # convert coefficients of transform A to be of type T
B = convert(AffineTransform{T}, A)  # idem

eltype(A)               # yields floating-point type of A

C = compose(A, B, ...)  # compose 2 (or more) transforms, C = apply B then A
C = A∘B                 # idem
C = A*B                 # idem
C = A⋅B                 # idem

B = translate(x, y, A)  # B = apply A then translate by (x,y)
B = translate(v, A)     # idem with v = (x,y)
B = v + A               # idem

B = translate(A, x, y)  # B = translate by (x,y) then apply A
B = translate(A, v)     # idem with v = (x,y)
B = A + v               # idem

B = rotate(θ, A)   # B = apply A then rotate by angle θ
C = rotate(A, θ)   # C = rotate by angle θ then apply A

B = scale(ρ, A)    # B = apply A then scale by ρ
B = ρ*A            # idem
C = scale(A, ρ)    # C = scale by ρ then apply A
C = A*ρ            # idem

B = inv(A)         # reciprocal coordinate transform
C = A/B            # right division, same as: C = compose(A, inv(B))
C = A\\B            # left division, same as: C = compose(inv(A), B)
```

"`∘`" and "`⋅`" can be typed by `\\circ<tab>` and `\\cdot<tab>`.


## Type conversion

As a general rule, the floating-point type `T` of an `AffineTransform{T}` is
imposed for all operations and for the result.  The floating-point type of the
composition of several coordinate transforms is the promoted type of the
transforms which have been composed.

To change the floating-point type of a 2D affine transform can be changed as
follows:

```julia
B = T(A)  # convert coefficients of transform A to be of type T
B = convert(AffineTransform{T}, A)  # idem
```

"""
struct AffineTransform{T<:AbstractFloat} <: Function
    xx::T
    xy::T
    x ::T
    yx::T
    yy::T
    y ::T
    AffineTransform{T}() where T = new{T}(1,0,0, 0,1,0)
    AffineTransform{T}(a11::Real, a12::Real, a13::Real,
                       a21::Real, a22::Real, a23::Real) where T =
                           new{T}(a11,a12,a13, a21,a22,a23)
end

eltype(::AffineTransform{T}) where {T} = T

# Use Float64 type by default.
AffineTransform() = AffineTransform{Float64}()
function AffineTransform(a11::Real, a12::Real, a13::Real,
                         a21::Real, a22::Real, a23::Real)
    return AffineTransform{Float64}(a11,a12,a13, a21,a22,a23)
end

# The following is a no-op when the destination type matches that of the
# source.
#
# The trick is to have a more restrictive signature than the general case
# above.  So the template type T for the result must have the same
# restrictions as in the general case.
#
# Another trick to remember: you can call a specific constructor, e.g.
# AffineTransform{Float16}, but this is not allowed for methods for which
# you must rely on Julia dispatching rules.
#
# When you make specialized versions of methods beware of infinite loops
# resulting from recursively calling the same method.  The diagnostic is a
# stack overflow.
#
function Base.convert(::Type{AffineTransform{T}},
                      A::AffineTransform{T}) where {T<:AbstractFloat}
    return A
end

function Base.convert(::Type{AffineTransform{T}},
                      A::AffineTransform) where {T<:AbstractFloat}
    return AffineTransform{T}(A.xx, A.xy, A.x, A.yx, A.yy, A.y)
end

for T in (:Float64, :Float32, :Float16)
    @eval Base.$T(A::AffineTransform) =
        convert(AffineTransform{$T}, A)
end
Base.MPFR.BigFloat(A::AffineTransform) =
    convert(AffineTransform{Base.MPFR.BigFloat}, A)

#------------------------------------------------------------------------------
# apply the transform to some coordinates:

(A::AffineTransform{T})(x::T, y::T) where {T<:AbstractFloat} =
    (A.xx*x + A.xy*y + A.x,
     A.yx*x + A.yy*y + A.y)

(A::AffineTransform{T})(x::Real, y::Real) where {T<:AbstractFloat} =
    A(convert(T, x), convert(T, y))

(A::AffineTransform)(v::Tuple{Real,Real}) = A(v[1], v[2])

#------------------------------------------------------------------------------
# Combine a translation with an affine transform.

"""
### Translating an affine transform

Affine transforms can be letf- or right-translated.

```julia
translate(x, y, A)
```
or
```julia
translate((x,y), A)
```

yield an affine transform which translate the output of affine transform `A` by
offsets `x` and `y`.

```julia
translate(A, x, y)
```
or
```julia
translate(A, (x,y))
```

yield an affine transform which translate the input of affine transform `A` by
offsets `x` and `y`.

The same results can be obtained with the `+` operator:

```julia
B = (x,y) + A    # same as: B = translate((x,y), A)
B = A + (x,y)    # same as: B = translate(A, (x,y))
```

See also: [`AffineTransform`](@ref), [`rotate`](@ref), [`scale`](@ref).

""" translate

# Left-translating results in translating the output of the transform.
translate(x::T, y::T, A::AffineTransform{T}) where {T<:AbstractFloat} =
    AffineTransform{T}(A.xx, A.xy, A.x + x,
                       A.yx, A.yy, A.y + y)

translate(x::Real, y::Real, A::AffineTransform{T}) where {T<:AbstractFloat} =
    translate(convert(T, x), convert(T, y), A)

translate(v::Tuple{Real,Real}, A::AffineTransform) =
    translate(v[1], v[2], A)

# Right-translating results in translating the input of the transform.
translate(A::AffineTransform{T}, x::T, y::T) where {T<:AbstractFloat} =
    AffineTransform{T}(A.xx, A.xy, A.xx*x + A.xy*y + A.x,
                       A.yx, A.yy, A.yx*x + A.yy*y + A.y)

translate(A::AffineTransform{T}, x::Real, y::Real) where {T<:AbstractFloat} =
    translate(A, convert(T, x), convert(T, y))

translate(A::AffineTransform, v::Tuple{Real,Real}) =
    translate(A, v[1], v[2])

#------------------------------------------------------------------------------
"""
### Scaling an affine transform

There are two ways to combine a scaling by a factor `ρ` with an affine
transform `A`.  Left-scaling as in:

```julia
B = scale(ρ, A)
```

results in scaling the output of the transform; while right-scaling as in:

```julia
C = scale(A, ρ)
```

results in scaling the input of the transform.  The above examples yield
transforms which behave as:

```julia
B(v) = ρ.*A(v)
C(v) = A(ρ.*v)
```

where `v` is any 2-element tuple.

The same results can be obtained with the `*` operator:

```julia
B = ρ*A    # same as: B = scale(ρ, A)
C = A*ρ    # same as: B = scale(A, ρ)
```

See also: [`AffineTransform`](@ref), [`rotate`](@ref), [`translate`](@ref).

"""
scale(ρ::T, A::AffineTransform{T}) where {T<:AbstractFloat} =
    AffineTransform{T}(ρ*A.xx, ρ*A.xy, ρ*A.x,
                       ρ*A.yx, ρ*A.yy, ρ*A.y)

scale(A::AffineTransform{T}, ρ::T) where {T<:AbstractFloat} =
    AffineTransform{T}(ρ*A.xx, ρ*A.xy, A.x,
                       ρ*A.yx, ρ*A.yy, A.y)

#------------------------------------------------------------------------------
"""
### Rotating an affine transform

There are two ways to combine a rotation by angle `θ` (in radians
counterclockwise) with an affine transform `A`.  Left-rotating as in:

```julia
B = rotate(θ, A)
```

results in rotating the output of the transform; while right-rotating as in:

```julia
C = rotate(A, θ)
```

results in rotating the input of the transform.  The above examples are
similar to:

```julia
B = R∘A
C = A∘R
```

where `R` implements rotation by angle `θ` around `(0,0)`.


See also: [`AffineTransform`](@ref), [`scale`](@ref), [`translate`](@ref).

"""
function rotate(θ::T, A::AffineTransform{T}) where {T<:AbstractFloat}
    cs = cos(θ)
    sn = sin(θ)
    return AffineTransform{T}(cs*A.xx - sn*A.yx,
                              cs*A.xy - sn*A.yy,
                              cs*A.x  - sn*A.y,
                              cs*A.yx + sn*A.xx,
                              cs*A.yy + sn*A.xy,
                              cs*A.y  + sn*A.x)
end

function rotate(A::AffineTransform{T}, θ::T) where {T<:AbstractFloat}
    cs = cos(θ)
    sn = sin(θ)
    return AffineTransform{T}(A.xx*cs + A.xy*sn,
                              A.xy*cs - A.xx*sn,
                              A.x,
                              A.yx*cs + A.yy*sn,
                              A.yy*cs - A.yx*sn,
                              A.y)
end

# Make sure the floating-point type of an affine transform is preserved.
for func in (:scale, :rotate)
    @eval begin
        $func(α::Real, A::AffineTransform{T}) where {T<:AbstractFloat} =
            $func(convert(T, α), A)
        $func(A::AffineTransform{T}, α::Real) where {T<:AbstractFloat} =
            $func(A, convert(T, α))
    end
end

#------------------------------------------------------------------------------

"""
`det(A)` returns the determinant of the linear part of the affine
transform `A`.
"""
det(A::AffineTransform) = A.xx*A.yy - A.xy*A.yx

"""
`jacobian(A)` returns the Jacobian of the affine transform `A`, that is the
absolute value of the determinant of its linear part.
"""
jacobian(A::AffineTransform) = abs(det(A))

"""
`inv(A)` returns the inverse of the affine transform `A`.
"""
function inv(A::AffineTransform{T}) where {T<:AbstractFloat}
    d = det(A)
    d == zero(T) && error("transformation is not invertible")
    Txx =  A.yy/d
    Txy = -A.xy/d
    Tyx = -A.yx/d
    Tyy =  A.xx/d
    return AffineTransform{T}(Txx, Txy, -Txx*A.x - Txy*A.y,
                              Tyx, Tyy, -Tyx*A.x - Tyy*A.y)
end

"""

`compose(A,B)` yields the affine transform which combines the two affine
transforms `A` and `B`, that is the affine transform which applies `B` and then
`A`.  Composition is accessible via: `A∘B`, `A*B` or `A⋅B` ("`∘`" and "`⋅`" can
be typed by `\\circ<tab>` and `\\cdot<tab>`).

It is possible to compose more than two affine transforms.  For instance,
`compose(A,B,C)` yields the affine transform which applies `C` then `B`, then
`A`.

"""
compose() = error("missing argument(s)")

compose(A::AffineTransform) = A

compose(A::AffineTransform, B::AffineTransform) = __compose(A, B)

compose(args::AffineTransform...) =
    compose(__compose(args[1], args[2]), args[3:end]...)

function __compose(A::AffineTransform{Ta},
                   B::AffineTransform{Tb}) where {Ta, Tb}
    T = promote_type(Ta, Tb)
    return AffineTransform{T}(A.xx*B.xx + A.xy*B.yx,
                              A.xx*B.xy + A.xy*B.yy,
                              A.xx*B.x  + A.xy*B.y + A.x,
                              A.yx*B.xx + A.yy*B.yx,
                              A.yx*B.xy + A.yy*B.yy,
                              A.yx*B.x  + A.yy*B.y + A.y)
end

"""

`rightdivide(A,B)` yields `A/B`, the right division of the affine
transform `A` by the affine transform `B`.

"""
function rightdivide(A::AffineTransform{T},
                     B::AffineTransform{T}) where {T<:AbstractFloat}
    d = det(B)
    d == zero(T) && error("right operand is not invertible")
    Rxx = (A.xx*B.yy - A.xy*B.yx)/d
    Rxy = (A.xy*B.xx - A.xx*B.xy)/d
    Ryx = (A.yx*B.yy - A.yy*B.yx)/d
    Ryy = (A.yy*B.xx - A.yx*B.xy)/d
    return AffineTransform{T}(Rxx, Rxy, A.x - (Rxx*B.x + Rxy*B.y),
                              Ryx, Ryy, A.y - (Ryx*B.y + Ryy*B.y))

end

"""
`leftdivide(A,B)` yields `A\\B`, the left division of the affine
transform `A` by the affine transform `B`.
"""
function leftdivide(A::AffineTransform{T},
                    B::AffineTransform{T}) where {T<:AbstractFloat}
    d = det(A)
    d == zero(T) && error("left operand is not invertible")
    Txx =  A.yy/d
    Txy = -A.xy/d
    Tyx = -A.yx/d
    Tyy =  A.xx/d
    Tx = B.x - A.x
    Ty = B.y - A.y
    return AffineTransform{T}(Txx*B.xx + Txy*B.yx,
                              Txx*B.xy + Txy*B.yy,
                              Txx*Tx   + Txy*Ty,
                              Tyx*B.xx + Tyy*B.yx,
                              Tyx*B.xy + Tyy*B.yy,
                              Tyx*Tx   + Tyy*Ty)
end

for func in (:rightdivide, :leftdivide)
    @eval begin
        function $func(A::AffineTransform{Ta},
                       B::AffineTransform{Tb}) where {Ta<:AbstractFloat,
                                                      Tb<:AbstractFloat}
            T = AffineTransform{promote_type(Ta, Tb)}
            return $func(convert(T, A), convert(T, B))
        end
    end
end

"""

`intercept(A)` returns the tuple `(x,y)` such that `A(x,y) = (0,0)`.

"""
function intercept(A::AffineTransform{T}) where {T<:AbstractFloat}
    d = det(A)
    d == zero(T) && error("transformation is not invertible")
    return ((A.xy*A.y - A.yy*A.x)/d, (A.yx*A.x - A.xx*A.y)/d)
end


+(v::Tuple{Real,Real}, A::AffineTransform) = translate(v, A)

+(A::AffineTransform, v::Tuple{Real,Real}) = translate(A, v)

for op in (:∘, :*, :⋅)
    @eval begin
        $op(A::AffineTransform, B::AffineTransform) = compose(A, B)
    end
end

*(A::AffineTransform, v::Tuple{Real,Real}) = A(v)

*(ρ::Real, A::AffineTransform) = scale(ρ, A)

*(A::AffineTransform, ρ::Real) = scale(A, ρ)

\(A::AffineTransform, B::AffineTransform) = leftdivide(A, B)

/(A::AffineTransform, B::AffineTransform) = rightdivide(A, B)

Base.show(io::IO, ::MIME"text/plain", A::AffineTransform) =
    print(io, typeof(A),
          "(",   A.xx, ",", A.xy, ",", A.x,
          ",  ", A.yx, ",", A.yy, ",", A.y, ")")

Base.show(io::IO, A::AffineTransform) = show(io, MIME"text/plain"(), A)

Base.print(io::IOBuffer, A::AffineTransform) = show(io, A)

end # module
