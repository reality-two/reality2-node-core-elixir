// ----------------------------------------------------------------------------------------------------
// Some useful Blockly-related functions.
// Author: Roy C. Davies, September, 2024
// ----------------------------------------------------------------------------------------------------

import R2 from "../reality2";
import reality2_action_set from "./reality2_action_set";
import reality2_action_set_clear from "./reality2_action_set_clear";
import reality2_action_debug from "./reality2_action_debug";
import reality2_action_send from "./reality2_action_send";
import reality2_action_send_no_params from "./reality2_action_send_no_params";
import reality2_action_send_now from "./reality2_action_send_now";
import reality2_action_send_now_no_params from "./reality2_action_send_now_no_params";
import reality2_action_send_plugin from "./reality2_action_send_plugin";
import reality2_action_send_plugin_no_params from "./reality2_action_send_plugin_no_params";
import reality2_action_signal from "./reality2_action_signal";
import reality2_action_signal_no_params from "./reality2_action_signal_no_params";
import reality2_action_test from "./reality2_action_test";
import reality2_action_test_no_params from "./reality2_action_test_no_params";
import reality2_action_test_simple from "./reality2_action_test_simple";

import ai_reality2_vars_set from "./ai_reality2_vars_set";
import ai_reality2_vars_set_no_value from "./ai_reality2_vars_set_no_value";
import ai_reality2_vars_get from "./ai_reality2_vars_get";
import ai_reality2_vars_all from "./ai_reality2_vars_all";
import ai_reality2_vars_delete from "./ai_reality2_vars_all";
import ai_reality2_vars_clear from "./ai_reality2_vars_clear";

import ai_reality2_geospatial_set from "./ai_reality2_geospatial_set";
import ai_reality2_geospatial_set_simple from "./ai_reality2_geospatial_set_simple";
import ai_reality2_geospatial_set_geohash from "./ai_reality2_geospatial_set_geohash";
import ai_reality2_geospatial_set_radius from "./ai_reality2_geospatial_set_radius";
import ai_reality2_geospatial_get from "./ai_reality2_geospatial_get";
import ai_reality2_geospatial_search from "./ai_reality2_geospatial_search";
import ai_reality2_geospatial_remove from "./ai_reality2_geospatial_remove";

import ai_reality2_backup_save from "./ai_reality2_backup_save";
import ai_reality2_backup_load from "./ai_reality2_backup_load";
import ai_reality2_backup_delete from "./ai_reality2_backup_delete";


// ----------------------------------------------------------------------------------------------------
// Split and convert conjoined JSON strings
// ----------------------------------------------------------------------------------------------------
export function splitConcatenatedJSON(jsonString: string, is_object: boolean = true): any {
    let objects: any[] = [];
    let braceLevel = 0;
    let start = 0;

    for (let i = 0; i < jsonString.length; i++) {
        const char = jsonString[i];

        if (char === '{') {
            if (braceLevel === 0) {
                start = i;
            }
            braceLevel++;
        } else if (char === '}') {
            braceLevel--;
            if (braceLevel === 0) {
                try {
                    const jsonObj = JSON.parse(jsonString.slice(start, i + 1));
                    objects.push(jsonObj);
                } catch (e) {
                    console.error("Invalid JSON object:", e);
                }
            }
        }
    }

    if (is_object) {
        let single_object = objects.reduce((accumulator, currentObject) => {
            return { ...accumulator, ...currentObject };
          }, {});
        return single_object;
    }
    else {
        return objects;
    }
}
// ----------------------------------------------------------------------------------------------------



// ----------------------------------------------------------------------------------------------------
// Interpret the actions required by each Transition
// ----------------------------------------------------------------------------------------------------
export function interpret_actions(transition: any, block: any)
{
    // Check if there are actions
    let actions: [any] = R2.JSONPath(transition, "actions");

    // If there are, go backwards through the array creating each block, and linking to the next
    if (actions) {
        let actions_block = actions.reduceRight((acc, action) => {
            let action_block: any;
            let plugin_name = R2.JSONPath(action, "plugin");

            if (plugin_name == "ai.reality2.vars")
            {
                let command = R2.JSONPath(action, "command");
                switch (command) {
                    case "set":
                        let key = R2.JSONPath(action, "parameters.key");
                        let value = R2.JSONPath(action, "parameters.value");
                        if (value === "__"+key+"__") {
                            action_block = ai_reality2_vars_set_no_value.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            };
                        } else {
                            action_block = ai_reality2_vars_set.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            };
                        }
                        break;
                    case "get": 
                        action_block = ai_reality2_vars_get.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                    case "all": 
                        action_block = ai_reality2_vars_all.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                    case "delete": 
                        action_block = ai_reality2_vars_delete.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                    case "clear": 
                        action_block = ai_reality2_vars_clear.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                }
            }
            else if (plugin_name == "ai.reality2.geospatial")
            {
                let command = R2.JSONPath(action, "command");
                switch (command) {
                    case "set":
                        let latitude = R2.JSONPath(action, "parameters.latitude");
                        let longitude = R2.JSONPath(action, "parameters.longitude");
                        let geohash = R2.JSONPath(action, "parameters.geohash");

                        if(!latitude && !longitude && !geohash) {
                            action_block = ai_reality2_geospatial_set_simple.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            };
                        } else if(!(latitude || longitude) && geohash) {
                            action_block = ai_reality2_geospatial_set_geohash.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            };                            
                        } else {
                            action_block = ai_reality2_geospatial_set.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            };
                        }
                        break;
                    case "get":
                        action_block = ai_reality2_geospatial_get.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                    case "search":
                        action_block = ai_reality2_geospatial_search.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                    case "remove":
                        action_block = ai_reality2_geospatial_remove.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                }
            }
            else if (plugin_name == "ai.reality2.backup")
            {
                let command = R2.JSONPath(action, "command");
                switch (command) {
                    case "store":
                        action_block = ai_reality2_backup_save.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                    case "retrieve":
                        action_block = ai_reality2_backup_load.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                    case "delete":
                        action_block = ai_reality2_backup_delete.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        };
                        break;
                }
            }
            else if (R2.JSONPath(action, "plugin")) {
                var parameters = R2.JSONPath(action, "parameters.parameters");
                if (parameters && Object.keys(parameters).length > 0) {
                    action_block = reality2_action_send_plugin.construct(action);
                    if (action_block && acc) {
                        action_block["next"] =  { "block": acc };
                    }
                } else {
                    action_block = reality2_action_send_plugin_no_params.construct(action);
                    if (action_block && acc) {
                        action_block["next"] =  { "block": acc };
                    }
                }
            }
            else
            {
                switch (R2.JSONPath(action, "command")) {
                    case "set":
                        let value = R2.JSONPath(action, "parameters.value");
                        if (value != null) {
                            switch (value) {
                                case "radius":
                                    action_block = ai_reality2_geospatial_set_radius.construct(action);
                                    break;
                                case "geohash":
                                    action_block = ai_reality2_geospatial_set_geohash.construct(action);
                                    break;
                                default:
                                    action_block = reality2_action_set.construct(action);
                                    break;
                            }
                            if (action_block && acc) {
                                action_block["next"] = { "block": acc };
                            }
                        }
                        else {
                            action_block = reality2_action_set_clear.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            }                           
                        }
                        break;
                    case "send":
                        var delay = R2.ToSimple(R2.JSONPath(action, "parameters.delay"));
                        var parameters = R2.JSONPath(action, "parameters.parameters");
                        if (delay > 0) {
                            if (parameters && Object.keys(parameters).length > 0) {
                                action_block = reality2_action_send.construct(action);
                                if (action_block && acc) {
                                    action_block["next"] =  { "block": acc };
                                }
                            } else {
                                action_block = reality2_action_send_no_params.construct(action);
                                if (action_block && acc) {
                                    action_block["next"] =  { "block": acc };
                                }
                            }
                        } else {
                            if (parameters && Object.keys(parameters).length > 0) {
                                action_block = reality2_action_send_now.construct(action);
                                if (action_block && acc) {
                                    action_block["next"] =  { "block": acc };
                                }
                            } else {
                                action_block = reality2_action_send_now_no_params.construct(action);
                                if (action_block && acc) {
                                    action_block["next"] =  { "block": acc };
                                }
                            }
                        }
                        break;
                    case "signal":
                        var parameters = R2.JSONPath(action, "parameters.parameters");
                        if (parameters && Object.keys(parameters).length > 0) {
                            action_block = reality2_action_signal.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            }
                        } else {
                            action_block = reality2_action_signal_no_params.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            }
                        }
                        break;
                    case "debug":
                        action_block = reality2_action_debug.construct(action);
                        if (action_block && acc) {
                            action_block["next"] =  { "block": acc };
                        }
                        break;
                    case "test":
                        var parameters = R2.JSONPath(action, "parameters.parameters");
                        var else_param = R2.JSONPath(action, "parameters.else");
                        var to = R2.JSONPath(action, "parameters.to");
                        if (parameters && Object.keys(parameters).length > 0) {
                            action_block = reality2_action_test.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            }
                        } else if (else_param || to) {
                            action_block = reality2_action_test_no_params.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            }  
                        } else {
                            action_block = reality2_action_test_simple.construct(action);
                            if (action_block && acc) {
                                action_block["next"] =  { "block": acc };
                            }                            
                        }
                        break;                       
                }
            }
    
            // accumulate the block so far
            return action_block;
        }, null);
    
        // Sentants starts as a block
        block["inputs"]["actions"] = { "block": actions_block };
    }

    return (block);
}