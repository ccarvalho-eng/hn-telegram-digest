defmodule HnTelegramDigest.Operators.RunDiagnosticsTest do
  use HnTelegramDigest.DataCase, async: false

  import ExUnit.CaptureIO

  alias HnTelegramDigest.Operators.RunDiagnostics
  alias HnTelegramDigest.Workflows.DeliverHnDigest

  @window_start_at "2026-05-10T13:00:00Z"

  setup do
    on_exit(fn ->
      Mix.Task.reenable("hn_telegram_digest.inspect_run")
      Mix.Task.reenable("hn_telegram_digest.explain_run")
    end)
  end

  test "inspect_run returns formatted run state for an existing run" do
    assert {:ok, run} =
             SquidMesh.start_run(
               DeliverHnDigest,
               :digest_requested,
               %{chat_id: 12_345, window_start_at: @window_start_at},
               repo: Repo
             )

    assert {:ok, output} = RunDiagnostics.inspect_run(run.id)

    assert output =~ "Run #{run.id}"
    assert output =~ "workflow: HnTelegramDigest.Workflows.DeliverHnDigest"
    assert output =~ "trigger: digest_requested"
    assert output =~ "status: pending"
    assert output =~ ~s("chat_id":12345)
    assert output =~ ~s("window_start_at":"#{@window_start_at}")
    assert output =~ "audit_events:"
  end

  test "diagnostics validate run ids at the operator boundary" do
    assert {:error, "Invalid run id: not-a-uuid"} = RunDiagnostics.inspect_run("not-a-uuid")
    assert {:error, "Invalid run id: not-a-uuid"} = RunDiagnostics.explain_run("not-a-uuid")
  end

  test "explain_run reports the currently unpublished Squid Mesh API" do
    run_id = Ecto.UUID.generate()

    assert {:error,
            "SquidMesh.explain_run/2 is not available in the current Hex release. See https://github.com/ccarvalho-eng/squid_mesh/issues/148"} =
             RunDiagnostics.explain_run(run_id)
  end

  test "diagnostics return clear errors for missing runs" do
    missing_id = Ecto.UUID.generate()
    expected_error = "Run not found: #{missing_id}"

    assert {:error, ^expected_error} = RunDiagnostics.inspect_run(missing_id)
  end

  test "formatted output redacts secret-like values" do
    output =
      RunDiagnostics.format_run(%SquidMesh.Run{
        id: Ecto.UUID.generate(),
        workflow: DeliverHnDigest,
        trigger: :digest_requested,
        status: :pending,
        payload: %{
          "bot_token" => "123:abc",
          "nested" => %{"authorization" => "Bearer secret"}
        },
        context: %{"password" => "secret"},
        current_step: :fetch_feed,
        last_error: nil,
        audit_events: [],
        steps: [],
        step_runs: []
      })

    refute output =~ "123:abc"
    refute output =~ "Bearer secret"
    assert output =~ ~s("bot_token":"[REDACTED]")
    assert output =~ ~s("authorization":"[REDACTED]")
    assert output =~ ~s("password":"[REDACTED]")
  end

  test "explanation formatting tolerates missing fields from future releases" do
    run_id = Ecto.UUID.generate()

    output =
      RunDiagnostics.format_explanation(run_id, %{
        status: :running,
        details: %{"bot_token" => "123:abc"}
      })

    assert output =~ "Run explanation #{run_id}"
    assert output =~ "status: running"
    assert output =~ "reason: none"
    assert output =~ "step: none"
    assert output =~ "next_actions: none"
    assert output =~ ~s("bot_token":"[REDACTED]")
    refute output =~ "123:abc"
  end

  test "generic diagnostic errors are redacted" do
    output =
      RunDiagnostics.format_error(%{
        message: "failed",
        bot_token: "123:abc",
        nested: %{authorization: "Bearer secret"}
      })

    assert output =~ ~s("bot_token":"[REDACTED]")
    assert output =~ ~s("authorization":"[REDACTED]")
    refute output =~ "123:abc"
    refute output =~ "Bearer secret"
  end

  test "inspect task prints formatted output" do
    assert {:ok, run} =
             SquidMesh.start_run(
               DeliverHnDigest,
               :digest_requested,
               %{chat_id: 12_345, window_start_at: @window_start_at},
               repo: Repo
             )

    output =
      capture_io(fn ->
        Mix.Tasks.HnTelegramDigest.InspectRun.run([run.id])
      end)

    assert output =~ "Run #{run.id}"
    assert output =~ "status: pending"
  end

  test "explain task exits with a clear unpublished API error" do
    run_id = Ecto.UUID.generate()

    assert_raise Mix.Error,
                 "SquidMesh.explain_run/2 is not available in the current Hex release. See https://github.com/ccarvalho-eng/squid_mesh/issues/148",
                 fn ->
                   Mix.Tasks.HnTelegramDigest.ExplainRun.run([run_id])
                 end
  end
end
