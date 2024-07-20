defmodule RPN do

  alias Reality2.Helpers.R2Map, as: R2Map

  @binary_ops ~w(+ - / * ^ atan2 fmod pow geohash)
  @unary_ops ~w(+ - acos acosh asin asinh atan atanh ceil cos cosh exp floor log log10 log2 sin sinh sqrt tan tanh latlong)
  @ops @binary_ops ++ @unary_ops

  def convert(input, context) when is_binary(input) do
    input |> String.split(" ") |> Enum.reduce([], &convert_rpn(&1, &2, context)) |> hd
  end

  def convert(input, context) when is_list(input) do
    input |> Enum.reduce([], &convert_rpn(&1, &2, context)) |> hd
  end

  defp convert_rpn(op, [a, b | tail], _context) when op in @binary_ops do
    case op do
      "+" -> [b+a | tail]
      "-" -> [b-a | tail]
      "*" -> [b*a | tail]
      "/" -> [b/a | tail]
      "^" -> [:math.pow(b, a) | tail]
      "atan2" -> [:math.atan2(b, a) | tail]
      "fmod" -> [:math.fmod(b, a) | tail]
      "pow" -> [:math.pow(b, a) | tail]
      "geohash" -> [Geohash.encode(b, a) | tail]
    end
  end

  defp convert_rpn(op, [a | tail], _context) when op in @unary_ops do
    case op do
      "+"    -> [a | tail]
      "-"    -> [-a | tail]
      "acos" -> [:math.acos(a) | tail]
      "acosh" -> [:math.acosh(a) | tail]
      "asin" -> [:math.asin(a) | tail]
      "asinh" -> [:math.asinh(a) | tail]
      "atan" -> [:math.atan(a) | tail]
      "atanh" -> [:math.atanh(a) | tail]
      "ceil" -> [:math.ceil(a) | tail]
      "cos" -> [:math.cos(a) | tail]
      "cosh" -> [:math.cosh(a) | tail]
      "exp" -> [:math.exp(a) | tail]
      "floor" -> [:math.floor(a) | tail]
      "log"   -> [:math.log(a) | tail]
      "log10" -> [:math.log10(a) | tail]
      "log2" -> [:math.log2(a) | tail]
      "sin" -> [:math.sin(a) | tail]
      "sinh" -> [:math.sinh(a) | tail]
      "sqrt" -> [:math.sqrt(a) | tail]
      "tan" -> [:math.tan(a) | tail]
      "tanh" -> [:math.tanh(a) | tail]

      "latlong" -> [Geohash.decode(a) | tail]
    end
  end

  defp convert_rpn(op, _rest, _context) when op in @ops do
    raise ArgumentError, message: "insufficient arguments count for #{op}"
  end

  defp convert_rpn(num_str, acc, context) do

    number = case safe_convert(num_str) do
      {:ok, num} -> num
      {:str, _} ->
        case R2Map.get(context, num_str) do
          nil -> %{error: "unknown variable #{num_str}"}
          num2 ->
            case safe_convert(num2) do
              {:ok, num3} -> num3
              _ -> %{error: "invalid value for variable #{num_str}"}
            end
        end
      end
    [number | acc]
  end

  defp safe_convert(num_str) do
    try do
      case Float.parse(num_str) do
        {num, _} -> {:ok, num} # Was a number in a string, so all good.
        _ ->
          case num_str do
            "pi" -> {:ok, :math.pi} # Special case for pi
            "e" -> {:ok, 2.7182818284590452353602874713527} # Special case for e
            _ -> {:str, num_str} # Probably a variable naame or something else.
          end
      end
    rescue
      _ -> {:ok, num_str} # Is not a string, perhaps a number, so return that
    end
  end
end
