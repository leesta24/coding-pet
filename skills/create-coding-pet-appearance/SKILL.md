---
name: create-coding-pet-appearance
description: Create and install an original or user-owned animated v2 pet for the native CodingPet macOS app. Use when the user asks Codex to design a new CodingPet character, turn owned character art into a desktop pet, generate a compatible sprite atlas, validate a pet package, or add a private appearance to CodingPet.
---

# Create a CodingPet appearance

Create an original animated character, validate its Codex-compatible v2
package, and install it into CodingPet's private local pet library. Do not
modify CodingPet session, hook, or navigation behavior.

## Protect artwork ownership

- Use only original artwork or files the user explicitly says they own or may
  adapt.
- Never extract, copy, trace, or inspect Codex built-in pet assets, application
  bundles, caches, binaries, update packages, or proprietary source code.
- If the user requests a protected or built-in character without permission,
  offer an original alternative with only high-level traits.
- Stop when ownership or provenance is unclear.

## Define the appearance

Confirm or choose:

- a stable lowercase hyphenated `pet-id`;
- display name and short description;
- visual identity, palette, proportions, and signature features;
- owned reference images, if any.

Keep details readable at 64–160 points. Avoid text, logos, floor shadows,
detached effects, and background rectangles.

## Produce the v2 package

Use an available image-generation or sprite-animation workflow, or work from
user-provided frames. Produce exactly:

```text
<pet-id>/
├── pet.json
└── spritesheet.webp
```

Require:

- `spriteVersionNumber: 2`;
- a transparent `1536x2288` WebP atlas;
- 8 columns by 11 rows;
- `192x208` cells;
- the manifest `id` to equal the directory name;
- a safe relative `spritesheetPath` contained in the package.

Use this row contract:

| Row | Meaning |
| --- | --- |
| 0 | idle |
| 1 | running right |
| 2 | running left |
| 3 | waving |
| 4 | jumping |
| 5 | failed/blocked |
| 6 | waiting for user input |
| 7 | working |
| 8 | ready/review |
| 9–10 | 16 clockwise look directions |

Preserve character identity, scale, baseline, lighting, and transparency
across every cell. Do not generate a complete atlas in one uncontrolled image
request; assemble validated rows from consistent frames.

## Validate before installation

Check all of the following:

1. `pet.json` parses as JSON and contains the expected ID, display name,
   description, version, and relative spritesheet path.
2. Neither file is a symlink and the spritesheet path cannot escape the package.
3. The decoded image is exactly `1536x2288`.
4. Cells `(0, 0)` and `(10, 7)` are readable.
5. Rows 0, 5, 6, 7, and 8 clearly communicate CodingPet's five states.
6. No cell has an opaque background or clipped neighboring content.
7. A normal-size contact sheet and motion preview pass visual inspection.

Repair failed rows as a coherent animation sequence. Do not claim completion
when structural or visual validation fails.

## Install privately

Copy only the validated package to:

```text
~/Library/Application Support/CodingPet/Pets/<pet-id>/
```

Do not add private pet assets to the CodingPet Git repository or application
bundle. Preserve the source package and avoid overwriting an unrelated local
pet with the same ID.

Restart CodingPet, open **Settings → Appearance**, select the new pet, and
verify idle, running, pending-input, ready, and blocked rendering at small,
default, and large sizes.

## Completion criteria

Finish only when ownership is clear, the v2 package is structurally and
visually valid, the local source remains safe, CodingPet lists and persists the
appearance, and no private asset entered the repository.
