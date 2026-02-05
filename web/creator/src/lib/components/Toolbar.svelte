<script lang="ts">
  import { getAdvancedMode, toggleAdvancedMode } from "../stores/preferences-store.svelte";
  import { t } from "../i18n/terminology";

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
    <button class="item" onclick={onAddSentant} title="Add a new {t('bee')} to the canvas">
      <i class="bug icon"></i> Add {t("Bee")}
    </button>

    <button class="item" onclick={onAddSwarm} title="Add a {t('swarm')} to organise {t('sentants')}">
      <i class="cubes icon"></i> Add {t("Swarm")}
    </button>

    <button class="item" onclick={onBrowseNode} title="Reload live {t('sentants')} from the {t('node')}">
      <i class="sync icon"></i> Reload
      {#if liveSentantCount > 0}
        <span class="ui mini circular label" style="margin-left: 4px; background: #43a047; color: #fff;">{liveSentantCount}</span>
      {/if}
    </button>

    <button class="item" onclick={onHive} title="View your {t('Hive')} and {t('Meadow')}">
      <i class="sitemap icon"></i> {t("Meadow")}
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

    <div class="right menu">
      <button
        class="item"
        onclick={toggleAdvancedMode}
        title={getAdvancedMode() ? "Switch to Standard mode (simplified)" : "Switch to Advanced mode (developer)"}
      >
        <i class="cog icon"></i>
        {getAdvancedMode() ? "Advanced" : "Standard"}
      </button>
    </div>

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
      <button class="item" onclick={onDeploy} title="{t('Deploy')} this {t('bee')} to the local Reality2 {t('node')}">
        <i class="play icon"></i> {t("Deploy")}
      </button>
      <button class="item" onclick={onDeleteSentant} title="Delete this {t('bee')}">
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
      <button class="item" onclick={onUnload} title="{t('Unload')} this {t('sentant')} from the {t('node')}">
        <i class="stop icon"></i> {t("Unload")}
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
      <button class="item" onclick={onDeploy} title="{t('Deploy')} this {t('swarm')} to the local Reality2 {t('node')}">
        <i class="play icon"></i> {t("Deploy")}
      </button>
      <button class="item" onclick={onDeleteSwarm} title="Delete this {t('swarm')}">
        <i class="trash icon"></i> Delete {t("Swarm")}
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
      <span style="font-weight: 600;">{t("Meadow")} &amp; {t("Neighbour")}s</span>
    </div>
    <div class="right menu">
      <button class="item" onclick={onRefreshHive} title="Refresh peer and hive data">
        <i class="sync icon"></i> Refresh
      </button>
    </div>
  {/if}
</div>
