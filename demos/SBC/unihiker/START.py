# ****************************************************************************************************
# Roy C. Davies, 2023
# ****************************************************************************************************
from unihiker import GUI
import time
from pinpong.board import *
from pinpong.extension.unihiker import *
import subprocess
import threading
import ifaddr
import ssl
import websocket
import serial.tools.list_ports as port_list
import serial
import time
import re
import pygeohash
from pyubx2 import UBXReader    # https://pypi.org/project/pyubx2/
from requests import *

from reality2 import Reality2
from fsm import *

# ====================================================================================================
# Variables
# ====================================================================================================
reality2 = "/root/Reality2/Reality2/SBC/unihiker/start_reality2"
unihiker_config_file = "/opt/unihiker/pyboardUI/config.cfg"
unihiker_config = {}
led = ""
rgblight = ""
ipaddr = ""
something_changed = False
running = True
lighton = True
messageGUI = ""
stateGUI = ""
gpsGUI = ""
qrcode = ""
qrcode_text = ""
gps_serial_port = None
prev_geohash = ""

display_wifi_qr = True

# WIFI Hotspot
wifi_ssid = ""
wifi_password = ""

# Set the GUI
gui = GUI()
stateGUI = gui.draw_text(x=120, y=0, text="", origin="n", font_size=10)
gpsGUI = gui.draw_text(x=120, y=20, text="", origin="n", font_size=10)

ssl_context = ssl.SSLContext()
ssl_context.verify_mode = ssl.CERT_NONE


# ====================================================================================================


# ====================================================================================================
# Create the FSM
# ====================================================================================================
Reality2FSM = Automation() 
# ====================================================================================================


# ====================================================================================================
# Service functions
# ====================================================================================================


# ----------------------------------------------------------------------------------------------------
# Extract Latitude and Longitude from the GPS string
# ----------------------------------------------------------------------------------------------------
def extract_lat_lon(input_str):
    pattern = r'lat=(-?\d+\.\d+),\s*NS=([NS]),\s*lon=(-?\d+\.\d+),\s*EW=([EW])'
    match = re.search(pattern, input_str)

    if match:
        latitude = float(match.group(1))
        longitude = float(match.group(3))

        return (latitude, longitude)

    return (None, None)  # Return None if the input doesn't match the expected format
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Determine if the serial port has a GPS unit, and if so, what port it is on
# ----------------------------------------------------------------------------------------------------
def extract_serial_port(ports):
    print ("Serial Ports:")
    for p in ports:
        print(p)
        # Check if the port contains the keyword "GPS"
        if "GPS" in str(p):
            # Use regular expression to extract the serial port information
            serial_port_match = re.search(r'/dev/tty\w+', str(p))
            if serial_port_match:
                return serial_port_match.group()
    
    return None  # Return None if it's not a GPS unit or no serial port found
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Generate a QR Code string for the hotspot
# ----------------------------------------------------------------------------------------------------
def generate_wifi_qr_code(ssid, password, authentication_type='WPA'):
    wifi_string = f'WIFI:T:{authentication_type};S:{ssid};P:{password};;'
    return wifi_string
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Button clicks
# ----------------------------------------------------------------------------------------------------
def on_a_click():
    global Reality2FSM
    Reality2FSM.event("a_button")
def on_b_click():
    global Reality2FSM
    Reality2FSM.event("b_button")
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------
def print_state():
    global stateGUI, Reality2FSM, running
    
    while running:
        stateGUI.config(text="state = " + Reality2FSM._state)
        time.sleep(0.05)
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------
def get_hotspot_ip():
    ipaddr = ""
    adapters = ifaddr.get_adapters()
    print (adapters)
    
    # First see if there is a wifi connection
    for adapter in adapters:
        if "wlan0" in adapter.nice_name:
            for ip in adapter.ips:
                if ip.is_IPv4:
                    ipaddr = ip.ip
                    
    # Otherwise see if there is a hotspot
    if (ipaddr == ""):
        for adapter in adapters:
            if "p2p0" in adapter.nice_name:
                for ip in adapter.ips:
                    if ip.is_IPv4:
                        ipaddr = ip.ip
                        
    return ipaddr
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Switch between QR codes
# ----------------------------------------------------------------------------------------------------
def switch_qr():
    global display_wifi_qr, qrcode, qrcode_text, ipaddr, wifi_ssid, wifi_password
    
    display_wifi_qr = not display_wifi_qr
    
    if display_wifi_qr:
        qrcode.config(text=generate_wifi_qr_code(wifi_ssid, wifi_password))
        qrcode_text.config(text="ssid: " + wifi_ssid + " pass: " + wifi_password)
    else:
        qrcode.config(text="https://" + ipaddr + ":4005")
        qrcode_text.config(text="reality2 web")
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Set things up
# ----------------------------------------------------------------------------------------------------
def initialise():
    global messageGUI, stateGUI, gui, qrcode, qrcode_text, display_wifi_qr, led, rgblight, wifi_ssid, wifi_password, ipaddr
    
    with open(unihiker_config_file) as user_file:
        unihiker_config = json.loads(user_file.read())
        wifi_ssid = unihiker_config["apName"]
        wifi_password = unihiker_config["apPassword"]
    
    # Get the IP Addr of this Reality2 Node
    ipaddr = get_hotspot_ip()

    # Set up the callbacks for the buttons
    gui.on_a_click(on_a_click)
    gui.on_b_click(on_b_click)

    # Draw the original message and keep the GUI object
    messageGUI = gui.draw_text(x=120, y=50, text="Initialising", origin="n", font_size=10)
    
    # Create a scannable QR code to the Wifi
    if (ipaddr == ""):
        gui.draw_text(x=120, y=170, text="No Network", origin="n", font_size=10)
    else:
        qrcode = gui.draw_qr_code(x=120, y=170, w=180, text=generate_wifi_qr_code(wifi_ssid, wifi_password), origin="center")
        qrcode_text = gui.draw_text(x=120, y=250, text="ssid: " + wifi_ssid + " pass: " + wifi_password, origin="n", font_size=10)
    
    # Interaction Buttons
    gui.add_button(x=120, y=290, w=100, h=30, text="Toggle", origin="center", onclick=switch_qr)

    # Show the state of the FSM
    gui.start_thread(print_state)

    # Disable warnings due to not having proper certificates for SSH
    # requests.packages.urllib3.disable_warnings()

    # Start the sensors board
    Board().begin()
    led = Pin(Pin.P25, Pin.OUT)
    rgblight = Pin(Pin.P15, Pin.OUT)
# ----------------------------------------------------------------------------------------------------

# ====================================================================================================



# ====================================================================================================
# Actions
# ====================================================================================================

# ----------------------------------------------------------------------------------------------------
# Check if Reality2 Node is running
# ----------------------------------------------------------------------------------------------------
def check_reality2(_):
    processes = subprocess.run(["ps", "-e"], capture_output=True)
    return ("beam.smp" in str(processes.stdout))
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------
def check_server(is_running):
    global Reality2FSM
    
    if (is_running):
        Reality2FSM.event("serverok")
    else:
        Reality2FSM.event("checkserver", 1)
        
    return (True)
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Start Reality2 Node
# ----------------------------------------------------------------------------------------------------
def start_thread():
    subprocess.run([reality2, "daemon"])

def start_reality2(is_running):
    global Reality2FSM
    if (not is_running):
        the_server = threading.Thread(target=start_thread)
        the_server.start()
        
    Reality2FSM.event("checkserver", 1)

    return (True)
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Stop Reality2 Node
# ----------------------------------------------------------------------------------------------------
def stop_thread():
    subprocess.run(["killall", "beam.smp"])

def stop_reality2(is_running):
    global Reality2FSM
    if (is_running):
        the_server = threading.Thread(target=stop_thread)
        the_server.start()

    return (True)
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Log in
# ----------------------------------------------------------------------------------------------------
def connect_monitor(_):
    global Reality2FSM, server

    Reality2FSM.event("connected")
    return (True)
# ----------------------------------------------------------------------------------------------------


# ----------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------
def send_event(event):
    global server
    pass
    # Send an event to a geobote
    # POST(server, "geobots/send", {"geobotid": geobotid1}, {"event":event, "parameters":{}})
# ----------------------------------------------------------------------------------------------------



def set_geobot_position(geobotid, geohash):
    global server
    pass
    # PUT(server, "geobots", {"geobotid": geobotid}, {"location": {"geohash":geohash}})



# ----------------------------------------------------------------------------------------------------
# set the LED
# ----------------------------------------------------------------------------------------------------
def set_led(value):
    global led, rgblight
    led.write_digital(int(value))
    # rgblight.write_digital(int(value))
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Interpret a message from the websocket companion
# ----------------------------------------------------------------------------------------------------
def interpret_message(message):
    pass
# ----------------------------------------------------------------------------------------------------
                
                

# ----------------------------------------------------------------------------------------------------
# Connect to the companion, wotch the given Geobot, and respond appropriately to messages
# ----------------------------------------------------------------------------------------------------
def wait_for_message(ws):
    pass
#     global running
#     while running:
#         message = ws.recv()
#         if (message == "ping"):
#             ws.send("pong")
#             print ("WebSocket Live")
#         else:
#             interpret_message(message)
#         # print(f"Received: {message}")
#     ws.close()
        
# def connect():
#     global userid, ssl_context, server, geobotid2, running
    
#     ws = websocket.WebSocket(sslopt={"cert_reqs": ssl.CERT_NONE})
#     ws.connect("wss://localhost/wotcha/" + server["userid"])
#     command = {
#         "command": "wotcha",
#         "sessionid": server["sessionid"],
#         "parameters": {
#             "id": geobotid2
#         }
#     }
#     ws.send(json.dumps(command))
#     print("Connected")
#     Reality2FSM.event("connected")

#     the_companion = threading.Thread(target=wait_for_message, args=(ws,))
#     the_companion.start()
        
def connect_to_companion(_):
    Reality2FSM.event("connected")

    # start_websocket = threading.Thread(target=connect)
    # start_websocket.start()
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# Change the message on the screen
# ----------------------------------------------------------------------------------------------------
def printout(something):
    global messageGUI, Reality2FSM

    messageGUI.config(text=something)
    Reality2FSM.event("clear", 1)
    
    print (something)
    return True
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------
def clear(_):
    global messageGUI
    messageGUI.config(text="")
    return True
# ----------------------------------------------------------------------------------------------------



# ----------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------
def quit(_):
    global running

    running = False
# ----------------------------------------------------------------------------------------------------

# ====================================================================================================


# ====================================================================================================
# Main Code
# ====================================================================================================

# ----------------------------------------------------------------------------------------------------
# Set the transitions
# ----------------------------------------------------------------------------------------------------
#                           state               event               newstate            actions
Reality2FSM.add(Transition("start",            "init",             "starting",          ["Starting Reality2 Node", printout, check_reality2, start_reality2]))

Reality2FSM.add(Transition("starting",         "checkserver",      "starting",          [check_reality2, check_server]))
Reality2FSM.add(Transition("starting",         "serverok",         "connecting",        ["Connecting", printout, connect_monitor]))

Reality2FSM.add(Transition("connecting",       "connect",          "connecting",        [connect_monitor]))
Reality2FSM.add(Transition("connecting",       "connected",        "ready",             ["Reality2 Node ready", printout, connect_to_companion]))
Reality2FSM.add(Transition("connecting",       "error",            "error",             ["Error", printout]))

Reality2FSM.add(Transition("wotching",         "connected",        "companion",         ["Connected to Companion", printout]))
Reality2FSM.add(Transition("wotching",         "error",            "error",             ["Error", printout]))

Reality2FSM.add(Transition("companion",        "error",            "error",             ["Error", printout]))


Reality2FSM.add(Transition("companion",        "a_button",         "companion",         ["Sending Message", printout, "touch", send_event]))
Reality2FSM.add(Transition("companion",        "on",               "companion",         ["ON", printout, "1", set_led]))
Reality2FSM.add(Transition("companion",        "off",              "companion",         ["OFF", printout, "0", set_led]))

Reality2FSM.add(Transition("*",                "clear",            "*",                 [clear]))
Reality2FSM.add(Transition("*",                "b_button",         "quitting",          ["Quitting...", printout, check_reality2, stop_reality2, quit]))
# ----------------------------------------------------------------------------------------------------

# Open the serial port for the GPS unit
gps_serial_port = extract_serial_port(list(port_list.comports()))

if (gps_serial_port != None):  
    s = serial.Serial(gps_serial_port, 9600)
    ubr = UBXReader(s)

# Initialise various things
initialise()

# Set the whole thing going
print ("Starting Reality2 Node")
Reality2FSM.go()

print ("Waiting for events")
# Wait until the end
while running:
    if (gps_serial_port != None):
        (raw_data, parsed_data) = ubr.read()
        
        (lat, lon) = extract_lat_lon(str(parsed_data))
        if (lat != None):
            geohash = pygeohash.encode(lat, lon)
            if (geohash != prev_geohash):
                gpsGUI.config(text=geohash)
                set_geobot_position(trackedgeobot, geohash)
                print(lat, lon, geohash)
                prev_geohash = geohash
    else:
        gpsGUI.config(text="no gps")
            
    time.sleep(0.1)

# Close down the FSM
print ("Stopping Reality2 Node")
Reality2FSM.stop()

# ====================================================================================================