# Reality2 Data Backup Plugin

### Description

The Data backup plugin allows you to save the current data stream to disk as an encrypted blob, and retrieve it later.


### Definition

The core backup functions, presently, are store, retrieve and delete.

#### store

Stores the current data stream (ie any values read from other sources, calculated or set) to a named encrypted blob in the database.  The decryption key is required in case there is already data stored under that name, to ensure you have the authority (by knowing the key) to decrypt it, and hence replace it.  In this implementation, the encryption and decryption keys are the same, so just the former may be included.

```yaml
- command: store
  plugin: ai.reality2.backup
  parameters: 
    name: "Test Backup"
    encryption_key: __encryption_key__
    decryption_key: __decryption_key__
```

The encryption and decryption keys are base64 encoded 32 byte binary sequence.  This may be created in python like this:

```python
binary_key = os.urandom(32)
encryption_key = base64.b64encode(binary_key).decode('utf-8')
```

Ideally, you would want to create this externally to your python code and store it somewherre safe if you intend being able to read and decrypt the data later...  The backup_test.py demo is a good example.

#### retrieve

Retrieves and decrypts the data.

```yaml
- command: retrieve
  plugin: ai.reality2.backup
  parameters: 
    name: "Test Backup"
    decryption_key: __decryption_key__
```

The decryption key in this case has to be the same as the encryption key as it usses a symmetric encryption algorithm.  This may change later.  Both the name and encryption/decryption key have to match or the data will not be retreived.

#### delete

Deletes the data, if and only if the name and decryption key match.

```yaml
- command: delete
  plugin: ai.reality2.backup
  parameters: 
    name: "Test Backup"
    decryption_key: __decryption_key__
```