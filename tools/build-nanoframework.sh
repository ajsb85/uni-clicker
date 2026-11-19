#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage="${UNI_WINDOWS_ROOT:?Set UNI_WINDOWS_ROOT or source tools/bench-env.sh}/.uni-clicker-lab-cache/frameworks/nano-sdk-app"
out="$PWD/build/nanoframework"
mkdir -p "$stage" "$out"
cp examples/frameworks/nanoframework/{Program.cs,UniClickerHello.csproj} "$stage/"

export DOTNET_CLI_TELEMETRY_OPTOUT=1
export NUGET_PACKAGES=$(wslpath -w "$stage/packages")
export WSLENV="${WSLENV:+$WSLENV:}DOTNET_CLI_TELEMETRY_OPTOUT:NUGET_PACKAGES"
(cd "$stage" && dotnet.exe build UniClickerHello.csproj --nologo)
cp "$stage/bin/Debug/netnano1.0/"{UniClickerHello,mscorlib}.pe "$out/"
