# Reality2 Geospatial Plugin

### Description

The Geospatial plugin brings a sense of place on the planet using latitude, longitude and altitude.  It not only stores and manages the location of the Sentant, but provides functionality for locating other Sentants nearby, and for using [GeoHashes](https://en.wikipedia.org/wiki/Geohash).

#### Future plans:

This plugin could store a range of Geospatial data such as lines and polygons (as well as points), and manage efficient operations on these.  It could also integrate with other Plugins for location by image recognition, or wifi triangulation, for example.  Further, more complex scenarios may be created using geospatial paths.

### Definition

The core geospatial functions, presently, are set, get and search.

#### set

Sets the geospatial position of a Sentant using either latitude and longitude or geohash.

```yaml
- command: set
  plugin: ai.reality2.geospatial
  parameters: 
    latitude: -36.860426874915866
    longitude: 174.77767677926224
    altitude: 100
    radius: 100
```

or

```yaml
- command: set
  plugin: ai.reality2.geospatial
  parameters:
    geohash: rckq31v0rn3
    altitude: 100
    radius: 100
```

The radius, if set, determines how close (in meters) the searching Sentant has to be in order to be able to find this one.  This allows Sentants to be findable only if the searching Sentnat is close enough - great for Treasure Hunts.  It can also effectively hide from being found by setting a very small radius.  **A radius of zero means 'ignore the radius'.**

#### get

Gets the currrent position of a Sentant (returns latitude, longitude, geohash, altitude and radius).

```yaml
- command: get
  plugin: ai.reality2.geospatial
```

#### search

Searches in a radius (in meters) around the current Sentant for other Sentants.  Returns an array of tuples of Sentant IDs and distances (in meters), ie

`'sentants': [{'id': 'dc4029b2-ffbc-11ee-8189-18c04dee389e', 'distance': 64.64886814019957}]`

Only Sentants that are within range, and whose own radius encompasses the searching Sentant, will be found.

```yaml
- command: search
  plugin: ai.reality2.geospatial
  parameters:
    radius: 100
```

***

There are other functions that are not so relevant yet:

#### all

Gets all the geospatial data on this Sentant, which presently is just one point.

```yaml
- command: all
  plugin: ai.reality2.geospatial
```

#### delete

Deletes the geolocation from the Sentant.

```yaml
- command: delete
  plugin: ai.reality2.geospatial
```

#### clear

Clears all the geolocation data from this Sentant.  Currently, with only one point stored, that is the same as the delete command above.

```yaml
- command: clear
  plugin: ai.reality2.geospatial
```

### Future functionality

#### distance

Returns the distance in meters between the current Sentant and the one given (if it has a geospatial location).

```yaml
- command: distance
  plugin: ai.reality2.geospatial
  parameters:
    id: dc383bda-ffbc-11ee-a338-18c04dee389e
```

or

```yaml
- command: distance
  plugin: ai.reality2.geospatial
  parameters:
    name: The Domain
```

### GIS

Add some basic GIS capability with different geographical entities, and the ability to perform analysis.

#### Automated movement

Setting a Sentant on a path, just like NPCs in games, could allow for some complex interaction scenarios.  These may be triggered, for example, to sense when someone comes near to a given location, and to start movement along a given path to lead the person on a journey.

#### Persistance

Presently, the Geospatial information is stored only in memory.  Oftentimes, if Sentants are moving around, it may be desirable to store the current position (and other Geospatial data) in long-term storage.  This might be through a database plugin.