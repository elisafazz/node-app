# node-app

iOS SwiftUI app for Node, a public invite-only multi-group social app modeled on the Miracles family app.

Backend is a separate repo: `~/Dropbox/claude_work/node-backend/`. See `~/Dropbox/claude/node/PROJECT.md` for the full architecture.

## Generating the Xcode project

This repo uses [xcodegen](https://github.com/yonaskolb/XcodeGen) to define the project. The `.xcodeproj` is gitignored and regenerated locally.

```bash
brew install xcodegen
xcodegen generate
open Node.xcodeproj
```

The generator reads `project.yml` and produces `Node.xcodeproj` with:
- iOS 17+ deployment target
- Bundle ID `com.elisafazzari.node`
- Display name `Node`
- Supabase Swift SDK (https://github.com/supabase/supabase-swift) as a Swift Package dependency

## Development setup checklist

Before the app will build and run end-to-end:

1. Set `Constants.Backend.supabaseURL` and `supabaseAnonKey` in `Node/Config/Constants.swift` (after creating Supabase project)
2. Set `Constants.Cloudinary.cloudName` (after creating Cloudinary account)
3. Set `Constants.AppleSignIn.serviceID` if different from default (after configuring Apple Developer Sign in with Apple service)
4. Open `Node.xcodeproj`, set the development team in target Signing & Capabilities
5. Run `xcodebuild -scheme Node -sdk iphonesimulator build` to verify

## Repository layout

```
node-app/
  project.yml               # xcodegen config
  Node/
    NodeApp.swift           # App entry point + UIApplicationDelegate for APNs
    Resources/
      Info.plist
      Node.entitlements
    Config/
      Constants.swift       # Supabase URL, Cloudinary cloud name, etc
      AppColors.swift       # Color tokens (placeholder palette)
    Models/
      User.swift, Node.swift, Membership.swift, Story.swift, Photo.swift, Thought.swift
    Services/
      SupabaseService.swift, AuthService.swift, NodeService.swift,
      StoryService.swift, PhotoService.swift, ThoughtService.swift,
      CloudinaryService.swift, NetworkMonitor.swift, PushService.swift,
      ReportService.swift, BlockService.swift
    Views/
      RootView.swift
      Auth/LoginView.swift
      Nodes/MyNodesView.swift, CreateNodeView.swift, JoinNodeView.swift, NodeRootView.swift
      Stories/StoriesView.swift           # stub; full port from Miracles in Phase 4
      Photos/GalleryView.swift            # stub; full port from Miracles in Phase 5
      Thoughts/ThoughtsView.swift         # stub; full port from Miracles in Phase 6
      Settings/NodeSettingsView.swift, GlobalSettingsView.swift
    Assets.xcassets/
```

## Stub views

The following views are stubs scaffolded in Phase 0; full implementations port from Miracles in Phases 4-6:

- `StoriesView.swift` + `StoryComposeView.swift` -- port from `~/Dropbox/claude_work/miracles-app/Sunzzari/Views/Stories/` (Phase 4)
- `GalleryView.swift` -- port from Miracles `Views/Photos/` (Phase 5)
- `ThoughtsView.swift` -- port from Miracles `Views/Thoughts/` (Phase 6)

## SourceKit warnings note

You may see "Cannot find Constants/AuthService/etc in scope" warnings if you open individual `.swift` files in your editor before generating the Xcode project. These are SourceKit limitations from missing project context and resolve as soon as `xcodegen generate` runs.

## Deploy

iOS, deploys to TestFlight via Xcode Cloud (same pattern as Sunzzari + Miracles). Setup happens in App Store Connect after the app record is created.
