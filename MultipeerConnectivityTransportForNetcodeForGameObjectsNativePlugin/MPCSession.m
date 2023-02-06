#import <MultipeerConnectivity/MultipeerConnectivity.h>

// Browser callbacks
void (*OnBrowserFoundPeer)(int, const char *) = NULL;
void (*OnBrowserLostPeer)(int, const char *) = NULL;

// Advertiser callbacks
void (*OnAdvertiserReceivedConnectionRequest)(int, const char *) = NULL;
void (*OnAdvertiserApprovedConnectionRequest)(int) = NULL;

// Shared callbacks
void (*OnConnectingWithPeer)(const char *) = NULL;
void (*OnConnectedWithPeer)(int, const char *) = NULL;
void (*OnDisconnectedWithPeer)(int, const char *) = NULL;
void (*OnReceivedData)(int, const void *, int) = NULL;

typedef void (^ConnectionRequestHandler)(BOOL, MCSession * _Nullable);

@interface MPCSession : NSObject

@end

@interface MPCSession () <MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate>

// Shared properties
@property (nonatomic, strong, nullable) MCSession *mcSession;
@property (nonatomic, strong, nonnull) NSString *serviceType;
@property (nonatomic, strong, nullable) MCPeerID *peerID;
@property (assign) int connectedPeerCount;
@property (nonatomic, strong, nullable) NSMutableDictionary<MCPeerID *, NSNumber *> *peerIDToTransportID;
@property (nonatomic, strong, nullable) NSMutableDictionary<NSNumber *, MCPeerID *> *transportIDToPeerID;
@property (assign) BOOL isHost;
@property (nonatomic, strong, nullable) NSString *sessionId;
@property (nonatomic, strong ,nullable) MCPeerID *hostPeerID;

// Advertiser properties
@property (nonatomic, strong, nullable) MCNearbyServiceAdvertiser *advertiser;
@property (assign) bool autoApproveConnectionRequest;
@property (nonatomic, strong, nullable) NSMutableDictionary<NSNumber *, ConnectionRequestHandler> *pendingConnectionRequestHandlerDict;
@property (assign) int connectionRequestCount; // Use this count as the key for the dict

// Browser properties
@property (nonatomic, strong, nullable) MCNearbyServiceBrowser *browser;
@property (assign) bool autoSendConnectionRequest;
@property (nonatomic, strong, nullable) NSMutableDictionary<NSNumber *, MCPeerID *> *nearbyHostDict;
@property (assign) int nearbyHostCount; // Use this count as the key for the dict

@end

@implementation MPCSession

- (instancetype)init {
    self = [super init];
    if (self) {
        self.serviceType = @"netcode-mpc";
    }
    return self;
}

+ (id)sharedInstance {
    static dispatch_once_t onceToken = 0;
    static id _sharedObject = nil;
    dispatch_once(&onceToken, ^{
        _sharedObject = [[self alloc] init];
    });
    return _sharedObject;
}

- (void)initializeWithNickname:(NSString *)nickname {
    NSString *displayName = nickname == nil ? [[UIDevice currentDevice] name] : nickname;
    self.peerID = [[MCPeerID alloc] initWithDisplayName:displayName];
    self.mcSession = [[MCSession alloc] initWithPeer:self.peerID securityIdentity:nil encryptionPreference:MCEncryptionNone];
    self.mcSession.delegate = self;
    self.connectedPeerCount = 0;
    self.peerIDToTransportID = [[NSMutableDictionary alloc] init];
    self.transportIDToPeerID = [[NSMutableDictionary alloc] init];
    
    NSLog(@"[MPCTransportNative] Initialized");
}

- (void)startAdvertising:(NSString *)sessionId autoApproveConnectionRequest:(bool)autoApproveConnectionRequest {
    self.sessionId = sessionId;
    self.isHost = YES;
    self.autoApproveConnectionRequest = autoApproveConnectionRequest;
    self.pendingConnectionRequestHandlerDict = [[NSMutableDictionary alloc] init];
    self.connectionRequestCount = 0;
    
    if (sessionId != nil) {
        NSDictionary<NSString *, NSString *> *discoveryInfo = @{ @"SessionId" : sessionId };
        self.advertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:self.peerID discoveryInfo:discoveryInfo serviceType:self.serviceType];
    } else {
        self.advertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:self.peerID discoveryInfo:nil serviceType:self.serviceType];
    }
    self.advertiser.delegate = self;
    [self.advertiser startAdvertisingPeer];
    
    NSLog(@"[MPCTransportNative] Started advertising");
}

- (void)startBrowsing:(NSString *)sessionId autoSendConnectionRequest:(bool)autoSendConnectionRequest {
    self.sessionId = sessionId;
    self.isHost = NO;
    self.autoSendConnectionRequest = autoSendConnectionRequest;
    self.nearbyHostDict = [[NSMutableDictionary alloc] init];
    self.nearbyHostCount = 0;
    
    self.browser = [[MCNearbyServiceBrowser alloc] initWithPeer:self.peerID serviceType:self.serviceType];
    self.browser.delegate = self;
    [self.browser startBrowsingForPeers];
    
    NSLog(@"[MPCTransportNative] Started browsing");
}

- (void)stopAdvertising {
    if (self.advertiser != nil) {
        [self.advertiser stopAdvertisingPeer];
        self.advertiser = nil;
        self.pendingConnectionRequestHandlerDict = nil;
        self.connectionRequestCount = 0;
        NSLog(@"[MPCTransportNative] Stopped advertising");
    }
}

- (void)stopBrowsing {
    if (self.browser != nil) {
        [self.browser stopBrowsingForPeers];
        self.browser = nil;
        self.nearbyHostDict = nil;
        self.nearbyHostCount = 0;
        NSLog(@"[MPCTransportNative] Stopped browsing");
    }
}

- (void)shutdown {
    [self stopAdvertising];
    [self stopBrowsing];
    
    if (self.mcSession != nil) {
        [self.mcSession disconnect];
    }
    self.mcSession.delegate = nil;
    self.mcSession = nil;
    self.peerID = nil;
    NSLog(@"[MPCTransportNative] Shutdown");
}

- (void)sendData:(NSData *)data toPeer:(MCPeerID *)peerID withReliability:(BOOL)reliable {
    NSArray *peers = @[peerID];
    BOOL success = [self.mcSession sendData:data toPeers:peers withMode:reliable ? MCSessionSendDataReliable : MCSessionSendDataUnreliable error:nil];
    if (!success) {
        NSLog(@"[MPCTransportNative] Failed to send data to peer %@", [peerID displayName]);
    }
}

- (void)approveConnectionRequestWithConnectionRequestKey:(int)connectionRequestKey {
    if (self.autoApproveConnectionRequest) {
        NSLog(@"[MPCTransportNative] You cannot manually approve connection request under auto mode. Set AutoApproveConnectionRequest to false to allow manual control.");
        return;
    }
    
    ConnectionRequestHandler connectionRequestHandler = self.pendingConnectionRequestHandlerDict[[NSNumber numberWithInt:connectionRequestKey]];
    if (connectionRequestHandler != nil) {
        connectionRequestHandler(true, self.mcSession);
        NSLog(@"[MPCTransportNative] Advertiser approved connection request with key %d", connectionRequestKey);
        // Remove the connection request from the dict
        NSNumber *key = [NSNumber numberWithInt:connectionRequestKey];
        if ([self.pendingConnectionRequestHandlerDict objectForKey:key]) {
            [self.pendingConnectionRequestHandlerDict removeObjectForKey:key];
        }
        // Invoke the callback
        if (OnAdvertiserApprovedConnectionRequest != NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                OnAdvertiserApprovedConnectionRequest(connectionRequestKey);
            });
        }
    } else {
        NSLog(@"[MPCTransportNative] There is no connection request in the dict with key %d", connectionRequestKey);
    }
}

- (void)sendConnectionRequestWithNearbyHostKey:(int)nearbyHostKey {
    if (self.autoSendConnectionRequest) {
        NSLog(@"[MPCTransportNative] You cannot manually send connection request under auto mode. Set AutoSendConnectionRequest to false to allow manual control.");
        return;
    }
    
    MCPeerID *peerID = self.nearbyHostDict[[NSNumber numberWithInt:nearbyHostKey]];
    if (peerID != nil) {
        [self sendConnectionRequestWithPeerID:peerID];
    } else {
        NSLog(@"[MPCTransportNative] There is no host peer in the dict with key %d", nearbyHostKey);
    }
}

- (void)sendConnectionRequestWithPeerID:(MCPeerID *)peerID {
    if (self.browser == nil) {
        NSLog(@"[MPCTransportNative] You need to have a browser to request connection.");
        return;
    }
    
    self.hostPeerID = peerID;
    [self.browser invitePeer:peerID toSession:self.mcSession withContext:nil timeout:30];
}

#pragma mark - MCSessionDelegate

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state {
    switch (state) {
        case MCSessionStateConnecting: {
            NSLog(@"[MPCTransportNative] Connecting with peer %@", [peerID displayName]);
            if (OnConnectingWithPeer != NULL) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    OnConnectingWithPeer([[peerID displayName] UTF8String]);
                });
            }
            break;
        }
        case MCSessionStateConnected: {
            NSLog(@"[MPCTransportNative] Connected with peer %@", [peerID displayName]);
            if ([self isHost]) {
                // TODO: Handle reconnected clients
                self.connectedPeerCount++;
                [self.peerIDToTransportID setObject:[NSNumber numberWithInt:self.connectedPeerCount] forKey:peerID];
                [self.transportIDToPeerID setObject:peerID forKey:[NSNumber numberWithInt:self.connectedPeerCount]];
                if (OnConnectedWithPeer != NULL) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        OnConnectedWithPeer(self.connectedPeerCount, [[peerID displayName] UTF8String]);
                    });
                }
            } else {
                if ([peerID isEqual:self.hostPeerID]) {
                    [self.peerIDToTransportID setObject:[NSNumber numberWithInt:0] forKey:peerID];
                    [self.transportIDToPeerID setObject:peerID forKey:[NSNumber numberWithInt:0]];
                    if (OnConnectedWithPeer != NULL) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            OnConnectedWithPeer(0, [[peerID displayName] UTF8String]);
                        });
                    }
                    [self stopBrowsing];
                }
            }
            break;
        }
        case MCSessionStateNotConnected: {
            NSLog(@"[MPCTransportNative] Disconnected with peer %@", [peerID displayName]);
            if (self.mcSession == nil) {
                return;
            }
            if ([self isHost]) {
                NSNumber *num = self.peerIDToTransportID[peerID];
                if (num) {
                    if (OnDisconnectedWithPeer != NULL) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            OnDisconnectedWithPeer([num intValue], [[peerID displayName] UTF8String]);
                        });
                    }
                }
            } else {
                if ([peerID isEqual:self.hostPeerID]) {
                    if (OnDisconnectedWithPeer != NULL) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            OnDisconnectedWithPeer(0, [[peerID displayName] UTF8String]);
                        });
                    }
                }
            }
            break;
        }
    }
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID {
    NSNumber *num = self.peerIDToTransportID[peerID];
    if (num) {
        int length = (int)[data length];
        if (OnReceivedData != NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                OnReceivedData([num intValue], [data bytes], length);
            });
        }
    } else {
        NSLog(@"[MPCTransportNative] Received data from unknown peer %@", [peerID displayName]);
    }
}

- (void)session:(MCSession *)session didReceiveStream:(NSInputStream *)stream withName:(NSString *)streamName fromPeer:(MCPeerID *)peerID {}

- (void)session:(MCSession *)session didReceiveCertificate:(NSArray *)certificate fromPeer:(MCPeerID *)peerID certificateHandler:(void (^)(BOOL))certificateHandler {
    if (certificateHandler != nil) {
        certificateHandler(YES);
    }
}

- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress {}

- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error {}

#pragma mark - MCNearbyServiceAdvertiserDelegate

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void (^)(BOOL, MCSession * _Nullable))invitationHandler {
    int connectionRequestKey = self.connectionRequestCount++;
    NSLog(@"[MPCTransportNative] Advertiser received connection request with key %d from peer %@", connectionRequestKey, [peerID displayName]);
    if (!self.autoApproveConnectionRequest) {
        [self.pendingConnectionRequestHandlerDict setObject:invitationHandler forKey:[NSNumber numberWithInt:connectionRequestKey]];
    }
    if (OnAdvertiserReceivedConnectionRequest != NULL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            OnAdvertiserReceivedConnectionRequest(connectionRequestKey, [[peerID displayName] UTF8String]);
        });
    }
    
    if (self.autoApproveConnectionRequest) {
        invitationHandler(true, self.mcSession);
        NSLog(@"[MPCTransportNative] Advertiser approved connection request with key %d from peer %@", connectionRequestKey, [peerID displayName]);
        if (OnAdvertiserApprovedConnectionRequest != NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                OnAdvertiserApprovedConnectionRequest(connectionRequestKey);
            });
        }
    }
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error {
    NSLog(@"[MPCTransportNative] Failed to start advertising peer");
}

#pragma mark - MCNearbyServiceBrowserDelegate

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary<NSString *,NSString *> *)info {
    NSString *sessionId = info[@"SessionId"];
    // If the session Id is compatible
    if ((self.sessionId == nil && sessionId == nil) || (self.sessionId != nil && [sessionId isEqualToString:self.sessionId])) {
        // Save the browsed peer to the dict
        int nearbyHostKey = self.nearbyHostCount++;
        [self.nearbyHostDict setObject:peerID forKey:[NSNumber numberWithInt:nearbyHostKey]];
        NSLog(@"[MPCTransportNative] Browser found peer with name %@", [peerID displayName]);
        
        if (OnBrowserFoundPeer != NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                OnBrowserFoundPeer(nearbyHostKey, [[peerID displayName] UTF8String]);
            });
        }
        
        if (self.autoSendConnectionRequest) {
            [self sendConnectionRequestWithPeerID:peerID];
        }
    }
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID {
    if (peerID == nil) {
        return;
    }
    
    NSLog(@"[MPCTransportNative] Browser lost peer with name %@", [peerID displayName]);
    for (NSNumber *nearbyHostKey in self.nearbyHostDict) {
        MCPeerID *savedPeerID = self.nearbyHostDict[nearbyHostKey];
        if ([savedPeerID isEqual:peerID]) {
            [self.nearbyHostDict removeObjectForKey:nearbyHostKey];
            if (OnBrowserLostPeer != NULL) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    OnBrowserLostPeer([nearbyHostKey intValue], [[peerID displayName] UTF8String]);
                });
            }
        }
    }
}

- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error {
    NSLog(@"[MPCTransportNative] Failed to start browsing for peers");
}

@end

#pragma mark - Marshalling

void MPC_Initialize(const char *nickname,
                    void (*onBrowserFoundPeerDelegate)(int, const char *),
                    void (*onBrowserLostPeerDelegate)(int, const char *),
                    void (*onAdvertiserReceivedConnectionRequestDelegate)(int, const char *),
                    void (*onAdvertiserApprovedConnectionRequestDelegate)(int),
                    void (*onConnectingWithPeerDelegate)(const char *),
                    void (*onConnectedWithPeerDelegate)(int, const char *),
                    void (*onDisconnectedWithPeerDelegate)(int, const char *),
                    void (*onReceivedDataDelegate)(int, const void *, int)) {
    OnBrowserFoundPeer = onBrowserFoundPeerDelegate;
    OnBrowserLostPeer = onBrowserLostPeerDelegate;
    OnAdvertiserReceivedConnectionRequest = onAdvertiserReceivedConnectionRequestDelegate;
    OnAdvertiserApprovedConnectionRequest = onAdvertiserApprovedConnectionRequestDelegate;
    OnConnectingWithPeer = onConnectingWithPeerDelegate;
    OnConnectedWithPeer = onConnectedWithPeerDelegate;
    OnDisconnectedWithPeer = onDisconnectedWithPeerDelegate;
    OnReceivedData = onReceivedDataDelegate;
    
    NSString *str = nickname == NULL ? nil : [NSString stringWithUTF8String:nickname];
    [[MPCSession sharedInstance] initializeWithNickname:str];
}

void MPC_StartAdvertising(const char *sessionId, bool autoApproveConnectionRequest) {
    NSString *str = sessionId == NULL ? nil : [NSString stringWithUTF8String:sessionId];
    [[MPCSession sharedInstance] startAdvertising:str autoApproveConnectionRequest:autoApproveConnectionRequest];
}

void MPC_StartBrowsing(const char *sessionId, bool autoSendConnectionRequest) {
    NSString *str = sessionId == NULL ? nil : [NSString stringWithUTF8String:sessionId];
    [[MPCSession sharedInstance] startBrowsing:str autoSendConnectionRequest:autoSendConnectionRequest];
}

void MPC_StopAdvertising(void) {
    [[MPCSession sharedInstance] stopAdvertising];
}

void MPC_StopBrowsing(void) {
    [[MPCSession sharedInstance] stopBrowsing];
}

void MPC_Shutdown(void) {
    [[MPCSession sharedInstance] shutdown];
}

void MPC_SendData(int transportID, unsigned char *data, int length, bool reliable) {
    MPCSession *mpcSession = [MPCSession sharedInstance];
    MCPeerID *peerID = mpcSession.transportIDToPeerID[[[NSNumber alloc] initWithInt:transportID]];
    if (peerID != nil) {
        NSData *arrData = [NSData dataWithBytes:data length:length];
        [mpcSession sendData:arrData toPeer:peerID withReliability:reliable];
    } else {
        NSLog(@"[MPCTransportNative] Failed to send data to peer with transport id %d", transportID);
    }
}

void MPC_SendConnectionRequest(int nearbyHostKey) {
    [[MPCSession sharedInstance] sendConnectionRequestWithNearbyHostKey:nearbyHostKey];
}

void MPC_ApproveConnectionRequest(int connectionRequestKey) {
    [[MPCSession sharedInstance] approveConnectionRequestWithConnectionRequestKey:connectionRequestKey];
}
