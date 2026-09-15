# Checks and Gates — chapter 3

> Topic reference. Historical measurements retain their original scope; use the current architecture and testing guides for operational guarantees.
> [Contents](../CHECKS.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

## Periodic (every ~3 phases)

- `mix dialyzer` across the whole umbrella with no ignore file growth. **Run it more
  often than this schedule says.** It was recorded as "0 errors, and no ignore file
  exists — none has ever been needed" at the phase-4 gate and was found at **9** on
  2026-08-22, all predating that session. Seven were one cause — three mix tasks built a
  source map inline instead of reading `Pramana.Sources`, and the copies had already
  drifted, so the lockfile and the database stated different licence terms for `sc`. The
  other two were specs that lied: a `toh: String.t()` that is nil for 84000's placeholder
  records, which made dialyzer call a live guard dead code. It runs in **22 seconds** once
  the PLT is built, which is cheap enough that "phase-gate only" is the wrong cadence for
  it.
- Dependency upgrade pass — deliberate, one PR-sized change
- Re-read `docs/COMPETITIVE.md`: has fojin shipped something that changes our
  positioning? Is our differentiation still real?
- Bake cost review: what does a full bake cost in time and tokens now?

## Security review

Run `/security-review` before any deployment task and at the Phase 7 gate. Specific
concerns for this project:
- Prompt injection via corpus text — canonical texts are trusted, but **locally-added
  sources and any OCR output are not**. Text from a manifest-added source must never
  be treated as instructions.
- The Python sidecar must not be reachable from outside the compose network.
- License gating must actually exclude `restricted` content from any public surface.

## What "stable" means here

The invariants in `CLAUDE.md` are the definition. Tests prove behavior; the checkpoint
architecture review proves the *shape* is still right. Both are required — a codebase
can be fully green and still have quietly stopped being the thing it was designed to
be.
