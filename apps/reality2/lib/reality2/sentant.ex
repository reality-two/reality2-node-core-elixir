defmodule Reality2.Sentant do
# *******************************************************************************************************************************************
@moduledoc false
# Start the Sentant, which is a Supervisor that manages the Sentant's Automations, Comms and Plugins.
#
# **Author**
# - Dr. Roy C. Davies
# - [roycdavies.github.io](https://roycdavies.github.io/)
# *******************************************************************************************************************************************

  use Supervisor, restart: :transient
  alias Reality2.Helpers.R2Process, as: R2Process
  alias Reality2.Helpers.R2Map, as: R2Map
  alias :mnesia, as: Mnesia
  alias Reality2.Helpers.Crypto, as: Crypto

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link({name, id, sentant_map}) do
    do_write = fn id, data ->
      Mnesia.write({:data, id, data})
    end

    encryption_key = case R2Map.get(sentant_map, "keys", nil) do
      nil -> nil
      keys ->
        case R2Map.get(keys, "encryption_key", nil) do
          nil -> nil
          key -> key
        end
    end

    # Add the name and id to the Sentant Map
    new_sentant_map = Map.merge(sentant_map, %{"id" => id, "name" => name})

    # Get the data from the Sentant Map and store in the Sentant Database
    new_sentant_map = case R2Map.get(new_sentant_map, "data") do
      nil -> new_sentant_map
      data ->
        try do
          case Jason.encode(data) do
            {:ok, data_string} ->
              data_to_store = case encryption_key do
                nil -> data_string
                key -> Base.encode64(Crypto.encrypt(data_string, key))
              end
              Mnesia.transaction(do_write, [id, data_to_store])
              new_sentant_map
            _ -> new_sentant_map
          end
        rescue
          _ -> new_sentant_map
        end

        # Remove data from the Sentant Map
        R2Map.delete(new_sentant_map, "data")
    end

    Supervisor.start_link(__MODULE__, {name, id, new_sentant_map})
    |> R2Process.register(id)
  end

  @impl true
  def init({name, id, sentant_map}) do
    children = [
      {Reality2.Plugins, {name, id, sentant_map}},
      {Reality2.Automations, {name, id, sentant_map}},
      {Reality2.Sentant.Comms, {name, id, sentant_map}}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Helper Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
end
