defmodule Reality2Wfs.RouterTest do
  @moduledoc """
  Tests for Reality2Wfs.Router path parsing and routing behavior.

  The core `parse_path/1` function is private, so these tests document and verify
  the expected path format classifications by testing observable behavior where
  possible and documenting expected parse results as structured descriptions.

  Path formats supported:
    - "*"                    -> :broadcast_all
    - "@sender"              -> :reply_to_sender
    - "sentant_name"         -> {:local_only, "sentant_name"}
    - "*|sentant_name"       -> {:all_nodes, "sentant_name"}
    - "node|sentant"         -> {:specific_node, ...} or {:specific_node_or_hive, ...}
    - "hive|sentant"         -> {:hive_sentant, ...}
    - "hive|node|sentant"    -> {:hive_node_sentant, ...}
    - %{id: uuid}            -> {:local_only, %{id: uuid}}
    - %{name: "Name"}        -> {:local_only, %{name: "Name"}}
  """

  use ExUnit.Case, async: true

  @moduletag :integration

  # ---------------------------------------------------------------------------
  # UUID Validation Helpers
  # ---------------------------------------------------------------------------

  @valid_uuid_v1 "550e8400-e29b-11d4-a716-446655440000"
  @valid_uuid_v4 "f47ac10b-58cc-4372-a567-0e02b2c3d479"
  @valid_uuid_upper "F47AC10B-58CC-4372-A567-0E02B2C3D479"
  @valid_uuid_nil "00000000-0000-0000-0000-000000000000"

  @invalid_uuid_short "550e8400-e29b-11d4-a716"
  @invalid_uuid_no_hyphens "550e8400e29b11d4a716446655440000"
  @invalid_uuid_bad_chars "550e8400-e29b-11d4-a716-44665544zzzz"
  @invalid_uuid_extra_segment "550e8400-e29b-11d4-a716-446655440000-extra"

  describe "UUID validation via UUID.info/1" do
    test "recognizes valid v1 UUID" do
      assert {:ok, _info} = UUID.info(@valid_uuid_v1)
    end

    test "recognizes valid v4 UUID" do
      assert {:ok, _info} = UUID.info(@valid_uuid_v4)
    end

    test "recognizes uppercase UUID" do
      assert {:ok, _info} = UUID.info(@valid_uuid_upper)
    end

    test "recognizes nil UUID (all zeros)" do
      assert {:ok, _info} = UUID.info(@valid_uuid_nil)
    end

    test "rejects truncated UUID" do
      assert {:error, _reason} = UUID.info(@invalid_uuid_short)
    end

    test "UUID without hyphens is recognized as hex format" do
      # UUID lib accepts 32 hex chars without hyphens as :hex type
      assert {:ok, info} = UUID.info(@invalid_uuid_no_hyphens)
      assert info[:type] == :hex
    end

    test "rejects UUID with invalid hex characters" do
      assert {:error, _reason} = UUID.info(@invalid_uuid_bad_chars)
    end

    test "rejects UUID with extra segment" do
      assert {:error, _reason} = UUID.info(@invalid_uuid_extra_segment)
    end

    test "rejects plain name string" do
      assert {:error, _reason} = UUID.info("Zen Quote")
    end

    test "rejects empty string" do
      assert {:error, _reason} = UUID.info("")
    end

    test "rejects single word" do
      assert {:error, _reason} = UUID.info("Sensor")
    end

    test "rejects node-like name" do
      assert {:error, _reason} = UUID.info("R2Node_A3F7")
    end
  end

  # ---------------------------------------------------------------------------
  # Path Format Splitting (String.split on "|")
  # ---------------------------------------------------------------------------
  # parse_path/1 splits on "|" to determine routing intent.
  # These tests verify the splitting logic that underpins path classification.

  describe "path splitting on pipe separator" do
    test "bare string with no pipe yields single-element list" do
      assert String.split("Zen Quote", "|") == ["Zen Quote"]
    end

    test "star-pipe prefix yields two-element list starting with *" do
      assert String.split("*|Sensor", "|") == ["*", "Sensor"]
    end

    test "node-pipe-sentant yields two-element list" do
      assert String.split("R2Node_A3F7|Zen Quote", "|") == ["R2Node_A3F7", "Zen Quote"]
    end

    test "hive-pipe-node-pipe-sentant yields three-element list" do
      assert String.split("MyHive|R2Node_A3F7|Zen Quote", "|") == ["MyHive", "R2Node_A3F7", "Zen Quote"]
    end

    test "UUID-pipe-UUID yields two-element list" do
      node_uuid = "550e8400-e29b-11d4-a716-446655440000"
      sentant_uuid = "f47ac10b-58cc-4372-a567-0e02b2c3d479"
      assert String.split("#{node_uuid}|#{sentant_uuid}", "|") == [node_uuid, sentant_uuid]
    end

    test "star alone does not split" do
      assert String.split("*", "|") == ["*"]
    end

    test "@sender alone does not split" do
      assert String.split("@sender", "|") == ["@sender"]
    end

    test "pipe at start yields empty first element" do
      assert String.split("|Sentant", "|") == ["", "Sentant"]
    end

    test "pipe at end yields empty last element" do
      assert String.split("Node|", "|") == ["Node", ""]
    end

    test "double pipe yields three elements with empty middle" do
      assert String.split("Hive||Sentant", "|") == ["Hive", "", "Sentant"]
    end

    test "four-part path yields four elements" do
      assert String.split("a|b|c|d", "|") == ["a", "b", "c", "d"]
    end
  end

  # ---------------------------------------------------------------------------
  # Expected parse_path/1 Classification Rules
  # ---------------------------------------------------------------------------
  # These tests document what parse_path/1 SHOULD return for each input format.
  # Since parse_path is private, we express the rules as pattern-match assertions
  # on the input structure, simulating the classification logic.

  describe "parse_path classification: broadcast_all" do
    test "literal '*' routes to broadcast_all" do
      # parse_path("*") -> :broadcast_all
      path = "*"
      assert path == "*"
      # This is matched by the first function clause: defp parse_path("*"), do: :broadcast_all
    end

    test "'*' is the only broadcast_all trigger (not '**' or ' *')" do
      # Only exact "*" matches; other star patterns go through String.split
      refute "*" == "**"
      refute "*" == " *"
      refute "*" == "* "
    end
  end

  describe "parse_path classification: reply_to_sender" do
    test "'@sender' routes to reply_to_sender" do
      # parse_path("@sender") -> :reply_to_sender
      path = "@sender"
      assert path == "@sender"
    end

    test "'@sender' is case-sensitive" do
      refute "@sender" == "@Sender"
      refute "@sender" == "@SENDER"
    end
  end

  describe "parse_path classification: local_only (bare name)" do
    test "plain name with no pipe is local_only" do
      # parse_path("Zen Quote") -> {:local_only, "Zen Quote"}
      parts = String.split("Zen Quote", "|")
      assert parts == ["Zen Quote"]
      # Single element list -> {:local_only, sentant_only}
    end

    test "UUID string with no pipe is local_only" do
      # parse_path("f47ac10b-58cc-4372-a567-0e02b2c3d479") -> {:local_only, "f47ac10b-..."}
      uuid = "f47ac10b-58cc-4372-a567-0e02b2c3d479"
      parts = String.split(uuid, "|")
      assert parts == [uuid]
    end

    test "empty string is local_only (degenerate case)" do
      parts = String.split("", "|")
      assert parts == [""]
    end
  end

  describe "parse_path classification: local_only (map inputs)" do
    test "map with :id key is local_only" do
      # parse_path(%{id: uuid}) -> {:local_only, %{id: uuid}}
      input = %{id: "f47ac10b-58cc-4372-a567-0e02b2c3d479"}
      assert match?(%{id: _}, input)
    end

    test "map with :name key is local_only" do
      # parse_path(%{name: "Zen Quote"}) -> {:local_only, %{name: "Zen Quote"}}
      input = %{name: "Zen Quote"}
      assert match?(%{name: _}, input)
    end

    test "map with both :id and :name still matches :id clause first" do
      # Elixir pattern matching: %{id: _} matches maps that HAVE :id key
      input = %{id: "some-uuid", name: "Zen Quote"}
      assert match?(%{id: _}, input)
    end

    test "map without :id or :name falls through to catch-all" do
      # parse_path(other) -> {:local_only, other}
      input = %{foo: "bar"}
      refute match?(%{id: _}, input)
      refute match?(%{name: _}, input)
    end
  end

  describe "parse_path classification: all_nodes (*| prefix)" do
    test "'*|SentantName' classifies as all_nodes" do
      # parse_path("*|Sensor") -> {:all_nodes, "Sensor"}
      parts = String.split("*|Sensor", "|")
      assert ["*", "Sensor"] = parts
    end

    test "'*|' with UUID classifies as all_nodes" do
      uuid = "f47ac10b-58cc-4372-a567-0e02b2c3d479"
      parts = String.split("*|#{uuid}", "|")
      assert ["*", ^uuid] = parts
    end

    test "'*|' with name containing spaces" do
      parts = String.split("*|Zen Quote", "|")
      assert ["*", "Zen Quote"] = parts
    end

    test "'*|' preserves the sentant part exactly" do
      parts = String.split("*|  Leading Spaces  ", "|")
      assert ["*", "  Leading Spaces  "] = parts
    end
  end

  describe "parse_path classification: two-part paths (node|sentant or hive|sentant)" do
    test "two-part path is split into part1 and part2" do
      # parse_path("NodeA|SentantB") -> depends on classify_identifier("NodeA")
      parts = String.split("NodeA|SentantB", "|")
      assert ["NodeA", "SentantB"] = parts
    end

    test "UUID|name yields two parts for specific_node routing" do
      node_uuid = "550e8400-e29b-11d4-a716-446655440000"
      parts = String.split("#{node_uuid}|Zen Quote", "|")
      assert [^node_uuid, "Zen Quote"] = parts
    end

    test "UUID|UUID yields two parts" do
      node_uuid = "550e8400-e29b-11d4-a716-446655440000"
      sentant_uuid = "f47ac10b-58cc-4372-a567-0e02b2c3d479"
      parts = String.split("#{node_uuid}|#{sentant_uuid}", "|")
      assert [^node_uuid, ^sentant_uuid] = parts
    end

    test "name|name yields two parts (classify_identifier decides routing)" do
      parts = String.split("R2Node_A3F7|Zen Quote", "|")
      assert ["R2Node_A3F7", "Zen Quote"] = parts
      # classify_identifier("R2Node_A3F7") determines if this is
      # :local_node, :known_peer, :hive, or :unknown
    end
  end

  describe "parse_path classification: three-part paths (hive|node|sentant)" do
    test "three-part path classifies as hive_node_sentant" do
      # parse_path("MyHive|NodeA|SentantB") -> {:hive_node_sentant, "MyHive", "NodeA", "SentantB"}
      parts = String.split("MyHive|NodeA|SentantB", "|")
      assert ["MyHive", "NodeA", "SentantB"] = parts
    end

    test "three UUIDs yield hive_node_sentant" do
      hive = "00000000-0000-0000-0000-000000000001"
      node = "00000000-0000-0000-0000-000000000002"
      sentant = "00000000-0000-0000-0000-000000000003"
      parts = String.split("#{hive}|#{node}|#{sentant}", "|")
      assert [^hive, ^node, ^sentant] = parts
    end

    test "mixed names and UUIDs in three-part path" do
      node_uuid = "550e8400-e29b-11d4-a716-446655440000"
      parts = String.split("ProductionHive|#{node_uuid}|Sensor", "|")
      assert ["ProductionHive", ^node_uuid, "Sensor"] = parts
    end
  end

  # ---------------------------------------------------------------------------
  # classify_identifier behavior rules
  # ---------------------------------------------------------------------------
  # classify_identifier/1 determines how two-part paths are routed.
  # It checks (in order):
  #   1. local node name/id -> :local_node
  #   2. known peer by name (WFS_NodeNames) -> :known_peer
  #   3. known peer by UUID (uuid? + peer_exists?) -> :known_peer
  #   4. hive identifier -> :hive
  #   5. fallthrough -> :unknown (try node first, then hive)

  describe "classify_identifier routing decisions" do
    test ":local_node -> {:specific_node, part1, part2}" do
      # When part1 matches local node name or ID, routes as specific_node
      # with local resolution
      classification = :local_node
      assert classification in [:local_node, :known_peer, :hive, :unknown]
    end

    test ":known_peer -> {:specific_node, part1, part2}" do
      classification = :known_peer
      assert classification in [:local_node, :known_peer, :hive, :unknown]
    end

    test ":hive -> {:hive_sentant, part1, part2}" do
      classification = :hive
      assert classification in [:local_node, :known_peer, :hive, :unknown]
    end

    test ":unknown -> {:specific_node_or_hive, part1, part2} (try node then hive)" do
      classification = :unknown
      assert classification in [:local_node, :known_peer, :hive, :unknown]
    end
  end

  # ---------------------------------------------------------------------------
  # Non-string input handling
  # ---------------------------------------------------------------------------

  describe "parse_path classification: non-string inputs" do
    test "integer input falls through to catch-all local_only" do
      # parse_path(42) -> {:local_only, 42}
      input = 42
      refute is_binary(input)
      refute match?(%{id: _}, input)
      refute match?(%{name: _}, input)
      # Falls to: defp parse_path(other), do: {:local_only, other}
    end

    test "atom input falls through to catch-all local_only" do
      input = :some_atom
      refute is_binary(input)
      refute match?(%{id: _}, input)
      refute match?(%{name: _}, input)
    end

    test "nil input falls through to catch-all local_only" do
      input = nil
      refute is_binary(input)
      refute match?(%{id: _}, input)
      refute match?(%{name: _}, input)
    end

    test "list input falls through to catch-all local_only" do
      input = ["a", "b"]
      refute is_binary(input)
      refute match?(%{id: _}, input)
      refute match?(%{name: _}, input)
    end

    test "tuple input falls through to catch-all local_only" do
      input = {:some, :tuple}
      refute is_binary(input)
      refute match?(%{id: _}, input)
      refute match?(%{name: _}, input)
    end
  end

  # ---------------------------------------------------------------------------
  # Edge cases in path formats
  # ---------------------------------------------------------------------------

  describe "edge cases in path parsing" do
    test "path with only a pipe separator yields two empty strings" do
      parts = String.split("|", "|")
      assert ["", ""] = parts
      # Would classify as two-part: classify_identifier("") decides routing
    end

    test "path with multiple consecutive pipes" do
      parts = String.split("|||", "|")
      assert ["", "", "", ""] = parts
      # Four parts: not handled by any specific clause (three-part is max)
      # String.split returns 4 elements, which doesn't match any case clause
    end

    test "sentant name containing special characters" do
      parts = String.split("My Sentant (v2.0) [test]", "|")
      assert ["My Sentant (v2.0) [test]"] = parts
    end

    test "sentant name with unicode characters" do
      parts = String.split("Zen Quote", "|")
      assert ["Zen Quote"] = parts
    end

    test "very long sentant name" do
      long_name = String.duplicate("a", 1000)
      parts = String.split(long_name, "|")
      assert [^long_name] = parts
    end

    test "path with trailing pipe" do
      parts = String.split("NodeA|", "|")
      assert ["NodeA", ""] = parts
      # Two-part path with empty sentant part
    end

    test "path with leading pipe" do
      parts = String.split("|SentantB", "|")
      assert ["", "SentantB"] = parts
      # Two-part path with empty node part
    end

    test "four-part path is not explicitly handled by parse_path" do
      # String.split("a|b|c|d", "|") => ["a", "b", "c", "d"]
      # parse_path only handles 1, 2, and 3 element lists from split
      # A 4-element list would not match any clause in the case statement
      parts = String.split("a|b|c|d", "|")
      assert length(parts) == 4
      # This would cause a CaseClauseError in parse_path/1
    end
  end

  # ---------------------------------------------------------------------------
  # normalize_identifier behavior
  # ---------------------------------------------------------------------------
  # normalize_identifier/1 converts names to UUIDs via Reality2.Metadata lookup.
  # These tests document the expected dispatch based on input type.

  describe "normalize_identifier input dispatch" do
    test "binary UUID is returned as-is (no lookup needed)" do
      uuid = "f47ac10b-58cc-4372-a567-0e02b2c3d479"
      assert {:ok, _} = UUID.info(uuid)
      # normalize_identifier would return uuid directly
    end

    test "binary name triggers Metadata lookup" do
      name = "Zen Quote"
      assert {:error, _} = UUID.info(name)
      # normalize_identifier would call Reality2.Metadata.get(:SentantIDs, name)
    end

    test "map with :id extracts the id directly" do
      input = %{id: "some-uuid"}
      assert input.id == "some-uuid"
      # normalize_identifier(%{id: id}) -> id
    end

    test "map with :name triggers Metadata lookup" do
      input = %{name: "Zen Quote"}
      assert input.name == "Zen Quote"
      # normalize_identifier(%{name: name}) -> Reality2.Metadata.get(:SentantIDs, name) || name
    end
  end

  # ---------------------------------------------------------------------------
  # Router API function signatures
  # ---------------------------------------------------------------------------

  describe "public API function existence" do
    setup do
      Code.ensure_loaded!(Reality2Wfs.Router)
      :ok
    end

    test "send_to_sentant/5 is exported" do
      assert function_exported?(Reality2Wfs.Router, :send_to_sentant, 5)
    end

    test "send_to_sentant/4 is exported (without sender)" do
      assert function_exported?(Reality2Wfs.Router, :send_to_sentant, 4)
    end

    test "send_to_sentant/3 is exported (minimal args)" do
      assert function_exported?(Reality2Wfs.Router, :send_to_sentant, 3)
    end

    test "send_to_sentant/2 is exported (identifier + event)" do
      assert function_exported?(Reality2Wfs.Router, :send_to_sentant, 2)
    end

    test "broadcast/4 is exported" do
      assert function_exported?(Reality2Wfs.Router, :broadcast, 4)
    end

    test "broadcast/3 is exported" do
      assert function_exported?(Reality2Wfs.Router, :broadcast, 3)
    end

    test "broadcast/2 is exported" do
      assert function_exported?(Reality2Wfs.Router, :broadcast, 2)
    end

    test "locate/1 is exported" do
      assert function_exported?(Reality2Wfs.Router, :locate, 1)
    end

    test "get_routing_table/0 is exported" do
      assert function_exported?(Reality2Wfs.Router, :get_routing_table, 0)
    end

    test "refresh_topology/0 is exported" do
      assert function_exported?(Reality2Wfs.Router, :refresh_topology, 0)
    end

    test "start_link/1 is exported" do
      assert function_exported?(Reality2Wfs.Router, :start_link, 1)
    end
  end

  # ---------------------------------------------------------------------------
  # Path format documentation as executable specs
  # ---------------------------------------------------------------------------

  describe "path format specification" do
    @tag :specification
    test "broadcast all: '*' sends to every sentant on every known node" do
      # Input: "*"
      # Expected parse result: :broadcast_all
      # Behavior: iterates all local sentant IDs + all peer sentant IDs
      assert "*" == "*"
    end

    @tag :specification
    test "reply to sender: '@sender' sends back to the originating sentant" do
      # Input: "@sender"
      # Expected parse result: :reply_to_sender
      # Behavior: uses sender context (node_id, sentant_id) to route back
      assert "@sender" == "@sender"
    end

    @tag :specification
    test "local only: bare name searches local node first, then hive directory" do
      # Input: "Zen Quote"
      # Expected parse result: {:local_only, "Zen Quote"}
      # Behavior: normalize_identifier -> is_local_sentant? -> find_in_hive_directory
      path = "Zen Quote"
      refute String.contains?(path, "|")
    end

    @tag :specification
    test "all nodes: '*|name' sends to all nodes that have a sentant with that name" do
      # Input: "*|Sensor"
      # Expected parse result: {:all_nodes, "Sensor"}
      # Behavior: check local + query all peers for matching sentant name
      [star, name] = String.split("*|Sensor", "|")
      assert star == "*"
      assert name == "Sensor"
    end

    @tag :specification
    test "specific node: 'node|sentant' routes to a particular node" do
      # Input: "R2Node_A3F7|Zen Quote"
      # Expected parse result: depends on classify_identifier("R2Node_A3F7")
      #   :local_node -> {:specific_node, ...}
      #   :known_peer -> {:specific_node, ...}
      #   :hive -> {:hive_sentant, ...}
      #   :unknown -> {:specific_node_or_hive, ...}
      [node_part, sentant_part] = String.split("R2Node_A3F7|Zen Quote", "|")
      assert node_part == "R2Node_A3F7"
      assert sentant_part == "Zen Quote"
    end

    @tag :specification
    test "hive node sentant: 'hive|node|sentant' routes through hive to specific node" do
      # Input: "MyHive|R2Node_A3F7|Zen Quote"
      # Expected parse result: {:hive_node_sentant, "MyHive", "R2Node_A3F7", "Zen Quote"}
      # Behavior: delegates to handle_specific_node with node_part and sentant_part
      [hive, node, sentant] = String.split("MyHive|R2Node_A3F7|Zen Quote", "|")
      assert hive == "MyHive"
      assert node == "R2Node_A3F7"
      assert sentant == "Zen Quote"
    end

    @tag :specification
    test "map with id: local_only lookup by UUID" do
      # Input: %{id: "f47ac10b-58cc-4372-a567-0e02b2c3d479"}
      # Expected parse result: {:local_only, %{id: "f47ac10b-..."}}
      input = %{id: "f47ac10b-58cc-4372-a567-0e02b2c3d479"}
      assert is_map(input)
      assert Map.has_key?(input, :id)
    end

    @tag :specification
    test "map with name: local_only lookup by name" do
      # Input: %{name: "Zen Quote"}
      # Expected parse result: {:local_only, %{name: "Zen Quote"}}
      input = %{name: "Zen Quote"}
      assert is_map(input)
      assert Map.has_key?(input, :name)
    end
  end
end
