# The life of a task — fleet decision tree

How work moves through the ship: every box a task can visit, every decision
that routes it, and every way it can come back. Companion to
[agent-fleet.md](agent-fleet.md) (mechanics and trust boundaries); this
document is the map.

Roles: the **captain** (human) commands; the **cockpit** (engineer model —
Claude Code seat or opencode web seat, same authority) runs the ship; the
**drones** (disposable worker microVMs) each execute exactly one task.

## 1. The big picture

```mermaid
flowchart TD
    CAP([Captain states a goal]) --> CKPT{"Cockpit:\nhow to do this?"}

    CKPT -->|"clarify / decision only the\ncaptain can make (taste, scope,\ndestructive, push, switch)"| ASK[Ask the captain] --> CAP
    CKPT -->|"small, local, or depends on\nunpushed/private host state"| LOCAL[Do it in the cockpit session]
    CKPT -->|substantial + self-contained| PLAN["Write task file:\nchoose agent + model + effort\n+ guidance per task"]

    PLAN --> DISPATCH[fleet dispatch / submit\nvia scoped sudo → queue]
    DISPATCH --> DRONE[Drone runs the task\nin a warm microVM]

    DRONE <-->|"peek / steer /\nescalate / answer"| MID[Mid-task interaction\nwith the cockpit]
    DRONE --> RESULT["Archive: report, log, patch,\nusage, progress, messages, Q&A"]

    RESULT --> REVIEW{Cockpit reviews\nUNTRUSTED output}
    REVIEW -->|inadequate / failed| PLAN
    REVIEW -->|"needs a stronger model\nor different provider"| PLAN
    REVIEW -->|good| APPLY[Apply patch, verify,\ncommit locally]

    LOCAL --> VERIFY["Verify: build / test / run"]
    APPLY --> VERIFY
    VERIFY --> REPORT([Report up to the captain])
    REPORT -->|push? switch? next heading?| CAP
```

Authority flows one way — captain → cockpit → drones — and every upward
arrow is *information*, never command: drone output is untrusted data, and
the cockpit acts on it only with its own judgment.

## 2. Dispatch: the cockpit's routing decisions

The cockpit is the sole decider. A task file **must** name `agent` and
`model` (missing either → rejected at submit, exit 2, nothing enqueued —
no downstream defaults exist).

```mermaid
flowchart TD
    TASK[Task in hand] --> WHERE{Where should it run?}

    WHERE -->|"needs session context,\nreal judgment, or private state"| COCKPIT[Cockpit does it itself]
    WHERE -->|self-contained work| EXEC{Pick executor + model\nby the economics doctrine}

    EXEC -->|"mechanical, fully specified"| HAIKU[claude / haiku]
    EXEC -->|"routine impl from clear spec"| SONNET[claude / sonnet]
    EXEC -->|"substantial standalone coding,\nindependent second opinion\n(ChatGPT pool)"| SOL[codex / gpt-5.6-sol]
    EXEC -->|"anything on the OpenRouter\ncatalog (per-token billing)"| OR[opencode / openrouter/…]
    EXEC -->|"bulk low-stakes volume\n(free, weaker, on-GPU)"| LOCALM[opencode / local/…]
    EXEC -->|"frontier judgment inside\nthe Claude pool"| FABLE[claude / fable]

    HAIKU & SONNET & SOL & OR & LOCALM & FABLE --> GUID{Advisor for escalations?}
    GUID -->|"none, or omitted with no\nfleet-wide default configured\n(the current default)"| G0["guidance: none —\nescalations answered\n'use your own judgment'"]
    GUID -->|"a stronger Claude model"| G1["guidance: &lt;claude-model&gt; —\nheadless advisor answers\n(5-min timeout → fall back to\n'use your own judgment')"]
    GUID -->|"the live cockpit itself"| G2["guidance: cockpit —\nquestions surface to the engineer"]

    G0 & G1 & G2 --> CTX{Does it need source context?}
    CTX -->|yes| CAPSULE["fleet dispatch &lt;slug&gt; task.md &lt;dir&gt;\n→ capsule (prompt ≤1 MiB + context\n≤512 MiB compressed, .git/.env excluded)"]
    CTX -->|"no (prompt is self-sufficient)"| SUBMIT["fleet submit &lt;slug&gt; < task.md"]

    CAPSULE & SUBMIT --> Q[(Queue\noperator-owned)]
```

Fan-out is free: submit N tasks and up to 10 warm drones run them
concurrently; the same review can be sent to two vendors in parallel for
genuinely independent opinions.

## 3. Inside the drone: one task, one VM, one life

```mermaid
flowchart TD
    WARM(["Warm pool: idle VM,\nguest refreshes .ready\nevery second"]) -->|"idle > 2h\n(preventive)"| RECYCLE
    WARM -->|"VM died or .ready\nwent stale while idle"| RECYCLE[Destroy + reboot\nfresh warm VM] --> WARM

    Q[(Queue)] --> CLAIM["Drainer atomically claims task\n(one resident root drainer per worker)"]
    WARM --> CLAIM
    CLAIM --> ALIVE{"VM alive and .ready\nFRESH (≤60s)?"}
    ALIVE -->|no| REQ1[Requeue task] --> Q
    ALIVE -->|yes| STAGE["Stage EXACTLY the selected\nexecutor's credential + task-meta\n(local/ tasks get none)"]
    STAGE --> DELIVER["Deliver context, then prompt.md LAST\n→ DISPATCH in audit log"]

    DELIVER --> GUEST{"Guest validates:\ncredential set matches executor?\ncapsule extracts cleanly?"}
    GUEST -->|"no → exit 64/65/66,\nexecutor never launches"| FAIL
    GUEST -->|yes| RUN["Executor CLI runs unsandboxed\n(all actions auto-approved) as its\nnon-root executor user — containment\nis the host: no route, no DNS, no\nGitHub; squid allowlist for egress,\ndirect bridge HTTP for local/ inference"]

    RUN --> WATCH{Host watchdogs}
    WATCH -->|"exit-code written"| DONE{exit 0?}
    WATCH -->|"no heartbeat 120s,\nbut NONE ever arrived\n(never picked up)"| REQ2["Pool fault, not task fault:\nrequeue ONCE on the fresh VM\nthe recycle produces"] --> Q
    WATCH -->|"no heartbeat 120s\n(after pickup, or 2nd time)"| STALL[STALLED] --> FAIL
    WATCH -->|"6h absolute cap"| CAP2[CAP] --> FAIL
    WATCH -->|"exchange > 768 MiB"| OVER[OVERSIZE] --> FAIL

    DONE -->|yes| OK[→ done/]
    DONE -->|no| FAIL[→ failed/]

    OK & FAIL --> STOPVM["VM stopped,\ncredentials cleared"]
    STOPVM --> ARCHIVE["Bounded no-follow archival:\nprompt, exit-code, report ≤10 MiB,\nlog + patch ≤50 MiB, usage ≤64 KiB,\nprogress, messages, Q&A"]
    ARCHIVE --> WIPE["Volumes wiped on next VM start\n→ fresh warm guest boots"]
    WIPE --> WARM
```

The VM is destroyed after every task regardless of outcome — a compromised
or wedged drone is one recycle from pristine, and nothing an agent writes
survives except the bounded archive. A drainer that restarts mid-task
(host switch, crash) requeues whatever was stranded in `running/`.

## 4. Mid-task: every way the cockpit and a running drone interact

```mermaid
flowchart TD
    subgraph DRONE_VM [Running drone]
        AGENT[Agent working]
        AGENT -->|"writes progress.md\nat each major step"| PROG[progress.md]
        AGENT -->|"checks ls /run/task at\ncheckpoints + before report"| MSGS[message-N.md]
        AGENT -->|"genuine judgment call:\nask-cockpit '…' (max 5)"| QN[question-N.md]
    end

    PROG -->|"drainer mirrors on change\n(progress ≤1 MiB, log tail 64 KiB,\nbounded no-follow)"| LIVE[(live/&lt;id&gt;/\nhost-owned mirrors)]
    LIVE -->|"fleet peek &lt;id&gt;\nprogress + questions + log tail"| ENG

    ENG[Cockpit engineer] -->|"fleet steer &lt;id&gt; 'msg'\n(≤32 per task, ≤64 KiB each)"| SPOOL[(steer spool)]
    SPOOL -->|"drainer delivers\n→ STEERED"| MSGS

    QN -->|"≤64 KiB each"| WHO{Task's guidance setting}
    WHO -->|"none / no default"| AUTO["Instant answer:\n'use your own judgment'"] --> ANS
    WHO -->|"claude model id"| ADVISOR["agent-guidance service:\nheadless advisor, no tools,\nreads spooled Q + prompt;\n5-min timeout → 'use your\nown judgment' fallback"] --> ANS
    WHO -->|cockpit| ATTN["fleet health: questions-pending\n+ ATTENTION line; visible in peek"] --> ENG
    ENG -->|"fleet answer &lt;id&gt; &lt;n&gt;\n(may consult the captain first)"| ANS[answer-N.md ≤1 MiB\ndelivered into the guest]
    ANS -->|"agent unblocks (waits\nup to 30 min, then proceeds\non its own judgment)"| AGENT

    ENG -.->|"wedged vs thinking?\npeek first, then judgment:\nlet it run / steer / kill"| DRONE_VM
```

Two invariants hold everywhere in this diagram: the host **displays**
guest-written content and **delivers** cockpit-written files, but never
takes instructions from guest prose — the only guest bytes the host acts
on are the two narrow machine fields it defined itself (`exit-code` for
done/failed routing, `usage.json` for the cost ledger), both bounded and
format-checked. And everything that crosses the boundary is a bounded
regular file moved with no-follow semantics.

## 5. Results: from archive to the captain

```mermaid
flowchart TD
    DONE[(done/ or failed/)] --> FETCH["fleet fetch &lt;id&gt; — report wrapped\nin UNTRUSTED banner; fleet logs /\nfleet patch for transcript + diff"]
    FETCH --> JUDGE{Engineer's review}

    JUDGE -->|"failed or inadequate"| RETRY{Why?}
    RETRY -->|"model below the task's bar"| UP["Escalate a tier and\nredispatch — never retry\nat the same tier"]
    RETRY -->|"directive was ambiguous"| REWRITE[Rewrite the task file,\nredispatch]
    UP & REWRITE --> BACK([→ dispatch tree, §2])

    JUDGE -->|"report suggests follow-up work"| OWN["Engineer's OWN judgment decides —\nnever auto-dispatch a drone's\nsuggestion; consequential calls\ngo to the captain"]
    JUDGE -->|good| PATCH{Code change?}

    PATCH -->|yes| APPLY["fleet patch &lt;id&gt; → apply to the\nreal repo, verify (build/test/run),\ncommit — plain message, NO push"]
    PATCH -->|"no (research/report)"| SUMM[Summarize up]

    APPLY & SUMM & OWN --> CAPREPORT([Report to captain with evidence])
    CAPREPORT --> CAPDECIDE{Captain}
    CAPDECIDE -->|push| PUSH[git push]
    CAPDECIDE -->|activate| SWITCH[nh os switch .#fw0\ncaptain-only]
    CAPDECIDE -->|new heading| NEXT([Next task → §1])
```

## 6. The full audit trail

Every **state-changing** hop leaves a line in `/var/lib/agents/tasks/log`
(read-only commands — watch, fetch, logs, patch, peek — do not):

```
SUBMIT → DISPATCH → [STEER → STEERED]*
                  → [ESCALATE (→ ANSWER → ANSWERED, cockpit guidance only)]*
                  → DONE | TIMEOUT (after a STALLED / CAP / OVERSIZE line)
```

A pre-pickup stall instead logs a requeue and later a second `DISPATCH`.
Model-advisor escalations log only `ESCALATE` — the guidance service
answers without further log lines. Add `NOTE` for free-text cockpit
annotations and rejection lines for anything that failed a trust check.
`fleet status` tails the log; `ship-status` shows the live pool;
`ship-costs` attributes each task's tokens to its subscription pool.
