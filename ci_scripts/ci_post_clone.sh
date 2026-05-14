#!/bin/sh
set -e

# Xcode Cloud clones the repo without the generated .xcodeproj (it's gitignored).
# This script installs xcodegen and regenerates it before the build step runs.

echo "Installing xcodegen..."
brew install xcodegen

echo "Generating Xcode project..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate

echo "Project generated successfully."
