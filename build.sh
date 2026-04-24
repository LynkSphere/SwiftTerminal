#!/bin/bash
xcodebuild -project SwiftTerminal.xcodeproj -scheme SwiftTerminal -destination 'generic/platform=macOS' -configuration Release archive -archivePath /tmp/SwiftTerminal.xcarchive && cp -R /tmp/SwiftTerminal.xcarchive/Products/Applications/*.app ~/Downloads/ && rm -rf /tmp/SwiftTerminal.xcarchive
