defmodule AiReality2Rustdemo.Main do
  @behaviour Reality2.Plugin.Main

  # *******************************************************************************************************************************************
  @moduledoc """
    Module for testing and experimenting with Rust NIFs in Elixir inside a Reality2 Node.

    In this instance, the main supervisor is a DynamicSupervisor, but we don't need a new process for each Sentant.

    **Author**
    - Dr. Roy C. Davies
    - [roycdavies.github.io](https://roycdavies.github.io/)
  """
  # *******************************************************************************************************************************************
  @doc false
  use GenServer, restart: :transient
  alias Reality2.Helpers.R2Map, as: R2Map
  alias Reality2.Helpers.Convert, as: Convert

  # -----------------------------------------------------------------------------------------------------------------------------------------
  # Supervisor Callbacks
  # -----------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(name), do: GenServer.start_link(__MODULE__, %{}, name: name)

  @doc false
  @impl true
  def init(state) do
    IO.puts("[ai.reality2.rustdemo] started successfully.")
    {:ok, state}
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
  Do things with the rust code.

  - Parameters
    - `id` - The id of the Sentant for which the command is being sent (ignored here)
    - `command` - A map containing the command and parameters to be sent.

  - Returns
    - `{:ok, %{/result map/}}` - If the command was sent successfully.
    - `{:error, :unknown_command}` - If the command was not recognised.
  """
  @impl true
  def sendto(_sentant_id, command_and_parameters) do
    command = R2Map.get(command_and_parameters, :command)
    parameters = R2Map.get(command_and_parameters, :parameters)
    value1 = R2Map.get(parameters, "value1") |> Convert.to_float()
    value2 = R2Map.get(parameters, "value2") |> Convert.to_float()

    case command do
      "add" ->
        {:ok, %{answer: AiReality2Rustdemo.Action.add(value1, value2)}}
      "subtract" ->
        {:ok, %{answer: AiReality2Rustdemo.Action.subtract(value1, value2)}}
      _ ->
        {:error, :command}
    end
  end
  # -----------------------------------------------------------------------------------------------------------------------------------------

end
