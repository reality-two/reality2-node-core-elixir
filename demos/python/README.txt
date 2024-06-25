To run these, use python3, and install the following libraries:

pip3 install gql
pip3 install requests
pip3 install requests_toolbelt

The encryption and decryption keys are created like this:

# ----------------------------------------------------------------------------------------------------
# You can create an encryption key with os.urandom(32)
# This is required for storing and retrieving to and from the database
# At the moment, we use symmetric encryption, so the encryption and decryption keys are the same.
# Note also that it has to be base64 encoded so we can pass it through the API.
encryption_key = base64.b64encode(b'\xc5\x13\x12\xd7\x0e\x14\xd1;{pf\xae\xe3\xfc\xe7Z+\xc2\x8b\x05\xdd4=\x8a\xfeB\x91\xa8JQ\xfa+').decode('utf-8')
decryption_key = base64.b64encode(b'\xc5\x13\x12\xd7\x0e\x14\xd1;{pf\xae\xe3\xfc\xe7Z+\xc2\x8b\x05\xdd4=\x8a\xfeB\x91\xa8JQ\xfa+').decode('utf-8')
# ----------------------------------------------------------------------------------------------------

