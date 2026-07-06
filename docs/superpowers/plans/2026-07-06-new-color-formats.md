# New Color Formats Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognize three new color-literal families in the RAD Studio swatch plugin — web-hex strings (`'#RGB'`/`'#RRGGBB'`), `TColorRec.X` member colors, and context-gated decimal integers assigned to a `*Color` target — by rewriting the parser into a statement-aware tokenizer.

**Architecture:** `ColorPreview.Parser.pas` is rewritten in two internal stages — a **lexer** (line → `TLexeme[]`) and a **recognizer** (lexemes → `TColorToken[]`). The public API (`FindColorTokens` / `FormatColorLiteral` / `HexUsesRgbOrder`) is unchanged, so `ColorPreview.Notifier.pas` and `ColorPreview.Render.pas` are untouched and `ColorPreview.PickerForm.pas` needs one additive edit. A new DUnitX console test project pins parser behavior (regression parity + new families).

**Tech Stack:** Delphi 12 (RAD Studio 23.0), VCL, DUnitX (console), `dcc32` via `rsvars.bat`.

**Spec:** `docs/superpowers/specs/2026-07-06-new-color-formats-design.md`

## Global Constraints

- **Delphi 12+ (RAD Studio 23.0)**; compiler `dcc32` version 36.0. Build via `rsvars.bat` in a single `cmd`.
- **House style (delphi-style):** `F` fields, `a` params, `L` locals (loop counters exempt); 2-space indent, no tabs; `Assigned(X)` never `X <> nil`; `String.Empty` / `X.IsEmpty` never `''`; new comments/identifiers in **English**; max 30 lines/function, max 3 nesting levels.
- **No fantasy code:** only RTL calls confirmed present are used — `IdentToColor`, `IdentToAlphaColor`, `TryStringToColor`, `ColorToString`, `AlphaColorToString`, `ColorToRGB`, `RGB`, `GetRValue`/`GetGValue`/`GetBValue`, `TAlphaColorRec` (all already used by the current unit).
- **Public API of `ColorPreview.Parser` must not change** its three exported signatures.
- **Regression parity:** every already-supported family (`clXXX`, `RGB()`, `TAlphaColorRec.X`, `TAlphaColors.X`, `claXXX`, `$hex` 6/8) must keep producing identical tokens.
- **Build command (BPL):** `cmd //c ".\build.bat"` from repo root (needs the IDE closed — `F2039` = exe/bpl in use).
- **Test build/run:** `cmd //c ".\Tests\run_parser_tests.bat"` from repo root.

---

## File Structure

- **Create** `Tests/ParserTests.dpr` — DUnitX console runner program.
- **Create** `Tests/TestColorParser.pas` — test fixture (parity + new families).
- **Create** `Tests/run_parser_tests.bat` — `rsvars` + `dcc32 -B` + run exe.
- **Create** `Tests/.gitignore` — ignore build artifacts (`*.exe`, `*.dcu`, `dcu/`).
- **Modify** `ColorPreview.Parser.pas` — full rewrite (lexer + recognizer), two new `TColorKind` values, record resolver, new format-back cases.
- **Modify** `ColorPreview.PickerForm.pas` — extend `AlphaAllowed` for ARGB decimals.
- **Modify** `ColorSamples.txt` — new sample lines + counter-examples.
- **Modify** `README.md` — document the new families.

Untouched: `ColorPreview.Notifier.pas`, `ColorPreview.Render.pas`, `ColorPreview.Settings.pas`, `ColorPreview.Register.pas`, `DelphiColorPreview.dpk`, `DelphiColorPreview.dproj`.

---

## Task 1: DUnitX test harness + regression-parity net

Establishes the safety net **before** the rewrite: a console DUnitX project that pins the current parser's output for every existing family. These tests must pass against the **current** (pre-rewrite) `ColorPreview.Parser.pas`.

**Files:**
- Create: `Tests/ParserTests.dpr`
- Create: `Tests/TestColorParser.pas`
- Create: `Tests/run_parser_tests.bat`
- Create: `Tests/.gitignore`

**Interfaces:**
- Consumes: `ColorPreview.Parser` public API — `FindColorTokens(const aLineText: string; aRgbOrder: Boolean): TColorTokens`, and record `TColorToken` fields `StartCol, Length, Color, Alpha, HexDigits, Prefix, Kind: TColorKind`, `TColorKind = (ckVclName, ckVclHex, ckRgbCall, ckAlphaName, ckRgbHex)`.
- Produces: a runnable `Tests/ParserTests.exe` returning exit code 0 on all-pass, 1 otherwise; helper `FindColorTokens` usage pattern reused by later tasks.

- [ ] **Step 1: Create the runner program**

Create `Tests/ParserTests.dpr`:

```pascal
program ParserTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  ColorPreview.Parser in '..\ColorPreview.Parser.pas',
  TestColorParser in 'TestColorParser.pas';

var
  LRunner  : ITestRunner;
  LResults : IRunResults;
begin
  LRunner := TDUnitX.CreateRunner;
  LRunner.AddLogger(TDUnitXConsoleLogger.Create(True));
  LResults := LRunner.Execute;
  if not LResults.AllPassed then
    ExitCode := 1;
end.
```

- [ ] **Step 2: Create the parity fixture**

Create `Tests/TestColorParser.pas`. `TColorKind` ordinals are compared by `Ord` so the tests do not depend on the enum being imported into scope beyond `ColorPreview.Parser`.

```pascal
unit TestColorParser;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TColorParserTests = class
  public
    // --- regression parity (existing families) ---
    [Test] procedure VclName_ClRed;
    [Test] procedure RgbCall_Parsed;
    [Test] procedure Hex6_BgrMode;
    [Test] procedure Hex6_RgbMode;
    [Test] procedure Hex8_AutoArgb;
    [Test] procedure Hex8_AutoVcl;
    [Test] procedure AlphaName_Cla;
    [Test] procedure AlphaRec_Member;
    [Test] procedure TooShortHex_NoToken;
    [Test] procedure PlainNumber_NoToken;
  end;

implementation

uses
  System.UITypes,
  Vcl.Graphics,
  ColorPreview.Parser;

procedure TColorParserTests.VclName_ClRed;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  FError := clRed;', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckVclName), Ord(L[0].Kind));
  Assert.AreEqual(Integer(clRed), Integer(L[0].Color));
end;

procedure TColorParserTests.RgbCall_Parsed;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  M := RGB(255, 0, 0);', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckRgbCall), Ord(L[0].Kind));
  Assert.AreEqual(Integer(RGB(255, 0, 0)), Integer(L[0].Color));
end;

procedure TColorParserTests.Hex6_BgrMode;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  P := $00FF8040;', False); // 8-digit VCL, high byte 0
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckVclHex), Ord(L[0].Kind));
end;

procedure TColorParserTests.Hex6_RgbMode;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  W := $C0FFEE;', True); // 6-digit, RGB order
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(6, L[0].HexDigits);
  Assert.AreEqual(Integer(RGB($C0, $FF, $EE)), Integer(L[0].Color));
end;

procedure TColorParserTests.Hex8_AutoArgb;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  X := $80FF0000;', False); // high byte <> 0 -> ARGB
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckRgbHex), Ord(L[0].Kind));
  Assert.AreEqual(128, Integer(L[0].Alpha));
end;

procedure TColorParserTests.Hex8_AutoVcl;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  X := $00336699;', True); // high byte 0 -> VCL even in RGB mode
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckVclHex), Ord(L[0].Kind));
end;

procedure TColorParserTests.AlphaName_Cla;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  A := claRed;', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckAlphaName), Ord(L[0].Kind));
end;

procedure TColorParserTests.AlphaRec_Member;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  A := TAlphaColorRec.Blue;', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckAlphaName), Ord(L[0].Kind));
  Assert.AreEqual('TAlphaColorRec.', L[0].Prefix);
end;

procedure TColorParserTests.TooShortHex_NoToken;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  Flags := $80;', False);
  Assert.AreEqual(0, Length(L));
end;

procedure TColorParserTests.PlainNumber_NoToken;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  Count := 12345;', False);
  Assert.AreEqual(0, Length(L));
end;

initialization
  TDUnitX.RegisterTestFixture(TColorParserTests);

end.
```

- [ ] **Step 3: Create the build/run script**

Create `Tests/run_parser_tests.bat` (compiles from inside `Tests` so relative `..` resolves; `dcc32` finds RTL/VCL/DUnitX from the default library path — verified):

```bat
@echo off
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\23.0\bin\rsvars.bat"
cd /d "%~dp0"
if not exist dcu mkdir dcu
dcc32 -B -NUdcu -E. ParserTests.dpr
if errorlevel 1 exit /b 1
ParserTests.exe
```

- [ ] **Step 4: Create Tests/.gitignore**

Create `Tests/.gitignore`:

```
*.exe
*.dcu
dcu/
*.map
```

- [ ] **Step 5: Run the parity suite against the CURRENT parser**

Run: `cmd //c ".\Tests\run_parser_tests.bat"`
Expected: compiler prints `... lines, ... seconds`, then DUnitX prints `Tests Passed  : 10`, `Tests Failed  : 0`, and the process exits 0. If any parity test fails, the test encodes an assumption the current parser does not meet — fix the test to match current behavior before continuing (this is the baseline).

- [ ] **Step 6: Commit**

```bash
git add Tests/ParserTests.dpr Tests/TestColorParser.pas Tests/run_parser_tests.bat Tests/.gitignore
git commit -m "test: DUnitX console parity net for the color parser"
```

---

## Task 2: Rewrite the parser into lexer + recognizer (parity only)

Replace the character-by-character scanner with a lexer + recognizer, reproducing **only** the existing families. The Task 1 suite must stay green — this is a refactor under a safety net.

**Files:**
- Modify: `ColorPreview.Parser.pas` (full rewrite of the implementation; interface unchanged except two enum values reserved for later tasks are NOT added yet)
- Test: `Tests/TestColorParser.pas` (existing parity tests, unchanged)

**Interfaces:**
- Consumes: RTL as listed in Global Constraints.
- Produces (internal, used by Tasks 3–5):
  - `TLexKind = (lkIdent, lkNumber, lkHex, lkString, lkSymbol)`
  - `TLexeme = record Kind: TLexKind; StartCol: Integer; Text: string; end;`
  - `TLexemes = TArray<TLexeme>;`
  - `function Lex(const aText: string): TLexemes;`
  - `function IsSym(const aLex: TLexemes; aIdx: Integer; const aSym: string): Boolean;`
  - `function RecognizeAt(const aLex: TLexemes; aIdx: Integer; aRgbOrder: Boolean; out aToken: TColorToken; out aConsumed: Integer): Boolean;`
  - helpers `MakeAlphaValue`, `FormatHex`, `FormatAlphaName`, `ParseHex8`, `ParseRgbHex` retained verbatim from the current unit.

- [ ] **Step 1: Replace `ColorPreview.Parser.pas` with the rewritten unit**

Overwrite the whole file with:

```pascal
unit ColorPreview.Parser;

{ Scans a single source line and extracts the color literals it contains, and
  formats a color value back into a literal.

  The line is first lexed into a token stream (Lex), then the recognizer walks
  that stream and emits color tokens. This makes context rules (e.g. a decimal
  assigned to a *Color target) straightforward instead of ad-hoc character state.

  Recognized literal families:
    - VCL clXXX constants               (BGR, order-fixed)
    - RGB(r,g,b) calls, integer args     (channels, order-fixed)
    - FMX TAlphaColor named consts       (ARGB, order-fixed):
        claXXX, TAlphaColorRec.X, TAlphaColors.X
    - $ hex literals                     (BGR or RGB, per the byte-order switch) }

interface

uses
  Vcl.Graphics;

type
  /// <summary>Kind of color literal found in source code.</summary>
  TColorKind = (ckVclName, ckVclHex, ckRgbCall, ckAlphaName, ckRgbHex);

  /// <summary>A color literal located inside a single source line.</summary>
  TColorToken = record
    StartCol  : Integer;    // 1-based column of the first character
    Length    : Integer;    // number of characters the literal spans
    Color     : TColor;     // display color (BGR, opaque) - always valid
    Alpha     : Byte;       // 255 for non-alpha families; real alpha otherwise
    HexDigits : Integer;    // digit count of a hex literal (0 when not hex)
    Prefix    : string;     // family prefix as typed: 'cla' | 'TAlphaColorRec.' | 'TAlphaColors.'
    Kind      : TColorKind;
  end;

  TColorTokens = TArray<TColorToken>;

/// <summary>
///   Scans a single source line and returns every color literal it contains.
///   When aRgbOrder is True, bare hex literals are read in RGB/web byte order
///   ($RRGGBB / $AARRGGBB); otherwise in VCL BGR order ($00BBGGRR).
/// </summary>
function FindColorTokens(const aLineText: string; aRgbOrder: Boolean): TColorTokens;

/// <summary>
///   Formats a color token back into source text, keeping its original family.
///   For the hex family the byte order follows aRgbOrder.
/// </summary>
function FormatColorLiteral(const aToken: TColorToken; aRgbOrder: Boolean): string;

/// <summary>
///   Returns the RGB-order flag to use when writing a hex token back.
/// </summary>
function HexUsesRgbOrder(const aToken: TColorToken; aEffective6: Boolean): Boolean;

implementation

uses
  System.SysUtils,
  System.Character,
  System.UITypes,
  System.UIConsts,
  System.Generics.Collections,
  Winapi.Windows;

const
  MIN_HEX_DIGITS   = 6;     // shortest hex treated as a color ($RRGGBB)
  MAX_HEX_DIGITS   = 8;     // longest hex treated as a color ($00BBGGRR / $AARRGGBB)
  RGB_ARG_COUNT    = 3;
  RGB_MAX_CHANNEL  = 255;
  OPAQUE           = 255;
  ALPHA_HEX_DIGITS = 8;     // hex width that carries an alpha byte
  RGB_HEX_DIGITS   = 6;

type
  TLexKind = (lkIdent, lkNumber, lkHex, lkString, lkSymbol);

  TLexeme = record
    Kind     : TLexKind;
    StartCol : Integer;     // 1-based column of the first character
    Text     : string;      // exact source text of the lexeme
  end;

  TLexemes = TArray<TLexeme>;

{ ---- character helpers ---- }

function IsIdentStart(aCh: Char): Boolean;
begin
  Result := aCh.IsLetter or (aCh = '_');
end;

function IsIdentChar(aCh: Char): Boolean;
begin
  Result := aCh.IsLetterOrDigit or (aCh = '_');
end;

function IsHexDigit(aCh: Char): Boolean;
begin
  Result := CharInSet(aCh, ['0'..'9', 'A'..'F', 'a'..'f']);
end;

function MakeLex(aKind: TLexKind; aStart: Integer; const aText: string): TLexeme;
begin
  Result.Kind := aKind;
  Result.StartCol := aStart;
  Result.Text := aText;
end;

{ ---- lexer ---- }

function LexWord(const aText: string; var aPos: Integer): TLexeme;
var
  LStart: Integer;
begin
  LStart := aPos;
  while (aPos <= aText.Length) and IsIdentChar(aText[aPos]) do
    Inc(aPos);
  Result := MakeLex(lkIdent, LStart, aText.Substring(LStart - 1, aPos - LStart));
end;

function LexHex(const aText: string; var aPos: Integer): TLexeme;
var
  LStart: Integer;
begin
  LStart := aPos;
  Inc(aPos);                                    // skip '$'
  while (aPos <= aText.Length) and IsHexDigit(aText[aPos]) do
    Inc(aPos);
  Result := MakeLex(lkHex, LStart, aText.Substring(LStart - 1, aPos - LStart));
end;

function LexNumber(const aText: string; var aPos: Integer): TLexeme;
var
  LStart: Integer;
begin
  LStart := aPos;
  while (aPos <= aText.Length) and aText[aPos].IsDigit do
    Inc(aPos);
  Result := MakeLex(lkNumber, LStart, aText.Substring(LStart - 1, aPos - LStart));
end;

{ Reads a Pascal string literal (aPos at the opening quote); '' stays embedded. }
function LexString(const aText: string; var aPos: Integer): TLexeme;
var
  LStart: Integer;
begin
  LStart := aPos;
  Inc(aPos);                                    // skip opening quote
  while aPos <= aText.Length do
  begin
    if aText[aPos] <> '''' then
      Inc(aPos)
    else if (aPos < aText.Length) and (aText[aPos + 1] = '''') then
      Inc(aPos, 2)                              // doubled quote
    else
    begin
      Inc(aPos);                                // closing quote
      Break;
    end;
  end;
  Result := MakeLex(lkString, LStart, aText.Substring(LStart - 1, aPos - LStart));
end;

function LexSymbol(const aText: string; var aPos: Integer): TLexeme;
var
  LStart: Integer;
begin
  LStart := aPos;
  if (aText[aPos] = ':') and (aPos < aText.Length) and (aText[aPos + 1] = '=') then
  begin
    Inc(aPos, 2);
    Exit(MakeLex(lkSymbol, LStart, ':='));
  end;
  Result := MakeLex(lkSymbol, LStart, aText[aPos]);   // any other single char
  Inc(aPos);
end;

function Lex(const aText: string): TLexemes;
var
  LList : TList<TLexeme>;
  LPos  : Integer;
  LCh   : Char;
begin
  LList := TList<TLexeme>.Create;
  try
    LPos := 1;
    while LPos <= aText.Length do
    begin
      LCh := aText[LPos];
      if LCh = ' ' then
        Inc(LPos)
      else if IsIdentStart(LCh) then
        LList.Add(LexWord(aText, LPos))
      else if LCh = '$' then
        LList.Add(LexHex(aText, LPos))
      else if LCh.IsDigit then
        LList.Add(LexNumber(aText, LPos))
      else if LCh = '''' then
        LList.Add(LexString(aText, LPos))
      else
        LList.Add(LexSymbol(aText, LPos));
    end;
    Result := LList.ToArray;
  finally
    LList.Free;
  end;
end;

{ ---- lexeme-stream helpers ---- }

function IsSym(const aLex: TLexemes; aIdx: Integer; const aSym: string): Boolean;
begin
  Result := (aIdx >= 0) and (aIdx <= High(aLex)) and
            (aLex[aIdx].Kind = lkSymbol) and (aLex[aIdx].Text = aSym);
end;

function ExpectChannel(const aLex: TLexemes; aIdx: Integer; out aValue: Integer): Boolean;
begin
  Result := (aIdx <= High(aLex)) and (aLex[aIdx].Kind = lkNumber);
  if Result then
  begin
    aValue := StrToIntDef(aLex[aIdx].Text, -1);
    Result := (aValue >= 0) and (aValue <= RGB_MAX_CHANNEL);
  end;
end;

{ ---- value parsers (retained) ---- }

{ Parses a bare hex literal in RGB/web order: $RRGGBB (opaque) or $AARRGGBB. }
function ParseRgbHex(const aLiteral: string; aDigits: Integer; var aToken: TColorToken): Boolean;
var
  LValue : Int64;
  LR, LG, LB, LA : Byte;
begin
  Result := False;
  if (aDigits <> MIN_HEX_DIGITS) and (aDigits <> ALPHA_HEX_DIGITS) then
    Exit;
  LValue := StrToInt64Def(aLiteral, -1);
  if LValue < 0 then
    Exit;
  if aDigits = ALPHA_HEX_DIGITS then
    LA := Byte(LValue shr 24)
  else
    LA := OPAQUE;
  LR := Byte(LValue shr 16);
  LG := Byte(LValue shr 8);
  LB := Byte(LValue);
  aToken.Color := RGB(LR, LG, LB);
  aToken.Alpha := LA;
  aToken.Kind  := ckRgbHex;
  Result := True;
end;

{ Parses an 8-digit hex, auto-detecting the family by its high byte. }
function ParseHex8(const aLiteral: string; var aToken: TColorToken): Boolean;
var
  LValue : Int64;
  LHigh  : Byte;
begin
  Result := False;
  LValue := StrToInt64Def(aLiteral, -1);
  if LValue < 0 then
    Exit;
  LHigh := Byte(LValue shr 24);
  if LHigh = 0 then
  begin
    aToken.Color := TColor(LValue);   // $00BBGGRR - VCL
    aToken.Alpha := OPAQUE;
    aToken.Kind  := ckVclHex;
  end
  else
  begin
    aToken.Color := RGB(Byte(LValue shr 16), Byte(LValue shr 8), Byte(LValue));
    aToken.Alpha := LHigh;
    aToken.Kind  := ckRgbHex;         // $AARRGGBB - FMX
  end;
  Result := True;
end;

function BuildHexToken(const aLex: TLexeme; aRgbOrder: Boolean; out aToken: TColorToken): Boolean;
var
  LDigits : Integer;
  LColor  : TColor;
begin
  Result := False;
  LDigits := aLex.Text.Length - 1;              // minus the '$'
  if (LDigits < MIN_HEX_DIGITS) or (LDigits > MAX_HEX_DIGITS) then
    Exit;
  aToken.StartCol  := aLex.StartCol;
  aToken.Length    := aLex.Text.Length;
  aToken.HexDigits := LDigits;
  aToken.Prefix    := String.Empty;
  if LDigits = ALPHA_HEX_DIGITS then
    Result := ParseHex8(aLex.Text, aToken)
  else if aRgbOrder then
    Result := ParseRgbHex(aLex.Text, LDigits, aToken)
  else
  begin
    Result := TryStringToColor(aLex.Text, LColor);
    if Result then
    begin
      aToken.Color := LColor;
      aToken.Alpha := OPAQUE;
      aToken.Kind  := ckVclHex;
    end;
  end;
end;

{ ---- named-color / record-member recognizers ---- }

procedure FillAlphaToken(out aToken: TColorToken; aValue: TAlphaColor; const aPrefix: string);
var
  LRec: TAlphaColorRec;
begin
  LRec := TAlphaColorRec.Create(aValue);
  aToken.Color     := RGB(LRec.R, LRec.G, LRec.B);
  aToken.Alpha     := LRec.A;
  aToken.HexDigits := 0;
  aToken.Prefix    := aPrefix;
  aToken.Kind      := ckAlphaName;
end;

{ Resolves RecordName.Member for the FMX alpha-color records. Extended in a
  later task to also handle TColorRec (VCL). }
function ResolveRecordMember(const aRecord, aMember: string; out aToken: TColorToken): Boolean;
var
  LColorInt: Integer;
begin
  Result := False;
  if SameText(aRecord, 'TAlphaColorRec') or SameText(aRecord, 'TAlphaColors') then
    if IdentToAlphaColor('cla' + aMember, LColorInt) then
    begin
      FillAlphaToken(aToken, TAlphaColor(LColorInt), aRecord + '.');
      Result := True;
    end;
end;

function TryRecordMember(const aLex: TLexemes; aStart: Integer;
  out aToken: TColorToken; out aConsumed: Integer): Boolean;
begin
  Result := False;
  aConsumed := 1;
  if not (IsSym(aLex, aStart + 1, '.') and (aStart + 2 <= High(aLex)) and
          (aLex[aStart + 2].Kind = lkIdent)) then
    Exit;
  if not ResolveRecordMember(aLex[aStart].Text, aLex[aStart + 2].Text, aToken) then
    Exit;
  aToken.StartCol := aLex[aStart].StartCol;
  aToken.Length   := (aLex[aStart + 2].StartCol + aLex[aStart + 2].Text.Length) -
                     aLex[aStart].StartCol;
  aConsumed := 3;
  Result := True;
end;

function TryRgbCall(const aLex: TLexemes; aStart: Integer;
  out aToken: TColorToken; out aConsumed: Integer): Boolean;
var
  LR, LG, LB : Integer;
  LClose     : Integer;
begin
  Result := False;
  aConsumed := 1;
  if not IsSym(aLex, aStart + 1, '(') then Exit;
  if not ExpectChannel(aLex, aStart + 2, LR) then Exit;
  if not IsSym(aLex, aStart + 3, ',') then Exit;
  if not ExpectChannel(aLex, aStart + 4, LG) then Exit;
  if not IsSym(aLex, aStart + 5, ',') then Exit;
  if not ExpectChannel(aLex, aStart + 6, LB) then Exit;
  if not IsSym(aLex, aStart + 7, ')') then Exit;
  LClose := aStart + 7;
  aToken.StartCol  := aLex[aStart].StartCol;
  aToken.Length    := (aLex[LClose].StartCol + 1) - aLex[aStart].StartCol;
  aToken.Color     := RGB(LR, LG, LB);
  aToken.Alpha     := OPAQUE;
  aToken.HexDigits := 0;
  aToken.Prefix    := String.Empty;
  aToken.Kind      := ckRgbCall;
  aConsumed := 8;
  Result := True;
end;

function TryNamedColor(const aLex: TLexemes; aStart: Integer;
  out aToken: TColorToken; out aConsumed: Integer): Boolean;
var
  LWord     : string;
  LColorInt : Integer;
begin
  Result := False;
  aConsumed := 1;
  LWord := aLex[aStart].Text;
  if (LWord.Length > 2) and LWord.StartsWith('cl', True) and
     IdentToColor(LWord, LColorInt) then
  begin
    aToken.StartCol  := aLex[aStart].StartCol;
    aToken.Length    := LWord.Length;
    aToken.Color     := TColor(LColorInt);
    aToken.Alpha     := OPAQUE;
    aToken.HexDigits := 0;
    aToken.Prefix    := String.Empty;
    aToken.Kind      := ckVclName;
    Exit(True);
  end;
  if (LWord.Length > 3) and LWord.StartsWith('cla', True) and
     IdentToAlphaColor(LWord, LColorInt) then
  begin
    FillAlphaToken(aToken, TAlphaColor(LColorInt), 'cla');
    aToken.StartCol := aLex[aStart].StartCol;
    aToken.Length   := LWord.Length;
    Exit(True);
  end;
end;

function TryIdent(const aLex: TLexemes; aStart: Integer;
  out aToken: TColorToken; out aConsumed: Integer): Boolean;
begin
  if TryRecordMember(aLex, aStart, aToken, aConsumed) then
    Exit(True);
  if SameText(aLex[aStart].Text, 'RGB') then
    Exit(TryRgbCall(aLex, aStart, aToken, aConsumed));
  Result := TryNamedColor(aLex, aStart, aToken, aConsumed);
end;

{ ---- top-level recognizer ---- }

function RecognizeAt(const aLex: TLexemes; aIdx: Integer; aRgbOrder: Boolean;
  out aToken: TColorToken; out aConsumed: Integer): Boolean;
begin
  Result := False;
  aConsumed := 1;
  case aLex[aIdx].Kind of
    lkIdent : Result := TryIdent(aLex, aIdx, aToken, aConsumed);
    lkHex   : Result := BuildHexToken(aLex[aIdx], aRgbOrder, aToken);
  end;
end;

function FindColorTokens(const aLineText: string; aRgbOrder: Boolean): TColorTokens;
var
  LLex      : TLexemes;
  LOut      : TList<TColorToken>;
  LIdx      : Integer;
  LTok      : TColorToken;
  LConsumed : Integer;
begin
  if aLineText.IsEmpty then
    Exit(nil);
  LLex := Lex(aLineText);
  LOut := TList<TColorToken>.Create;
  try
    LIdx := 0;
    while LIdx <= High(LLex) do
    begin
      if RecognizeAt(LLex, LIdx, aRgbOrder, LTok, LConsumed) then
        LOut.Add(LTok);
      Inc(LIdx, LConsumed);
    end;
    Result := LOut.ToArray;
  finally
    LOut.Free;
  end;
end;

{ ---- format back ---- }

function MakeAlphaValue(aRgb: TColor; aAlpha: Byte): Cardinal;
begin
  Result := (Cardinal(aAlpha) shl 24) or (Cardinal(GetRValue(aRgb)) shl 16) or
            (Cardinal(GetGValue(aRgb)) shl 8) or Cardinal(GetBValue(aRgb));
end;

function FormatAlphaName(const aToken: TColorToken; aRgb: TColor): string;
var
  LValue : Cardinal;
  LName  : string;
begin
  LValue := MakeAlphaValue(aRgb, aToken.Alpha);
  LName := AlphaColorToString(TAlphaColor(LValue));
  if not LName.StartsWith('cla', True) then
    Exit('$' + IntToHex(LValue, ALPHA_HEX_DIGITS));
  if aToken.Prefix.IsEmpty or SameText(aToken.Prefix, 'cla') then
    Result := LName
  else
    Result := aToken.Prefix + LName.Substring(3);
end;

function FormatHex(aRgb: TColor; aAlpha: Byte; aHexDigits: Integer; aRgbOrder: Boolean): string;
begin
  if not aRgbOrder then
    Exit('$' + IntToHex(aRgb, ALPHA_HEX_DIGITS));
  if (aAlpha < OPAQUE) or (aHexDigits = ALPHA_HEX_DIGITS) then
    Result := '$' + IntToHex(aAlpha, 2) + IntToHex(GetRValue(aRgb), 2) +
              IntToHex(GetGValue(aRgb), 2) + IntToHex(GetBValue(aRgb), 2)
  else
    Result := '$' + IntToHex(GetRValue(aRgb), 2) + IntToHex(GetGValue(aRgb), 2) +
              IntToHex(GetBValue(aRgb), 2);
end;

function FormatColorLiteral(const aToken: TColorToken; aRgbOrder: Boolean): string;
var
  LRgb: TColor;
begin
  LRgb := ColorToRGB(aToken.Color);
  case aToken.Kind of
    ckRgbCall:
      Result := Format('RGB(%d, %d, %d)', [GetRValue(LRgb), GetGValue(LRgb), GetBValue(LRgb)]);
    ckVclName:
      Result := ColorToString(aToken.Color);
    ckAlphaName:
      Result := FormatAlphaName(aToken, LRgb);
  else
    Result := FormatHex(LRgb, aToken.Alpha, aToken.HexDigits, aRgbOrder);
  end;
end;

function HexUsesRgbOrder(const aToken: TColorToken; aEffective6: Boolean): Boolean;
begin
  if aToken.HexDigits = ALPHA_HEX_DIGITS then
    Result := aToken.Kind = ckRgbHex
  else
    Result := aEffective6;
end;

end.
```

- [ ] **Step 2: Run the parity suite (must stay green)**

Run: `cmd //c ".\Tests\run_parser_tests.bat"`
Expected: `Tests Passed  : 10`, `Tests Failed  : 0`, exit 0. If any fail, the rewrite diverged from the current behavior — fix the recognizer, not the tests.

- [ ] **Step 3: Commit**

```bash
git add ColorPreview.Parser.pas
git commit -m "refactor: rewrite parser as lexer + recognizer (parity)"
```

---

## Task 3: Web-hex strings (`'#RGB'` / `'#RRGGBB'`)

**Files:**
- Modify: `ColorPreview.Parser.pas`
- Test: `Tests/TestColorParser.pas`

**Interfaces:**
- Consumes: `TLexeme`, `RecognizeAt` dispatch, `IntToHex`, `RGB`, `GetRValue/GetGValue/GetBValue`.
- Produces: enum value `ckWebHex`; `function BuildWebHexToken(const aLex: TLexeme; out aToken: TColorToken): Boolean;` (used only internally).

- [ ] **Step 1: Write failing tests**

Add to the fixture `interface` test list:

```pascal
    [Test] procedure WebHex_Six;
    [Test] procedure WebHex_ShortExpands;
    [Test] procedure WebHex_NonHex_NoToken;
```

Add the implementations:

```pascal
procedure TColorParserTests.WebHex_Six;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  S := ''#FF8800'';', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckWebHex), Ord(L[0].Kind));
  Assert.AreEqual(Integer(RGB($FF, $88, $00)), Integer(L[0].Color));
  Assert.AreEqual(9, L[0].Length); // '#FF8800' including both quotes = 9 chars
end;

procedure TColorParserTests.WebHex_ShortExpands;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  S := ''#F80'';', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Integer(RGB($FF, $88, $00)), Integer(L[0].Color));
end;

procedure TColorParserTests.WebHex_NonHex_NoToken;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  S := ''#pragma'';', False);
  Assert.AreEqual(0, Length(L));
end;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cmd //c ".\Tests\run_parser_tests.bat"`
Expected: FAIL — `ckWebHex` is undeclared (compile error) or the new tests fail. This confirms the tests exercise new behavior.

- [ ] **Step 3: Implement web-hex support**

In `ColorPreview.Parser.pas` interface, extend the enum:

```pascal
  TColorKind = (ckVclName, ckVclHex, ckRgbCall, ckAlphaName, ckRgbHex, ckWebHex);
```

Add these functions in the implementation, just before `RecognizeAt`:

```pascal
function IsWebHexDigits(const aDigits: string): Boolean;
var
  LCh: Char;
begin
  Result := (aDigits.Length = 3) or (aDigits.Length = 6);
  if not Result then
    Exit;
  for LCh in aDigits do
    if not IsHexDigit(LCh) then
      Exit(False);
end;

function ExpandShortHex(const aShort: string): string;
begin
  Result := aShort[1] + aShort[1] + aShort[2] + aShort[2] + aShort[3] + aShort[3];
end;

{ Recognizes a '#RGB' / '#RRGGBB' web color inside a string literal (fixed RGB). }
function BuildWebHexToken(const aLex: TLexeme; out aToken: TColorToken): Boolean;
var
  LInner : string;
  LHex   : string;
  LValue : Integer;
begin
  Result := False;
  LInner := aLex.Text;
  if (LInner.Length < 3) or (LInner.Chars[0] <> '''') then
    Exit;
  LInner := LInner.Substring(1, LInner.Length - 2);   // strip the quotes
  if (LInner.Length < 4) or (LInner.Chars[0] <> '#') then
    Exit;
  LHex := LInner.Substring(1);
  if not IsWebHexDigits(LHex) then
    Exit;
  if LHex.Length = 3 then
    LHex := ExpandShortHex(LHex);
  LValue := StrToIntDef('$' + LHex, -1);
  if LValue < 0 then
    Exit;
  aToken.StartCol  := aLex.StartCol;
  aToken.Length    := aLex.Text.Length;
  aToken.Color     := RGB(Byte(LValue shr 16), Byte(LValue shr 8), Byte(LValue));
  aToken.Alpha     := OPAQUE;
  aToken.HexDigits := RGB_HEX_DIGITS;
  aToken.Prefix    := String.Empty;
  aToken.Kind      := ckWebHex;
  Result := True;
end;
```

Add the `lkString` arm to `RecognizeAt`:

```pascal
  case aLex[aIdx].Kind of
    lkIdent : Result := TryIdent(aLex, aIdx, aToken, aConsumed);
    lkHex   : Result := BuildHexToken(aLex[aIdx], aRgbOrder, aToken);
    lkString: Result := BuildWebHexToken(aLex[aIdx], aToken);
  end;
```

Add a `FormatWebHex` and wire it into `FormatColorLiteral`. Add the function above `FormatColorLiteral`:

```pascal
function FormatWebHex(aRgb: TColor): string;
begin
  Result := '''#' + IntToHex(GetRValue(aRgb), 2) + IntToHex(GetGValue(aRgb), 2) +
            IntToHex(GetBValue(aRgb), 2) + '''';
end;
```

In `FormatColorLiteral`, add a case before the `else`:

```pascal
    ckAlphaName:
      Result := FormatAlphaName(aToken, LRgb);
    ckWebHex:
      Result := FormatWebHex(LRgb);
  else
```

In `HexUsesRgbOrder`, make web-hex always RGB (add at the top):

```pascal
function HexUsesRgbOrder(const aToken: TColorToken; aEffective6: Boolean): Boolean;
begin
  if aToken.Kind = ckWebHex then
    Exit(True);
  if aToken.HexDigits = ALPHA_HEX_DIGITS then
    Result := aToken.Kind = ckRgbHex
  else
    Result := aEffective6;
end;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cmd //c ".\Tests\run_parser_tests.bat"`
Expected: `Tests Passed  : 13`, `Tests Failed  : 0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add ColorPreview.Parser.pas Tests/TestColorParser.pas
git commit -m "feat: recognize web-hex color strings ('#RGB'/'#RRGGBB')"
```

---

## Task 4: `TColorRec.X` member colors

**Files:**
- Modify: `ColorPreview.Parser.pas`
- Test: `Tests/TestColorParser.pas`

**Interfaces:**
- Consumes: `ResolveRecordMember`, `FormatColorLiteral` (`ckVclName` branch), `AlphaColorToString`, `MakeAlphaValue`.
- Produces: `TColorRec.X` resolves to a `ckVclName` token with `Prefix = 'TColorRec.'`; `FormatVclName` helper.

- [ ] **Step 1: Write failing tests**

Add to the fixture test list:

```pascal
    [Test] procedure ColorRec_Member;
    [Test] procedure ColorRec_RoundTrip;
    [Test] procedure Colors_Disabled;
```

Implementations:

```pascal
procedure TColorParserTests.ColorRec_Member;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  C := TColorRec.Crimson;', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckVclName), Ord(L[0].Kind));
  Assert.AreEqual('TColorRec.', L[0].Prefix);
end;

procedure TColorParserTests.ColorRec_RoundTrip;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  C := TColorRec.Crimson;', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual('TColorRec.Crimson', FormatColorLiteral(L[0], False));
end;

procedure TColorParserTests.Colors_Disabled;
var
  L: TColorTokens;
begin
  // TColors is a not-yet-mapped custom type -> no token until enabled
  L := FindColorTokens('  C := TColors.Red;', False);
  Assert.AreEqual(0, Length(L));
end;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cmd //c ".\Tests\run_parser_tests.bat"`
Expected: FAIL — `ColorRec_Member` finds 0 tokens and `ColorRec_RoundTrip` returns `clWebCrimson`/`$hex` instead of `TColorRec.Crimson`.

- [ ] **Step 3: Implement `TColorRec` resolution + prefixed format-back**

Add a filler for VCL record members, above `ResolveRecordMember`:

```pascal
procedure FillVclRecToken(out aToken: TColorToken; aValue: TAlphaColor; const aPrefix: string);
var
  LRec: TAlphaColorRec;
begin
  LRec := TAlphaColorRec.Create(aValue);
  aToken.Color     := RGB(LRec.R, LRec.G, LRec.B);   // opaque VCL color
  aToken.Alpha     := OPAQUE;
  aToken.HexDigits := 0;
  aToken.Prefix    := aPrefix;                        // 'TColorRec.'
  aToken.Kind      := ckVclName;
end;
```

Extend `ResolveRecordMember` (add the `TColorRec` branch; leave a comment slot for `TColors`):

```pascal
function ResolveRecordMember(const aRecord, aMember: string; out aToken: TColorToken): Boolean;
var
  LColorInt: Integer;
begin
  Result := False;
  if SameText(aRecord, 'TAlphaColorRec') or SameText(aRecord, 'TAlphaColors') then
  begin
    if IdentToAlphaColor('cla' + aMember, LColorInt) then
    begin
      FillAlphaToken(aToken, TAlphaColor(LColorInt), aRecord + '.');
      Result := True;
    end;
  end
  else if SameText(aRecord, 'TColorRec') then
  begin
    if IdentToAlphaColor('cla' + aMember, LColorInt) then
    begin
      FillVclRecToken(aToken, TAlphaColor(LColorInt), 'TColorRec.');
      Result := True;
    end;
  end;
  // 'TColors' -> disabled slot: add a name->value resolution here once the
  // defining unit and its member mapping are known.
end;
```

Replace the `ckVclName` branch of `FormatColorLiteral` so a set `Prefix` rebuilds `TColorRec.Name`. Add `FormatVclName` above `FormatColorLiteral`:

```pascal
function FormatVclName(const aToken: TColorToken; aRgb: TColor): string;
var
  LName: string;
begin
  if aToken.Prefix.IsEmpty then
    Exit(ColorToString(aToken.Color));
  LName := AlphaColorToString(TAlphaColor(MakeAlphaValue(aRgb, OPAQUE)));
  if LName.StartsWith('cla', True) then
    Result := aToken.Prefix + LName.Substring(3)                 // TColorRec.Crimson
  else
    Result := '$' + IntToHex(ColorToRGB(aToken.Color), ALPHA_HEX_DIGITS); // $00BBGGRR fallback
end;
```

Change the `ckVclName` line in `FormatColorLiteral`:

```pascal
    ckVclName:
      Result := FormatVclName(aToken, LRgb);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cmd //c ".\Tests\run_parser_tests.bat"`
Expected: `Tests Passed  : 16`, `Tests Failed  : 0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add ColorPreview.Parser.pas Tests/TestColorParser.pas
git commit -m "feat: recognize TColorRec.X named colors"
```

---

## Task 5: Context-gated decimal integers

**Files:**
- Modify: `ColorPreview.Parser.pas`
- Test: `Tests/TestColorParser.pas`

**Interfaces:**
- Consumes: `IsSym`, `RecognizeAt`, `FormatColorLiteral`, `HexUsesRgbOrder`.
- Produces: enum value `ckDecimal`; `function IsColorAssign(const aLex: TLexemes; aIdx: Integer): Boolean;`, `function BuildDecimalToken(const aLexNum: TLexeme; aRgbOrder: Boolean; out aToken: TColorToken): Boolean;`, `function FormatDecimal(...)`.

- [ ] **Step 1: Write failing tests**

Add to the fixture test list:

```pascal
    [Test] procedure Decimal_ColorAssign_Bgr;
    [Test] procedure Decimal_TextColor;
    [Test] procedure Decimal_RoundTrip;
    [Test] procedure Decimal_ArgbInRgbFile;
    [Test] procedure Decimal_NotColorTarget_NoToken;
    [Test] procedure Decimal_InCall_NoToken;
    [Test] procedure Decimal_ColorIndex_NoToken;
```

Implementations:

```pascal
procedure TColorParserTests.Decimal_ColorAssign_Bgr;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  X.Color := 16708849;', False); // $FEF4F1 BGR
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckDecimal), Ord(L[0].Kind));
  Assert.AreEqual(Integer(TColor($FEF4F1)), Integer(L[0].Color));
end;

procedure TColorParserTests.Decimal_TextColor;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  TextColor := 15988209;', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(Ord(ckDecimal), Ord(L[0].Kind));
end;

procedure TColorParserTests.Decimal_RoundTrip;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  X.Color := 16708849;', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual('16708849', FormatColorLiteral(L[0], False));
end;

procedure TColorParserTests.Decimal_ArgbInRgbFile;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  Fill.Color := 4278190080;', True); // $FF000000 ARGB
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual(8, L[0].HexDigits);
  Assert.AreEqual(255, Integer(L[0].Alpha));
end;

procedure TColorParserTests.Decimal_NotColorTarget_NoToken;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  Width := 16708849;', False);
  Assert.AreEqual(0, Length(L));
end;

procedure TColorParserTests.Decimal_InCall_NoToken;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  Color := SomeFunc(16708849);', False);
  Assert.AreEqual(0, Length(L));
end;

procedure TColorParserTests.Decimal_ColorIndex_NoToken;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  ColorIndex := 5;', False);
  Assert.AreEqual(0, Length(L));
end;
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cmd //c ".\Tests\run_parser_tests.bat"`
Expected: FAIL — `ckDecimal` undeclared (compile error) or the decimal tests fail.

- [ ] **Step 3: Implement the decimal gate**

Extend the enum in the interface:

```pascal
  TColorKind = (ckVclName, ckVclHex, ckRgbCall, ckAlphaName, ckRgbHex, ckWebHex, ckDecimal);
```

Add a `COLOR_MASK` / `COLOR_SUFFIX` constant next to the other consts:

```pascal
  COLOR_MASK   = $00FFFFFF;   // 24-bit color range
  COLOR_SUFFIX = 'Color';     // decimal gate: the assignment target must end with this
```

Add these functions above `RecognizeAt`:

```pascal
function EndsWithColor(const aWord: string): Boolean;
begin
  Result := (aWord.Length >= Length(COLOR_SUFFIX)) and
            aWord.EndsWith(COLOR_SUFFIX, True);
end;

{ True when aLex[aIdx] is ':=' whose LHS is a *Color target and whose RHS first
  lexeme is a bare number (the direct operand). }
function IsColorAssign(const aLex: TLexemes; aIdx: Integer): Boolean;
begin
  Result := IsSym(aLex, aIdx, ':=') and
            (aIdx > 0) and (aLex[aIdx - 1].Kind = lkIdent) and
            EndsWithColor(aLex[aIdx - 1].Text) and
            (aIdx + 1 <= High(aLex)) and (aLex[aIdx + 1].Kind = lkNumber);
end;

{ Interprets a bare decimal like the equivalent hex literal: <= $FFFFFF is a
  24-bit color (BGR or RGB per aRgbOrder); a larger value carries a high byte
  and is read as ARGB. Values above $FFFFFFFF are rejected. }
function BuildDecimalToken(const aLexNum: TLexeme; aRgbOrder: Boolean;
  out aToken: TColorToken): Boolean;
var
  LValue: Int64;
begin
  Result := False;
  LValue := StrToInt64Def(aLexNum.Text, -1);
  if (LValue < 0) or (LValue > $FFFFFFFF) then
    Exit;
  aToken.StartCol := aLexNum.StartCol;
  aToken.Length   := aLexNum.Text.Length;
  aToken.Prefix   := String.Empty;
  aToken.Kind     := ckDecimal;
  if LValue > COLOR_MASK then
  begin
    aToken.Color     := RGB(Byte(LValue shr 16), Byte(LValue shr 8), Byte(LValue));
    aToken.Alpha     := Byte(LValue shr 24);
    aToken.HexDigits := ALPHA_HEX_DIGITS;
  end
  else if aRgbOrder then
  begin
    aToken.Color     := RGB(Byte(LValue shr 16), Byte(LValue shr 8), Byte(LValue));
    aToken.Alpha     := OPAQUE;
    aToken.HexDigits := RGB_HEX_DIGITS;
  end
  else
  begin
    aToken.Color     := TColor(LValue);          // $00BBGGRR VCL
    aToken.Alpha     := OPAQUE;
    aToken.HexDigits := RGB_HEX_DIGITS;
  end;
  Result := True;
end;
```

Add the `lkSymbol` arm to `RecognizeAt`:

```pascal
function RecognizeAt(const aLex: TLexemes; aIdx: Integer; aRgbOrder: Boolean;
  out aToken: TColorToken; out aConsumed: Integer): Boolean;
begin
  Result := False;
  aConsumed := 1;
  case aLex[aIdx].Kind of
    lkIdent : Result := TryIdent(aLex, aIdx, aToken, aConsumed);
    lkHex   : Result := BuildHexToken(aLex[aIdx], aRgbOrder, aToken);
    lkString: Result := BuildWebHexToken(aLex[aIdx], aToken);
    lkSymbol:
      if IsColorAssign(aLex, aIdx) and
         BuildDecimalToken(aLex[aIdx + 1], aRgbOrder, aToken) then
      begin
        Result := True;
        aConsumed := 2;   // skip ':=' and the consumed number
      end;
  end;
end;
```

Add `FormatDecimal` above `FormatColorLiteral`:

```pascal
function FormatDecimal(aRgb: TColor; aAlpha: Byte; aHexDigits: Integer; aRgbOrder: Boolean): string;
var
  LValue: Cardinal;
begin
  if aHexDigits = ALPHA_HEX_DIGITS then
    LValue := MakeAlphaValue(aRgb, aAlpha)
  else if aRgbOrder then
    LValue := (Cardinal(GetRValue(aRgb)) shl 16) or
              (Cardinal(GetGValue(aRgb)) shl 8) or Cardinal(GetBValue(aRgb))
  else
    LValue := Cardinal(ColorToRGB(aRgb)) and COLOR_MASK;   // $00BBGGRR VCL
  Result := IntToStr(Int64(LValue));
end;
```

Add the `ckDecimal` case to `FormatColorLiteral` (before the `else`):

```pascal
    ckWebHex:
      Result := FormatWebHex(LRgb);
    ckDecimal:
      Result := FormatDecimal(LRgb, aToken.Alpha, aToken.HexDigits, aRgbOrder);
  else
```

Update `HexUsesRgbOrder` so an ARGB decimal reports RGB order:

```pascal
function HexUsesRgbOrder(const aToken: TColorToken; aEffective6: Boolean): Boolean;
begin
  if aToken.Kind = ckWebHex then
    Exit(True);
  if aToken.HexDigits = ALPHA_HEX_DIGITS then
    Result := (aToken.Kind = ckRgbHex) or (aToken.Kind = ckDecimal)
  else
    Result := aEffective6;
end;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cmd //c ".\Tests\run_parser_tests.bat"`
Expected: `Tests Passed  : 23`, `Tests Failed  : 0`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add ColorPreview.Parser.pas Tests/TestColorParser.pas
git commit -m "feat: recognize decimal color literals assigned to a *Color target"
```

---

## Task 6: Picker — enable alpha for ARGB decimals

The picker is VCL/ToolsAPI UI and is not unit-tested; verify by compiling the package (Task 8) and the manual IDE check. This edit is small and additive.

**Files:**
- Modify: `ColorPreview.PickerForm.pas`

**Interfaces:**
- Consumes: `TColorToken.Kind` (`ckDecimal`), `TColorToken.HexDigits`.
- Produces: alpha slider enabled when a decimal token is ARGB (8-wide).

- [ ] **Step 1: Add a local width constant**

In `ColorPreview.PickerForm.pas`, extend the `const` block near the top (currently `OPAQUE = 255; FORM_WIDTH = 288;`):

```pascal
const
  OPAQUE      = 255;
  FORM_WIDTH  = 288;
  ALPHA_WIDTH = 8;    // decimal/hex width that carries an alpha byte
```

- [ ] **Step 2: Extend `AlphaAllowed`**

Replace the current `AlphaAllowed` body:

```pascal
function TColorPickerForm.AlphaAllowed: Boolean;
begin
  Result := (FToken.Kind = ckAlphaName) or
            ((FToken.Kind in [ckVclHex, ckRgbHex]) and CurrentWriteRgb) or
            ((FToken.Kind = ckDecimal) and (FToken.HexDigits = ALPHA_WIDTH));
end;
```

- [ ] **Step 3: Verify it compiles as part of the package**

Deferred to Task 8 (package build). No standalone test.

- [ ] **Step 4: Commit**

```bash
git add ColorPreview.PickerForm.pas
git commit -m "feat: enable alpha slider for ARGB decimal literals in the picker"
```

---

## Task 7: Sample file + README documentation

**Files:**
- Modify: `ColorSamples.txt`
- Modify: `README.md`

**Interfaces:** none (documentation/manual-test data).

- [ ] **Step 1: Append new samples + counter-examples to `ColorSamples.txt`**

Add at the end of `ColorSamples.txt`:

```
  // --- New in this release ---

  // Web-hex inside string literals (always read as RGB/web):
  WebShort    := '#F80';        // expands to #FF8800
  WebFull     := '#FF8800';     // orange

  // VCL TColorRec named colors:
  RecColor    := TColorRec.Crimson;
  RecBlue     := TColorRec.Blue;

  // Decimal TColor assigned to a *Color target (BGR):
  Cell.Color  := 16708849;      // $FEF4F1
  TextColor   := 15988209;      // $F3F5F1

  // Decimal ARGB assigned to a *Color target in an FMX unit (needs FMX. in the file):
  Fill.Color  := 4278190080;    // $FF000000 opaque black

  // Counter-examples (should NOT get a swatch):
  ColorIndex  := 5;             // does not end in "Color"
  Width       := 16708849;      // not a color target
  Pen.Color   := SomeFunc(16708849);  // decimal is inside a call, not a direct operand
  Casted      := TColor(16708849);     // cast excluded
  const Fixed : TColor = 16708849;     // const declaration excluded
```

- [ ] **Step 2: Document the new families in `README.md`**

Locate the color-format list/table in `README.md` and add rows/bullets for the three new families. Add this block after the existing "recognized formats" list (adjust surrounding prose to match the file's style):

```markdown
- **Web-hex strings** — `'#RGB'` and `'#RRGGBB'` inside string literals, read in web RGB order (e.g. `'#FF8800'`).
- **`TColorRec.X`** — VCL named-color record members (`TColorRec.Crimson`, `TColorRec.Blue`, …).
- **Decimal `TColor`** — a raw decimal integer assigned directly to a `*Color` target (`Font.Color := 16708849;`, `TextColor := 15988209;`). Recognized only as the direct operand of the assignment: values in casts, function arguments, or `const` declarations are intentionally ignored to avoid false positives on non-color integers.
```

- [ ] **Step 3: Commit**

```bash
git add ColorSamples.txt README.md
git commit -m "docs: document web-hex, TColorRec and decimal color literals"
```

---

## Task 8: Rebuild the package + manual IDE verification

**Files:** none modified (build + manual check).

**Interfaces:** none.

- [ ] **Step 1: Close the RAD Studio IDE**

The BPL cannot be overwritten while loaded (`F2039`). Ensure RAD Studio is fully closed.

- [ ] **Step 2: Rebuild the design-time package**

Run: `cmd //c ".\build.bat"`
Expected: `msbuild` completes with `Build succeeded`, 0 errors; `bpl\DelphiColorPreview.bpl` is regenerated.

- [ ] **Step 3: Reopen the IDE and open `ColorSamples.txt` in the editor**

Confirm in the gutter (left breakpoint column):
- Swatches appear for `'#F80'`, `'#FF8800'`, `TColorRec.Crimson`, `TColorRec.Blue`, `Cell.Color := 16708849`, `TextColor := 15988209`.
- **No** swatch for `ColorIndex := 5`, `Width := 16708849`, `Pen.Color := SomeFunc(16708849)`, `TColor(16708849)`, `const Fixed: TColor = 16708849`.
- All previously supported literals still show swatches (parity).

- [ ] **Step 4: Verify Shift+click editing round-trips each new family**

- Shift+click the `TColorRec.Crimson` swatch → picker opens → OK writes back `TColorRec.<name>` (family preserved).
- Shift+click `Cell.Color := 16708849` → OK writes back a decimal integer (not `$hex`).
- Shift+click `'#FF8800'` → OK writes back `'#RRGGBB'` (quotes kept), alpha slider disabled.
- In a unit containing `FMX.` in its first lines, Shift+click an ARGB decimal (`Fill.Color := 4278190080`) → alpha slider is enabled and the checkerboard preview shows.

- [ ] **Step 5: Final verification of the full test suite**

Run: `cmd //c ".\Tests\run_parser_tests.bat"`
Expected: `Tests Passed  : 23`, `Tests Failed  : 0`, exit 0.

- [ ] **Step 6: Commit any final doc/state changes (if the manual check surfaced fixes)**

```bash
git add -A
git commit -m "chore: verify new color formats in the IDE"
```

---

## Notes for the implementer

- **Do not** change the three public signatures of `ColorPreview.Parser`; the notifier and picker depend on them.
- The lexer skips spaces; "first lexeme after `:=`" therefore means index `aIdx + 1`. Negative decimals never match (the `-` lexes as a separate symbol, so the RHS first lexeme is not a number) — this is the intended exclusion of VCL system colors.
- `TColorRec` and the FMX alpha records share the same web-palette member names, which is why `IdentToAlphaColor('cla' + member)` resolves all of them. Members without a `cla` equivalent (e.g. `TColorRec.SysWindow`) correctly resolve to nothing.
- If a later task enables `TColors.X`, add its resolution inside `ResolveRecordMember` at the marked slot; no other code changes are needed.
