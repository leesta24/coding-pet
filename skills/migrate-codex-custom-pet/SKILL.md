---
name: migrate-codex-custom-pet
description: Safely migrate a user-created or user-owned custom Codex pet into CodingPet's private local appearance library. Use when the user supplies an exact custom pet directory or identifies a customized pet under ~/.codex/pets; never use for Codex built-in pets, application assets, caches, or extracted proprietary artwork.
---

# Migrate a custom Codex pet

Copy only a user-created or user-owned Codex pet package into CodingPet's
private local library. Keep the source read-only and do not modify application
code.

## Confirm provenance first

Require both:

1. The user explicitly says they created, commissioned, or have permission to
   reuse the pet.
2. The user supplies either an exact directory or an exact pet ID under
   `${CODEX_HOME:-$HOME/.codex}/pets/<pet-id>`.

Do not crawl for candidates. Never inspect or extract `/Applications/Codex.app`,
application resources, caches, updater directories, binaries, private
frameworks, or built-in pets. If provenance is missing, ask one concise
ownership question and stop until answered.

## Inspect without modifying

- Do not edit, move, rename, or delete source files.
- Resolve the exact directory and reject symlinks or paths escaping it.
- Require regular `pet.json` and `spritesheet.webp` files.
- Record SHA-256 hashes before copying.
- Parse the manifest and require `spriteVersionNumber: 2`.
- Require a lowercase package ID matching the directory name.
- Require a safe relative spritesheet path.
- Decode and require a transparent `1536x2288` image with 8 columns, 11 rows,
  and `192x208` cells.

The expected rows are idle, right run, left run, wave, jump, failed, waiting,
working, review, and two rows of clockwise look directions.

If the package is older or incomplete, do not stretch or reinterpret it. Use
an original-art repair workflow only after reconfirming ownership, then migrate
the resulting validated v2 package.

## Copy into CodingPet

Use this destination:

```text
~/Library/Application Support/CodingPet/Pets/<pet-id>/
```

Before copying:

- reject a collision with an unrelated destination package;
- create the parent directory if needed;
- copy only `pet.json` and its referenced spritesheet;
- do not copy prompts, QA output, Codex preferences, hooks, logs, or executable
  files.

After copying, hash both destination files and confirm they match the source.
Do not recompress, crop, recolor, watermark, or otherwise transform a valid v2
package during migration.

## Verify in CodingPet

Restart CodingPet, open **Settings → Appearance**, and confirm:

- the display name appears;
- selection persists after another restart;
- idle, blocked, pending-input, running, and ready states render correctly;
- disabled animation shows a stable frame;
- transparency, scale, and baseline remain consistent.

## Refuse unsafe migrations

Refuse when the requested pet is built in to Codex, points into an application
bundle or cache, has unclear ownership, escapes its source directory, or fails
v2 validation. Offer `create-coding-pet-appearance` to make an original
replacement.

## Completion criteria

Finish only when ownership is explicit, the source remained untouched, hashes
match, the package is v2-valid, CodingPet lists it, and no pet asset was added
to the repository or a release bundle.
