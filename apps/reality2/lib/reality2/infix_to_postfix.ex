defmodule InfixToPostfix do
  # Public function to convert infix expression to postfix
  def infix_to_postfix(infix) do
    tokens = tokenize(infix)
    {postfix, _} = process_tokens(tokens, [], [])
    postfix
  end

  # Tokenize an infix expression into a list of tokens
  defp tokenize(infix) do
    {:ok, tokens, _} =
      Regex.scan(~r/\s+|(?=[()\+\-\*\/^])|(?<=[()\+\-*\/^])/, infix)

    tokens
    |> List.flatten()
    |> Enum.reject(&(&1 == ""))
  end

  # Process a list of tokens using the Shunting Yard algorithm
  defp process_tokens([], op_stack, output) do
    # Pop remaining operators from the operator stack to output queue
    Enum.reverse(output ++ Enum.reverse(op_stack))
  end

  defp process_tokens([token | tokens], op_stack, output) do
    cond do
      is_number(token) ->
        # Add numbers directly to output queue
        process_tokens(tokens, op_stack, output ++ [token])

      operator?(token) ->
        # Pop operators with higher precedence from the operator stack to output queue
        {new_op_stack, new_output} = pop_higher_precedence(token, op_stack, output)
        # Push the current operator onto the operator stack
        process_tokens(tokens, [token | new_op_stack], new_output)

      token == "(" ->
        # Push opening parenthesis onto operator stack
        process_tokens(tokens, [token | op_stack], output)

      token == ")" ->
        # Pop operators from the operator stack to output queue until opening parenthesis is found
        case Enum.member?(op_stack, "(") do
          true ->
            {new_op_stack, new_output} = pop_until_opening_parenthesis(op_stack, output)
            process_tokens(tokens, new_op_stack, new_output)
          false ->
            # Syntax error: mismatched parentheses
            {[], []}
        end

      true ->
        # Syntax error: invalid token
        {[], []}
    end
  end

  # Pop operators with higher precedence from the operator stack to output queue
  defp pop_higher_precedence(operator, [top_op | op_stack], output) when precedence!(top_op) >= precedence(operator) do
    {new_op_stack, new_output} = pop_higher_precedence(operator, op_stack, output ++ [top_op])
    {new_op_stack, new_output}
  end
  defp pop_higher_precedence(operator, op_stack, output) do
    {op_stack, output}
  end

  # Pop operators from the operator stack to output queue until opening parenthesis is found
  defp pop_until_opening_parenthesis(["(" | op_stack], output) do
    {op_stack, output}
  end
  defp pop_until_opening_parenthesis([top_op | op_stack], output) do
    {new_op_stack, new_output} = pop_until_opening_parenthesis(op_stack, output ++ [top_op])
    {new_op_stack, new_output}
  end
  defp pop_until_opening_parenthesis([], _) do
    # Syntax error: mismatched parentheses
    {[], []}
  end

  # Determine if a token is an operator
  defp operator?(token) do
    token in ["+", "-", "*", "/", "^"]
  end

  # Precedence of operators
  defp precedence!("^"), do: 4
  defp precedence!("*"), do: 3
  defp precedence!("/"), do: 3
  defp precedence!("+"), do: 2
  defp precedence!("-"), do: 2
  defp precedence!(_), do: 1

  # Check if the token is a number (as a string)
  defp is_number(token) do
    String.match?(token, ~r/^\d+(\.\d+)?$/)
  end
end

# Example usage
infix_expression = "3 + 4 * 2 / (1 - 5) ^ 2 ^ 3"
postfix_expression = InfixToPostfix.infix_to_postfix(infix_expression)
IO.puts("Postfix Expression: #{Enum.join(postfix_expression, " ")}")
