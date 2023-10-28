defmodule FluffyTrain.RuntimeEvaluator do
  require Logger
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

  def remove_module_if_present(code_evaluation) do
    # Need to remove the module, otherwise a warning is generated because next run will overwrite the current module
    case code_evaluation do
      {{:module, module_name, _binary, _tuple}, _list} ->
        remove_module(module_name)

      _ ->
        Logger.info("No module defined in the code.")
    end
  end

  def remove_module(module_name) do
    try do
      :code.purge(module_name)
      :code.delete(module_name)
    rescue
      _ -> :ok
    end
  end

  def evaluate_and_construct_message(code, example, output) do
    intro_message = """
    I have evaluated your code by executing it in runtime environment via Code.eval_string. \n
    """

    {code_evaluation_message, code_evaluation} = evaluate_code(code)
    example_evaluation_message = evaluate_example(example, output)
    remove_module_if_present(code_evaluation)
    intro_message <> code_evaluation_message <> example_evaluation_message
  end

  defp evaluate_code(code) do
    %{error: code_errors, warnings: code_warnings, evaluation: code_evaluation} =
      evaluate(code)

    code_evaluation_message =
      if code_errors != "" or code_warnings != "" do
        "Code compilation errors: \n" <>
          code_errors <>
          "\n" <>
          "Code compilation warnings: \n" <> code_warnings <> "\n"
      else
        "Code evaluation completed without errors and warnings!\n"
      end

    {code_evaluation_message, code_evaluation}
  end

  defp evaluate_example(example, output) do
    %{error: example_errors, warnings: example_warnings, evaluation: example_evaluation} =
      evaluate(example)

    example_evaluation_message =
      if example_errors != "" or example_warnings != "" do
        "Example compilation errors: \n" <>
          example_errors <>
          "\n" <>
          "Example compilation warnings: \n" <> example_warnings <> "\n"
      else
        "Example evaluation completed without errors and warnings! Excellent!\n"
      end

    example_evaluation_message =
      example_evaluation_message <>
        "Execution output of example code is, as provided by Code.eval_string: \n" <>
        "#{inspect(example_evaluation)}" <>
        "\n" <>
        "vs the expected result: " <> output <> "\n"

    example_evaluation_message
  end
end
