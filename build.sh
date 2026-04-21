#!/bin/bash

APP_NAME="VMMenuBar"
BUNDLE_ID="com.vmmonitor.menubar"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

echo "Building $APP_NAME..."

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

swiftc \
    VMInfo.swift \
    VMDetector.swift \
    VMScanner.swift \
    StatsProvider.swift \
    AppDelegate.swift \
    main.swift \
    -o "$APP_DIR/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -target arm64-apple-macos13.0

if [ $? -ne 0 ]; then
    echo "Error: Compilation failed"
    exit 1
fi

cp Info.plist "$APP_DIR/Contents/Info.plist"

echo "Build complete! App created at: $APP_DIR"
echo ""
echo "To run the app:"
echo "  open $APP_DIR"
echo ""
echo "To install the app:"
echo "  cp -r $APP_DIR /Applications/"
