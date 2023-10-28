defmodule FluffyTrain.RuntimeEvaluator do
  alias ExUnit.CaptureIO

  def evaluate(code) do
    # Initialize the agent with an empty map
    {:ok, agent} = Agent.start_link(fn -> %{} end)

    # Capture warnings during code evaluation
    warnings =
      CaptureIO.capture_io(:stderr, fn ->
        try do
          {result, output} = Code.eval_string(code)
          # Store the result in the agent
          Agent.update(agent, fn _ -> %{evaluation: {result, output}, error: ""} end)
        catch
          kind, reason ->
            error = Exception.format(kind, reason, __STACKTRACE__)
            # Store the exception in the agent
            Agent.update(agent, fn _ -> %{evaluation: %{}, error: error} end)
        end
      end)

    # Fetch the stored values
    return_value = Agent.get(agent, fn state -> state end)

    # Construct the final map
    %{
      warnings: warnings,
      evaluation: Map.get(return_value, :evaluation, {}),
      error: Map.get(return_value, :error, "")
    }
  end

  def remove_module(module_name) do
    try do
      :code.purge(module_name)
      :code.delete(module_name)
    rescue
      _ -> :ok
    end
  end
end
