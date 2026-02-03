defmodule Reality2Transnet.Transports.TransportSelectionTest do
  use ExUnit.Case, async: true

  alias Reality2Transnet.Transport

  describe "Transport.fits?/2" do
    test "binary payload within limit returns true" do
      defmodule SmallTransport do
        @behaviour Reality2Transnet.Transport
        def transport_type, do: :test
        def available?, do: true
        def max_payload_size, do: 100
        def capabilities, do: %{broadcast: true, unicast: false, bidirectional: false, reliable: false, max_payload: 100}
        def broadcast(_), do: :ok
        def send_to(_, _), do: {:error, :not_supported}
        def handle_incoming(_), do: :ok
      end

      assert Transport.fits?(SmallTransport, <<1, 2, 3>>)
      assert Transport.fits?(SmallTransport, :binary.copy(<<0>>, 100))
      refute Transport.fits?(SmallTransport, :binary.copy(<<0>>, 101))
    end

    test "map payload checks JSON-encoded size" do
      defmodule MapTransport do
        @behaviour Reality2Transnet.Transport
        def transport_type, do: :test_map
        def available?, do: true
        def max_payload_size, do: 50
        def capabilities, do: %{broadcast: true, unicast: false, bidirectional: false, reliable: false, max_payload: 50}
        def broadcast(_), do: :ok
        def send_to(_, _), do: {:error, :not_supported}
        def handle_incoming(_), do: :ok
      end

      assert Transport.fits?(MapTransport, %{a: 1})
      # Large map should not fit
      large_map = %{data: String.duplicate("x", 100)}
      refute Transport.fits?(MapTransport, large_map)
    end

    test "non-binary non-map returns false" do
      defmodule AnyTransport do
        @behaviour Reality2Transnet.Transport
        def transport_type, do: :test_any
        def available?, do: true
        def max_payload_size, do: 1000
        def capabilities, do: %{broadcast: true, unicast: false, bidirectional: false, reliable: false, max_payload: 1000}
        def broadcast(_), do: :ok
        def send_to(_, _), do: {:error, :not_supported}
        def handle_incoming(_), do: :ok
      end

      refute Transport.fits?(AnyTransport, 12345)
      refute Transport.fits?(AnyTransport, :atom)
    end
  end

  describe "Transport.select_best/3" do
    defmodule WiFiTransportMock do
      @behaviour Reality2Transnet.Transport
      def transport_type, do: :wifi_hotspot
      def available?, do: true
      def max_payload_size, do: 1_000_000
      def capabilities, do: %{broadcast: true, unicast: true, bidirectional: true, reliable: true, max_payload: 1_000_000}
      def broadcast(_), do: :ok
      def send_to(_, _), do: :ok
      def handle_incoming(_), do: :ok
    end

    defmodule LoRaTransportMock do
      @behaviour Reality2Transnet.Transport
      def transport_type, do: :lora
      def available?, do: true
      def max_payload_size, do: 200
      def capabilities, do: %{broadcast: true, unicast: false, bidirectional: true, reliable: false, max_payload: 200}
      def broadcast(_), do: :ok
      def send_to(_, _), do: {:error, :not_supported}
      def handle_incoming(_), do: :ok
    end

    defmodule BLETransportMock do
      @behaviour Reality2Transnet.Transport
      def transport_type, do: :ble
      def available?, do: true
      def max_payload_size, do: 18
      def capabilities, do: %{broadcast: true, unicast: false, bidirectional: false, reliable: false, max_payload: 18}
      def broadcast(_), do: :ok
      def send_to(_, _), do: {:error, :not_supported}
      def handle_incoming(_), do: :ok
    end

    defmodule UnavailableTransport do
      @behaviour Reality2Transnet.Transport
      def transport_type, do: :unavailable
      def available?, do: false
      def max_payload_size, do: 1_000_000
      def capabilities, do: %{broadcast: true, unicast: true, bidirectional: true, reliable: true, max_payload: 1_000_000}
      def broadcast(_), do: :ok
      def send_to(_, _), do: :ok
      def handle_incoming(_), do: :ok
    end

    test "selects WiFi for large payloads (priority order)" do
      transports = [WiFiTransportMock, LoRaTransportMock, BLETransportMock]
      assert {:ok, WiFiTransportMock} = Transport.select_best(transports, 500)
    end

    test "selects LoRa when WiFi not in list" do
      transports = [LoRaTransportMock, BLETransportMock]
      assert {:ok, LoRaTransportMock} = Transport.select_best(transports, 100)
    end

    test "selects BLE for tiny payloads when only option" do
      transports = [BLETransportMock]
      assert {:ok, BLETransportMock} = Transport.select_best(transports, 10)
    end

    test "returns error when payload too large for all transports" do
      transports = [LoRaTransportMock, BLETransportMock]
      assert {:error, :no_suitable_transport} = Transport.select_best(transports, 500)
    end

    test "filters out unavailable transports" do
      transports = [UnavailableTransport, BLETransportMock]
      assert {:ok, BLETransportMock} = Transport.select_best(transports, 10)
    end

    test "returns error when all transports unavailable" do
      transports = [UnavailableTransport]
      assert {:error, :no_suitable_transport} = Transport.select_best(transports, 10)
    end

    test "returns error for empty transport list" do
      assert {:error, :no_suitable_transport} = Transport.select_best([], 10)
    end

    test "prefer option selects specified transport" do
      transports = [WiFiTransportMock, LoRaTransportMock, BLETransportMock]
      assert {:ok, LoRaTransportMock} = Transport.select_best(transports, 100, prefer: :lora)
    end

    test "prefer falls back to priority when preferred not available" do
      transports = [WiFiTransportMock, BLETransportMock]
      assert {:ok, WiFiTransportMock} = Transport.select_best(transports, 10, prefer: :lora)
    end

    test "require_reliable filters to reliable transports" do
      transports = [WiFiTransportMock, LoRaTransportMock, BLETransportMock]
      assert {:ok, WiFiTransportMock} = Transport.select_best(transports, 100, require_reliable: true)
    end

    test "require_reliable with no reliable transports returns error" do
      transports = [LoRaTransportMock, BLETransportMock]
      assert {:error, :no_suitable_transport} = Transport.select_best(transports, 10, require_reliable: true)
    end

    test "priority order: wifi > internet > lora > ble" do
      # WiFi should be preferred
      transports = [BLETransportMock, LoRaTransportMock, WiFiTransportMock]
      assert {:ok, WiFiTransportMock} = Transport.select_best(transports, 10)
    end
  end
end
