#!/bin/sh

# SPDX-FileCopyrightText: Copyright 2024 Reality Design Lab <dev@reality.design>
# SPDX-FileContributor: Botao Amber Hu <botao@reality.design>
# SPDX-License-Identifier: MIT

CFLAGS="-O3 -Wall "
CC=gcc
AR=ar

INCLUDES="-IMultipeerConnectivityTransportForNetcodeForGameObjectsNativePlugin"
SOURCES="MultipeerConnectivityTransportForNetcodeForGameObjectsNativePlugin"
LIBNAME=MultipeerConnectivityTransportForNetcodeForGameObjectsNativePlugin
LIBS="-framework MultipeerConnectivity -framework Foundation"

rm -rf *.o *.so *.a *.bundle *.dylib 
set -x

# Use "zip target" to get the target name

## MacOS 
# arm64
MAC_ROOT=`xcrun --sdk macosx --show-sdk-path`
ARCH_TARGET="-target aarch64-apple-macos"
MAC_ARGS="$ARCH_TARGET --sysroot $MAC_ROOT -isysroot $MAC_ROOT -fPIC"

$CC $CFLAGS $INCLUDES $MAC_ARGS -c $SOURCES/MPCSession.m -o MPCSession.o 

$CC $MAC_ARGS -fPIC -rdynamic -shared -o lib${LIBNAME}_arm64.dylib $LIBS MPCSession.o

## x86_64
MAC_ROOT=`xcrun --sdk macosx --show-sdk-path`
ARCH_TARGET="-target x86_64-apple-macos"
MAC_ARGS="$ARCH_TARGET --sysroot $MAC_ROOT -isysroot $MAC_ROOT -fPIC"

$CC $CFLAGS $INCLUDES $MAC_ARGS -c $SOURCES/MPCSession.m -o MPCSession.o 

$CC $MAC_ARGS -fPIC -rdynamic -shared -o lib${LIBNAME}_x86_64.dylib $LIBS MPCSession.o 

lipo -create -output ${LIBNAME}.bundle lib${LIBNAME}_arm64.dylib lib${LIBNAME}_x86_64.dylib

DST="../Runtime/Plugins/macOS"
mkdir -p $DST
rm -rf $DST/${LIBNAME}.bundle
cp -r ${LIBNAME}.bundle $DST


# iOS  
IOS_ROOT=`xcrun --sdk iphoneos --show-sdk-path`
ARCH_TARGET="-target aarch64-apple-ios"
IOS_ARGS="$ARCH_TARGET --sysroot $IOS_ROOT -isysroot $IOS_ROOT -fembed-bitcode"

$CC $CFLAGS $INCLUDES $IOS_ARGS -c $SOURCES/MPCSession.m $LIBS -o MPCSession.o 

$AR -crv lib${LIBNAME}.a MPCSession.o

DST="../Runtime/Plugins/iOS"
mkdir -p $DST
rm -rf $DST/lib${LIBNAME}.a
cp -r lib${LIBNAME}.a $DST

rm -rf *.o *.so *.a *.bundle *.dylib 

# visionOS
VISIONOS_ROOT=`xcrun --sdk xros --show-sdk-path`
ARCH_TARGET="-target aarch64-apple-visionos"
VISIONOS_ARGS="$ARCH_TARGET --sysroot $VISIONOS_ROOT -isysroot $VISIONOS_ROOT -fembed-bitcode"

$CC $CFLAGS $INCLUDES $VISIONOS_ARGS -c $SOURCES/MPCSession.m $LIBS -o MPCSession.o 

$AR -crv lib${LIBNAME}.a MPCSession.o

DST="../Runtime/Plugins/visionOS"
mkdir -p $DST
rm -rf $DST/lib${LIBNAME}.a
cp -r lib${LIBNAME}.a $DST

rm -rf *.o *.so *.a *.bundle *.dylib 

