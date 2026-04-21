# Checkpoint — 2026-04-20 — v17 rules audit (Phase 6 prep)

**PRs shipped this day (prior to this session):** #35 (victory conditions), #37 (roster builder), #39 (targeting visibility), #41 (objective scoring).

**This session's scope:** full v17 core-rules accuracy audit (#38), fix the small data divergences inline, and file sub-issues for every remaining gap so the audit finding catalog is tracker-visible.

## Work shipped

- **PR [#43](https://github.com/rpmcdougall/turnipsim/pull/43)** — first slice of #38. Five inline data corrections:
  - Chaff gains `vanguard` (JSON was missing it per v17 p.31).
  - Brutes loses `vanguard` (JSON had it incorrectly; book p.30 says no).
  - Stump Gun `weapon_range` 48 → 60 (Round Shot is 60" per p.32).
  - Stump Gun description corrected: 2 wounds per Round Shot hit (not 3); notes the 3D6 Grape Shot attack count.
  - Initiative roll replaced with proper roll-off: two D6, higher wins, ties re-roll (p.9).

## Audit findings + sub-issues filed

Audit delegated to a research agent with `/tmp/v17.txt` (pdftotext of the v17 core rules). Produced a structured catalog with finding IDs, severity, fix-size, file:line hotspots, and a recommended PR split. Counts: 8 critical, 14 major, 9 minor, 16 implemented-correctly.

**Orphans added to board during this session:** #38 (core audit umbrella), #40 (return fire + retreat), #42 (Cult audit — pre-deploy, not tackled yet).

**Sub-issues filed (all on project board, Todo):**

| # | Title | Severity | Fix size |
|---|---|---|---|
| #44 | Decision: inches vs. integer-Manhattan grid | Critical | Large (meta) |
| #45 | Improbable Hits (7+/8+) | Critical | Medium |
| #46 | 1" rule for non-charge moves | Major | Small |
| #47 | Charge fail-still-move-full + 1" exception | Major | Small |
| #48 | Snob moves with commanded unit | Minor | Small |
| #49 | Reroll infrastructure | Major | Medium |
| #50 | Vanguard pre-game phase | Major | Medium |
| #51 | Dash free move after Whelps' order | Major | Small |
| #52 | Panic test subsystem (foundational) | Critical | Medium |
| #53 | Retreat subsystem | Critical | Large |
| #54 | Stand and Shoot | Critical | Medium |
| #55 | Two-sided melee bouts + post-melee panic | Critical | Large |
| #56 | LoS + closest-target enforcement | Critical | Large |
| #57 | Toff Off duel | Major | — |
| #58 | Terrain system | Major | Large |
| #59 | Scenario system | Major | Large |

Plus the cult-audit umbrella (#42) still outstanding as a Phase 6 gate.

## Sequencing decision

Agreed plan with user: modular discrete chunks.

1. **#43 data PR** (this session — shipping now)
2. **#44 grid-vs-inches decision** — meta, gates LoS / 1" rule / range math
3. **#52 panic subsystem** — foundational; unlocks charge panic, retreat, Fearless, Bowel-Loosening
4. **#53 retreat subsystem** — depends on panic
5. **#55 two-sided melee bouts** — depends on panic/retreat
6. **#56 LoS + closest-target** — depends on grid decision
7. Independent mediums (#45 / #46 / #47 / #48 / #49 / #50 / #51 / #54 / #57)
8. Systems-sized (#58 terrain, #59 scenarios) — coupled with scenarios memory
9. #42 Cult audit — last, pre-deploy

## Notable insights from the audit

- Order sequence, equipment, roster validation, objectives, victory check are **solid**. The rules engine isn't wrong — it's *incomplete*. Good news.
- **None of the special rules in `v17.json` beyond `immobile` are actually enforced.** They're data waiting for engine support.
- **Panic tests are the keystone** — once they land, Fearless / Safety in Numbers / Bowel-Loosening / Stubborn Fanatics / retreat-on-loss / charge-panic-test all become wirings, not new features.
- **Grid-vs-inches decision ripples through every range check.** Worth a decision-log pass before committing to more combat mechanics.
- Change list (`rules_export/Change list v17.txt`) cross-checked during session — it's the v16→v17 delta and confirms data points we now have right (Bastards 2W, Whelps V6+, initiative-sticks, Vanguard ownership).
- Playtest v18 rules exist in `rules_export/` — out of scope for v17 audit. Filing a future-version issue later, once v18 settles.

## Footguns discovered this session

None new. Previously-flagged traps (inferred-Variant ternary, `godot -s` autoload parse errors) held steady. Agent work went smoothly — delegating the page-by-page cross-reference paid off in main-context cleanliness.

## Roadmap impact

- Phase 5 polish is effectively done except deferred #21 bullets (sprites, camera, tooltips — non-blocking).
- Phase 6 deploy is now gated on: #38 (in progress via the sub-issues), #40, #42 cult audit. No code-level blockers otherwise.
- Phase 7 Cult mechanics (#29) is scoped after #42 audit.

## Next pickup

**#44 (grid-vs-inches decision)** is the most valuable single piece of work to resolve next — small focused discussion, followed by a decision-log entry in CLAUDE.md. Everything downstream benefits from the locked-in coord system.
