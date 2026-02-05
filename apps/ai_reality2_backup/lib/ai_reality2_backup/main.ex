defmodule AiReality2Backup.Main do
  @behaviour Reality2.Plugin.Main

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
  require Logger
  alias Reality2.Helpers.R2Map, as: R2Map
  alias Reality2.Helpers.Crypto, as: Crypto
  alias :mnesia, as: Mnesia

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(name), do: GenServer.start_link(__MODULE__, %{}, name: name)

  @doc false
  @impl true
  def init(state) do
    with :stopped <- Mnesia.stop(),
         :ok <- create_schema(),
         :ok <- Mnesia.start(),
         :ok <- create_table(:backup, attributes: [:name, :data], disc_only_copies: [node()]),
         :ok <- create_table(:data, attributes: [:id, :data], disc_only_copies: [node()]) do
      Logger.info("[ai.reality2.backup] started successfully")
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

      error ->
        error
    end
  end

  defp create_table(table_name, attributes) do
    case Mnesia.create_table(table_name, attributes) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, _}} ->
        :ok

      error ->
        error
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Does nothing in this module as there are no child processes.

  - Parameters
    - `sentant_id` - ignored in this implementation.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def create(_sentant_id, _details \\ %{}) do
    {:ok}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Does nothing in this module as there are no child processes.

  - Parameters
    - `sentant_id` - ignored in this implementation.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def delete(_sentant_id) do
    {:ok}
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Return the process id that can be used for subsequent communications.

  In this implementation, this just refers to this module.

  - Parameters
    - `id` - The id of the Sentant for which process id is being returned.
  """
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @impl true
  def whereis(_sentant_id) do
    self()
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc """
  Do things with the database.

  - Parameters
    - `id` - The id of the Sentant for which the command is being sent (ignored here)
    - `command` - A map containing the command and parameters to be sent.

  - Returns
    - `{:ok}` - If the command was sent successfully.
    - `{:error, :unknown_command}` - If the command was not recognised.
  """
  @impl true
  def sendto(_sentant_id, command_and_parameters) do
    sentant_name = R2Map.get(command_and_parameters, :name, "")

    # Legacy key support for migration - if provided, use old TrustGroup key
    keys = R2Map.get(command_and_parameters, :keys, %{})
    old_trust_group_key = R2Map.get(keys, :old_trust_group_key, nil)

    parameters = R2Map.get(command_and_parameters, :parameters, %{})
    data = parameters |> R2Map.delete(:result)

    case R2Map.get(command_and_parameters, :command) do
      "store" ->
        # Encrypt with current TrustGroup key and store
        encrypt_and_store(sentant_name, data)

      "retrieve" ->
        # Retrieve and decrypt with current TrustGroup key
        retrieve_and_decrypt(sentant_name)

      "retrieve_migrate" ->
        # Retrieve using old TrustGroup key, re-encrypt with current, and store
        retrieve_and_migrate(sentant_name, old_trust_group_key)

      "delete" ->
        # Delete an entry from the database
        delete_entry(sentant_name)

      _ ->
        {:error, :command}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions - All encryption now uses TrustGroup-derived keys
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # Store data encrypted with the current TrustGroup key
  defp encrypt_and_store("", _data), do: {:error, :name}

  defp encrypt_and_store(name, data) do
    purpose = "backup:#{name}"

    case Jason.encode(data) do
      {:ok, data_string} ->
        case Crypto.encrypt(data_string, purpose) do
          {:ok, encrypted_data} ->
            do_write = fn ->
              Mnesia.write({:backup, name, Base.encode64(encrypted_data)})
            end

            case Mnesia.transaction(do_write) do
              {:atomic, :ok} -> :ok
              _ -> {:error, :storage}
            end

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :data}
    end
  end

  # Retrieve and decrypt data using current TrustGroup key
  defp retrieve_and_decrypt(""), do: {:error, :name}

  defp retrieve_and_decrypt(name) do
    purpose = "backup:#{name}"

    do_read = fn ->
      Mnesia.read({:backup, name})
    end

    case Mnesia.transaction(do_read) do
      {:atomic, [{:backup, ^name, encrypted_data_b64}]} ->
        try do
          encrypted_data = Base.decode64!(encrypted_data_b64)

          case Crypto.decrypt(encrypted_data, purpose) do
            {:ok, data_string} ->
              case Jason.decode(data_string) do
                {:ok, decrypted_data} ->
                  {:ok, decrypted_data}

                _ ->
                  {:error, :json_decode}
              end

            {:error, reason} ->
              {:error, reason}
          end
        rescue
          _ -> {:error, :decryption}
        end

      {:atomic, []} ->
        {:error, :not_found}

      _ ->
        {:error, :storage}
    end
  end

  # Retrieve data encrypted with old TrustGroup, re-encrypt with current TrustGroup, and store
  defp retrieve_and_migrate("", _old_trust_group_key), do: {:error, :name}
  defp retrieve_and_migrate(_name, nil), do: {:error, :old_trust_group_key}

  defp retrieve_and_migrate(name, old_trust_group_key) do
    purpose = "backup:#{name}"

    do_read = fn ->
      Mnesia.read({:backup, name})
    end

    case Mnesia.transaction(do_read) do
      {:atomic, [{:backup, ^name, encrypted_data_b64}]} ->
        try do
          encrypted_data = Base.decode64!(encrypted_data_b64)

          # Migrate: decrypt with old key, re-encrypt with current TrustGroup key
          case Crypto.migrate_from_old_trust_group(encrypted_data, purpose, old_trust_group_key) do
            {:ok, re_encrypted_data} ->
              # Store the re-encrypted data
              do_write = fn ->
                Mnesia.write({:backup, name, Base.encode64(re_encrypted_data)})
              end

              case Mnesia.transaction(do_write) do
                {:atomic, :ok} ->
                  # Now retrieve with current key to return the data
                  retrieve_and_decrypt(name)

                _ ->
                  {:error, :storage}
              end

            {:error, reason} ->
              {:error, reason}
          end
        rescue
          _ -> {:error, :migration}
        end

      {:atomic, []} ->
        {:error, :not_found}

      _ ->
        {:error, :storage}
    end
  end

  # Delete an entry - only requires verifying we can decrypt it first
  defp delete_entry(""), do: {:error, :name}

  defp delete_entry(name) do
    # Verify we can decrypt (proves we own it) before deleting
    case retrieve_and_decrypt(name) do
      {:ok, _} ->
        do_delete = fn ->
          Mnesia.delete({:backup, name})
        end

        case Mnesia.transaction(do_delete) do
          {:atomic, :ok} -> :ok
          _ -> {:error, :storage}
        end

      {:error, :not_found} ->
        # Already gone, that's fine
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  # -----------------------------------------------------------------------------------------------------------------------------------------
end
