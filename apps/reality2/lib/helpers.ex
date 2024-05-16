defmodule Helpers do
  @moduledoc """
  Some useful helper functions for working with Elixir data structures.
    - Version: 0.0.1
    - Date: 2024-03-23

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """

  defmodule Map do

    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec get(map(), String.t() | atom() | binary(), any()) ::
    any()
    @doc """
    Gets a value from a map where the key in the map may be a string or an atom, and the key in the function call may be a string or an atom.

    - Parameters
      - `map` - The map to get the value from.
      - `key` - The key to get the value for.
      - `default` - The default value to return if the key is not found in the map.
    """
  def get(map, key, default \\ nil)
  def get(nil, _, default), do: default

    def get(map, key, default) when is_binary(key) do
      case Elixir.Map.get(map, key) do
        nil ->
          case Elixir.Map.get(map, String.to_atom(key)) do
            nil -> default
            value -> value
          end
        value -> value
      end
    end

    def get(map, key, default) when is_atom(key) do
      case Elixir.Map.get(map, key) do
        nil ->
          case Elixir.Map.get(map, Atom.to_string(key)) do
            nil -> default
            value -> value
          end
        value -> value
      end
    end

    def get(map, key, default), do: Elixir.Map.get(map, key, default)

    def delete(map, key) when is_binary(key) do
      Elixir.Map.delete(map, key)
      Elixir.Map.delete(map, String.to_atom(key))
    end
    def delete(map, key) when is_atom(key) do
      Elixir.Map.delete(map, key)
      Elixir.Map.delete(map, Atom.to_string(key))
    end

  end
  # -----------------------------------------------------------------------------------------------------------------------------------------




  # Takes a map representing a JSON object along with a path, and returns the value at that path.
  defmodule Json do
    def get_value(data, path) do
      case get_values(data, String.split(path, ".")) do
        nil -> {:error, :not_found}
        value -> {:ok, value}
      end
    end

    defp get_values(data, []), do: data

    defp get_values(data, [key | tail]) when is_map(data) do
      case Helpers.Map.get(data, key) do
        nil -> nil
        value -> get_values(value, tail)
      end
    end

    defp get_values(data, [key | tail]) when is_list(data) do
      if key == "[]" do
        Enum.map(data, fn value -> get_values(value, tail) end) |> Enum.filter(& &1 != nil)
      else
        try do
          String.to_integer(key)
        rescue
          _ -> {:error, :not_found}
        else
          index -> case Enum.at(data, index) do
            nil -> nil
            value -> get_values(value, tail)
          end
        end
      end
    end

    defp get_values(data, _), do: data
  end
end
