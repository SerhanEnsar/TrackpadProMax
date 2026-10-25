# Security Policy

TrackpadProMax runs with Accessibility permission and can execute the AppleScripts and Shortcuts the user configures, so we take security reports seriously.

## Reporting a vulnerability
Please **do not open a public issue**. Report privately via [GitHub Security Advisories](https://github.com/SerhanEnsar/TrackpadProMax/security/advisories/new). You'll get a response within 7 days.

## Scope
- The app makes no network connections and collects no data.
- Configuration lives in `~/Library/Application Support/TrackpadProMax/config.json`. Treat shared configuration files like scripts, because they can contain AppleScript.

## Supported versions
Only the latest release receives fixes.
