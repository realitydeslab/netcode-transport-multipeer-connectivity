# Multipeer Connectivity Transport for Netcode for GameObjects

## Overview

This package implements the Transport layer of Netcode for GameObjects using Apple Multipeer Connectivity, enabling peer-to-peer communication between nearby Apple devices (macOS, visionOS, iOS). Multipeer Connectivity facilitates real-time communication and data exchange, supporting activities like multiplayer gaming, collaborative work, and data sharing, even without WiFi or cellular networks. It powers technologies like AirDrop, allowing fast large file transfers. For more details, refer to Apple's official documentation of [Multipeer Connectivity](https://developer.apple.com/documentation/multipeerconnectivity).

The Multipeer Connectivity Transport for Netcode for GameObjects extends this capability to Unity-based projects, enabling developers to integrate cross-platform networking features into their games and applications. This allows peer-to-peer local network communication between iOS, visionOS, macOS devices, and within the Unity Editor on Mac. For a demonstration on how to use this transport, please check out our [sample project](https://github.com/realitydeslab/netcode-transport-multipeer-connectivity-sample).

We also contribute this early version of this package to Unity Multiplayer Community repo. 
See https://github.com/Unity-Technologies/multiplayer-community-contributions/tree/main/Transports/com.community.netcode.transport.multipeer-connectivity

## System Requirements

This package has been tested and verified for peer-to-peer communication using MultipeerConnectivity across the following platforms:
- iOS 17.0+
- visionOS 1.0+
- macOS 14.0+
- Unity Editor 2022.3 LTS (macOS)

Note: The later versions may work but are not tested.

## How To Install

This package uses the scoped registry feature to resolve package dependencies. Open the Package Manager page in the Project Settings window and add the following entry to the Scoped Registries list:

* Name: `Reality Design Lab`
* URL: `https://registry.npmjs.com`
* Scope: `org.realitydeslab`

Now you can Install a package from a registry by name:

```org.realitydeslab.netcode.transport.multipeer-connectivity```

## Concepts Before Using The Transport

### Host-Client Architecture vs Peer-To-Peer Architecture

Before using this transport, it is important to know that Netcode for GameObjects uses a host-client network architecture while Multipeer Connectivity uses a peer-to-peer architecture.

In a host-client network, one device hosts the network and other devices join the network as clients. The host can directly communicate with all connected clients but a client can only directly communicate with the host. For two connected client, the messages they send to each other must be relayed by the host.

In a peer-to-peer network, there is no host device and any two devices are connected directly as peers. Therefore, any two peers can directly send messages to each other.

In this transport, we wrapped Multipeer Connectivity in a host-client manner to fit the architecture of Netcode for GameObjects.

### Advertising and Browsing

Before nearby devices can establish network connection, Multipeer Connectivity requires a discovery phase where nearby devices first find each other. This makes Multipeer Connectivity transport different from other Netcode transports.

In Multipeer Connectivity, an advertiser is a device which advertises itself and a browser is a device which browses nearby advertising peers. Therefore, in discovery phase, the host device should be an advertiser and all other devices should be browsers. In the following sections, we will use host and advertiser, client and browser interchangeably.

When a host starts the network, it starts to advertise itself so that nearby browsers can find it. When a browser finds a nearby host (an advertiser), it sends a connection request to the host. If the host approves the connection request, the sender of the connection request will be connected to the network as a client. When a client successfully connects to the network, it should stop browsing.

## Transport Configurations

Before start as either host or client, you can set the properties of the transport to adjust its behaviour to meet your needs. Under the default configuration, nearby host and clients will automatically connected.

<img width="363" alt="image" src="https://user-images.githubusercontent.com/44870300/217411500-35190153-683c-46a0-be16-34be3472f341.png">

Property `SessionId` is a string to make your Multipeer Connectivity session unique. Only browsers with the same `SessionId` as the advertiser can connect to the network. When there are multiple applications using Multipeer Connectivity in the surrounding area, this property ensures devices only connected to other devices running the same application.

Property `Nickname` is the name of your device shown in the discovery phase.

### Host Configurations

When property `AutoAdvertise` is set to true, the device will automatically advertise right after starting as host. Otherwise, you will need to start advertising manually.

```
// We make the transport a singleton so you can easily reference it
MultipeerConnectivityTransport.Instance.StartAdvertising();
```

When you do not want new clients to join the network, you can stop advertising so that nearby browers can no longer find you anymore.

```
MultipeerConnectivityTransport.Instance.StopAdvertising();
```

When property `AutoApproveConnectionRequest` is set to true, it will automatically approve any incoming connection request when it receives one. Otherwise, you will need to manually approve all connection requests which you want to approve.

```
private void Start()
{
    // Event invoked when the advertiser receives a new connection request
    MultipeerConnectivityTransport.Instance.OnAdvertiserReceivedConnectionRequest += OnAdvertiserReceivedConnectionRequest;
}

private void OnAdvertiserReceivedConnectionRequest(int connectionRequestKey, string senderName) 
{
    if (decide whether we want to approve this connection request) 
    {
        // We approve the connection request with the given key
        MultipeerConnectivityTransport.Instance.ApproveConnectionRequest(connectionRequestKey);
    }
}
```

### Client Configurations

When property `AutoBrowse` is set to true, the device will automatically browse nearby hosts right after starting as client. Otherwise, you will need to start browsing manually.

```
MultipeerConnectivityTransport.Instance.StartBrowsing();

// You can also stop browsing manually
MultipeerConnectivityTransport.Instance.StopBrowsing();
```

When property `AutoSendConnectionRequest` is set to true, the browser will automatically send connection request to the first nearby host it finds. Otherwise, you will need to manually send connection request to the nearby host with which you want to connect.

```
private void Start()
{
    // Event invoked when the browser finds a nearby host device
    MultipeerConnectivityTransport.Instance.OnBrowserFoundPeer += OnBrowserFoundPeer;
}

private void OnBrowserFoundPeer(int nearbyHostKey, string nearbyHostName)
{
    if (device whether we want to send connection request to this host)
    {
        MultipeerConnectivityTransport.Instance.SendConnectionRequest(nearbyHostKey);
    }
}
```

## iOS Permissions

When you build the project onto your iOS devices for the first time, both host and client devices will trigger the Local Network Permission. You must allow this permission to let your devices connect. Furthermore, the browser device will trigger another Wireless Data Permission. You need to also allow this permission as well.

## Debug Your Project in Unity Editor

Please notice that Multipeer Connectivity Transport can run on an iOS, visionOS, macOS device. It cannot run on your Mac. Therefore, when you want to debug your project in Unity Editor, we recommand you temporarily switch to use Unity Transport.


## How to compile native plugins 

To build the native plugins for this transport from source code, follow these steps:

1. Ensure you have Xcode and the necessary iOS development tools installed on your Mac.
1. Open a terminal and navigate to the root directory of this project.
1. Run the following commands:
    ```
    cd Source~
    ./build.sh
    ```
    This script will compile the native iOS, macOS, visionOS plugin and place the resulting `.a` files in the appropriate directories within the Unity project structure.
1. After running the build script, the updated plugin files should be ready for use in your Unity project.

Note: You'll need to rebuild the plugin if you make any changes to the native code or want to target a different iOS architecture.

## Author and License 

This project is authored by [Reality Design Lab](https://reality.design) and is licensed under the [MIT License](https://opensource.org/license/mit).
