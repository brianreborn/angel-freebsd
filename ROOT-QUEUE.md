# Root job queue

The worker account is `green`. Root stays at one prompt and approves scripts. The worker never executes the queued file in place.

## Start the waiter

```sh
/BSD/sh ~green/bin/root-queue.sh
```

Leave it running. It sleeps one second, then looks for new scripts. One key, no Enter:

| Key | Action |
|---|---|
| `a` | approve and run |
| `d` | disapprove |
| `v` | show the script, then `a` or `d` |
| `s` | skip for this pass |
| `q` | quit the waiter |

Escape bytes are ignored, so a terminal that sends `^[a^[` still counts as `a`.

One-shot commands, if you do not want the loop: `list`, `next`, `run [id]`, `view id`, `cancel id`.

## Directories

| Path | Who | Mode | Role |
|---|---|---|---|
| `/var/root-queue/pending/` | root:green | `1770` sticky | Worker publishes `ID.sh` here |
| `/var/root-queue/private/` | root:wheel | `0700` | Claimed copy. The only file that is read or run |
| `/var/root-queue/done/` | root | `0700` | Ran |
| `/var/root-queue/cancelled/` | root | `0700` | Disapproved |
| `/var/root-queue/results/ID` | root:green | dir `0755`, file `0644` | `status ran\|failed\|cancelled` and `exit N` |
| `/var/root-queue/waiter.pid` | root | | PID of the running waiter |
| `/home/green/root-queue/notes/ID` | green | fifo `0644` | Optional wake for `queue-wait.sh` |
| `/home/green/root-queue/seen` | green | | Ids already announced by `queue-notice.sh` |

`pending/` is group `green` so this account can create files. Sticky bit: green can remove only its own files. After claim, the pending name is gone and green cannot change the bytes root will run.

## How a job is claimed

`claim` in `root-queue.sh`:

1. `stat` the pending file.
2. `cp` it to `private/ID.sh.copy`.
3. `stat` again. If device, inode, size, or mtime changed, retry up to five times.
4. `mv` the copy to `private/ID.sh`, `chown root:wheel`, `chmod 700`.
5. `rm` the pending name.

`view` and `run` use only that private copy. `list` prints ids and whether each is still pending or already claimed. It does not read the script body.

## Publishing a job

```sh
/BSD/sh ~green/bin/queue-add.sh 018-example <<'EOF'
# title: one line shown after claim
set -eu
echo hello
EOF
```

`queue-add.sh` writes `ID.sh.partial`, then `mv`s it to `ID.sh`. The waiter only considers `*.sh`. First line `# title:` is the label. The body is `/BSD/sh`.

Ids are the filename without `.sh`. Reusing an id that already has a result file makes a later wait return the old result.

## How the worker hears back

Do not block the agent on `queue-wait.sh` for a long time. The command tool backgrounds that after a few seconds and the result is missed.

`queue-notice.sh` is the path that wakes the session. It loops once a second on `/var/root-queue/results`. For each new id it prints one line:

- `DONE ID` when the file contains `status ran` and `exit 0`
- `FAILED ID` otherwise

Ids already printed are listed in `/home/green/root-queue/seen`.

`queue-wait.sh ID` is the blocking form. It creates `/home/green/root-queue/notes/ID` and reads one line. `record()` in the waiter writes the result file, then `queue-poke` writes `status … exit N` plus a newline into that fifo. The poke is nonblocking, so the waiter does not stall if nobody is reading. A newline is required or `read` never returns. If the result file already exists, `queue-wait.sh` prints it and exits without touching the fifo.

## Cancel

- Worker: `rm /var/root-queue/pending/ID.sh` before claim.
- Root: `d` at the prompt, or `cancel ID`. The private copy moves to `cancelled/` and the result is `status cancelled`.

## Shell

Scripts in this system start with `#!/BSD/sh`. `/BSD` is a directory of links to `/rescue`, so `/BSD/sh` is the static FreeBSD shell and is the same length as `/bin/sh`. Do not point a Linux `exec` of `bash` at `/rescue/sh`. Rescue has no `bash` applet (`bash not compiled in`). `/compat/linux/bin/bash` points at `/usr/local/bin/bash`, the ports bash. `/compat/linux/bin/sh` points at `/BSD/sh`.
