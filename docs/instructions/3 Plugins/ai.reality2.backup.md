# Reality2 Data Backup Plugin

### Description

The Data backup plugin allows you to save the current data stream to disk as an encrypted blob, and retrieve it later.  The encryption and decryption keys come from the `keys` section of the Sentant (see the Sentant definition page).

### Definition

The core backup functions, presently, are store, retrieve and delete.

#### store

Stores the current data stream (ie any values read from other sources, calculated or set) to an encrypted blob in the database.

```yaml
- command: store
  plugin: ai.reality2.backup
```

#### retrieve

Retrieves and decrypts the data and inserts it into the data stream, overwriting any existing data with same keys.

```yaml
- command: retrieve
  plugin: ai.reality2.backup
```

The decryption key in this case has to be the same as the encryption key as it usses a symmetric encryption algorithm.  This may change later.  Both the name and encryption/decryption key have to match or the data will not be retreived.

#### delete

Deletes the data, if and only if the name and decryption key match.

```yaml
- command: delete
  plugin: ai.reality2.backup
```