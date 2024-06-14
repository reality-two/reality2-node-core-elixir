defmodule AiReality2Backup.Main do
  # *******************************************************************************************************************************************
  @moduledoc """
    Module for managing the main supervisor tree for the `AiReality2Backup` App.

    In this instance, the main supervisor is a DynamicSupervisor, which is used to manage the database storage for Sentants.
    Presently, we are using mnesia as the database due to its general availability.

    In order to minimise side effects of a database operation crashing and causing problems for the rest of the system, we use a
    process for each Sentant.  This way, if one Sentant crashes, it does not affect the others.

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """
  # *******************************************************************************************************************************************
    @doc false
    use GenServer, restart: :transient
    alias Reality2.Helpers.R2Process, as: R2Process
    alias Reality2.Helpers.R2Map, as: R2Map

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Supervisor Callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def start_link(name),                              do: GenServer.start_link(__MODULE__, %{}, name: name)

    @doc false
    def init(state),                                   do: {:ok, state}
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
      IO.puts("Received command: #{inspect(command_and_parameters)}")
      parameters = R2Map.get(command_and_parameters, :parameters, %{})
      case R2Map.get(command_and_parameters, :command) do
        "store" ->
          # Encrypt and store data in the database
          encrypt_and_store(R2Map.get(parameters, :name, ""), R2Map.get(parameters, :data, %{}), R2Map.get(parameters, :encryption_key, ""))
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
    defp encrypt_and_store(_name, _data, _encryption_key) do
      # Encrypt the data and store it in the database
      IO.puts("Encrypted and stored data in the database")
      :ok
    end

    defp retrieve_and_decrypt("", _decryption_key), do: {:error, :name}
    defp retrieve_and_decrypt(_name, ""), do: {:error, :decryption_key}
    defp retrieve_and_decrypt(_name, _decryption_key) do
      # Retrieve the data from the database and decrypt it
      IO.puts("Retrieved data from the database")
      {:ok, %{}}
    end

    defp delete("", _decryption_key), do: {:error, :name}
    defp delete(_name, ""), do: {:error, :decryption_key}
    defp delete(_name, _decryption_key) do
      # Delete the data from the database if it descrypts correctly
      IO.puts("Deleted data from the database")
      :ok
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------
  end
