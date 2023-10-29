defmodule FluffyTrain.OpenEL do
  use GenServer
  require Logger
  alias FluffyTrain.RuntimeEvaluator
  alias FluffyTrain.PromptRepo
  alias FluffyTrain.TextExtractor
  alias OpenaiEx.ChatCompletion

  @topic_user_message "open_el:user_message"
  @topic_response_stream "open_el:response_stream"

  def topic_user_message, do: @topic_user_message
  def topic_response_stream, do: @topic_response_stream

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # Phoenix.PubSub.local_broadcast(LynceusApplication.PubSub, @topic, {:node_up, node})

  def init(_) do
    state = reset()
    Phoenix.PubSub.subscribe(FluffyTrain.PubSub, topic_user_message())

    {:ok, state}
  end

  defp reset() do
    apikey = System.fetch_env!("OPENAI_API_KEY")
    openai = OpenaiEx.new(apikey)
    model_type = PromptRepo.model()
    system = PromptRepo.prompt()

    state = %{
      apikey: apikey,
      openai: openai,
      model_type: model_type,
      task_pid: nil,
      system: system,
      messages: [%{role: "system", content: system}],
      processed_messages: %{}
    }

    state
  end

  def reset_state do
    GenServer.cast(__MODULE__, :reset_state)
  end

  def get_raw_messages() do
    GenServer.call(__MODULE__, :get_raw_messages)
  end

  def cancel_generation do
    GenServer.cast(__MODULE__, :cancel_generation)
  end

  def handle_cast(:reset_state, _state) do
    {:noreply, reset()}
  end

  def handle_cast(:cancel_generation, state) do
    IO.inspect(state)
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

  defp is_code_validation_required(response) do
    result = TextExtractor.extract(response)

    code = result["#CODE"]
    example = result["#EXAMPLE"]
    output = result["#OUTPUT"]

    if code != "" do
      Logger.info("Response has code blocks that require evaluation")
      send(self(), {:evaluate_code, code, example, output})
    end
  end

  def handle_info({:process_response, response}, state) do
    state = append_message(:assistant, response, state)
    is_code_validation_required(response)
    {:noreply, state}
  end

  def handle_info({:user_message, message}, state) do
    Logger.info("User message: #{inspect(message)}")

    state = append_message(:user, message, state)

    state = get_response(state)

    IO.inspect(state)

    {:noreply, state}
  end

  def handle_info({:evaluate_code, code, example, output}, state) do
    runtime_evaluation_results =
      RuntimeEvaluator.evaluate_and_construct_message(code, example, output)

    Phoenix.PubSub.local_broadcast(
      FluffyTrain.PubSub,
      FluffyTrain.OpenEL.topic_user_message(),
      {:user_message, runtime_evaluation_results}
    )

    {:noreply, state}
  end
end
