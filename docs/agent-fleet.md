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

A task is a markdown prompt. From the cockpit:

```sh
vim /tmp/mytask.md                              # write the prompt
mv /tmp/mytask.md /var/lib/agents/tasks/queue/  # mv, so no half-written file is seen
```

An optional front-matter block sets task options (unknown keys are ignored):

```markdown
---
model: sonnet
---
The prompt starts here…
```

`model` is handed to `claude --model` in the guest — use it to run routine
tasks on a cheaper model and keep the strong models for review.

### Guidance (mid-task escalation)

A worker that gets stuck can consult a stronger model: the agent runs
`ask-cockpit "<question>"` (it is told about this in its system prompt),
which drops `question-N.md` into the task share and blocks. On the host, a
path unit fires `agent-guidance`, which answers with
`agentFleet.guidanceModel` (default `opus`) running headless as the cockpit
user — same subscription login as the cockpit session — and writes
`answer-N.md` back through the share; `ask-cockpit` prints it and the worker
continues. Capped at 5 questions per task, 15 min wait each; the Q/A pairs
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
— default 90 min — go to `failed/` instead). Progress is in
`journalctl -u 'agent-dispatch-*'`.

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
