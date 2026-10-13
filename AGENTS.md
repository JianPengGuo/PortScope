# Project instructions

- After changing Swift source files or package/build configuration, build from the repository root with:
  `SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --scratch-path .build --cache-path .build/swiftpm-cache`
- This keeps build caches inside the repository. `--disable-sandbox` is needed in this Codex environment because SwiftPM's nested sandbox cannot be applied here. Revisit this command if package plugins or build scripts are added.
- Fix any build failures caused by the changes before considering the work complete. If the build cannot run, report the specific blocker.
- Documentation-only changes do not require a build.
