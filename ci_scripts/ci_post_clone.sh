#!/bin/sh
set -e

echo "Installing xcodegen..."
brew install xcodegen

echo "Generating Xcode project..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "Done."
