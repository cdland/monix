# The agent fleet on fw0

fw0 runs a fleet of worker microVMs in which coding agents (Claude Code,
Codex) run fully-permissioned against exactly one repository each, contained
by the host rather than by anything the guest promises. Two modules implement
it, both gated on `agentFleet.enable`:

- `modules/server/microvm-host.mod.nix` — the host side: microvm.nix runner,
  host-only bridge, squid egress proxy.
- `modules/server/agent-vm.mod.nix` — the guest side: the `agentFleet.workers`
  roster option and the `mkAgentGuest` factory that turns each entry into a
  microVM plus its `agents.slice` unit override and credential plumbing. The
  roster (and the `agentFleet.credentials` paths) are set per host, in
  `hosts/fw0/fw0.mod.nix`.
- `modules/server/agent-dispatch.mod.nix` — the task queue and dispatcher:
  drop a prompt file in the queue, get a report back (see Dispatch below).

## Containment model

Containment is structural, not rule-based:

- **No route out.** Guests sit on the host-only bridge `br-agents`
  (`10.100.0.1/24`) with a static address, **no default gateway, and no
  DNS**. No uplink is enslaved to the bridge, and no IP forwarding is enabled
  anywhere, so there is nothing to route to even if a guest reconfigures
  itself.
- **One reachable host port.** The firewall on `br-agents` admits only TCP
  3128 (squid). The bridge is not a trusted interface; everything else —
  including DNS and the host's sshd — hits the default drop.
- **Squid is the sole egress path**, bound to the bridge IP, with a
  `dstdomain` CONNECT allowlist (`allowedDomains` in microvm-host.mod.nix)
  and a per-request access log at `/var/log/squid/access.log` — the egress
  audit trail. Squid resolves DNS on the guests' behalf. Anything that isn't
  HTTP(S) via the proxy (ssh-to-github, raw sockets) fails closed; widen the
  allowlist by reviewed commit, never bypass the proxy.
- **Containment by absence.** Workers are built from a minimal inline module
  list, not `self.nixosModules`: no tailnet, no host secrets, no monorepo.
  The host's `/nix/store` is shared read-only over virtiofs (so never put
  secrets in the store).
- **Squid is sandboxed.** It is the one host process that parses bytes from
  the guests, so its unit runs under a strict systemd sandbox (read-only
  filesystem, no new privileges, syscall/capability allowlist limited to the
  root→`squid` privilege drop).

The guest root is tmpfs, and the two per-worker volume images (nix-store
overlay + `/workspace` scratch) are deleted by `ExecStartPre` on every VM
start and recreated blank — nothing an agent writes survives a restart, so a
compromised or wedged worker is one `systemctl restart microvm@<name>` from
pristine.

## Credentials

Agents authenticate with **subscription logins**, not API keys: one Claude
Code OAuth token (`claude setup-token`) and one copy of Codex's `auth.json`
(ChatGPT login) are shared fleet-wide. Workers are generic by default: no
repo binding, no push credential — tasks return results over the task
share, so the forge is not in the loop at all. A worker meant to work one
specific repository gets `repo` plus optionally `patFile`, a
**fine-grained GitHub PAT scoped to exactly that repository** (Contents
read/write on that repo only; a forge ruleset protects `main` and permits
`agent/**` pushes). The credential's scope is the forge-side containment
boundary — repo-specificity lives only in the roster entry and the injected
secret, never in the modules.

These are agenix secrets under `hosts/fw0/`, decrypted by the host key at
activation. cloud-hypervisor does not support `microvm.credentialFiles`
(qemu-only), so injection works via a share: per worker, a host oneshot
(`agent-creds-<name>`) assembles a root-owned `0700` directory
`/run/agents/creds/<name>` containing exactly that worker's files,
which is exported to the guest as a **read-only virtiofs share** (virtiofsd
runs as root; the `microvm` user can never read it). In the guest,
`agent-credentials.service` installs them for the `agent` user:

- `/run/agent-env` (`0400`) — exports `CLAUDE_CODE_OAUTH_TOKEN` (and
  `GH_TOKEN`, when a PAT is configured); sourced by login shells. Non-login
  invocations must `. /run/agent-env` themselves.
- `~agent/.codex/auth.json` (`0400`) — Codex's login.
- git pushes over HTTPS using gh as the credential helper (`GH_TOKEN` →
  credentials at run time; no token on disk in gitconfig). `AGENT_REPO`
  holds the repo URL on repo-bound workers.

Never place secrets in the nix store: guests read the entire host store.

## Networking layout

The host uses systemd-networkd for **all** interfaces (mixing networkd with
scripted DHCP is unsupported): the `en*` uplink keeps plain DHCP, `br-agents`
is declared carrier-less, and `vm-*` taps are auto-enslaved to the bridge by
match. `tailscale0` is left to tailscaled. Worker addresses are
`10.100.0.10+index`; MACs are locally administered with the index as the
last octet.

## Resource fences

Every worker's `microvm@<name>` unit and squid run in `agents.slice`
(48G `MemoryMax`, declared in `hosts/fw0/fw0.mod.nix`). Guest memory is
static (no ballooning), default 8 vCPU / 8 GiB. Guest state lives on the
`@agents` btrfs subvolume (`/var/lib/agents/microvms`).

## Dispatch

A task is a markdown prompt, enqueued with the `fleet` tool. The cockpit never
writes the queue directly: the queue is owned by an unprivileged operator user
(`agentFleet.operatorUser`, default `fleet-operator`), and the cockpit reaches
it only by running `fleet` as that operator through a sudo rule scoped to
exactly that one binary (see fleet-tool.mod.nix). This sudo hop — not any
Claude permission rule — is the security boundary: a compromised or
prompt-injected cockpit can enqueue tasks and read reports, and nothing else.

```sh
run() { sudo -n -u fleet-operator fleet "$@"; }

id=$(run submit myslug < mytask.md)   # prompt on STDIN; prints the task id
run watch  "$id"                      # block until done/failed
run fetch  "$id"                      # print report.md (untrusted-output banner)
run status                            # tail the audit log
run note "$id" both models agreed     # annotate the audit trail (see below)
# or the whole loop in one blocking call:
run run myslug < mytask.md            # submit + watch + fetch -> the report
```

`submit` takes the prompt on stdin, never a path: the `< mytask.md` redirect is
opened by the *caller's* shell with the caller's privileges, so the tool never
opens a caller-supplied path and the root drainer never dereferences a
caller-supplied symlink. As further defense in depth the drainer rejects any
symlink or non-regular queue entry (quarantining it under `tasks/rejected/`)
before it would otherwise `install` it as root.

An optional front-matter block sets task options (unknown keys are ignored):

```markdown
---
agent: codex
model: gpt-5.5
---
The prompt starts here…
```

`agent` picks the executor — `claude` (default) or `codex`, both
subscription-authenticated in every guest; new executors are one case
branch in agent-vm.mod.nix. `model` is handed to the executor's `--model` —
use it to run routine tasks on a cheaper model and keep the strong models
for review, or to spread work across the two subscription pools.

### Guidance (mid-task escalation)

A worker that gets stuck can consult a stronger model: the agent runs
`ask-cockpit "<question>"` (it is told about this in its system prompt),
which drops `question-N.md` into the task share and blocks. The worker's
drainer notices the pending question on its poll and starts
`agent-guidance`, which answers with `agentFleet.guidanceModel` (default
`opus`) running headless as the cockpit user — same subscription login as
the cockpit session — and writes `answer-N.md` back through the share;
`ask-cockpit` prints it and the worker continues. Capped at 5 questions per task, 15 min wait each; the Q/A pairs
are archived with the results. The question text comes from inside a guest
and is untrusted, so the answering claude runs with all tools disallowed —
it can only produce text.

A path unit fires when the queue becomes non-empty and starts one drainer
per roster worker (`agent-dispatch-<worker>`). Each drainer claims tasks
off the queue with an atomic rename — losers of the race just re-scan — so
tasks run concurrently up to the number of workers. Per task, the drainer
stages `prompt.md` into its worker's task share
(`/var/lib/agents/work/<worker>/task`, mounted at `/run/task` in the
guest), restarts the VM — the volume wipe makes every task run pristine —
and the guest's `agent-task` unit runs
`claude -p "$(cat /run/task/prompt.md)"` as the agent user, writing
`report.md`, `agent.log`, and `exit-code` back through the share. The
drainer polls for the exit code, stops the VM, and files everything under
`/var/lib/agents/tasks/done/<id>/` (nonzero exit or `agentFleet.taskTimeout`
— default 90 min — go to `failed/` instead). The task lifecycle is recorded
as a narrative audit trail in `/var/lib/agents/tasks/log` — `tail -f` it from
the cockpit as the fleet ticker:

```
2026-07-08 13:20:00 cockpit SUBMIT   fix-lint-20260708-132000-4210842 agent=codex model=gpt-5.5 by=max
2026-07-08 13:20:04 worker-0 DISPATCH fix-lint-20260708-132000-4210842 agent=codex model=gpt-5.5
2026-07-08 13:24:31 worker-0 ESCALATE fix-lint-20260708-132000-4210842 question 1 -> opus
2026-07-08 13:26:10 cockpit NOTE     fix-lint-20260708-132000-4210842 both models agreed on the fix (by max)
2026-07-08 13:28:12 worker-0 DONE     fix-lint-20260708-132000-4210842 ran 8m8s, 1 escalation(s), report 24043 bytes
```

(The tool gives each task a unique id at submit, and the drainer files results
under that id verbatim, so one id threads the whole lifecycle.)

i.e. who dispatched what (and as which agent/model), when it started on which
worker, each ask-cockpit escalation as it happens (and to which model), and how
long it ran / how many escalations / whether a report came back. The SUBMIT
line is written by the `fleet` tool (the log is group-owned by the operator so
it can append); the rest by the root drainer. Fuller detail is in
`journalctl -u 'agent-dispatch-*'`.

The cockpit can interleave its own free-text annotations with `fleet note [id]
<text>` — tagged `NOTE` and attributed, so they read as commentary
(`cockpit NOTE fix-lint-… both models agreed on the retry-with-backoff fix
(by max)`) and are never mistaken for a machine-emitted lifecycle fact.
Newlines are flattened so a note is always exactly one line and cannot forge
extra entries.

The dispatcher owns worker lifecycle: a manually started VM is restarted out
from under you when a task arrives. Results land on the host disk only —
tasks need no forge access and no push credentials.

## Operating a worker

Lifecycle is manual, from the cockpit session on fw0:

```sh
systemctl start microvm@worker-0    # boot (seconds)
microvm -s worker-0                 # serial console (root autologin —
                                    # reaching the PTY already requires host root)
systemctl stop microvm@worker-0
```

Guests run no sshd and hold no authorized keys — the task share is the only
data channel, and the serial console (host-root-gated) the only interactive
one.

Adding a worker is one `agentFleet.workers` entry in the host module; the
VM definition, its queue drainer, slice override, and credential directory
are all generated from it.

## Verifying containment

From inside a guest, all of these must fail:

```sh
curl -m5 https://example.com        # proxy 403: not on the allowlist
getent hosts google.com             # no DNS
curl -m5 http://10.100.0.1:22       # no host ports besides 3128
```

And these must succeed, each leaving a line in squid's access log:

```sh
curl -sI https://api.anthropic.com
git ls-remote https://github.com/NixOS/nixpkgs
```

On the host, `systemd-cgls /agents.slice` shows the running VMs and squid
under the slice.
