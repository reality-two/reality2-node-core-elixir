defmodule Reality2.Plugins do
# *********************************************************************************************************************************************
@moduledoc false
# Module for creating and managing Plugins on a Sentant.
#
# **Author**
# - Dr. Roy C. Davies
# - [roycdavies.github.io](https://roycdavies.github.io/)
# *********************************************************************************************************************************************

    @doc false
    use DynamicSupervisor
    alias Reality2.Types
    alias Reality2.Helpers.R2Process, as: R2Process

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Supervisor Callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def start_link({_name, id, _plugin_map} = init_arg) do
      DynamicSupervisor.start_link(__MODULE__, init_arg)
      |> R2Process.register(id <> "|plugins")
    end

    @impl true
    def init(init_arg) do
      DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [init_arg])
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------



    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Public Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------------------------------------------------------------------------------------
    @spec create(Types.uuid(), Types.automation()) ::
      {:ok}
      | {:error, :definition}
    @doc """
    Create a new Plugin on the Sentant, returning {:ok} or an appropriate error.

    **Parameters**
    - `definition` - A map containing the definition of the Plugin.
    """
    # -----------------------------------------------------------------------------------------------------------------------------------------
    def create(id, plugin_map) do
      case R2Process.whereis(id <> "|plugins") do
        nil->
          {:error, :existence}
        pid ->
          case DynamicSupervisor.start_child(pid, Reality2.Plugin.child_spec(plugin_map)) do
            # New child proces started
            {:ok, _pid} ->
              {:ok}
            # Child process already existing, so just send a reinitialise message to the plugin GenServer
            {:error, {:already_started, existing_pid}} ->
              GenServer.cast(existing_pid, {:reinit, plugin_map})
              {:ok}
            # Error starting child for some other reason.
            {:error, reason} ->
              if (Application.get_env(:reality2, :build_env) != :prod) do
                IO.puts("Error starting child: #{inspect(reason)}")
              end
              {:error, reason}
          end
      end
    end
    # -----------------------------------------------------------------------------------------------------------------------------------------

  end
