# track

The whole idea in three lines: an event stream outside, one send per event, the session hears it.

    ./track.sh

sends every song change to the newest session's inbox. Start the listener there with `/inbox`.

With a contract — the session is told what the events are before the first one lands:

    inbox contract music track.contract
    INBOX=music claude
    ./track.sh music        # from another shell

Or tell a session that is already running what the stream is: `inbox contract latest track.contract`
lands in it as `(new contract)` if it is listening, and `./track.sh` follows.

Needs `playerctl`. Any command that prints one line per event works in its place.
