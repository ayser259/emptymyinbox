# Project Jade Manual Setup Checklist

These steps must be done outside the codebase after the rename. The app UX name is `Jade`; code, targets, package, and workspace names use `ProjectJade`.

## 1. Apple Developer Portal

1. Sign in to Apple Developer.
2. Create or update these App IDs:
   - `aysersHobbies.ProjectJade`
   - `aysersHobbies.ProjectJadeTests`
   - `aysersHobbies.ProjectJadeUITests`
   - `aysersHobbies.ProjectJadeMac`
   - `aysersHobbies.ProjectJadeMacTests`
   - `aysersHobbies.ProjectJadeMacUITests`
   - `aysersHobbies.ProjectJadeDesktop`
   - `aysersHobbies.ProjectJadeDesktopTests`
   - `aysersHobbies.ProjectJadeDesktopUITests`
3. Enable the same capabilities the old app used:
   - macOS App Sandbox
   - Keychain access for `aysersHobbies.ProjectJadeMac`
   - Network client access for the macOS app
   - User-selected file read/write access for the macOS app
4. If you later enable CloudKit, create the container `iCloud.aysersHobbies.ProjectJade` and attach it to the app IDs.
5. Regenerate development provisioning profiles for iOS and macOS if automatic signing does not do it for you.
6. Download or let Xcode refresh the new profiles.

## 2. App Store Connect

1. If this will ship as a new app identity, create new app records for the new bundle IDs.
2. Set the app display name to `Jade`.
3. Recreate TestFlight groups, internal testers, external testers, screenshots, privacy declarations, and app metadata as needed.
4. If you are replacing an old pre-launch app, archive or delete references to the old app record so testers do not install the wrong build.

## 3. Google Cloud OAuth

1. Open the Google Cloud project that owns the current OAuth client.
2. For iOS, create or update an OAuth client with bundle ID `aysersHobbies.ProjectJade`.
3. For macOS, create or update an OAuth client with bundle ID `aysersHobbies.ProjectJadeMac`.
4. Confirm the custom URL scheme is registered as `projectjade`.
5. Keep the reversed Google client URL scheme currently in the plists unless you create a new Google OAuth client:
   - `com.googleusercontent.apps.832722404678-blbtmrqva1r1phkcrbcd2h75u553mt2b`
6. If Google gives you a new client ID, update both:
   - `iOS/ProjectJade/Info.plist`
   - `Mac/ProjectJadeMac/Info.plist`
7. Test Google Sign-In on device/simulator after the Apple bundle IDs and Google OAuth clients match.

## 4. Local Xcode Reset

1. Close Xcode.
2. Open `ProjectJade.xcworkspace`, not the old workspace path.
3. If Xcode still shows old schemes, remove stale user schemes from Xcode's scheme manager and allow Xcode to recreate schemes for:
   - `ProjectJade`
   - `ProjectJadeMac`
   - `ProjectJadeShared`
4. Reset package resolution if Xcode complains about the local package:
   - File > Packages > Reset Package Caches
   - File > Packages > Resolve Package Versions
5. Clean build folder:
   - Product > Clean Build Folder
6. If project indexing is confused, delete Derived Data for this project from Xcode Settings > Locations > Derived Data.

## 5. Local App Data Reset

This rename intentionally does not preserve old pre-launch app data.

1. Delete old iOS simulator installs of the previous app.
2. Delete old macOS builds of the previous app from `/Applications` or the build products folder.
3. Remove old local app support data if you want a clean machine:
   - `~/Library/Application Support/emptyMyInbox`
   - `~/Library/Application Support/ProjectJade` if you want to reset the new app too
4. Remove old keychain items if testing sign-in from scratch:
   - `com.emptyMyInbox.gmail`
   - `com.emptyMyInbox.llm`
   - `com.emptymyinbox.gemini`
   - `com.emptymyinbox.claude`
5. New keychain services are:
   - `com.projectjade.gmail`
   - `com.projectjade.llm`
   - `com.projectjade.gemini`
   - `com.projectjade.claude`

## 6. Repository Rename

1. Rename the remote repository from `emptymyinbox` to `project-jade` or `projectjade`.
2. Update your local remote URL after the remote is renamed:
   - `git remote set-url origin <new-repo-url>`
3. Optionally rename the local checkout folder from `emptymyinbox` to `project-jade`.
4. Update any bookmarks, Cursor workspace entries, scripts, and external docs that point at the old repo path.

## 7. Validation Before Continuing Development

1. Search the repository for old identifiers:
   - `Empty My Inbox`
   - `EmptyMyInbox`
   - `emptyMyInbox`
   - `emptymyinbox`
2. Build the shared package.
3. Build and run the iOS app target `ProjectJade`.
4. Build and run the macOS app target `ProjectJadeMac`.
5. Sign in with Google on iOS and macOS.
6. Create a local vault and a Google Drive vault.
7. Confirm new files are written under `ProjectJade` app support paths.
8. Confirm the app display name appears as `Jade`.
