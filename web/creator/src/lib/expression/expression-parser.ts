// Infix expression parser → JSON tree (matching Reality2.Calculation format)
// and tree → infix formatter for display.

const FUNCTIONS = new Set([
  "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh",
  "asinh", "acosh", "atanh", "sqrt", "log", "log2", "log10", "exp",
  "ceil", "floor", "latlong",
]);

const BINARY_FUNCTIONS = new Set(["atan2", "pow", "fmod", "geohash"]);

const CONSTANTS = new Set(["pi", "e", "true", "false"]);

// Token types
type Token =
  | { type: "number"; value: number }
  | { type: "variable"; value: string }
  | { type: "constant"; value: string }
  | { type: "op"; value: string }
  | { type: "unary"; value: string }
  | { type: "func"; value: string }
  | { type: "binfunc"; value: string }
  | { type: "lparen" }
  | { type: "rparen" }
  | { type: "comma" };

// Operator precedence (higher = binds tighter)
const PRECEDENCE: Record<string, number> = {
  "||": 1,
  "&&": 2,
  "==": 3, "!=": 3,
  ">": 4, "<": 4, ">=": 4, "<=": 4,
  "+": 5, "-": 5,
  "*": 6, "/": 6,
  "^": 7,
};

const RIGHT_ASSOC = new Set(["^"]);

// Multi-char operators sorted longest-first for greedy matching
const OPERATORS = [">=", "<=", "==", "!=", "&&", "||", ">", "<", "+", "-", "*", "/", "^", "!"];

function tokenize(input: string): Token[] {
  const tokens: Token[] = [];
  let i = 0;

  while (i < input.length) {
    // Skip whitespace
    if (/\s/.test(input[i])) { i++; continue; }

    // Parentheses
    if (input[i] === "(") { tokens.push({ type: "lparen" }); i++; continue; }
    if (input[i] === ")") { tokens.push({ type: "rparen" }); i++; continue; }
    if (input[i] === ",") { tokens.push({ type: "comma" }); i++; continue; }

    // Multi-char operators
    let matchedOp = false;
    for (const op of OPERATORS) {
      if (input.startsWith(op, i)) {
        // Determine if - or + is unary
        if ((op === "-" || op === "+" || op === "!") && isUnaryContext(tokens)) {
          tokens.push({ type: "unary", value: op });
        } else if (op === "!") {
          tokens.push({ type: "unary", value: op });
        } else {
          tokens.push({ type: "op", value: op });
        }
        i += op.length;
        matchedOp = true;
        break;
      }
    }
    if (matchedOp) continue;

    // Numbers (including decimals)
    if (/[0-9.]/.test(input[i])) {
      let numStr = "";
      while (i < input.length && /[0-9.]/.test(input[i])) {
        numStr += input[i];
        i++;
      }
      tokens.push({ type: "number", value: parseFloat(numStr) });
      continue;
    }

    // Identifiers (variables, functions, constants)
    if (/[a-zA-Z_]/.test(input[i])) {
      let ident = "";
      while (i < input.length && /[a-zA-Z0-9_]/.test(input[i])) {
        ident += input[i];
        i++;
      }
      if (FUNCTIONS.has(ident)) {
        tokens.push({ type: "func", value: ident });
      } else if (BINARY_FUNCTIONS.has(ident)) {
        tokens.push({ type: "binfunc", value: ident });
      } else if (CONSTANTS.has(ident)) {
        tokens.push({ type: "constant", value: ident });
      } else {
        tokens.push({ type: "variable", value: ident });
      }
      continue;
    }

    // Unknown character — skip
    i++;
  }
  return tokens;
}

function isUnaryContext(tokens: Token[]): boolean {
  if (tokens.length === 0) return true;
  const last = tokens[tokens.length - 1];
  return last.type === "op" || last.type === "unary" || last.type === "lparen" || last.type === "comma";
}

type ExprTree = string | number | boolean | Record<string, unknown>;

// Shunting-yard: infix tokens → tree
function shuntingYard(tokens: Token[]): ExprTree {
  const output: ExprTree[] = [];
  const ops: Token[] = [];

  function applyOp(op: Token) {
    if (op.type === "op") {
      const right = output.pop()!;
      const left = output.pop()!;
      output.push({ [op.value]: [left, right] });
    } else if (op.type === "unary") {
      const operand = output.pop()!;
      output.push({ [op.value]: [operand] });
    } else if (op.type === "func") {
      const arg = output.pop()!;
      output.push({ [op.value]: [arg] });
    } else if (op.type === "binfunc") {
      const arg2 = output.pop()!;
      const arg1 = output.pop()!;
      output.push({ [op.value]: [arg1, arg2] });
    }
  }

  for (let i = 0; i < tokens.length; i++) {
    const tok = tokens[i];

    if (tok.type === "number") {
      output.push(tok.value);
    } else if (tok.type === "variable") {
      output.push(tok.value);
    } else if (tok.type === "constant") {
      if (tok.value === "true") output.push(true);
      else if (tok.value === "false") output.push(false);
      else output.push(tok.value); // "pi", "e" — server resolves these
    } else if (tok.type === "func" || tok.type === "binfunc") {
      ops.push(tok);
    } else if (tok.type === "comma") {
      while (ops.length > 0 && ops[ops.length - 1].type !== "lparen") {
        applyOp(ops.pop()!);
      }
    } else if (tok.type === "op") {
      const prec = PRECEDENCE[tok.value] ?? 0;
      while (ops.length > 0) {
        const top = ops[ops.length - 1];
        if (top.type === "lparen") break;
        if (top.type === "unary") { applyOp(ops.pop()!); continue; }
        const topPrec = top.type === "op" ? (PRECEDENCE[top.value] ?? 0) : 99;
        if (topPrec > prec || (topPrec === prec && !RIGHT_ASSOC.has(tok.value))) {
          applyOp(ops.pop()!);
        } else {
          break;
        }
      }
      ops.push(tok);
    } else if (tok.type === "unary") {
      ops.push(tok);
    } else if (tok.type === "lparen") {
      ops.push(tok);
    } else if (tok.type === "rparen") {
      while (ops.length > 0 && ops[ops.length - 1].type !== "lparen") {
        applyOp(ops.pop()!);
      }
      if (ops.length > 0 && ops[ops.length - 1].type === "lparen") {
        ops.pop(); // discard lparen
      }
      // If top of ops is a function, apply it
      if (ops.length > 0 && (ops[ops.length - 1].type === "func" || ops[ops.length - 1].type === "binfunc")) {
        applyOp(ops.pop()!);
      }
    }
  }

  while (ops.length > 0) {
    applyOp(ops.pop()!);
  }

  return output.length > 0 ? output[0] : "";
}

/**
 * Convert an expression tree to RPN (Reverse Polish Notation) string.
 * This is the storage format — avoids YAML mangling operator keys like +, >.
 */
export function treeToRPN(tree: ExprTree): string {
  if (tree === null || tree === undefined) return "";
  if (typeof tree === "number") return String(tree);
  if (typeof tree === "boolean") return String(tree);
  if (typeof tree === "string") return tree;

  if (typeof tree !== "object") return String(tree);

  const keys = Object.keys(tree);
  if (keys.length !== 1) return JSON.stringify(tree);

  const op = keys[0];
  const args = (tree as Record<string, unknown>)[op];

  if (Array.isArray(args) && args.length === 1) {
    // Unary: operand op
    return `${treeToRPN(args[0] as ExprTree)} ${op}`;
  }

  if (Array.isArray(args) && args.length === 2) {
    // Binary: left right op
    return `${treeToRPN(args[0] as ExprTree)} ${treeToRPN(args[1] as ExprTree)} ${op}`;
  }

  // Non-array arg (legacy unary without array wrapper)
  if (!Array.isArray(args)) {
    return `${treeToRPN(args as ExprTree)} ${op}`;
  }

  return String(tree);
}

/**
 * Parse an infix expression string into an RPN string for the server.
 * Returns { rpn, error? }. On failure, rpn is the raw input string.
 */
export function parseExpression(input: string): { rpn: string; error?: string } {
  const trimmed = input.trim();
  if (!trimmed) return { rpn: "" };

  try {
    const tokens = tokenize(trimmed);
    if (tokens.length === 0) return { rpn: "" };

    // Single token shortcuts
    if (tokens.length === 1) {
      const t = tokens[0];
      if (t.type === "number") return { rpn: String(t.value) };
      if (t.type === "variable" || t.type === "constant") return { rpn: t.value };
    }

    const tree = shuntingYard(tokens);
    return { rpn: treeToRPN(tree) };
  } catch (e) {
    return { rpn: trimmed, error: String(e) };
  }
}

// Operator precedence for minimal-parentheses output
function opPrecedence(op: string): number {
  return PRECEDENCE[op] ?? 0;
}

/**
 * Convert a JSON expression tree back to a human-readable infix string.
 */
export function treeToInfix(tree: ExprTree, parentPrec = 0, isRight = false): string {
  if (tree === null || tree === undefined) return "";
  if (typeof tree === "number") return String(tree);
  if (typeof tree === "boolean") return String(tree);
  if (typeof tree === "string") return tree;

  if (typeof tree !== "object") return String(tree);

  const keys = Object.keys(tree);
  if (keys.length !== 1) return JSON.stringify(tree);

  const op = keys[0];
  const args = (tree as Record<string, unknown>)[op];

  // Unary function or operator with single arg
  if (Array.isArray(args) && args.length === 1) {
    const arg = args[0] as ExprTree;
    if (FUNCTIONS.has(op)) {
      return `${op}(${treeToInfix(arg)})`;
    }
    // Unary - or !
    if (op === "-" || op === "!") {
      const inner = treeToInfix(arg, 99);
      const needsParens = typeof arg === "object" && arg !== null && !Array.isArray(arg);
      return needsParens ? `${op}(${inner})` : `${op}${inner}`;
    }
    return `${op}(${treeToInfix(arg)})`;
  }

  // Binary function
  if (Array.isArray(args) && args.length === 2 && BINARY_FUNCTIONS.has(op)) {
    return `${op}(${treeToInfix(args[0] as ExprTree)}, ${treeToInfix(args[1] as ExprTree)})`;
  }

  // Binary operator
  if (Array.isArray(args) && args.length === 2) {
    const prec = opPrecedence(op);
    const left = treeToInfix(args[0] as ExprTree, prec, false);
    const right = treeToInfix(args[1] as ExprTree, prec, true);
    const expr = `${left} ${op} ${right}`;

    // Add parens if this operator has lower precedence than parent
    const needsParens = prec < parentPrec || (prec === parentPrec && isRight && !RIGHT_ASSOC.has(op));
    return needsParens ? `(${expr})` : expr;
  }

  // Non-array arg (legacy unary without array wrapper)
  if (!Array.isArray(args)) {
    const arg = args as ExprTree;
    if (FUNCTIONS.has(op)) {
      return `${op}(${treeToInfix(arg)})`;
    }
    return `${op}(${treeToInfix(arg)})`;
  }

  return JSON.stringify(tree);
}

/**
 * Check if a value looks like a tree expression (object with operator key).
 */
export function isExprTree(value: unknown): boolean {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  const keys = Object.keys(value);
  if (keys.length !== 1) return false;
  const op = keys[0];
  return op in PRECEDENCE || FUNCTIONS.has(op) || BINARY_FUNCTIONS.has(op) || op === "!" || op === "-" || op === "+";
}

const ALL_OPS = new Set([
  ...Object.keys(PRECEDENCE), "!",
  ...FUNCTIONS, ...BINARY_FUNCTIONS,
]);

/**
 * Convert an RPN string to a human-readable infix string for display.
 * Falls back to returning the raw string if parsing fails.
 */
export function rpnToInfix(rpn: string): string {
  if (!rpn || typeof rpn !== "string") return rpn ?? "";
  const tokens = rpn.trim().split(/\s+/);
  if (tokens.length <= 1) return rpn;

  try {
    const stack: { text: string; prec: number }[] = [];

    for (const tok of tokens) {
      if (ALL_OPS.has(tok)) {
        const prec = PRECEDENCE[tok] ?? 0;

        if (BINARY_FUNCTIONS.has(tok)) {
          // Binary function: func(a, b)
          const b = stack.pop()!;
          const a = stack.pop()!;
          stack.push({ text: `${tok}(${a.text}, ${b.text})`, prec: 99 });
        } else if (FUNCTIONS.has(tok)) {
          // Unary function: func(a)
          const a = stack.pop()!;
          stack.push({ text: `${tok}(${a.text})`, prec: 99 });
        } else if (tok === "!" || (stack.length < 2 && (tok === "-" || tok === "+"))) {
          // Unary operator
          const a = stack.pop()!;
          const inner = a.prec < 99 && a.prec > 0 ? `(${a.text})` : a.text;
          stack.push({ text: `${tok}${inner}`, prec: 99 });
        } else {
          // Binary operator
          const right = stack.pop()!;
          const left = stack.pop()!;
          const leftText = left.prec > 0 && left.prec < prec ? `(${left.text})` : left.text;
          const rightText = right.prec > 0 && (right.prec < prec || (right.prec === prec && !RIGHT_ASSOC.has(tok))) ? `(${right.text})` : right.text;
          stack.push({ text: `${leftText} ${tok} ${rightText}`, prec });
        }
      } else {
        // Operand: number, variable, or constant
        stack.push({ text: tok, prec: 99 });
      }
    }

    return stack.length > 0 ? stack[0].text : rpn;
  } catch {
    return rpn;
  }
}
