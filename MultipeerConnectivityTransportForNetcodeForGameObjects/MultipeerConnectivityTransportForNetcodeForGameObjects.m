//
//  MultipeerConnectivityTransportForNetcodeForGameObjects.m
//  MultipeerConnectivityTransportForNetcodeForGameObjects
//
//  Created by Yuchen Zhang on 2022/9/4.
//

#import "MultipeerConnectivityTransportForNetcodeForGameObjects.h"

void (*OnClientConnected)(int) = NULL;
void (*OnConnectedToHost)(void) = NULL;
void (*OnReceivedData)(int, const void *, int) = NULL;
void (*OnClientDisconnected)(int) = NULL;
void (*OnHostDisconnected)(void) = NULL;

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

@end

@implementation MPCSession

- (instancetype)init {
    self = [super init];
    if (self) {
        self.serviceType = @"holokit-0904";
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

- (void)startAdvertising {
    self.advertiser = [[MCNearbyServiceAdvertiser alloc] initWithPeer:self.peerID discoveryInfo:nil serviceType:self.serviceType];
    self.advertiser.delegate = self;
    self.isHost = YES;
    [self.advertiser startAdvertisingPeer];
    NSLog(@"[MPC] Started advertising");
}

- (void)startBrowsing {
    self.browser = [[MCNearbyServiceBrowser alloc] initWithPeer:self.peerID serviceType:self.serviceType];
    self.browser.delegate = self;
    self.isHost = NO;
    [self.browser startBrowsingForPeers];
    NSLog(@"[MPC] Started browsing");
}

- (void)stopAdvertising {
    [self.advertiser stopAdvertisingPeer];
    self.advertiser = nil;
    NSLog(@"[MPC] Stopped advertising");
}

- (void)stopBrowsing {
    [self.browser stopBrowsingForPeers];
    self.browser = nil;
    NSLog(@"[MPC] Stopped browsing");
}

- (void)deinitialize {
    if (self.advertiser != nil) {
        [self stopAdvertising];
    }
    if (self.browser != nil) {
        [self stopBrowsing];
    }
    if (self.session != nil) {
        [self.session disconnect];
    }
    self.session = nil;
    self.peerID = nil;
    NSLog(@"[MPC] Deinitialized");
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
            break;
        }
        case MCSessionStateConnected: {
            NSLog(@"[MPC] Connected with peer %@", [peerID displayName]);
            if ([self isHost]) {
                self.connectedPeerCount++;
                [self.peerIDToTransportID setObject:[NSNumber numberWithInt:self.connectedPeerCount] forKey:peerID];
                [self.transportIDToPeerID setObject:peerID forKey:[NSNumber numberWithInt:self.connectedPeerCount]];
                if (OnClientConnected != NULL) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        OnClientConnected(self.connectedPeerCount);
                    });
                }
            } else {
                [self.peerIDToTransportID setObject:[NSNumber numberWithInt:0] forKey:peerID];
                [self.transportIDToPeerID setObject:peerID forKey:[NSNumber numberWithInt:0]];
                if (OnConnectedToHost != NULL) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        OnConnectedToHost();
                    });
                }
                [self stopBrowsing];
            }
            break;
        }
        case MCSessionStateNotConnected: {
            NSLog(@"[MPC] Disconnected with peer %@", [peerID displayName]);
            if ([self isHost]) {
                NSNumber *num = self.peerIDToTransportID[peerID];
                if (num) {
                    if (OnClientDisconnected != NULL) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            OnClientDisconnected([num intValue]);
                        });
                    }
                }
            } else {
                if (OnHostDisconnected != NULL) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        OnHostDisconnected();
                    });
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
    certificateHandler(YES);
}

- (void)session:(MCSession *)session didStartReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID withProgress:(NSProgress *)progress {}

- (void)session:(MCSession *)session didFinishReceivingResourceWithName:(NSString *)resourceName fromPeer:(MCPeerID *)peerID atURL:(NSURL *)localURL withError:(NSError *)error {}

#pragma mark - MCNearbyServiceAdvertiserDelegate

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didReceiveInvitationFromPeer:(MCPeerID *)peerID withContext:(NSData *)context invitationHandler:(void (^)(BOOL, MCSession * _Nullable))invitationHandler {
    NSLog(@"[MPC] Advertiser did receive invitation from peer %@", [peerID displayName]);
    invitationHandler(true, self.session);
}

- (void)advertiser:(MCNearbyServiceAdvertiser *)advertiser didNotStartAdvertisingPeer:(NSError *)error {
    NSLog(@"[MPC] Failed to start advertising peer");
}

#pragma mark - MCNearbyServiceBrowserDelegate

- (void)browser:(MCNearbyServiceBrowser *)browser foundPeer:(MCPeerID *)peerID withDiscoveryInfo:(NSDictionary<NSString *,NSString *> *)info {
    NSLog(@"[MPC] Browser found peer %@", [peerID displayName]);
    [browser invitePeer:peerID toSession:self.session withContext:nil timeout:30];
}

- (void)browser:(MCNearbyServiceBrowser *)browser lostPeer:(MCPeerID *)peerID {
    NSLog(@"[MPC] Browser lost peer %@", [peerID displayName]);
}

- (void)browser:(MCNearbyServiceBrowser *)browser didNotStartBrowsingForPeers:(NSError *)error {
    NSLog(@"[MPC] Failed to start browsing for peers");
}

@end

#pragma mark - Marshalling

void MPC_Initialize(void (*OnClientConnectedDelegate)(int),
                    void (*OnConnectedToHostDelegate)(void),
                    void (*OnReceivedDataDelegate)(int, const void *, int),
                    void (*OnClientDisconnectedDelegate)(int),
                    void (*OnHostDisconnectedDelegate)(void)) {
    OnClientConnected = OnClientConnectedDelegate;
    OnConnectedToHost = OnConnectedToHostDelegate;
    OnReceivedData = OnReceivedDataDelegate;
    OnClientDisconnected = OnClientDisconnectedDelegate;
    OnHostDisconnected = OnHostDisconnectedDelegate;
    [[MPCSession sharedInstance] initialize];
}

void MPC_StartAdvertising(void) {
    [[MPCSession sharedInstance] startAdvertising];
}

void MPC_StartBrowsing(void) {
    [[MPCSession sharedInstance] startBrowsing];
}

void MPC_StopAdvertising(void) {
    [[MPCSession sharedInstance] stopAdvertising];
}

void MPC_StopBrowsing(void) {
    [[MPCSession sharedInstance] stopBrowsing];
}

void MPC_Deinitialize(void) {
    [[MPCSession sharedInstance] deinitialize];
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
