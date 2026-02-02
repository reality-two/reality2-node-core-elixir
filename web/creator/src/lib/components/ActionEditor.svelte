<script lang="ts">
  import type { ActionModel } from "../models/canvas";
  import DataEditor from "./DataEditor.svelte";

  let {
    action,
    onUpdate,
    onRemove,
  }: {
    action: ActionModel;
    onUpdate: (updates: Record<string, unknown>) => void;
    onRemove: () => void;
  } = $props();

  let expanded = $state(true);

  // Compound key encodes plugin:command for the dropdown
  // Core commands have no prefix; internal plugins use "plugin:command"
  const INTERNAL_PLUGINS: Record<string, { label: string; icon: string; color: string; commands: { value: string; label: string }[] }> = {
    "ai.reality2.vars": {
      label: "Variables",
      icon: "database",
      color: "#00838f",
      commands: [
        { value: "set", label: "Store variable" },
        { value: "get", label: "Fetch variable" },
        { value: "all", label: "Fetch all" },
        { value: "delete", label: "Delete variable" },
        { value: "clear", label: "Clear all" },
      ],
    },
    "ai.reality2.geospatial": {
      label: "Geospatial",
      icon: "map marker alternate",
      color: "#00695c",
      commands: [
        { value: "set", label: "Set location" },
        { value: "get", label: "Get location" },
        { value: "search", label: "Search nearby" },
        { value: "delete", label: "Remove location" },
      ],
    },
    "ai.reality2.backup": {
      label: "Storage",
      icon: "hdd",
      color: "#5d4037",
      commands: [
        { value: "store", label: "Save data flow" },
        { value: "retrieve", label: "Load data flow" },
        { value: "delete", label: "Delete saved data" },
      ],
    },
    "ai.reality2.rustdemo": {
      label: "Rust Demo",
      icon: "cog",
      color: "#bf360c",
      commands: [
        { value: "add", label: "Add" },
        { value: "subtract", label: "Subtract" },
      ],
    },
  };

  function getCompoundKey(): string {
    if (action.plugin && action.plugin in INTERNAL_PLUGINS) {
      return `${action.plugin}:${action.command}`;
    }
    return action.command;
  }

  function setCompoundKey(key: string) {
    if (key.includes(":")) {
      const [plugin, command] = key.split(":", 2);
      onUpdate({ plugin, command, parameters: {} });
    } else {
      onUpdate({ plugin: undefined, command: key, parameters: {} });
    }
  }

  let compoundKey = $derived(getCompoundKey());

  // Helpers to read/write nested parameter fields
  function param(key: string): unknown {
    return action.parameters?.[key] ?? undefined;
  }

  function paramStr(key: string): string {
    const v = param(key);
    if (v === undefined || v === null) return "";
    if (typeof v === "object") return JSON.stringify(v);
    return String(v);
  }

  function setParam(key: string, value: unknown) {
    const params = { ...(action.parameters ?? {}) };
    if (value === undefined || value === "" || value === null) {
      delete params[key];
    } else {
      params[key] = value;
    }
    onUpdate({ parameters: params });
  }

  function setParams(updates: Record<string, unknown>) {
    const params = { ...(action.parameters ?? {}), ...updates };
    for (const [k, v] of Object.entries(updates)) {
      if (v === undefined || v === "" || v === null) delete params[k];
    }
    onUpdate({ parameters: params });
  }

  // For "set" command: detect value type from current parameters
  function getSetValueType(): "literal" | "jsonpath" | "expr" | "data" | "delete" {
    const v = param("value");
    if (v === undefined || v === null) return "delete";
    if (typeof v === "object" && v !== null) {
      if ("jsonpath" in (v as Record<string, unknown>)) return "jsonpath";
      if ("expr" in (v as Record<string, unknown>)) return "expr";
      if ("data" in (v as Record<string, unknown>)) return "data";
    }
    return "literal";
  }

  function getSetValueContent(): string {
    const v = param("value");
    if (v === undefined || v === null) return "";
    if (typeof v === "object" && v !== null) {
      const obj = v as Record<string, unknown>;
      if (obj.jsonpath !== undefined) return String(obj.jsonpath);
      if (obj.expr !== undefined) {
        if (typeof obj.expr === "string") return obj.expr;
        return JSON.stringify(obj.expr);
      }
      if (obj.data !== undefined) return String(obj.data);
    }
    return String(v);
  }

  function setSetValue(type: string, content: string) {
    let value: unknown;
    switch (type) {
      case "literal":
        value = content;
        break;
      case "jsonpath":
        value = { jsonpath: content };
        break;
      case "expr":
        value = { expr: content };
        break;
      case "data":
        value = { data: content };
        break;
      case "delete":
        value = undefined;
        break;
    }
    setParam("value", value);
  }

  let setValueType = $derived(getSetValueType());
  let setValueContent = $derived(getSetValueContent());

  // Extra parameters for send/signal (exclude known fields)
  const sendKnownKeys = new Set(["event", "to", "delay"]);
  const signalKnownKeys = new Set(["event", "public"]);
  const testKnownKeys = new Set(["if", "then", "else", "to"]);

  function getExtraParams(knownKeys: Set<string>): Record<string, unknown> {
    const result: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(action.parameters ?? {})) {
      if (!knownKeys.has(k)) result[k] = v;
    }
    return result;
  }

  function setExtraParams(knownKeys: Set<string>, extras: Record<string, unknown>) {
    const params: Record<string, unknown> = {};
    // Keep known keys
    for (const [k, v] of Object.entries(action.parameters ?? {})) {
      if (knownKeys.has(k)) params[k] = v;
    }
    // Add extras
    for (const [k, v] of Object.entries(extras)) {
      params[k] = v;
    }
    onUpdate({ parameters: params });
  }

  // --- Send type detection ---
  type SendType = "bee" | "antenna" | "reply" | "broadcast" | "self";

  function deriveSendType(act: ActionModel): SendType {
    if (act.command !== "send") return "bee";
    if (act.plugin) return "antenna";
    const to = act.parameters?.to as string | undefined;
    if (to === "@sender") return "reply";
    if (to === "*" || (to && to.includes("|"))) return "broadcast";
    if (!to) return "self";
    return "bee";
  }

  let sendType = $derived(deriveSendType(action));

  function handleSendTypeChange(newType: SendType) {
    switch (newType) {
      case "bee":
        onUpdate({ plugin: undefined, parameters: { ...(action.parameters ?? {}), to: action.parameters?.to === "@sender" || action.parameters?.to === "*" ? "" : (action.parameters?.to ?? "") } });
        break;
      case "antenna":
        onUpdate({ plugin: action.plugin || "", parameters: { ...(action.parameters ?? {}) } });
        break;
      case "reply":
        onUpdate({ plugin: undefined, parameters: { ...(action.parameters ?? {}), to: "@sender" } });
        break;
      case "broadcast":
        onUpdate({ plugin: undefined, parameters: { ...(action.parameters ?? {}), to: action.parameters?.to === "@sender" ? "*" : (action.parameters?.to || "*") } });
        break;
      case "self": {
        const params = { ...(action.parameters ?? {}) };
        delete params.to;
        onUpdate({ plugin: undefined, parameters: params });
        break;
      }
    }
  }

  const sendTypeOptions: { value: SendType; label: string; icon: string }[] = [
    { value: "bee", label: "Send to Bee", icon: "paper plane" },
    { value: "antenna", label: "Send via Antenna", icon: "wifi" },
    { value: "reply", label: "Reply (@sender)", icon: "reply" },
    { value: "broadcast", label: "Broadcast", icon: "bullhorn" },
    { value: "self", label: "Send to Self", icon: "redo" },
  ];

  // Command label and icon — handles both core commands and internal plugins
  function commandInfo(act: ActionModel): { icon: string; label: string; color: string } {
    if (act.plugin && act.plugin in INTERNAL_PLUGINS) {
      const pluginDef = INTERNAL_PLUGINS[act.plugin];
      const cmdDef = pluginDef.commands.find(c => c.value === act.command);
      return { icon: pluginDef.icon, label: cmdDef?.label ?? act.command, color: pluginDef.color };
    }
    if (act.command === "send") {
      const st = deriveSendType(act);
      switch (st) {
        case "antenna": return { icon: "wifi", label: "Send", color: "#1565c0" };
        case "reply": return { icon: "reply", label: "Send", color: "#00838f" };
        case "broadcast": return { icon: "bullhorn", label: "Send", color: "#e65100" };
        case "self": return { icon: "redo", label: "Send", color: "#616161" };
        default: return { icon: "paper plane", label: "Send", color: "#1565c0" };
      }
    }
    switch (act.command) {
      case "set": return { icon: "edit", label: "Set", color: "#7b1fa2" };
      case "signal": return { icon: "broadcast tower", label: "Signal", color: "#2e7d32" };
      case "test": return { icon: "question circle", label: "Test", color: "#e65100" };
      case "debug": return { icon: "bug", label: "Debug", color: "#616161" };
      default: return { icon: "cog", label: act.command, color: "#333" };
    }
  }

  // Summary text for internal plugin actions
  function pluginSummary(act: ActionModel): string {
    if (act.plugin === "ai.reality2.vars") {
      switch (act.command) {
        case "set": return paramStr("key") ? `${paramStr("key")} = ${paramStr("value") || "(from flow)"}` : "";
        case "get": return paramStr("key") || "";
        case "all": return "all variables";
        case "delete": return paramStr("key") || "";
        case "clear": return "all variables";
      }
    }
    if (act.plugin === "ai.reality2.geospatial") {
      switch (act.command) {
        case "set": return paramStr("latitude") ? `${paramStr("latitude")}, ${paramStr("longitude")}` : "(from flow)";
        case "get": return "position";
        case "search": return paramStr("radius") ? `radius ${paramStr("radius")}m` : "";
        case "delete": return "";
      }
    }
    if (act.plugin === "ai.reality2.backup") {
      switch (act.command) {
        case "store": return "encrypted";
        case "retrieve": return "encrypted";
        case "delete": return "";
      }
    }
    if (act.plugin === "ai.reality2.rustdemo") {
      const v1 = paramStr("value1");
      const v2 = paramStr("value2");
      if (v1 || v2) return `${v1 || "?"} ${act.command === "subtract" ? "-" : "+"} ${v2 || "?"}`;
      return "";
    }
    return "";
  }

  let info = $derived(commandInfo(action));
  let isInternalPlugin = $derived(!!action.plugin && action.plugin in INTERNAL_PLUGINS);
</script>

<div class="action-card" style="border-left-color: {info.color};">
  <div class="action-header" onclick={() => (expanded = !expanded)}
    role="button" tabindex="0" onkeydown={(e) => { if (e.key === 'Enter') expanded = !expanded; }}>
    <i class="icon {expanded ? 'angle down' : 'angle right'}" style="color: #999; font-size: 11px;"></i>
    <i class="{info.icon} icon" style="color: {info.color}; font-size: 11px;"></i>
    <select class="command-select" value={compoundKey}
      onclick={(e) => e.stopPropagation()}
      onchange={(e) => setCompoundKey((e.target as HTMLSelectElement).value)}>
      <optgroup label="Core">
        <option value="set">Set</option>
        <option value="send">Send</option>
        <option value="signal">Signal</option>
        <option value="test">Test</option>
        <option value="debug">Debug</option>
      </optgroup>
      {#each Object.entries(INTERNAL_PLUGINS) as [pluginName, pluginDef]}
        <optgroup label={pluginDef.label}>
          {#each pluginDef.commands as cmd}
            <option value="{pluginName}:{cmd.value}">{cmd.label}</option>
          {/each}
        </optgroup>
      {/each}
    </select>
    <span class="action-summary">
      {#if isInternalPlugin}
        {pluginSummary(action)}
      {:else if action.command === "set"}
        {paramStr("key") || "?"} = {setValueType === "delete" ? "(delete)" : setValueContent || "?"}
      {:else if action.command === "send"}
        {#if sendType === "antenna"}→ {action.plugin || "?"}
        {:else if sendType === "reply"}{paramStr("event") || "?"} → @sender
        {:else if sendType === "broadcast"}{paramStr("event") || "?"} → {paramStr("to") || "*"}
        {:else if sendType === "self"}{paramStr("event") || "?"} → self
        {:else}{paramStr("event") || "?"} → {paramStr("to") || "?"}
        {/if}
      {:else if action.command === "signal"}
        {paramStr("event") || "?"}
      {:else if action.command === "test"}
        {paramStr("then") || "?"} / {paramStr("else") || "?"}
      {:else if action.command === "debug"}
        (inspect data flow)
      {/if}
    </span>
    <button class="remove-btn" onclick={(e) => { e.stopPropagation(); onRemove(); }}
      title="Remove task" aria-label="Remove task">
      <i class="close icon"></i>
    </button>
  </div>

  {#if expanded}
    <div class="action-body">
      <!-- ===== INTERNAL PLUGINS ===== -->
      {#if isInternalPlugin}

        <!-- Variables plugin -->
        {#if action.plugin === "ai.reality2.vars"}
          {#if action.command === "set"}
            <div class="field-row">
              <label>Variable name</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="key"
                  value={paramStr("key")}
                  oninput={(e) => setParam("key", (e.target as HTMLInputElement).value)} />
              </div>
            </div>
            <div class="field-row">
              <label>Value</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="value (leave empty to store from data flow)"
                  value={paramStr("value")}
                  oninput={(e) => {
                    const v = (e.target as HTMLInputElement).value;
                    if (v) {
                      setParam("value", v);
                    } else {
                      // Store from data flow: value = "__key__"
                      const key = paramStr("key");
                      setParam("value", key ? `__${key}__` : undefined);
                    }
                  }} />
              </div>
            </div>
            <div class="hint">Stores a value in the bee's persistent variables. Leave value empty to capture from data flow.</div>
          {:else if action.command === "get"}
            <div class="field-row">
              <label>Variable name</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="key to fetch"
                  value={paramStr("key")}
                  oninput={(e) => setParam("key", (e.target as HTMLInputElement).value)} />
              </div>
            </div>
            <div class="hint">Fetches this variable's value into the data flow.</div>
          {:else if action.command === "all"}
            <div class="hint">Fetches all stored variables into the data flow.</div>
          {:else if action.command === "delete"}
            <div class="field-row">
              <label>Variable name</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="key to delete"
                  value={paramStr("key")}
                  oninput={(e) => setParam("key", (e.target as HTMLInputElement).value)} />
              </div>
            </div>
            <div class="hint">Deletes this variable from the bee's persistent store.</div>
          {:else if action.command === "clear"}
            <div class="hint">Clears all stored variables for this bee.</div>
          {/if}

        <!-- Geospatial plugin -->
        {:else if action.plugin === "ai.reality2.geospatial"}
          {#if action.command === "set"}
            <div class="field-row">
              <label>Latitude</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="(from data flow)"
                  value={paramStr("latitude")}
                  oninput={(e) => {
                    const v = (e.target as HTMLInputElement).value;
                    setParam("latitude", v ? parseFloat(v) || v : undefined);
                  }} />
              </div>
            </div>
            <div class="field-row">
              <label>Longitude</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="(from data flow)"
                  value={paramStr("longitude")}
                  oninput={(e) => {
                    const v = (e.target as HTMLInputElement).value;
                    setParam("longitude", v ? parseFloat(v) || v : undefined);
                  }} />
              </div>
            </div>
            <div class="field-row">
              <label>Altitude</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="0"
                  value={paramStr("altitude")}
                  oninput={(e) => {
                    const v = (e.target as HTMLInputElement).value;
                    setParam("altitude", v ? parseFloat(v) || v : undefined);
                  }} />
              </div>
            </div>
            <div class="field-row">
              <label>Radius</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="0 (privacy radius in metres)"
                  value={paramStr("radius")}
                  oninput={(e) => {
                    const v = (e.target as HTMLInputElement).value;
                    setParam("radius", v ? parseFloat(v) || v : undefined);
                  }} />
              </div>
            </div>
            <div class="hint">Sets this bee's location. Leave fields empty to use values from the data flow.</div>
          {:else if action.command === "get"}
            <div class="hint">Gets this bee's current location into the data flow.</div>
          {:else if action.command === "search"}
            <div class="field-row">
              <label>Radius (metres)</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="search radius"
                  value={paramStr("radius")}
                  oninput={(e) => {
                    const v = (e.target as HTMLInputElement).value;
                    setParam("radius", v ? parseFloat(v) || v : undefined);
                  }} />
              </div>
            </div>
            <div class="hint">Searches for bees within the given radius of this bee.</div>
          {:else if action.command === "delete"}
            <div class="hint">Removes this bee's location from the geospatial index.</div>
          {/if}

        <!-- Backup/Storage plugin -->
        {:else if action.plugin === "ai.reality2.backup"}
          {#if action.command === "store"}
            <div class="hint">Saves the current data flow as an encrypted blob to the database. Set encryption and decryption keys in the bee header.</div>
          {:else if action.command === "retrieve"}
            <div class="hint">Loads saved data from the database into the data flow. Set encryption and decryption keys in the bee header.</div>
          {:else if action.command === "delete"}
            <div class="hint">Deletes the encrypted blob from the database for this bee.</div>
          {/if}

        <!-- Rust Demo plugin -->
        {:else if action.plugin === "ai.reality2.rustdemo"}
          <div class="field-row">
            <label>Value 1</label>
            <div class="ui mini input fluid">
              <input type="text" placeholder="number or __variable__"
                value={paramStr("value1")}
                oninput={(e) => {
                  const v = (e.target as HTMLInputElement).value;
                  setParam("value1", v ? (isNaN(Number(v)) ? v : Number(v)) : undefined);
                }} />
            </div>
          </div>
          <div class="field-row">
            <label>Value 2</label>
            <div class="ui mini input fluid">
              <input type="text" placeholder="number or __variable__"
                value={paramStr("value2")}
                oninput={(e) => {
                  const v = (e.target as HTMLInputElement).value;
                  setParam("value2", v ? (isNaN(Number(v)) ? v : Number(v)) : undefined);
                }} />
            </div>
          </div>
          <div class="hint">
            {#if action.command === "add"}
              Adds two numbers using Rust NIF. Result available as <code>answer</code> in the data flow.
            {:else}
              Subtracts value2 from value1 using Rust NIF. Result available as <code>answer</code> in the data flow.
            {/if}
          </div>
        {/if}

      <!-- ===== CORE COMMANDS ===== -->
      {:else}

      <!-- (send type dropdown is inside the send section below) -->

      <!-- ===== SET ===== -->
      {#if action.command === "set"}
        <div class="field-row">
          <label>Key</label>
          <div class="ui mini input fluid">
            <input type="text" placeholder="variable name"
              value={paramStr("key")}
              oninput={(e) => setParam("key", (e.target as HTMLInputElement).value)} />
          </div>
        </div>
        <div class="field-row">
          <label>Value type</label>
          <select class="ui mini dropdown fluid-select"
            value={setValueType}
            onchange={(e) => setSetValue((e.target as HTMLSelectElement).value, setValueContent)}>
            <option value="literal">Literal</option>
            <option value="jsonpath">JSON Path</option>
            <option value="expr">Expression</option>
            <option value="data">Bee Data</option>
            <option value="delete">Delete key</option>
          </select>
        </div>
        {#if setValueType !== "delete"}
          <div class="field-row">
            <label>
              {#if setValueType === "literal"}Value
              {:else if setValueType === "jsonpath"}Path
              {:else if setValueType === "expr"}Expression
              {:else if setValueType === "data"}Data key
              {/if}
            </label>
            <div class="ui mini input fluid">
              <input type="text"
                placeholder={setValueType === "jsonpath" ? "e.g. answer.q" :
                             setValueType === "expr" ? "e.g. counter + 1" :
                             setValueType === "data" ? "key from bee data" :
                             "value or __variable__"}
                value={setValueContent}
                oninput={(e) => setSetValue(setValueType, (e.target as HTMLInputElement).value)} />
            </div>
          </div>
          {#if setValueType === "literal"}
            <div class="hint">Use <code>__name__</code> to reference a value from the data flow</div>
          {:else if setValueType === "jsonpath"}
            <div class="hint">Extract nested values, e.g. <code>answer.q</code> or <code>items.[].name</code></div>
          {:else if setValueType === "expr"}
            <div class="hint">Arithmetic expression, e.g. <code>count + 1</code> or <code>(a + b) * 2</code></div>
          {:else if setValueType === "data"}
            <div class="hint">Read from the bee's own stored data</div>
          {/if}
        {:else}
          <div class="hint">Removes this key from the data flow</div>
        {/if}

      <!-- ===== SEND ===== -->
      {:else if action.command === "send"}
        <div class="field-row">
          <label>Send type</label>
          <select class="fluid-select"
            value={sendType}
            onchange={(e) => handleSendTypeChange((e.target as HTMLSelectElement).value as SendType)}>
            {#each sendTypeOptions as opt}
              <option value={opt.value}>{opt.label}</option>
            {/each}
          </select>
        </div>

        {#if sendType === "antenna"}
          <div class="field-row">
            <label>Antenna</label>
            <div class="ui mini input fluid">
              <input type="text" placeholder="e.g. io.zenquotes.api"
                value={action.plugin ?? ""}
                oninput={(e) => onUpdate({ plugin: (e.target as HTMLInputElement).value || undefined })} />
            </div>
          </div>
          <div class="hint">Sends the data flow through an external antenna/plugin.</div>
        {:else}
          <div class="field-row">
            <label>Event</label>
            <div class="ui mini input fluid">
              <input type="text" placeholder="event name"
                value={paramStr("event")}
                oninput={(e) => setParam("event", (e.target as HTMLInputElement).value)} />
            </div>
          </div>

          {#if sendType === "bee"}
            <div class="field-row">
              <label>To</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="bee name or ID"
                  value={paramStr("to")}
                  oninput={(e) => setParam("to", (e.target as HTMLInputElement).value)} />
              </div>
            </div>
            <div class="hint">Sends the data flow as event parameters to another bee.</div>
          {:else if sendType === "reply"}
            <div class="hint">Replies to the sender of the event that triggered this chain. Target: <code>@sender</code></div>
          {:else if sendType === "broadcast"}
            <div class="field-row">
              <label>To pattern</label>
              <div class="ui mini input fluid">
                <input type="text" placeholder="* (all) or NodeName|BeeName"
                  value={paramStr("to")}
                  oninput={(e) => setParam("to", (e.target as HTMLInputElement).value)} />
              </div>
            </div>
            <div class="hint">Broadcasts to all matching bees. Use <code>*</code> for all, or <code>*|Name</code> for named bees on all nodes.</div>
          {:else if sendType === "self"}
            <div class="hint">Sends the event back to this bee.</div>
          {/if}

          <div class="field-row">
            <label>Delay (ms)</label>
            <div class="ui mini input fluid">
              <input type="text" placeholder="0"
                value={paramStr("delay")}
                oninput={(e) => {
                  const v = (e.target as HTMLInputElement).value;
                  setParam("delay", v ? parseInt(v) || undefined : undefined);
                }} />
            </div>
          </div>
        {/if}

        {@const extras = getExtraParams(sendKnownKeys)}
        {#if Object.keys(extras).length > 0}
          <div class="extra-params">
            <label>Extra parameters</label>
            <DataEditor data={extras} onChange={(d) => setExtraParams(sendKnownKeys, d)} />
          </div>
        {/if}

      <!-- ===== SIGNAL ===== -->
      {:else if action.command === "signal"}
        <div class="field-row">
          <label>Event</label>
          <div class="ui mini input fluid">
            <input type="text" placeholder="signal event name"
              value={paramStr("event")}
              oninput={(e) => setParam("event", (e.target as HTMLInputElement).value)} />
          </div>
        </div>
        <div class="field-row">
          <label style="display: flex; align-items: center; gap: 6px;">
            <input type="checkbox" checked={param("public") === true || param("public") === "true"}
              onchange={(e) => setParam("public", (e.target as HTMLInputElement).checked || undefined)} />
            Public signal
          </label>
        </div>
        <div class="hint">Broadcasts the data flow to external listeners (apps, devices).</div>
        {@const extras = getExtraParams(signalKnownKeys)}
        {#if Object.keys(extras).length > 0}
          <div class="extra-params">
            <label>Extra parameters</label>
            <DataEditor data={extras} onChange={(d) => setExtraParams(signalKnownKeys, d)} />
          </div>
        {/if}

      <!-- ===== TEST ===== -->
      {:else if action.command === "test"}
        <div class="field-row">
          <label>Condition</label>
          <div class="ui mini input fluid">
            <input type="text" placeholder="e.g. counter > 10"
              value={typeof param("if") === "string" ? paramStr("if") : JSON.stringify(param("if") ?? "")}
              oninput={(e) => setParam("if", (e.target as HTMLInputElement).value)} />
          </div>
        </div>
        <div class="field-row">
          <label>Then send event</label>
          <div class="ui mini input fluid">
            <input type="text" placeholder="event if true"
              value={paramStr("then")}
              oninput={(e) => setParam("then", (e.target as HTMLInputElement).value)} />
          </div>
        </div>
        <div class="field-row">
          <label>Else send event</label>
          <div class="ui mini input fluid">
            <input type="text" placeholder="event if false"
              value={paramStr("else")}
              oninput={(e) => setParam("else", (e.target as HTMLInputElement).value)} />
          </div>
        </div>
        <div class="field-row">
          <label>To</label>
          <div class="ui mini input fluid">
            <input type="text" placeholder="self (default)"
              value={paramStr("to")}
              oninput={(e) => setParam("to", (e.target as HTMLInputElement).value)} />
          </div>
        </div>
        <div class="hint">Tests a condition against data flow values. Sends one of two events.</div>

      <!-- ===== DEBUG ===== -->
      {:else if action.command === "debug"}
        <div class="hint">Outputs the entire current data flow to the debug signal for inspection.</div>
      {/if}

      {/if}
    </div>
  {/if}
</div>

<style>
  .action-card {
    background: #fff;
    border: 1px solid #e0e0e0;
    border-left: 3px solid #999;
    border-radius: 4px;
    margin-bottom: 0;
    overflow: hidden;
  }
  .action-header {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 6px 8px;
    cursor: pointer;
    background: #fafafa;
  }
  .action-header:hover {
    background: #f0f0f0;
  }
  .command-select {
    font-size: 11px;
    font-weight: 600;
    padding: 1px 4px;
    border: 1px solid #ddd;
    border-radius: 3px;
    background: #fff;
    cursor: pointer;
  }
  .action-summary {
    font-size: 11px;
    color: #888;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    flex: 1;
  }
  .remove-btn {
    border: none;
    background: none;
    cursor: pointer;
    color: #ccc;
    padding: 2px;
    font-size: 11px;
  }
  .remove-btn:hover {
    color: #e74c3c;
  }
  .action-body {
    padding: 8px 10px;
    border-top: 1px solid #f0f0f0;
  }
  .field-row {
    margin-bottom: 8px;
  }
  .field-row label {
    display: block;
    font-size: 10px;
    font-weight: 600;
    color: #777;
    margin-bottom: 2px;
    text-transform: uppercase;
    letter-spacing: 0.3px;
  }
  .fluid-select {
    width: 100%;
    font-size: 12px;
    padding: 4px 6px;
    border: 1px solid rgba(34, 36, 38, 0.15);
    border-radius: 4px;
  }
  .hint {
    font-size: 10px;
    color: #999;
    margin-top: 2px;
    margin-bottom: 4px;
    line-height: 1.4;
  }
  .hint code {
    background: #f0e8d0;
    padding: 1px 4px;
    border-radius: 2px;
    font-size: 10px;
    color: #8a6d00;
  }
  .extra-params {
    margin-top: 8px;
    padding-top: 6px;
    border-top: 1px dashed #eee;
  }
  .extra-params label {
    display: block;
    font-size: 10px;
    font-weight: 600;
    color: #777;
    margin-bottom: 2px;
    text-transform: uppercase;
    letter-spacing: 0.3px;
  }
</style>
