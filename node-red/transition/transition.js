module.exports = function(RED) {
    function TransitionNode(config) {
        RED.nodes.createNode(this,config);
        var node = this;
        node.on('input', function(msg) {
            msg.payload = {"from": node.from, "event": node.event, "to": node.to, "actions": msg.payload}
            node.send(msg);
        });
    }
    RED.nodes.registerType("transition",TransitionNode);
}
