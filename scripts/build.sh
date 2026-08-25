#!/usr/bin/env bash

set -euo pipefail

ssh -F ~/.ssh/config thailand-mac \
    'cd /Users/martijnkooi/Developer/ThailandHolidayApp/app/ThailandHolidayApp && xcodebuild -project ThailandHolidayApp.xcodeproj -scheme ThailandHolidayApp -configuration Debug -destination "platform=iOS Simulator,name=iPhone 17 Pro,OS=latest" clean build'
