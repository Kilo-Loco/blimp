#!/bin/bash

set -eu

executable=$1

target=.build/container/$executable
rm -rf "$target"
mkdir -p "$target"
cp ".build/release/$executable" "$target/"
cp -Pv /usr/lib/swift/linux/lib*so* "$target"
cd "$target"
ln -s "$executable" "bootstrap"
pwd
zip --symlinks container.zip *
