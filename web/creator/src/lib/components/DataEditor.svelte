<script lang="ts">
  let {
    data = {},
    onChange,
  }: {
    data: Record<string, unknown>;
    onChange: (data: Record<string, unknown>) => void;
  } = $props();

  let entries = $derived(Object.entries(data));

  function updateKey(oldKey: string, newKey: string) {
    const updated = { ...data };
    const value = updated[oldKey];
    delete updated[oldKey];
    updated[newKey] = value;
    onChange(updated);
  }

  function updateValue(key: string, value: string) {
    onChange({ ...data, [key]: value });
  }

  function addEntry() {
    onChange({ ...data, ["key" + (entries.length + 1)]: "" });
  }

  function removeEntry(key: string) {
    const updated = { ...data };
    delete updated[key];
    onChange(updated);
  }
</script>

<div class="data-editor">
  {#each entries as [key, value], i}
    <div class="ui mini action input fluid" style="margin-bottom: 4px;">
      <input
        type="text"
        value={key}
        style="width: 40%;"
        onchange={(e) => updateKey(key, (e.target as HTMLInputElement).value)}
      />
      <input
        type="text"
        value={String(value ?? "")}
        style="width: 50%;"
        oninput={(e) => updateValue(key, (e.target as HTMLInputElement).value)}
      />
      <button class="ui mini icon button" onclick={() => removeEntry(key)}>
        <i class="close icon"></i>
      </button>
    </div>
  {/each}
  <button class="ui mini basic button" style="margin-top: 4px;" onclick={addEntry}>
    <i class="plus icon"></i> Add
  </button>
</div>
