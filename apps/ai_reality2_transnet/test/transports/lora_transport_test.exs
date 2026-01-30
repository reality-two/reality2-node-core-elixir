defmodule AiReality2Transnet.Transports.LoRaTransportTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias AiReality2Transnet.Transports.LoRaTransport
  alias AiReality2Transnet.TestNodeFactory

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp compressed_id(node_id) do
    :crypto.hash(:sha256, node_id) |> binary_part(0, 4)
  end

  defp compressed_hex(node_id) do
    <<value::32>> = compressed_id(node_id)
    "0x" <> String.upcase(Integer.to_string(value, 16) |> String.pad_leading(8, "0"))
  end

  # Actual header byte size: msg_id(2) + ttl_class(1) + src_compressed(4) = 7
  @wire_header_size 7

  # The module's @max_inner_payload = @max_payload_size(200) - @header_size(8) = 192
  @max_inner_payload 192

  # All six message types with their expected class nibble
  @type_class_pairs [
    {:event, 0x01},
    {:signal, 0x02},
    {:presence, 0x03},
    {:backlog, 0x04},
    {:lastseen, 0x05},
    {:bundle, 0x06}
  ]

  # ---------------------------------------------------------------------------
  # 1. encode_message / decode_message roundtrip for every message type
  # ---------------------------------------------------------------------------

  describe "encode_message/decode_message roundtrip" do
    for {type, _class} <- @type_class_pairs do
      @tag_type type

      test "roundtrips :#{type} messages" do
        msg = TestNodeFactory.build_mesh_message(%{
          type: @tag_type,
          payload: "hello-#{@tag_type}"
        })

        encoded = LoRaTransport.encode_message(msg)
        assert is_binary(encoded)

        {:ok, decoded} = LoRaTransport.decode_message(encoded)

        assert decoded.msg_id == msg.msg_id
        assert decoded.ttl == msg.ttl
        assert decoded.type == @tag_type
        assert decoded.payload == "hello-#{@tag_type}"

        # Without HiveDirectory running, src_node_id resolves to compressed hex
        expected_src = "compressed:" <> compressed_hex(msg.src_node_id)
        assert decoded.src_node_id == expected_src
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 2. TTL / class packing -- upper 4 bits = TTL, lower 4 bits = class
  # ---------------------------------------------------------------------------

  describe "TTL/class byte packing" do
    for {type, class} <- @type_class_pairs do
      @tag_type type
      @tag_class class

      test "packs TTL and class correctly for :#{type}" do
        msg = TestNodeFactory.build_mesh_message(%{type: @tag_type, ttl: 11, payload: <<>>})
        encoded = LoRaTransport.encode_message(msg)

        # Third byte is the ttl_class byte
        <<_msg_id::16, ttl_class::8, _rest::binary>> = encoded

        assert ((ttl_class >>> 4) &&& 0x0F) == 11
        assert (ttl_class &&& 0x0F) == @tag_class
      end
    end

    test "clamps TTL to 15 when given a larger value" do
      msg = TestNodeFactory.build_mesh_message(%{ttl: 99, payload: <<>>})
      encoded = LoRaTransport.encode_message(msg)
      <<_msg_id::16, ttl_class::8, _rest::binary>> = encoded

      assert ((ttl_class >>> 4) &&& 0x0F) == 15
    end

    test "encodes TTL 0 correctly" do
      msg = TestNodeFactory.build_mesh_message(%{ttl: 0, payload: <<>>})
      encoded = LoRaTransport.encode_message(msg)
      <<_msg_id::16, ttl_class::8, _rest::binary>> = encoded

      assert ((ttl_class >>> 4) &&& 0x0F) == 0
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Payload preservation through encode/decode
  # ---------------------------------------------------------------------------

  describe "payload preservation" do
    test "preserves arbitrary binary payload" do
      binary_payload = <<0, 1, 2, 255, 128, 64>>
      msg = TestNodeFactory.build_mesh_message(%{payload: binary_payload})

      encoded = LoRaTransport.encode_message(msg)
      {:ok, decoded} = LoRaTransport.decode_message(encoded)

      assert decoded.payload == binary_payload
    end

    test "preserves UTF-8 string payload" do
      utf8_payload = "hello world"
      msg = TestNodeFactory.build_mesh_message(%{payload: utf8_payload})

      encoded = LoRaTransport.encode_message(msg)
      {:ok, decoded} = LoRaTransport.decode_message(encoded)

      assert decoded.payload == utf8_payload
    end

    test "preserves JSON-encoded payload" do
      json_payload = Jason.encode!(%{"key" => "value", "n" => 42})
      msg = TestNodeFactory.build_mesh_message(%{payload: json_payload})

      encoded = LoRaTransport.encode_message(msg)
      {:ok, decoded} = LoRaTransport.decode_message(encoded)

      assert decoded.payload == json_payload
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Legacy 6-byte format decode
  #
  # The current decode_message/1 has two clauses:
  #   1) New 7-byte header: <<msg_id::16, ttl_class::8, src_compressed::binary-4, payload::binary>>
  #      Matches any binary >= 7 bytes.
  #   2) Legacy 6-byte header: <<msg_id::16, ttl::8, type_byte::8, src_hash::16, payload::binary>>
  #      when byte_size(payload) > 0
  #      Also matches any binary >= 7 bytes, but is shadowed by clause 1.
  #
  # Because clause 1 consumes all binaries >= 7 bytes, clause 2 is only
  # reachable when the binary is exactly 6 bytes (payload = <<>>) -- but the
  # guard requires byte_size(payload) > 0, so it falls through to the catch-all.
  #
  # We test the actual observed behaviour: any binary >= 7 bytes is decoded
  # by the new-format clause. A 6-byte binary returns {:error, :invalid_format}.
  # ---------------------------------------------------------------------------

  describe "legacy 6-byte header decode (shadowed by new format clause)" do
    test "a 6-byte binary (legacy header, no payload) returns error" do
      # Legacy format with empty payload hits neither clause:
      # clause 1 needs >= 7 bytes, clause 2 guard requires payload > 0
      packet = <<0x1234::16, 7::8, 0x01::8, 0xABCD::16>>
      assert {:error, :invalid_format} = LoRaTransport.decode_message(packet)
    end

    test "a legacy-shaped 7+ byte binary is decoded as new format" do
      # Even though this was intended as legacy, clause 1 matches first.
      # Bytes: msg_id(2) + ttl_class(1) + src_compressed(4) + payload(rest)
      msg_id = 0x1234
      legacy_ttl = 7
      legacy_type = 0x01
      legacy_src_hash = 0xABCD
      payload = "legacy-payload"

      packet = <<msg_id::16, legacy_ttl::8, legacy_type::8, legacy_src_hash::16, payload::binary>>

      {:ok, decoded} = LoRaTransport.decode_message(packet)

      # Decoded via new-format clause:
      assert decoded.msg_id == msg_id
      # TTL comes from upper nibble of the third byte (legacy_ttl = 7 = 0x07)
      assert decoded.ttl == ((legacy_ttl >>> 4) &&& 0x0F)
      # Type comes from lower nibble of the third byte
      assert is_atom(decoded.type)
      # src_compressed is bytes 4-7 of the packet
      assert is_binary(decoded.src_compressed)
      assert byte_size(decoded.src_compressed) == 4
    end
  end

  # ---------------------------------------------------------------------------
  # 5. Invalid input returns {:error, :invalid_format}
  # ---------------------------------------------------------------------------

  describe "invalid input handling" do
    test "empty binary" do
      assert {:error, :invalid_format} = LoRaTransport.decode_message(<<>>)
    end

    test "single byte" do
      assert {:error, :invalid_format} = LoRaTransport.decode_message(<<0x42>>)
    end

    test "two bytes (too short for any format)" do
      assert {:error, :invalid_format} = LoRaTransport.decode_message(<<0x00, 0x01>>)
    end

    test "three bytes" do
      assert {:error, :invalid_format} = LoRaTransport.decode_message(<<0x00, 0x01, 0x02>>)
    end

    test "six bytes (too short for new format, legacy guard fails)" do
      assert {:error, :invalid_format} = LoRaTransport.decode_message(<<0, 0, 0, 1, 0, 0>>)
    end

    test "non-binary input" do
      assert {:error, :invalid_format} = LoRaTransport.decode_message(:not_binary)
      assert {:error, :invalid_format} = LoRaTransport.decode_message(nil)
      assert {:error, :invalid_format} = LoRaTransport.decode_message(42)
    end
  end

  # ---------------------------------------------------------------------------
  # 6. encode_presence / decode_presence roundtrip (16-byte payload)
  #
  # Presence binary layout (16 bytes):
  #   hive_compressed:  4 bytes
  #   capabilities:     1 byte
  #   sentant_count:    1 byte
  #   hosting_priority: 1 byte
  #   node_name_hash:   2 bytes
  #   cell_hint:        2 bytes
  #   dir_version:      2 bytes
  #   energy_state:     1 byte
  #   backlog_count:    2 bytes
  # ---------------------------------------------------------------------------

  describe "encode_presence/decode_presence roundtrip" do
    test "roundtrips full presence info" do
      info = TestNodeFactory.build_presence_info()

      encoded = LoRaTransport.encode_presence(info)
      assert byte_size(encoded) == 16

      {:ok, decoded} = LoRaTransport.decode_presence(encoded)

      assert decoded.hive_compressed == info.hive_compressed
      assert decoded.sentant_count == info.sentant_count
      assert decoded.hosting_priority == info.hosting_priority
      assert decoded.node_name_hash == info.node_name_hash
      assert decoded.cell_hint == info.cell_hint
      assert decoded.dir_version == info.dir_version
      assert decoded.energy_state == info.energy_state
      assert decoded.backlog_count == info.backlog_count
      assert decoded.capabilities == info.capabilities
    end

    test "roundtrips with all-zero fields" do
      info = %{
        hive_compressed: <<0, 0, 0, 0>>,
        capabilities: %{},
        sentant_count: 0,
        hosting_priority: 0,
        node_name_hash: 0,
        cell_hint: 0,
        dir_version: 0,
        energy_state: 0,
        backlog_count: 0
      }

      encoded = LoRaTransport.encode_presence(info)
      {:ok, decoded} = LoRaTransport.decode_presence(encoded)

      assert decoded.sentant_count == 0
      assert decoded.hosting_priority == 0
      assert decoded.backlog_count == 0
      assert decoded.energy_state == 0
    end

    test "clamps sentant_count to 255" do
      info = TestNodeFactory.build_presence_info(%{sentant_count: 999})
      encoded = LoRaTransport.encode_presence(info)
      {:ok, decoded} = LoRaTransport.decode_presence(encoded)

      assert decoded.sentant_count == 255
    end

    test "clamps dir_version to 0xFFFF" do
      info = TestNodeFactory.build_presence_info(%{dir_version: 0x1FFFF})
      encoded = LoRaTransport.encode_presence(info)
      {:ok, decoded} = LoRaTransport.decode_presence(encoded)

      assert decoded.dir_version == 0xFFFF
    end

    test "returns error for invalid presence binary" do
      assert {:error, :invalid_format} = LoRaTransport.decode_presence(<<1, 2, 3>>)
      assert {:error, :invalid_format} = LoRaTransport.decode_presence(<<>>)
    end
  end

  # ---------------------------------------------------------------------------
  # 7. Legacy 2-byte presence decode
  # ---------------------------------------------------------------------------

  describe "legacy 2-byte presence" do
    test "decodes 2-byte presence as sentant_count" do
      {:ok, decoded} = LoRaTransport.decode_presence(<<0, 42>>)

      assert decoded.sentant_count == 42
      assert decoded.capabilities == %{}
      assert decoded.dir_version == 0
    end

    test "decodes max 2-byte value" do
      {:ok, decoded} = LoRaTransport.decode_presence(<<0xFF, 0xFF>>)

      assert decoded.sentant_count == 65535
    end
  end

  # ---------------------------------------------------------------------------
  # 8. Capabilities bitfield
  # ---------------------------------------------------------------------------

  describe "capabilities bitfield" do
    test "encodes and decodes all flags set" do
      all_caps = %{
        has_wifi: true,
        has_ble: true,
        is_relay: true,
        is_bridge: true,
        is_anchor: true,
        is_sensor: true,
        is_mobile: true,
        is_cloud: true
      }

      info = TestNodeFactory.build_presence_info(%{capabilities: all_caps})
      encoded = LoRaTransport.encode_presence(info)
      {:ok, decoded} = LoRaTransport.decode_presence(encoded)

      assert decoded.capabilities.has_wifi == true
      assert decoded.capabilities.has_ble == true
      assert decoded.capabilities.is_relay == true
      assert decoded.capabilities.is_bridge == true
      assert decoded.capabilities.is_anchor == true
      assert decoded.capabilities.is_sensor == true
      assert decoded.capabilities.is_mobile == true
      assert decoded.capabilities.is_cloud == true
    end

    test "encodes and decodes all flags unset" do
      no_caps = %{
        has_wifi: false,
        has_ble: false,
        is_relay: false,
        is_bridge: false,
        is_anchor: false,
        is_sensor: false,
        is_mobile: false,
        is_cloud: false
      }

      info = TestNodeFactory.build_presence_info(%{capabilities: no_caps})
      encoded = LoRaTransport.encode_presence(info)
      {:ok, decoded} = LoRaTransport.decode_presence(encoded)

      assert decoded.capabilities.has_wifi == false
      assert decoded.capabilities.has_ble == false
      assert decoded.capabilities.is_relay == false
      assert decoded.capabilities.is_bridge == false
      assert decoded.capabilities.is_anchor == false
      assert decoded.capabilities.is_sensor == false
      assert decoded.capabilities.is_mobile == false
      assert decoded.capabilities.is_cloud == false
    end

    test "is_cloud occupies bit 7 (0x80)" do
      cloud_only = %{
        has_wifi: false,
        has_ble: false,
        is_relay: false,
        is_bridge: false,
        is_anchor: false,
        is_sensor: false,
        is_mobile: false,
        is_cloud: true
      }

      info = TestNodeFactory.build_presence_info(%{capabilities: cloud_only})
      encoded = LoRaTransport.encode_presence(info)

      # Capabilities byte is at offset 4 (after 4-byte hive_compressed)
      <<_hive::binary-size(4), cap_byte::8, _rest::binary>> = encoded
      assert cap_byte == 0x80
    end

    test "individual flag positions are correct" do
      flags_and_bits = [
        {:has_wifi, 0x01},
        {:has_ble, 0x02},
        {:is_relay, 0x04},
        {:is_bridge, 0x08},
        {:is_anchor, 0x10},
        {:is_sensor, 0x20},
        {:is_mobile, 0x40},
        {:is_cloud, 0x80}
      ]

      for {flag, expected_bit} <- flags_and_bits do
        caps = %{flag => true}
        info = TestNodeFactory.build_presence_info(%{capabilities: caps})
        encoded = LoRaTransport.encode_presence(info)

        <<_hive::binary-size(4), cap_byte::8, _rest::binary>> = encoded
        assert (cap_byte &&& expected_bit) == expected_bit,
               "Expected #{flag} at bit #{expected_bit}, got cap_byte=#{cap_byte}"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # 9. Max payload truncation behaviour
  #
  # The module defines @max_inner_payload = 200 - 8 = 192.
  # The wire header is actually 7 bytes (msg_id:2 + ttl_class:1 + src:4).
  # So total wire size when truncated = 7 + 192 = 199.
  # ---------------------------------------------------------------------------

  describe "max payload truncation" do
    test "truncates payload exceeding max inner size (192 bytes)" do
      oversized = :binary.copy(<<0xAA>>, @max_inner_payload + 50)

      msg = TestNodeFactory.build_mesh_message(%{payload: oversized})
      encoded = LoRaTransport.encode_message(msg)

      # Wire header is 7 bytes, truncated payload is 192 bytes
      assert byte_size(encoded) == @wire_header_size + @max_inner_payload

      {:ok, decoded} = LoRaTransport.decode_message(encoded)
      assert byte_size(decoded.payload) == @max_inner_payload
    end

    test "does not truncate payload at exactly max inner size" do
      exact = :binary.copy(<<0xBB>>, @max_inner_payload)

      msg = TestNodeFactory.build_mesh_message(%{payload: exact})
      encoded = LoRaTransport.encode_message(msg)

      assert byte_size(encoded) == @wire_header_size + @max_inner_payload

      {:ok, decoded} = LoRaTransport.decode_message(encoded)
      assert decoded.payload == exact
    end

    test "does not truncate payload under max inner size" do
      small = "small"
      msg = TestNodeFactory.build_mesh_message(%{payload: small})
      encoded = LoRaTransport.encode_message(msg)

      assert byte_size(encoded) == @wire_header_size + byte_size(small)

      {:ok, decoded} = LoRaTransport.decode_message(encoded)
      assert decoded.payload == small
    end
  end

  # ---------------------------------------------------------------------------
  # 10. Empty payload handling
  # ---------------------------------------------------------------------------

  describe "empty payload handling" do
    test "encode_message with empty binary payload" do
      msg = TestNodeFactory.build_mesh_message(%{payload: <<>>})
      encoded = LoRaTransport.encode_message(msg)

      # Header only, no payload bytes
      assert byte_size(encoded) == @wire_header_size

      {:ok, decoded} = LoRaTransport.decode_message(encoded)
      assert decoded.payload == <<>>
    end

    test "encode_message with nil payload encodes as JSON null" do
      msg = TestNodeFactory.build_mesh_message(%{payload: nil})
      encoded = LoRaTransport.encode_message(msg)

      # nil is not binary, so encode_message converts via Jason.encode!(nil) => "null" (4 bytes)
      assert byte_size(encoded) == @wire_header_size + 4

      {:ok, decoded} = LoRaTransport.decode_message(encoded)
      assert decoded.payload == "null"
    end

    test "encode_message with missing payload key defaults to empty binary" do
      msg = %{
        msg_id: 1,
        ttl: 3,
        type: :event,
        src_node_id: TestNodeFactory.generate_uuid()
      }

      encoded = LoRaTransport.encode_message(msg)
      assert byte_size(encoded) == @wire_header_size

      {:ok, decoded} = LoRaTransport.decode_message(encoded)
      assert decoded.payload == <<>>
    end
  end
end
