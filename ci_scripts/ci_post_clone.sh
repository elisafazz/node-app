#!/bin/sh
set -e

echo "Installing xcodegen..."
brew install xcodegen

echo "Generating Xcode project..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "Resolving Swift package dependencies..."
xcodebuild -resolvePackageDependencies \
  -project "$CI_PRIMARY_REPOSITORY_PATH/Node.xcodeproj" \
  -scheme Node

echo "Done."
