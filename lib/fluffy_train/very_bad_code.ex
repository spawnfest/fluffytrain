defmodule FluffyTrain.VeryBadCode do
  use GenServer
  require Logger

  @topic "very_bad_code"

  def topic, do: @topic

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    Phoenix.PubSub.subscribe(FluffyTrain.PubSub, topic())

    {:ok, %{}}
  end

  def handle_info({:divide_by_zero, _message}, state) do
    Logger.info("Trying to divide by zero")

    Task.start(fn ->
      FluffyTrain.DivideByZero.execute()
    end)

    {:noreply, state}
  end
end
