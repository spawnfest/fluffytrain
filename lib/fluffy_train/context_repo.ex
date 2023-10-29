defmodule FluffyTrain.ContextRepo do
  require Logger

  @file_list [
    "lib/fluffy_train/open_el.ex",
    "lib/fluffy_train/runtime_evaluator.ex",
    "lib/fluffy_train/text_extractor.ex",
    "lib/fluffy_train/lib/fluffy_train_web/live/portal.ex"
  ]

  def load_context() do
    @file_list
    |> Enum.map(fn file ->
      case File.read(file) do
        {:ok, contents} ->
          {file, contents}

        {:error, reason} ->
          Logger.warning("Failed to open file #{file}: #{reason}")
          {file, ""}
      end
    end)
    |> Enum.into(%{})
  end
end
