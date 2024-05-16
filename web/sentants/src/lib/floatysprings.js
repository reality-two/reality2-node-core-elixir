
// Base address of the API
var APIBaseAddress = "/APIHandler.ashx";
//var APIBaseAddress = "https://api.imersia.net/api/2.0/";
var developerID = "3D Portal";

var showConsole = true;

// Pubnub details
var pubnub_pubkey = 'pub-c-d3db3f4d-e184-4b67-9b28-2a0d2a0d8b02';
var pubnub_subkey = 'sub-c-245e877e-7870-11e2-89a1-12313f022c90';

// Details for the Radial Menus
var radialMenuTypes = [  "Companion", ["Logout", "First", "Second", "Third", "Fourth", "Fifth", "NewOverlay", "Seventh"],
                     "Overlay", ["Details", "Metadata", "Files", "QRCode", "Map", "Wotcha", "NewAgent", "Delete"],
                     "Agent", ["Details", "Metadata", "Files", "QRCode", "Map", "Analytics", "Delete", "NextMenu"],
                     "Agent2", ["Wotcha", "Programming", "MailingList", "Third", "Fourth", "Fifth", "Sixth", "GoBack"],
                     "Metadata", ["Edit", "Remove", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh"],
                     "MetadataSub", ["Add", "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh"],
                     "Details", ["Edit", "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh"],
                     "Files", ["Remove", "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh"],
                     "FilesSub", ["Add", "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh"],
                     "YesNo", ["Yes", "No", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh"]];

var radialMenuFunctions = {
 "Companion": [function () { Logout(); }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { NewOverlay(); }, function () { }],
 "Overlay": [function () { LoadDetails(); }, function () { LoadMetaData(); }, function () { LoadFiles(); }, function () { LoadQRCode(); }, function () { MapView(); }, function () { LoadWotcha(); }, function () { NewAgent(); }, function () { DeleteOverlay(); }],
 "Agent": [function () { LoadDetails(); }, function () { LoadMetaData(); }, function () { LoadFiles(); }, function () { LoadQRCode(); }, function () { MapView(); }, function () { LoadAnalytics(); }, function () { DeleteAgent(); }, function () { NextAgentMenu(); }],
 "Agent2": [function () { LoadWotcha(); }, function () { LoadProgramming(); }, function () { LoadMailingList(); }, function () { }, function () { }, function () { }, function () { }, function () { PrevAgentMenu(); }],
 "Metadata": [function () { EditMetadata(); }, function () { DeleteMetadata(); }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }],
 "MetadataSub": [function () { AddMetadata(); }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }],
 "Details": [function () { EditDetail(); }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }],
 "Files": [function () { }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }],
 "FilesSub": [function () { }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }],
 "YesNo": [function () { YesSelected(); }, function () { NoSelected(); }, function () { }, function () { }, function () { }, function () { }, function () { }, function () { }]
};

var radialMenuActive = {
 "Companion": [true, false, false, false, false, false, true, false],
 "Overlay": [true, true, true, true, true, true, true, true],
 "Agent": [true, true, true, true, true, true, true, true],
 "Agent2": [true, true, true, false, false, false, false, true],
 "Metadata": [true, true, false, false, false, false, false, false],
 "MetadataSub": [true, false, false, false, false, false, false, false],
 "Details": [true, false, false, false, false, false, false, false],
 "Files": [false, false, false, false, false, false, false, false],
 "YesNo": [true, true, false, false, false, false, false, false]
};

var radialMenuTooltips = {
 "Companion": ["Log out", "", "", "", "", "", "New Overlay", ""],
 "Overlay": ["Details", "Variables", "Files", "QR Code", "Toggle Mapview", "Wotcha", "New Agent", "Delete Overlay"],
 "Agent": ["Details", "Variables", "Files", "QR Code", "Toggle Mapview", "Analytics", "Delete", ""],
 "Agent2": ["Wotcha", "Program", "Mailing List", "", "", "", "", ""],
 "Metadata": ["Edit Variable", "Delete Variable", "", "", "", "", "", ""],
 "MetadataSub": ["New Variable", "", "", "", "", "", "", ""],
 "Details": ["Edit", "", "", "", "", "", "", ""],
 "Files": ["Add", "Delete", "", "", "", "", "", ""],
 "YesNo": ["OK", "Cancel", "", "", "", "", "", ""]
}


var currentGeoHash = "";
var currentLatitude, currentLongitude, currentAltitude, currentAccuracy, currentHeading;

var currentCenterObject;
var currentCommand = "";

var currentOverlayID = "";
var currentOverlays;
var currentOverlay; 
var currentOverlayMetadata;
var currentOverlayFiles;
var currentOverlayJSON;
var currentOverlayMetadataJSON;
var currentOverlayFileJSON;
var currentOverlayFilename;
var currentOverlayFileURL;

var currentAgentID = "";
var currentAgents;
var currentAgent;
var currentAgentMetadata;
var currentAgentFiles;
var currentAgentJSON;
var currentAgentMetadataJSON;
var currentAgentFileJSON;
var currentAgentFilename;
var currentAgentFileURL;
var currentAgent3DJSON;
var currentAgentAudioJSON;

// Parameters coming in from code behind
var tokenID = "";
var userName = "";

// Counter for number of server reads currently ongoing
var readCounter = 0;

// standard global variables
var container, scene, cssscene, camera, renderer, cssrenderer, controls, stats;
var div, element;
var keyboard = new THREEx.KeyboardState();
var clock = new THREE.Clock();

// custom global variables
var targetList = [];
var connectors = [];
var projector, mouse = new THREE.Vector3();
var menuSprites = {};
var radialMenus = {};
var currentMenu = '';
var radialMenuSensor;

// custom global variables
// The central object
var center;

// Map Stuff
var mapimage, mapplane, mapdiv, mapbounds, map, maptiles, mapcanvas;

var displayMode = "satellite"; // map, satellite

var simplePhysicsTimestep = 50;


// ******************************************************************************************
// An object for each Overlay or Agent
// ******************************************************************************************
var ImersiaObject = function (newTitle, newPosition, newTransform)
{
 this.title = newTitle;
 this.latitude = 0;
 this.longitude = 0;

 this.force = new THREE.Vector3(0, 0, 0);
 this.velocity = new THREE.Vector3(0, 0, 0);
 this.mass = 1.0;

 this.friction = 0.1;

 this.position = newPosition;
 this.newPosition = newPosition;
 this.transform = newTransform;

 this.angularForce = new THREE.Vector3(0, 0, 0);
 this.angularVelocity = new THREE.Vector3(0, 0, 0);
 this.angularFriction = 10.0;

 this.closestDistance = 1200;
 this.springStiffness = 1;
 this.damping = 0.1;
 this.distanceToSun = 300;


 // ******************************************************************************************
 // Set the position of this point
 // ******************************************************************************************
 this.SetPosition = function (newPosition) {
     this.newPosition = newPosition;
 };
 // ******************************************************************************************



 // ******************************************************************************************
 // Randomize the rotations a little to get a floaty effect
 // ******************************************************************************************
 this.RandomizeRotation = function (divider)
 {
     stepValue = 1 / divider;
     maxValue = stepValue * 10.0;

     xDirection = Math.random() > 0.5;
     yDirection = Math.random() > 0.5;
     zDirection = Math.random() > 0.5;

     if (xDirection) this.angularVelocity.x += stepValue; else this.angularVelocity.x -= stepValue;
     this.angularVelocity.x = Math.max(-maxValue, Math.min(maxValue, this.angularVelocity.x));
     if (yDirection) this.angularVelocity.y += stepValue; else this.angularVelocity.y -= stepValue;
     this.angularVelocity.y = Math.max(-maxValue, Math.min(maxValue, this.angularVelocity.y));
     if (zDirection) this.angularVelocity.z += stepValue; else this.angularVelocity.z -= stepValue;
     this.angularVelocity.z = Math.max(-maxValue, Math.min(maxValue, this.angularVelocity.z));

     this.transform.rotation.set (this.transform.rotation.x + this.angularVelocity.x, this.transform.rotation.y + this.angularVelocity.y, this.transform.rotation.z + this.angularVelocity.z);
 }
 // ******************************************************************************************



 // ******************************************************************************************
 // Do simple physics calculations at a regular time step
 // ******************************************************************************************
 this.Step = function (timeStep) {
     var frictionalForce = new THREE.Vector3(this.velocity.x * -this.friction, this.velocity.y * -this.friction, this.velocity.z * -this.friction);
     this.velocity = new THREE.Vector3(((this.force.x + frictionalForce.x) / this.mass) / timeStep, ((this.force.y + frictionalForce.y) / this.mass) / timeStep, ((this.force.z + frictionalForce.z) / this.mass) / timeStep);

     this.position = this.transform.position.add(this.velocity);

     this.transform.position.set(this.position.x, this.position.y, this.position.z);
 }
 // ******************************************************************************************



 // ******************************************************************************************
 // Make the children objects linked to the parent object and to each other by 'springs'
 // ******************************************************************************************
 this.FloatySprings = function () {

     this.force.set(0, 0, 0);
     var forceValue = 0;
     var thisobjectType = this.transform.name;

     if ((this.transform.parent != null) && ((this.transform.name === 'Overlay') || (this.transform.name === "Agent") || (this.transform.name === "Metadata") || (this.transform.name === "Details") || (this.transform.name === "Files"))) {

         thisParent = this.transform.parent;
         siblings = thisParent.children;

         // Calculate the force against all the siblings of this object
         for (i = 0; i < siblings.length; i++) {
             thisChild = siblings[i];
             if (((thisChild.name === 'Overlay') || (thisChild.name === 'Agent') || (thisChild.name === "Metadata") || (thisChild.name === "Details") || (thisChild.name === "Files")) && (thisobjectType === thisChild.name)) {
                 direction = new THREE.Vector3(this.transform.position.x - thisChild.position.x, this.transform.position.y - thisChild.position.y, this.transform.position.z - thisChild.position.z);
                 forceValue = direction.length() - this.closestDistance;
                 normalizedDirection = new THREE.Vector3(direction.x, direction.y, direction.z);
                 normalizedDirection.normalize();
                 thisForce = new THREE.Vector3((forceValue * -this.springStiffness * normalizedDirection.x) - (this.velocity.x * this.damping), (forceValue * -this.springStiffness * normalizedDirection.y) - (this.velocity.y * this.damping), (forceValue * -this.springStiffness * normalizedDirection.z) - (this.velocity.z * this.damping));
                 this.force.set(this.force.x + thisForce.x, this.force.y + thisForce.y, this.force.z + thisForce.z);
             }
         }

         // Calculate the force against the parent of this object
         forceValue = this.transform.position.length() - this.distanceToSun;
         normalizedDirection = new THREE.Vector3(this.transform.position.x, this.transform.position.y, this.transform.position.z);
         normalizedDirection.normalize();
         thisForce = new THREE.Vector3((forceValue * -this.springStiffness * normalizedDirection.x) - (this.velocity.x * this.damping), (forceValue * -this.springStiffness * normalizedDirection.y) - (this.velocity.y * this.damping), (forceValue * -this.springStiffness * normalizedDirection.z) - (this.velocity.z * this.damping));
         this.force.set(this.force.x + thisForce.x, this.force.y + thisForce.y, this.force.z + thisForce.z);
     }
 }
 // ******************************************************************************************



 // ******************************************************************************************
 // When in map mode, place the Agents on the map surface
 // ******************************************************************************************
 this.PlaceOnMap = function () {
     if (map) {
         var theBounds = map.getBounds();
         y2 = theBounds.getNorth();
         x2 = theBounds.getWest();
         y1 = theBounds.getSouth();
         x1 = theBounds.getEast();

         southEast = map.latLngToLayerPoint([y1, x1]);
         northWest = map.latLngToLayerPoint([y2, x2]);

         thisPoint = map.latLngToLayerPoint([this.latitude, this.longitude]);

         xdiff = southEast.x - northWest.x;
         ydiff = southEast.y - northWest.y;

         if (xdiff != 0) {
             xposa = (thisPoint.x - northWest.x) / xdiff;
             xpos = xposa * 40000 - 20000;
         }
         else
             xpos = 0;
         if (ydiff != 0) {
             yposa = (thisPoint.y - northWest.y) / ydiff;
             ypos = yposa * 32000 - 16000;
         }
         else
             ypos = 0;

         var mapPosition = new THREE.Vector3(xpos, -10000, ypos);

         this.transform.parent.worldToLocal(mapPosition);
         this.transform.position.set(mapPosition.x, mapPosition.y, mapPosition.z);
     }
 }
 // ******************************************************************************************

}
// ******************************************************************************************



// ******************************************************************************************
// A list of Imersia Objects
// ******************************************************************************************
var ImersiaObjects = [];
// ******************************************************************************************



// ******************************************************************************************
// The main function
// ******************************************************************************************
//$(document).ready(function () { onDeviceReady(); });
window.onload = function () { onDeviceReady(); }
function onDeviceReady() {

 //LogInToImersia("roy.c.davies@ieee.org", "#6DDf9f9ce4");

 // Start GPS Reading
 navigator.geolocation.watchPosition(GetLocation, GetLocationError, { 'enableHighAccuracy': true, 'timeout': 100000, 'maximumAge': 0 });

 // Get the login details from the codebehind
 tokenID = $("#Login_TokenID").val();
 userName = $("#Login_CurrentUser").val();

 if (!showConsole)
 {
     $("#Console").attr("width:0px; left:100%");
 }

 init();
 build();
 animate();
}
// ******************************************************************************************



// ******************************************************************************************
// Create the renderers, one for the main 3D view, and one for maps and other css objects
// ******************************************************************************************
function createGlRenderer() {
 if (Detector.webgl)
     glRenderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
 else
     glRenderer = new THREE.CanvasRenderer();
 glRenderer.setClearColor(0x112233);
 glRenderer.setPixelRatio(window.devicePixelRatio);
 glRenderer.setSize(window.innerWidth, window.innerHeight);
 glRenderer.domElement.style.position = 'absolute';
 glRenderer.domElement.style.zIndex = 1;
 glRenderer.domElement.style.top = 0;
 return glRenderer;
}

function createCssRenderer() {
 var cssRenderer = new THREE.CSS3DRenderer();
 cssRenderer.setSize(window.innerWidth, window.innerHeight);
 cssRenderer.domElement.style.position = 'absolute';
 renderer.domElement.style.zIndex = 0;
 cssRenderer.domElement.style.top = 0;
 return cssRenderer;
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function LoadImageOnMap(url)
{
 var material = new THREE.MeshBasicMaterial({
     color: 0xFFFFFF,
     transparent: true,
     side: THREE.FrontSide,
     map: THREE.ImageUtils.loadTexture(url, null, function () {
         material.opacity = 1;
         mapplane.material = material;
     }),
     opacity: 0
 });
}
// ******************************************************************************************



// ******************************************************************************************
// Create a map at a specific size and orientation
// ******************************************************************************************
function createMap(w, h, position, rotation)
{
 // If this is a reload, remove the existing elements
 if (map) {
     $("#map").remove();
     map.remove();
 }

 LoadImageOnMap("images/loading.png");

 /*var material = new THREE.MeshBasicMaterial({
     color: 0xFFFFFF,
     transparent: true,
     side: THREE.FrontSide,
     map: THREE.ImageUtils.loadTexture("images/loading.png", null, function () {
         material.opacity = 1;
         mapplane.material = material;
     }),
     opacity: 0
 });*/

 // Create a new DIV element to contain the map
 mapcanvas = document.createElement("div");
 mapcanvas.id = "map";

 mapcanvas.setAttribute("style", 'width:' + w + 'px; height:' + h + 'px; overflow: hidden;');
 document.body.appendChild(mapcanvas);

 // Set up the map
 if (currentCenterObject.name === "Overlay") {
     map = L.map(mapcanvas, { zoomControl: false, attributionControl: false }).fitBounds(mapbounds);
 }
 else {
     map = L.map(mapcanvas, { zoomControl: false, attributionControl: false, center: [currentCenterObject.latitude, currentCenterObject.longitude], zoom: 18 });
 }

 maptiles = L.tileLayer('https://api.tiles.mapbox.com/v4/{id}/{z}/{x}/{y}.png?access_token={accessToken}', {
     accessToken: 'pk.eyJ1Ijoicm95Y2RhdmllcyIsImEiOiJua2ZoY3JnIn0.2ybExrs-yDA5hLbt838zdg',
     id: 'mapbox.streets'
 }).addTo(map);

 // When the map is ready, add the markers
 map.whenReady(function () {
     if (currentCenterObject.name === "Overlay") {
         var myIcon = L.icon({
             iconUrl: 'images/marker.png',
             iconSize: [10, 10],
             iconAnchor: [5, 5]
         });

         $.each(currentCenterObject.children, function (i, item) {
             if (item.latitude != null) {
                 thisMarker = L.marker([item.latitude, item.longitude], { icon: myIcon }).addTo(map);
             }
         });
     }

     // And then grab the image for the plane
     leafletImage(map, function (err, canvas) {
         LoadImageOnMap(canvas.toDataURL());
     });
 });
}


// ******************************************************************************************



// ******************************************************************************************
// Initialise the Scene etc
// ******************************************************************************************
function init() {
 // SCENE
 scene = new THREE.Scene();
 //cssscene = new THREE.Scene();
 // CAMERA
 var SCREEN_WIDTH = window.innerWidth, SCREEN_HEIGHT = window.innerHeight;
 var VIEW_ANGLE = 60, ASPECT = SCREEN_WIDTH / SCREEN_HEIGHT, NEAR = 10, FAR = 100000;
 camera = new THREE.PerspectiveCamera(VIEW_ANGLE, ASPECT, NEAR, FAR);
 scene.add(camera);

 camera.position.set(0, 4000, 4000);
 camera.lookAt(scene.position);

 // RENDERER
 renderer = createGlRenderer();

 document.body.insertBefore(renderer.domElement, document.body.firstChild);


 // EVENTS
 THREEx.WindowResize(renderer, camera);
 THREEx.FullScreen.bindKey({ charCode: '~'.charCodeAt(0) });
 // CONTROLS
 controls = new THREE.OrbitControls(camera, renderer.domElement); //new THREE.TrackballControls(camera);

 /*controls.rotateSpeed = 1.0;
 controls.zoomSpeed = 1.2;
 controls.panSpeed = 0.8;

 controls.noZoom = false;
 controls.noPan = false;

 controls.staticMoving = true;
 controls.dynamicDampingFactor = 0.3;

 controls.keys = [65, 83, 68];

 controls.addEventListener('change', render);*/
 // STATS
 /*stats = new Stats();
 stats.domElement.style.position = 'absolute';
 stats.domElement.style.bottom = '0px';
 stats.domElement.style.zIndex = 100;
 container.appendChild(stats.domElement);*/
 // LIGHT
 var light = new THREE.PointLight(0xffffff);
 light.position.set(25000, 25000, 0);
 scene.add(light);

 var ambientlight = new THREE.AmbientLight(0x909090); // soft white light
 scene.add(ambientlight);

 // FLOOR
 /*var floorTexture = new THREE.ImageUtils.loadTexture('images/greencheckers.jpg');
 floorTexture.wrapS = floorTexture.wrapT = THREE.RepeatWrapping;
 floorTexture.repeat.set(50, 50);
 var floorMaterial = new THREE.MeshBasicMaterial({ map: floorTexture, side: THREE.DoubleSide });
 var floorGeometry = new THREE.PlaneGeometry(10000, 10000, 10, 10);
 var floor = new THREE.Mesh(floorGeometry, floorMaterial);
 floor.position.y = -500;
 floor.rotation.x = Math.PI / 2;
 scene.add(floor);*/

 ////////////
 // CUSTOM //
 ////////////

 // axes
 //var axes = new THREE.AxisHelper(100);
 //scene.add(axes);

 // Skybox
 /*var imagePrefix = "images/skyboxes/12/";
 var directions = ["left", "right", "top", "bottom", "front", "back"];
 var imageSuffix = ".jpg";
 var skyGeometry = new THREE.CubeGeometry(40000, 40000, 40000);

 var materialArray = [];
 for (var i = 0; i < 6; i++)
     materialArray.push(new THREE.MeshBasicMaterial({
         map: THREE.ImageUtils.loadTexture(imagePrefix + directions[i] + imageSuffix),
         side: THREE.BackSide
     }));
 var skyMaterial = new THREE.MeshFaceMaterial(materialArray);
 var skyBox = new THREE.Mesh(skyGeometry, skyMaterial);
 skyBox.position.y = -5000;

 scene.add(skyBox);*/

 // Create the map plane
 var position = new THREE.Vector3(0, -10000, 0);
 var rotation = new THREE.Vector3(-Math.PI / 2, 0, 0);
 var maptexture = new THREE.ImageUtils.loadTexture("images/imersialogo.png");
 var geometry = new THREE.PlaneGeometry(1000, 800);
 var material = new THREE.MeshBasicMaterial({
     color: 0xFFFFFF,
     side: THREE.DoubleSide,
     map: maptexture
 });
 mapplane = new THREE.Mesh(geometry, material);

 mapplane.position.x = position.x;
 mapplane.position.y = position.y;
 mapplane.position.z = position.z;
 mapplane.rotation.x = rotation.x;
 mapplane.rotation.y = rotation.y;
 mapplane.rotation.z = rotation.z;
 mapplane.scale.set(40, 40, 40);

 mapplane.name = 'Webpage';
 mapplane.userData = 'Map';
 scene.add(mapplane);

 // Read the Radial Menu Images
 for (var j = 0; j < radialMenuTypes.length; j=j+2) {
     var radialMenuPrefix = "images/RadialMenus/" + radialMenuTypes[j] + "/";
     var radialMenuCenter = radialMenuTypes[j + 1];
     var radialMenuSuffix = ".png";
     var menuSpriteGroup = new THREE.Object3D();
     var currentRadialSprites = [];

     for (var i = 0; i < radialMenuCenter.length; i++) {
         var menuMap = THREE.ImageUtils.loadTexture(radialMenuPrefix + radialMenuCenter[i] + radialMenuSuffix);
         var roundMenuMaterial = new THREE.SpriteMaterial({ map: menuMap, depthTest: false });

         var menuSprite = new THREE.Sprite(roundMenuMaterial);
         menuSprite.name = radialMenuCenter[i];
         menuSprite.scale.set(400, 400, 1.0);
         menuSprite.position.set(0, 0, 0);

         currentRadialSprites.push(menuSprite);
         menuSpriteGroup.add(menuSprite);
     }
     menuSprites[radialMenuTypes[j]] = currentRadialSprites;
     radialMenus[radialMenuTypes[j]] = menuSpriteGroup;
     scene.add(menuSpriteGroup);
     menuSpriteGroup.visible = false;

     var geometry = new THREE.SphereGeometry(150, 12, 12);
     var material = new THREE.MeshPhongMaterial({ color: 0x2222ff });
     radialMenuSensor = new THREE.Mesh(geometry, material);
     radialMenuSensor.visible = false;
     scene.add(radialMenuSensor);
 }

 // Hide the editor and message boxes until later.
 $("#editor").hide();
 $("#message").hide();
 $("#fileupload").hide();

 // initialize object to perform world/screen calculations
 projector = new THREE.Projector();

 //HTML
 $("#title").text('');

 // when the mouse moves, call the given function
 document.addEventListener('mousemove', onDocumentMouseMove, false);
 document.addEventListener('mousedown', onDocumentMouseDown, false);
 //document.addEventListener('mouseup', onDocumentMouseUp, false);
}
// ******************************************************************************************



// ******************************************************************************************
// Build the scene, starting with the central 'companion' and adding the overlays and agents
// ******************************************************************************************
function build()
{
 var geometry = new THREE.SphereGeometry(100, 12, 12);
 var material = new THREE.MeshPhongMaterial({ color: 0x2222ff });
 center = new THREE.Mesh(geometry, material);
 center.userData = "Companion";
 center.name = "Companion";
 targetList.push(center);

 currentCenterObject = center;

 scene.add(center);

 zeroVector = new THREE.Vector3(0, 0, 0);
 var imersiaObject = new ImersiaObject("Center", zeroVector, center);
 imersiaObject.closestDistance = 0;
 imersiaObject.distanceToSun = 0;
 ImersiaObjects.push(imersiaObject);

 // Load the Overlays and Agents
 LoadOverlays();

 // Things to be done on a regular timestep
 window.setInterval(function () {
     $.each(ImersiaObjects, function (i, item) {
         if (item.transform.name === "Agent")  {
             if ((displayMode === "map") && ((item.transform.parent == currentCenterObject) || (item.transform.parent == currentCenterObject.parent)))
             {
                 item.PlaceOnMap();
             }
             else
             {
                 item.FloatySprings();
                 item.Step(simplePhysicsTimestep);
                 item.RandomizeRotation(10000);
             }
         }
         else {
             item.FloatySprings();
             item.Step(simplePhysicsTimestep);
             item.RandomizeRotation(10000);
         }
     });
     AdjustConnectors();
 }, simplePhysicsTimestep);
}
// ******************************************************************************************



// ******************************************************************************************
// Keep the 3D going
// ******************************************************************************************
function animate() {
 render();
 update();
 UpdateOrbitCenter();
 requestAnimationFrame(animate);
}

function update() {
 if (keyboard.pressed("z")) {
     // do something
 }

 controls.update();
 //stats.update();
}

function render() {
 renderer.render(scene, camera);
}
// ******************************************************************************************



// ******************************************************************************************
// Work out the angle the mouse position is relative to the currently selected obejct
// This is for the radial menus to know which segment to highlight and select
// ******************************************************************************************
function CalculateAngleFromMouse(theObject) {
 var vector = theObject.position.clone();
 theObject.parent.localToWorld(vector);

 // map to normalized device coordinate (NDC) space
 vector.project(camera);

 // map to 2D screen space
 vector.x = Math.round((vector.x + 1) * window.innerWidth / 2),
 vector.y = Math.round((-vector.y + 1) * window.innerHeight / 2);
 vector.z = 0;

 var xDiff = vector.x - event.clientX;
 var yDiff = vector.y - event.clientY;
 var angle = ((Math.floor(((Math.atan2(yDiff, xDiff) * (180 / Math.PI)) + 180) / 45) + 2) % 8);

 return angle;
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function onDocumentMouseMove(event) {
 var menuSelected = false;

 // update the mouse variable
 mouse.x = (event.clientX / (window.innerWidth)) * 2 - 1;
 mouse.y = -(event.clientY / window.innerHeight) * 2 + 1;

 // create a Ray with origin at the mouse position
 //   and direction into the scene (camera direction)
 var raycaster = new THREE.Raycaster();
 raycaster.setFromCamera(mouse, camera);

 var intersects = raycaster.intersectObjects(targetList);
 var intersectsMenu = raycaster.intersectObjects(menuSprites[currentMenu]);

 // Find out which part of the round menus is currently being hovered over
 if (currentMenu != '') {
     if (intersectsMenu.length > 0) {
         angle = CalculateAngleFromMouse(intersectsMenu[0].object);

         inMiddle = false;
         if (intersects.length > 0)
         {
             if (intersects[0].object == currentCenterObject)
                 inMiddle = true;
         }

         if ((angle < intersectsMenu.length) && (radialMenuActive[currentMenu][angle]) && !inMiddle){
             for (var i = 0; i < menuSprites[currentMenu].length; i++)
                 menuSprites[currentMenu][i].material.color.setHex(0xffffff);
             $("#title").text(radialMenuTooltips[currentMenu][angle]);
             $("#title").css({ left: event.clientX - 250, top: event.clientY - 20 })
             menuSprites[currentMenu][angle].material.color.setHex(0x8888ff);
             menuSelected = true;
         }
         else {
             $("#title").text("");
             for (var i = 0; i < menuSprites[currentMenu].length; i++)
                 menuSprites[currentMenu][i].material.color.setHex(0xffffff);
         }
     }
     else {
         $("#title").text("");
         for (var i = 0; i < menuSprites[currentMenu].length; i++)
             menuSprites[currentMenu][i].material.color.setHex(0xffffff);
     }
 }
 else {
     $("#title").text("");
 }


 // Adjust the text being shown on top of the object under the mouse
 if ((intersects.length > 0) && !menuSelected) {
     // update text, if it has a "name" field.
     if (intersects[0].object.userData) {
         var message = intersects[0].object.userData;
         $("#title").text(message);
         $("#title").css({ left: event.clientX - 250, top: event.clientY - 20 })
     }
 }
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function onDocumentMouseDown(event) {
 var menuSelected = false;

 // update the mouse variable
 mouse.x = (event.clientX / (window.innerWidth)) * 2 - 1;
 mouse.y = -(event.clientY / window.innerHeight) * 2 + 1;

 // create a Ray with origin at the mouse position
 //   and direction into the scene (camera direction)
 var raycaster = new THREE.Raycaster();
 raycaster.setFromCamera(mouse, camera);

 // create an array containing all objects in the scene with which the ray intersects
 var intersects = raycaster.intersectObjects(targetList);
 var intersectsMenu = raycaster.intersectObjects(menuSprites[currentMenu]);

 // Find out which part of the round menus is currently being pressed on
 if (currentMenu != '') {
     if (intersectsMenu.length > 0) {
         angle = CalculateAngleFromMouse(intersectsMenu[0].object);

         inMiddle = false;
         if (intersects.length > 0) {
             if (intersects[0].object == currentCenterObject)
                 inMiddle = true;
         }

         if ((angle < intersectsMenu.length) && (radialMenuActive[currentMenu][angle]) && !inMiddle) {
             radialMenuPressed = true;
             var functionToCall = radialMenuFunctions[currentMenu][angle];
             functionToCall();
             menuSelected = true;
         }
     }
 }

 if (!menuSelected) {
     // if there is one (or more) intersections
     if (intersects.length > 0) {
         var vector = new THREE.Vector3();
         vector.set(intersects[0].object.position.x, intersects[0].object.position.y, intersects[0].object.position.z);
         intersects[0].object.parent.localToWorld(vector);

         // map to normalized device coordinate (NDC) space
         vector.project(camera);

         // map to 2D screen space
         vector.x = Math.round((vector.x + 1) * window.innerWidth / 2),
         vector.y = Math.round((-vector.y + 1) * window.innerHeight / 2);
         vector.z = 0;

         var xDiff = vector.x - event.clientX;
         var yDiff = vector.y - event.clientY;

         // Clear any other objects coming off this one that are not agents or overlays (ie metadata etc)
         if ((intersects[0].object.name == "Agent") || (intersects[0].object.name == "Overlay") || (intersects[0].object.name == "Companion"))
             ClearObjectData();

         // Change the object pressed on and update the map etc
         if ((intersects[0].object.name == "Agent") || (intersects[0].object.name == "Overlay") || (intersects[0].object.name == "Companion")
             || (intersects[0].object.name == "Metadata") || (intersects[0].object.name == "Details") || (intersects[0].object.name == "File")) {

             $("#editor").hide();

             currentCenterObject = intersects[0].object;

             // update menu
             if (intersects[0].object.userData) {
                 ChangeRadialMenu(intersects[0].object.name, intersects[0].object.name, intersects[0].object);
             }
             else {
                 currentMenu = '';
             }

             if ((currentCenterObject.name == "Agent") && (displayMode === "map")) {
                 mapbounds = new L.latLngBounds(L.latLng(currentCenterObject.latitude, currentCenterObject.longitude), L.latLng(currentCenterObject.latitude, currentCenterObject.longitude));

                 createMap(
                     1000, 800,
                     new THREE.Vector3(0, -10000, 0),
                     new THREE.Vector3(-Math.PI / 2, 0, 0));
             }
         }
     }
 }
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function UpdateOrbitCenter() {
 if (currentCenterObject.parent != null) {
     var currentCenter = new THREE.Vector3(currentCenterObject.position.x, currentCenterObject.position.y, currentCenterObject.position.z);

     currentCenter.applyMatrix4(currentCenterObject.parent.matrixWorld);
     controls.target.set(currentCenter.x, currentCenter.y, currentCenter.z);
     camera.lookAt(currentCenter);
 }
}
// ******************************************************************************************



// ******************************************************************************************
// Adjust the connectors to keep them in line with the points
// ******************************************************************************************
function AdjustConnectors() {
 for (i = 0; i < connectors.length; i++) {

     var thisConnector = connectors[i];
     var objectRotation = thisConnector.parent.quaternion.clone()
     objectRotation.inverse();

     var parentPoint = new THREE.Vector3(-thisConnector.parent.position.x, -thisConnector.parent.position.y, -thisConnector.parent.position.z);

     parentPoint.applyQuaternion(objectRotation);
     thisConnector.parent.localToWorld(parentPoint);
     thisConnector.worldToLocal(parentPoint);

     thisConnector.geometry.vertices[1] = parentPoint;
     thisConnector.geometry.verticesNeedUpdate = true;
 }
}
// ******************************************************************************************



// ******************************************************************************************
// Distribute points around a sphere
// ******************************************************************************************
function spherical(N, k, rmultiplier) {
 var inc = Math.PI * (3 - Math.sqrt(5));
 var off = 2 / N;
 var y = k * off - 1 + (off / 2);
 var r = Math.sqrt(1 - y * y) * rmultiplier;
 var phi = k * inc;
 return new THREE.Vector3((Math.cos(phi) * r), y, Math.sin(phi) * r);
};
// ******************************************************************************************



// ******************************************************************************************
// View switchers
// ******************************************************************************************
function MapView() {
 if (displayMode === "map") {
     if (currentCenterObject.name == "Agent") {
         currentCenterObject = currentCenterObject.parent;
         ChangeRadialMenu("Overlay", "Overlay", currentCenterObject);
     }
     else
     {
         displayMode = "satellite";
         LoadImageOnMap("images/imersialogo.png");
     }
 }
 else {
     mapbounds = null;
     $.each(currentCenterObject.children, function (i, item) {
         if (item.latitude != null) {
             if (mapbounds)
                 mapbounds.extend(L.latLng(item.latitude, item.longitude));
             else
                 mapbounds = new L.latLngBounds(L.latLng(item.latitude, item.longitude), L.latLng(item.latitude, item.longitude));
         }
     });

     createMap(
         1000, 800,
         new THREE.Vector3(0, -10000, 0),
         new THREE.Vector3(-Math.PI / 2, 0, 0));

     displayMode = "map";
 }
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function ClearObjectData()
{
 if (currentCenterObject) {
     var objectToUse = currentCenterObject;

     if ((objectToUse.name === "Details") || (objectToUse.name === "Metadata") || (objectToUse.name === "Files"))
         objectToUse = objectToUse.parent;

     if (objectToUse.children) {

         // Get a list of objects that match that need removing
         var objectsToRemove = [];
         $.each(objectToUse.children, function (i, item) {
             if ((item.name === "Metadata") || (item.name === "Details") || (item.name === "Files")) {
                 objectsToRemove.push(item);
             }
         });

         // Now remove them
         $.each(objectsToRemove, function (i, item) {
             // Remove its connector from the list of connectors
             var connectorToRemove;
             $.each(item.children, function (i2, item2) {
                 var connectorIndexToRemove;
                 if (item2.name === "connector") {
                     for (var i = 0; i < connectors.length; i++)
                     {
                         if (connectors[i].id === item2.id) {
                             connectorIndexToRemove = i;
                             connectorToRemove = item2;
                         }
                     }
                     connectors.splice(connectorIndexToRemove, 1);
                 }
             });

             // Remove it from the list of ImersiaObjects
             var objectIndexToRemove;
             for (var i = 0; i < ImersiaObjects.length; i++) {
                 if (ImersiaObjects[i].transform.id === item.id) {
                     objectIndexToRemove = i;
                 }
             }
             ImersiaObjects.splice(objectIndexToRemove, 1);

             // Remove it from the list of targets
             var targetIndexToRemove;
             for (var i = 0; i < targetList.length; i++) {
                 if (targetList[i].id === item.id) {
                     targetIndexToRemove = i;
                 }
             }
             targetList.splice(targetIndexToRemove, 1);

             // Remove the Item from the scenegraph and delete it
             objectToUse.remove(item);
             delete (item);
         });
     }
 }
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function DeleteCenterObject() {
 if (currentCenterObject) {
     var objectToUse = currentCenterObject;

     if (objectToUse.children) {

         // Get a list of objects that match that need removing
         var objectsToRemove = [];
         $.each(objectToUse.children, function (i, item) {
             if ((item.name === "Metadata") || (item.name === "Details") || (item.name === "Files")) {
                 objectsToRemove.push(item);
             }
         });

         // Add this object to the list
         objectsToRemove.push(currentCenterObject);

         // Now remove them
         $.each(objectsToRemove, function (i, item) {
             // Remove its connector from the list of connectors
             var connectorToRemove;
             $.each(item.children, function (i2, item2) {
                 var connectorIndexToRemove;
                 if (item2.name === "connector") {
                     for (var i = 0; i < connectors.length; i++) {
                         if (connectors[i].id === item2.id) {
                             connectorIndexToRemove = i;
                             connectorToRemove = item2;
                         }
                     }
                     connectors.splice(connectorIndexToRemove, 1);
                 }
             });

             // Remove it from the list of ImersiaObjects
             var objectIndexToRemove;
             for (var i = 0; i < ImersiaObjects.length; i++) {
                 if (ImersiaObjects[i].transform.id === item.id) {
                     objectIndexToRemove = i;
                 }
             }
             ImersiaObjects.splice(objectIndexToRemove, 1);

             // Remove it from the list of targets
             var targetIndexToRemove;
             for (var i = 0; i < targetList.length; i++) {
                 if (targetList[i].id === item.id) {
                     targetIndexToRemove = i;
                 }
             }
             targetList.splice(targetIndexToRemove, 1);

             // Remove the Item from the scenegraph and delete it
             objectToUse.remove(item);
             delete (item);
         });

         currentCenterObject.parent.remove(currentCenterObject);
         delete (currentCenterObject);
     }
 }
}
// ******************************************************************************************



// ******************************************************************************************
// Load all the users Overlays
// ******************************************************************************************
function LoadOverlays() {
 var parameters = {
     items: ["all"]
 };

 PostToImersia("overlay_list_byowner", parameters, function (data) {
     if (data.err === "") {
         currentOverlays = data;

         var counter = 0;
         $.each(currentOverlays.list, function (i, item) {

             var geometry = new THREE.SphereGeometry(100, 12, 12);
             var material = new THREE.MeshPhongMaterial({ color: 0x6666ff });
             var linematerial = new THREE.LineBasicMaterial({ color: 0x333388 });
             var sphere = new THREE.Mesh(geometry, material);

             overlayPosition = spherical(data.list.length, counter, 100);
             zeroVector = new THREE.Vector3(0, 0, 0);
             var geometry = new THREE.Geometry();
             geometry.vertices.push(zeroVector, overlayPosition);

             sphere.position.set(overlayPosition.x, overlayPosition.y, overlayPosition.z);
             sphere.name = "Overlay";
             sphere.userData = data.title[counter];
             sphere.imersiaID = item;
             targetList.push(sphere);

             center.add(sphere);
             var line = new THREE.Line(geometry, linematerial);
             line.name = "connector";
             sphere.add(line);
             connectors.push(line);

             var imersiaObject = new ImersiaObject("Overlay - " + counter, zeroVector, sphere);
             //WriteToConsole("Overlay - " + counter);

             imersiaObject.distanceToSun = 500;
             imersiaObject.closestDistance = 3000;
             imersiaObject.SetPosition(overlayPosition);

             ImersiaObjects.push(imersiaObject);

             LoadAgents(item, sphere)
             counter++;
         });
     }
 });
}
// ******************************************************************************************



// ******************************************************************************************
// Load all the users Agents
// ******************************************************************************************
function LoadAgents(overlayID, overlayObject) {
 var parameters = {
     overlayid: overlayID,
     count: 100,
     items: ["all"]
 };

 PostToImersia("agent_list_byowner", parameters, function (data) {
     if (data.err === "") {

         $.each(data.list, function (i, item) {
             CreateAgentObject(item, overlayObject, data.list.length, i, data.title[i], data.latitude[i], data.longitude[i]);
         });
     }
     else {
         alert("agent_list_byowner " + data.err + data.debug);
     }
 });

}
// ******************************************************************************************



// ******************************************************************************************
// Create a new Agent Object
// ******************************************************************************************
function CreateAgentObject(agentID, overlayObject, listLength, agentNumber, agentTitle, latitude, longitude) {
 var geometry = new THREE.SphereGeometry(100, 12, 12);
 var material = new THREE.MeshPhongMaterial({ color: 0xaaaaff });
 var linematerial = new THREE.LineBasicMaterial({ color: 0x333388 });
 var sphere = new THREE.Mesh(geometry, material);

 overlayObject.add(sphere);
 var agentPosition = spherical(listLength, agentNumber, 100);
 var zeroVector = new THREE.Vector3(0, 0, 0);
 var geometry = new THREE.Geometry();
 geometry.vertices.push(zeroVector, agentPosition);

 sphere.position.set(agentPosition.x, agentPosition.y, agentPosition.z);
 sphere.name = "Agent";
 sphere.imersiaID = agentID;
 sphere.userData = agentTitle;
 sphere.latitude = latitude;
 sphere.longitude = longitude;
 targetList.push(sphere);

 var line = new THREE.Line(geometry, linematerial);
 line.name = "connector";
 sphere.add(line);
 connectors.push(line);

 var imersiaObject = new ImersiaObject("Agent - " + agentNumber, zeroVector, sphere);

 imersiaObject.latitude = latitude;
 imersiaObject.longitude = longitude;
 imersiaObject.SetPosition(agentPosition);

 ImersiaObjects.push(imersiaObject);
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function CreateOverlayObject(overlayID, overlayObject, listLength, overlayNumber, overlayTitle) {
 var geometry = new THREE.SphereGeometry(100, 12, 12);
 var material = new THREE.MeshPhongMaterial({ color: 0x6666ff });
 var linematerial = new THREE.LineBasicMaterial({ color: 0x333388 });
 var sphere = new THREE.Mesh(geometry, material);

 overlayObject.add(sphere);
 var overlayPosition = spherical(listLength, overlayNumber, 100);
 var zeroVector = new THREE.Vector3(0, 0, 0);
 var geometry = new THREE.Geometry();
 geometry.vertices.push(zeroVector, overlayPosition);

 sphere.position.set(overlayPosition.x, overlayPosition.y, overlayPosition.z);
 sphere.name = "Overlay";
 sphere.imersiaID = overlayID;
 sphere.userData = overlayTitle;
 targetList.push(sphere);

 var line = new THREE.Line(geometry, linematerial);
 line.name = "connector";
 sphere.add(line);
 connectors.push(line);

 var imersiaObject = new ImersiaObject("Overlay - " + overlayNumber, zeroVector, sphere);

 imersiaObject.distanceToSun = 500;
 imersiaObject.closestDistance = 3000;

 imersiaObject.SetPosition(overlayPosition);

 ImersiaObjects.push(imersiaObject);
}
// ******************************************************************************************



// ******************************************************************************************
// Create a new File or Metadata Object
// ******************************************************************************************
function CreateFileOrMetadataObject(objectType, agentObject, listLength, itemNumber, key, value) {
 var geometry = new THREE.SphereGeometry(100, 12, 12);
 var material = new THREE.MeshPhongMaterial({ color: 0xffaaaa });
 var linematerial = new THREE.LineBasicMaterial({ color: 0x883333 });
 if (objectType == "File") {
     material = new THREE.MeshPhongMaterial({ color: 0xaaffff });
     linematerial = new THREE.LineBasicMaterial({ color: 0x338888 });
 }
 var sphere = new THREE.Mesh(geometry, material);

 agentObject.add(sphere);
 var itemPosition = spherical(listLength, itemNumber, 100);
 var zeroVector = new THREE.Vector3(0, 0, 0);
 var geometry = new THREE.Geometry();
 geometry.vertices.push(zeroVector, itemPosition);

 sphere.position.set(itemPosition.x, itemPosition.y, itemPosition.z);
 sphere.name = objectType;
 sphere.userData = key + " = " + value;
 sphere.key = key;
 sphere.value = value;
 targetList.push(sphere);

 var line = new THREE.Line(geometry, linematerial);
 line.name = "connector";
 sphere.add(line);
 connectors.push(line);

 var imersiaObject = new ImersiaObject(objectType + " - " + itemNumber, zeroVector, sphere);

 imersiaObject.SetPosition(itemPosition);

 ImersiaObjects.push(imersiaObject);
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function ShowMessageAndRadialMenu(theAction, radialMenu, theMessage)
{
 var vector = new THREE.Vector3();
 vector.set(currentCenterObject.position.x, currentCenterObject.position.y, currentCenterObject.position.z);
 currentCenterObject.parent.localToWorld(vector);

 // map to normalized device coordinate (NDC) space
 vector.project(camera);

 // map to 2D screen space
 vector.x = Math.round((vector.x + 1) * window.innerWidth / 2),
 vector.y = Math.round((-vector.y + 1) * window.innerHeight / 2);
 vector.z = 0;

 // Set Yes No Menu
 ChangeRadialMenu(theAction, radialMenu, currentCenterObject);

 $("#editor").hide();
 $("#message").show();
 $("#messagelabel").html(theMessage);
 $("#message").css({ left: vector.x - 150, top: vector.y - 20 });
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function ShowMessageAndGetInput(theAction, radialMenu, theMessage, theValue) {
 var vector = new THREE.Vector3();
 vector.set(currentCenterObject.position.x, currentCenterObject.position.y, currentCenterObject.position.z);
 currentCenterObject.parent.localToWorld(vector);

 // map to normalized device coordinate (NDC) space
 vector.project(camera);

 // map to 2D screen space
 vector.x = Math.round((vector.x + 1) * window.innerWidth / 2),
 vector.y = Math.round((-vector.y + 1) * window.innerHeight / 2);
 vector.z = 0;

 // Set Yes No Menu
 ChangeRadialMenu(theAction, radialMenu, currentCenterObject);

 $("#editor").show();
 $("#message").hide();
 $("#textlabel").html(theMessage);
 $("#textinput").val(theValue);
 $("#editor").css({ left: vector.x - 250, top: vector.y - 20 });
}
// ******************************************************************************************



// ******************************************************************************************
// Various actions from the Radial Menus
// ******************************************************************************************
function NewAgent() { ShowMessageAndGetInput("NewAgent", "YesNo", "New Agent name", ""); }
function DeleteAgent() { ShowMessageAndRadialMenu("DeleteAgent", "YesNo", "Delete Agent?"); }
function NewOverlay() { ShowMessageAndGetInput("NewOverlay", "YesNo", "New Overlay name", ""); }
function DeleteOverlay() { ShowMessageAndRadialMenu("DeleteOverlay", "YesNo", "Delete Overlay and all its Agents?"); }
function ReallyDeleteOverlay() { ShowMessageAndRadialMenu("ReallyDeleteOverlay", "YesNo", "Are you sure ? Cannot be undone..."); }
function Logout() { ShowMessageAndRadialMenu("Logout", "YesNo", "Log out?"); }
function EditDetail() { ShowMessageAndGetInput("EditDetail", "YesNo", currentCenterObject.key, currentCenterObject.value); }
function EditMetadata() { ShowMessageAndGetInput("EditMetadata", "YesNo", currentCenterObject.key, currentCenterObject.value); }
function AddMetadata() { ShowMessageAndGetInput("AddMetadata", "YesNo", "New Variable Name", ""); }
function DeleteMetadata() { ShowMessageAndRadialMenu("DeleteMetadata", "YesNo", "Delete Variable?"); }
// ******************************************************************************************



// ******************************************************************************************
// Go between Agent Menus
// ******************************************************************************************
function NextAgentMenu() {
 ChangeRadialMenu("Agent2", "Agent2", currentCenterObject);
}
function PrevAgentMenu() {
 ChangeRadialMenu("Agent", "Agent", currentCenterObject);
}
// ******************************************************************************************



// ******************************************************************************************
// "Metadata", "Files", "QRCode", "MailingList", "Analytics", "Programming", "Wotcha", "Details"
// ******************************************************************************************
function LoadMetaData() {
 WriteToConsole("Loading Metadata for " + currentCenterObject.userData + "<br>");
 if (currentCenterObject.imersiaID)
 {
     ClearObjectData();

     var objectType = currentCenterObject.name.toLowerCase();
     var parameters = {
         overlayid: currentCenterObject.imersiaID,
         agentid: currentCenterObject.imersiaID,
         items: ["metadata"]
     };

     PostToImersia(objectType + "_getdetails", parameters, function (data) {
         if (data.err === "") {
             var returnData = data[objectType].metadata;
             WriteToConsole(JSON.stringify(returnData) + "<br>");
             var counter = 0;
             $.each(Object.keys(returnData), function (i, item) {

                 var geometry = new THREE.SphereGeometry(100, 12, 12);
                 var material = new THREE.MeshPhongMaterial({ color: 0xffaaaa });
                 var linematerial = new THREE.LineBasicMaterial({ color: 0x883333 });
                 var sphere = new THREE.Mesh(geometry, material);

                 currentCenterObject.add(sphere);
                 objectPosition = spherical(Object.keys(returnData).length, counter, 100);
                 zeroVector = new THREE.Vector3(0, 0, 0);
                 var geometry = new THREE.Geometry();
                 geometry.vertices.push(zeroVector, objectPosition);

                 sphere.position.set(objectPosition.x, objectPosition.y, objectPosition.z);
                 sphere.name = "Metadata";
                 sphere.userData = item + " = " + JSON.stringify(returnData[item]);
                 sphere.value = returnData[item];
                 sphere.key = item;
                 targetList.push(sphere);

                 var line = new THREE.Line(geometry, linematerial);
                 line.name = "connector";
                 sphere.add(line);
                 connectors.push(line);

                 var imersiaObject = new ImersiaObject("Metadata - " + counter, zeroVector, sphere);

                 imersiaObject.distanceToSun = 500;
                 imersiaObject.closestDistance = 1000;
                 imersiaObject.SetPosition(objectPosition);

                 ImersiaObjects.push(imersiaObject);

                 counter++;
             });

             ChangeRadialMenu("MetadataSub", "MetadataSub", currentCenterObject);
         }
     });
 }
}
// ******************************************************************************************



// ******************************************************************************************
// "Metadata", "Files", "QRCode", "MailingList", "Analytics", "Programming", "Wotcha", "Details"
// ******************************************************************************************
function LoadFiles() {
 WriteToConsole("Loading Files for " + currentCenterObject.userData + "<br>");

 if (currentCenterObject.imersiaID) {
     ClearObjectData();

     var objectType = currentCenterObject.name.toLowerCase();
     var parameters = {
         overlayid: currentCenterObject.imersiaID,
         agentid: currentCenterObject.imersiaID
     };

     PostToImersia(objectType + "_file_list", parameters, function (data) {
         if (data.err === "") {
             var returnData = data.files;
             WriteToConsole(JSON.stringify(returnData) + "<br>");
             var counter = 0;
             $.each(returnData, function (i, item) {

                 var geometry = new THREE.SphereGeometry(100, 12, 12);
                 var material = new THREE.MeshPhongMaterial({ color: 0xaaffff });
                 var linematerial = new THREE.LineBasicMaterial({ color: 0x338888 });
                 var sphere = new THREE.Mesh(geometry, material);

                 currentCenterObject.add(sphere);
                 objectPosition = spherical(returnData.length, counter, 100);
                 zeroVector = new THREE.Vector3(0, 0, 0);
                 var geometry = new THREE.Geometry();
                 geometry.vertices.push(zeroVector, objectPosition);

                 sphere.position.set(objectPosition.x, objectPosition.y, objectPosition.z);
                 sphere.name = "Files";
                 sphere.userData = item;
                 targetList.push(sphere);

                 var line = new THREE.Line(geometry, linematerial);
                 line.name = "connector";
                 sphere.add(line);
                 connectors.push(line);

                 var imersiaObject = new ImersiaObject("Files - " + counter, zeroVector, sphere);

                 imersiaObject.distanceToSun = 500;
                 imersiaObject.closestDistance = 1000;
                 imersiaObject.SetPosition(objectPosition);

                 ImersiaObjects.push(imersiaObject);

                 counter++;
             });
         }
     });
 }
}
// ******************************************************************************************



// ******************************************************************************************
// "Metadata", "Files", "QRCode", "MailingList", "Analytics", "Programming", "Wotcha", "Details"
// ******************************************************************************************
function LoadQRCode() {
 WriteToConsole("Loading QR Code for " + currentCenterObject.userData + "<br>");
}
// ******************************************************************************************



// ******************************************************************************************
// "Metadata", "Files", "QRCode", "MailingList", "Analytics", "Programming", "Wotcha", "Details"
// ******************************************************************************************
function LoadMailingList() {
 WriteToConsole("Loading Mailing List for " + currentCenterObject.userData + "<br>");
}
// ******************************************************************************************



// ******************************************************************************************
// "Metadata", "Files", "QRCode", "MailingList", "Analytics", "Programming", "Wotcha", "Details"
// ******************************************************************************************
function LoadAnalytics() {
 WriteToConsole("Loading Analytics for " + currentCenterObject.userData + "<br>");
}
// ******************************************************************************************



// ******************************************************************************************
// "Metadata", "Files", "QRCode", "MailingList", "Analytics", "Programming", "Wotcha", "Details"
// ******************************************************************************************
function LoadProgramming() {
 WriteToConsole("Loading Programming for " + currentCenterObject.userData + "<br>");
}
// ******************************************************************************************



// ******************************************************************************************
// "Metadata", "Files", "QRCode", "MailingList", "Analytics", "Programming", "Wotcha", "Details"
// ******************************************************************************************
function LoadWotcha() {
 WriteToConsole("Loading Wotcha for " + currentCenterObject.userData + "<br>");
}
// ******************************************************************************************



// ******************************************************************************************
// "Metadata", "Files", "QRCode", "MailingList", "Analytics", "Programming", "Wotcha", "Details"
// ******************************************************************************************
function LoadDetails() {
 WriteToConsole("Loading Details for " + currentCenterObject.userData + "<br>");
 if (currentCenterObject.imersiaID) {
     ClearObjectData();

     var objectType = currentCenterObject.name.toLowerCase();
     var parameters = {
         overlayid: currentCenterObject.imersiaID,
         agentid: currentCenterObject.imersiaID,
         items: ["title", "description", "imageurl", "webpageurl", "soundurl", "latitude", "longitude", "altitude", "radius"]
     };

     PostToImersia(objectType + "_getdetails", parameters, function (data) {
         if (data.err === "") {
             var returnData = data[objectType];
             WriteToConsole(JSON.stringify(returnData) + "<br>");
             var counter = 0;
             $.each(Object.keys(returnData), function (i, item) {

                 var geometry = new THREE.SphereGeometry(100, 12, 12);
                 var material = new THREE.MeshPhongMaterial({ color: 0xffffaa });
                 var linematerial = new THREE.LineBasicMaterial({ color: 0x888833 });
                 var sphere = new THREE.Mesh(geometry, material);

                 currentCenterObject.add(sphere);
                 objectPosition = spherical(Object.keys(returnData).length, counter, 100);
                 zeroVector = new THREE.Vector3(0, 0, 0);
                 var geometry = new THREE.Geometry();
                 geometry.vertices.push(zeroVector, objectPosition);

                 sphere.position.set(objectPosition.x, objectPosition.y, objectPosition.z);
                 sphere.name = "Details";
                 sphere.userData = item + " = " + JSON.stringify(returnData[item]);
                 sphere.value = returnData[item];
                 sphere.key = item;
                 targetList.push(sphere);

                 var line = new THREE.Line(geometry, linematerial);
                 line.name = "connector";
                 sphere.add(line);
                 connectors.push(line);

                 var imersiaObject = new ImersiaObject("Details - " + counter, zeroVector, sphere);

                 imersiaObject.distanceToSun = 500;
                 imersiaObject.closestDistance = 1000;
                 imersiaObject.SetPosition(objectPosition);

                 ImersiaObjects.push(imersiaObject);

                 counter++;
             });
         }
     });
 }
}
// ******************************************************************************************



// ******************************************************************************************
// A major thoroughfare where decisions are acted upon...
// ******************************************************************************************
function YesSelected() {
 switch (currentCommand)
 {
     case "Logout":
         window.location = "https://auth.imersia.net";
         break;

     case "NewAgent":
         // New Agent
         var parameters = {
             overlayid: currentCenterObject.imersiaID,
             agent: {
                 title: $("#textinput").val()
             }
         };

         PostToImersia("agent_new", parameters, function (data) {
             if (data.err === "") {
                 // If Agent created successfully, add it to the visible structure
                 CreateAgentObject(data.agentid, currentCenterObject, 1, 1, $("#textinput").val(), 0, 0);
             }
             ChangeRadialMenu("Overlay", "Overlay", currentCenterObject);
             // Hide the editor pane
             $("#editor").hide();
         });
         break;

     case "DeleteAgent":
         var parameters = {
             agentid: currentCenterObject.imersiaID
         };

         PostToImersia("agent_delete", parameters, function (data) {
             if (data.err === "") {
                 // If Agent delete successfully, remove it from the visible structure and move the focus to the Overlay
                 var newCenterObject = currentCenterObject.parent;
                 DeleteCenterObject();
                 currentCenterObject = newCenterObject;
                 ChangeRadialMenu("Overlay", "Overlay", newCenterObject);
             }
             else
             {
                 ChangeRadialMenu("Agent", "Agent", currentCenterObject);
             }
             // Hide the message pane
             $("#message").hide();
         });
         break;

     case "NewOverlay":
         // New Overlay
         var parameters = {
             overlay: {
                 title: $("#textinput").val()
             }
         };

         PostToImersia("overlay_new", parameters, function (data) {
             if (data.err === "") {
                 // If Agent created successfully, add it to the visible structure
                 CreateOverlayObject(data.overlayid, currentCenterObject, 1, 1, $("#textinput").val());
             }
             ChangeRadialMenu("Companion", "Companion", currentCenterObject);
             // Hide the editor pane
             $("#editor").hide();
         });
         break;

     case "DeleteOverlay":
         ReallyDeleteOverlay();
         break;

     case "ReallyDeleteOverlay":
         var parameters = {
             overlayid: currentCenterObject.imersiaID
         };

         PostToImersia("overlay_delete", parameters, function (data) {
             if (data.err === "") {
                 // If Overlay deleted successfully, remove it from the visible structure and move the focus to the Companion
                 var newCenterObject = currentCenterObject.parent;
                 DeleteCenterObject();
                 currentCenterObject = newCenterObject;
                 ChangeRadialMenu("Companion", "Companion", newCenterObject);
             }
             else {
                 ChangeRadialMenu("Overlay", "Overlay", currentCenterObject);
             }
             // Hide the message pane
             $("#message").hide();
         });
         break;

     case "EditDetail":
         // Get the key and new Value
         key = currentCenterObject.key;
         newValue = $("#textinput").val();
         // Set these in the 3D object
         currentCenterObject.value = newValue;
         currentCenterObject.userData = key + " = " + JSON.stringify(newValue);
         if (key === "title") currentCenterObject.parent.userData = newValue;
         // Write a message
         WriteToConsole("Writing " + $("#textinput").val() + " to Overlay " + currentCenterObject.parent.imersiaID);
         // Write to the Agent
         var itemDetails = {}; itemDetails[key] = newValue;
         if (currentCenterObject.parent.name === "Agent")
         {
             var parameters = {
                 agentid: currentCenterObject.parent.imersiaID,
                 agent: itemDetails
             };
             PostToImersia("agent_setdetails", parameters, function (data) {
             });
         }
         else if (currentCenterObject.parent.name === "Overlay")
         {
             var parameters = {
                 overlayid: currentCenterObject.parent.imersiaID,
                 overlay: itemDetails
             };
             PostToImersia("overlay_setdetails", parameters, function (data) {
             });
         }
         // Change the Menu back
         ChangeRadialMenu("Details", "Details", currentCenterObject);
         // Hide the editor pane
         $("#editor").hide();
         break;

     case "EditMetadata":
         // Get the key and new Value
         key = currentCenterObject.key;
         newValue = $("#textinput").val();
         // Set these in the 3D object
         currentCenterObject.value = newValue;
         currentCenterObject.userData = key + " = " + JSON.stringify(newValue);
         // Write a message
         WriteToConsole("Writing " + $("#textinput").val() + " to Agent " + currentCenterObject.parent.imersiaID);
         // Write to the Agent
         var parameters = {
             agentid: currentCenterObject.parent.imersiaID,
             overlayid: currentCenterObject.parent.imersiaID,
             key: key,
             value: newValue
         };
         if (currentCenterObject.parent.name === "Agent")
         {
             PostToImersia("agent_metadata_setvalue", parameters, function (data) {
             });
         }
         else if (currentCenterObject.parent.name === "Overlay")
         {
             PostToImersia("overlay_metadata_setvalue", parameters, function (data) {
             });
         }
         // Change the Menu back
         ChangeRadialMenu("Metadata", "Metadata", currentCenterObject);
         // Hide the editor pane
         $("#editor").hide();
         break;

     case "AddMetadata":
         // Get the key and new Value
         key = $("#textinput").val();
         newValue = "";
        // Write a message
         WriteToConsole("Adding Metadata " + key + " to Agent or Overlay " + currentCenterObject.imersiaID);
         // Write to the Agent
         var parameters = {
             agentid: currentCenterObject.imersiaID,
             overlayid: currentCenterObject.imersiaID,
             key: key,
             value: newValue
         };
         if (currentCenterObject.name === "Agent") {
             PostToImersia("agent_metadata_setvalue", parameters, function (data) {
                 // If Metadata created successfully, add it to the visible structure
                 CreateFileOrMetadataObject("Metadata", currentCenterObject, 1, 1, key, newValue)
             });
         }
         else if (currentCenterObject.name === "Overlay") {
             PostToImersia("overlay_metadata_setvalue", parameters, function (data) {
                 // If Metadata created successfully, add it to the visible structure
                 CreateFileOrMetadataObject("Metadata", currentCenterObject, 1, 1, key, newValue)
             });
         }
         // Change the Menu back
         ChangeRadialMenu("Metadata", "Metadata", currentCenterObject);
         // Hide the editor pane
         $("#editor").hide();
         break;

     case "DeleteMetadata":
         // Get the key and new Value
         key = currentCenterObject.key;
         // Write a message
         WriteToConsole("Deleting Metadata " + key + " from Agent or Overlay " + currentCenterObject.parent.imersiaID);
         // Write to the Agent
         var parameters = {
             agentid: currentCenterObject.parent.imersiaID,
             overlayid: currentCenterObject.parent.imersiaID,
             key: key
         };
         if (currentCenterObject.parent.name === "Agent") {
             PostToImersia("agent_metadata_delete", parameters, function (data) {
                 // If Metadata deleted successfully, add it to the visible structure
                 var newCenterObject = currentCenterObject.parent;
                 DeleteCenterObject();
                 currentCenterObject = newCenterObject;
                 ChangeRadialMenu("Agent", "Agent", newCenterObject);
             });
         }
         else if (currentCenterObject.parent.name === "Overlay") {
             PostToImersia("overlay_metadata_delete", parameters, function (data) {
                 // If Metadata deleted successfully, add it to the visible structure
                 var newCenterObject = currentCenterObject.parent;
                 DeleteCenterObject();
                 currentCenterObject = newCenterObject;
                 ChangeRadialMenu("Overlay", "Overlay", newCenterObject);
             });
         }
         // Hide the message pane
         $("#message").hide();
         break;
 }
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function NoSelected() {
 // Switch the menu back
 ChangeRadialMenu(currentCenterObject.name, currentCenterObject.name, currentCenterObject);

 // Hide the editor pane
 $("#editor").hide();
 $("#message").hide();
}
// ******************************************************************************************



// ******************************************************************************************
// Change the menu and anchor it to a specified object
// ******************************************************************************************
function ChangeRadialMenu(command, newMenu, anchorObject) {
 // Switch the menu back
 currentMenu = newMenu;
 currentCommand = command;
 for (var i = 0; i < radialMenuTypes.length; i = i + 2) {
     var menuType = radialMenuTypes[i];
     radialMenus[menuType].visible = false;
 }
 radialMenus[currentMenu].visible = true;
 anchorObject.add(radialMenus[currentMenu]);
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function WriteToConsole(message) {
 if (showConsole) $("#Console").append(message);
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function PostToImersia(command, parameters, resultCallback) {

 //readCounter = readCounter + 1;
 storedParameters = JSON.stringify(parameters);
 storedParameters = storedParameters.replace(/\"/g, '"');
 //command = command.replace(/_/g, '/');

 storedQuery = APIBaseAddress;
 //storedQuery = APIBaseAddress + command + "?" + storedParameters;
 var ajaxRequest = $.ajax({
     beforeSend: function (xhrObj) {
         xhrObj.setRequestHeader("Content-Type", "application/json");
         xhrObj.setRequestHeader("tokenid", tokenID);
         xhrObj.setRequestHeader("user", userName);
         xhrObj.setRequestHeader("location", currentGeoHash);
         xhrObj.setRequestHeader("command", command);
         xhrObj.setRequestHeader("developerid", developerID);
         xhrObj.setRequestHeader("parameters", encodeURIComponent(storedParameters));

         //$('#Command_Loader').show();
     },
     type: 'POST',
     url: storedQuery,
     dataType: 'json'
 });

 ajaxRequest.fail(function (data) {
     //readCounter = readCounter - 1;
     //if (readCounter == 0) $('#Command_Loader').hide();
     //alert(JSON.stringify(data));
 });

 ajaxRequest.done(function (data) {
     //readCounter = readCounter - 1;
     //if (readCounter == 0) $('#Command_Loader').hide();
     resultCallback(eval(data));
 });

 return false;
}
// ******************************************************************************************



// ******************************************************************************************
// * Post a file with a command to the Imersia API and return the result
// ******************************************************************************************
function PostFileToImersia(command, parameters, theFile, resultCallback) {

 //readCounter = readCounter + 1;
 storedParameters = JSON.stringify(parameters);

 storedQuery = APIBaseAddress;
 var ajaxRequest = $.ajax({
     beforeSend: function (xhrObj) {
         xhrObj.setRequestHeader("tokenid", tokenID);
         xhrObj.setRequestHeader("user", userName);
         xhrObj.setRequestHeader("location", currentGeoHash);
         xhrObj.setRequestHeader("command", command);
         xhrObj.setRequestHeader("developerid", developerID);
         xhrObj.setRequestHeader("parameters", encodeURIComponent(storedParameters));
         //$('#Command_Loader').show();
     },

     type: 'POST',
     data: theFile,
     url: storedQuery,
     dataType: 'jsonp',
     contentType: false,
     processData: false,
     crossDomain: true
 });

 ajaxRequest.fail(function (data) {
     //readCounter = readCounter - 1;
     //if (readCounter == 0) $('#Command_Loader').hide();
     resultCallback(data);
 });

 ajaxRequest.done(function (data) {
     //readCounter = readCounter - 1;
     //if (readCounter == 0) $('#Command_Loader').hide();
     resultCallback(eval(data));
 });

 return false;
}
// ******************************************************************************************



// ******************************************************************************************
// ******************************************************************************************
function LogInToImersia(username, password)
{
 
 datastring =  "Email=" + username + "&Password=" + password;
 var ajaxRequest = $.ajax({
     type: 'POST',
     url: "https://auth.imersia.net/api/user/login/",
     data: datastring,
     dataType: 'jsonp'
 });

 ajaxRequest.fail( function (data) {
     alert("Failed");
 });
 ajaxRequest.done( function (data) {
     alert("Success");
 });

 return false;
}
// ******************************************************************************************



// ******************************************************************************************
// Store the current location
// ******************************************************************************************
function GetLocation(location) {

 if (location.coords) {
     currentLatitude = location.coords.latitude;
     currentLongitude = location.coords.longitude;
     currentAltitude = location.coords.altitude;
     currentAccuracy = location.coords.accuracy;
     currentHeading = location.coords.heading;
 } else {
     currentLatitude = location.latitude;
     currentLongitude = location.longitude;
     currentAltitude = location.altitude;
     currentAccuracy = location.accuracy;
     currentHeading = location.heading;
 }

 //currentGeoHash = encodeGeoHash(currentLatitude, currentLongitude);
 //$("#Current_Location").text("Current Location : " + currentGeoHash);
}

function GetLocationError(err) {
 if (err.code == 1) {
     $("#Current_Location").text("User denied geolocation.");
 }
 else if (err.code == 2) {
     $("#Current_Location").text("Position unavailable.");
 }
 else if (err.code == 3) {
     $("#Current_Location").text("Timeout expired.");
 }
 else {
     $("#Current_Location").text("ERROR:" + err.message);
 }
}
// ******************************************************************************************
