# Copyright 2018 Erik Edin
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Selecting which features and scenarios to run, based on tags.

# Exports

    TagSelector
    select(::TagSelector, tags::AbstractVector{String}) :: Bool
    parsetagselector(::String) :: TagSelector
"""
module Selection

using Behavior.Gherkin

export select, parsetagselector, TagSelector

"""
Abstract type for a tag expression.
Each tag expression can be matched against a set of tags.
"""
abstract type TagExpression end

"""
    matches(ex::TagExpression, tags::AbstractVector{String}) :: Bool

Returns true if `tags` matches the tag expression `ex`, false otherwise.
This must be implemented for each `TagExpression` subtype.
"""
matches(::TagExpression, tags::AbstractVector{String}) :: Bool = error("Implement this in TagExpression types")

"""
Tag is an expression that matches against a single tag.

It will match if the tag in the `value` is in the `tags` set.
"""
struct Tag <: TagExpression
    value::String
end
matches(ex::Tag, tags::AbstractVector{String}) = ex.value in tags

"""
Not matches a tag set if and only if the `inner` tag expression _does not_ match.
"""
struct Not <: TagExpression
    inner::TagExpression
end
matches(ex::Not, tags::AbstractVector{String}) = !matches(ex.inner, tags)

"""
All is a tag expression that matches any tags or no tags.
"""
struct All <: TagExpression end
matches(::All, ::AbstractVector{String}) = true

"""
Any matches any tags in a list.
"""
struct Any <: TagExpression
    exs::Vector{TagExpression}
end
matches(anyex::Any, tags::AbstractVector{String}) = any(ex -> matches(ex, tags), anyex.exs)

"""
    parsetagexpression(s::String) :: TagExpression

Parse the string `s` into a `TagExpression`.
"""
function parsetagexpression(s::String) :: TagExpression
    if isempty(strip(s))
        All()
    elseif startswith(s, "not ")
        tag = replace(s, "not " => "")
        Not(parsetagexpression(tag))
    else
        tags = split(s, ",")
        Any([Tag(t) for t in tags])
    end
end

"""
TagSelector is used to select a feature or scenario based on its tags.

The `TagSelector` is created by parsing a tag expression in string form. Then the
`select` method can be used to query if a given feature or scenario should be selected for execution.
"""
struct TagSelector
    expression::TagExpression
end

"""
    selectscenario(::TagSelector, feature::Feature, scenario::Scenario) :: Boolean

Check if a given scenario ought to be included in the execution. Returns true if that is the case,
false otherwise.
"""
function select(ts::TagSelector, feature::Feature, scenario::Gherkin.AbstractScenario) :: Bool
    tags = vcat(feature.header.tags, scenario.tags)
    matches(ts.expression, tags)
end

"""
    select(::TagSelector, feature::Feature) :: Union{Feature,Nothing}

Filter a feature and its scenarios based on the selected tags.
Returns a feature with zero or more scenarios, or nothing if the feature
and none of the scenarios matched the tag selector.
"""
function select(ts::TagSelector, feature::Feature) :: Feature
    newscenarios = [scenario
                    for scenario in feature.scenarios
                    if select(ts, feature, scenario)]
    Feature(feature, newscenarios)
end

"""
    parsetagselector(s::String) :: TagSelector

Parse a string into a `TagSelector` struct. This can then be used with the `select` query to determine
if a given feature or scenario should be selected for execution.

# Examples
```julia-repl
julia> # Will match any feature/scenario with the tag @foo
julia> parsetagselector("@foo")

julia> # Will match any feature/scenario without the tag @bar
julia> parsetagselector("not @bar")
```
"""
function parsetagselector(s::String) :: TagSelector
    TagSelector(parsetagexpression(s))
end

const AllScenarios = TagSelector(All())

##
## Parser combinators for tag expressions
##
## This will soonish replace most of the code above.
##

struct TagExpressionInput
    source::String
    position::Int

    TagExpressionInput(source::String, position::Int = 1) = new(source, position)
end

currentchar(input::TagExpressionInput) = (input.source[input.position], TagExpressionInput(input.source, input.position + 1))
iseof(input::TagExpressionInput) = input.position > length(input.source)

abstract type ParseResult{T} end

struct OKParseResult{T} <: ParseResult{T}
    value::T
    newinput::TagExpressionInput
end

struct BadParseResult{T} <: ParseResult{T}
    newinput::TagExpressionInput
end

abstract type TagExpressionParser{T} end

"""
    NotIn(::String)

Take a single character if it is not one of the specified forbidden values.
"""
struct NotIn <: TagExpressionParser{Char}
    notchars::String
end

function (parser::NotIn)(input::TagExpressionInput) :: ParseResult{Char}
    if iseof(input)
        return BadParseResult{Char}(input)
    end

    c, newinput = currentchar(input)
    if contains(parser.notchars, c)
        BadParseResult{Char}(input)
    else
        OKParseResult{Char}(c, newinput)
    end
end

"""
    Repeating(::TagExpressionParser)

Repeat a given parser while it succeeds.
"""
struct Repeating{T} <: TagExpressionParser{Vector{T}}
    inner::TagExpressionParser{T}
end

function (parser::Repeating{T})(input::TagExpressionInput) :: ParseResult{Vector{T}} where {T}
    result = Vector{T}()
    currentinput = input

    while true
        innerresult = parser.inner(currentinput)
        if innerresult isa BadParseResult{T}
            break
        end
        push!(result, innerresult.value)
        currentinput = innerresult.newinput
    end

    OKParseResult{Vector{T}}(result, currentinput)
end

"""
    Transforming(::TagExpressionParser, f::Function)

Transforms an OK parse result using a provided function
"""
struct Transforming{S, T} <: TagExpressionParser{T}
    inner::TagExpressionParser{S}
    f::Function
end

function (parser::Transforming{S, T})(input::TagExpressionInput) :: ParseResult{T}  where {S, T}
    result = parser.inner(input)
    if result isa OKParseResult{S}
        OKParseResult{T}(parser.f(result.value), result.newinput)
    else
        BadParseResult{T}(newinput)
    end
end

SingleTagParser() = Transforming{Vector{Char}, String}(Repeating{Char}(NotIn("() ")), xs -> join(xs))

end