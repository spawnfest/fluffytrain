defmodule FluffyTrain.ExceptionCatcher do
  @behaviour :gen_event

  def init(_opts) do
    # Initialize state if needed
    {:ok, []}
  end

  def handle_event({:error, _group_leader, {Logger, message, timestamp, metadata}}, state)
      when is_list(metadata) do
    timestamp_string = "Timestamp: " <> "#{inspect(timestamp)}"
    error_string = "Error Message: " <> "#{message}"

    message_to_send = timestamp_string <> "\n" <> error_string <> "\n"

    Phoenix.PubSub.local_broadcast(
      FluffyTrain.PubSub,
      FluffyTrain.OpenEAI.topic_user_message(),
      {:user_message, message_to_send}
    )

    {:ok, state}
  end

  def handle_event(_other, state) do
    {:ok, state}
  end

  def handle_call({:configure, _options}, state) do
    # Handle backend configuration if needed
    {:ok, :ok, state}
  end

  def handle_info(_info, state) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end

  def code_change(_old_vsn, state, _extra) do
    {:ok, state}
  end
end
