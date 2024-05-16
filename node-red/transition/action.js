module.exports = function(RED) {
    function ActionNode(config) {
        RED.nodes.createNode(this,config);
        var node = this;
        node.on('input', function(msg) {
            msg.payload = {"command": node.command, "parameters": node.parameters}
            node.send(msg);
        });
    }
    RED.nodes.registerType("action",ActionNode);
}
