# Single Board Computers

There are many single board computers such as Raspberry Pi, Arduino and Unihiker.  Many of these have the ability to read sensors (such as sound level and humidity) and control actuators (such as lights and motors).

To communicate with these devices, regardless of the device, the logic is the same.

1. On the device, create code that can read from a websocket and send an event to a Sentant.
2. Use `awaitSignal` to subscribe to a signal on a Sentant (if required).
3. When the signal is triggered, do some appropriate action, and
4. If required, periodically send some data to the Sentant using `sentantSend`.

   ```mermaid
   flowchart LR
       Sensor --> Raspberry_PI
       Raspberry_PI --> Actuator
       subgraph Reality2_Node
       Raspberry_PI -- sentantSend --> Sentant
       Sentant -- awaitSignal --> Raspberry_PI
       end
   ```


Below are some examples.

### Table of Contents

[Main Menu](../README.md)

1. [Raspberry Pi example.](Raspberry%20PI.md)

