#import <MultipeerConnectivity/MultipeerConnectivity.h>

void (*OnBrowserFoundPeer)(const char *) = NULL;
void (*OnBrowserLostPeer)(const char *) = NULL;
void (*OnAdvertiserReceivedInvitation)(const char *) = NULL;
void (*OnConnectingWithPeer)(const char *) = NULL;
void (*OnConnectedWithPeer)(int, const char *) = NULL;
void (*OnDisconnectedWithPeer)(int, const char *) = NULL;
void (*OnReceivedData)(int, const void *, int) = NULL;

@interface MPCSession : NSObject

@end

@interface MPCSession () <MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate>

@property (nonatomic, strong, nullable) MCSession *session;
@property (nonatomic, strong, nonnull) NSString *serviceType;
@property (nonatomic, strong, nullable) MCPeerID *peerID;
@property (nonatomic, strong, nullable) MCNearbyServiceAdvertiser *advertiser;
@property (nonatomic, strong, nullable) MCNearbyServiceBrowser *browser;
@property (assign) int connectedPeerCount;
@property (nonatomic, strong, nullable) NSMutableDictionary<MCPeerID *, NSNumber *> *peerIDToTransportID;
@property (nonatomic, strong, nullable) NSMutableDictionary<NSNumber *, MCPeerID *> *transportIDToPeerID;
@property (assign) BOOL isHost;
@property (nonatomic, strong, nullable) NSString *sessionId;
@property (nonatomic, strong ,nullable) MCPeerID *hostPeerID;

@end

@implementation MPCSession

- (instancetype)init {
    self = [super init];
    if (self) {
        self.serviceType = @"unity-netcode-mpc";
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

- (void)initialize {
    self.peerID = [[MCPeerID alloc] initWithDisplayName:[[UIDevice currentDevice] name]];
    self.session = [[MCSession alloc] initWithPeer:self.peerID securityIdentity:nil encryptionPreference:MCEncryptionNone];
    self.session.delegate = self;
    self.connectedPeerCount = 0;
    self.peerIDToTransportID = [[NSMutableDictionary alloc] init];
    self.transportIDToPeerID = [[NSMutableDictionary alloc] init];
    NSLog(@"[MPC] Initialized");
}

- (void)startAdvertising:(NSString *)sessionId {
    self.sessionId = sessionId;
    if (sessionId != nil) {
        NSDictionary<NSString *, NSString *> *discoveryInfo = @{ @"SessionId" : sessionId };
        self.advertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:self.peerID discoveryInfo:discoveryInfo serviceType:self.serviceType];
    } else {
        self.advertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:self.peerID discoveryInfo:nil serviceType:self.serviceType];
    }
    self.advertiser.delegate = self;
    self.isHost = YES;
    [self.advertiser startAdvertisingPeer];
    NSLog(@"[MPC] Started advertising");
}

- (void)startBrowsing:(NSString *)sessionId {
    self.sessionId = sessionId;
    self.browser = [[MCNearbyServiceBrowser alloc] initWithPeer:self.peerID serviceType:self.serviceType];
    self.browser.delegate = self;
    self.isHost = NO;
    [self.browser startBrowsingForPeers];
    NSLog(@"[MPC] Started browsing");
}

- (void)stopAdvertising {
    if (self.advertiser != nil) {
        [self.advertiser stopAdvertisingPeer];
        self.advertiser = nil;
        NSLog(@"[MPC] Stopped advertising");
    }
}

- (void)stopBrowsing {
    if (self.browser != nil) {
        [self.browser stopBrowsingForPeers];
        self.browser = nil;
        NSLog(@"[MPC] Stopped browsing");
    }
}

- (void)shutdown {
    if (self.advertiser != nil) {
        [self stopAdvertising];
    }
    if (self.browser != nil) {
        [self stopBrowsing];
    }
    if (self.session != nil) {
        [self.session disconnect];
    }
    self.session.delegate = nil;
    self.session = nil;
    self.peerID = nil;
    NSLog(@"[MPC] Shutdown");
}

- (void)sendData:(NSData *)data toPeer:(MCPeerID *)peerID withReliability:(BOOL)reliable {
    NSArray *peers = @[peerID];
    BOOL success = [self.session sendData:data toPeers:peers withMode:reliable ? MCSessionSendDataReliable : MCSessionSendDataUnreliable error:nil];
    if (!success) {
        NSLog(@"[MPC] Failed to send data to peer %@", [peerID displayName]);
    }
}

#pragma mark - MCSessionDelegate

- (void)session:(MCSession *)session peer:(MCPeerID *)peerID didChangeState:(MCSessionState)state {
    switch (state) {
        case MCSessionStateConnecting: {
            NSLog(@"[MPC] Connecting with peer %@", [peerID displayName]);
            if (OnConnectingWithPeer != NULL) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    OnConnectingWithPeer([[peerID displayName] UTF8String]);
                });
            }
            break;
        }
        case MCSessionStateConnected: {
            NSLog(@"[MPC] Connected with peer %@", [peerID displayName]);
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
            NSLog(@"[MPC] Disconnected with peer %@", [peerID displayName]);
            if (self.session == nil) {
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
        NSLog(@"[MPC] Received data from unknown peer %@", [peerID displayName]);
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
    NSLog(@"[MPC] Advertiser did receive invitation from peer %@", [peerID displayName]);
    if (OnAdvertiserReceivedInvitation != NULL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            OnAdvertiserReceivedInvitation([[peerID displayName] UTF8String]);
        });
    }
    invitationHandler(true, self.session);
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error {
    NSLog(@"[MPC] Failed to start advertising peer");
}

#pragma mark - MCNearbyServiceBrowserDelegate

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary<NSString *,NSString *> *)info {
    NSString *sessionId = info[@"SessionId"];
    if (self.sessionId == nil && sessionId == nil) {
        NSLog(@"[MPC] Browser found peer %@", [peerID displayName]);
        if (OnBrowserFoundPeer != NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                OnBrowserFoundPeer([[peerID displayName] UTF8String]);
            });
        }
        self.hostPeerID = peerID;
        [browser invitePeer:peerID toSession:self.session withContext:nil timeout:30];
        return;
    }
    
    if ([sessionId isEqualToString:self.sessionId]) {
        NSLog(@"[MPC] Browser found peer %@ with correct session Id: %@", [peerID displayName], sessionId);
        if (OnBrowserFoundPeer != NULL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                OnBrowserFoundPeer([[peerID displayName] UTF8String]);
            });
        }
        self.hostPeerID = peerID;
        [browser invitePeer:peerID toSession:self.session withContext:nil timeout:30];
    } else {
        NSLog(@"[MPC] Browser found peer %@ with wrong session Id: %@, expecting session Id: %@", [peerID displayName], sessionId, self.sessionId);
    }
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID {
    NSLog(@"[MPC] Browser lost peer %@", [peerID displayName]);
    if (OnBrowserLostPeer != NULL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            OnBrowserLostPeer([[peerID displayName] UTF8String]);
        });
    }
}

- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error {
    NSLog(@"[MPC] Failed to start browsing for peers");
}

@end

#pragma mark - Marshalling

void MPC_Initialize(void (*OnBrowserFoundPeerDelegate)(const char *),
                    void (*OnBrowserLostPeerDelegate)(const char *),
                    void (*OnAdvertiserReceivedInvitationDelegate)(const char *),
                    void (*OnConnectingWithPeerDelegate)(const char *),
                    void (*OnConnectedWithPeerDelegate)(int, const char *),
                    void (*OnDisconnectedWithPeerDelegate)(int, const char *),
                    void (*OnReceivedDataDelegate)(int, const void *, int)) {
    OnBrowserFoundPeer = OnBrowserFoundPeerDelegate;
    OnBrowserLostPeer = OnBrowserLostPeerDelegate;
    OnAdvertiserReceivedInvitation = OnAdvertiserReceivedInvitationDelegate;
    OnConnectingWithPeer = OnConnectingWithPeerDelegate;
    OnConnectedWithPeer = OnConnectedWithPeerDelegate;
    OnDisconnectedWithPeer = OnDisconnectedWithPeerDelegate;
    OnReceivedData = OnReceivedDataDelegate;
    [[MPCSession sharedInstance] initialize];
}

void MPC_StartAdvertising(const char *sessionId) {
    NSString *str = sessionId == NULL ? nil : [NSString stringWithUTF8String:sessionId];
    [[MPCSession sharedInstance] startAdvertising: str];
}

void MPC_StartBrowsing(const char *sessionId) {
    NSString *str = sessionId == NULL ? nil : [NSString stringWithUTF8String:sessionId];
    [[MPCSession sharedInstance] startBrowsing: str];
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
    if (peerID) {
        NSData *arrData = [NSData dataWithBytes:data length:length];
        [mpcSession sendData:arrData toPeer:peerID withReliability:reliable];
    } else {
        NSLog(@"[MPC] Failed to send data to peer with transport id %d", transportID);
    }
}
