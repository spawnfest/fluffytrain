defmodule FluffyTrainWeb.Portal do
  use FluffyTrainWeb, :live_view

  def mount(params, session, socket) do
    {:ok,
     assign(socket,
       output: "",
       document_types: ["Select a document type"],
       text: "",
       content: ""
     )}
  end

  def render(assigns) do
    ~H"""
    <div class="container mt-4 w-full">
    <textarea name="text2" rows="20" cols="100"><%= @content %></textarea>
    <form phx-submit="submit_text">
    <textarea name="text" rows="20" cols="100">
    <%= assigns.text %>
    </textarea> <br />
    <.button type="submit" color="success">
      Submit
    </.button>
    </form>

    <%= @output %>
    </div>
    """
  end
end
