defmodule AiReality2Backup.Main do
  # *******************************************************************************************************************************************
  @moduledoc """
    Module for managing the main supervisor tree for the `AiReality2Backup` App.

    In this instance, the main supervisor is a DynamicSupervisor, which is used to manage the database storage for Sentants.
    Presently, we are using mnesia as the database due to its general availability.

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """
  # *******************************************************************************************************************************************
    @doc false
    use GenServer, restart: :transient
    alias Reality2.Helpers.R2Map, as: R2Map
    alias Reality2.Helpers.Crypto, as: Crypto
    alias :mnesia, as: Mnesia

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Supervisor Callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def start_link(name),                              do: GenServer.start_link(__MODULE__, %{}, name: name)

    @doc false
    def init(state) do
      with :stopped <- Mnesia.stop(),
        :ok <- create_schema(),
        :ok <- Mnesia.start(),
        :ok <- create_table(:backup, [attributes: [:name, :data], disc_only_copies: [node()]]),
        :ok <- create_table(:data, [attributes: [:id, :data], disc_only_copies: [node()]])
      do
        IO.puts("[ai.reality2.backup] started successfully.")
        {:ok, state}
      else
        _ -> {:error, :mnesia}
      end
    end

    defp create_schema do
      case Mnesia.create_schema([node()]) do
        :ok ->
          :ok
        {:error, {_, {:already_exists, _}}} ->
          :ok
        error -> error
      end
    end

    defp create_table(table_name, attributes) do
      case Mnesia.create_table(table_name, attributes) do
        {:atomic, :ok} ->
          :ok
        {:aborted, {:already_exists, _}} ->
          :ok
        error -> error
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Public Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec create(String.t()) ::
      {:ok}
      | {:error, :existance}

    @doc """
    Does nothing in this module as there are no child processes.

    - Parameters
      - `sentant_id` - ignored in this implementation.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def create(_sentant_id) do
      {:ok}
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec delete(String.t()) ::
      {:ok}
      | {:error, :existance}

    @doc """
    Does nothing in this module as there are no child processes.

    - Parameters
      - `sentant_id` - ignored in this implementation.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def delete(_sentant_id) do
      {:ok}
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec whereis(String.t() | pid()) :: pid() | String.t() | nil
    @doc """
    Return the process id that can be used for subsequent communications.

    In this implementation, this just refers to this module.

    - Parameters
      - `id` - The id of the Sentant for which process id is being returned.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def whereis(_sentant_id) do
      self()
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec sendto(String.t(), map()) :: :ok | {:error, :command} | {:ok, any()} | {:error, :key}
    @doc """
    Do things with the database.

    - Parameters
      - `id` - The id of the Sentant for which the command is being sent (ignored here)
      - `command` - A map containing the command and parameters to be sent.

    - Returns
      - `{:ok}` - If the command was sent successfully.
      - `{:error, :unknown_command}` - If the command was not recognised.
    """
    def sendto(_sentant_id, command_and_parameters) do
      sentant_name = R2Map.get(command_and_parameters, :name, "")
      keys = R2Map.get(command_and_parameters, :keys, %{})
      decryption_key = R2Map.get(keys, :decryption_key, "")
      encryption_key = R2Map.get(keys, :encryption_key, "")

      parameters = R2Map.get(command_and_parameters, :parameters, %{})
      data = parameters |> R2Map.delete(:result)
      case R2Map.get(command_and_parameters, :command) do
        "store" ->
          # Encrypt and store data in the database
          encrypt_and_store(sentant_name, data, encryption_key, decryption_key)
        "retrieve" ->
          # Retrieve and decrypt data from the database
          retrieve_and_decrypt(sentant_name, decryption_key)
        "delete" ->
            # Delete an entry from the database
            delete(sentant_name, decryption_key)
        _ ->
          {:error, :command}
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Private Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp encrypt_and_store("", _data, _encryption_key, _decryption_key), do: {:error, :name}
    defp encrypt_and_store(_name, _data, "", _decryption_key), do: {:error, :encryption_key}
    defp encrypt_and_store(name, data, encryption_key, ""), do: encrypt_and_store(name, data, encryption_key, encryption_key)
    defp encrypt_and_store(name, data, encryption_key, decryption_key) do
      # Encrypt the data and store it in the database
      do_write = fn name, data ->
        Mnesia.write({:backup, name, data})
      end
      case retrieve_and_decrypt(name, decryption_key) do
        {:ok, _} ->
          case Jason.encode(data) do
            {:ok, data_string} ->
              encrypted_data = Crypto.encrypt(data_string, encryption_key)
              Mnesia.transaction(do_write, [name, Base.encode64(encrypted_data)])
              :ok
            _ -> {:error, :data}
          end
          :ok
        {:error, :name} ->
          case Jason.encode(data) do
            {:ok, data_string} ->
              encrypted_data = Crypto.encrypt(data_string, encryption_key)
              Mnesia.transaction(do_write, [name, Base.encode64(encrypted_data)])
              :ok
            _ -> {:error, :data}
          end
        _ -> {:error, :decryption}
      end
    end

    defp retrieve_and_decrypt("", _decryption_key), do: {:error, :name}
    defp retrieve_and_decrypt(_name, ""), do: {:error, :decryption_key}
    defp retrieve_and_decrypt(name, decryption_key) do
      # Retrieve the data from the database and decrypt it
      do_read = fn name ->
        Mnesia.read({:backup, name})
      end

      case Mnesia.transaction(do_read, [name]) do
        {:atomic, [{:backup, ^name, encrypted_data}]} ->
          try do
            data_string = Crypto.decrypt(Base.decode64!(encrypted_data), decryption_key)
            case Jason.decode(data_string) do
              {:ok, decrypted_data} ->
                {:ok, decrypted_data}
              _ -> {:error, :decryption}
            end
          rescue
            _ -> {:error, :decryption}
          end
        _ ->
          {:error, :name}
      end
    end

    defp delete("", _decryption_key), do: {:error, :name}
    defp delete(_name, ""), do: {:error, :decryption_key}
    defp delete(name, decryption_key) do
      # Delete the data from the database if it descrypts correctly
      do_delete = fn name ->
        Mnesia.delete({:backup, name})
      end
      case retrieve_and_decrypt(name, decryption_key) do
        {:ok, _} ->
          Mnesia.transaction(do_delete, [name])
          :ok
        _ -> {:error, :decryption}
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------
  end
