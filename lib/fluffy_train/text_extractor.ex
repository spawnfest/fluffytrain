defmodule FluffyTrain.TextExtractor do
  def extract(text) do
    %{
      "#CODE" => extract_between_tags(text, "#CODE"),
      "#EXAMPLE" => extract_between_tags(text, "#EXAMPLE"),
      "#OUTPUT" => extract_between_tags(text, "#OUTPUT")
    }
  end

  def extract_for_fix(text) do
    %{
      "#SOURCE" => extract_between_tags(text, "#SOURCE"),
      "#LINE" => extract_between_tags(text, "#LINE"),
      "#DESCRIPTION" => extract_between_tags(text, "#DESCRIPTION"),
      "#TIMESTAMP" => extract_between_tags(text, "#TIMESTAMP")
    }
  end

  def extract_solution(text) do
    %{
      "#SOLUTION_SUCCESS" => extract_between_tags(text, "#SOLUTION_SUCCESS"),
      "#WORKING_CODE" => extract_between_tags(text, "#WORKING_CODE"),
      "#DESCRIPTION" => extract_between_tags(text, "#DESCRIPTION")
    }
  end

  def extract_fix(text) do
    %{
      "#FIXED_SOURCE_CODE" => extract_between_tags(text, "#FIXED_SOURCE_CODE")
    }
  end

  defp extract_between_tags(text, tag) do
    if String.contains?(text, tag) do
      parts = String.split(text, tag) |> Enum.reverse()
      prev_content = Enum.at(parts, 1)

      if prev_content do
        prev_content
        |> String.replace("'''elixir", "")
        |> String.replace("```", "")
        |> String.trim()
      else
        ""
      end
    else
      ""
    end
  end
end
