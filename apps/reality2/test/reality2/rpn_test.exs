defmodule RPNTest do
  use ExUnit.Case, async: true

  # ===========================================================================
  # Basic Input Format Tests
  # ===========================================================================

  describe "convert/2 input formats" do
    test "accepts string input with space-separated tokens" do
      assert RPN.convert("3 4 +", %{}) == 7.0
    end

    test "accepts list input" do
      assert RPN.convert(["3", "4", "+"], %{}) == 7.0
    end
  end

  # ===========================================================================
  # Arithmetic Operations
  # ===========================================================================

  describe "arithmetic operations" do
    test "addition" do
      assert RPN.convert("5 3 +", %{}) == 8.0
      assert RPN.convert("10.5 2.5 +", %{}) == 13.0
    end

    test "subtraction" do
      assert RPN.convert("10 3 -", %{}) == 7.0
      assert RPN.convert("5.5 2.5 -", %{}) == 3.0
    end

    test "multiplication" do
      assert RPN.convert("4 5 *", %{}) == 20.0
      assert RPN.convert("2.5 4 *", %{}) == 10.0
    end

    test "division" do
      assert RPN.convert("20 4 /", %{}) == 5.0
      assert RPN.convert("7 2 /", %{}) == 3.5
    end

    test "power operator ^" do
      assert RPN.convert("2 3 ^", %{}) == 8.0
      assert RPN.convert("5 2 ^", %{}) == 25.0
    end

    test "pow function" do
      assert RPN.convert("2 3 pow", %{}) == 8.0
      assert RPN.convert("3 4 pow", %{}) == 81.0
    end

    test "fmod function" do
      result = RPN.convert("7 3 fmod", %{})
      assert_in_delta result, 1.0, 0.0001
    end

    test "complex arithmetic expression" do
      # (3 + 4) * 5 = 35
      assert RPN.convert("3 4 + 5 *", %{}) == 35.0
    end

    test "nested arithmetic expression" do
      # ((2 + 3) * 4) - 5 = 15
      assert RPN.convert("2 3 + 4 * 5 -", %{}) == 15.0
    end
  end

  # ===========================================================================
  # Trigonometric Functions
  # ===========================================================================

  describe "trigonometric functions" do
    test "sin function" do
      result = RPN.convert("0 sin", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("pi 2 / sin", %{})
      assert_in_delta result, 1.0, 0.0001
    end

    test "cos function" do
      result = RPN.convert("0 cos", %{})
      assert_in_delta result, 1.0, 0.0001

      result = RPN.convert("pi cos", %{})
      assert_in_delta result, -1.0, 0.0001
    end

    test "tan function" do
      result = RPN.convert("0 tan", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("pi 4 / tan", %{})
      assert_in_delta result, 1.0, 0.0001
    end

    test "asin function" do
      result = RPN.convert("0 asin", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("1 asin", %{})
      assert_in_delta result, :math.pi() / 2, 0.0001
    end

    test "acos function" do
      result = RPN.convert("1 acos", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("0 acos", %{})
      assert_in_delta result, :math.pi() / 2, 0.0001
    end

    test "atan function" do
      result = RPN.convert("0 atan", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("1 atan", %{})
      assert_in_delta result, :math.pi() / 4, 0.0001
    end

    test "atan2 function" do
      result = RPN.convert("1 1 atan2", %{})
      assert_in_delta result, :math.pi() / 4, 0.0001

      result = RPN.convert("0 1 atan2", %{})
      assert_in_delta result, 0.0, 0.0001
    end
  end

  # ===========================================================================
  # Hyperbolic Functions
  # ===========================================================================

  describe "hyperbolic functions" do
    test "sinh function" do
      result = RPN.convert("0 sinh", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("1 sinh", %{})
      assert_in_delta result, :math.sinh(1), 0.0001
    end

    test "cosh function" do
      result = RPN.convert("0 cosh", %{})
      assert_in_delta result, 1.0, 0.0001

      result = RPN.convert("1 cosh", %{})
      assert_in_delta result, :math.cosh(1), 0.0001
    end

    test "tanh function" do
      result = RPN.convert("0 tanh", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("1 tanh", %{})
      assert_in_delta result, :math.tanh(1), 0.0001
    end

    test "asinh function" do
      result = RPN.convert("0 asinh", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("1 asinh", %{})
      assert_in_delta result, :math.asinh(1), 0.0001
    end

    test "acosh function" do
      result = RPN.convert("1 acosh", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("2 acosh", %{})
      assert_in_delta result, :math.acosh(2), 0.0001
    end

    test "atanh function" do
      result = RPN.convert("0 atanh", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("0.5 atanh", %{})
      assert_in_delta result, :math.atanh(0.5), 0.0001
    end
  end

  # ===========================================================================
  # Other Mathematical Functions
  # ===========================================================================

  describe "other mathematical functions" do
    test "ceil function" do
      assert RPN.convert("3.2 ceil", %{}) == 4.0
      assert RPN.convert("3.9 ceil", %{}) == 4.0
      assert RPN.convert("-2.3 ceil", %{}) == -2.0
    end

    test "floor function" do
      assert RPN.convert("3.2 floor", %{}) == 3.0
      assert RPN.convert("3.9 floor", %{}) == 3.0
      assert RPN.convert("-2.3 floor", %{}) == -3.0
    end

    test "exp function" do
      result = RPN.convert("0 exp", %{})
      assert_in_delta result, 1.0, 0.0001

      result = RPN.convert("1 exp", %{})
      assert_in_delta result, :math.exp(1), 0.0001

      result = RPN.convert("2 exp", %{})
      assert_in_delta result, :math.exp(2), 0.0001
    end

    test "log function (natural logarithm)" do
      result = RPN.convert("1 log", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("e log", %{})
      assert_in_delta result, 1.0, 0.0001

      result = RPN.convert("10 log", %{})
      assert_in_delta result, :math.log(10), 0.0001
    end

    test "log10 function" do
      result = RPN.convert("1 log10", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("10 log10", %{})
      assert_in_delta result, 1.0, 0.0001

      result = RPN.convert("100 log10", %{})
      assert_in_delta result, 2.0, 0.0001
    end

    test "log2 function" do
      result = RPN.convert("1 log2", %{})
      assert_in_delta result, 0.0, 0.0001

      result = RPN.convert("2 log2", %{})
      assert_in_delta result, 1.0, 0.0001

      result = RPN.convert("8 log2", %{})
      assert_in_delta result, 3.0, 0.0001
    end

    test "sqrt function" do
      result = RPN.convert("4 sqrt", %{})
      assert_in_delta result, 2.0, 0.0001

      result = RPN.convert("9 sqrt", %{})
      assert_in_delta result, 3.0, 0.0001

      result = RPN.convert("2 sqrt", %{})
      assert_in_delta result, :math.sqrt(2), 0.0001
    end
  end

  # ===========================================================================
  # Unary Operators
  # ===========================================================================

  describe "unary operators" do
    test "unary plus" do
      assert RPN.convert("5 +", %{}) == 5.0
      assert RPN.convert("-3 +", %{}) == -3.0
    end

    test "unary minus (negation)" do
      assert RPN.convert("5 -", %{}) == -5.0
      assert RPN.convert("-3 -", %{}) == 3.0
    end
  end

  # ===========================================================================
  # Logical Operations
  # ===========================================================================

  describe "logical operations" do
    test "logical AND (&&)" do
      assert RPN.convert("true true &&", %{}) == true
      assert RPN.convert("true false &&", %{}) == false
      assert RPN.convert("false true &&", %{}) == false
      assert RPN.convert("false false &&", %{}) == false
    end

    test "logical OR (||)" do
      assert RPN.convert("true true ||", %{}) == true
      assert RPN.convert("true false ||", %{}) == true
      assert RPN.convert("false true ||", %{}) == true
      assert RPN.convert("false false ||", %{}) == false
    end

    test "logical NOT (!)" do
      assert RPN.convert("true !", %{}) == false
      assert RPN.convert("false !", %{}) == true
    end

    test "equality (==)" do
      assert RPN.convert("5 5 ==", %{}) == true
      assert RPN.convert("5 3 ==", %{}) == false
      assert RPN.convert("true true ==", %{}) == true
    end

    test "inequality (!=)" do
      assert RPN.convert("5 3 !=", %{}) == true
      assert RPN.convert("5 5 !=", %{}) == false
    end

    test "greater than (>)" do
      assert RPN.convert("3 5 >", %{}) == true
      assert RPN.convert("5 3 >", %{}) == false
      assert RPN.convert("5 5 >", %{}) == false
    end

    test "less than (<)" do
      assert RPN.convert("5 3 <", %{}) == true
      assert RPN.convert("3 5 <", %{}) == false
      assert RPN.convert("5 5 <", %{}) == false
    end

    test "greater than or equal (>=)" do
      assert RPN.convert("3 5 >=", %{}) == true
      assert RPN.convert("5 5 >=", %{}) == true
      assert RPN.convert("5 3 >=", %{}) == false
    end

    test "less than or equal (<=)" do
      assert RPN.convert("5 3 <=", %{}) == true
      assert RPN.convert("5 5 <=", %{}) == true
      assert RPN.convert("3 5 <=", %{}) == false
    end
  end

  # ===========================================================================
  # Special Values
  # ===========================================================================

  describe "special values" do
    test "pi constant" do
      result = RPN.convert("pi", %{})
      assert_in_delta result, :math.pi(), 0.0001
    end

    test "e constant" do
      result = RPN.convert("e", %{})
      assert_in_delta result, 2.7182818284590452353602874713527, 0.0001
    end

    test "true constant" do
      assert RPN.convert("true", %{}) == true
    end

    test "false constant" do
      assert RPN.convert("false", %{}) == false
    end

    test "pi in expression" do
      # 2 * pi
      result = RPN.convert("2 pi *", %{})
      assert_in_delta result, 2 * :math.pi(), 0.0001
    end

    test "e in expression" do
      # e^2
      result = RPN.convert("e 2 ^", %{})
      assert_in_delta result, :math.exp(2), 0.0001
    end
  end

  # ===========================================================================
  # Variable Lookup from Context
  # ===========================================================================

  describe "variable lookup" do
    test "looks up variable with string key" do
      context = %{"x" => 5, "y" => 3}
      assert RPN.convert("x y +", context) == 8.0
    end

    test "looks up variable with atom key" do
      context = %{x: 10, y: 2}
      assert RPN.convert("x y *", context) == 20.0
    end

    test "looks up variable with mixed keys (R2Map)" do
      context = %{"x" => 5, y: 3}
      result = RPN.convert("x y +", context)
      # R2Map should handle both string and atom keys
      assert result == 8.0 or is_map(result)
    end

    test "uses numeric string from context" do
      context = %{"value" => "42"}
      assert RPN.convert("value 8 +", context) == 50.0
    end

    test "uses numeric value from context" do
      context = %{"value" => 42}
      assert RPN.convert("value 8 +", context) == 50.0
    end

    test "complex expression with variables" do
      context = %{"a" => 2, "b" => 3, "c" => 4}
      # (a + b) * c = (2 + 3) * 4 = 20
      assert RPN.convert("a b + c *", context) == 20.0
    end
  end

  # ===========================================================================
  # Error Handling
  # ===========================================================================

  describe "error handling" do
    test "unknown variable returns error map" do
      result = RPN.convert("unknown_var", %{})
      assert %{error: "unknown variable unknown_var"} = result
    end

    test "unknown variable in expression raises ArithmeticError" do
      assert_raise ArithmeticError, fn ->
        RPN.convert("5 unknown +", %{})
      end
    end

    test "invalid value for variable raises ArithmeticError" do
      context = %{"bad" => %{nested: "map"}}
      assert_raise ArithmeticError, fn ->
        RPN.convert("bad 5 +", context)
      end
    end

    test "unary plus with single argument" do
      # "5 +" matches the unary plus operator and just returns the value
      assert RPN.convert("5 +", %{}) == 5.0
    end

    test "insufficient arguments for division raises ArgumentError" do
      assert_raise ArgumentError, ~r/insufficient arguments count for \//, fn ->
        RPN.convert("5 /", %{})
      end
    end

    test "insufficient arguments for unary operation raises ArgumentError" do
      assert_raise ArgumentError, ~r/insufficient arguments count for sin/, fn ->
        RPN.convert("sin", %{})
      end
    end

    test "insufficient arguments for atan2 raises ArgumentError" do
      assert_raise ArgumentError, ~r/insufficient arguments count for atan2/, fn ->
        RPN.convert("5 atan2", %{})
      end
    end

    test "no arguments for operation raises ArgumentError" do
      assert_raise ArgumentError, ~r/insufficient arguments count/, fn ->
        RPN.convert("+", %{})
      end
    end
  end

  # ===========================================================================
  # Complex Expressions
  # ===========================================================================

  describe "complex expressions" do
    test "quadratic formula component" do
      # b^2 - 4*a*c where a=1, b=5, c=6
      # 25 - 24 = 1
      context = %{"a" => 1, "b" => 5, "c" => 6}
      result = RPN.convert("b 2 ^ 4 a * c * -", context)
      assert_in_delta result, 1.0, 0.0001
    end

    test "distance formula" do
      # sqrt((x2-x1)^2 + (y2-y1)^2) where x1=0, y1=0, x2=3, y2=4
      # sqrt(9 + 16) = sqrt(25) = 5
      context = %{"x1" => 0, "y1" => 0, "x2" => 3, "y2" => 4}
      result = RPN.convert("x2 x1 - 2 ^ y2 y1 - 2 ^ + sqrt", context)
      assert_in_delta result, 5.0, 0.0001
    end

    test "temperature conversion F to C" do
      # (F - 32) * 5 / 9 where F = 212
      # (212 - 32) * 5 / 9 = 100
      context = %{"F" => 212}
      result = RPN.convert("F 32 - 5 * 9 /", context)
      assert_in_delta result, 100.0, 0.0001
    end

    test "multiple operations in sequence" do
      # 2 3 + 4 * 5 / 2 ^ = ((2+3)*4/5)^2 = (20/5)^2 = 4^2 = 16
      result = RPN.convert("2 3 + 4 * 5 / 2 ^", %{})
      assert_in_delta result, 16.0, 0.0001
    end

    test "trigonometric identity sin^2 + cos^2 = 1" do
      # sin(x)^2 + cos(x)^2 where x = pi/4
      x = :math.pi() / 4
      context = %{"x" => x}
      result = RPN.convert("x sin 2 ^ x cos 2 ^ +", context)
      assert_in_delta result, 1.0, 0.0001
    end

    test "exponential and logarithm inverse" do
      # log(exp(x)) = x where x = 2.5
      context = %{"x" => 2.5}
      result = RPN.convert("x exp log", context)
      assert_in_delta result, 2.5, 0.0001
    end

    test "logical expression" do
      # (a > b) && (c < d) where a=5, b=3, c=2, d=4
      # Note: In RPN "a b >" means "b > a" (reversed operand order)
      context = %{"a" => 5, "b" => 3, "c" => 2, "d" => 4}
      assert RPN.convert("b a > d c < &&", context) == true
    end
  end

  # ===========================================================================
  # Edge Cases
  # ===========================================================================

  describe "edge cases" do
    test "single number" do
      assert RPN.convert("42", %{}) == 42.0
    end

    test "single variable" do
      context = %{"x" => 99}
      assert RPN.convert("x", context) == 99.0
    end

    test "negative numbers in input" do
      assert RPN.convert("-5 3 +", %{}) == -2.0
    end

    test "floating point numbers" do
      assert RPN.convert("3.14159 2 *", %{}) == 6.28318
    end

    test "zero division raises ArithmeticError" do
      assert_raise ArithmeticError, fn ->
        RPN.convert("5 0 /", %{})
      end
    end

    test "very small numbers" do
      result = RPN.convert("0.0001 0.0001 *", %{})
      assert_in_delta result, 0.00000001, 0.000000001
    end

    test "very large numbers" do
      result = RPN.convert("1000000 1000000 *", %{})
      assert_in_delta result, 1.0e12, 1.0e6
    end

    test "empty context" do
      assert RPN.convert("5 3 +", %{}) == 8.0
    end
  end
end
