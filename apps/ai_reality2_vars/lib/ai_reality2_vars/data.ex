defmodule AiReality2Vars.Data do
  # *******************************************************************************************************************************************
  @moduledoc """
    Manage key / value pairs for Sentants.

    In this implementation, these are kept in memory using the state parameter of a GenServer, however, this could be a database or other persistent storage.

    The GenServer for each Sentant is supervised by the `AiReality2Vars.Main` DynamicSupervisor.

    For your own Reality2 Node Apps, you should follow this pattern, ie create a `GenServer` for each App, and define the `Main` module as specified.
  """
  # *******************************************************************************************************************************************

    @doc false
    use GenServer, restart: :transient
    alias Reality2.Helpers.R2Map, as: R2Map

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # GenServer callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def start_link(_, _),                                 do: GenServer.start_link(__MODULE__, %{})

    @doc false
    def init(state),                                      do: {:ok, state}
    # -----------------------------------------------------------------------------------------------------------------------------------------


    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Public Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------------------------------------------------------------------------------------
    # GenServer callbacks
    # -----------------------------------------------------------------------------------------------------------------------------------------
    @doc false
    def handle_call(%{command: "get", parameters: %{key: key}}, _from, state),                        do: {:reply, {:ok, %{key => R2Map.get(state, key, nil)}}, state}
    def handle_call(%{command: "get", parameters: %{"key" => key}}, _from, state),                    do: {:reply, {:ok, %{key => R2Map.get(state, key, nil)}}, state}
    def handle_call(%{command: "all"}, _from, state),                                                 do: {:reply, {:ok, state}, state}
    def handle_call(_, _from, state),                                                                 do: {:reply, {:error, :unknown_command}, state}


    @doc false
    def handle_cast(%{command: "set", parameters: %{key: key, value: value}}, state),                 do: {:noreply, R2Map.put(state, key, value)}
    def handle_cast(%{command: "set", parameters: %{"key" => key, "value" => value}}, state),         do: {:noreply, R2Map.put(state, key, value)}
    def handle_cast(%{command: "delete", parameters: %{key: key}}, state),                            do: {:noreply, R2Map.delete(state, key)}
    def handle_cast(%{command: "delete", parameters: %{"key" => key}}, state),                        do: {:noreply, R2Map.delete(state, key)}
    def handle_cast(%{command: "clear"}, _state),                                                     do: {:noreply, %{}}
    def handle_cast(_, state),                                                                        do: {:noreply, state}
    # -----------------------------------------------------------------------------------------------------------------------------------------


    # -----------------------------------------------------------------------------------------------------------------------------------------
    # Private Functions
    # -----------------------------------------------------------------------------------------------------------------------------------------

    # -----------------------------------------------------------------------------------------------------------------------------------------
  end
