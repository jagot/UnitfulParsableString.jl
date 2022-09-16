module UnitfulParsableString

using Unitful
using Unitful: # unexported Struct 
	Unit, Unitlike, Units, Affine, MixedUnits, LogScaled, Gain, Level
using Unitful: # need for print
	prefix, abbr, power, ustrcheck_bool
using Memoization

has_value_bracket(x::Quantity) = has_value_bracket(x.val)
has_value_bracket(::Union{Gain, Level}) = true
has_value_bracket(::Union{Complex, Rational}) = true
has_value_bracket(::Union{BigInt,Int128,Int16,Int32,Int64,Int8}) = false
has_value_bracket(::Union{BigFloat,Float16,Float32,Float64}) =  false
has_value_bracket(x::Number) = any(!isdigit, string(x)) # slow

has_unit_bracket(x::Quantity) = has_unit_bracket(unit(x)) 
has_unit_bracket(u::Unitlike) = length(typeof(u).parameters[1]) > 1 && !is_u_str_expression()

is_u_str_expression() = begin
	v = get(ENV, "UNITFUL_PARSABLE_STRING_U_STR", "false")
	(tryparse(Bool, v) == true) ? true : false
end


unittuple(u) = typeof(u).parameters[1]
sortedunits(u) = begin
	us = collect(unittuple(u))
	sort!(us, by = u->power(u)>0 ? 1 : -1, rev=true)
end


const default_context = Module[Unitful]#register
"""
	addcontext!(mod::Module...)

Input modules `mod...` are added to the default unit context where the strings converted from `Units` or `Quantity` are chacked parsability.

see also: `rmcontext!`
"""
function addcontext!(mod::Module...)
	push!(default_context, mod...)
end
"""
	rmcontext!(mod::Module...)

Input modules `mod...` are removed to the default unit context where the strings converted from `Units` or `Quantity` are chacked parsability.

see also: `addcontext!`
"""
function rmcontext!(mod::Module...)
	filter!(m -> m ∉ mod, default_context)
end


@memoize definedunits(mod::Module) = begin #いらない
	filter( reverse!(names(mod, all=true)) ) do sym
		return isdefined(mod, sym) && ustrcheck_bool( getfield(mod, sym) )
	end
end
@memoize find_unitsymbol(unit , mod::Module) = begin#いらない
	for sym in definedunits(mod) #総当たりで試していくダサいが現状これしか思いつかない．
		typeof.(unittuple(getfield(mod, sym))) === (typeof(unit), ) && return sym
	end
	return nothing
end
function symbol(unit::Unit, unit_context::Module...)#いらない
	abb = abbr(unit)
	sym_abb = Symbol(abb)
	for mod in unit_context
		isdefined(mod, sym_abb) && ustrcheck_bool(getfield(mod, sym_abb)) && return sym_abb
		sym = find_unitsymbol(unit, mod)	
		isnothing(sym) || return sym
	end
	@warn """
	A symbol to be parsed into "$(abb)" could not be found in the given "$([unit_context...])" 
	If you need, please try `string(str; unit_context=[Unitful, AddtionalUnitModule...])`
	or `UnitfulParsableString.addcontext!(AddtionalUnitModule...); string(str)`.
	"""
	sym_abb
end

@memoize find_unitsymbol(unit::Units{U, D, A}, mod::Module) where {U, D, A<:Affine} = begin#いらない
	for sym in definedunits(mod) #総当たりで試していくダサいが現状これしか思いつかない．
		unittuple(getfield(mod, sym)) == unit && return sym
	end
	return nothing
end
function symbol(unit::Units{U, D, A}, unit_context::Module...) where {U, D, A<:Affine}#いらない
	abb = sprint(show, unit)
	sym_abb = Symbol(abb)
	for mod in unit_context
		isdefined(mod, sym_abb) && ustrcheck_bool(getfield(mod, sym_abb)) && return sym_abb
		sym = find_unitsymbol(unit, mod)	
		isnothing(sym) || return sym
	end
	@warn """
	A symbol to be parsed into "$(abb)" could not be found in the given "$([unit_context...])" 
	If you need, please try `string(str; unit_context=[Unitful, AddtionalUnitModule...])`
	or `UnitfulParsableString.addcontext!(AddtionalUnitModule...); string(str)`.
	"""
	sym_abb
end

"""
	Unitful.string(unit::Unitlike [, unit_context=[Unitful]])

This function provied by `UnitfulParsableString` converts the value of `Unitful.Unitlike` subtypes to `string` that julia can parse.

Multi-units are expressed as basicaly separeted by "*".

When all exponential of the units is positive, all separates are "\\*". (ex. `"m*s"`)\n
When all exponential of the units is negative, all separates are "\\*" and the negative exponential is expressed as "^-|x|". (ex. `"m^-1*s^-1"`)\n
When both positive and negative exponentials coexist, if there are rational exponentials, all separates are "\\*" and the negative exponential is expressed as "^-|x|". (ex. `"m^(1/2)*s^-2"`)\n
When both positive and negative exponentials coexist, if not there are rational exponentials, the separates of the units with negative exponential are "/" and the negative exponential is expressed as "^|x|".  (ex. `"m/s^2"`)

When the exponentials are rational, if the velue n//m is strictly same as n/m, it is expressed as "^(n/m)".
If not the velue n//m is strictly same as n/m, it is expressed as "^(n//m)".

The generated strings are checked to see if they can be parsed in `unit_context` (the `Unitful` module by default), and a warning is issued if an unparsable string is generated.
If warn and you know where the units defined, please specify `unit_context=[Unitful, UnitDefinedModule...])`.
Or use unexported `addcontext!` function to add the module to the default unit context, so that `unit_context` is no longer required.

see also: `addcontext!`, `rmcontext!` 

## Examples:

```jldoctest
julia> u"m*m", string(u"m*m")
(m², "m^2")

julia> u"m*s^2", string(u"m*s^2")
(m s², "m*s^2")
```

## Examples: Expression of negative exponential

```jldoctest
julia> string(u"(m*s)^-1") # all exponents are negative
"m^-1*s^-1"                # -> separater is "*"

julia> string(u"m^(1/2)*s^-2") # positive and negative exponent coexist
"m^(1/2)*s^-2"                 # if rational exponent exist -> separater is "*"

julia> string(u"m*s^-2") # positive and negative exponent coexist
"m/s^2"                  # if rational exponent never exist -> "/" can be use for separater
```

## Examples: Expression of rational exponential

```jldoctest
julia> string(u"m^(1//2)" # 1//2 == 1/2 
"m^(1/2)"

julia> string(u"m^(1//3)" # 1//3 != 1/3
"m^(1//3)"
```
"""
function Unitful.string(u::Unitlike, mod...)
	unit_list = sortedunits(u)
	is_div_note = any(power(u)>0 for u in unit_list) && all(power(u).den==1 for u in unit_list)
	str = ""
	for (i, y) in enumerate(unit_list);
		sep = "*"
		p = power(y) 
		if is_div_note && p.num<0
			sep = "/"
			p = abs(p)
		end
		pow = p == 1//1        ? ""  :
		      p.den == 1       ? string("^", p.num) : 
		      p == p.num/p.den ? string("^", "(", p.num, "/" , p.den, ")") :
		                         string("^", "(", p.num, "//", p.den, ")")
		sym = symbol(y, mod...)
		str = string(str, (i==1 ? "" : sep), prefix(y), sym, pow)
	end
	is_u_str_expression() ? string("u\"", str, "\"") : str
end
Unitful.string(u::Unitlike, mod::Union{AbstractVector, Tuple}) = Unitful.string(u, mod...)
Unitful.string(u::Unitlike; unit_context=default_context) = Unitful.string(u, unit_context)

function Unitful.string(u::Units{U, D, A}, mod...) where {U, D, A<:Affine}
	str = string(symbol(u, default_context...))
	is_u_str_expression() ? string("u\"", str, "\"") : str
end
Unitful.string(u::Units{U, D, A}, mod::Union{AbstractVector, Tuple}) where {U, D, A<:Affine} = Unitful.string(u, mod...)
Unitful.string(u::Units{U, D, A}; unit_context=default_context) where {U, D, A<:Affine} = Unitful.string(u, unit_context)

"""
	Unitful.string(x::Quantity [, unit_context=[Unitful]])

This function provied by `UnitfulParsableString` converts the value of `Unitful.Quantity` subtypes to `string` that julia can parse.

The `Unitful.Quantity` which have value and units is converted as 
```
"[ ( ,] string(value), [ ) ,] [ * ,] [ ( ,] string(unit) [, ) ]"
```
The presence or absence of each bracket is determined by the return values of the `has_value_bracket(x)` and `has_unit_bracket(x)` functions.

if `has_value_bracket(x) && has_unit_bracket(x) == true`, the operator "\\*" is inserted.

Note: see `Unitful.string(x::Unitlike)` about the string expression of unit 

The generated strings are checked to see if they can be parsed in `unit_context` (the `Unitful` module by default), and a warning is issued if an unparsable string is generated.
If warn and you know where the units defined, please specify `unit_context=[Unitful, UnitDefinedModule...])`.
Or use unexported `addcontext!` function to add the module to the default unit context, so that `unit_context` is no longer required.
	
see also: `addcontext!`, `rmcontext!` 

## Examples:

```jldoctest
julia> string(u"1.0s^2")	# u"1.0s^2" -> 1.0 s²
"1.0s^2"

julia> string(u"1.0m*kg")	# u"1.0m*kg" -> 1.0 kg m
"1.0(kg*m)"

julia> string((1//2)u"m")	# (1//2)u"m" -> 1//2 m
"(1//2)m"

julia> string((1+2im)u"m/s")	# (1+2im)u"m/s" -> (1 + 2im) m s⁻¹
"(1 + 2im)*(m/s)"
```
"""
function Unitful.string(x::Quantity; karg...)
	v = string(x.val)
	u = string(unit(x); karg...)
	val = has_value_bracket(x) ? string("(", v, ")") : v
	uni = has_unit_bracket(x)  ? string("(", u, ")") : u
	sep = has_value_bracket(x) && has_unit_bracket(x) ? "*" : ""
	string(val, sep, uni)
end

"""
	Unitful.string(r::StepRange{T}) where T<:Quantity

あとで	
"""
function Unitful.string(r::StepRange{T}; karg...) where T<:Quantity
	a,s,b = first(r), step(r), last(r)
	U,u = unit(a), string(unit(a); karg...)
	rng = ustrip(U, s)==1 ? repr(ustrip(U, a):ustrip(U, b)) : 
	                        repr(ustrip(U, a):ustrip(U, s):ustrip(U, b))
	uni = has_unit_bracket(U) ? string("*", "(", u, ")") : u
	string("(", rng, ")", uni)
end

"""
	Unitful.string(r::StepRangeLen{T}) where T<:Quantity

あとで	
"""
function Unitful.string(r::StepRangeLen{T}; karg...) where T<:Quantity
	a,s,b = first(r), step(r), last(r)
	U,u = unit(a), string(unit(a); karg...)
	rng = repr(ustrip(U, a):ustrip(U, s):ustrip(U, b))
	uni = has_unit_bracket(U) ? string("*", "(", u, ")") : u
	string("(", rng, ")", uni)
end

"""
	Unitful.string(x::typeof(NoUnits))
"""
function Unitful.string(x::typeof(NoUnits); karg...)
	"NoUnits"
end

end

#=
All Types defined at Unitful
 :Affine
 :BracketStyle
 :Dimension
 :IsRootPowerRatio
 :LogInfo
 :LogScaled
 :MixedUnits
 :Unit
 :Unitlike
=#

#  Log系勉強して出直してきます．
# function symbol(unit::LogScaled? MixedUnits?, unit_context::Module...)
# 	abb = abbr(unit) 
# 	sym_abb = Symbol(abb)
# 	for mod in unit_context
# 		isdefined(mod, sym_abb) && ustrcheck_bool(getfield(mod, sym_abb)) && return sym_abb
# 		sym = find_unitsymbol(unit, mod)	
# 		isnothing(sym) || return sym
# 	end
# 	@warn """A symbol to be parsed into "$(abb)" could not be found in the given "$([unit_context...])" """ _file=nothing
# 	sym_abb
# end
# Unitful.string(u::MixedUnits, mod::Union{AbstractVector, Tuple}) = Unitful.string(u; karg...)
# Unitful.string(u::MixedUnits; unit_context=default_context) = Unitful.string(u, unit_context)

# """
# # 	`Unitful.string(x::Gain)`

# # あとで	
# # """
# function Unitful.string(x::Gain; karg...)
# 	v = x.val |> string
# 	u = symbol(x; karg...)
# 	val = has_value_bracket(x.val) ? string("(", v, ")") : v
# 	uni = is_u_str_expression() ? string("u\"", u ,"\"") : u
# 	sep = has_value_bracket(x.val) && is_u_str_expression() ? "*" : ""
# 	string(val, sep, uni)
# end

# """
# 	Unitful.string(x::Level)

# あとで	
# """
# function Unitful.string(x::Level; karg...)
# 	v = ustrip(x) |> string
# 	u = symbol(x; karg...)
# 	val = has_value_bracket(ustrip(x)) ? string("(", v, ")") : v
# 	uni = is_u_str_expression() ? string("u\"", u ,"\"") : u
# 	sep = has_value_bracket(ustrip(x)) && is_u_str_expression() ? "*" : ""
# 	string(val, sep, uni)
# end

# function Unitful.string(x::MixedUnits; karg...)
# 	@show u = symbol(x; karg...)
# end
