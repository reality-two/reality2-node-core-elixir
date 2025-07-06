defmodule Reality2.Swarm do
# *******************************************************************************************************************************************
@moduledoc """
  Module for creating and managing Swarms on a Node.  A Swarm is a collection of Sentants that are managed together.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
"""
# *******************************************************************************************************************************************

  alias Reality2.Types
  alias Reality2.Helpers.R2Map, as: R2Map

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec create(Types.swarm() | String.t()) ::
    {:ok, map}
    | {:error, :definition}
  @doc """
  Create a new Swarm on the Node, returning {:ok} or an appropriate error.

  Uploading a Swarm creates the Sentants on the Node, and then sends the init event to each Sentant.
  If Sentants with the same name or ID already exist on the Node, then they are not created again, but redefined and restarted.

  - Parameters
    - `swarm_definition` - A map containing the definition of the Swarm, or a string containing the YAML definition of the Swarm.
  """
  def create(swarm_definition) do
    case convert_input(swarm_definition) do
      {:ok, definition_map} ->
        swarm_map = remove_swarm_parent_from_definition_map(definition_map)
        case Reality2.Types.validate(swarm_map, Reality2.Types.swarm()) do
          :ok ->
            create_from_map(swarm_map)
          {:error, error} -> {:error, error}
        end
      _ ->
        {:error, :definition}
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp create_from_map(definition_map) do
    name = R2Map.get(definition_map, "name", "")
    description = R2Map.get(definition_map, "description", "")
    case R2Map.get(definition_map, "sentants") do
      nil ->
        {:ok, %{name: name, description: description, sentants: []}}
      sentants ->
        case is_list(sentants) do
          true ->
            sentant_ids = Enum.map(sentants, fn sentant_map ->
              case Reality2.Sentants.create(sentant_map) do
                {:ok, id} ->
                  id
                {:error, reason} ->
                  {:error, reason}
              end
            end)
            |> Enum.filter(fn x ->
              case x do
                {:error, _reason} -> false
                _ -> true
              end
            end)
            {:ok, %{name: name, description: description, sentants: sentant_ids}}
          false -> {:ok, %{name: name, description: description, sentants: []}}
        end
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Convert an input String in either JSON, TOML or YAML format to a map.
  defp convert_input(definition) when is_map(definition), do: {:ok, definition}
  defp convert_input(definition) when is_binary(definition) do
    case Jason.decode(definition) do
      {:ok, definition_map} ->
        {:ok, definition_map}
      _ ->
        case YamlElixir.read_from_string(definition) do
          {:ok, definition_map} ->
            {:ok, definition_map}
          _ -> case Toml.decode(definition) do
            {:ok, definition_map} ->
              {:ok, definition_map}
            _ -> {:error, :definition}
          end
        end
    end
  end
  defp convert_input(_), do: {:error, :definition}
  # -----------------------------------------------------------------------------------------------------------------------------------------

  defp remove_swarm_parent_from_definition_map(%{"swarm" => swarm_map}), do: swarm_map
  defp remove_swarm_parent_from_definition_map(%{swarm: swarm_map}), do: swarm_map
  defp remove_swarm_parent_from_definition_map(swarm_map), do: swarm_map
end
