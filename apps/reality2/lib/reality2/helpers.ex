defmodule Reality2.Helpers do
  # *******************************************************************************************************************************************
  @moduledoc false
  # Some useful functions arranged into modules
  #
  # **Author**
  # - Dr. Roy C. Davies
  # - [roycdavies.github.io](https://roycdavies.github.io/)
  # *******************************************************************************************************************************************


    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Process management in a process registry
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defmodule R2Process do
      @doc false
      use GenServer

      # ---------------------------------------------------------------------------------------------------------------------------------------
      # GenServer callbacks
      # ---------------------------------------------------------------------------------------------------------------------------------------
      @doc false
      def start_link(name),                              do: GenServer.start_link(__MODULE__, %{}, name: name)

      @doc false
      def init(state),                                   do: {:ok, state}
      # ---------------------------------------------------------------------------------------------------------------------------------------


      # ---------------------------------------------------------------------------------------------------------------------------------------
      # Public Functions
      # ---------------------------------------------------------------------------------------------------------------------------------------


      # ---------------------------------------------------------------------------------------------------------------------------------------
      # Alternative whereis function that doesn't require atoms
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def whereis(name), do: whereis(name, __MODULE__)
      def whereis(name, module) do
        case GenServer.call(module, {:get, name}) do
          nil -> nil
          pid when is_pid(pid) ->
            case Elixir.Process.info(pid) do # Process is no longer running, so deregister
              nil -> deregister(name, module)
              _ -> pid
            end
          other -> other
        end
      end
      # ---------------------------------------------------------------------------------------------------------------------------------------



      # ---------------------------------------------------------------------------------------------------------------------------------------
      # The opposite of 'whereis', given a PID, return the name.
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def whatis(pid), do: whatis(pid, __MODULE__)
      def whatis(pid, module) do
        case GenServer.call(module, {:get, pid}) do
          nil -> nil
          name ->
            case Elixir.Process.info(pid) do
              nil -> deregister(name, module)
              _ -> name
            end
        end
      end
      # ---------------------------------------------------------------------------------------------------------------------------------------



      # ---------------------------------------------------------------------------------------------------------------------------------------
      # Convenience functions
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def pid(name), do: whereis(name)
      def pid(name, module), do: whereis(name, module)
      def name(pid), do: whatis(pid)
      def name(pid, module), do: whatis(pid, module)
      def all(), do: GenServer.call(__MODULE__, {:all})
      def all(module), do: GenServer.call(module, {:all})
      # ---------------------------------------------------------------------------------------------------------------------------------------



      # ---------------------------------------------------------------------------------------------------------------------------------------
      # Register a Process ID.  The first three simplify the registration of a process that has just been started.
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def register({:ok, pid}, name, module) when is_atom(name), do: register(Atom.to_string(name), pid, module)
      def register({:ok, pid}, name, module), do: register(name, pid, module)
      def register({:error, reason}, _, _), do: {:error, reason}
      def register(key, value, module) do
        GenServer.call(module, {:set, key, value})
        GenServer.call(module, {:set, value, key})
        {:ok, value}
      end
      def register({:ok, pid}, name) when is_atom(name), do: register(Atom.to_string(name), pid, __MODULE__)
      def register({:ok, pid}, name), do: register(name, pid, __MODULE__)
      def register({:error, reason}, _), do: {:error, reason}
      def register(key, value), do: register(key, value, __MODULE__)
      # ---------------------------------------------------------------------------------------------------------------------------------------



      # ---------------------------------------------------------------------------------------------------------------------------------------
      # Deregister a Process ID
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def deregister(name_or_id), do: deregister(name_or_id, __MODULE__)
      def deregister(name_or_id, module) do
        case GenServer.call(module, {:get, name_or_id}) do
          nil -> nil
          the_other ->
            GenServer.call(module, {:delete, name_or_id})
            GenServer.call(module, {:delete, the_other})
            nil
        end
        :ok
      end
      # ---------------------------------------------------------------------------------------------------------------------------------------



      # ---------------------------------------------------------------------------------------------------------------------------------------
      # GenServer callbacks
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def handle_call({:set, key, value}, _from, state),    do: {:reply, :ok, Elixir.Map.put(state, key, value)}
      def handle_call({:delete, key}, _from, state),        do: {:reply, :ok, Elixir.Map.delete(state, key)}
      def handle_call({:get, key}, _from, state),           do: {:reply, Elixir.Map.get(state, key, nil), state}
      def handle_call({:all}, _from, state),                do: {:reply, state, state}
      # ---------------------------------------------------------------------------------------------------------------------------------------



      # ---------------------------------------------------------------------------------------------------------------------------------------
      # A useful Map Get function
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def get(map, key, default \\ nil)
      def get(nil, _, default), do: default
      def get(map, _, default) when not is_map(map), do: default
      def get(map, key, default) when is_binary(key), do: Elixir.Map.get(map, key, nil) || Elixir.Map.get(map, String.to_atom(key), default)
      def get(map, key, default) when is_atom(key), do: Elixir.Map.get(map, key, nil) || Elixir.Map.get(map, Atom.to_string(key), default)
      def get(map, key, default), do: Elixir.Map.get(map, key, default)
      # ---------------------------------------------------------------------------------------------------------------------------------------
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # A set of Map functions that work regardless if the key is a binary or an atom
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defmodule R2Map do
      @moduledoc false

      # ---------------------------------------------------------------------------------------------------------------------------------------
      # A useful Map Get function that works regardless if the key is a binary or an atom
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def get(map, key, default \\ nil)
      def get(nil, _, default), do: default
      def get(map, _, default) when not is_map(map), do: default
      def get(map, key, default) when is_binary(key), do: Elixir.Map.get(map, key, nil) || Elixir.Map.get(map, String.to_atom(key), default)
      def get(map, key, default) when is_atom(key), do: Elixir.Map.get(map, key, nil) || Elixir.Map.get(map, Atom.to_string(key), default)
      def get(map, key, default), do: Elixir.Map.get(map, key, default)
      # ---------------------------------------------------------------------------------------------------------------------------------------



      # ---------------------------------------------------------------------------------------------------------------------------------------
      # A useful Map Delete function that works regardless if the key is a binary or an atom
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def delete(nil, _), do: nil
      def delete(map, _) when not is_map(map), do: nil
      def delete(map, key) when is_binary(key), do: Elixir.Map.delete(map, key) |> Elixir.Map.delete(String.to_atom(key))
      def delete(map, key) when is_atom(key), do: Elixir.Map.delete(map, key) |> Elixir.Map.delete(Atom.to_string(key))
      def delete(map, key), do: Elixir.Map.delete(map, key)
      # ---------------------------------------------------------------------------------------------------------------------------------------



      # ---------------------------------------------------------------------------------------------------------------------------------------
      # A useful Map Put function that works regardless if the key is a binary or an atom
      # ---------------------------------------------------------------------------------------------------------------------------------------
      def put(nil, _, _), do: nil
      def put(_, nil, _), do: nil
      def put(map, _, _) when not is_map(map), do: nil
      def put(map, key, value) when is_atom(key), do: Elixir.Map.put(map, Atom.to_string(key), value)
      def put(map, key, value), do: Elixir.Map.put(map, key, value)
      # ---------------------------------------------------------------------------------------------------------------------------------------

    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # A set of functions to help extract data from a JSON structure using a simplified JSON path.
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defmodule JsonPath do
      def get_value(data, path) do
        case get_values(data, String.split(path, ".")) do
          nil -> {:error, :not_found}
          value -> {:ok, value}
        end
      end

      defp get_values(data, []), do: data

      defp get_values(data, [key | tail]) when is_map(data) do
        case Reality2.Helpers.R2Map.get(data, key) do
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
    # -----------------------------------------------------------------------------------------------------------------------------------------


    # -----------------------------------------------------------------------------------------------------------------------------------------
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defmodule Crypto do
      def encrypt(data, encoded_encryption_key) do
        key = Base.decode64!(encoded_encryption_key)
        iv = :crypto.strong_rand_bytes(12)
        {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_gcm, key, iv, data, "", true)

        # Combine IV, tag, and ciphertext into a blob
        iv <> tag <> ciphertext
      end

      def decrypt(data, encoded_decryption_key) do
        key = Base.decode64!(encoded_decryption_key)
        <<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>> = data
        :crypto.crypto_one_time_aead(:aes_gcm, key, iv, ciphertext, "", tag, false)
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defmodule Convert do
      def to_float(nil), do: 0.0
      def to_float(value) when is_number(value), do: value + 0.0 # Convert to float
      def to_float(value) do
        try do
          String.to_integer(value)
        rescue
          _ ->
            try do
              String.to_float(value)
            rescue
              _ ->
                0.0
            end
        end + 0.0 # Convert to float
      end

      def to_integer(nil), do: 0
      def to_integer(value) when is_float(value), do: Math.round(value)
      def to_integer(value) when is_integer(value), do: value
      def to_integer(value) do
        try do
          String.to_integer(value)
        rescue
          _ ->
            try do
              String.to_float(value) |> Math.round()
            rescue
              _ ->
                0
            end
        end
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------
  end
