[![Build Status](https://travis-ci.org/ivRodriguezCA/nuntius.svg?branch=master)](https://travis-ci.org/ivRodriguezCA/nuntius)
[![CocoaPods](https://img.shields.io/cocoapods/v/nuntius.svg)](https://cocoapods.org/pods/nuntius)

# [β] nuntius
nuntius is an iOS framework that helps iOS developers integrate [end-to-end encryption (e2ee)](https://en.wikipedia.org/wiki/End-to-end_encryption) into their apps with simple APIs. It provides an objc implementation of the Extended Triple Diffie-Hellman (X3DH) and Double Ratchet protocols using [libsodium](https://github.com/jedisct1/libsodium) for most of the crypto operations. nuntius provides Authenticated Encryption with Associated Data (AEAD) via AES-CBC-HMAC-256, it uses Apple's CommonCrypto framework for these operations, but in the future I'll move to libsodium-only crypto and use [ChaCha20-Poly1305](https://en.wikipedia.org/wiki/Poly1305) instead.

## Extended Triple Diffie-Hellman (X3DH)
As described [here](https://whispersystems.org/docs/specifications/x3dh/), X3DH is a key agreement protocol that establishes a shared *session* key between two parties that mutually authenticate each other based on public keys. `nuntius` uses:
- [Curve25519](https://cr.yp.to/ecdh.html) for elliptic curve public key cryptography [(ECDH)](https://en.wikipedia.org/wiki/Elliptic_curve_Diffie%E2%80%93Hellman)
- [Ed25519](https://ed25519.cr.yp.to/) for public-key signatures
- [SHA256](https://en.wikipedia.org/wiki/SHA-2) hashing algorithm
- [BLAKE2b](https://blake2.net/) as [KDF](https://en.wikipedia.org/wiki/Key_derivation_function) for key derivation

## Double Ratchet
As described [here](https://whispersystems.org/docs/specifications/doubleratchet/), the Double Ratchet protocol is used after a shared *session* key is established between two parties (for example with X3DH) to send and receive encrypted messages. It provides [forward secrecy (FS)](https://en.wikipedia.org/wiki/Forward_secrecy) by deriving new encryption keys after every Double Ratchet message, meaning that if an encryption key is compromised, it cannot be used to decrypt old messages. It provides a symmetric encryption key ratachet and a Diffie-Hellman public key encryption ratachet, this is why is called Double Ratchet. `nuntius` uses:
- [Curve25519](https://cr.yp.to/ecdh.html) for elliptic curve public key cryptography [(ECDH)](https://en.wikipedia.org/wiki/Elliptic_curve_Diffie%E2%80%93Hellman)
- [BLAKE2b](https://blake2.net/) as [KDF](https://en.wikipedia.org/wiki/Key_derivation_function) for key derivation
- [AES-256](https://en.wikipedia.org/wiki/Advanced_Encryption_Standard) in [CBC mode](https://en.wikipedia.org/wiki/Block_cipher_mode_of_operation#Cipher_Block_Chaining_.28CBC.29) with PKCS#7 padding for symmectric encryption
- [HMAC-256](https://en.wikipedia.org/wiki/Hash-based_message_authentication_code) for Authenticated Encryption

## Importing

### Cocoapods
```sh
pod "nuntius"
```
In Objc import the nuntius header
```Objc
#import <nuntius/nuntius.h>
```
In Swift import the nuntius module
```Swift
import nuntius
```

## Usage
### Generate Curve25519 key pairs
Objc
```Objc
EncryptionService *encryptionService = [EncryptionService new];
Curve25519KeyPair *keyPair = [encryptionService generateKeyPair];
NSLog(@"Public Key: %@", keyPair.publicKey);
NSLog(@"Private Key: %@", keyPair.privateKey);
```
Swift
```Swift
let encryptionService = EncryptionService()
let keyPair = encryptionService.generateKeyPair()!
print("Public Key: \(keyPair.publicKey)")
print("Private Key: \(keyPair.privateKey)")
```
### Sign Curve25519 public key
Objc
```Objc
EncryptionService *encryptionService = [EncryptionService new];
Curve25519KeyPair *signingKeyPair = [encryptionService generateKeyPair];
Curve25519KeyPair *signedKeyPair = [encryptionService generateKeyPair];
NSData *signature = [encryptionService signData:signedKeyPair.publicKey withKeyPair:signingKeyPair];
[signedKeyPair addKeyPairSignature:signature];
NSLog(@"Signature: %@", signedKeyPair.signature);
```
Swift
```Swift
let encryptionService = EncryptionService()
let signingKeyPair = encryptionService.generateKeyPair()!
let signedKeyPair = encryptionService.generateKeyPair()!
guard let signature = encryptionService.sign(signedKeyPair.publicKey, with: signingKeyPair) else {
    return
}
signedKeyPair.addSignature(signature)
print("Signature: \(signedKeyPair.signature!)")
```
### Verify Curve25519 Signature
Objc
```Objc
EncryptionService *encryptionService = [EncryptionService new];
Curve25519KeyPair *signingKeyPair = //get signing key pair
Curve25519KeyPair *signedKeyPair = //get signed key pair
BOOL valid = [encryptionService verifySignature:signedKeyPair.signature ofRawData:signedKeyPair.publicKey withKeyPair:signingKeyPair];
if (valid) {
    NSLog(@"Valid signature");
} else {
    NSLog(@"Invalid signature");
}
```
Swift
```Swift
let encryptionService = EncryptionService()
let signingKeyPair = //get signing key pair
let signedKeyPair = //get signed key pair
let valid = encryptionService.verifySignature(signedKeyPair.signature!, ofRawData: signedKeyPair.publicKey, with: signingKeyPair)
if valid {
    print("Valid signature")
} else {
    print("Invalid signature")
}
```
### Generate shared secret from 2 Curve25519 keys (ECDH)
Objc
```Objc
EncryptionService *encryptionService = [EncryptionService new];
//Alice is the sender
Curve25519KeyPair *aliceKeyPair = [encryptionService generateKeyPair];
//Bob is the receiver
Curve25519KeyPair *bobKeyPair = [encryptionService generateKeyPair];
NSData *sharedSecretAlice = [encryptionService senderSharedKeyWithRecieverPublicKey:bobKeyPair.publicKey andSenderKeyPair:aliceKeyPair];
NSData *sharedSecretBob = [encryptionService receiverSharedKeyWithSenderPublicKey:aliceKeyPair.publicKey andReceiverKeyPair:bobKeyPair];
if ([sharedSecretAlice isEqualToData:sharedSecretBob]) {
    NSLog(@"Success!");
} else {
    NSLog(@"Error!");
}
```
Swift
```Swift
let encryptionService = EncryptionService()
//Alice is the sender
let aliceKeyPair = encryptionService.generateKeyPair()!
//Bob is the receiver
let bobKeyPair = encryptionService.generateKeyPair()!
let sharedSecretAlice = encryptionService.senderSharedKey(withRecieverPublicKey: bobKeyPair.publicKey, andSenderKeyPair: aliceKeyPair)
let sharedSecretBob = encryptionService.receiverSharedKey(withSenderPublicKey: aliceKeyPair.publicKey, andReceiverKeyPair: bobKeyPair)
guard sharedSecretAlice != nil, sharedSecretBob != nil, sharedSecretAlice == sharedSecretBob else {
    return
}
print("Success!")
```
### Derive Keys
Objc
```Objc
EncryptionService *encryptionService = [EncryptionService new];
NSData *sharedSecret = //some shared secret, for example ECDH(alice.privateKey,bob.publicKey)
/* MIN outputLength: 16, MAX outputLength: 64, Salt: key id */
NSData *key1 = [encryptionService sharedKeyKDFWithSecret:sharedSecret andSalt:1 outputLength:32];
NSData *key2 = [encryptionService sharedKeyKDFWithSecret:sharedSecret andSalt:2 outputLength:64];
NSLog(@"Derived Key1: %@", key1);
NSLog(@"Derived Key2: %@", key2);
```
Swift
```Swift
let encryptionService = EncryptionService()
let sharedSecret = //some shared secret, for example ECDH(alice.privateKey,bob.publicKey)
/* MIN outputLength: 16, MAX outputLength: 64, Salt: key id */
let key1 = encryptionService.sharedKeyKDF(withSecret: sharedSecret, andSalt: 1, outputLength: 32)
let key2 = encryptionService.sharedKeyKDF(withSecret: sharedSecret, andSalt: 2, outputLength: 64)
print("Key 1 \(key1!)")
print("Key 2 \(key2!)")
```
There is also:
```Objc
- (NSData * _Nullable)rootKeyKDFWithSecret:(NSData * _Nonnull)secret
                                   andSalt:(uint64_t)salt
                              outputLength:(NSUInteger)outputLength;
- (NSData * _Nullable)chainKeyKDFWithSecret:(NSData * _Nonnull)secret
                                    andSalt:(uint64_t)salt
                               outputLength:(NSUInteger)outputLength;
- (NSData * _Nullable)messageKeyKDFWithSecret:(NSData * _Nonnull)secret
                                      andSalt:(uint64_t)salt
                                 outputLength:(NSUInteger)outputLength;
```
All of these methods can be used for deriving keys, they are convenience methods for the Double Ratchet protocol. Internally they all use the same method but with different `ctx` (one of libsodium's `crypto_kdf_derive_from_key` parameter)
### Encrypt and Decrypt
Objc
```Objc
EncryptionService *encryptionService = [EncryptionService new];
NSData *data = [@"my-secret-data" dataUsingEncoding:NSUTF8StringEncoding];
NSData *aesKey = //Random AES key, for example key = KDF(sharedSecret, 1, 32)
NSData *hmacKey = //Random HMAC key, for example key = KDF(sharedSecret, 2, 32)
NSData *iv = //Random IV, for example key = KDF(sharedSecret, 3, 16)
NSMutableData *ratchetData = [NSMutableData new];
//Add Sender Ratchet Public Key
[ratchetData appendData:senderKeyPair.publicKey];
//Add Number of Sent Messages
const char numberOfSentMessages[1] = {0x0};
[ratchetData appendBytes:numberOfSentMessages length:sizeof(numberOfSentMessages)];
//Add Number of Sent Messages in Previous Chain
const char numberOfSentMessagesInPreviousChain[1] = {0x0};
[ratchetData appendBytes:numberOfSentMessagesInPreviousChain length:sizeof(numberOfSentMessagesInPreviousChain)];
NSError *error = nil;
NSData *ciphertext = [encryptionService aeEncryptData:data: symmetricKey:aesKey hmacKey:hmacKey iv:iv ratchetHeader:ratchetData error:&error];
if (error == nil) {
    NSLog(@"Encrypted data: %@", ciphertext);
    //Decrypting
    NSError *decryptionError = nil;
    NSData *plaintext = [encryptionService aeDecryptData:ciphertext symmetricKey:aesKey hmacKey:hmacKey iv:iv error:&decryptionError];
    if (decryptionError == nil) {
        NSLog(@"Plaintext: %@",plaintext);
    } else {
        NSLog(@"Error: %@", decryptionError);
    }
    
} else {
    NSLog(@"Error: %@", error);
}
```
Swift
```Swift
let encryptionService = EncryptionService()
let data = "my-secret-data".data(using: .utf8)!
let aesKey = //Random AES key, for example key = KDF(sharedSecret, 1, 32)
let hmacKey = //Random HMAC key, for example key = KDF(sharedSecret, 2, 32)
let iv = //Random IV, for example key = KDF(sharedSecret, 3, 16)
var ratchetData = Data()
//Add Sender Ratchet Public Key
ratchetData.append(aliceKeyPair.publicKey)
//Add Number of Sent Messages
let numberOfSentMessages: Int32 = 0x0
var beNumberOfSentMessages = numberOfSentMessages.bigEndian
ratchetData.append(UnsafeBufferPointer(start: &beNumberOfSentMessages, count: 1))
//Add Number of Sent Messages in Previous Chain
let numberOfSentMessagesInPreviousChain: Int32 = 0x0
var beNumberOfSentMessagesInPreviousChain = numberOfSentMessagesInPreviousChain.bigEndian
ratchetData.append(UnsafeBufferPointer(start: &beNumberOfSentMessagesInPreviousChain, count: 1))
do {
    let ciphertext = try encryptionService.aeEncryptData(data, symmetricKey: aesKey, hmacKey: hmacKey, iv: iv, ratchetHeader: ratchetData)
    print("Encrypted data: \(ciphertext)")
    //Decrypting
    let plaintext = try encryptionService.aeDecryptData(ciphertext, symmetricKey: aesKey, hmacKey: hmacKey, iv: iv)
    print("Plaintext: \(plaintext)")
} catch {
    print("Error \(error)")
}
```
You can read more about what the `Ratchet Header` is and why is it needed [here](https://whispersystems.org/docs/specifications/doubleratchet/). For encrypting/decrypting data outside the Double Ratchet protocol there is also:
```Objc
- (NSData * _Nullable)aeEncryptSimpleData:(NSData * _Nonnull)plaintextData
                             symmetricKey:(NSData * _Nonnull)symmetricKey
                                  hmacKey:(NSData * _Nonnull)hmacKey
                                       iv:(NSData * _Nonnull)iv
                                    error:(NSError * _Nullable * _Nullable)error;

- (NSData * _Nullable)aeDecryptSimpleData:(NSData * _Nonnull)cipherData
                             symmetricKey:(NSData * _Nonnull)symmetricKey
                                  hmacKey:(NSData * _Nonnull)hmacKey
                                       iv:(NSData * _Nonnull)iv
                                    error:(NSError * _Nullable * _Nullable)error;
```
### Double Ratchet: setup, send and receive messages
Objc
```Objc
//Alice is the sender and Bob is the receiver
DoubleRatchetService *aliceDoubleRatchet = [DoubleRatchetService new];
NSData *aliceSharedSecret = //some shared secret, for example ECDH(alice.privateKey,bob.publicKey)
[aliceDoubleRatchet setupRatchetForSendingWithSharedKey:aliceSharedSecret andDHReceiverKey:bobKeyPair];

DoubleRatchetService *bobDoubleRatchet = [DoubleRatchetService new];
NSData *bobSharedSecret = //some shared secret, for example ECDH(bob.privateKey,alice.publicKey)
[bobDoubleRatchet setupRatchetForReceivingWithSharedKey:bobSharedSecret andSignedPreKeyPair:alice.signedPreKeyPair];

//Sending messages
NSData *message = //some message
NSError *error = nil;
NSData *ciphertext = [aliceDoubleRatchet encryptData:message error:&error];
if (error == nil) {
    NSLog(@"Ready to send message: %@", ciphertext);
} else {
    NSLog(@"Error %@",error);
}

//Receiving message
NSData *plaintext = [bobDoubleRatchet decryptData:ciphertext error:&error];
if (error == nil) {
    NSLog(@"Message received: %@", plaintext);
} else {
    NSLog(@"Error %@",error);
}
```
Swift
```Swift
let aliceDoubleRatchet = DoubleRatchetService()
let aliceSharedSecret = //some shared secret, for example ECDH(alice.privateKey,bob.publicKey)
aliceDoubleRatchet.setupRatchetForSending(withSharedKey: aliceSharedSecret, andDHReceiverKey: bobKeyPair)

let bobDoubleRatchet = DoubleRatchetService()
let bobSharedSecret = //some shared secret, for example ECDH(bob.privateKey,alice.publicKey)
bobDoubleRatchet.setupRatchetForReceiving(withSharedKey: bobSharedSecret, andSignedPreKeyPair: alice.signedPreKeyPair)

//Sending messages
let message = //some message
do {
    let ciphertext = try aliceDoubleRatchet.encryptData(message)
    print("Ready to send message: \(ciphertext)")

    //Receiving message
    let plaintext = try bobDoubleRatchet.decryptData(ciphertext)
    print("Message received \(plaintext)")
} catch {
    print("Error \(error)")
}

```

## Contributions
Do you want to contribute? awesome! I'd love to see some PRs opened here.

## TODO
- [X] Add Examples/Usage
- [] Add Documentation
- [] Create wiki
- [X] Add project to Travis CI

## Disclaimer
- The Extended Triple Diffie-Hellman and Double Ratchet protocols' implementations where developed from scratch and do not share any source code with existing libraries.
- This library has no relation and is not backed nor supported by the authors of the X3DH and Double Ratchet protocols.
