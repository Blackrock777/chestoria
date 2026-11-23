# CheStoria

CheStoria is a native iPhone and Apple Watch guide to Pompeii and Naples. Explore landmarks, answer short questions and collect stickers from places you discover.

## Run locally

- Use Xcode 26 or later. Deployment targets are iOS 26 and watchOS 11.
- Open `CheStoria.xcodeproj`. Run the **CheStoria** scheme on an iPhone simulator or device. Use **CheStoriaWatch** for the Watch app.
- Press `⌘U` in the **CheStoria** scheme to run tests. Run `xcodegen generate` after changing `project.yml` or adding files.

## Enable email password recovery

Local accounts use a recovery key set up in **Profile → Account → Recovery key**. For hosted recovery, configure `SupabaseURL` and `SupabaseAnonKey` in `project.yml` with the project URL and public client key. Set the Supabase reset email template to include `{{ .Token }}` and configure [SMTP](https://supabase.com/docs/guides/auth/auth-smtp) for production. Regenerate the Xcode project after updating the settings.

## Content and credits

See [CONTENT.md](CONTENT.md) for content editing, [CREDITS.md](CREDITS.md) for attribution and the [privacy policy](https://blackrock777.github.io/chestoria/) for data handling. The repository currently has no project-wide source-code licence.
