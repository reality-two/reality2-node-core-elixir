/**
 * Maps App.svelte data formats to 3D visualization component types.
 */

import type { NodeInfo, Peer, LiveSentant } from '../types';
import type { LiveSentantModel, LiveSwarmGroupModel } from '../models/canvas';

/**
 * Maps hiveNodeInfo from GraphQL to NodeInfo for 3D visualization.
 */
export function mapHiveNodeInfoToNodeInfo(hiveNodeInfo: any): NodeInfo | null {
  if (!hiveNodeInfo) return null;
  return {
    id: hiveNodeInfo.nodeId ?? '',
    name: hiveNodeInfo.nodeName ?? 'My Hive',
    trustGroupId: hiveNodeInfo.trustGroupId,
    trustGroupName: hiveNodeInfo.trustGroupName,
    isKeyHolder: !hiveNodeInfo.isProvisional,
  };
}

/**
 * Maps hivePeers from GraphQL to Peer[] for 3D visualization.
 * Peers closer to the hive have stronger signals (lower absolute RSSI).
 */
export function mapHivePeersToPeers(
  hivePeers: any[],
  localTrustGroupId?: string
): Peer[] {
  if (!hivePeers || !Array.isArray(hivePeers)) return [];
  return hivePeers.map(p => ({
    nodeId: p.nodeId ?? p.id ?? `peer-${Math.random().toString(36).slice(2, 8)}`,
    name: p.nodeName ?? p.name,
    publicKey: p.publicKey,
    transport: p.transport ?? 'unknown',
    rssi: typeof p.rssi === 'number' ? p.rssi : -70,
    sameTrustGroup: localTrustGroupId
      ? p.trustGroupId === localTrustGroupId
      : false,
    lastSeen: p.lastSeen,
  }));
}

/**
 * Maps LiveSentantModel[] to LiveSentant[] for 3D visualization.
 * Extracts swarm name from the hive group structure for clustering.
 */
export function mapLiveSentantModelsToLiveSentants(
  liveSentants: LiveSentantModel[],
  liveSwarmGroups: LiveSwarmGroupModel[]
): LiveSentant[] {
  if (!liveSentants || !Array.isArray(liveSentants)) return [];

  // Create a map of swarm group ID to swarm name
  const swarmMap = new Map<string, string>();
  for (const sg of liveSwarmGroups ?? []) {
    swarmMap.set(sg._nodeId, sg.swarmName);
  }

  return liveSentants.map(ls => {
    // Derive swarm name from hive group ID
    let swarm: string | undefined;
    if (ls._hiveGroupId) {
      // Check if it's directly a swarm group
      if (swarmMap.has(ls._hiveGroupId)) {
        swarm = swarmMap.get(ls._hiveGroupId);
      } else {
        // Check if any swarm group contains this sentant
        for (const [groupId, swarmName] of swarmMap) {
          if (ls._hiveGroupId === groupId) {
            swarm = swarmName;
            break;
          }
        }
      }
    }

    return {
      id: ls.id,
      name: ls.name,
      description: ls.description,
      events: ls.events,
      signals: ls.signals,
      nodeId: ls.nodeId,
      nodeName: ls.nodeName,
      swarm,
    };
  });
}
