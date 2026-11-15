# Development Credentials

Precis uses different credential storage by build configuration:

- **Debug:** Feedbin and The Old Reader credentials are stored as JSON files in the app's user Application Support directory, under `Precis/DevelopmentCredentials`. The directory is restricted to the current user (`0700`) and each credential file is restricted to that user (`0600`). These files are local development convenience only; they are not encrypted and must never be committed or used for production credentials.
- **Release:** credentials continue to use macOS Keychain.

The Debug-only file store avoids repeated Keychain authorization prompts from ad-hoc signed development builds. After switching to a production build, enter or save the credentials again so the Release app stores them in Keychain. Debug and Release stores are intentionally separate; the app does not migrate credentials between them.

When preparing a production build, use a stable Apple signing identity so Keychain can recognize the app across updates. Do not change the Release credential store to the local JSON file.
