let variables = $state<Record<string, string>>({});

export function getVariables(): Record<string, string> {
  return variables;
}

export function setVariables(vars: Record<string, string>): void {
  variables = vars;
}

export function getVariableCount(): number {
  return Object.keys(variables).length;
}

export function replaceVariables(str: string): string {
  for (const [key, value] of Object.entries(variables)) {
    const regex = new RegExp(key, "g");
    str = str.replace(regex, String(value));
  }
  return str;
}

export function loadVariablesFromFile(): void {
  const input = document.createElement("input");
  input.type = "file";
  input.accept = ".json";

  input.onchange = (e: Event) => {
    const file = (e.target as HTMLInputElement).files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (readerEvent) => {
      try {
        const parsed = JSON.parse(readerEvent.target?.result as string);
        if (typeof parsed === "object" && parsed !== null) {
          variables = parsed;
        }
      } catch {
        // Invalid JSON — ignore
      }
    };
    reader.readAsText(file);
  };

  input.click();
}

export function saveVariablesToFile(): void {
  const json = JSON.stringify(variables, null, 2);
  const blob = new Blob([json], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "variables.json";
  a.click();
  URL.revokeObjectURL(url);
}
