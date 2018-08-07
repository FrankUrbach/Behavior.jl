using ExecutableSpecifications:
    Engine, ExecutorEngine, QuietRealTimePresenter, FromMacroStepDefinitionMatcher,
    runfeature!, finish, issuccess, findstepdefinition, NoMatchingStepDefinition,
    Driver, readstepdefinitions!, OSAbstraction
using ExecutableSpecifications.Gherkin: Feature, FeatureHeader, Scenario, Given
import ExecutableSpecifications: addmatcher!, findfileswithextension, readfile

@testset "Engine               " begin
    # Beware: This test actually exercises far too much of the code. It should be isolated to
    # `Engine`` only.
    @testset "Run a successful feature; Result is successful" begin
        # Arrange
        engine = ExecutorEngine(QuietRealTimePresenter())
        matcher = FromMacroStepDefinitionMatcher("""
            using ExecutableSpecifications

            @given "successful step" begin end
        """)
        addmatcher!(engine, matcher)

        successfulscenario = Scenario("", [], [Given("successful step")])
        feature = Feature(FeatureHeader("", [], []), [successfulscenario])

        # Act
        runfeature!(engine, feature)

        # Assert
        result = finish(engine)
        @test issuccess(result)
    end

    @testset "Run a failing feature; Result is not successful" begin
        # Arrange
        engine = ExecutorEngine(QuietRealTimePresenter())
        matcher = FromMacroStepDefinitionMatcher("""
            using ExecutableSpecifications

            @given "failing step" begin
                @expect 1 == 2
            end
        """)
        addmatcher!(engine, matcher)

        failingscenario = Scenario("", [], [Given("failing step")])
        feature = Feature(FeatureHeader("", [], []), [failingscenario])

        # Act
        runfeature!(engine, feature)

        # Assert
        result = finish(engine)
        @test !issuccess(result)
    end

    @testset "Run a failing and a successful feature; Result is not successful" begin
        # Arrange
        engine = ExecutorEngine(QuietRealTimePresenter())
        matcher = FromMacroStepDefinitionMatcher("""
            using ExecutableSpecifications

            @given "failing step" begin
                @expect 1 == 2
            end

            @given "successful step" begin end
        """)
        addmatcher!(engine, matcher)

        failingscenario = Scenario("", [], [Given("failing step")])
        successfulscenario = Scenario("", [], [Given("successful step")])
        feature1 = Feature(FeatureHeader("fails", [], []), [failingscenario])
        feature2 = Feature(FeatureHeader("succeeds", [], []), [successfulscenario])

        # Act
        runfeature!(engine, feature1)
        runfeature!(engine, feature2)

        # Assert
        result = finish(engine)
        @test !issuccess(result)
    end
end

mutable struct FakeEngine <: Engine
    matchers::Vector{StepDefinitionMatcher}

    FakeEngine() = new([])
end
addmatcher!(engine::FakeEngine, m::StepDefinitionMatcher) = push!(engine.matchers, m)

struct FakeOSAbstraction <: OSAbstraction
    fileswithext::Vector{String}
    filecontents::Dict{String, String}

    findfileswithextension_args::Vector{Pair{String, String}}

    FakeOSAbstraction(; fileswithext::Vector{String} = [],
                        filecontents::Dict{String, String} = Dict()) = new(fileswithext, filecontents, [])
end
function findfileswithextension(os::FakeOSAbstraction, path::String, extension::String)
    push!(os.findfileswithextension_args, Pair(path, extension))
    os.fileswithext
end

readfile(os::FakeOSAbstraction, path::String) = os.filecontents[path]

@testset "Driver               " begin
    @testset "Finding step definitions; One definition found; The engine has one matcher" begin
        # Arrange
        engine = FakeEngine()
        osal = FakeOSAbstraction(fileswithext=["somepath/file.jl"],
                                 filecontents = Dict("somepath/file.jl" => ""))
        driver = Driver(osal, engine)

        # Act
        readstepdefinitions!(driver, "somepath")

        # Assert
        @test length(engine.matchers) == 1
    end

    @testset "Finding step definitions; Two definitions found; The engine has two matchers" begin
        # Arrange
        engine = FakeEngine()
        osal = FakeOSAbstraction(fileswithext=["somepath/file.jl", "somepath/file2.jl"],
                                 filecontents = Dict("somepath/file.jl" => "",
                                                     "somepath/file2.jl" => ""))
        driver = Driver(osal, engine)

        # Act
        readstepdefinitions!(driver, "somepath")

        # Assert
        @test length(engine.matchers) == 2
    end

    @testset "Finding step definitions; Driver searches for .jl files" begin
        # Arrange
        engine = FakeEngine()
        osal = FakeOSAbstraction(fileswithext=["somepath/file.jl", "somepath/file2.jl"],
                                 filecontents = Dict("somepath/file.jl" => "",
                                                     "somepath/file2.jl" => ""))
        driver = Driver(osal, engine)

        # Act
        readstepdefinitions!(driver, "somepath")

        # Assert
        @test osal.findfileswithextension_args[1][2] == ".jl"
    end

    @testset "Finding step definitions; Step path is features/steps; Driver searches features/steps" begin
        # Arrange
        engine = FakeEngine()
        osal = FakeOSAbstraction(fileswithext=["somepath/file.jl", "somepath/file2.jl"],
                                 filecontents = Dict("somepath/file.jl" => "",
                                                     "somepath/file2.jl" => ""))
        driver = Driver(osal, engine)

        # Act
        readstepdefinitions!(driver, "features/steps")

        # Assert
        @test osal.findfileswithextension_args[1][1] == "features/steps"
    end

    @testset "Finding step definitions; Step path is features/othersteps; Driver search features/othersteps" begin
        # Arrange
        engine = FakeEngine()
        osal = FakeOSAbstraction(fileswithext=["somepath/file.jl", "somepath/file2.jl"],
                                 filecontents = Dict("somepath/file.jl" => "",
                                                     "somepath/file2.jl" => ""))
        driver = Driver(osal, engine)

        # Act
        readstepdefinitions!(driver, "features/othersteps")

        # Assert
        @test osal.findfileswithextension_args[1][1] == "features/othersteps"
    end

    @testset "Reading step definitions; Step definition has successful scenario step; The matcher can find that step" begin
        # Arrange
        engine = FakeEngine()
        osal = FakeOSAbstraction(fileswithext=["features/steps/file.jl"],
                                 filecontents = Dict("features/steps/file.jl" => """
                                    using ExecutableSpecifications

                                    @given "successful step" begin end
                                 """))
        driver = Driver(osal, engine)

        successfulstep = Given("successful step")

        # Act
        readstepdefinitions!(driver, "features/othersteps")

        # Assert
        # This method throws if no such step definition was found.
        findstepdefinition(engine.matchers[1], successfulstep)
    end


    @testset "Reading step definitions; Step definition has no scenario step; Matcher cannot find that senario step" begin
        # Arrange
        engine = FakeEngine()
        osal = FakeOSAbstraction(fileswithext=["features/steps/file.jl"],
                                 filecontents = Dict("features/steps/file.jl" => """
                                    using ExecutableSpecifications

                                 """))
        driver = Driver(osal, engine)

        successfulstep = Given("successful step")

        # Act
        readstepdefinitions!(driver, "features/othersteps")

        # Assert
        # This method throws if no such step definition was found.
        @test_throws NoMatchingStepDefinition findstepdefinition(engine.matchers[1], successfulstep)
    end
end