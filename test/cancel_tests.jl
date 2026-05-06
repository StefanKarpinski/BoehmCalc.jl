using BoehmCalc
using Test

@testset "cancel" begin
    @test BoehmCalc.check_cancellation() === nothing  # no token set: no-op

    tok = BoehmCalc.CancelToken()
    @test tok.cancelled[] == false

    # Token activated → check_cancellation throws
    @test_throws BoehmCalc.CancelException BoehmCalc._with_token(tok) do
        tok.cancelled[] = true
        BoehmCalc.check_cancellation()
    end

    # with_timeout returns the function's value when fast
    result = BoehmCalc.with_timeout(1.0) do
        42
    end
    @test result == 42

    # with_timeout throws CancelException when slow
    @test_throws BoehmCalc.CancelException BoehmCalc.with_timeout(0.05) do
        # Busy-loop with cancellation checks until the timer fires
        while true
            BoehmCalc.check_cancellation()
            sleep(0.001)
        end
    end

    @testset "cancellation aborts CR computation" begin
        # Build a deeply-nested CR that takes a while to refine, then cancel it.
        deep = BoehmCalc.IntCR(2)
        for _ in 1:30
            deep = BoehmCalc.SqrtCR(BoehmCalc.AddCR(deep, BoehmCalc.IntCR(1)))
        end
        @test_throws BoehmCalc.CancelException BoehmCalc.with_timeout(0.001) do
            # Demand high precision; should be canceled before completion
            BoehmCalc.get_approx(deep, -10_000_000)
        end
    end
end
