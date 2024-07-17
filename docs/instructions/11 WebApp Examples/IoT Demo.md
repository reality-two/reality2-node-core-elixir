# IoT Demo

## Introduction

We wanted to create an example at the University for students in a lecture theatre, to help them understand IoT devices and for each to be able to interact with a shared experience, all at once, during the lecture that involved hardware and software.

## User story

1. As each student enters the lecture hall, they scan a QR code with the mobile phone to link to a WebApp.
2. Each device appears on the lecture room projector screen, attached to some part of a simulation or Digital Twin.
3. The sensors on the phone are used to change parameters of the simulation, with the students having to interact in specific ways to achieve a result (for example, rotate the phone yaw until it reaches 90 degrees, and tap the 'count' button 20 times).

   ```mermaid
   flowchart TD
       Device_0010 <---> Reality2_node
       Device_0002 <---> Reality2_node
       Device_0003 <---> Reality2_node
       Device_0004 <---> Reality2_node
       Device_0005 <---> Reality2_node
   
       Device_n <---> Reality2_node
       Reality2_node <---> Lecture_Room_Computer
       Lecture_Room_Computer --> Projector
   ```


## WebApp pages

To achieve the desired result, there are several parts to the WebApp

1. The WebApp **Landing page**: `/iotdemo`This has the QR code(s) for the students to scan to enter their devices.
2. The **Connection page** that the QR code leads to: `/iotdemo?connect` which has some interaction to approve the enrolement of the phone.
3. The **Sensor page** that reads the phone's sensors and passes that information to the Reality2 Node: `/iotdemo?id=[sentant ID]`
4. The **View page** that shows all the devices together `/iotdemo?view`

### Setting up

Follow the instructions for [adding a new WebApp](../10%20Adding%20a%20WebApp/New.md), and call this one 'iotdemo'.  Note that the full code for this is included in the GitHub.

### App.svelte

The main page for any WebApp set up using Svellte and Vite, is a page called 'App.svelte' in the main directory.  The view area is a

Given that it is essentially impossible to connect IoT devices to the university WiFi, we opted to have our own router in the lecture theatre, but that necessitates that each student has to join that WiFi network first.  Luckily, this can be also be achieved using a QR code.