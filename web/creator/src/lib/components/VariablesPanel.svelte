<script lang="ts">
  import { getVariables, setVariables, loadVariablesFromFile, saveVariablesToFile } from "../stores/variables-store.svelte";

  let entries = $derived(Object.entries(getVariables()));

  function updateKey(oldKey: string, newKey: string) {
    const vars = { ...getVariables() };
    const value = vars[oldKey];
    delete vars[oldKey];
    vars[newKey] = value;
    setVariables(vars);
  }

  function updateValue(key: string, value: string) {
    setVariables({ ...getVariables(), [key]: value });
  }

  function addEntry() {
    const vars = getVariables();
    let name = "__new_key__";
    let i = 1;
    while (name in vars) {
      name = `__new_key_${i++}__`;
    }
    setVariables({ ...vars, [name]: "" });
  }

  function removeEntry(key: string) {
    const vars = { ...getVariables() };
    delete vars[key];
    setVariables(vars);
  }
</script>

<div class="variables-panel">
  <div class="panel-body">
    <div class="ui segment">
      <div style="display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px;">
        <h4 class="ui header" style="margin: 0;">
          <i class="key icon"></i>
          Variables
          {#if entries.length > 0}
            <span class="ui mini circular label" style="margin-left: 6px;">{entries.length}</span>
          {/if}
        </h4>
        <div style="display: flex; gap: 4px;">
          <button class="ui mini basic icon button" onclick={loadVariablesFromFile} title="Load from file">
            <i class="upload icon"></i>
          </button>
          <button class="ui mini basic icon button" onclick={saveVariablesToFile} title="Save to file">
            <i class="download icon"></i>
          </button>
        </div>
      </div>
      <p style="color: #999; font-size: 12px; margin-bottom: 12px;">
        API keys and secrets for deployment. Use <span class="mono">__name__</span> syntax in antenna fields.
      </p>

      <div class="var-list">
        {#each entries as [key, value]}
          <div class="var-card">
            <div class="var-row">
              <input
                class="var-key"
                type="text"
                placeholder="__variable_name__"
                value={key}
                onblur={(e) => {
                  const newKey = (e.target as HTMLInputElement).value;
                  if (newKey && newKey !== key) updateKey(key, newKey);
                }}
              />
              <input
                class="var-value"
                type="text"
                placeholder="value"
                value={value}
                oninput={(e) => updateValue(key, (e.target as HTMLInputElement).value)}
              />
              <button class="ui mini icon button" onclick={() => removeEntry(key)} title="Remove">
                <i class="close icon"></i>
              </button>
            </div>
          </div>
        {/each}
      </div>

      <button class="ui mini basic button" style="margin-top: 10px;" onclick={addEntry}>
        <i class="plus icon"></i> Add Variable
      </button>
    </div>
  </div>
</div>

<style>
  .variables-panel {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    background: #f5f5f5;
  }
  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
    max-width: 800px;
  }
  .mono {
    font-family: monospace;
    font-size: 12px;
    color: #555;
  }
  .var-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }
  .var-card {
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 8px 10px;
    border-left: 4px solid #1976d2;
  }
  .var-row {
    display: flex;
    gap: 6px;
    align-items: center;
  }
  .var-key {
    flex: 2;
    padding: 6px 8px;
    font-size: 12px;
    font-family: "Cascadia Code", "Fira Code", monospace;
    border: 1px solid rgba(34, 36, 38, 0.15);
    border-radius: 4px;
  }
  .var-value {
    flex: 3;
    padding: 6px 8px;
    font-size: 12px;
    border: 1px solid rgba(34, 36, 38, 0.15);
    border-radius: 4px;
  }
</style>
