# nip

Minimal desktop utility set that shows:

- Public IP
- Local IP
- Tailscale detection
- Traceroute to the current public IP

Windows portable build included:

- `dist/nip.exe`

Linux portable build included:

- `dist/nip-linux`

macOS/Linux CLI included:

- `cli/nip`

## Files

- `Nip.MacApp/main.swift` - macOS app source
- `Nip.MacApp/Info.plist` - macOS bundle metadata
- `Nip.MacApp/IconGenerator.swift` - generates the app icon
- `Nip.Desktop/` - Avalonia desktop app source
- `cli/nip` - portable Bash CLI for macOS/Linux
- `dist/nip.exe` - portable Windows executable
- `dist/nip-linux` - portable Linux executable

## Build

Apple Silicon:

```bash
swiftc Nip.MacApp/main.swift -o /tmp/nip.app/Contents/MacOS/nip -framework AppKit -framework Foundation
```

Intel:

```bash
swiftc -target x86_64-apple-macos13.0 Nip.MacApp/main.swift -o /tmp/nip-x86_64 -framework AppKit -framework Foundation
```

Icon:

```bash
swiftc Nip.MacApp/IconGenerator.swift -o /tmp/IconGenerator -framework AppKit -framework Foundation
/tmp/IconGenerator /tmp/AppIcon.iconset Nip.MacApp/AppIcon.icns
```

Windows portable `.exe`:

```bash
export DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec
export PATH=$DOTNET_ROOT:$PATH
dotnet publish Nip.Desktop/Nip.Desktop.csproj -c Release -r win-x64 --self-contained true /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true /p:PublishTrimmed=true /p:TrimMode=partial /p:DebugType=None /p:DebugSymbols=false
cp Nip.Desktop/bin/Release/net10.0/win-x64/publish/nip.exe dist/nip.exe
```

Linux portable binary:

```bash
export DOTNET_ROOT=/opt/homebrew/opt/dotnet/libexec
export PATH=$DOTNET_ROOT:$PATH
dotnet publish Nip.Desktop/Nip.Desktop.csproj -c Release -r linux-x64 --self-contained true /p:PublishSingleFile=true /p:IncludeNativeLibrariesForSelfExtract=true /p:PublishTrimmed=true /p:TrimMode=partial /p:DebugType=None /p:DebugSymbols=false
cp Nip.Desktop/bin/Release/net10.0/linux-x64/publish/nip dist/nip-linux
```

macOS/Linux CLI:

```bash
./cli/nip
./cli/nip --no-trace
./cli/nip --json
```

## Notes

- The app uses `https://api.ipify.org` for the public IP lookup.
- Tailscale detection prefers the `tailscale` CLI when present and falls back to interface scanning.
- Traceroute uses the native command for each OS.
- The CLI runs on macOS and Linux without a build step.
- The committed Windows `.exe` is the trimmed portable build to keep size down.

## License

MIT
