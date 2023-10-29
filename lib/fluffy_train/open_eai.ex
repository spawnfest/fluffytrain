defmodule FluffyTrain.OpenEAI do
  use GenServer
  require Logger
  alias FluffyTrain.RuntimeEvaluator
  alias FluffyTrain.PromptRepo
  alias FluffyTrain.TextExtractor
  alias OpenaiEx.ChatCompletion

  @topic_user_message "open_eal:error_message"
  @topic_response_stream "open_eal:response_stream"

  def topic_user_message, do: @topic_user_message
  def topic_response_stream, do: @topic_response_stream

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Phoenix.PubSub.local_broadcast(LynceusApplication.PubSub, @topic, {:node_up, node})

  def init(_) do
    state = reset()

    {:ok, state}
  end

  defp reset() do
    apikey = System.fetch_env!("OPENAI_API_KEY")
    openai = OpenaiEx.new(apikey)
    model_type = PromptRepo.model()
    system = PromptRepo.prompt_fixer()

    state = %{
      is_agent_on: false,
      status: "OFF",
      is_wip: false,
      apikey: apikey,
      openai: openai,
      model_type: model_type,
      task_pid: nil,
      system: system,
      messages: [%{role: "system", content: system}],
      processed_messages: %{},
      context: FluffyTrain.ContextRepo.load_context()
    }

    Phoenix.PubSub.unsubscribe(FluffyTrain.PubSub, topic_user_message())

    Phoenix.PubSub.unsubscribe(
      FluffyTrain.PubSub,
      FluffyTrain.OpenEI.topic_successfull_solution()
    )

    IO.inspect(state)

    state
  end

  def reset_state do
    GenServer.cast(__MODULE__, :reset_state)
  end

  def get_raw_messages() do
    GenServer.call(__MODULE__, :get_raw_messages)
  end

  def get_agent_status() do
    GenServer.call(__MODULE__, :get_agent_status)
  end

  def toggle_state() do
    GenServer.call(__MODULE__, :toggle_state)
  end

  def is_agent_on() do
    GenServer.call(__MODULE__, :is_agent_on)
  end

  def cancel_generation do
    GenServer.cast(__MODULE__, :cancel_generation)
  end

  def handle_cast(:reset_state, _state) do
    {:noreply, reset()}
  end

  def handle_cast(:cancel_generation, state) do
    pid = Map.get(state, :task_pid)

    if pid && Process.alive?(pid) do
      Process.exit(pid, :kill)
    else
      Logger.warning("Task is already dead.")
    end

    {:noreply, reset()}
  end

  def handle_call(:get_raw_messages, _from, state) do
    messages = Map.get(state, :messages)
    # remove the system prompt message
    messages = List.delete_at(messages, 0)
    {:reply, messages, state}
  end

  def handle_call(:toggle_state, _from, state) do
    is_agent_on = Map.get(state, :is_agent_on)

    state =
      if is_agent_on do
        Phoenix.PubSub.unsubscribe(FluffyTrain.PubSub, topic_user_message())

        Phoenix.PubSub.unsubscribe(
          FluffyTrain.PubSub,
          FluffyTrain.OpenEI.topic_successfull_solution()
        )

        state
        |> Map.put(:status, "OFF")
        |> Map.put(:is_agent_on, false)
      else
        Phoenix.PubSub.subscribe(FluffyTrain.PubSub, topic_user_message())

        Phoenix.PubSub.subscribe(
          FluffyTrain.PubSub,
          FluffyTrain.OpenEI.topic_successfull_solution()
        )

        state
        |> Map.put(:status, "ON")
        |> Map.put(:is_agent_on, true)
      end

    {:reply, Map.get(state, :status), state}
  end

  def handle_call(:get_agent_status, _from, state) do
    status = Map.get(state, :status)
    {:reply, status, state}
  end

  def handle_call(:is_agent_on, _from, state) do
    status = Map.get(state, :is_agent_on)
    {:reply, status, state}
  end

  defp append_message(:user, message, state) do
    message = String.trim(message)

    state =
      Map.update!(state, :messages, fn messages ->
        messages ++ [%{role: "user", content: message}]
      end)

    state
  end

  defp append_message(:assistant, message, state) do
    message = String.trim(message)

    state =
      Map.update!(state, :messages, fn messages ->
        messages ++ [%{role: "assistant", content: message}]
      end)

    state
  end

  defp create_completion_request(state) do
    model_type = Map.get(state, :model_type)
    messages = Map.get(state, :messages)
    ChatCompletion.new(model: model_type, messages: messages)
  end

  defp get_response(state) do
    Logger.info("Getting streamed response")
    completion_request = create_completion_request(state)
    pid = self()

    {:ok, responce_task_pid} =
      Task.start(fn ->
        openai = Map.get(state, :openai)
        completion_stream = openai |> ChatCompletion.create(completion_request, stream: true)

        Phoenix.PubSub.local_broadcast(
          FluffyTrain.PubSub,
          topic_response_stream(),
          {:new_response, ""}
        )

        token_stream =
          completion_stream
          |> Stream.flat_map(& &1)
          |> Stream.map(fn %{data: d} ->
            d |> Map.get("choices") |> Enum.at(0) |> Map.get("delta")
          end)
          |> Stream.filter(fn map -> map |> Map.has_key?("content") end)
          |> Stream.map(fn map -> map |> Map.get("content") end)
          # Print each content to the console
          |> Stream.each(
            &Phoenix.PubSub.local_broadcast(
              FluffyTrain.PubSub,
              topic_response_stream(),
              {:new_content, &1}
            )
          )

        response =
          token_stream
          |> Enum.to_list()
          |> Enum.join("")

        send(pid, {:process_response, response})
      end)

    state = Map.put(state, :task_pid, responce_task_pid)
    state
  end

  defp is_fix_required(response, state) do
    result = TextExtractor.extract_for_fix(response)

    source = result["#SOURCE"]
    line = result["#LINE"]
    description = result["#DESCRIPTION"]
    timestamp = result["#TIMESTAMP"]

    if source != "" do
      Logger.info("Response has error details that require a fix")
      create_user_fix_code_request(source, line, description, timestamp, state)
    else
      Logger.info("Response doesn't have error details that require a fix")
    end
  end

  defp get_context(source, state) do
    Logger.info("Loading context")
    context_repo = Map.get(state, :context)
    context = Map.get(context_repo, source, "No source file in the context repo found")
    context
  end

  defp create_user_fix_code_request(source, line, description, timestamp, state) do
    Logger.info("Generating a message")
    context = get_context(source, state)

    fix_code_request_message =
      context <>
        "My application has encountered the following error: \n" <>
        "On " <>
        timestamp <>
        " in file " <>
        source <>
        " on line " <>
        line <>
        "\n" <>
        "Description: \n" <>
        description <>
        "\n" <>
        "How can I fix the issue? Provde complete code that can be executed via Code.compile to hotload the fix."

    Phoenix.PubSub.local_broadcast(
      FluffyTrain.PubSub,
      FluffyTrain.OpenEI.topic_user_message(),
      {:user_message, fix_code_request_message}
    )
  end

  defp is_code_validation_required(response) do
    result = TextExtractor.extract(response)

    code = result["#CODE"]
    example = result["#EXAMPLE"]
    output = result["#OUTPUT"]

    if code != "" do
      Logger.info("Response has code blocks that require evaluation")
      send(self(), {:evaluate_code, code, example, output})
    else
      Logger.info("Response doesn't have code blocks that require evaluation")
    end
  end

  defp is_it_hotreload_fix_to_be_appliead(response, state) do
    result = TextExtractor.extract_fix(response)

    fixed_code = result["#FIXED_SOURCE_CODE"]

    state =
      if fixed_code != "" do
        Logger.info("Response has fixed code blocks that can be hotreloaded")
        FluffyTrain.RuntimeEvaluator.apply_hotreload_fix(fixed_code)

        Phoenix.PubSub.local_broadcast(
          FluffyTrain.PubSub,
          FluffyTrain.OpenEAI.topic_user_message(),
          {:user_message, "HOT CODE UPDATE SUCCESSUFFULY APPLIED!!!"}
        )

        state
        |> Map.put(:is_agent_on, false)
      else
        Logger.info("Response doesn't have fixed code blocks that can be hotreloaded")
        state
      end

    state
  end

  def handle_info({:process_response, response}, state) do
    state = append_message(:assistant, response, state)
    is_code_validation_required(response)
    is_fix_required(response, state)
    state = is_it_hotreload_fix_to_be_appliead(response, state)
    {:noreply, state}
  end

  # def handle_info({:successfull_solution, response}, state) do
  # Logger.info("Successfull solution received")
  # state = handle_info({:user_message, response}, state)
  # {:noreply, state}
  # end

  def handle_info({:user_message, message}, state) do
    is_wip = Map.get(state, :is_wip)

    # if is_wip == false do
    # state =
    # Logger.info("User message: #{inspect(message)}")

    state = Map.put(state, :is_wip, true)
    state = append_message(:user, message, state)
    state = get_response(state)
    # state
    # end

    # Logger.warning("Can't process exception - WIP. Error message: #{inspect(message)}")

    {:noreply, state}
  end

  def handle_info({:successfull_solution, message}, state) do
    state = append_message(:user, message, state)
    state = get_response(state)
    {:noreply, state}
  end

  def handle_info({:evaluate_code, code, example, output}, state) do
    runtime_evaluation_results =
      RuntimeEvaluator.evaluate_and_construct_message(code, example, output)

    Phoenix.PubSub.local_broadcast(
      FluffyTrain.PubSub,
      topic_user_message(),
      {:user_message, runtime_evaluation_results}
    )

    {:noreply, state}
  end
end
