# 2026-10-16 — The relaunch advice names a shell

The two `session-start` warnings for a session started past the shim told the
user to run `direnv allow` in the plugin root and relaunch `claude`. When direnv
was already allowed and the session came from an IDE, the desktop app or an
absolute path to `claude`, following that advice launched past the shim again
and the warning repeated. Both messages now end "relaunch claude from a shell
there": the user-level control is direnv plus a shell launch, and the messages
still never name the shim's path.
