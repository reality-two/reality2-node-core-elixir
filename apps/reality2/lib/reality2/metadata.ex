defmodule Reality2.Metadata do
# *******************************************************************************************************************************************
@moduledoc false
# Manage key / value pairs.  This may be implemented however desired, but in this case, it is simply using a Map inside a GenServer.
# Put this in your supervisor tree.
#
# **Author**
# - Dr. Roy C. Davies
# - [roycdavies.github.io](https://roycdavies.github.io/)
# *******************************************************************************************************************************************

  @doc false
  use GenServer
  alias Reality2.Helpers.R2Process, as: R2Process
  alias Reality2.Helpers.R2Map, as: R2Map

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(name)                                 do
    GenServer.start_link(__MODULE__, %{}, name: name) |> R2Process.register(name)
    # IO.puts("Metadata: Starting Metadata GenServer: " <> inspect(result) <> " : " <> inspect(name))
    # result2 = R2Process.register(result, name)
    # IO.puts("Metadata: Registering Metadata GenServer: " <> inspect(result2))
    # result |> R2Process.register(name)
  end

  @doc false
  def init(state),                                      do: {:ok, state}
  # -----------------------------------------------------------------------------------------------------------------------------------------


  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Set a key / value pair
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec set(String.t() | atom() | pid(), String.t() | atom() | pid(), any()) :: any()
  def set(name, key, value) when is_binary(name),       do: check_existance(String.to_atom(name), fn () -> GenServer.call(String.to_atom(name), {:set, key, value}) end)
  def set(name, key, value) when is_atom(name),         do: check_existance(name, fn () -> GenServer.call(name, {:set, key, value}) end)
  def set(pid, key, value) when is_pid(pid),            do: GenServer.call(pid, {:set, key, value})
  def set(nil, _, _),                                   do: nil
  def set(_, nil, _),                                   do: nil
  def set(_, _, _),                                     do: nil
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Get a value
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec get(String.t() | atom() | pid(), String.t() | atom() | pid()) :: any()
  def get(name, key) when is_binary(name),              do: check_existance(String.to_atom(name), fn () -> GenServer.call(String.to_atom(name), {:get, key}) end)
  def get(name, key) when is_atom(name),                do: check_existance(name, fn () -> GenServer.call(name, {:get, key}) end)
  def get(pid, key) when is_pid(pid),                   do: GenServer.call(pid, {:get, key})
  def get(nil, _),                                      do: nil
  def get(_, nil),                                      do: nil
  def get(_, _),                                        do: nil
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Delete a key / value pair
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec delete(String.t() | atom() | pid(), String.t() | atom() | pid()) :: any()
  def delete(name, key) when is_binary(name),           do: check_existance(String.to_atom(name), fn () -> GenServer.call(String.to_atom(name), {:delete, key}) end)
  def delete(name, key) when is_atom(name),             do: check_existance(name, fn () -> GenServer.call(name, {:delete, key}) end)
  def delete(pid, key) when is_pid(pid),                do: GenServer.call(pid, {:delete, key})
  def delete(nil, _),                                   do: nil
  def delete(_, nil),                                   do: nil
  def delete(_, _),                                     do: nil
  # -----------------------------------------------------------------------------------------------------------------------------------------

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Get all key / value pairs
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @spec all(String.t() | atom() | pid()) :: any()
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def all(name) when is_binary(name),                   do: check_existance(String.to_atom(name), fn () -> GenServer.call(String.to_atom(name), {:all}) end, [])
  def all(name) when is_atom(name),                     do: check_existance(name, fn () -> GenServer.call(name, {:all}) end, [])
  def all(pid) when is_pid(pid),                        do: GenServer.call(pid, {:all})
  def all(_),                                           do: []
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  def handle_call({:set, key, value}, _from, state),    do: {:reply, :ok, R2Map.put(state, key, value)}
  def handle_call({:delete, key}, _from, state),        do: {:reply, :ok, R2Map.delete(state, key)}
  def handle_call({:get, key}, _from, state),           do: {:reply, R2Map.get(state, key, nil), state}
  def handle_call({:all}, _from, state),                do: {:reply, state, state}
  # -----------------------------------------------------------------------------------------------------------------------------------------



  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # -----------------------------------------------------------------------------------------------------------------------------------------
  defp check_existance(name, func, default \\ nil) do
    case Process.whereis(name) do
      nil->
        default
      _pid ->
        func.()
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------

end
