# Contributing to MountGate

Thanks for your interest! Contributions are welcome.

## Workflow

1. **Open an issue first** for anything non-trivial, so the approach can be discussed.
2. Fork the repo and create a feature branch from `main`.
3. Make your changes; keep commits focused and messages descriptive.
4. Run the test suite: `swift test` (requires `./scripts/fetch-rclone.sh` once).
5. Open a pull request against `main`.

`main` is protected: every PR needs a passing CI run and an approving review
from the maintainer ([@zivisaiah](https://github.com/zivisaiah)) before merge.

## Development setup

macOS 14+ with Command Line Tools (no Xcode needed):

```sh
./scripts/fetch-rclone.sh   # download the rclone engine (SHA256-verified)
swift test                  # run the 17-test suite
./scripts/build-app.sh      # build dist/MountGate.app
```

## Code style

- Swift, SwiftPM only — no Xcode project files.
- Match the existing style; comments explain *constraints*, not what the code does.
- New behavior needs a test where practical (see `Tests/MountGateCoreTests`
  for end-to-end patterns using rclone's `:memory:`/`:local:` backends).

## Reporting security issues

Please do not open public issues for security vulnerabilities — email the
maintainer instead (address on the GitHub profile).
