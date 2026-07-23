# Changelog

All notable changes to SPARROW are documented in this file.

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.0.0 - 2026-07-23

### Added

- Added standalone contribution guidelines.
- Added a project changelog.

### Changed

- Replaced the legacy Jetson setup path with the Raspberry Pi 5 setup.
- Restored repository support, citation, and issue-template metadata.
- Removed committed runtime logs.
- Reverted XBee payload deduplication pending further validation.

## 0.9.0 - 2026-07-13

### Added

- Added SHA-256 deduplication for incoming XBee payload retransmissions.

## 0.8.0 - 2026-07-13

### Changed

- Updated both service containers to Python 3.12.
- Refreshed dependency pins affected by the Python upgrade.

## 0.7.0 - 2026-07-13

### Changed

- Updated the PyTorch, torchvision, and torchaudio dependency set.
- Pointed setup and updater flows at the public `microsoft/SPARROW` repository
  and removed personal access token handling.
- Renamed the default hosted service endpoint to
  `sparrowstudio.azure.com`.
- Refreshed the hardware assembly and bill-of-materials documentation.

## 0.6.0 - 2026-06-10

### Added

- Added support for receiving and uploading MP3 audio over XBee.
- Documented the automatic updater, rollback behavior, and operator controls.
