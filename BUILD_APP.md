# Building GraphicDocApp

This project is a plain Swift package — there is no Xcode project file.
Everything here is done from the Terminal.

## One-time setup

You need the Xcode command-line developer tools (this includes the Swift
compiler, but not the Xcode application itself). Check whether you already
have them:

```bash
swift --version
```

If that prints a version number, skip ahead. If it doesn't, install them:

```bash
xcode-select --install
```

The first time you build anything with Apple's toolchain, you may also be
asked to accept a license agreement. If `swift build` fails with a message
about not having agreed to the Xcode license, run:

```bash
sudo xcodebuild -license
```

Type your password when prompted (nothing will appear on screen as you
type — that's normal), page through the text with the space bar, and type
`agree` at the end.

## Running it while you're developing

From the project folder:

```bash
cd /Users/RalphDratman/GraphicDocApp
swift run
```

This compiles the source files in `Sources/GraphicDocApp/` and immediately
launches the result — a window should appear on screen. `swift build`
(without `run`) just compiles and reports errors, without launching
anything, which is a faster way to check that an edit didn't break the
build.

Each time you save an edit (in BBEdit or any other editor) and run
`swift run` again, it recompiles only the files that changed and relaunches.
This is a normal command-line executable, not a packaged app — it only
runs while that Terminal command is active, and there's no icon to
double-click.

## Building a real, double-clickable app

To get an actual `.app` you can double-click from Finder, move to
`/Applications`, or launch without Terminal at all, run:

```bash
cd /Users/RalphDratman/GraphicDocApp
./build_app.sh
```

This does four things, in order:

1. Compiles an optimized build with `swift build -c release` (release
   builds run faster than the debug builds `swift run` produces, at the
   cost of a slightly longer compile).
2. Creates the standard macOS app folder structure by hand: a
   `GraphicDocApp.app` folder containing `Contents/MacOS/` (where the
   actual compiled program goes) and `Contents/Info.plist` (a small text
   file describing the app's name, version, and a few settings macOS
   needs — including one that matters a lot for this app in particular,
   `NSHighResolutionCapable`, which tells the system to give the app real
   Retina-resolution pixels rather than a lower-resolution image stretched
   to fit).
3. Copies the compiled program into that structure.
4. Applies an "ad-hoc" code signature — a signature with no real identity
   behind it, just enough that macOS's Gatekeeper doesn't flag the app as
   untrusted when you open it locally.

None of this involves Xcode or its project file format (`.xcodeproj`).
A `.app` is just that folder layout; Xcode is one tool that can produce it,
not the only one.

When it finishes, you'll have `GraphicDocApp.app` sitting in the project
folder. Double-click it, or open it from Terminal with:

```bash
open GraphicDocApp.app
```

## Re-building the app after making changes

`build_app.sh` always rebuilds from current source and replaces the old
`.app`, so after editing any `.swift` file, just run it again:

```bash
./build_app.sh
```

## What's tracked in git, and what isn't

`GraphicDocApp.app` (the built app) and `.build/` (intermediate compiler
output) are both listed in `.gitignore` and are never committed — they're
regenerated from source, not source themselves. Only the `.swift` files,
`Package.swift`, `build_app.sh`, and this document are tracked.

## Known limitations of the current app bundle

- **No custom icon.** It uses a generic default icon. Adding a real one
  means creating an `.icns` file and referencing it from `Info.plist`
  (`CFBundleIconFile`) — not done yet.
- **Not notarized.** Ad-hoc signing is enough for running it on this Mac,
  but if you ever copied it to a different Mac (e.g. by AirDrop or a USB
  drive), Gatekeeper would likely refuse to open it without an extra
  right-click-and-choose-Open step, since it isn't signed with a real
  Apple Developer certificate.
