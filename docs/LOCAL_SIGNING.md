# Local Signing

`LectureCaption` needs a stable code-signing requirement for macOS to retain Screen & System Audio Recording authorization between local rebuilds. Ad-hoc signing is not sufficient because its designated requirement is only the build-specific code hash.

Before the first local run, initialize the per-machine development identity:

```zsh
./Scripts/setup-local-signing.sh
```

The script creates a self-signed code-signing certificate named `LectureCaption Stable Local Signing` in the current user's login keychain. Its private key never enters the repository. Re-running the script signs a temporary probe to verify the private key is usable and does not create a second identity.

Xcode Debug and Release configurations use this identity. CI explicitly overrides it with ad-hoc signing because it does not need to retain TCC authorization.

After installing the identity, build with Command-R and authorize `LectureCaption` once in System Settings > Privacy & Security > Screen & System Audio Recording. A normal source rebuild then retains that authorization.
