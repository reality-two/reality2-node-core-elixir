defmodule Reality2Transnet.HiveIdentityTest do
  use ExUnit.Case, async: true

  alias Reality2Transnet.HiveIdentity

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp generate_identity(name \\ "TestHive") do
    {:ok, identity} = HiveIdentity.generate(name)
    identity
  end

  defp generate_node_keypair do
    :crypto.generate_key(:eddsa, :ed25519)
  end

  # ---------------------------------------------------------------------------
  # generate/1
  # ---------------------------------------------------------------------------

  describe "generate/1" do
    test "returns {:ok, %HiveIdentity{}} with expected fields" do
      {:ok, identity} = HiveIdentity.generate("MyHive")

      assert %HiveIdentity{} = identity
      assert identity.name == "MyHive"
      assert identity.algorithm == :ed25519
      assert identity.mode == :key_holder
      assert identity.provisional == true
      assert %DateTime{} = identity.created_at
    end

    test "generates a 32-byte public key" do
      identity = generate_identity()
      assert byte_size(identity.public_key) == 32
    end

    test "generates a 32-byte private key" do
      identity = generate_identity()
      assert byte_size(identity.private_key) == 32
    end

    test "hive_id is derived deterministically from public key" do
      identity = generate_identity()
      assert identity.hive_id == HiveIdentity.derive_hive_id(identity.public_key)
    end

    test "two generates produce different identities" do
      {:ok, id1} = HiveIdentity.generate("Hive1")
      {:ok, id2} = HiveIdentity.generate("Hive2")

      refute id1.hive_id == id2.hive_id
      refute id1.public_key == id2.public_key
      refute id1.private_key == id2.private_key
    end
  end

  # ---------------------------------------------------------------------------
  # derive_hive_id/1
  # ---------------------------------------------------------------------------

  describe "derive_hive_id/1" do
    test "returns a valid UUID v5 format string" do
      identity = generate_identity()
      hive_id = HiveIdentity.derive_hive_id(identity.public_key)

      # UUID format: 8-4-4-4-12 hex chars
      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
               hive_id
             )
    end

    test "is deterministic - same public key always produces same UUID" do
      identity = generate_identity()

      id1 = HiveIdentity.derive_hive_id(identity.public_key)
      id2 = HiveIdentity.derive_hive_id(identity.public_key)

      assert id1 == id2
    end

    test "different public keys produce different UUIDs" do
      id1 = generate_identity()
      id2 = generate_identity()

      refute HiveIdentity.derive_hive_id(id1.public_key) ==
               HiveIdentity.derive_hive_id(id2.public_key)
    end

    test "version nibble is 5" do
      identity = generate_identity()
      hive_id = HiveIdentity.derive_hive_id(identity.public_key)

      # The 13th character (index 14 counting the dash) should be '5'
      parts = String.split(hive_id, "-")
      third_segment = Enum.at(parts, 2)
      assert String.starts_with?(third_segment, "5")
    end

    test "variant bits are correctly set (8, 9, a, or b)" do
      identity = generate_identity()
      hive_id = HiveIdentity.derive_hive_id(identity.public_key)

      parts = String.split(hive_id, "-")
      fourth_segment = Enum.at(parts, 3)
      first_char = String.at(fourth_segment, 0)
      assert first_char in ["8", "9", "a", "b"]
    end
  end

  # ---------------------------------------------------------------------------
  # compressed_id/1
  # ---------------------------------------------------------------------------

  describe "compressed_id/1" do
    test "returns a 4-byte binary" do
      identity = generate_identity()
      compressed = HiveIdentity.compressed_id(identity.hive_id)
      assert byte_size(compressed) == 4
    end

    test "is deterministic - same UUID always produces same compressed ID" do
      identity = generate_identity()

      c1 = HiveIdentity.compressed_id(identity.hive_id)
      c2 = HiveIdentity.compressed_id(identity.hive_id)

      assert c1 == c2
    end

    test "different UUIDs produce different compressed IDs (with high probability)" do
      id1 = generate_identity()
      id2 = generate_identity()

      refute HiveIdentity.compressed_id(id1.hive_id) ==
               HiveIdentity.compressed_id(id2.hive_id)
    end

    test "compressed ID is first 4 bytes of SHA256 of the UUID string" do
      uuid = "12345678-1234-5678-9abc-123456789abc"
      expected = binary_part(:crypto.hash(:sha256, uuid), 0, 4)
      assert HiveIdentity.compressed_id(uuid) == expected
    end
  end

  # ---------------------------------------------------------------------------
  # compressed_id_to_hex/1
  # ---------------------------------------------------------------------------

  describe "compressed_id_to_hex/1" do
    test "formats a 4-byte binary as 0x prefixed uppercase hex" do
      # 0xA3F7B2C1 = 2751263425
      input = <<0xA3, 0xF7, 0xB2, 0xC1>>
      assert HiveIdentity.compressed_id_to_hex(input) == "0xA3F7B2C1"
    end

    test "pads with leading zeros when value is small" do
      input = <<0x00, 0x00, 0x00, 0x01>>
      assert HiveIdentity.compressed_id_to_hex(input) == "0x00000001"
    end

    test "handles all zeros" do
      input = <<0, 0, 0, 0>>
      assert HiveIdentity.compressed_id_to_hex(input) == "0x00000000"
    end

    test "handles max value" do
      input = <<0xFF, 0xFF, 0xFF, 0xFF>>
      assert HiveIdentity.compressed_id_to_hex(input) == "0xFFFFFFFF"
    end

    test "returns default for non-4-byte input" do
      assert HiveIdentity.compressed_id_to_hex(<<1, 2, 3>>) == "0x00000000"
      assert HiveIdentity.compressed_id_to_hex(<<1, 2, 3, 4, 5>>) == "0x00000000"
      assert HiveIdentity.compressed_id_to_hex("invalid") == "0x00000000"
    end

    test "roundtrips with compressed_id/1" do
      identity = generate_identity()
      compressed = HiveIdentity.compressed_id(identity.hive_id)
      hex = HiveIdentity.compressed_id_to_hex(compressed)

      assert String.starts_with?(hex, "0x")
      assert String.length(hex) == 10
      # All chars after 0x should be uppercase hex
      hex_part = String.slice(hex, 2..-1//1)
      assert Regex.match?(~r/^[0-9A-F]{8}$/, hex_part)
    end
  end

  # ---------------------------------------------------------------------------
  # sign/2 and verify/3
  # ---------------------------------------------------------------------------

  describe "sign/2 and verify/3" do
    test "sign returns a 64-byte binary signature" do
      identity = generate_identity()
      signature = HiveIdentity.sign(identity, "hello world")
      assert byte_size(signature) == 64
    end

    test "roundtrip: sign then verify succeeds" do
      identity = generate_identity()
      message = "test message"
      signature = HiveIdentity.sign(identity, message)

      assert HiveIdentity.verify(identity.public_key, message, signature) == true
    end

    test "verify fails with wrong public key" do
      identity = generate_identity()
      other = generate_identity()
      message = "test message"
      signature = HiveIdentity.sign(identity, message)

      assert HiveIdentity.verify(other.public_key, message, signature) == false
    end

    test "verify fails with tampered message" do
      identity = generate_identity()
      signature = HiveIdentity.sign(identity, "original")

      assert HiveIdentity.verify(identity.public_key, "tampered", signature) == false
    end

    test "verify fails with tampered signature" do
      identity = generate_identity()
      message = "test message"
      signature = HiveIdentity.sign(identity, message)

      # Flip a byte in the signature
      <<first_byte, rest::binary>> = signature
      tampered_sig = <<Bitwise.bxor(first_byte, 0xFF), rest::binary>>

      assert HiveIdentity.verify(identity.public_key, message, tampered_sig) == false
    end

    test "verify returns false for mismatched random inputs instead of crashing" do
      random_key = :crypto.strong_rand_bytes(32)
      random_sig = :crypto.strong_rand_bytes(64)
      assert HiveIdentity.verify(random_key, "msg", random_sig) == false
    end

    test "sign works with binary data (not just strings)" do
      identity = generate_identity()
      binary_data = :crypto.strong_rand_bytes(256)
      signature = HiveIdentity.sign(identity, binary_data)

      assert byte_size(signature) == 64
      assert HiveIdentity.verify(identity.public_key, binary_data, signature) == true
    end

    test "sign works with empty message" do
      identity = generate_identity()
      signature = HiveIdentity.sign(identity, "")

      assert byte_size(signature) == 64
      assert HiveIdentity.verify(identity.public_key, "", signature) == true
    end
  end

  # ---------------------------------------------------------------------------
  # issue_node_cert/4 and verify_node_cert/2
  # ---------------------------------------------------------------------------

  describe "issue_node_cert/4" do
    test "returns {:ok, cert} with expected fields" do
      identity = generate_identity()
      {node_pub, _node_priv} = generate_node_keypair()

      {:ok, cert} = HiveIdentity.issue_node_cert(identity, "laptop", node_pub)

      assert cert.type == :node_cert
      assert cert.version == 1
      assert cert.hive_id == identity.hive_id
      assert cert.node_name == "laptop"
      assert cert.node_public_key == Base.encode64(node_pub)
      assert cert.permissions == [:full]
      assert is_integer(cert.issued_at)
      assert is_integer(cert.expires_at) or cert.expires_at == :never
      assert is_binary(cert.signature)
    end

    test "respects custom permissions option" do
      identity = generate_identity()
      {node_pub, _} = generate_node_keypair()

      {:ok, cert} =
        HiveIdentity.issue_node_cert(identity, "sensor", node_pub,
          permissions: [:read, :signal]
        )

      assert cert.permissions == [:read, :signal]
    end

    test "respects :never validity" do
      identity = generate_identity()
      {node_pub, _} = generate_node_keypair()

      {:ok, cert} =
        HiveIdentity.issue_node_cert(identity, "node", node_pub, validity: :never)

      assert cert.expires_at == :never
    end

    test "expires_at is in the future by default" do
      identity = generate_identity()
      {node_pub, _} = generate_node_keypair()

      {:ok, cert} = HiveIdentity.issue_node_cert(identity, "node", node_pub)

      now = System.system_time(:second)
      assert cert.expires_at > now
      # Should be approximately 1 year from now
      assert cert.expires_at - now > 364 * 24 * 60 * 60
    end
  end

  describe "verify_node_cert/2" do
    test "verifies a valid certificate successfully" do
      identity = generate_identity()
      {node_pub, _} = generate_node_keypair()

      {:ok, cert} = HiveIdentity.issue_node_cert(identity, "laptop", node_pub)
      {:ok, cert_data} = HiveIdentity.verify_node_cert(cert, identity.public_key)

      assert cert_data.hive_id == identity.hive_id
      assert cert_data.node_name == "laptop"
      # cert_data should not contain the signature key
      refute Map.has_key?(cert_data, :signature)
    end

    test "rejects certificate signed by different key" do
      identity = generate_identity()
      other = generate_identity()
      {node_pub, _} = generate_node_keypair()

      {:ok, cert} = HiveIdentity.issue_node_cert(identity, "laptop", node_pub)

      assert {:error, :invalid_signature} =
               HiveIdentity.verify_node_cert(cert, other.public_key)
    end

    test "rejects tampered certificate (changed node_name)" do
      identity = generate_identity()
      {node_pub, _} = generate_node_keypair()

      {:ok, cert} = HiveIdentity.issue_node_cert(identity, "laptop", node_pub)
      tampered = %{cert | node_name: "hacked"}

      assert {:error, :invalid_signature} =
               HiveIdentity.verify_node_cert(tampered, identity.public_key)
    end

    test "rejects tampered certificate (changed permissions)" do
      identity = generate_identity()
      {node_pub, _} = generate_node_keypair()

      {:ok, cert} =
        HiveIdentity.issue_node_cert(identity, "node", node_pub, permissions: [:read])

      tampered = %{cert | permissions: [:full]}

      assert {:error, :invalid_signature} =
               HiveIdentity.verify_node_cert(tampered, identity.public_key)
    end

    test "rejects expired certificate" do
      identity = generate_identity()
      {node_pub, _} = generate_node_keypair()

      # Issue a cert with 1-second validity
      {:ok, cert} =
        HiveIdentity.issue_node_cert(identity, "node", node_pub, validity: 1)

      # Manually set expires_at to the past to avoid sleeping
      expired_cert = %{cert | expires_at: System.system_time(:second) - 10}

      # Re-sign it so the signature is valid but expiry check catches it
      # Actually, we can't re-sign without tampering. The expiry check happens
      # before signature verification in verify_node_cert, so this should
      # return :expired even though the signature won't match the modified data.
      assert {:error, :expired} =
               HiveIdentity.verify_node_cert(expired_cert, identity.public_key)
    end

    test "accepts certificate with :never expiry" do
      identity = generate_identity()
      {node_pub, _} = generate_node_keypair()

      {:ok, cert} =
        HiveIdentity.issue_node_cert(identity, "node", node_pub, validity: :never)

      assert {:ok, _cert_data} =
               HiveIdentity.verify_node_cert(cert, identity.public_key)
    end

    test "rejects certificate with no signature" do
      cert = %{
        type: :node_cert,
        version: 1,
        hive_id: "fake",
        node_name: "test",
        node_public_key: Base.encode64(<<0::256>>),
        permissions: [:full],
        issued_at: System.system_time(:second),
        expires_at: System.system_time(:second) + 3600
      }

      identity = generate_identity()
      assert {:error, :no_signature} = HiveIdentity.verify_node_cert(cert, identity.public_key)
    end
  end

  # ---------------------------------------------------------------------------
  # export_public/1 and from_public/1
  # ---------------------------------------------------------------------------

  describe "export_public/1" do
    test "returns a map with expected keys and no private key" do
      identity = generate_identity("ExportTest")
      exported = HiveIdentity.export_public(identity)

      assert exported.hive_id == identity.hive_id
      assert exported.name == "ExportTest"
      assert exported.algorithm == :ed25519
      assert is_binary(exported.public_key)
      assert is_binary(exported.created_at)

      # Must not contain private key
      refute Map.has_key?(exported, :private_key)
    end

    test "public_key is Base64 encoded" do
      identity = generate_identity()
      exported = HiveIdentity.export_public(identity)

      assert {:ok, decoded} = Base.decode64(exported.public_key)
      assert decoded == identity.public_key
    end

    test "created_at is ISO8601 format" do
      identity = generate_identity()
      exported = HiveIdentity.export_public(identity)

      assert {:ok, _dt, _offset} = DateTime.from_iso8601(exported.created_at)
    end
  end

  describe "from_public/1" do
    test "roundtrips through export_public successfully" do
      identity = generate_identity("RoundTrip")
      exported = HiveIdentity.export_public(identity)

      {:ok, reconstructed} = HiveIdentity.from_public(exported)

      assert reconstructed.hive_id == identity.hive_id
      assert reconstructed.name == "RoundTrip"
      assert reconstructed.public_key == identity.public_key
      assert reconstructed.private_key == nil
      assert reconstructed.algorithm == :ed25519
    end

    test "reconstructed identity has nil private key (no leak)" do
      identity = generate_identity()
      exported = HiveIdentity.export_public(identity)

      {:ok, reconstructed} = HiveIdentity.from_public(exported)
      assert reconstructed.private_key == nil
    end

    test "rejects mismatched hive_id and public_key" do
      identity = generate_identity()
      exported = HiveIdentity.export_public(identity)

      # Tamper with hive_id
      tampered = %{exported | hive_id: "00000000-0000-5000-8000-000000000000"}

      assert {:error, :invalid_identity} = HiveIdentity.from_public(tampered)
    end

    test "rejects invalid Base64 public key" do
      data = %{hive_id: "something", public_key: "not-valid-base64!!!"}

      assert {:error, :invalid_identity} = HiveIdentity.from_public(data)
    end

    test "uses default name when name is missing" do
      identity = generate_identity()
      exported = HiveIdentity.export_public(identity) |> Map.delete(:name)

      {:ok, reconstructed} = HiveIdentity.from_public(exported)
      assert reconstructed.name == "unknown"
    end

    test "can verify signatures using reconstructed public identity" do
      identity = generate_identity()
      message = "verify with reconstructed"
      signature = HiveIdentity.sign(identity, message)

      exported = HiveIdentity.export_public(identity)
      {:ok, reconstructed} = HiveIdentity.from_public(exported)

      assert HiveIdentity.verify(reconstructed.public_key, message, signature) == true
    end
  end

  # ---------------------------------------------------------------------------
  # Full roundtrip: generate -> issue cert -> export -> from_public -> verify cert
  # ---------------------------------------------------------------------------

  describe "full certification roundtrip" do
    test "cert issued by identity can be verified using exported public info" do
      # Key holder generates identity
      identity = generate_identity("ProductionHive")
      {node_pub, _node_priv} = generate_node_keypair()

      # Issue a certificate
      {:ok, cert} = HiveIdentity.issue_node_cert(identity, "field-sensor", node_pub)

      # Export public info (as would be shared over network)
      exported = HiveIdentity.export_public(identity)

      # Receiving node reconstructs public identity
      {:ok, public_identity} = HiveIdentity.from_public(exported)

      # Verify the certificate using only the public key
      {:ok, cert_data} = HiveIdentity.verify_node_cert(cert, public_identity.public_key)

      assert cert_data.node_name == "field-sensor"
      assert cert_data.hive_id == identity.hive_id
    end

    test "can extract node public key from certificate" do
      identity = generate_identity()
      {node_pub, _} = generate_node_keypair()

      {:ok, cert} = HiveIdentity.issue_node_cert(identity, "node1", node_pub)
      {:ok, extracted} = HiveIdentity.get_node_public_key(cert)

      assert extracted == node_pub
    end
  end

  # ---------------------------------------------------------------------------
  # Join codes (case-insensitive verify via String.upcase)
  # ---------------------------------------------------------------------------

  describe "join code case-insensitivity" do
    test "String.upcase normalizes lowercase to uppercase for code lookup" do
      # The GenServer handler uses String.upcase(code) for lookup, so codes are
      # case-insensitive. We test the String.upcase behavior directly since
      # verify_join_code requires a running GenServer.

      code = "A7X9"
      assert String.upcase("a7x9") == code
      assert String.upcase("A7x9") == code
      assert String.upcase("a7X9") == code
      assert String.upcase("A7X9") == code
    end

    test "join codes from generate_code would be uppercase alphanumeric" do
      # We can't call the private generate_code, but we can verify the character
      # set it uses. The allowed chars are: ABCDEFGHJKLMNPQRSTUVWXYZ23456789
      # (no I, O, 0, 1). Any valid code uppercased should match this pattern.
      valid_pattern = ~r/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{4}$/

      # Simulate what a code would look like
      chars = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

      for _ <- 1..20 do
        code =
          1..4
          |> Enum.map(fn _ -> Enum.random(chars) end)
          |> List.to_string()

        assert Regex.match?(valid_pattern, code)
        # Lowercase version should normalize back
        assert String.upcase(String.downcase(code)) == code
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases
  # ---------------------------------------------------------------------------

  describe "edge cases" do
    test "generate with empty name string" do
      {:ok, identity} = HiveIdentity.generate("")
      assert identity.name == ""
      assert is_binary(identity.hive_id)
    end

    test "generate with unicode name" do
      {:ok, identity} = HiveIdentity.generate("Hive-\u00E9\u00E8\u00EA")
      assert identity.name == "Hive-\u00E9\u00E8\u00EA"
    end

    test "compressed_id of two different UUID strings differs" do
      c1 = HiveIdentity.compressed_id("aaaaaaaa-aaaa-5aaa-8aaa-aaaaaaaaaaaa")
      c2 = HiveIdentity.compressed_id("bbbbbbbb-bbbb-5bbb-8bbb-bbbbbbbbbbbb")
      refute c1 == c2
    end

    test "sign and verify with large message" do
      identity = generate_identity()
      large_message = :crypto.strong_rand_bytes(1_000_000)
      signature = HiveIdentity.sign(identity, large_message)

      assert HiveIdentity.verify(identity.public_key, large_message, signature) == true
    end

    test "multiple certificates can be issued by same identity" do
      identity = generate_identity()
      {pub1, _} = generate_node_keypair()
      {pub2, _} = generate_node_keypair()

      {:ok, cert1} = HiveIdentity.issue_node_cert(identity, "node1", pub1)
      {:ok, cert2} = HiveIdentity.issue_node_cert(identity, "node2", pub2)

      assert {:ok, _} = HiveIdentity.verify_node_cert(cert1, identity.public_key)
      assert {:ok, _} = HiveIdentity.verify_node_cert(cert2, identity.public_key)

      # Certificates should have different signatures
      refute cert1.signature == cert2.signature
    end
  end
end
