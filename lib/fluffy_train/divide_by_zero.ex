defmodule FluffyTrain.DivideByZero do
  def execute() do
    number = 10
    divisor = 0
    IO.puts("Attempting to divide by zero...")
    result = number / divisor
    IO.puts("Result: #{result}")
  end
end
