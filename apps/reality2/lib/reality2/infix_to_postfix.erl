-module(infix_to_postfix).
-export([infix_to_postfix/1]).

infix_to_postfix(Infix) ->
    Tokens = tokenize(Infix),
    {Postfix, _} = process_tokens(Tokens, [], []),
    Postfix.

% Tokenize an infix expression into a list of tokens
tokenize(Infix) ->
    {ok, Tokens, _} = re:split(Infix, "\s+|(?=[()\+\-*/^])|(?<=[()\+\-*/^])", [{return, list}, {capture, all_but_first}, unicode]),
    TokensFiltered = lists:filter(fun(Token) -> Token /= "" end, Tokens),
    TokensFiltered.

% Process a list of tokens using the Shunting Yard algorithm
process_tokens([], OpStack, Output) ->
    % Pop remaining operators from the operator stack to output queue
    lists:reverse(Output ++ lists:reverse(OpStack));
process_tokens([Token|Tokens], OpStack, Output) ->
    case Token of
        Number when is_number(Token) ->
            % Add numbers directly to output queue
            process_tokens(Tokens, OpStack, Output ++ [Token]);
        Operator when Operator =:= "+" orelse Operator =:= "-" orelse Operator =:= "*" orelse Operator =:= "/" orelse Operator =:= "^" ->
            % Pop operators with higher precedence from the operator stack to output queue
            {NewOpStack, NewOutput} = pop_higher_precedence(Operator, OpStack, Output),
            % Push the current operator onto the operator stack
            process_tokens(Tokens, [Operator|NewOpStack], NewOutput);
        "(" ->
            % Push opening parenthesis onto operator stack
            process_tokens(Tokens, ["("|OpStack], Output);
        ")" ->
            % Pop operators from the operator stack to output queue until opening parenthesis is found
            case lists:member("(", OpStack) of
                true ->
                    {NewOpStack, NewOutput} = pop_until_opening_parenthesis(OpStack, Output),
                    process_tokens(Tokens, NewOpStack, NewOutput);
                false ->
                    % Syntax error: mismatched parentheses
                    {[], []}
            end;
        _ ->
            % Syntax error: invalid token
            {[], []}
    end.

% Pop operators with higher precedence from the operator stack to output queue
pop_higher_precedence(Operator, [TopOp|OpStack], Output) when precedence(TopOp) >= precedence(Operator) ->
    {NewOpStack, NewOutput} = pop_higher_precedence(Operator, OpStack, Output ++ [TopOp]),
    {NewOpStack, NewOutput};
pop_higher_precedence(Operator, OpStack, Output) ->
    {OpStack, Output}.

% Pop operators from the operator stack to output queue until opening parenthesis is found
pop_until_opening_parenthesis(["("|OpStack], Output) ->
    {OpStack, Output};
pop_until_opening_parenthesis([TopOp|OpStack], Output) ->
    {NewOpStack, NewOutput} = pop_until_opening_parenthesis(OpStack, Output ++ [TopOp]),
    {NewOpStack, NewOutput};
pop_until_opening_parenthesis([], _) ->
    % Syntax error: mismatched parentheses
    {[], []}.

% Precedence of operators
precedence("^") -> 4;
precedence("*") -> 3;
precedence("/") -> 3;
precedence("+") -> 2;
precedence("-") -> 2;
precedence(_) -> 1.