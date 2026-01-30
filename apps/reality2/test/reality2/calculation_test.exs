defmodule Reality2.CalculationTest do
  use ExUnit.Case, async: true

  alias Reality2.Calculation

  describe "passthrough values" do
    test "nil returns nil" do
      assert Calculation.calculate(nil, %{}) == nil
    end

    test "integers pass through unchanged" do
      assert Calculation.calculate(42, %{}) == 42
      assert Calculation.calculate(0, %{}) == 0
      assert Calculation.calculate(-10, %{}) == -10
    end

    test "floats pass through unchanged" do
      assert Calculation.calculate(3.14, %{}) == 3.14
      assert Calculation.calculate(-2.5, %{}) == -2.5
      assert Calculation.calculate(0.0, %{}) == 0.0
    end

    test "booleans pass through unchanged" do
      assert Calculation.calculate(true, %{}) == true
      assert Calculation.calculate(false, %{}) == false
    end

    test "string 'true' converts to boolean true" do
      assert Calculation.calculate("true", %{}) == true
    end

    test "string 'false' converts to boolean false" do
      assert Calculation.calculate("false", %{}) == false
    end
  end

  describe "variable lookup" do
    test "returns variable value when found in vars map" do
      vars = %{"x" => 10, "name" => "Alice", "flag" => true}

      assert Calculation.calculate("x", vars) == 10
      assert Calculation.calculate("name", vars) == "Alice"
      assert Calculation.calculate("flag", vars) == true
    end

    test "returns string as-is when variable not found" do
      vars = %{"x" => 10}

      assert Calculation.calculate("unknown", vars) == "unknown"
      assert Calculation.calculate("y", vars) == "y"
    end

    test "returns string as-is with empty vars map" do
      assert Calculation.calculate("somevar", %{}) == "somevar"
    end
  end

  describe "binary arithmetic operations" do
    test "addition with numbers" do
      assert Calculation.calculate(%{"+" => [5, 3]}, %{}) == 8
      assert Calculation.calculate(%{"+" => [2.5, 1.5]}, %{}) == 4.0
      assert Calculation.calculate(%{"+" => [-10, 5]}, %{}) == -5
    end

    test "subtraction with numbers" do
      assert Calculation.calculate(%{"-" => [10, 3]}, %{}) == 7
      assert Calculation.calculate(%{"-" => [5.5, 2.5]}, %{}) == 3.0
      assert Calculation.calculate(%{"-" => [0, 5]}, %{}) == -5
    end

    test "multiplication with numbers" do
      assert Calculation.calculate(%{"*" => [4, 5]}, %{}) == 20
      assert Calculation.calculate(%{"*" => [2.5, 2]}, %{}) == 5.0
      assert Calculation.calculate(%{"*" => [-3, 4]}, %{}) == -12
    end

    test "division with numbers" do
      assert Calculation.calculate(%{"/" => [10, 2]}, %{}) == 5.0
      assert Calculation.calculate(%{"/" => [7, 2]}, %{}) == 3.5
      assert Calculation.calculate(%{"/" => [1, 4]}, %{}) == 0.25
    end

    test "division by literal zero returns nil" do
      assert Calculation.calculate(%{"/" => [10, 0]}, %{}) == nil
      assert Calculation.calculate(%{"/" => [0, 0]}, %{}) == nil
    end

    test "power operation" do
      assert Calculation.calculate(%{"^" => [2, 3]}, %{}) == 8.0
      assert Calculation.calculate(%{"^" => [5, 2]}, %{}) == 25.0
      assert Calculation.calculate(%{"^" => [2, 0]}, %{}) == 1.0
    end

    test "pow operation (alias for ^)" do
      assert Calculation.calculate(%{"pow" => [2, 3]}, %{}) == 8.0
      assert Calculation.calculate(%{"pow" => [10, 2]}, %{}) == 100.0
    end

    test "atan2 operation" do
      result = Calculation.calculate(%{"atan2" => [1, 1]}, %{})
      assert_in_delta result, :math.pi() / 4, 0.0001
    end

    test "fmod operation" do
      assert Calculation.calculate(%{"fmod" => [7, 3]}, %{}) == 1.0
      assert Calculation.calculate(%{"fmod" => [5.5, 2]}, %{}) == 1.5
    end
  end

  describe "string concatenation with +" do
    test "concatenates two strings" do
      assert Calculation.calculate(%{"+" => ["hello", "world"]}, %{}) == "helloworld"
      assert Calculation.calculate(%{"+" => ["foo", "bar"]}, %{}) == "foobar"
    end

    test "concatenates number and string" do
      assert Calculation.calculate(%{"+" => [10, "px"]}, %{}) == "10px"
      assert Calculation.calculate(%{"+" => ["value:", 42]}, %{}) == "value:42"
    end

    test "concatenates mixed types" do
      assert Calculation.calculate(%{"+" => [true, "value"]}, %{}) == "truevalue"
      assert Calculation.calculate(%{"+" => ["flag:", false]}, %{}) == "flag:false"
    end
  end

  describe "comparison operations" do
    test "equality ==" do
      assert Calculation.calculate(%{"==" => [5, 5]}, %{}) == true
      assert Calculation.calculate(%{"==" => [5, 3]}, %{}) == false
      assert Calculation.calculate(%{"==" => ["abc", "abc"]}, %{}) == true
      assert Calculation.calculate(%{"==" => ["abc", "def"]}, %{}) == false
    end

    test "inequality !=" do
      assert Calculation.calculate(%{"!=" => [5, 3]}, %{}) == true
      assert Calculation.calculate(%{"!=" => [5, 5]}, %{}) == false
      assert Calculation.calculate(%{"!=" => ["abc", "def"]}, %{}) == true
    end

    test "greater than >" do
      assert Calculation.calculate(%{">" => [10, 5]}, %{}) == true
      assert Calculation.calculate(%{">" => [5, 10]}, %{}) == false
      assert Calculation.calculate(%{">" => [5, 5]}, %{}) == false
    end

    test "less than <" do
      assert Calculation.calculate(%{"<" => [5, 10]}, %{}) == true
      assert Calculation.calculate(%{"<" => [10, 5]}, %{}) == false
      assert Calculation.calculate(%{"<" => [5, 5]}, %{}) == false
    end

    test "greater than or equal >=" do
      assert Calculation.calculate(%{">=" => [10, 5]}, %{}) == true
      assert Calculation.calculate(%{">=" => [5, 5]}, %{}) == true
      assert Calculation.calculate(%{">=" => [3, 5]}, %{}) == false
    end

    test "less than or equal <=" do
      assert Calculation.calculate(%{"<=" => [5, 10]}, %{}) == true
      assert Calculation.calculate(%{"<=" => [5, 5]}, %{}) == true
      assert Calculation.calculate(%{"<=" => [10, 5]}, %{}) == false
    end
  end

  describe "logical operations" do
    test "logical AND &&" do
      assert Calculation.calculate(%{"&&" => [true, true]}, %{}) == true
      assert Calculation.calculate(%{"&&" => [true, false]}, %{}) == false
      assert Calculation.calculate(%{"&&" => [false, true]}, %{}) == false
      assert Calculation.calculate(%{"&&" => [false, false]}, %{}) == false
    end

    test "logical OR ||" do
      assert Calculation.calculate(%{"||" => [true, true]}, %{}) == true
      assert Calculation.calculate(%{"||" => [true, false]}, %{}) == true
      assert Calculation.calculate(%{"||" => [false, true]}, %{}) == true
      assert Calculation.calculate(%{"||" => [false, false]}, %{}) == false
    end

    test "logical NOT !" do
      assert Calculation.calculate(%{"!" => true}, %{}) == false
      assert Calculation.calculate(%{"!" => false}, %{}) == true
    end
  end

  describe "unary operations" do
    test "unary plus +" do
      assert Calculation.calculate(%{"+" => 5}, %{}) == 5
      assert Calculation.calculate(%{"+" => -3}, %{}) == -3
      assert Calculation.calculate(%{"+" => 0}, %{}) == 0
    end

    test "unary minus -" do
      assert Calculation.calculate(%{"-" => 5}, %{}) == -5
      assert Calculation.calculate(%{"-" => -3}, %{}) == 3
      assert Calculation.calculate(%{"-" => 0}, %{}) == 0
    end
  end

  describe "trigonometric functions" do
    test "sin" do
      result = Calculation.calculate(%{"sin" => 0}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"sin" => :math.pi() / 2}, %{})
      assert_in_delta result, 1.0, 0.0001
    end

    test "cos" do
      result = Calculation.calculate(%{"cos" => 0}, %{})
      assert_in_delta result, 1.0, 0.0001

      result = Calculation.calculate(%{"cos" => :math.pi()}, %{})
      assert_in_delta result, -1.0, 0.0001
    end

    test "tan" do
      result = Calculation.calculate(%{"tan" => 0}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"tan" => :math.pi() / 4}, %{})
      assert_in_delta result, 1.0, 0.0001
    end

    test "asin" do
      result = Calculation.calculate(%{"asin" => 0}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"asin" => 1}, %{})
      assert_in_delta result, :math.pi() / 2, 0.0001
    end

    test "acos" do
      result = Calculation.calculate(%{"acos" => 1}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"acos" => 0}, %{})
      assert_in_delta result, :math.pi() / 2, 0.0001
    end

    test "atan" do
      result = Calculation.calculate(%{"atan" => 0}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"atan" => 1}, %{})
      assert_in_delta result, :math.pi() / 4, 0.0001
    end
  end

  describe "hyperbolic functions" do
    test "sinh" do
      result = Calculation.calculate(%{"sinh" => 0}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"sinh" => 1}, %{})
      assert_in_delta result, 1.1752011936438014, 0.0001
    end

    test "cosh" do
      result = Calculation.calculate(%{"cosh" => 0}, %{})
      assert_in_delta result, 1.0, 0.0001

      result = Calculation.calculate(%{"cosh" => 1}, %{})
      assert_in_delta result, 1.5430806348152437, 0.0001
    end

    test "tanh" do
      result = Calculation.calculate(%{"tanh" => 0}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"tanh" => 1}, %{})
      assert_in_delta result, 0.7615941559557649, 0.0001
    end

    test "asinh" do
      result = Calculation.calculate(%{"asinh" => 0}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"asinh" => 1}, %{})
      assert_in_delta result, 0.881373587019543, 0.0001
    end

    test "acosh" do
      result = Calculation.calculate(%{"acosh" => 1}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"acosh" => 2}, %{})
      assert_in_delta result, 1.3169578969248166, 0.0001
    end

    test "atanh" do
      result = Calculation.calculate(%{"atanh" => 0}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"atanh" => 0.5}, %{})
      assert_in_delta result, 0.5493061443340548, 0.0001
    end
  end

  describe "exponential and logarithmic functions" do
    test "exp" do
      result = Calculation.calculate(%{"exp" => 0}, %{})
      assert_in_delta result, 1.0, 0.0001

      result = Calculation.calculate(%{"exp" => 1}, %{})
      assert_in_delta result, :math.exp(1), 0.0001

      result = Calculation.calculate(%{"exp" => 2}, %{})
      assert_in_delta result, :math.exp(2), 0.0001
    end

    test "log (natural logarithm)" do
      result = Calculation.calculate(%{"log" => 1}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"log" => :math.exp(1)}, %{})
      assert_in_delta result, 1.0, 0.0001
    end

    test "log10 (base 10 logarithm)" do
      result = Calculation.calculate(%{"log10" => 1}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"log10" => 10}, %{})
      assert_in_delta result, 1.0, 0.0001

      result = Calculation.calculate(%{"log10" => 100}, %{})
      assert_in_delta result, 2.0, 0.0001
    end

    test "log2 (base 2 logarithm)" do
      result = Calculation.calculate(%{"log2" => 1}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"log2" => 2}, %{})
      assert_in_delta result, 1.0, 0.0001

      result = Calculation.calculate(%{"log2" => 8}, %{})
      assert_in_delta result, 3.0, 0.0001
    end

    test "sqrt" do
      assert Calculation.calculate(%{"sqrt" => 4}, %{}) == 2.0
      assert Calculation.calculate(%{"sqrt" => 9}, %{}) == 3.0
      assert Calculation.calculate(%{"sqrt" => 0}, %{}) == 0.0

      result = Calculation.calculate(%{"sqrt" => 2}, %{})
      assert_in_delta result, 1.4142135623730951, 0.0001
    end
  end

  describe "rounding functions" do
    test "ceil" do
      assert Calculation.calculate(%{"ceil" => 3.2}, %{}) == 4.0
      assert Calculation.calculate(%{"ceil" => 3.8}, %{}) == 4.0
      assert Calculation.calculate(%{"ceil" => -3.2}, %{}) == -3.0
      assert Calculation.calculate(%{"ceil" => 5.0}, %{}) == 5.0
    end

    test "floor" do
      assert Calculation.calculate(%{"floor" => 3.2}, %{}) == 3.0
      assert Calculation.calculate(%{"floor" => 3.8}, %{}) == 3.0
      assert Calculation.calculate(%{"floor" => -3.2}, %{}) == -4.0
      assert Calculation.calculate(%{"floor" => 5.0}, %{}) == 5.0
    end
  end

  describe "nil propagation" do
    test "binary operations with nil left operand return nil" do
      assert Calculation.calculate(%{"+" => [nil, 5]}, %{}) == nil
      assert Calculation.calculate(%{"-" => [nil, 5]}, %{}) == nil
      assert Calculation.calculate(%{"*" => [nil, 5]}, %{}) == nil
      assert Calculation.calculate(%{"/" => [nil, 5]}, %{}) == nil
    end

    test "binary operations with nil right operand return nil" do
      assert Calculation.calculate(%{"+" => [5, nil]}, %{}) == nil
      assert Calculation.calculate(%{"-" => [5, nil]}, %{}) == nil
      assert Calculation.calculate(%{"*" => [5, nil]}, %{}) == nil
      assert Calculation.calculate(%{"/" => [5, nil]}, %{}) == nil
    end

    test "binary operations with both operands nil return nil" do
      assert Calculation.calculate(%{"+" => [nil, nil]}, %{}) == nil
      assert Calculation.calculate(%{"-" => [nil, nil]}, %{}) == nil
    end

    test "unary operations with nil operand return nil" do
      assert Calculation.calculate(%{"-" => nil}, %{}) == nil
      assert Calculation.calculate(%{"!" => nil}, %{}) == nil
      assert Calculation.calculate(%{"sin" => nil}, %{}) == nil
      assert Calculation.calculate(%{"sqrt" => nil}, %{}) == nil
    end

    test "comparison operations with nil return nil" do
      assert Calculation.calculate(%{"==" => [nil, 5]}, %{}) == nil
      assert Calculation.calculate(%{">" => [5, nil]}, %{}) == nil
      assert Calculation.calculate(%{"<" => [nil, nil]}, %{}) == nil
    end
  end

  describe "string number auto-conversion" do
    test "string numbers are converted in binary operations" do
      assert Calculation.calculate(%{"+" => ["3.14", "2.86"]}, %{}) == 6.0
      assert Calculation.calculate(%{"-" => ["10", "3"]}, %{}) == 7.0
      assert Calculation.calculate(%{"*" => ["4", "5"]}, %{}) == 20.0
      assert Calculation.calculate(%{"/" => ["10", "2"]}, %{}) == 5.0
    end

    test "string numbers are converted in unary operations" do
      assert Calculation.calculate(%{"-" => "5"}, %{}) == -5.0
      assert Calculation.calculate(%{"+" => "3.14"}, %{}) == 3.14

      result = Calculation.calculate(%{"sqrt" => "16"}, %{})
      assert_in_delta result, 4.0, 0.0001
    end

    test "special constant 'pi' is recognized" do
      result = Calculation.calculate(%{"sin" => "pi"}, %{})
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"*" => ["2", "pi"]}, %{})
      assert_in_delta result, 2 * :math.pi(), 0.0001
    end

    test "special constant 'e' is recognized" do
      result = Calculation.calculate(%{"log" => "e"}, %{})
      assert_in_delta result, 1.0, 0.0001

      result = Calculation.calculate(%{"*" => ["2", "e"]}, %{})
      assert_in_delta result, 2 * 2.7182818284590452353602874713527, 0.0001
    end
  end

  describe "nested expressions" do
    test "nested binary operations" do
      # (5 + 3) * 2 = 16
      expr = %{"*" => [%{"+" => [5, 3]}, 2]}
      assert Calculation.calculate(expr, %{}) == 16.0
    end

    test "deeply nested operations" do
      # ((10 - 2) / 2) + 1 = 5
      expr = %{"+" => [%{"/" => [%{"-" => [10, 2]}, 2]}, 1]}
      assert Calculation.calculate(expr, %{}) == 5.0
    end

    test "nested with unary operations" do
      # sqrt(16) + (-2) = 2
      expr = %{"+" => [%{"sqrt" => 16}, %{"-" => 2}]}
      assert Calculation.calculate(expr, %{}) == 2.0
    end

    test "nested with variables" do
      # x + (y * 2) where x=5, y=3 = 11
      vars = %{"x" => 5, "y" => 3}
      expr = %{"+" => ["x", %{"*" => ["y", 2]}]}
      assert Calculation.calculate(expr, vars) == 11.0
    end

    test "complex nested expression with multiple operations" do
      # sqrt((3^2) + (4^2)) = 5 (Pythagorean theorem)
      expr = %{"sqrt" => %{"+" => [%{"^" => [3, 2]}, %{"^" => [4, 2]}]}}
      result = Calculation.calculate(expr, %{})
      assert_in_delta result, 5.0, 0.0001
    end
  end

  describe "variables with operations" do
    test "binary operations with variables" do
      vars = %{"a" => 10, "b" => 5}

      assert Calculation.calculate(%{"+" => ["a", "b"]}, vars) == 15.0
      assert Calculation.calculate(%{"-" => ["a", "b"]}, vars) == 5.0
      assert Calculation.calculate(%{"*" => ["a", "b"]}, vars) == 50.0
      assert Calculation.calculate(%{"/" => ["a", "b"]}, vars) == 2.0
    end

    test "unary operations with variables" do
      vars = %{"x" => 5, "y" => -3}

      assert Calculation.calculate(%{"-" => "x"}, vars) == -5.0
      assert Calculation.calculate(%{"-" => "y"}, vars) == 3.0
    end

    test "math functions with variables" do
      vars = %{"angle" => 0, "value" => 16}

      result = Calculation.calculate(%{"sin" => "angle"}, vars)
      assert_in_delta result, 0.0, 0.0001

      result = Calculation.calculate(%{"sqrt" => "value"}, vars)
      assert_in_delta result, 4.0, 0.0001
    end

    test "comparison with variables" do
      vars = %{"x" => 10, "y" => 5, "z" => 10}

      assert Calculation.calculate(%{">" => ["x", "y"]}, vars) == true
      assert Calculation.calculate(%{"<" => ["x", "y"]}, vars) == false
      assert Calculation.calculate(%{"==" => ["x", "z"]}, vars) == true
    end
  end

  describe "edge cases" do
    test "operations with zero" do
      assert Calculation.calculate(%{"+" => [0, 0]}, %{}) == 0.0
      assert Calculation.calculate(%{"-" => [0, 0]}, %{}) == 0.0
      assert Calculation.calculate(%{"*" => [5, 0]}, %{}) == 0.0
      assert Calculation.calculate(%{"*" => [0, 5]}, %{}) == 0.0
    end

    test "operations with negative numbers" do
      assert Calculation.calculate(%{"+" => [-5, -3]}, %{}) == -8.0
      assert Calculation.calculate(%{"-" => [-5, -3]}, %{}) == -2.0
      assert Calculation.calculate(%{"*" => [-5, -3]}, %{}) == 15.0
      assert Calculation.calculate(%{"/" => [-10, -2]}, %{}) == 5.0
    end

    test "very small numbers" do
      result = Calculation.calculate(%{"+" => [0.0001, 0.0002]}, %{})
      assert_in_delta result, 0.0003, 0.000001
    end

    test "very large numbers" do
      result = Calculation.calculate(%{"+" => [1_000_000, 2_000_000]}, %{})
      assert result == 3_000_000.0
    end

    test "mixed integers and floats" do
      assert Calculation.calculate(%{"+" => [5, 2.5]}, %{}) == 7.5
      assert Calculation.calculate(%{"*" => [3, 1.5]}, %{}) == 4.5
    end
  end

  describe "logical operations with truthy/falsy values" do
    test "logical AND with truthy values" do
      assert Calculation.calculate(%{"&&" => [1, 2]}, %{}) == 2
      assert Calculation.calculate(%{"&&" => ["a", "b"]}, %{}) == "b"
      assert Calculation.calculate(%{"&&" => [true, "value"]}, %{}) == "value"
    end

    test "logical AND with falsy values" do
      assert Calculation.calculate(%{"&&" => [false, "value"]}, %{}) == false
      assert Calculation.calculate(%{"&&" => [nil, "value"]}, %{}) == nil
    end

    test "logical OR with truthy values" do
      assert Calculation.calculate(%{"||" => [false, "default"]}, %{}) == "default"
      # nil operand is caught by binaryop/3 nil guard → returns nil
      assert Calculation.calculate(%{"||" => [nil, "default"]}, %{}) == nil
      assert Calculation.calculate(%{"||" => [true, "default"]}, %{}) == true
    end
  end
end
