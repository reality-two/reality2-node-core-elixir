<script lang="ts">
  let {
    mode = "canvas",
    editingName = "",
    onBack,
    onAddSentant,
    onAddSwarm,
    onDeploy,
    onUnload,
    onBrowseNode,
    onHive,
    onSave,
    onImport,
    onClear,
    onDeleteSentant,
    onDeleteSwarm,
    onRefreshHive,
    onLibrary,
    onLoadVariables,
    liveSentantCount = 0,
    variableCount = 0,
  }: {
    mode?: "canvas" | "editing" | "live" | "hive" | "swarm" | "library" | "variables";
    editingName?: string;
    onBack?: () => void;
    onAddSentant: () => void;
    onAddSwarm?: () => void;
    onDeploy?: () => void;
    onUnload?: () => void;
    onBrowseNode: () => void;
    onHive?: () => void;
    onLibrary?: () => void;
    onSave: () => void;
    onImport: () => void;
    onClear: () => void;
    onDeleteSentant?: () => void;
    onDeleteSwarm?: () => void;
    onRefreshHive?: () => void;
    onLoadVariables?: () => void;
    liveSentantCount?: number;
    variableCount?: number;
  } = $props();
</script>

<div class="toolbar ui menu inverted" style="margin: 0; border-radius: 0;">
  <div class="item">
    <strong style="color: #f0c040;">Reality2 Creator</strong>
  </div>

  {#if mode === "canvas"}
    <button class="item" onclick={onAddSentant} title="Add a new bee to the canvas">
      <i class="bug icon"></i> Add Bee
    </button>

    <button class="item" onclick={onAddSwarm} title="Add a swarm group to organise bees">
      <i class="cubes icon"></i> Add Swarm
    </button>

    <button class="item" onclick={onBrowseNode} title="Reload live bees from the node">
      <i class="sync icon"></i> Reload
      {#if liveSentantCount > 0}
        <span class="ui mini circular label" style="margin-left: 4px; background: #43a047; color: #fff;">{liveSentantCount}</span>
      {/if}
    </button>

    <button class="item" onclick={onHive} title="View node identity, peers and hive">
      <i class="sitemap icon"></i> Hive
    </button>

    <button class="item" onclick={onLibrary} title="Browse definition library on GitHub">
      <i class="book icon"></i> Library
    </button>

    <button class="item" onclick={onImport} title="Import a YAML or JSON definition file">
      <i class="upload icon"></i> Import
    </button>

    <button class="item" onclick={onLoadVariables} title="Manage API keys and variables for deployment">
      <i class="key icon"></i> Variables
      {#if variableCount > 0}
        <span class="ui mini circular label" style="margin-left: 4px; background: #1976d2; color: #fff;">{variableCount}</span>
      {/if}
    </button>

    <button class="item" onclick={onClear} title="Clear the canvas">
      <i class="trash icon"></i> Clear
    </button>

  {:else if mode === "editing"}
    <button class="item" onclick={onBack}>
      <i class="arrow left icon"></i> Back
    </button>
    <div class="item">
      <span style="font-weight: 600;">{editingName}</span>
    </div>
    <div class="right menu">
      <button class="item" onclick={onSave} title="Save as YAML file">
        <i class="save icon"></i> Save
      </button>
      <button class="item" onclick={onDeploy} title="Deploy this bee to the local Reality2 node">
        <i class="play icon"></i> Deploy
      </button>
      <button class="item" onclick={onDeleteSentant} title="Delete this bee">
        <i class="trash icon"></i> Delete
      </button>
    </div>

  {:else if mode === "live"}
    <button class="item" onclick={onBack}>
      <i class="arrow left icon"></i> Back
    </button>
    <div class="item">
      <span class="ui mini label" style="background: #43a047; color: #fff; margin-right: 6px;">LIVE</span>
      <span style="font-weight: 600;">{editingName}</span>
    </div>
    <div class="right menu">
      <button class="item" onclick={onUnload} title="Unload this sentant from the node">
        <i class="stop icon"></i> Unload
      </button>
    </div>

  {:else if mode === "swarm"}
    <button class="item" onclick={onBack}>
      <i class="arrow left icon"></i> Back
    </button>
    <div class="item">
      <i class="cubes icon" style="color: #b39ddb;"></i>
      <span style="font-weight: 600;">{editingName}</span>
    </div>
    <div class="right menu">
      <button class="item" onclick={onSave} title="Save as YAML file">
        <i class="save icon"></i> Save
      </button>
      <button class="item" onclick={onDeploy} title="Deploy this swarm to the local Reality2 node">
        <i class="play icon"></i> Deploy
      </button>
      <button class="item" onclick={onDeleteSwarm} title="Delete this swarm">
        <i class="trash icon"></i> Delete Swarm
      </button>
    </div>

  {:else if mode === "variables"}
    <button class="item" onclick={onBack}>
      <i class="arrow left icon"></i> Back
    </button>
    <div class="item">
      <i class="key icon"></i>
      <span style="font-weight: 600;">Variables</span>
      {#if variableCount > 0}
        <span class="ui mini circular label" style="margin-left: 6px; background: #1976d2; color: #fff;">{variableCount}</span>
      {/if}
    </div>

  {:else if mode === "library"}
    <button class="item" onclick={onBack}>
      <i class="arrow left icon"></i> Back
    </button>
    <div class="item">
      <i class="book icon"></i>
      <span style="font-weight: 600;">Definition Library</span>
    </div>

  {:else if mode === "hive"}
    <button class="item" onclick={onBack}>
      <i class="arrow left icon"></i> Back
    </button>
    <div class="item">
      <i class="sitemap icon"></i>
      <span style="font-weight: 600;">Hive &amp; Peers</span>
    </div>
    <div class="right menu">
      <button class="item" onclick={onRefreshHive} title="Refresh peer and hive data">
        <i class="sync icon"></i> Refresh
      </button>
    </div>
  {/if}
</div>
