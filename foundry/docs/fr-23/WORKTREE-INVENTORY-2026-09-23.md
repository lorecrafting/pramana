# Worktree and branch inventory — 2026-09-23

Inventory only, per FR-23a's "Remaining" item on worktrees and branches. Nothing here was
deleted or pruned. Snapshot taken from `git worktree list --porcelain`, `git branch --format`,
and `git merge-base --is-ancestor` against `origin/repair/fr08b-kernel`
(`b94317dc1fed66c82329311d0578bdf6e4b7cd60`) and `origin/main`
(`a19070ad1c9e90ce116be0f89c04a4c6b24850e1`), both as fetched at inventory time. Several
worktrees are `locked` by a running Foundry coordinator (pid 89602 at snapshot time) with other
Claude sessions attached; their HEADs and dirty state can move between this snapshot and any
later read, and one worktree's HEAD (`agent-a1fdf45078e11051d`) already advanced during this
scan. Treat the table as a photograph, not a live query.

**Disposition rule used below:** `safe to remove` only when a row is **unlocked AND clean AND**
its HEAD is an ancestor of `origin/repair/fr08b-kernel` or `origin/main`. Everything else is
`needs owner`, including every locked row (an active agent may depend on it) and every dirty
row (uncommitted or untracked work would be lost). This is a conservative rule, not a claim that
every `needs owner` row is unsafe forever — several rows below carry a note explaining why a
human could likely clear them quickly.

**Caveat on "merged".** `merge-base --is-ancestor` only catches a fast-forward-reachable commit.
A branch whose commit was cherry-picked or re-committed with a different hash reads as "no" here
even when its content already landed. Several rows below have a HEAD commit **subject** that
matches a commit already on `origin/repair/fr08b-kernel` under a different hash — evidence of a
duplicate/superseded parallel attempt, not confirmed identical content (no diff was run). These
are flagged in the Notes column and still scored `needs owner`, not `safe to remove`.

## Worktrees

| Path | HEAD | Branch | Locked | Merged→repair | Merged→main | Working tree | Disposition | Notes |
|---|---|---|---|---|---|---|---|---|
| `/Users/raymondluong/dev/pramana` | `b94317dc` | `repair/fr08b-kernel` | no | yes (is the tip) | no | clean | **keep** | Primary checkout. Never a removal candidate. |
| `.../scratchpad/b5-probe` (another session's scratchpad, `3cec5694-…`) | `f3f03880` | (detached) | no | yes | yes | dirty: 2 untracked (`probe_b5b.exs`, `probe_b5c.exs`) | needs owner | HEAD is fully merged both ways, but untracked scratch files may belong to a still-running session. Do not sweep (see parallel-session note in operator memory). |
| `.../pramana-supervisor/runs/20260905-omp-r4/candidates/T03R-02d4db75` | `7e98ac4b` | (detached) | no | no | no | clean | needs owner | Foundry supervisor candidate output, not an agent worktree. Disposition is the supervisor/steerer's, not this ticket's. |
| `.../pramana-supervisor/runs/20260907-omp-r13/candidates/AUTO-STATE-LOCALITY-02-e4aa13d6` | `5ee5dd47` | (detached) | no | no | no | clean | needs owner | Same as above; a different run. |
| `.../worktrees/agent-a098191df7987b847` | `4a511e45` | `worktree-agent-a098191df7987b847` | no | no | no | clean | needs owner | Unintegrated; no duplicate-subject match found on repair's tip history. |
| `.../worktrees/agent-a1fdf45078e11051d` | `6b96a404` (moved from `b94317dc` mid-scan) | `worktree-agent-a1fdf45078e11051d` | **yes** | no | no | clean | **keep — locked** | HEAD advanced during this scan; an agent is actively committing here. |
| `.../worktrees/agent-a36f808dd1417b754` | `8a490ad2` | `worktree-agent-a36f808dd1417b754` | no | no | no | clean | needs owner | Subject "O0 authority inventory of workflow crossings; changes no behaviour" matches `b4396ac0` on repair's tip — likely a superseded duplicate, not diffed. |
| `.../worktrees/agent-a3fc42c27fcca9534` | `0295965d` | `worktree-agent-a3fc42c27fcca9534` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-a558c98365e3f84dd` | `eac0a843` | `worktree-agent-a558c98365e3f84dd` | **yes** | no | no | clean | **keep — locked** | |
| `.../worktrees/agent-a5e4b34fab0b9a174` | `6e87be67` | `worktree-agent-a5e4b34fab0b9a174` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-a6b7b5fe84664c31d` | `68e91bd2` | `worktree-agent-a6b7b5fe84664c31d` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-a6d6180854c6c4dbc` | `6e737b6d` | `worktree-agent-a6d6180854c6c4dbc` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-a73b3780f82a90a86` | `89ac37ad` | `worktree-agent-a73b3780f82a90a86` | no | no | no | clean | needs owner | Subject "pin 18 loose refusal assertions; record four that passed on another guard" matches `b46d3825` on repair's tip — likely a superseded duplicate, not diffed. |
| `.../worktrees/agent-a7b084add1ff8151a` | `97c1a0a2` | `worktree-agent-a7b084add1ff8151a` | **yes** | no | no | clean | **keep — locked** | |
| `.../worktrees/agent-a853ab6551637b7d8` | `fbcee186` | `worktree-agent-a853ab6551637b7d8` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-a87da308e7e1244d2` | `ad80ee27` | `worktree-agent-a87da308e7e1244d2` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-a9ee75704a6b8a606` | `393eb942` | `worktree-agent-a9ee75704a6b8a606` | no | no | no | clean | needs owner | Subject "bin script health check; no self-check had drifted" matches `87ee6d57` on repair's tip — likely a superseded duplicate, not diffed. |
| `.../worktrees/agent-aa12e2eb69b12dea6` | `e608a2b0` | `worktree-agent-aa12e2eb69b12dea6` | **yes** | yes | no | **dirty**: 3 files modified under `workflow/kernel/` | **keep — locked, dirty** | Merged HEAD but live uncommitted edits; do not touch. |
| `.../worktrees/agent-aa15dae5a6f550c33` | `479fe476` | `worktree-agent-aa15dae5a6f550c33` | **yes** | no | no | clean | **keep — locked** | |
| `.../worktrees/agent-aad81bbb0543ad2fe` | `4331af94` | `worktree-agent-aad81bbb0543ad2fe` | no | no | no | clean | needs owner | Subject "FR-08B subcommit 3 design proposal and struct measurement" matches `d0da6fc1` on repair's tip — likely a superseded duplicate, not diffed. |
| `.../worktrees/agent-ab9d2b8f80ab0e7b8` | `f08bb534` | `worktree-agent-ab9d2b8f80ab0e7b8` | no | no | no | clean | needs owner | Subject "a check settlement binds only its own execution" matches `aed6561e` on repair's tip — likely a superseded duplicate, not diffed. |
| `.../worktrees/agent-ac02eda0e4ce924ee` | `2eb27db6` | `worktree-agent-ac02eda0e4ce924ee` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-acf2756faa1e4023a` | `3d562b92` | `worktree-agent-acf2756faa1e4023a` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-ad073359a95c8f2ca` | `5318fafc` | `worktree-agent-ad073359a95c8f2ca` | **yes** | no | no | clean | **keep — locked** | |
| `.../worktrees/agent-ad3f24216bbf3abbb` | `e608a2b0` | `worktree-agent-ad3f24216bbf3abbb` | **yes** | yes | no | clean | **keep — locked** | Would score `safe to remove` if unlocked (merged, clean); locked wins. |
| `.../worktrees/agent-ad84735d34cfe5d49` | `5b559119` | `worktree-agent-ad84735d34cfe5d49` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-ad90a9728ec98c4d2` | `36fbc819` | `worktree-agent-ad90a9728ec98c4d2` | no | no | no | clean | needs owner | This is the ticket-instruction-referenced worktree (`ad90a9728ec98c4d2`) but is not the one this scan runs from; the task assigned this agent to `agent-ae7f19358de7e4ffe`. |
| `.../worktrees/agent-ad962bdd55b2b6125` | `8984b6cb` | `worktree-agent-ad962bdd55b2b6125` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-ad9e97f4f9ed52803` | `684eacc1` | `worktree-agent-ad9e97f4f9ed52803` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-ae6586ae516843e25` | `a626b8fd` | `worktree-agent-ae6586ae516843e25` | no | no | no | clean | needs owner | |
| `.../worktrees/agent-ae7f19358de7e4ffe` | `f32a4b55` (base) | `worktree-agent-ae7f19358de7e4ffe` | **yes** | yes | no | dirty (this task's pending edits) | **keep — this session** | Where this inventory and the FR-23a bin fixes were made. |
| `.../worktrees/agent-af8f5a352ce484a1e` | `56200586` | `worktree-agent-af8f5a352ce484a1e` | no | no | no | clean | needs owner | |

**Count: 31 worktrees.** 8 locked (keep), 1 primary (keep), 22 unlocked: 0 clean+merged
(`safe to remove` under the rule above), 1 dirty+merged (`b5-probe`, needs owner), 2 supervisor
candidates (needs owner, out of this ticket's scope), 19 clean+unmerged (needs owner; 6 of those
carry a duplicate-subject note). **No worktree currently qualifies as `safe to remove`** — every
merged HEAD sits either on the primary checkout or a locked worktree, and no unlocked worktree is
both clean and merged. If a locked row's owner confirms the lock is stale (the recorded pid is no
longer a live coordinator) and its HEAD is merged, its removal command would be:

```
git worktree remove <path>          # add --force only if the tree turns out dirty
git branch -d worktree-agent-<id>   # -d refuses unless HEAD is actually merged
```

For the two supervisor-candidate rows, removal is the supervisor/steerer's process, not
`git worktree remove` — do not run a generic worktree removal against a candidate directory.

## Local branches with no attached worktree

9 of 38 local branches have no worktree. Same merge check against the same two refs.

| Branch | HEAD | Merged→repair | Merged→main | Disposition | Notes |
|---|---|---|---|---|---|
| `backup-history` | `3e0309bc` | no | no | needs owner | Name suggests a deliberate manual snapshot; not this ticket's to remove. |
| `docs/positioning-audit-2026-09-21` | `5abf18e2` | yes | yes | **safe to remove** | `git branch -d docs/positioning-audit-2026-09-21` |
| `main` | `a319b399` | yes | — (is `origin/main`'s local tracking branch) | **keep** | Never a removal candidate. |
| `repair/fr08a-event-vocabulary` | `27b4d6e0` | yes | yes | **safe to remove** | `git branch -d repair/fr08a-event-vocabulary` |
| `repair/fr08b-blocked-event` | `e64006d3` | yes | no | **safe to remove** | `git branch -d repair/fr08b-blocked-event` |
| `repair/fr08b-kernel-wip` | `059546b5` | no | no | needs owner | |
| `repair/fr08b-pure-kernel` | `a8ecf36b` | no | no | needs owner | |
| `repair/fr08b-vocab-collision` | `55490aad` | yes | no | **safe to remove** | `git branch -d repair/fr08b-vocab-collision` |
| `spike/execution-struct-aad81` | `099f417f` | no | no | **safe to remove (author-declared)** | Commit message is `spike: execution entity as a struct (throwaway)`. Unmerged, so `git branch -d` will refuse; the confirming command is `git branch -D spike/execution-struct-aad81`, which bypasses the merge check — get a second look before running it despite the self-label. |

None of these commands were run.
