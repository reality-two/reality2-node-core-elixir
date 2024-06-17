# Reality2 Data Backup Plugin

### Description

The Data backup plugin allows you to save the current data stream to disk as an encrypted blob, and retrieve it later.


### Definition

The core backup functions, presently, are store, retrieve and delete.

#### store

Stores the current data stream (ie any values read from other sources, calculated or set) to a named encrypted blob in the database.

```yaml
- command: store
  plugin: ai.reality2.stpre
  parameters: 
    name: "Test Backup"
    encryption_key: __encryption_key__
```

The encryption key is a base64 encoded 32 byte binary sequence.  This may be created in python like this:

```python
binary_key = os.urandom(32)
encryption_key = base64.b64encode(binary_key).decode('utf-8')
```

Ideally, you would want to create this externally to your python code and store it somewherre safe if you intend being able to read and decrypt the data later...  The backup_test.py demo is a good example.

#### retrieve

Gets the currrent position of a Sentant (returns latitude, longitude, geohash, altitude and radius).

```yaml
- command: retrieve
  plugin: ai.reality2.stpre
  parameters: 
    name: "Test Backup"
    encryption_key: __decryption_key__
```

The decryption key in this case is the same as the encryption key as it usses a symmetric encryption algorithm.  This may change later.  Both the name and encryption key have to match or the data will not be retreived.

#### delete

Searches in a radius (in meters) around the current Sentant for other Sentants.  Returns an array of tuples of Sentant IDs and distances (in meters), ie

`'sentants': [{'id': 'dc4029b2-ffbc-11ee-8189-18c04dee389e', 'distance': 64.64886814019957}]`

Only Sentants that are within range, and whose own radius encompasses the searching Sentant, will be found.

```yaml
- command: delete
  parameters: 
    name: "Test Backup"
    encryption_key: __decryption_key__
```