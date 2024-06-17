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
    alias :mnesia, as: Mnesia
    alias :crypto, as: Crypto

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Supervisor Callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def start_link(name),                              do: GenServer.start_link(__MODULE__, %{}, name: name)

    @doc false
    def init(state) do
      Mnesia.stop()
      Mnesia.create_schema([node()])
      Mnesia.start()
      Mnesia.create_table(:backup, [attributes: [:name, :data], disc_only_copies: [node()]])
      Mnesia.add_table_index(:backup, :name)
      {:ok, state}
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
      parameters = R2Map.get(command_and_parameters, :parameters, %{})
      data = parameters |> R2Map.delete(:name) |> R2Map.delete(:encryption_key) |> R2Map.delete(:result) |> R2Map.delete(:decryption_key)
      case R2Map.get(command_and_parameters, :command) do
        "store" ->
          # Encrypt and store data in the database
          encrypt_and_store(R2Map.get(parameters, :name, ""), data, R2Map.get(parameters, :encryption_key, ""))
        "retrieve" ->
          # Retrieve and decrypt data from the database
          retrieve_and_decrypt(R2Map.get(parameters, :name, ""), R2Map.get(parameters, :decryption_key, ""))
        "delete" ->
            # Delete an entry from the database
            delete(R2Map.get(parameters, :name, ""), R2Map.get(parameters, :decryption_key, ""))
        _ ->
          {:error, :command}
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Private Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------
    defp encrypt_and_store("", _data, _encryption_key), do: {:error, :name}
    defp encrypt_and_store(_name, _data, ""), do: {:error, :encryption_key}
    defp encrypt_and_store(name, data, encryption_key) do
      # Encrypt the data and store it in the database
      do_write = fn name, data ->
        Mnesia.write({:backup, name, data})
      end
      case Jason.encode(data) do
        {:ok, data_string} ->
          encrypted_data = encrypt(data_string, encryption_key)
          result = Mnesia.transaction(do_write, [name, encrypted_data])
          :ok
        _ -> {:error, :data}
      end
    end

    defp retrieve_and_decrypt("", _decryption_key), do: {:error, :name}
    defp retrieve_and_decrypt(_name, ""), do: {:error, :decryption_key}
    defp retrieve_and_decrypt(name, decryption_key) do
      # Retrieve the data from the database and decrypt it
      do_read = fn name ->
        Mnesia.read({:backup, name})
      end
      result = Mnesia.transaction(do_read, [name])
      case result do
        {:atomic, [{:backup, name, encrypted_data}]} ->
          try do
            data_string = decrypt(encrypted_data, decryption_key)
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
          result = Mnesia.transaction(do_delete, [name])
          :ok
        _ -> {:error, :decryption}
      end
    end

    defp encrypt(data, encoded_encryption_key) do
      key = Base.decode64!(encoded_encryption_key)
      iv = Crypto.strong_rand_bytes(12)
      {ciphertext, tag} = Crypto.crypto_one_time_aead(:aes_gcm, key, iv, data, "", true)

      # Combine IV, tag, and ciphertext into a blob
      iv <> tag <> ciphertext
    end

    defp decrypt(data, encoded_decryption_key) do
      key = Base.decode64!(encoded_decryption_key)
      <<iv::binary-size(12), tag::binary-size(16), ciphertext::binary>> = data
      Crypto.crypto_one_time_aead(:aes_gcm, key, iv, ciphertext, "", tag, false)
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------
  end
