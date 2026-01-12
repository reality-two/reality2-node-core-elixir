defmodule Reality2.Autostart do
  # *******************************************************************************************************************************************
  @moduledoc false
  # Check the Autostart directory in the root folder, and if there are any swarms or sentants, load them.
  #
  # **Author**
  # - Dr. Roy C. Davies
  # - [roycdavies.github.io](https://roycdavies.github.io/)
  # *******************************************************************************************************************************************

  @doc false
  use GenServer
  require Logger

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  @doc false
  def start_link(_name) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc false
  @impl true
  def init(state) do
    # Wait until everything is up and running.
    # Check if there is a folder called autostart.
    # Get the contents of the folder.
    # For each file, load the file either as a Swarm or Sentant.

    Process.send_after(self(), :check_ready, 5000)
    {:ok, state}
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Public Functions
  # ---------------------------------------------------------------------------------------------------------------------------------------------

  @impl true
  def handle_info(:check_ready, state) do
    if system_ready?() do
      Logger.info("System is ready. Loading autostart files...")
      load_autostart_files()
    else
      Logger.debug("System not ready yet, retrying...")
      Process.send_after(self(), :check_ready, 1000)
    end

    {:noreply, state}
  end

  # Check if the core system and all plugins are ready
  defp system_ready? do
    http_ready = Process.whereis(Reality2.HTTPClient) != nil
    sentants_ready = PartitionSupervisor.which_children(Reality2.Sentants) != []
    metadata_ready = Process.whereis(:SentantNames) != nil and Process.whereis(:SentantIDs) != nil

    http_ready and sentants_ready and metadata_ready and plugins_ready?()
  end

  # Check if all configured plugin applications have started
  defp plugins_ready? do
    started_apps = Application.started_applications()
                   |> Enum.map(fn {app, _, _} -> app end)

    plugin_apps = get_plugin_app_names()

    Enum.all?(plugin_apps, fn app -> app in started_apps end)
  end

  # Convert plugin names from env var to application atom names
  # e.g., "ai.reality2.vars" -> :ai_reality2_vars
  defp get_plugin_app_names do
    case System.get_env("PLUGINS") do
      nil -> []
      "" -> []
      plugins_str ->
        plugins_str
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&plugin_to_app_name/1)
    end
  end

  defp plugin_to_app_name(plugin_name) do
    # Convert "ai.reality2.vars" to :ai_reality2_vars
    plugin_name
    |> String.replace(".", "_")
    |> String.to_atom()
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Get the Autostart directory, if there is one.
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp autostart_dir do
    case System.get_env("AUTOSTART") do
      nil ->
        Path.join(File.cwd!(), "/autostart/")

      autostart ->
        Path.join(autostart, "/autostart/")
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Load the files in the the autostart directory.
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp load_autostart_files do
    autostart = autostart_dir()

    if File.dir?(autostart) do
      Logger.info("Loading from autostart directory: #{autostart}")

      files = File.ls!(autostart) |> Enum.sort()

      Enum.each(files, fn file ->
        load_file(file)
        # Small delay between files to avoid race conditions
        Process.sleep(100)
      end)
    else
      Logger.debug("Autostart directory not found")
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Try to the load the file either as a swarm or sentant / bee
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp load_file(file_name) do
    full_path = Path.join(autostart_dir(), file_name)

    if File.dir?(full_path) do
      :ok
    else
      case File.read(full_path) do
        {:ok, content} ->
          case Reality2.Swarm.create(content, true, true) do
            {:ok, _} ->
              Logger.info("Swarm file loaded: #{file_name}")

            _ ->
              case Reality2.Sentants.create(content, true, true) do
                {:ok, _} ->
                  Logger.info("Sentant file loaded: #{file_name}")

                _ ->
                  Logger.warning("Error loading file: #{full_path}")
              end
          end

        {:error, reason} ->
          Logger.error("Error reading file #{full_path}: #{reason}")
      end
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------
end
