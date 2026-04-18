# Phase 2 Testing Instructions

## Automated Validation ✅

Scene instantiation test passed:
```bash
godot --headless --script tests/test_ui_instantiate.gd
# Result: PASSED - TestRoll scene loads and instantiates correctly
```

## Manual Testing (Godot Editor)

To test the army rolling UI:

1. **Open the project in Godot 4.6.2**
   ```bash
   cd godot/
   godot project.godot
   ```

2. **Run the client** (F5)
   - The entry scene will detect client mode
   - You should see "Turnip28 Simulator" main menu with a "Test Army Roller" button

3. **Click "Test Army Roller"**
   - Should navigate to the TestRoll scene
   - An army of 5-10 units should appear immediately

4. **Verify army display shows:**
   - [x] Unit number, name, and archetype (e.g., "[1] Sir Moldington (Toff)")
   - [x] Effective stats (M, S, C, R, W, Sv)
   - [x] Weapon name and type
   - [x] Mutations list with descriptions and stat modifiers

5. **Click "Re-roll Army"**
   - Should clear the display and roll a new random army
   - Army size and composition should vary

6. **Click "Back to Menu"**
   - Should return to the main menu

7. **Test multiple re-rolls**
   - Verify variety in army composition (different Toff counts, unit types, mutations)
   - Check that all armies have 1-2 Toffs (composition rule enforcement)

## Expected Results

- ✅ Main menu → TestRoll navigation works
- ✅ Army rolls on scene load
- ✅ Re-roll button generates new armies
- ✅ Back button returns to menu
- ✅ Units display correctly with stats, weapons, mutations
- ✅ Composition rules respected (5-10 units, 1-2 Toffs)

## Known Limitations (Expected)

- No networking (Phase 3)
- No visual sprites (Phase 4/5)
- Simple label-based display (MVP - good enough for Phase 2 checkpoint)

## Phase 2 Checkpoint

**Goal:** Run the client, click a button, see a random army, and re-roll.

**Status:** ✅ COMPLETE
