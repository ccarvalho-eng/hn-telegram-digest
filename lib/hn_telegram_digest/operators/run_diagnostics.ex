defmodule HnTelegramDigest.Operators.RunDiagnostics do
  @moduledoc """
  Formats Squid Mesh run diagnostics for operator-facing tasks.
  """

  @secret_fragments ~w(authorization password secret token api_key access_key)
  @explain_unavailable_message "SquidMesh.explain_run/2 is not available in the current Hex release. See https://github.com/ccarvalho-eng/squid_mesh/issues/148"

  @type diagnostic_result :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Returns a formatted run snapshot from `SquidMesh.inspect_run/2`.
  """
  @spec inspect_run(Ecto.UUID.t(), keyword()) :: diagnostic_result()
  def inspect_run(run_id, opts \\ []) do
    with {:ok, run_id} <- validate_run_id(run_id) do
      opts = Keyword.put_new(opts, :include_history, true)

      case SquidMesh.inspect_run(run_id, opts) do
        {:ok, run} -> {:ok, format_run(run)}
        {:error, reason} -> {:error, format_error(run_id, reason)}
      end
    end
  end

  @doc """
  Returns a formatted runtime explanation from `SquidMesh.explain_run/2`.
  """
  @spec explain_run(Ecto.UUID.t(), keyword()) :: diagnostic_result()
  def explain_run(run_id, opts \\ []) do
    with {:ok, run_id} <- validate_run_id(run_id) do
      if function_exported?(SquidMesh, :explain_run, 2) do
        case apply(SquidMesh, :explain_run, [run_id, opts]) do
          {:ok, explanation} -> {:ok, format_explanation(run_id, explanation)}
          {:error, reason} -> {:error, format_error(run_id, reason)}
        end
      else
        {:error, @explain_unavailable_message}
      end
    end
  end

  @doc """
  Formats a Squid Mesh run without leaking secret-like values.
  """
  @spec format_run(SquidMesh.Run.t()) :: String.t()
  def format_run(%SquidMesh.Run{} = run) do
    [
      "Run #{run.id}",
      "workflow: #{inspect(run.workflow)}",
      "trigger: #{format_value(run.trigger)}",
      "status: #{format_value(run.status)}",
      "current_step: #{format_value(run.current_step)}",
      "inserted_at: #{format_value(run.inserted_at)}",
      "updated_at: #{format_value(run.updated_at)}",
      "payload: #{encode(run.payload)}",
      "context: #{encode(run.context)}",
      "last_error: #{encode(run.last_error)}",
      "audit_events: #{encode(run.audit_events || [])}",
      "steps: #{encode(run.steps || [])}",
      "step_runs: #{encode(run.step_runs || [])}"
    ]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Formats a Squid Mesh run explanation without leaking secret-like values.
  """
  @spec format_explanation(Ecto.UUID.t(), map() | struct()) :: String.t()
  def format_explanation(run_id, explanation) do
    [
      "Run explanation #{run_id}",
      "status: #{format_value(explanation_field(explanation, :status))}",
      "reason: #{format_value(explanation_field(explanation, :reason))}",
      "step: #{format_value(explanation_field(explanation, :step))}",
      "next_actions: #{format_list(explanation_field(explanation, :next_actions) || [])}",
      "details: #{encode(explanation_field(explanation, :details) || %{})}",
      "evidence: #{encode(explanation_field(explanation, :evidence) || %{})}"
    ]
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Formats a Squid Mesh diagnostic error without leaking secret-like values.
  """
  @spec format_error(term()) :: String.t()
  def format_error(reason), do: "Run diagnostics failed: #{encode(reason)}"

  defp validate_run_id(run_id) do
    case Ecto.UUID.cast(run_id) do
      {:ok, run_id} -> {:ok, run_id}
      :error -> {:error, "Invalid run id: #{run_id}"}
    end
  end

  defp format_error(run_id, :not_found), do: "Run not found: #{run_id}"
  defp format_error(_run_id, reason), do: format_error(reason)

  defp explanation_field(%_struct{} = explanation, field) when is_atom(field) do
    explanation
    |> Map.from_struct()
    |> Map.get(field)
  end

  defp explanation_field(explanation, field) when is_map(explanation) and is_atom(field) do
    Map.get(explanation, field)
  end

  defp format_list([]), do: "none"

  defp format_list(values) when is_list(values) do
    values
    |> Enum.map(&format_value/1)
    |> Enum.join(", ")
  end

  defp format_value(nil), do: "none"
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp format_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp format_value(value), do: to_string(value)

  defp encode(value) do
    value
    |> sanitize()
    |> Jason.encode!()
  end

  defp sanitize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp sanitize(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)

  defp sanitize(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: value

  defp sanitize(value) when is_atom(value), do: Atom.to_string(value)
  defp sanitize(values) when is_list(values), do: Enum.map(values, &sanitize/1)

  defp sanitize(%_struct{} = value) do
    value
    |> Map.from_struct()
    |> sanitize()
  end

  defp sanitize(value) when is_map(value) do
    value
    |> Enum.map(fn {key, field_value} ->
      key = to_string(key)

      if secret_key?(key) do
        {key, "[REDACTED]"}
      else
        {key, sanitize(field_value)}
      end
    end)
    |> Map.new()
  end

  defp secret_key?(key) do
    normalized_key = String.downcase(key)
    Enum.any?(@secret_fragments, &String.contains?(normalized_key, &1))
  end
end
