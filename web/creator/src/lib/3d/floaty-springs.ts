// FloatySprings - Ported from Godot GDScript
// Creates organic orbital motion using spring physics
//
// Dr. Roy C. Davies - Original Godot implementation
// Ported to Three.js/TypeScript for Threlte

import { Vector3 } from 'three';

export interface FloatySpringConfig {
  /** Distance siblings try to maintain from each other */
  closestDistance?: number;
  /** Spring stiffness for sibling repulsion */
  springStiffness?: number;
  /** Spring stiffness pulling toward center */
  centreSpringStiffness?: number;
  /** Target distance from center */
  centreDistance?: number;
  /** Velocity damping (prevents oscillation) */
  damping?: number;
  /** Friction coefficient */
  friction?: number;
  /** Mass of the object */
  mass?: number;
  /** Optional: Affinity to same-group siblings (negative = attract) */
  groupAffinity?: number;
}

export class FloatySprings {
  // Config
  closestDistance: number;
  springStiffness: number;
  centreSpringStiffness: number;
  centreDistance: number;
  damping: number;
  friction: number;
  mass: number;
  groupAffinity: number;

  // State
  private velocity = new Vector3(0, 0, 0);
  private force = new Vector3(0, 0, 0);
  private tempVec = new Vector3();

  // Position (managed externally, but we track it)
  position: Vector3;

  // Optional group ID for affinity calculations
  groupId?: string;

  constructor(
    initialPosition?: Vector3,
    config: FloatySpringConfig = {}
  ) {
    this.closestDistance = config.closestDistance ?? 3.0;
    this.springStiffness = config.springStiffness ?? 0.1;
    this.centreSpringStiffness = config.centreSpringStiffness ?? 1.0;
    this.centreDistance = config.centreDistance ?? 5.0;
    this.damping = config.damping ?? 0.1;
    this.friction = config.friction ?? 0.5;
    this.mass = config.mass ?? 1.0;
    this.groupAffinity = config.groupAffinity ?? 0;

    // Start with small random offset to break symmetry
    this.position = initialPosition?.clone() ?? new Vector3(
      (Math.random() - 0.5) * 0.2,
      (Math.random() - 0.5) * 0.2,
      (Math.random() - 0.5) * 0.2
    );
  }

  /**
   * Update physics simulation
   * @param delta Time since last frame in seconds
   * @param siblings Array of other FloatySprings objects to interact with
   * @param center Optional center point (defaults to origin)
   */
  update(
    delta: number,
    siblings: FloatySprings[],
    center: Vector3 = new Vector3(0, 0, 0)
  ): void {
    this.force.set(0, 0, 0);

    // Sibling interaction forces
    for (const sibling of siblings) {
      if (sibling === this) continue;

      // Direction from sibling to us
      this.tempVec.subVectors(this.position, sibling.position);
      const dist = this.tempVec.length();

      if (dist < 0.001) continue; // Avoid division by zero

      // Spring force based on distance from desired separation
      const forceValue = dist - this.closestDistance;

      this.tempVec.normalize();

      // Base repulsion/attraction
      let stiffness = this.springStiffness;

      // If same group and affinity is set, modify the force
      if (this.groupId && sibling.groupId && this.groupId === sibling.groupId) {
        stiffness -= this.groupAffinity; // Negative affinity = attraction
      }

      this.tempVec.multiplyScalar(-stiffness * forceValue);

      // Add damping relative to sibling
      const relativeVel = this.tempVec.clone().subVectors(this.velocity, sibling.velocity);
      this.tempVec.addScaledVector(relativeVel, -this.damping * 0.5);

      this.force.add(this.tempVec);
    }

    // Center attraction force
    this.tempVec.subVectors(this.position, center);
    const centerDist = this.tempVec.length();

    if (centerDist > 0.001) {
      const centerForce = centerDist - this.centreDistance;
      this.tempVec.normalize();
      this.tempVec.multiplyScalar(-this.centreSpringStiffness * centerForce);
      this.force.add(this.tempVec);
    }

    // Velocity damping
    this.tempVec.copy(this.velocity).multiplyScalar(-this.damping);
    this.force.add(this.tempVec);

    // Friction
    this.tempVec.copy(this.velocity).multiplyScalar(-this.friction);
    this.force.add(this.tempVec);

    // Integrate: F = ma, so a = F/m, then v += a*dt
    this.velocity.addScaledVector(this.force, delta / this.mass);

    // Update position
    this.position.addScaledVector(this.velocity, delta);
  }

  /**
   * Apply an impulse (instant velocity change)
   */
  impulse(force: Vector3): void {
    this.velocity.add(force);
  }

  /**
   * Set target distance from center (useful for RSSI-based positioning)
   */
  setTargetDistance(distance: number): void {
    this.centreDistance = distance;
  }

  /**
   * Get current velocity magnitude (useful for activity detection)
   */
  getSpeed(): number {
    return this.velocity.length();
  }
}

/**
 * Manage a collection of FloatySprings objects
 */
export class FloatySpringSystem {
  private springs: Map<string, FloatySprings> = new Map();

  add(id: string, spring: FloatySprings): void {
    this.springs.set(id, spring);
  }

  remove(id: string): void {
    this.springs.delete(id);
  }

  get(id: string): FloatySprings | undefined {
    return this.springs.get(id);
  }

  getAll(): FloatySprings[] {
    return Array.from(this.springs.values());
  }

  update(delta: number, center?: Vector3): void {
    const all = this.getAll();
    for (const spring of all) {
      spring.update(delta, all, center);
    }
  }

  clear(): void {
    this.springs.clear();
  }
}
