defmodule Reality2.HelpersTest do
  use ExUnit.Case, async: true

  alias Reality2.Helpers.{R2Map, JsonPath, Convert}

  describe "R2Map.get/3" do
    test "returns default when map is nil" do
      assert R2Map.get(nil, "key", "default") == "default"
      assert R2Map.get(nil, :key, "default") == "default"
      assert R2Map.get(nil, "key") == nil
    end

    test "returns default when input is not a map" do
      assert R2Map.get("not a map", "key", "default") == "default"
      assert R2Map.get(123, "key", "default") == "default"
      assert R2Map.get([], "key", "default") == "default"
      assert R2Map.get(:atom, "key", "default") == "default"
    end

    test "gets value with string key" do
      map = %{"name" => "Alice", "age" => 30}
      assert R2Map.get(map, "name") == "Alice"
      assert R2Map.get(map, "age", 0) == 30
    end

    test "gets value with atom key" do
      map = %{name: "Bob", age: 25}
      assert R2Map.get(map, :name) == "Bob"
      assert R2Map.get(map, :age, 0) == 25
    end

    test "falls back to atom key when string key is missing" do
      map = %{name: "Charlie"}
      assert R2Map.get(map, "name") == "Charlie"
    end

    test "falls back to string key when atom key is missing" do
      map = %{"name" => "Dave"}
      assert R2Map.get(map, :name) == "Dave"
    end

    test "returns default when both string and atom keys are missing" do
      map = %{other: "value"}
      assert R2Map.get(map, "name", "default") == "default"
      assert R2Map.get(map, :name, "default") == "default"
    end

    test "handles mixed key types in map" do
      map = %{"string_key" => "string_val", atom_key: "atom_val"}
      assert R2Map.get(map, "string_key") == "string_val"
      assert R2Map.get(map, :atom_key) == "atom_val"
      assert R2Map.get(map, "atom_key") == "atom_val"
      assert R2Map.get(map, :string_key) == "string_val"
    end

    test "handles integer keys" do
      map = %{1 => "one", 2 => "two"}
      assert R2Map.get(map, 1) == "one"
      assert R2Map.get(map, 3, "default") == "default"
    end

    test "prefers exact key match over fallback" do
      map = %{"name" => "string_name", name: "atom_name"}
      assert R2Map.get(map, "name") == "string_name"
      assert R2Map.get(map, :name) == "atom_name"
    end

    test "returns nil as value when it exists in map" do
      map = %{key: nil}
      assert R2Map.get(map, :key, "default") == "default"
    end
  end

  describe "R2Map.delete/2" do
    test "returns nil when map is nil" do
      assert R2Map.delete(nil, "key") == nil
      assert R2Map.delete(nil, :key) == nil
    end

    test "returns nil when input is not a map" do
      assert R2Map.delete("not a map", "key") == nil
      assert R2Map.delete(123, "key") == nil
      assert R2Map.delete([], "key") == nil
    end

    test "deletes string key" do
      map = %{"name" => "Alice", "age" => 30}
      result = R2Map.delete(map, "name")
      assert result == %{"age" => 30}
      refute Map.has_key?(result, "name")
    end

    test "deletes atom key" do
      map = %{name: "Bob", age: 25}
      result = R2Map.delete(map, :name)
      assert result == %{age: 25}
      refute Map.has_key?(result, :name)
    end

    test "deletes both string and atom versions when deleting with string key" do
      map = Map.merge(%{"name" => "Charlie", "age" => 30}, %{name: "Charlie2"})
      result = R2Map.delete(map, "name")
      assert result == %{"age" => 30}
      refute Map.has_key?(result, "name")
      refute Map.has_key?(result, :name)
    end

    test "deletes both string and atom versions when deleting with atom key" do
      map = Map.merge(%{"name" => "Dave"}, %{name: "Dave2", age: 30})
      result = R2Map.delete(map, :name)
      assert result == %{age: 30}
      refute Map.has_key?(result, "name")
      refute Map.has_key?(result, :name)
    end

    test "handles integer keys" do
      map = %{1 => "one", 2 => "two"}
      result = R2Map.delete(map, 1)
      assert result == %{2 => "two"}
    end

    test "returns unchanged map when key doesn't exist" do
      map = %{name: "Eve"}
      assert R2Map.delete(map, :age) == %{name: "Eve"}
    end

    test "can delete all keys from map" do
      map = %{name: "Frank"}
      result = R2Map.delete(map, :name)
      assert result == %{}
    end
  end

  describe "R2Map.put/3" do
    test "returns nil when map is nil" do
      assert R2Map.put(nil, "key", "value") == nil
      assert R2Map.put(nil, :key, "value") == nil
    end

    test "returns nil when key is nil" do
      assert R2Map.put(%{}, nil, "value") == nil
      assert R2Map.put(%{name: "Alice"}, nil, "value") == nil
    end

    test "returns nil when input is not a map" do
      assert R2Map.put("not a map", "key", "value") == nil
      assert R2Map.put(123, "key", "value") == nil
      assert R2Map.put([], "key", "value") == nil
    end

    test "puts value with atom key as string" do
      map = %{}
      result = R2Map.put(map, :name, "Alice")
      assert result == %{"name" => "Alice"}
      assert Map.has_key?(result, "name")
      refute Map.has_key?(result, :name)
    end

    test "puts value with string key" do
      map = %{}
      result = R2Map.put(map, "age", 30)
      assert result == %{"age" => 30}
    end

    test "puts value with integer key" do
      map = %{}
      result = R2Map.put(map, 1, "one")
      assert result == %{1 => "one"}
    end

    test "overwrites existing value with atom key" do
      map = %{"name" => "Alice"}
      result = R2Map.put(map, :name, "Bob")
      assert result == %{"name" => "Bob"}
    end

    test "overwrites existing value with string key" do
      map = %{name: "Alice"}
      result = R2Map.put(map, "name", "Bob")
      assert result == Map.merge(%{name: "Alice"}, %{"name" => "Bob"})
    end

    test "can put nil values" do
      map = %{}
      result = R2Map.put(map, :key, nil)
      assert result == %{"key" => nil}
      assert Map.has_key?(result, "key")
    end

    test "works with nested maps" do
      map = %{}
      result = R2Map.put(map, :nested, %{inner: "value"})
      assert result == %{"nested" => %{inner: "value"}}
    end
  end

  describe "Convert.to_float/1" do
    test "converts nil to 0.0" do
      assert Convert.to_float(nil) == 0.0
    end

    test "converts integer to float" do
      assert Convert.to_float(42) == 42.0
      assert Convert.to_float(0) == 0.0
      assert Convert.to_float(-10) == -10.0
    end

    test "keeps float as float" do
      assert Convert.to_float(3.14) == 3.14
      assert Convert.to_float(0.0) == 0.0
      assert Convert.to_float(-2.5) == -2.5
    end

    test "converts integer string to float" do
      assert Convert.to_float("42") == 42.0
      assert Convert.to_float("0") == 0.0
      assert Convert.to_float("-10") == -10.0
    end

    test "converts float string to float" do
      assert Convert.to_float("3.14") == 3.14
      assert Convert.to_float("0.0") == 0.0
      assert Convert.to_float("-2.5") == -2.5
    end

    test "converts invalid string to 0.0" do
      assert Convert.to_float("not a number") == 0.0
      assert Convert.to_float("abc") == 0.0
      assert Convert.to_float("") == 0.0
      assert Convert.to_float("12.34.56") == 0.0
    end

    test "handles whitespace in strings" do
      assert Convert.to_float("  42  ") == 0.0
      assert Convert.to_float(" ") == 0.0
    end
  end

  describe "Convert.to_integer/1" do
    test "converts nil to 0" do
      assert Convert.to_integer(nil) == 0
    end

    test "keeps integer as integer" do
      assert Convert.to_integer(42) == 42
      assert Convert.to_integer(0) == 0
      assert Convert.to_integer(-10) == -10
    end

    test "rounds float to integer" do
      assert Convert.to_integer(3.14) == 3
      assert Convert.to_integer(3.7) == 4
      assert Convert.to_integer(-2.3) == -2
      assert Convert.to_integer(-2.7) == -3
      assert Convert.to_integer(0.0) == 0
    end

    test "converts integer string to integer" do
      assert Convert.to_integer("42") == 42
      assert Convert.to_integer("0") == 0
      assert Convert.to_integer("-10") == -10
    end

    test "converts float string to integer" do
      assert Convert.to_integer("3.14") == 3
      assert Convert.to_integer("3.7") == 4
      assert Convert.to_integer("-2.5") == -3
    end

    test "converts invalid string to 0" do
      assert Convert.to_integer("not a number") == 0
      assert Convert.to_integer("abc") == 0
      assert Convert.to_integer("") == 0
      assert Convert.to_integer("12.34.56") == 0
    end

    test "handles whitespace in strings" do
      assert Convert.to_integer("  42  ") == 0
      assert Convert.to_integer(" ") == 0
    end
  end

  describe "JsonPath.get_value/2" do
    test "returns data when path is empty" do
      data = %{name: "Alice"}
      assert JsonPath.get_value(data, "") == {:ok, data}
    end

    test "gets simple string key from map" do
      data = %{"name" => "Alice"}
      assert JsonPath.get_value(data, "name") == {:ok, "Alice"}
    end

    test "gets simple atom key from map" do
      data = %{name: "Bob"}
      assert JsonPath.get_value(data, "name") == {:ok, "Bob"}
    end

    test "gets nested value from map" do
      data = %{
        "user" => %{
          "profile" => %{
            "name" => "Charlie"
          }
        }
      }
      assert JsonPath.get_value(data, "user.profile.name") == {:ok, "Charlie"}
    end

    test "gets nested value with mixed key types" do
      data = %{
        user: %{
          "profile" => %{
            name: "Dave"
          }
        }
      }
      assert JsonPath.get_value(data, "user.profile.name") == {:ok, "Dave"}
    end

    test "returns error when key not found" do
      data = %{name: "Eve"}
      assert JsonPath.get_value(data, "age") == {:error, :not_found}
    end

    test "returns error when nested key not found" do
      data = %{user: %{name: "Frank"}}
      assert JsonPath.get_value(data, "user.age") == {:error, :not_found}
      assert JsonPath.get_value(data, "user.profile.name") == {:error, :not_found}
    end

    test "gets value from array by index" do
      data = ["first", "second", "third"]
      assert JsonPath.get_value(data, "0") == {:ok, "first"}
      assert JsonPath.get_value(data, "1") == {:ok, "second"}
      assert JsonPath.get_value(data, "2") == {:ok, "third"}
    end

    test "returns error when array index out of bounds" do
      data = ["first", "second"]
      assert JsonPath.get_value(data, "5") == {:error, :not_found}
      assert JsonPath.get_value(data, "100") == {:error, :not_found}
    end

    test "gets nested value from array element" do
      data = [
        %{"name" => "Alice", "age" => 30},
        %{"name" => "Bob", "age" => 25}
      ]
      assert JsonPath.get_value(data, "0.name") == {:ok, "Alice"}
      assert JsonPath.get_value(data, "1.age") == {:ok, 25}
    end

    test "maps over array with [] notation" do
      data = [
        %{"name" => "Alice"},
        %{"name" => "Bob"},
        %{"name" => "Charlie"}
      ]
      assert JsonPath.get_value(data, "[].name") == {:ok, ["Alice", "Bob", "Charlie"]}
    end

    test "filters nil values when mapping over array" do
      data = [
        %{"name" => "Alice"},
        %{"age" => 30},
        %{"name" => "Bob"}
      ]
      assert JsonPath.get_value(data, "[].name") == {:ok, ["Alice", "Bob"]}
    end

    test "maps over nested arrays" do
      data = %{
        "users" => [
          %{"name" => "Alice", "age" => 30},
          %{"name" => "Bob", "age" => 25}
        ]
      }
      assert JsonPath.get_value(data, "users.[].name") == {:ok, ["Alice", "Bob"]}
    end

    test "handles deeply nested paths" do
      data = %{
        "level1" => %{
          "level2" => %{
            "level3" => %{
              "value" => "deep"
            }
          }
        }
      }
      assert JsonPath.get_value(data, "level1.level2.level3.value") == {:ok, "deep"}
    end

    test "handles array of arrays" do
      data = [
        [1, 2, 3],
        [4, 5, 6]
      ]
      assert JsonPath.get_value(data, "0.1") == {:ok, 2}
      assert JsonPath.get_value(data, "1.2") == {:ok, 6}
    end

    test "returns error for invalid array index" do
      data = ["first", "second"]
      assert JsonPath.get_value(data, "not_a_number") == {:ok, {:error, :not_found}}
    end

    test "handles nil values in path" do
      data = %{user: nil}
      assert JsonPath.get_value(data, "user.name") == {:error, :not_found}
    end

    test "handles non-map non-list values in path" do
      data = %{value: "string"}
      assert JsonPath.get_value(data, "value.invalid") == {:ok, "string"}
    end

    test "handles empty array" do
      data = []
      assert JsonPath.get_value(data, "0") == {:error, :not_found}
      assert JsonPath.get_value(data, "[].name") == {:ok, []}
    end

    test "handles complex mixed structure" do
      data = %{
        "company" => %{
          "departments" => [
            %{
              "name" => "Engineering",
              "employees" => [
                %{"name" => "Alice", "role" => "Engineer"},
                %{"name" => "Bob", "role" => "Manager"}
              ]
            },
            %{
              "name" => "Sales",
              "employees" => [
                %{"name" => "Charlie", "role" => "Rep"}
              ]
            }
          ]
        }
      }

      assert JsonPath.get_value(data, "company.departments.0.name") == {:ok, "Engineering"}
      assert JsonPath.get_value(data, "company.departments.0.employees.1.name") == {:ok, "Bob"}
      assert JsonPath.get_value(data, "company.departments.[].name") == {:ok, ["Engineering", "Sales"]}
    end

    test "handles negative array indices" do
      data = ["first", "second", "third"]
      assert JsonPath.get_value(data, "-1") == {:ok, "third"}
      assert JsonPath.get_value(data, "-2") == {:ok, "second"}
    end
  end
end
