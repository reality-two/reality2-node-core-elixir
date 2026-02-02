<script lang="ts">
  import { parseExpression, treeToInfix, isExprTree, rpnToInfix } from "../expression/expression-parser";

  let {
    value,
    onChange,
    placeholder = "e.g. (count + 1) * 3",
  }: {
    value: unknown;
    onChange: (value: unknown) => void;
    placeholder?: string;
  } = $props();

  let inputRef: HTMLInputElement | undefined = $state();

  // Convert stored value to display string (infix notation for the user)
  let displayText = $derived.by(() => {
    if (value === undefined || value === null || value === "") return "";
    if (typeof value === "number" || typeof value === "boolean") return String(value);
    if (typeof value === "string") return rpnToInfix(value);
    if (isExprTree(value)) return treeToInfix(value as Record<string, unknown>);
    return JSON.stringify(value);
  });

  let localText = $state("");
  let hasFocus = $state(false);

  // Sync display text when value changes externally (not while editing)
  $effect(() => {
    if (!hasFocus) {
      localText = displayText;
    }
  });

  function handleInput(e: Event) {
    const text = (e.target as HTMLInputElement).value;
    localText = text;
    commitText(text);
  }

  function commitText(text: string) {
    const trimmed = text.trim();
    if (!trimmed) {
      onChange(undefined);
      return;
    }
    const { rpn } = parseExpression(trimmed);
    onChange(rpn);
  }

  function handleFocus() {
    hasFocus = true;
  }

  function handleBlur() {
    hasFocus = false;
    localText = displayText;
  }

  function insertAtCursor(text: string) {
    if (!inputRef) return;
    const start = inputRef.selectionStart ?? localText.length;
    const end = inputRef.selectionEnd ?? start;
    const before = localText.slice(0, start);
    const after = localText.slice(end);

    // Add spaces around operators if needed
    const needsSpaceBefore = before.length > 0 && !/[\s(]$/.test(before);
    const needsSpaceAfter = after.length > 0 && !/^[\s)]/.test(after);

    const isFunc = text.endsWith("(");
    const prefix = (needsSpaceBefore && !isFunc) ? " " : "";
    const suffix = (needsSpaceAfter && !isFunc) ? " " : "";

    const newText = before + prefix + text + suffix + after;
    localText = newText;
    commitText(newText);

    // Restore cursor position
    const cursorPos = start + prefix.length + text.length;
    requestAnimationFrame(() => {
      inputRef?.focus();
      inputRef?.setSelectionRange(cursorPos, cursorPos);
    });
  }

  let showPalette = $state(false);
</script>

<div class="expr-editor">
  <div class="expr-input-row">
    <div class="ui mini input fluid">
      <input type="text" {placeholder}
        bind:this={inputRef}
        value={localText}
        oninput={handleInput}
        onfocus={handleFocus}
        onblur={handleBlur} />
    </div>
    <button class="palette-toggle" class:active={showPalette}
      onclick={() => (showPalette = !showPalette)}
      title="Operator palette" type="button">
      <i class="calculator icon"></i>
    </button>
  </div>

  {#if showPalette}
    <div class="palette">
      <div class="palette-group">
        <span class="group-label">Math</span>
        <button type="button" onclick={() => insertAtCursor("+")}>+</button>
        <button type="button" onclick={() => insertAtCursor("-")}>-</button>
        <button type="button" onclick={() => insertAtCursor("*")}>*</button>
        <button type="button" onclick={() => insertAtCursor("/")}>/</button>
        <button type="button" onclick={() => insertAtCursor("^")}>^</button>
        <button type="button" onclick={() => insertAtCursor("(")}>&#40;</button>
        <button type="button" onclick={() => insertAtCursor(")")}>&#41;</button>
      </div>
      <div class="palette-group">
        <span class="group-label">Compare</span>
        <button type="button" onclick={() => insertAtCursor("==")}>==</button>
        <button type="button" onclick={() => insertAtCursor("!=")}>!=</button>
        <button type="button" onclick={() => insertAtCursor(">")}>&#62;</button>
        <button type="button" onclick={() => insertAtCursor("<")}>&#60;</button>
        <button type="button" onclick={() => insertAtCursor(">=")}>&#62;=</button>
        <button type="button" onclick={() => insertAtCursor("<=")}>&#60;=</button>
      </div>
      <div class="palette-group">
        <span class="group-label">Logic</span>
        <button type="button" onclick={() => insertAtCursor("&&")}>&&</button>
        <button type="button" onclick={() => insertAtCursor("||")}>||</button>
        <button type="button" onclick={() => insertAtCursor("!")}>!</button>
      </div>
      <div class="palette-group">
        <span class="group-label">Functions</span>
        <button type="button" onclick={() => insertAtCursor("sqrt(")}>sqrt</button>
        <button type="button" onclick={() => insertAtCursor("log(")}>log</button>
        <button type="button" onclick={() => insertAtCursor("exp(")}>exp</button>
        <button type="button" onclick={() => insertAtCursor("ceil(")}>ceil</button>
        <button type="button" onclick={() => insertAtCursor("floor(")}>floor</button>
        <button type="button" onclick={() => insertAtCursor("sin(")}>sin</button>
        <button type="button" onclick={() => insertAtCursor("cos(")}>cos</button>
        <button type="button" onclick={() => insertAtCursor("tan(")}>tan</button>
        <button type="button" onclick={() => insertAtCursor("pow(")}>pow</button>
        <button type="button" onclick={() => insertAtCursor("atan2(")}>atan2</button>
      </div>
      <div class="palette-group">
        <span class="group-label">Constants</span>
        <button type="button" onclick={() => insertAtCursor("pi")}>pi</button>
        <button type="button" onclick={() => insertAtCursor("e")}>e</button>
        <button type="button" onclick={() => insertAtCursor("true")}>true</button>
        <button type="button" onclick={() => insertAtCursor("false")}>false</button>
      </div>
    </div>
  {/if}
</div>

<style>
  .expr-editor {
    width: 100%;
  }
  .expr-input-row {
    display: flex;
    gap: 4px;
    align-items: center;
  }
  .expr-input-row .ui.input {
    flex: 1;
  }
  .palette-toggle {
    border: 1px solid #ddd;
    background: #fafafa;
    border-radius: 4px;
    padding: 4px 6px;
    cursor: pointer;
    color: #888;
    font-size: 12px;
    line-height: 1;
    flex-shrink: 0;
  }
  .palette-toggle:hover, .palette-toggle.active {
    background: #e8e8e8;
    color: #555;
  }
  .palette {
    margin-top: 4px;
    padding: 6px;
    background: #f8f8f8;
    border: 1px solid #e0e0e0;
    border-radius: 4px;
  }
  .palette-group {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 2px;
    margin-bottom: 3px;
  }
  .palette-group:last-child {
    margin-bottom: 0;
  }
  .group-label {
    font-size: 9px;
    font-weight: 700;
    color: #999;
    text-transform: uppercase;
    letter-spacing: 0.3px;
    width: 56px;
    flex-shrink: 0;
  }
  .palette button {
    font-family: monospace;
    font-size: 11px;
    font-weight: 600;
    padding: 2px 6px;
    border: 1px solid #ddd;
    background: #fff;
    border-radius: 3px;
    cursor: pointer;
    color: #555;
    line-height: 1.3;
  }
  .palette button:hover {
    background: #e0e0ff;
    border-color: #aac;
  }
</style>
