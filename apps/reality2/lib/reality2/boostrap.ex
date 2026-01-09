defmodule Reality2.Bootstrap do
  # *******************************************************************************************************************************************
  @moduledoc """
  Bootstrap module for Reality2 node initialization.

  Persists node configuration to `.node` file in JSON format:

  ```json
  {
    "node_id": "123e4567-e89b-12d3-a456-426614174000",
    "node_name": "R2Node_A3F7"
  }
  ```

  ## Node ID
  - Unique UUID for this node
  - Generated once on first run, then persisted

  ## Node Name
  Priority order:
  1. Environment variable `R2_NODE_NAME` (temporary override, not persisted)
  2. Persisted name from `.node` file
  3. Auto-generated "R2Node_XXXX" (4 random hex chars, then persisted)

  The node name is used in:
  - BLE beacon advertisements
  - WiFi hotspot SSID
  - `/transnet/info` endpoint
  - GATT node info characteristic

  ## SSL Certificates
  On first run, generates self-signed SSL certificates for HTTPS if they don't exist.

  **Author**
  - Dr. Roy C. Davies
  - [roycdavies.github.io](https://roycdavies.github.io/)
  """
  # *******************************************************************************************************************************************
  use GenServer
  require Logger

  @node_file ".node"
  @cert_file "selfsigned.pem"
  @key_file "selfsigned_key.pem"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def put(key, value), do: GenServer.call(__MODULE__, {:put, key, value})
  def get(key, default \\ nil), do: GenServer.call(__MODULE__, {:get, key, default})

  @impl true
  def init(state) do
    node_config = load_or_create_node_config!()

    # Allow env var to override node_name (but don't persist the override)
    node_name = case System.get_env("R2_NODE_NAME") do
      nil -> node_config.node_name
      "" -> node_config.node_name
      env_name -> env_name
    end

    state = state
    |> Map.put(:node_id, node_config.node_id)
    |> Map.put(:node_name, node_name)

    log_version()
    Logger.info("[Bootstrap] Node ID: #{node_config.node_id}")
    Logger.info("[Bootstrap] Node Name: #{node_name}")
    log_ip_addresses()
    ensure_ssl_certificates()

    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state),
    do: {:reply, :ok, Map.put(state, key, value)}

  def handle_call({:get, key, default}, _from, state),
    do: {:reply, Map.get(state, key, default), state}

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # Private Functions
  # ---------------------------------------------------------------------------------------------------------------------------------------------

  defp log_version do
    version = Application.spec(:reality2, :vsn) |> to_string()
    mix_env = Mix.env() |> to_string()

    # BUILD_BRANCH is set by make_runtime when creating releases
    branch_suffix = case System.get_env("BUILD_BRANCH") do
      "develop" -> " (develop)"
      _ -> ""
    end

    Logger.info("**************************************")
    Logger.info("Reality2 Node v#{version}#{branch_suffix}")
    Logger.info("Environment: #{mix_env}")
    Logger.info("**************************************")
  end

  defp load_or_create_node_config! do
    path = Path.join(File.cwd!(), @node_file)

    case File.read(path) do
      {:ok, contents} ->
        parse_node_file(contents, path)

      {:error, :enoent} ->
        create_new_node_config!(path)

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read", path: path
    end
  end

  defp parse_node_file(contents, path) do
    contents = String.trim(contents)

    # Try JSON format first
    case Jason.decode(contents) do
      {:ok, %{"node_id" => node_id} = config} ->
        # Valid JSON config
        node_name = Map.get(config, "node_name") || generate_node_name()

        # If node_name was missing, update the file
        unless Map.has_key?(config, "node_name") do
          save_node_config!(path, node_id, node_name)
        end

        %{node_id: node_id, node_name: node_name}

      _ ->
        # Legacy format (plain UUID) - migrate to JSON
        if String.match?(contents, ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i) do
          Logger.info("[Bootstrap] Migrating legacy .node file to JSON format")
          node_id = contents
          node_name = generate_node_name()
          save_node_config!(path, node_id, node_name)
          %{node_id: node_id, node_name: node_name}
        else
          raise "Invalid .node file format"
        end
    end
  end

  defp create_new_node_config!(path) do
    node_id = UUID.uuid4()
    node_name = generate_node_name()
    save_node_config!(path, node_id, node_name)
    %{node_id: node_id, node_name: node_name}
  end

  defp save_node_config!(path, node_id, node_name) do
    config = %{
      node_id: node_id,
      node_name: node_name
    }

    json = Jason.encode!(config, pretty: true)
    tmp = path <> ".tmp"

    File.write!(tmp, json <> "\n")
    File.rename!(tmp, path)

    # Optional: restrict permissions
    try do
      File.chmod!(path, 0o600)
    rescue
      _ -> :ok
    end

    :ok
  end

  defp generate_node_name do
    # Generate "R2Node_XXXX" where XXXX is 4 random hex chars
    suffix = :crypto.strong_rand_bytes(2)
    |> Base.encode16(case: :upper)

    "R2Node_#{suffix}"
  end

  defp log_ip_addresses do
    case :inet.getifaddrs() do
      {:ok, interfaces} ->
        ip_addresses =
          interfaces
          |> Enum.flat_map(fn {_name, opts} ->
            opts
            |> Keyword.get_values(:addr)
            |> Enum.filter(&ipv4_non_loopback?/1)
            |> Enum.map(&format_ip/1)
          end)
          |> Enum.uniq()

        case ip_addresses do
          [] ->
            Logger.info("[Bootstrap] IP Addresses: none detected")

          ips ->
            Logger.info("[Bootstrap] IP Addresses: #{Enum.join(ips, ", ")}")
        end

      {:error, _reason} ->
        Logger.info("[Bootstrap] IP Addresses: unable to detect")
    end
  end

  defp ipv4_non_loopback?({a, b, c, d}) when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    # Exclude loopback (127.x.x.x) and link-local (169.254.x.x)
    a != 127 and not (a == 169 and b == 254)
  end

  defp ipv4_non_loopback?(_), do: false

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  # ---------------------------------------------------------------------------------------------------------------------------------------------
  # SSL Certificate Functions
  # ---------------------------------------------------------------------------------------------------------------------------------------------

  defp ensure_ssl_certificates do
    cert_dir = get_cert_dir()
    cert_path = Path.join(cert_dir, @cert_file)
    key_path = Path.join(cert_dir, @key_file)

    cond do
      not File.dir?(cert_dir) ->
        Logger.warning("[Bootstrap] Certificate directory not found: #{cert_dir}")

      valid_certificate?(cert_path) and File.exists?(key_path) ->
        Logger.info("[Bootstrap] SSL certificates: valid")

      true ->
        Logger.info("[Bootstrap] SSL certificates: generating new certificates...")
        generate_ssl_certificates(cert_dir, cert_path, key_path)
    end
  end

  defp get_cert_dir do
    # Try to find the cert directory in reality2_web app
    case Application.app_dir(:reality2_web, "priv/cert") do
      path when is_binary(path) -> path
      _ ->
        # Fallback for umbrella development
        Path.join([File.cwd!(), "apps/reality2_web/priv/cert"])
    end
  rescue
    # App not loaded yet - use fallback path
    _ -> Path.join([File.cwd!(), "apps/reality2_web/priv/cert"])
  end

  defp valid_certificate?(cert_path) do
    if File.exists?(cert_path) do
      case File.read(cert_path) do
        {:ok, contents} ->
          # Check it's a valid PEM file without merge conflicts
          String.starts_with?(contents, "-----BEGIN CERTIFICATE-----") and
            not String.contains?(contents, "<<<<<<<")

        _ ->
          false
      end
    else
      false
    end
  end

  defp generate_ssl_certificates(cert_dir, cert_path, key_path) do
    # Ensure directory exists
    File.mkdir_p!(cert_dir)

    # Generate CA certificate
    {_, 0} = System.cmd("openssl", [
      "req", "-x509", "-newkey", "rsa:4096",
      "-keyout", Path.join(cert_dir, "ca.key"),
      "-out", Path.join(cert_dir, "ca.crt"),
      "-days", "365", "-nodes",
      "-subj", "/CN=reality2.local CA"
    ], stderr_to_stdout: true)

    # Generate server key and CSR
    {_, 0} = System.cmd("openssl", [
      "req", "-new", "-newkey", "rsa:4096",
      "-keyout", key_path,
      "-out", Path.join(cert_dir, "server.csr"),
      "-nodes",
      "-subj", "/CN=reality2.local"
    ], stderr_to_stdout: true)

    # Sign server certificate with CA
    {_, 0} = System.cmd("openssl", [
      "x509", "-req",
      "-in", Path.join(cert_dir, "server.csr"),
      "-CA", Path.join(cert_dir, "ca.crt"),
      "-CAkey", Path.join(cert_dir, "ca.key"),
      "-CAcreateserial",
      "-out", cert_path,
      "-days", "365"
    ], stderr_to_stdout: true)

    # Clean up intermediate files
    Enum.each(["ca.key", "ca.crt", "ca.srl", "server.csr"], fn file ->
      File.rm(Path.join(cert_dir, file))
    end)

    Logger.info("[Bootstrap] SSL certificates: generated successfully")
  rescue
    e ->
      Logger.error("[Bootstrap] SSL certificate generation failed: #{inspect(e)}")
  end
end
