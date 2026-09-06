# track

The whole idea in three lines: an event stream outside, one send per event, the session hears it.

    ./track.sh

sends every song change to the newest session's inbox. Start the listener there with `/inbox`.

With an intro — the session is told what the events are before the first one lands:

    cp track.intro /tmp/claude-inbox/music.intro
    INBOX=music claude
    ./track.sh music        # from another shell

Needs `playerctl`. Any command that prints one line per event works in its place.
