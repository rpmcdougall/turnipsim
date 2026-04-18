# Phase 1 Review — Game Data Layer

**Date:** 2026-04-17
**Commit:** `9b9b2c1`
**Status:** ✅ PASSING — All requirements met, tests green

## Summary

Phase 1 successfully implements the core game data layer with RefCounted types, JSON-driven rulesets, and deterministic army rolling. All 19 automated tests pass, and the demo script confirms armies roll correctly with proper composition, mutations, and weapon assignments.

## Implementation Review

### types.gd — Data Classes ✅

**Implemented:**
- `Stats` — 6 core stats (movement, shooting, combat, resolve, wounds, save)
- `Weapon` — name, type, range, modifier
- `Mutation` — name, description, stat_modifiers dictionary
- `Unit` — complete unit with base_stats, weapon, mutations array

**Strengths:**
- Pure RefCounted, zero Node dependencies ✓
- Complete serialization (to_dict/from_dict) for all types ✓
- `get_effective_stats()` correctly applies mutation modifiers ✓
- Clean separation of base stats and mutations

**Minor Notes:**
- Stat modifiers can push values negative (e.g., save: 5 - 6 = -1). This is acceptable for MVP — negative stats will just make units terrible. Can add clamping in Phase 4 if needed.
- Unknown stat names in mutations (typos in JSON) silently do nothing. The match statement in `get_effective_stats()` won't warn. Acceptable trade-off for simplicity.

### ruleset.gd — JSON Loader ✅

**Implemented:**
- Comprehensive validation with clear error messages
- Validates archetypes, mutation tables, weapons, composition rules
- Fails fast on missing required fields or malformed data
- Helper methods: `get_archetype()`, `get_allowed_weapons_for_archetype()`, `get_random_weapon_for_archetype()`

**Strengths:**
- Excellent error messages include context (archetype name, table name) ✓
- Type checking for all critical fields ✓
- Validates mutation table ranges and weapon types ✓

**Minor Notes:**
- Does not validate that weapon names in `allowed_weapons` actually exist in the `weapons` array. If you reference a non-existent weapon, `get_random_weapon_for_archetype()` returns an empty dict, and `army_roller.gd` creates a unit with a default empty Weapon. This is graceful degradation but could be caught earlier with a validation pass. Low priority.

### army_roller.gd — Army Generation ✅

**Implemented:**
- `roll_army(ruleset, roll_d6)` with dependency-injected dice
- Respects composition rules (min/max units, required archetypes)
- Rolls mutations from tables using dice ranges
- Assigns weapons from allowed lists
- Generates thematic unit names (hardcoded for now, data-driven later)

**Strengths:**
- Dependency injection makes testing deterministic ✓
- Fulfills required units first, then fills remaining slots ✓
- Mutation rolling correctly matches dice ranges [1-2], [3-4], [5-6] ✓

**Edge Cases Found:**
1. **Infinite loop risk (line 42-60):** If `slots_remaining > 0` but all archetypes hit their max counts, the while loop relies on `_all_archetypes_maxed()` to break. This works, but if composition rules are misconfigured (e.g., min_units > sum of all max archetype counts), the loop could spin. **Mitigation:** Current MVP ruleset is valid. Can add a safety counter in future if needed.

2. **Dice assumptions:** `_pick_random()` subtracts 1 from the dice roll (line 178), assuming roll_d6 returns 1-6. If a dice function returns 0, we'd get index -1 (wraps to end of array in GDScript). **Mitigation:** All callers use proper 1-6 dice. Acceptable for MVP.

3. **Mutation table selection:** Line 89 uses `min(mutations_per_unit, mutation_tables.size())`, meaning mutations are only rolled from the *first N tables*. If an archetype has 3 tables but mutations_per_unit is 2, the 3rd table is never used. **Mitigation:** Current MVP rulesets all have exactly 2 tables and mutations_per_unit = 2. This could be improved by randomly selecting which tables to roll from, but the current behavior is deterministic and works.

### mvp.json — Ruleset Data ✅

**Validation:**
- 3 archetypes: Toff (officer), Chuff (infantry), RootBeast (monster) ✓
- Each archetype has 2 mutation tables, each covering full d6 range ✓
- 7 weapons defined, all referenced weapons exist in allowed_weapons ✓
- Composition rules: 5-10 units, 1-2 Toffs required ✓
- mutations_per_unit = 2 matches table count ✓

**Balance:**
- Toffs: High resolve, moderate combat, 2 wounds (leaders)
- Chuffs: Better shooting/combat, lower resolve, 1 wound (cannon fodder)
- RootBeasts: No shooting, high combat/resolve/wounds, melee only (bruisers)

Looks thematically appropriate for grimdark vegetable warfare.

## Test Results

### Automated Tests: 19/19 Passing ✅

```
[Test Suite: Types]
  ✓ Stats creation
  ✓ Stats to_dict and from_dict
  ✓ Weapon creation
  ✓ Weapon to_dict and from_dict
  ✓ Mutation with stat modifiers
  ✓ Unit with mutations applies stat modifiers
  ✓ Unit to_dict and from_dict

[Test Suite: Ruleset]
  ✓ Load valid MVP ruleset
  ✓ MVP ruleset has expected archetypes
  ✓ MVP ruleset has weapons
  ✓ Get archetype returns correct data
  ✓ Get allowed weapons for archetype
  ✓ Reject non-existent file
  ✓ Reject invalid JSON

[Test Suite: ArmyRoller]
  ✓ Roll army with deterministic dice
  ✓ Army respects composition rules (has required Toff)
  ✓ Units have mutations
  ✓ Units have weapons
  ✓ Same dice sequence produces identical army
```

### Demo Script: PASSED ✅

Rolled 3 random armies (sizes: 6, 8, 5 units):
- All armies had 1-2 Toffs (composition rules enforced) ✓
- Units received appropriate weapons for their archetype ✓
- Mutations applied correctly (visible in effective stats) ✓
- Thematic names generated (Lord Moldington, Wretch Trenchfoot, Carrot Abomination) ✓
- Stat modifiers computed correctly (e.g., Baron Gangrenshire: base W2 + Turnip Rot +1 = W3) ✓

Sample output:
```
[1] Sir Moldington (Toff)
    Stats: M6 S4 C5 R5 W2 Sv3+
    Weapon: Pistol (ranged)
    Mutations:
      • Dueling Scars — Hardened by countless affairs of honor (Combat +1)
      • Beetroot Heart — Pumps with unnatural vigor (Movement +1)
```

## Architectural Compliance

- ✅ All `game/` code is pure RefCounted
- ✅ Zero Node/scene/signal dependencies
- ✅ Usable from server, client, or headless tests
- ✅ Data-driven rulesets (JSON, not hardcoded)
- ✅ Dependency injection for dice (deterministic testing)

## Bugs Found

**None.** All edge cases noted above are acceptable behavior for MVP.

## Recommendations for Future Phases

1. **Ruleset validation enhancement:** Add a pass that validates `allowed_weapons` references exist in the weapons array. Low priority — easily caught by QA.

2. **Mutation table randomization:** Instead of always rolling from the first N tables, randomly select which tables to use. This would give more variety if archetypes have >2 mutation tables in future rulesets.

3. **Stat clamping:** Consider clamping stats to prevent negatives in `get_effective_stats()`. Not urgent — negative stats just make units bad, which is fine.

4. **Safety counter for army rolling:** Add a max iteration counter to the while loop in `roll_army()` to prevent infinite loops if composition rules are misconfigured. Can wait until Phase 5 when we add multiple rulesets.

## Phase 1 Checkpoint: PASSED ✅

All requirements met:
- [x] Data classes defined and tested
- [x] Ruleset loader validates and loads MVP JSON
- [x] Army roller respects composition rules with injected dice
- [x] 19 automated tests pass
- [x] Demo script rolls armies successfully

**Ready to proceed to Phase 2 (Army rolling UI).**
