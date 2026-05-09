# bobo

**bobo** is a manga reader plugin for [KOReader](https://github.com/koreader/koreader). It adds a full manga library browser, source management, and seamless chapter reading — all inside KOReader's native UI.

## Features

- Browse and search manga from [Aidoku](https://github.com/Aidoku)-compatible sources
- Library with reading progress, chapter tracking, and last-read timestamps
- User profiles — each profile has its own library and reading history (great for shared devices)
- Offline reading — downloaded chapters are stored as `.cbz` files and available without a connection
- In-app updates — bobo can download and install new versions of itself
- Screen rotation carried over between chapters

## Installation

### Kobo

1. Download `bobo-kobo.zip` from the [latest release](https://github.com/evanspn/bobo-koreader/releases/latest).
2. Extract the zip — you'll get a `bobo.koplugin` folder.
3. Copy `bobo.koplugin` to your Kobo's KOReader plugins directory:
   ```
   /mnt/onboard/.adds/koreader/plugins/bobo.koplugin
   ```
4. Restart KOReader.
5. Tap the menu bar at the top of the screen → the **bobo** icon will appear in the tools.

> **Note:** If you already have the `rakuyomi.koplugin` installed, both plugins can coexist — bobo uses its own separate plugin namespace and environment variables.

### Desktop (Linux)

1. Download `bobo-desktop.zip` from the [latest release](https://github.com/evanspn/bobo-koreader/releases/latest).
2. Extract and copy `bobo.koplugin` to your KOReader plugins directory, typically:
   ```
   ~/.config/koreader/plugins/bobo.koplugin
   ```
3. Restart KOReader.

## Getting started

1. Open bobo from the KOReader toolbar.
2. Tap the menu button (top-left) and choose **Manage Sources**.
3. Add a source list URL, then install sources from it.
4. Search for manga and add titles to your library.

## Updates

bobo can update itself in-app. When a new release is published to this repository, you'll see an update prompt inside the plugin. Updates download and install automatically without needing to manually copy files again.

## User profiles

Multiple users sharing a device can each have their own profile with a completely separate library and reading history. Open **Settings → Profiles → Manage Profiles** to create and switch between profiles.

## Building from source

See [CLAUDE.md](CLAUDE.md) for the development setup and build commands.
