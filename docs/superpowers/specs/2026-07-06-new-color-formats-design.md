# DelphiColorPreview — New color formats design

**Date:** 2026-07-06
**Status:** Approved (pending spec review)

## Goal

Recognize three additional color-literal families in the RAD Studio editor swatch
plugin, on top of the families already supported (`clXXX`, `RGB()`,
`TAlphaColorRec.X` / `TAlphaColors.X`, `claXXX`, `$hex` 6/8 digits):

1. **Web-hex string** — `'#RGB'` / `'#RRGGBB'` inside string literals.
2. **`TColorRec.X`** — VCL named-color record members (`System.UITypes`).
3. **Decimal integer** — a raw `TColor`/`TAlphaColor` integer, recognized **only**
   in a color-assignment context (the concrete case that motivated this work).

### Motivating example

```pascal
ModuleLanguage.StyleStartCell.Color := 16708849;   // $FEF4F1 (BGR) -> RGB(F1,F4,FE)
ModuleLanguage.StyleEndCell.Color   := 15988209;   // $F3F5F1 (BGR) -> RGB(F1,F5,F3)
TextColor := 15988209;                              // LHS identifier ends with "Color"
```

## Scope

### In scope
- Web-hex strings `'#RGB'` and `'#RRGGBB'` (fixed RGB/web byte order, opaque).
- `TColorRec.X` member colors (VCL web palette), reusing the existing `cla`-name resolver.
- Context-gated decimal integers, in **one** context only:
  - `<colorTarget> := <decimal>` where `<colorTarget>` is an identifier (optionally
    qualified, e.g. `A.B.Color`) whose **final segment ends with `Color`**
    (case-insensitive): `Color`, `TextColor`, `FontColor`, ... — but **not**
    `ColorIndex` / `ColorCount` (they do not end in "Color").
  - The decimal must be the **direct operand** of the `:=` (first lexeme after `:=`,
    skipping spaces, is the number). `Color := SomeFunc(16708849)` does **not** match
    (after `:=` comes a call, not a number), so the call argument is never lit.

### Deliberately excluded (too risky / too noisy)
- **Decimals passed to functions or in casts** — `SomeFunc(16708849)`,
  `TColor(16708849)`, `TAlphaColor(16708849)`. Without the real type there is no
  reliable signal, and opening the picker on a non-color argument risks an accidental
  edit (e.g. `Sleep(1000)` → `Sleep(16708849)`). Not recognized.
- **Decimals "as a range" anywhere** — every integer in `0..16_777_215` would light
  up. Rejected: pure primaries are small numbers (`clRed` = `$0000FF` = 255,
  `clLime` = `$00FF00` = 65280, black = 0), so no magnitude threshold separates
  colors from sizes/counts/IDs. Huge noise, no clean gate.
- **Typed const/field default** `<name>: TColor = <decimal>;` — zero-noise (the type
  is explicit) but excluded from the MVP per the "assignment only" decision. Candidate
  future extension.

### Out of scope (deferred, flagged for later)
- **`TColors.X`** — no such type exists in the RAD Studio RTL, and no definition or
  usage was found in the ResiXE library or `C:\Progetti\Trunk`. The record-member
  resolver leaves a disabled slot for it; it can be enabled once the user supplies
  the defining unit and its member→value mapping.
- **Web 8-digit `#RRGGBBAA`** — web puts alpha last, unlike FMX ARGB; needs its own
  parsing branch. Not in this iteration.
- **System-color decimals** — a decimal `TColor` whose high byte is `$FF` is a VCL
  system-color mask; its RGB depends on the running theme, so no swatch is drawn.

## Architecture

The parser is rewritten from a character-by-character single-pass scanner into a
**statement-aware tokenizer** (approach C). This is the chosen approach despite
being the largest change, so the context rule (the assignment target that gates a
decimal literal) is expressed cleanly instead of via ad-hoc character state.

The rewrite is internal to `ColorPreview.Parser.pas`. The unit stays **per-line**
(the notifier paints per visible line; color assignments are single-line in
practice) and the **public API is unchanged**, so `ColorPreview.Notifier.pas`,
`ColorPreview.Render.pas` and the picker need only additive changes.

```pascal
function FindColorTokens(const aLineText: string; aRgbOrder: Boolean): TColorTokens;   // unchanged signature
function FormatColorLiteral(const aToken: TColorToken; aRgbOrder: Boolean): string;    // new kinds handled
function HexUsesRgbOrder(const aToken: TColorToken; aEffective6: Boolean): Boolean;    // new kinds handled
```

### Two internal stages

**Stage 1 — Lexer.** Scan the line once into `TArray<TLexeme>`. Each lexeme:
`Kind` (`lkIdent`, `lkNumber`, `lkHex`, `lkString`, `lkSymbol`, `lkOther`),
`StartCol`, `Length`, `Text`. Symbols captured: `.`, `:=`, `(`, `)`, `,`, `;`.
String literals are captured whole (`'...'`).

**Stage 2 — Recognizer.** Walk the lexeme stream with lookahead/lookbehind and
emit `TColorToken[]` (same record as today). All context rules live here.

### Regression parity

Before the rewrite, capture the current `FindColorTokens` output over the existing
`ColorSamples.txt` as a baseline. The new tokenizer must produce **byte-identical
tokens** for every already-supported family.

## Recognition rules

Emit a `TColorToken` when the lexeme stream matches:

### Existing families (parity, unchanged semantics)
- `lkIdent` = `clXXX` → `IdentToColor` → `ckVclName`
- `lkIdent` = `claXXX` → `IdentToAlphaColor` → `ckAlphaName`
- `lkIdent` = `RGB` then `( num , num , num )` → `ckRgbCall`
- `lkHex` 6/8 digits → `ckVclHex` / `ckRgbHex` (byte order + high-byte auto-detect
  exactly as today)

### New — record member (generalized resolver)
- `lkIdent` (a known color-record name) + `.` + `lkIdent` (member).
- Resolver table: record name → resolution function:
  - `TColorRec` → `IdentToAlphaColor('cla' + member)` (web palette; drop alpha) →
    `ckVclName` with `Prefix = 'TColorRec.'`
  - `TAlphaColorRec`, `TAlphaColors` → existing `cla`-path → `ckAlphaName` (unchanged)
  - `TColors` → **disabled slot** (see out of scope)
- Members that do not resolve (e.g. `TColorRec.SysWindow`, `TColorRec.Null`) produce
  no token.

### New — web-hex string
- `lkString` whose content matches `^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6})$`.
- `#RGB` shorthand expands per nibble (`#F80` → `#FF8800`).
- Byte order is fixed RGB/web; opaque. → `ckWebHex`. Span = the whole `'...'` literal.

### New — decimal integer (context-gated)
- Gate: `<colorTarget> := <lkNumber>` where the LHS final identifier ends with
  `Color` and the `lkNumber` is the **first lexeme after `:=`** (direct operand).
  No casts, no function arguments, no const declarations.
- Value interpretation mirrors the equivalent hex literal:
  - `<= $FFFFFF` → 6-digit rule: BGR or RGB per `EffectiveRgbOrder` (the file/mode
    order). `16708849` in a VCL file → BGR → `$FEF4F1` → RGB(F1,F4,FE).
  - `> $FFFFFF` → 8-digit rule: high-byte auto-detect → ARGB (as `ParseHex8`).
  - negative values → skipped (system colors).
- → `ckDecimal`.

## Data model

`TColorKind` gains two values:

```pascal
TColorKind = (ckVclName, ckVclHex, ckRgbCall, ckAlphaName, ckRgbHex,
              ckWebHex,     // '#RRGGBB' web string, fixed RGB, opaque (MVP)
              ckDecimal);   // context-gated decimal int; BGR or ARGB by magnitude
```

`TColorToken` keeps its current shape; existing fields are reused:
- `Prefix` carries `'TColorRec.'` for the VCL record family (write-back rebuilds
  `TColorRec.Name`). VCL record members stay `ckVclName` + `Prefix`; no extra kind.
- `HexDigits` for `ckDecimal` is set to 6 (24-bit) or 8 (ARGB) to drive write-back
  width and alpha, mirroring the hex families.
- `Alpha` is real only for ARGB decimals; `OPAQUE` otherwise.

## Write-back and picker

### `FormatColorLiteral` new cases
- `ckWebHex` → `'#' + RRGGBB` (quotes kept, RGB order fixed; `#RGB` normalizes to
  6 digits on edit).
- `ckDecimal` → `IntToStr` of the color integer; 24-bit BGR/RGB per effective order,
  or ARGB when 8-wide — same order resolution as hex, decimal output.
- `ckVclName` with `Prefix` set → `Prefix + WebName` (e.g. `TColorRec.Crimson`);
  fallback `$00BBGGRR` when the color no longer maps to a named member.

### `HexUsesRgbOrder` extension
- `ckWebHex` → always `True` (web order).
- `ckDecimal` → same rule as hex (8-wide keeps its detected family; 6-wide follows
  the effective order).

### PickerForm (`ColorPreview.PickerForm.pas`)
- One edit: `AlphaAllowed` also returns `True` for `ckDecimal` when ARGB (8-wide).
- `ckWebHex` stays opaque (alpha slider disabled).
- Preview, byte-order combo, and themed dialog work unchanged.

## Edge-case decisions
- `Color := SomeFunc(16708849)` — **no swatch** (after `:=` is a call, not a direct
  number; the argument is never lit — avoids accidental edits on non-colors).
- `TColor(16708849)`, `TAlphaColor(16708849)` — **no swatch** (casts excluded).
- `const C: TColor = 16708849;` — **no swatch** in the MVP (assignment only).
- `ColorIndex := 5;`, `ColorCount := 3;`, `Width := 16708849;` — **no swatch**
  (LHS does not end in "Color" / not a color target).
- `Font.Color := 16708849;`, `TextColor := 15988209;` — **swatch** (direct decimal
  operand assigned to a `*Color` target).

## Testing and rollout
- **Parity baseline** captured before the rewrite (see Regression parity).
- **New cases added to `ColorSamples.txt`:** `'#F80'`, `'#FF8800'`,
  `TColorRec.Crimson`, `Font.Color := 16708849;`, `TextColor := 15988209;`,
  `SomeCtrl.Color := 4278190080;` (ARGB in an FMX file), plus counter-examples that
  must **not** light up: `ColorIndex := 5;`, `Width := 16708849;`,
  `Color := SomeFunc(16708849);`, `TColor(16708849)`, `const C: TColor = 16708849;`.
- **Manual IDE verification:** rebuild the BPL with the IDE closed (the `F2039`
  close-exe-first rule), reopen, check gutter swatches and Shift+click → picker with
  family-preserving write-back, in both VCL and FMX units.

## Files touched
- `ColorPreview.Parser.pas` — rewrite (lexer + recognizer), new kinds, record
  resolver, `FormatColorLiteral` / `HexUsesRgbOrder` cases.
- `ColorPreview.PickerForm.pas` — extend `AlphaAllowed` for ARGB decimals.
- `ColorSamples.txt` — new sample lines + counter-examples.
- `README.md` — document the new families.
- Untouched: `ColorPreview.Notifier.pas`, `ColorPreview.Render.pas`,
  `ColorPreview.Settings.pas`, `ColorPreview.Register.pas`.
