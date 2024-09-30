defmodule Reality2.Calculation do

  def calculate(nil, _), do: nil
  def calculate(op, _) when is_number(op), do: op
  def calculate(op, _) when is_boolean(op), do: op
  def calculate("true", _), do: true
  def calculate("false", _), do: false

  def calculate(op, vars) when is_binary(op) do
    case Map.fetch(vars, op) do
      {:ok, val} -> val
      _ -> nil
    end
  end

  def calculate( %{"+" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a + b end)
  def calculate( %{"-" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a - b end)
  def calculate( %{"*" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a * b end)
  def calculate( %{"/" => [ _, 0 ]}, _ ), do: nil
  def calculate( %{"/" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a / b end)
  def calculate( %{"^" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> :math.pow(a, b) end)
  def calculate( %{"atan2" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> :math.atan2(a, b) end)
  def calculate( %{"fmod" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> :math.fmod(a, b) end)
  def calculate( %{"pow" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> :math.pow(a, b) end)
  def calculate( %{"geohash" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> Geohash.encode(a, b) end)
  def calculate( %{"&&" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a && b end)
  def calculate( %{"||" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a || b end)
  def calculate( %{"==" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a == b end)
  def calculate( %{"!=" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a != b end)
  def calculate( %{">" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a > b end)
  def calculate( %{"<" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a < b end)
  def calculate( %{">=" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a >= b end)
  def calculate( %{"<=" => [ op2, op3 ]}, vars ), do: binaryop(calculate(op2, vars), calculate(op3, vars), fn a, b -> a <= b end)

  def calculate( %{"+" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> a end)
  def calculate( %{"-" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> -a end)
  def calculate( %{"!" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> !a end)
  def calculate( %{"acos" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.acos(a) end)
  def calculate( %{"acosh" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.acosh(a) end)
  def calculate( %{"asin" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.asin(a) end)
  def calculate( %{"asinh" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.asinh(a) end)
  def calculate( %{"atan" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.atan(a) end)
  def calculate( %{"atanh" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.atanh(a) end)
  def calculate( %{"ceil" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.ceil(a) end)
  def calculate( %{"cos" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.cos(a) end)
  def calculate( %{"cosh" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.cosh(a) end)
  def calculate( %{"exp" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.exp(a) end)
  def calculate( %{"floor" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.floor(a) end)
  def calculate( %{"log" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.log(a) end)
  def calculate( %{"log10" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.log10(a) end)
  def calculate( %{"log2" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.log2(a) end)
  def calculate( %{"sin" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.sin(a) end)
  def calculate( %{"sinh" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.sinh(a) end)
  def calculate( %{"sqrt" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.sqrt(a) end)
  def calculate( %{"tan" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.tan(a) end)
  def calculate( %{"tanh" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> :math.tanh(a) end)
  def calculate( %{"latlong" => op2 }, vars ), do: unaryop(calculate(op2, vars), fn a -> Geohash.decode(a) end)

  defp binaryop(nil, _, _), do: nil
  defp binaryop(_, nil, _), do: nil
  defp binaryop(op1, op2, func) do
    {_, op1_converted} = safe_convert(op1)
    {_, op2_converted} = safe_convert(op2)

    func.(op1_converted, op2_converted)
  end

  defp unaryop(nil, _), do: nil
  defp unaryop(op1, func) do
    {_, op1_converted} = safe_convert(op1)

    func.(op1_converted)
  end


  defp safe_convert(num_str) do
    try do
      case Float.parse(num_str) do
        {num, _} -> {:ok, num} # Was a number in a string, so all good.
        _ ->
          case num_str do
            "pi" -> {:ok, :math.pi} # Special case for pi
            "e" -> {:ok, 2.7182818284590452353602874713527} # Special case for e
            "true" -> {:ok, :true}
            "false" -> {:ok, :false}
            _ -> {:str, num_str} # Probably a variable naame or something else.
          end
      end
    rescue
      _ -> {:ok, num_str} # Is not a string, perhaps a number, so return that
    end
  end
end
