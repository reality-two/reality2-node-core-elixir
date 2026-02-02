<script lang="ts">
  import { Handle, Position } from "@xyflow/svelte";

  let { data } = $props();
  let target = $derived(data.state.sendTarget || "");
  let sendType = $derived(data.state.sendType || "bee");

  const iconMap: Record<string, string> = {
    bee: "paper plane outline",
    reply: "reply",
    broadcast: "bullhorn",
    self: "redo",
  };

  const targetLabel: Record<string, string> = {
    reply: "@sender",
    broadcast: target || "*",
    self: "self",
    bee: target,
  };

  const icon = iconMap[sendType] || "paper plane outline";
  const label = targetLabel[sendType] || target;
</script>

<div class="fsm-send" class:reply={sendType === "reply"} class:broadcast={sendType === "broadcast"} class:self-send={sendType === "self"}>
  <Handle id="in" type="target" position={Position.Left} />
  <i class="{icon} icon" style="font-size: 10px; margin: 0;"></i>
  <span class="send-label">
    {data.state.name}{#if label} <span class="send-target">&rarr; {label}</span>{/if}
  </span>
</div>

<style>
  .fsm-send {
    background: #faf5ff;
    border: 2px solid #ab7dd6;
    border-radius: 20px;
    padding: 5px 14px;
    font-size: 10px;
    font-weight: 600;
    color: #6a3d9a;
    min-width: 50px;
    text-align: center;
    display: flex;
    align-items: center;
    gap: 4px;
    white-space: nowrap;
    cursor: default;
    box-shadow: 0 1px 3px rgba(106, 61, 154, 0.1);
  }
  .fsm-send.reply {
    border-color: #00838f;
    color: #00606b;
    background: #f0fafb;
  }
  .fsm-send.broadcast {
    border-color: #e65100;
    color: #bf4500;
    background: #fff8f0;
  }
  .fsm-send.self-send {
    border-color: #888;
    color: #666;
    background: #f8f8f8;
  }
  .send-label {
    max-width: 180px;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .send-target {
    font-weight: 400;
    opacity: 0.8;
  }
</style>
