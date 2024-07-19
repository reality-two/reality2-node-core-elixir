defmodule AiReality2Rustdemo.Main do
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

    @doc false
    def start_link(name), do: GenServer.start_link(__MODULE__, %{}, name: name)

    @doc false
    def init(state), do: {:ok, state}

    @doc false
    def create(_sentant_id), do: {:ok}

    @doc false
    def delete(_sentant_id), do: {:ok}

    @doc false
    def whereis(_sentant_id), do: self()

    @doc false
    def sendto(_sentant_id, command_and_parameters) do
      IO.puts("Received command: #{inspect(command_and_parameters)}")
      {:ok}
    end

  end
