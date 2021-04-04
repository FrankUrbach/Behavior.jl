abstract type Engine end
abstract type OSAbstraction end

findfileswithextension(::OSAbstraction, ::String, ::String) = error("override this method")
readfile(::OSAbstraction, ::String) = error("override this method")
fileexists(::OSAbstraction, ::String) = error("override this method")

struct ExecutorEngine <: Engine
    accumulator::ResultAccumulator
    executor::Executor
    matcher::StepDefinitionMatcher
    selector::Selection.TagSelector

    function ExecutorEngine(realtimepresenter::RealTimePresenter;
                            executionenv=NoExecutionEnvironment(),
                            selector::Selection.TagSelector = Selection.AllScenarios)
        matcher = CompositeStepDefinitionMatcher()
        executor = Executor(matcher, realtimepresenter; executionenv=executionenv)
        new(ResultAccumulator(), executor, matcher, selector)
    end
end

addmatcher!(engine::ExecutorEngine, matcher::StepDefinitionMatcher) = addmatcher!(engine.matcher, matcher)

"""
    runfeature!(::ExecutorEngine, ::Feature)

Run the scenarios in a feature and record the result.
"""
function runfeature!(engine::ExecutorEngine, feature::Feature)
    result = executefeature(engine.executor, feature)
    accumulateresult!(engine.accumulator, result)
end

"""
    runfeature!(::ExecutorEngine, ::Gherkin.OKParseResult{Feature})

Wrapper method for the above runfeature!.
"""
function runfeature!(engine::ExecutorEngine, parseresult::Gherkin.OKParseResult{Feature}, _featurefile::String)
    # Filter all features to run only the scenarios chosen by the tag selector, if any.
    # Any features or scenarios that do not match the tag selector will be removed here.
    filteredfeature = Selection.select(engine.selector, parseresult.value)

    # If there are no scenarios in this feature, then do not run it at all.
    # This matters because we don't want it listed in the results view having 0 successes
    # and 0 failures.
    if !isempty(filteredfeature.scenarios)
        runfeature!(engine, filteredfeature)
    end
end

"""
    runfeature!(::ExecutorEngine, ::Gherkin.BadParseResult{Feature})

A feature could not be parsed. Record the result.
"""
function runfeature!(engine::ExecutorEngine, parsefailure::Gherkin.BadParseResult{Feature}, featurefile::String)
    accumulateresult!(engine.accumulator, parsefailure, featurefile)
end

finish(engine::ExecutorEngine) = engine.accumulator


struct Driver
    os::OSAbstraction
    engine::Engine

    Driver(os::OSAbstraction, engine::Engine) = new(os, engine)
end

function readstepdefinitions!(driver::Driver, path::String)
    stepdefinitionfiles = findfileswithextension(driver.os, path, ".jl")
    for f in stepdefinitionfiles
        addmatcher!(driver.engine, FromMacroStepDefinitionMatcher(readfile(driver.os, f)))
    end
end

function runfeatures!(driver::Driver, path::String; parseoptions::ParseOptions = ParseOptions())
    featurefiles = findfileswithextension(driver.os, path, ".feature")
    for featurefile in featurefiles
        featureparseresult = parsefeature(readfile(driver.os, featurefile), options=parseoptions)
        runfeature!(driver.engine, featureparseresult, featurefile)
    end
    finish(driver.engine)
end