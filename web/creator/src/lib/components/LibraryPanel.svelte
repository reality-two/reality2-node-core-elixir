<script lang="ts">
  import {
    LIBRARY_CATEGORIES,
    getLibraryEntries,
    getDefinitionContent,
    type LibraryCategory,
    type LibraryEntry,
  } from "../github";

  let { onLoad }: { onLoad: (content: string, name: string, format: "yaml" | "json") => void } = $props();

  let activeCategory = $state<LibraryCategory>(LIBRARY_CATEGORIES[0]);
  let entries = $state<LibraryEntry[]>([]);
  let loading = $state(false);
  let error = $state("");
  let loadingEntry = $state<string | null>(null);
  let previewContent = $state<string | null>(null);
  let previewEntry = $state<string | null>(null);

  async function fetchCategory(cat: LibraryCategory) {
    activeCategory = cat;
    entries = [];
    error = "";
    loading = true;
    previewContent = null;
    previewEntry = null;
    try {
      entries = await getLibraryEntries(cat);
    } catch (err) {
      error = (err as Error).message;
    } finally {
      loading = false;
    }
  }

  async function handlePreview(entry: LibraryEntry) {
    if (previewEntry === entry.shortName) {
      previewContent = null;
      previewEntry = null;
      return;
    }
    loadingEntry = entry.shortName;
    try {
      const result = await getDefinitionContent(activeCategory, entry);
      previewContent = result.content;
      previewEntry = entry.shortName;
      entry.format = result.format;
    } catch (err) {
      error = (err as Error).message;
    } finally {
      loadingEntry = null;
    }
  }

  async function handleLoad(entry: LibraryEntry) {
    loadingEntry = entry.shortName;
    try {
      const result = await getDefinitionContent(activeCategory, entry);
      onLoad(result.content, entry.name, result.format);
    } catch (err) {
      error = (err as Error).message;
    } finally {
      loadingEntry = null;
    }
  }

  // Fetch initial category
  fetchCategory(LIBRARY_CATEGORIES[0]);
</script>

<div class="library-panel">
  <div class="category-tabs">
    {#each LIBRARY_CATEGORIES as cat}
      <button
        class="tab-btn"
        class:active={activeCategory.dir === cat.dir}
        onclick={() => fetchCategory(cat)}
      >
        {cat.label}
      </button>
    {/each}
  </div>

  <div class="panel-body">
    {#if loading}
      <div class="loading-msg">
        <i class="spinner loading icon"></i> Loading {activeCategory.label}...
      </div>
    {:else if error}
      <div class="error-msg">
        <i class="exclamation triangle icon"></i> {error}
        <button class="ui mini basic button" style="margin-left: 8px;" onclick={() => { error = ""; fetchCategory(activeCategory); }}>
          Retry
        </button>
      </div>
    {:else if entries.length === 0}
      <p style="color: #999; padding: 16px;">No entries found.</p>
    {:else}
      <div class="entry-list">
        {#each entries as entry}
          <div class="entry-card">
            <div class="entry-header">
              <div class="entry-info">
                <span class="entry-name">{entry.name}</span>
              </div>
              <div class="entry-actions">
                <button
                  class="ui mini basic button"
                  onclick={() => handlePreview(entry)}
                  disabled={loadingEntry === entry.shortName}
                >
                  {#if loadingEntry === entry.shortName}
                    <i class="spinner loading icon"></i>
                  {:else}
                    <i class="eye icon"></i>
                  {/if}
                  {previewEntry === entry.shortName ? "Hide" : "View"}
                </button>
                <button
                  class="ui mini primary button"
                  onclick={() => handleLoad(entry)}
                  disabled={loadingEntry === entry.shortName}
                >
                  <i class="download icon"></i> Load
                </button>
              </div>
            </div>
            {#if entry.description}
              <div class="entry-desc">{entry.description}</div>
            {/if}
            <div class="entry-shortname">{entry.shortName}.{activeCategory.extension}</div>
            {#if previewEntry === entry.shortName && previewContent}
              <pre class="preview-code">{previewContent}</pre>
            {/if}
          </div>
        {/each}
      </div>
    {/if}
  </div>
</div>

<style>
  .library-panel {
    display: flex;
    flex-direction: column;
    height: 100%;
    width: 100%;
    background: #f5f5f5;
  }
  .category-tabs {
    display: flex;
    gap: 0;
    border-bottom: 2px solid #ddd;
    background: #fff;
    padding: 0 12px;
    flex-shrink: 0;
  }
  .tab-btn {
    padding: 10px 18px;
    border: none;
    background: none;
    font-size: 13px;
    font-weight: 600;
    color: #666;
    cursor: pointer;
    border-bottom: 2px solid transparent;
    margin-bottom: -2px;
    transition: color 0.15s, border-color 0.15s;
  }
  .tab-btn:hover {
    color: #333;
  }
  .tab-btn.active {
    color: #4183c4;
    border-bottom-color: #4183c4;
  }
  .panel-body {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
  }
  .loading-msg, .error-msg {
    padding: 20px;
    text-align: center;
    color: #888;
    font-size: 13px;
  }
  .error-msg {
    color: #c0392b;
  }
  .entry-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
    max-width: 800px;
  }
  .entry-card {
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 12px 14px;
    border-left: 4px solid #4183c4;
  }
  .entry-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }
  .entry-info {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }
  .entry-name {
    font-weight: 600;
    font-size: 14px;
  }
  .entry-actions {
    display: flex;
    gap: 4px;
    flex-shrink: 0;
  }
  .entry-desc {
    font-size: 12px;
    color: #666;
    margin-top: 4px;
  }
  .entry-shortname {
    font-size: 11px;
    color: #aaa;
    font-family: monospace;
    margin-top: 2px;
  }
  .preview-code {
    margin-top: 8px;
    padding: 10px;
    background: #1e1e1e;
    color: #d4d4d4;
    border-radius: 4px;
    font-size: 12px;
    font-family: monospace;
    overflow-x: auto;
    max-height: 400px;
    overflow-y: auto;
    white-space: pre-wrap;
    word-break: break-word;
  }
</style>
