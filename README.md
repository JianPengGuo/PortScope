# PortScope

[English](README.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md)

A small native macOS menu bar app for seeing which process is listening on each TCP port.

## Current scope

- Lists TCP listeners using the macOS `lsof` utility.
- Refreshes every four seconds and supports searching by process, port, or PID.
- Shows each listener process's physical memory footprint and recent CPU usage, sorted by memory then CPU from highest to lowest. Values turn red at 10% of installed memory or 100% of one CPU core.
- Copies endpoints and localhost URLs from each row's context menu.
- Requests confirmation before sending `SIGTERM` to a process owned by your account.
- Re-checks the PID and endpoint just before signaling; it never runs with administrator privileges.

The first version does not include Docker controls, Kubernetes, Cloudflare, auto-kill rules, or force-kill. Those can be considered after the basic port list has been tried.

## Build and run

Requires macOS 13 or later and Xcode Command Line Tools.

```sh
swift run
```

This is currently a source project rather than a signed/notarized release. macOS may show a warning if you package and distribute a built app; do not bypass Gatekeeper for an unverified build.
