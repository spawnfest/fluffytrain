defmodule FluffyTrainWeb.OpenEIPortal do
  use FluffyTrainWeb, :live_view
  require Logger

  def mount(_params, _session, socket) do
    socket = assign(socket, form: to_form(%{}, as: "object"))

    Phoenix.PubSub.subscribe(FluffyTrain.PubSub, FluffyTrain.OpenEI.topic_response_stream())
    Phoenix.PubSub.subscribe(FluffyTrain.PubSub, FluffyTrain.OpenEI.topic_user_message())

    {:ok,
     assign(socket,
       text: nil,
       content: "",
       raw_messages: FluffyTrain.OpenEI.get_raw_messages()
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

  def handle_info({:user_message, message}, socket) do
    Logger.info("User message: #{inspect(message)}")

    {:noreply,
     assign(socket,
       raw_messages: socket.assigns.raw_messages ++ [%{role: "user", content: message}]
     )}
  end

  def handle_info({:successfull_solution, message}, socket) do
    {:noreply, socket}
  end

  def handle_event("submit_text", %{"text" => text}, socket) do
    Phoenix.PubSub.local_broadcast(
      FluffyTrain.PubSub,
      FluffyTrain.OpenEI.topic_user_message(),
      {:user_message, text}
    )

    {:noreply, socket}
  end

  def handle_event("new_chat", _params, socket) do
    FluffyTrain.OpenEI.reset_state()

    {:noreply,
     assign(socket,
       content: "",
       raw_messages: FluffyTrain.OpenEI.get_raw_messages()
     )}
  end

  def handle_event("cancel_generation", _params, socket) do
    FluffyTrain.OpenEI.cancel_generation()

    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="container mt-4 w-full pb-32 flex"> <!-- Added padding-bottom to make space for the floating form -->
      <div class="w-1/4 flex flex-col items-center fixed" style="top: 10%; left: 5%;">
        <img src="/images/Logo_Concept_2.png" class="object-cover h-41 w-41">
        <.button color="info" label="New Chat" variant="shadow" phx-click="new_chat" class="top-60 m-4 z-50"/>
        <.button color="danger" label="Cancel Generation" variant="shadow" phx-click="cancel_generation" class="top-80 m-4 z-5"/>
      </div>
      <div class="w-2/3 mx-auto" style="margin-left: 30%;"> <!-- Shifted the card div to the right -->
        <%= for %{role: role, content: content} <- @raw_messages do %>
          <.card class="mt-4 ">
            <.card_content category={role} class={"max-w-full #{if role == "user", do: "bg-gray-600 bg-opacity-60", else: "bg-blue-600 bg-opacity-20"}"}>
              <div class="whitespace-pre-line">
                <%= content %>
              </div>
            </.card_content>
          </.card>
        <% end %>
        <div class="mb-20"></div> <!-- Added padding below the last card -->
        <div class="fixed bottom-0 z-50 w-1/2 mx-auto bg-white dark:bg-gray-800 shadow" style="left: 50%; transform: translateX(-50%); background: rgba(255, 255, 255, 0.6);">
          <form phx-submit="submit_text" class="p-4">
            <textarea name="text" id="message" rows="4" class="mt-4 block p-2.5 w-full text-sm text-gray-900 bg-gray-50 rounded-lg border border-gray-300 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500" placeholder="Write your thoughts here..."><%= assigns.text %></textarea> <br />
            <.button type="submit" color="success">
              Submit
            </.button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
