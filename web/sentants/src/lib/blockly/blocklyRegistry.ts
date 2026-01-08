/**
 * Blockly Module Registry
 *
 * Centralizes all custom Blockly block imports and provides a registration function.
 * This reduces the number of imports needed in components using Blockly.
 */

// Reality2 Core Blocks
import reality2_swarm from "./reality2_swarm";
import reality2_sentant from "./reality2_sentant";
import reality2_key_value from "./reality2_key_value";
import reality2_data from "./reality2_data";
import reality2_encrypt_decrypt_keys from "./reality2_encrypt_decrypt_keys";
import reality2_get_plugin from "./reality2_get_plugin";
import reality2_post_plugin from "./reality2_post_plugin";
import reality2_plugin_header from "./reality2_plugin_header";
import reality2_plugin_body from "./reality2_plugin_body";
import reality2_plugin_body_string from "./reality2_plugin_body_string";
import reality2_plugin_parameter from "./reality2_plugin_parameter";

// Automation Blocks
import reality2_automation from "./reality2_automation";
import reality2_parameter from "./reality2_parameter";
import reality2_transition from "./reality2_transition";
import reality2_transition_no_params from "./reality2_transition_no_params";
import reality2_start_transition from "./reality2_start_transition";
import reality2_start_transition_no_params from "./reality2_start_transition_no_params";
import reality2_simple_transition from "./reality2_simple_transition";
import reality2_simple_transition_no_params from "./reality2_simple_transition_no_params";
import reality2_start_transition_simple from "./reality2_start_transition_simple";
import reality2_monitor from "./reality2_monitor";

// Action Blocks
import reality2_action_set from "./reality2_action_set";
import reality2_action_set_clear from "./reality2_action_set_clear";
import reality2_action_set_jsonpath from "./reality2_action_set_jsonpath";
import reality2_action_set_data from "./reality2_action_set_data";
import reality2_action_set_calculation from "./reality2_action_set_calculation";
import reality2_action_set_calc_binary from "./reality2_action_set_calc_binary";
import reality2_action_set_calc_unary from "./reality2_action_set_calc_unary";
import reality2_action_set_value from "./reality2_action_set_value";
import reality2_action_send from "./reality2_action_send";
import reality2_action_send_no_params from "./reality2_action_send_no_params";
import reality2_action_send_now from "./reality2_action_send_now";
import reality2_action_send_now_no_params from "./reality2_action_send_now_no_params";
import reality2_action_send_plugin from "./reality2_action_send_plugin";
import reality2_action_send_plugin_no_params from "./reality2_action_send_plugin_no_params";
import reality2_action_send_plugin_no_params_no_event from "./reality2_action_send_plugin_no_params_no_event";
import reality2_action_debug from "./reality2_action_debug";
import reality2_action_test from "./reality2_action_test";
import reality2_action_test_no_params from "./reality2_action_test_no_params";
import reality2_action_test_simple from "./reality2_action_test_simple";
import reality2_action_signal from "./reality2_action_signal";
import reality2_action_signal_no_params from "./reality2_action_signal_no_params";
import reality2_action_parameter from "./reality2_action_parameter";

// Variable Blocks
import ai_reality2_vars_set from "./ai_reality2_vars_set";
import ai_reality2_vars_set_no_value from "./ai_reality2_vars_set_no_value";
import ai_reality2_vars_get from "./ai_reality2_vars_get";
import ai_reality2_vars_all from "./ai_reality2_vars_all";
import ai_reality2_vars_delete from "./ai_reality2_vars_delete";
import ai_reality2_vars_clear from "./ai_reality2_vars_clear";

// Geospatial Blocks
import ai_reality2_geospatial_set from "./ai_reality2_geospatial_set";
import ai_reality2_geospatial_set_simple from "./ai_reality2_geospatial_set_simple";
import ai_reality2_geospatial_set_geohash from "./ai_reality2_geospatial_set_geohash";
import ai_reality2_geospatial_set_radius from "./ai_reality2_geospatial_set_radius";
import ai_reality2_geospatial_get from "./ai_reality2_geospatial_get";
import ai_reality2_geospatial_search from "./ai_reality2_geospatial_search";
import ai_reality2_geospatial_remove from "./ai_reality2_geospatial_remove";

// Backup Blocks
import ai_reality2_backup_save from "./ai_reality2_backup_save";
import ai_reality2_backup_load from "./ai_reality2_backup_load";
import ai_reality2_backup_delete from "./ai_reality2_backup_delete";

/**
 * Registry of all Blockly blocks
 * Organized by category for easier maintenance
 */
export const blocklyModules = {
  core: {
    reality2_swarm,
    reality2_sentant,
    reality2_key_value,
    reality2_data,
    reality2_encrypt_decrypt_keys,
    reality2_get_plugin,
    reality2_post_plugin,
    reality2_plugin_header,
    reality2_plugin_body,
    reality2_plugin_body_string,
    reality2_plugin_parameter,
  },
  automation: {
    reality2_automation,
    reality2_parameter,
    reality2_transition,
    reality2_transition_no_params,
    reality2_start_transition,
    reality2_start_transition_no_params,
    reality2_simple_transition,
    reality2_simple_transition_no_params,
    reality2_start_transition_simple,
    reality2_monitor,
  },
  actions: {
    reality2_action_set,
    reality2_action_set_clear,
    reality2_action_set_jsonpath,
    reality2_action_set_data,
    reality2_action_set_calculation,
    reality2_action_set_calc_binary,
    reality2_action_set_calc_unary,
    reality2_action_set_value,
    reality2_action_send,
    reality2_action_send_no_params,
    reality2_action_send_now,
    reality2_action_send_now_no_params,
    reality2_action_send_plugin,
    reality2_action_send_plugin_no_params,
    reality2_action_send_plugin_no_params_no_event,
    reality2_action_debug,
    reality2_action_test,
    reality2_action_test_no_params,
    reality2_action_test_simple,
    reality2_action_signal,
    reality2_action_signal_no_params,
    reality2_action_parameter,
  },
  variables: {
    ai_reality2_vars_set,
    ai_reality2_vars_set_no_value,
    ai_reality2_vars_get,
    ai_reality2_vars_all,
    ai_reality2_vars_delete,
    ai_reality2_vars_clear,
  },
  geospatial: {
    ai_reality2_geospatial_set,
    ai_reality2_geospatial_set_simple,
    ai_reality2_geospatial_set_geohash,
    ai_reality2_geospatial_set_radius,
    ai_reality2_geospatial_get,
    ai_reality2_geospatial_search,
    ai_reality2_geospatial_remove,
  },
  backup: {
    ai_reality2_backup_save,
    ai_reality2_backup_load,
    ai_reality2_backup_delete,
  },
};

/**
 * Get a flat array of all blockly modules
 */
export function getAllBlocklyModules() {
  return Object.values(blocklyModules).flatMap((category) =>
    Object.values(category)
  );
}
