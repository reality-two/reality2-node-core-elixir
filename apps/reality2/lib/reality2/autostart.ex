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

  # Check if the core system is ready
  # Note: Plugins are started as supervised children within the main app,
  # not as separate OTP applications, so we don't check for them here.
  defp system_ready? do
    http_ready = Process.whereis(Reality2.HTTPClient) != nil
    sentants_ready = PartitionSupervisor.which_children(Reality2.Sentants) != []
    metadata_ready = Process.whereis(:SentantNames) != nil and Process.whereis(:SentantIDs) != nil

    Logger.debug("[Autostart] Ready check: http=#{http_ready}, sentants=#{sentants_ready}, metadata=#{metadata_ready}")

    http_ready and sentants_ready and metadata_ready
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
    Logger.info("[Autostart] Checking directory: #{autostart}")
    Logger.info("[Autostart] Current working directory: #{File.cwd!()}")

    if File.dir?(autostart) do
      Logger.info("[Autostart] Loading from autostart directory: #{autostart}")

      files = File.ls!(autostart) |> Enum.sort()
      Logger.info("[Autostart] Found #{length(files)} files: #{inspect(files)}")

      Enum.each(files, fn file ->
        load_file(file)
        # Small delay between files to avoid race conditions
        Process.sleep(100)
      end)
    else
      Logger.warning("[Autostart] Autostart directory not found: #{autostart}")
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Try to the load the file either as a swarm or sentant / bee
  # ---------------------------------------------------------------------------------------------------------------------------------------------
  defp load_file(file_name) do
    full_path = Path.join(autostart_dir(), file_name)
    Logger.debug("[Autostart] Attempting to load: #{full_path}")

    if File.dir?(full_path) do
      Logger.debug("[Autostart] Skipping directory: #{file_name}")
      :ok
    else
      case File.read(full_path) do
        {:ok, content} ->
          Logger.debug("[Autostart] Read file #{file_name}, #{byte_size(content)} bytes")
          case Reality2.Swarm.create(content, true, true) do
            {:ok, swarm} ->
              Logger.info("[Autostart] Swarm file loaded: #{file_name} -> #{inspect(swarm)}")

            swarm_error ->
              Logger.debug("[Autostart] Not a swarm (#{inspect(swarm_error)}), trying as sentant...")
              case Reality2.Sentants.create(content, true, true) do
                {:ok, id} ->
                  Logger.info("[Autostart] Sentant file loaded: #{file_name} -> #{id}")

                sentant_error ->
                  Logger.warning("[Autostart] Error loading file #{full_path}: swarm_error=#{inspect(swarm_error)}, sentant_error=#{inspect(sentant_error)}")
              end
          end

        {:error, reason} ->
          Logger.error("[Autostart] Error reading file #{full_path}: #{reason}")
      end
    end
  end

  # ---------------------------------------------------------------------------------------------------------------------------------------------
end
