/*
 The MIT License (MIT)
 Copyright © 2017 Ivan Rodriguez. All rights reserved.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software
 and associated documentation files (the "Software"), to deal in the Software without restriction,
 including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
 subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial
 portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
 LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE
 OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

#import "DoubleRatchetService.h"
#import "EncryptionService.h"
#import "Curve25519KeyPair.h"
#import "RatchetHeader.h"
#import "Constants.h"
#import "AEADInfo.h"

static NSUInteger const kSkippedMessagesLimit = 50;

static uint64_t const crypto_kdf_rootkey_salt = 0;
static uint64_t const crypto_kdf_message_salt = 0;
static uint64_t const crypto_kdf_chainkey_salt = 1;
static uint64_t const crypto_kdf_aes_salt = 1;
static uint64_t const crypto_kdf_hmac_salt = 2;
static uint64_t const crypto_kdf_iv_salt = 3;

@interface DoubleRatchetService ()

@property (nonatomic, strong) EncryptionService * _Nonnull encryptionService;

@property (nonatomic, strong) Curve25519KeyPair * _Nonnull DHSenderKey;
@property (nonatomic, strong) Curve25519KeyPair * _Nullable DHReceiverKey;
@property (nonatomic, strong) NSData * _Nonnull rootKey;
@property (nonatomic, strong) NSData * _Nullable chainKeySender;
@property (nonatomic, strong) NSData * _Nullable chainKeyReceiver;
@property (nonatomic, strong) NSMutableDictionary <NSObject *, NSData *> * _Nonnull skippedMessagesKeys;
@property (nonatomic, assign) NSUInteger numberOfSentMessages;
@property (nonatomic, assign) NSUInteger numberOfReceivedMessages;
@property (nonatomic, assign) NSUInteger numberOfPreviousChainSentMessages;

@end

@implementation DoubleRatchetService

#pragma mark - Override

- (instancetype)init {
    if (self = [super init]) {
        _encryptionService = [EncryptionService new];
    }
    return self;
}

#pragma mark - Sending Setup

- (void)setupRatchetForSendingWithSharedKey:(NSData * _Nonnull)sharedKey
                           andDHReceiverKey:(Curve25519KeyPair * _Nonnull)DHReceiverKey
                         doubleRatchetState:(NSDictionary<NSString *, NSString *> * _Nullable)doubleRatchetState {
    self.DHSenderKey = [self.encryptionService generateKeyPair];
    self.DHReceiverKey = DHReceiverKey;

    NSData *ratchetDH = [self.encryptionService senderSharedKeyWithRecieverPublicKey:self.DHReceiverKey.publicKey
                                                                    andSenderKeyPair:self.DHSenderKey];
    NSData *rootKeyKDFOutput = [self.encryptionService rootKeyKDFWithSecret:ratchetDH
                                                                    andSalt:crypto_kdf_rootkey_salt
                                                               outputLength:64];
    NSRange rootKeyRange = NSMakeRange(0, 32);
    self.rootKey = [rootKeyKDFOutput subdataWithRange:rootKeyRange];

    NSRange chainKeySenderRange = NSMakeRange(32, 32);
    self.chainKeySender = [rootKeyKDFOutput subdataWithRange:chainKeySenderRange];

    //Parse Double Ratchet State
    self.chainKeyReceiver = [self chainKeyReceiverFromDoubleRatchetState:doubleRatchetState];

    self.skippedMessagesKeys = [self skippedMessagesKeysFromDoubleRatchetState:doubleRatchetState];

    self.numberOfSentMessages = [self numberOfSentMessagesFromDoubleRatchetState:doubleRatchetState];
    self.numberOfReceivedMessages = [self numberOfReceivedMessagesFromDoubleRatchetState:doubleRatchetState];
    self.numberOfPreviousChainSentMessages = [self numberOfPreviousChainSentMessagesFromDoubleRatchetState:doubleRatchetState];
}

- (void)setupRatchetForSendingWithSharedKey:(NSData * _Nonnull)sharedKey
                           andDHReceiverKey:(Curve25519KeyPair * _Nonnull)DHReceiverKey {

    [self setupRatchetForSendingWithSharedKey:sharedKey
                             andDHReceiverKey:DHReceiverKey
                           doubleRatchetState:nil];
}

#pragma mark - Receiving Setup

- (void)setupRatchetForReceivingWithSharedKey:(NSData * _Nonnull)sharedKey
                          andSignedPreKeyPair:(Curve25519KeyPair * _Nonnull)signedPreKeyPair
                           doubleRatchetState:(NSDictionary * _Nullable)doubleRatchetState {

    Curve25519KeyPair *ratchetKey = [self DHSenderKeyFromDoubleRatchetState:doubleRatchetState];
    self.DHSenderKey = ratchetKey != nil ? ratchetKey : signedPreKeyPair;
    self.rootKey = sharedKey;

    //Parse Double Ratchet State

    self.DHReceiverKey = [self DHReceiverKeyFromDoubleRatchetState:doubleRatchetState];
    self.chainKeySender = [self chainKeySenderFromDoubleRatchetState:doubleRatchetState];
    self.chainKeyReceiver = [self chainKeyReceiverFromDoubleRatchetState:doubleRatchetState];

    self.skippedMessagesKeys = [self skippedMessagesKeysFromDoubleRatchetState:doubleRatchetState];

    self.numberOfSentMessages = [self numberOfSentMessagesFromDoubleRatchetState:doubleRatchetState];
    self.numberOfReceivedMessages = [self numberOfReceivedMessagesFromDoubleRatchetState:doubleRatchetState];
    self.numberOfPreviousChainSentMessages = [self numberOfPreviousChainSentMessagesFromDoubleRatchetState:doubleRatchetState];
}

- (void)setupRatchetForReceivingWithSharedKey:(NSData * _Nonnull)sharedKey
                          andSignedPreKeyPair:(Curve25519KeyPair * _Nonnull)signedPreKeyPair {

    [self setupRatchetForReceivingWithSharedKey:sharedKey
                            andSignedPreKeyPair:signedPreKeyPair
                             doubleRatchetState:nil];
}

#pragma mark - Encrypt

- (NSData * _Nullable)encryptData:(NSData * _Nonnull)plaintext
                            error:(NSError * _Nullable * _Nullable)error {
    //Generate Message Key
    NSData *messageKey = [self.encryptionService chainKeyKDFWithSecret:self.chainKeySender
                                                               andSalt:crypto_kdf_message_salt
                                                          outputLength:32];

    //Symmetric Ratchet of Sender Chain Key
    self.chainKeySender = [self.encryptionService chainKeyKDFWithSecret:self.chainKeySender
                                                                andSalt:crypto_kdf_chainkey_salt
                                                           outputLength:32];

    NSMutableData *ratchetHeaderData = [NSMutableData new];

    //Add Sender Ratchet Public Key
    [ratchetHeaderData appendData:self.DHSenderKey.publicKey];

    //Add Number of Sent Messages
    const char numberOfSentMessages[1] = {self.numberOfSentMessages};
    [ratchetHeaderData appendBytes:numberOfSentMessages length:sizeof(numberOfSentMessages)];

    //Add Number of Sent Messages in Previous Chain
    const char previousChainSentMessages[1] = {self.numberOfSentMessages};
    [ratchetHeaderData appendBytes:previousChainSentMessages length:sizeof(previousChainSentMessages)];

    AEADInfo *aeadInfo = [self aeadInfoFromMessageKey:messageKey];

    self.numberOfSentMessages = self.numberOfSentMessages + 1;

    return [self.encryptionService aeEncryptData:plaintext
                                    symmetricKey:aeadInfo.aesKey
                                         hmacKey:aeadInfo.hmacKey
                                              iv:aeadInfo.iv
                                   ratchetHeader:[ratchetHeaderData copy]
                                           error:error];
}

#pragma mark - Decrypt

- (NSData * _Nullable)decryptData:(NSData * _Nonnull)cipherdata
                            error:(NSError * _Nullable * _Nullable)error {

    RatchetHeader *ratchetHeader = [self.encryptionService ratchetHeaderFromCipherData:cipherdata];
    NSData *skippedMessageKey = self.skippedMessagesKeys[[ratchetHeader dictionaryKey]];
    if (skippedMessageKey != nil) {
        AEADInfo *aeadInfo = [self aeadInfoFromMessageKey:skippedMessageKey];
        [self.skippedMessagesKeys removeObjectForKey:[ratchetHeader dictionaryKey]];

        return [self.encryptionService aeDecryptData:cipherdata
                                        symmetricKey:aeadInfo.aesKey
                                             hmacKey:aeadInfo.hmacKey
                                                  iv:aeadInfo.iv
                                               error:error];
    }

    if (![ratchetHeader.ratchetKey isEqual:self.DHReceiverKey]) {
        NSError *err = [self addSkippedMessages:ratchetHeader.numberOfPreviousChainSentMessages];
        if (err != nil) {
            *error = err;
            return nil;
        }

        [self performDHRatchet:ratchetHeader.ratchetKey];
    }

    //Skip Messages if Necessary
    [self addSkippedMessages:ratchetHeader.numberOfSentMessages];

    //Generate Message Key
    NSData *messageKey = [self.encryptionService chainKeyKDFWithSecret:self.chainKeyReceiver
                                                               andSalt:crypto_kdf_message_salt
                                                          outputLength:32];

    //Symmetric Ratchet of Receiver Chain Key
    self.chainKeyReceiver = [self.encryptionService chainKeyKDFWithSecret:self.chainKeyReceiver
                                                                  andSalt:crypto_kdf_chainkey_salt
                                                             outputLength:32];
    self.numberOfReceivedMessages = self.numberOfReceivedMessages + 1;

    AEADInfo *aeadInfo = [self aeadInfoFromMessageKey:messageKey];

    return [self.encryptionService aeDecryptData:cipherdata
                                    symmetricKey:aeadInfo.aesKey
                                         hmacKey:aeadInfo.hmacKey
                                              iv:aeadInfo.iv
                                           error:error];
}

#pragma mark - Ratchet

- (NSError * _Nullable)addSkippedMessages:(NSUInteger)lastMessage {
    if (self.numberOfReceivedMessages + kSkippedMessagesLimit < lastMessage) {
        NSString *description = NSLocalizedString(@"Too many skipped messages", nil);
        NSError *error = [NSError errorWithDomain:@"com.ivrodriguez.SkippedMessagesError" code:kSkippedMessagesError_ErrorCode userInfo:@{NSLocalizedDescriptionKey: description}];
        return error;
    }

    if (self.chainKeyReceiver != nil) {
        while(self.numberOfReceivedMessages < lastMessage) {
            //Generate Message Key
            NSData *messageKey = [self.encryptionService chainKeyKDFWithSecret:self.chainKeyReceiver
                                                                       andSalt:crypto_kdf_message_salt
                                                                  outputLength:32];

            //Symmetric Ratchet of Receiver Chain Key
            self.chainKeyReceiver = [self.encryptionService chainKeyKDFWithSecret:self.chainKeyReceiver
                                                                          andSalt:crypto_kdf_chainkey_salt
                                                                     outputLength:32];
            NSString *key = [self dictionaryKeyFrom:self.DHReceiverKey.publicKey receivedMessages:self.numberOfReceivedMessages];
            self.skippedMessagesKeys[key] = messageKey;
            self.numberOfReceivedMessages = self.numberOfReceivedMessages + 1;
        }
    }

    return nil;
}

- (void)performDHRatchet:(Curve25519KeyPair * _Nonnull)ratchetKey {
    self.numberOfPreviousChainSentMessages = self.numberOfSentMessages;
    self.numberOfSentMessages = 0;
    self.numberOfReceivedMessages = 0;
    self.DHReceiverKey = ratchetKey;

    //Update Chain Key Receiver
    NSData *ratchetDHReceiver = [self.encryptionService receiverSharedKeyWithSenderPublicKey:self.DHReceiverKey.publicKey
                                                                          andReceiverKeyPair:self.DHSenderKey];
    NSData *rootKeyKDFOutputReceiver = [self.encryptionService rootKeyKDFWithSecret:ratchetDHReceiver
                                                                            andSalt:crypto_kdf_rootkey_salt
                                                                       outputLength:64];
    NSRange rootKeyRangeReceiver = NSMakeRange(0, 32);
    self.rootKey = [rootKeyKDFOutputReceiver subdataWithRange:rootKeyRangeReceiver];

    NSRange chainKeyReceiverRange = NSMakeRange(32, 32);
    self.chainKeyReceiver = [rootKeyKDFOutputReceiver subdataWithRange:chainKeyReceiverRange];

    //Generate New Ratchet Key
    self.DHSenderKey = [self.encryptionService generateKeyPair];

    //Update Chain Key Sender
    NSData *ratchetDHSender = [self.encryptionService senderSharedKeyWithRecieverPublicKey:self.DHReceiverKey.publicKey
                                                                          andSenderKeyPair:self.DHSenderKey];
    NSData *rootKeyKDFOutputSender = [self.encryptionService rootKeyKDFWithSecret:ratchetDHSender
                                                                          andSalt:crypto_kdf_rootkey_salt
                                                                     outputLength:64];
    NSRange rootKeyRangeSender = NSMakeRange(0, 32);
    self.rootKey = [rootKeyKDFOutputSender subdataWithRange:rootKeyRangeSender];

    NSRange chainKeySenderRangeSender = NSMakeRange(32, 32);
    self.chainKeySender = [rootKeyKDFOutputSender subdataWithRange:chainKeySenderRangeSender];
}

#pragma mark - State

- (NSDictionary<NSString *, NSString *> * _Nonnull)doubleRatchetState {
    NSMutableDictionary *state = [NSMutableDictionary new];

    //DHReceiverKey
    NSDictionary *serialized = [self.DHReceiverKey serialized];
    NSData *json = [NSJSONSerialization dataWithJSONObject:serialized options:0 error:nil];
    NSString *value = [json base64EncodedStringWithOptions:0];
    [state setValue:value forKey:kDHReceiverKey_Key];

    //ChainKeySender
    if (self.chainKeySender) {
        [state setValue:[self.chainKeySender base64EncodedStringWithOptions:0] forKey:kChainKeySender_Key];
    }

    //ChainKeyReceiver
    if (self.chainKeyReceiver) {
        [state setValue:[self.chainKeyReceiver base64EncodedStringWithOptions:0] forKey:kChainKeyReceiver_Key];
    }

    //SkippedMessagesKeys
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.skippedMessagesKeys];
    [state setValue:[data base64EncodedStringWithOptions:0] forKey:kSkippedMessagesKeys_Key];

    //NumberOfSentMessages
    [state setValue:[@(self.numberOfSentMessages) stringValue] forKey:kNumberOfSentMessages_Key];

    //NumberOfReceivedMessages
    [state setValue:[@(self.numberOfReceivedMessages) stringValue] forKey:kNumberOfReceivedMessages_Key];

    //NumberOfPreviousChainSentMessages
    [state setValue:[@(self.numberOfPreviousChainSentMessages) stringValue] forKey:kNumberOfPreviousChainSentMessages_Key];

    return [state copy];
}

- (Curve25519KeyPair *)DHSenderKeyFromDoubleRatchetState:(NSDictionary *)doubleRatchetState {
    NSString *string = doubleRatchetState[kDHSenderKey_Key];
    if (string == nil) {
        return nil;
    }

    NSData *data = [[NSData alloc]  initWithBase64EncodedString:string options:0];
    NSDictionary *serialized = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

    return [Curve25519KeyPair keyPairWithSerializedData:serialized];
}

- (Curve25519KeyPair *)DHReceiverKeyFromDoubleRatchetState:(NSDictionary *)doubleRatchetState {
    NSString *string = doubleRatchetState[kDHReceiverKey_Key];
    if (string == nil) {
        return nil;
    }

    NSData *data = [[NSData alloc]  initWithBase64EncodedString:string options:0];
    NSDictionary *serialized = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];

    return [Curve25519KeyPair keyPairWithSerializedData:serialized];
}

- (NSData *)chainKeySenderFromDoubleRatchetState:(NSDictionary *)doubleRatchetState {
    NSString *chainKey = doubleRatchetState[kChainKeySender_Key];
    if (chainKey == nil) {
        return nil;
    }

    return [[NSData alloc] initWithBase64EncodedString:chainKey options:0];
}

- (NSData *)chainKeyReceiverFromDoubleRatchetState:(NSDictionary *)doubleRatchetState {
    NSString *chainKey = doubleRatchetState[kChainKeyReceiver_Key];
    if (chainKey == nil) {
        return nil;
    }

    return [[NSData alloc] initWithBase64EncodedString:chainKey options:0];
}

- (NSMutableDictionary *)skippedMessagesKeysFromDoubleRatchetState:(NSDictionary *)doubleRatchetState {
    NSString *string = doubleRatchetState[kSkippedMessagesKeys_Key];
    if (string == nil) {
        return [NSMutableDictionary new];
    }

    NSData *data = [[NSData alloc] initWithBase64EncodedString:string options:0];
    if (data == nil) {
        return [NSMutableDictionary new];
    }

    NSDictionary *messages = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    return [messages mutableCopy];
}

- (NSUInteger)numberOfSentMessagesFromDoubleRatchetState:(NSDictionary *)doubleRatchetState {
    NSString *string = doubleRatchetState[kNumberOfSentMessages_Key];
    if (string == nil) {
        return 0;
    }

    return [string integerValue];
}

- (NSUInteger)numberOfReceivedMessagesFromDoubleRatchetState:(NSDictionary *)doubleRatchetState {
    NSString *string = doubleRatchetState[kNumberOfReceivedMessages_Key];
    if (string == nil) {
        return 0;
    }

    return [string integerValue];
}

- (NSUInteger)numberOfPreviousChainSentMessagesFromDoubleRatchetState:(NSDictionary *)doubleRatchetState {
    NSString *string = doubleRatchetState[kNumberOfPreviousChainSentMessages_Key];
    if (string == nil) {
        return 0;
    }

    return [string integerValue];
}

#pragma mark - Helpers

- (AEADInfo * _Nullable)aeadInfoFromMessageKey:(NSData * _Nonnull)messageKey {
    NSData *aes = [self.encryptionService chainKeyKDFWithSecret:messageKey
                                                        andSalt:crypto_kdf_aes_salt
                                                   outputLength:32];

    NSData *hmac = [self.encryptionService chainKeyKDFWithSecret:messageKey
                                                        andSalt:crypto_kdf_hmac_salt
                                                   outputLength:32];

    NSData *iv = [self.encryptionService chainKeyKDFWithSecret:messageKey
                                                        andSalt:crypto_kdf_iv_salt
                                                   outputLength:16];

    return [AEADInfo infoWithAESKey:aes HMACKey:hmac iv:iv];
}

- (NSString * _Nonnull)dictionaryKeyFrom:(NSData *)publicKey receivedMessages:(NSUInteger)messages {
    NSString *pk = [publicKey base64EncodedStringWithOptions:0];
    NSString *msgs = [@(messages) stringValue];
    
    return [NSString stringWithFormat:@"%@|%@",pk,msgs];
}

@end
