defmodule FluffyTrain.TextExtractor do
  def extract(text) do
    %{
      "#CODE" => extract_between_tags(text, "#CODE"),
      "#EXAMPLE" => extract_between_tags(text, "#EXAMPLE"),
      "#OUTPUT" => extract_between_tags(text, "#OUTPUT")
    }
  end

  defp extract_between_tags(text, tag) do
    if String.contains?(text, tag) do
      parts = String.split(text, tag) |> Enum.reverse()
      prev_content = Enum.at(parts, 1)

      if prev_content do
        String.trim(prev_content)
      else
        ""
      end
    else
      ""
    end
  end
end
