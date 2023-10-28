defmodule FluffyTrainWeb.Portal do
  use FluffyTrainWeb, :live_view
  require Logger
  alias FluffyTrain.TextExtractor
  alias FluffyTrain.RuntimeEvaluator
  alias FluffyTrain.PromptRepo
  alias OpenaiEx.ChatCompletion
  alias OpenaiEx.ChatMessage

  def mount(_params, _session, socket) do
    socket = assign(socket, form: to_form(%{}, as: "object"))

    Phoenix.PubSub.subscribe(FluffyTrain.PubSub, FluffyTrain.OpenEL.topic_response_stream())

    openai = [
      [%{prompt: PromptRepo.prompt(), model_type: PromptRepo.model()}]
    ]

    {:ok,
     assign(socket,
       openai: openai,
       output: "",
       text: nil,
       content: "",
       raw_messages: FluffyTrain.OpenEL.get_raw_messages()
     )}
  end

  def handle_info({:new_response, _}, socket) do
    {:noreply,
     assign(socket,
       raw_messages: socket.assigns.raw_messages ++ [%{role: "assistant", content: ""}]
     )}
  end

  def handle_info({:new_content, new_content}, socket) do
    raw_messages = socket.assigns.raw_messages
    last_index = length(raw_messages) - 1

    updated_raw_messages =
      List.update_at(raw_messages, last_index, fn last_message ->
        Map.update!(last_message, :content, &(&1 <> new_content))
      end)

    {:noreply, assign(socket, raw_messages: updated_raw_messages)}
  end

  def handle_info({:validate_code}, socket) do
    result = TextExtractor.extract(socket.assigns.content)

    code = result["#CODE"]
    example = result["#EXAMPLE"]
    output = result["#OUTPUT"]

    %{error: code_errors, warnings: code_warnings, evaluation: code_evaluation} =
      RuntimeEvaluator.evaluate(code)

    send(
      self(),
      {:new_content,
       "User:\n After running the code and examples you provided I got the following:\n"}
    )

    send(self(), {:new_content, "Code compilation errors: \n" <> code_errors <> "\n"})
    send(self(), {:new_content, "Code compilation warnings: \n" <> code_warnings <> "\n"})

    %{error: example_errors, warnings: example_warnings, evaluation: example_evaluation} =
      RuntimeEvaluator.evaluate(example)

    send(self(), {:new_content, "Example code compilation errors: \n" <> example_errors <> "\n"})

    send(
      self(),
      {:new_content, "Example code compilation warnings: \n" <> example_warnings <> "\n"}
    )

    send(
      self(),
      {:new_content,
       "Execution output of example code is, as provided by Code.eval_string: \n" <>
         "#{inspect(example_evaluation)}" <>
         "\n" <>
         "vs the expected result: " <> output <> "\n"}
    )

    # Need to remove the module, otherwise a warning is generated because next run will overwrite the current module
    case code_evaluation do
      {{:module, module_name, _binary, _tuple}, _list} ->
        RuntimeEvaluator.remove_module(module_name)

      _ ->
        Logger.info("No module defined in the code.")
    end

    if code_errors != "" or code_warnings != "" or example_errors != "" or
         example_warnings != "" do
      Logger.warning("Errors or warnings are not empty.")
      [[%{prompt: extracted_prompt, model_type: extracted_model_type}]] = socket.assigns.openai

      send(
        self(),
        {:chat_completion, extracted_prompt, extracted_model_type, socket.assigns.content}
      )
    end

    {:noreply, socket}
  end

  def handle_info({:chat_completion, prompt, model_type, text}, socket) do
    pid = self()

    apikey = System.fetch_env!("OPENAI_API_KEY")
    openai = OpenaiEx.new(apikey)

    completion_req =
      ChatCompletion.new(
        model: model_type,
        messages: [ChatMessage.system(prompt), ChatMessage.user(text)]
      )

    Task.start(fn ->
      completion_stream = openai |> ChatCompletion.create(completion_req, stream: true)

      token_stream =
        completion_stream
        |> Stream.flat_map(& &1)
        |> Stream.map(fn %{data: d} ->
          d |> Map.get("choices") |> Enum.at(0) |> Map.get("delta")
        end)
        |> Stream.filter(fn map -> map |> Map.has_key?("content") end)
        |> Stream.map(fn map -> map |> Map.get("content") end)
        # Print each content to the console
        |> Stream.each(&send(pid, {:new_content, &1}))

      Enum.to_list(token_stream)
      send(pid, {:new_content, "\n"})
      send(pid, {:validate_code})
    end)

    {:noreply, socket}
  end

  def handle_event("submit_text", %{"text" => text}, socket) do
    Phoenix.PubSub.local_broadcast(
      FluffyTrain.PubSub,
      FluffyTrain.OpenEL.topic_user_message(),
      {:user_message, text}
    )

    {:noreply,
     assign(socket,
       text: text,
       raw_messages: socket.assigns.raw_messages ++ [%{role: "user", content: text}]
     )}
  end

  def handle_event("new_chat", _params, socket) do
    FluffyTrain.OpenEL.reset_state()

    {:noreply,
     assign(socket,
       content: "",
       raw_messages: FluffyTrain.OpenEL.get_raw_messages()
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="container mt-4 w-full pb-32"> <!-- Added padding-bottom to make space for the floating form -->
    <.button color="info" label="New Chat" variant="shadow" phx-click="new_chat" class="fixed top-12 left-0 m-4 z-50"/>
    <%= for %{role: role, content: content} <- @raw_messages do %>
      <.card class="mt-4 ">
        <.card_content category={role} class={"max-w-full #{if role == "user", do: "bg-gray-600 bg-opacity-60", else: "bg-blue-600 bg-opacity-20"}"}>
          <div class="whitespace-pre-line">
            <%= content %>
          </div>
        </.card_content>
      </.card>
    <% end %>
    <div class="fixed bottom-0 z-50 w-2/3 bg-white dark:bg-gray-800 shadow" style="left: 50%; transform: translateX(-50%); background: rgba(255, 255, 255, 0.6);">
      <form phx-submit="submit_text" class="p-4">
        <textarea name="text" id="message" rows="4" class="mt-4 block p-2.5 w-full text-sm text-gray-900 bg-gray-50 rounded-lg border border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500" placeholder="Write your thoughts here..."><%= assigns.text %></textarea> <br />
        <.button type="submit" color="success">
          Submit
        </.button>
      </form>
    </div>


    <%= @output %>
    <.alert color="info">
    This is an info alert
    </.alert>
    </div>
    """
  end
end
