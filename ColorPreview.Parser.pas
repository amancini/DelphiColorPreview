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
  TColorKind = (ckVclName, ckVclHex, ckRgbCall, ckAlphaName, ckRgbHex, ckWebHex);

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

{ Resolves RecordName.Member for the FMX alpha-color records and TColorRec
  (VCL web palette). }
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

function IsWebHexDigits(const aDigits: string): Boolean;
var
  LCh: Char;
begin
  Result := (aDigits.Length = 3) or (aDigits.Length = RGB_HEX_DIGITS);
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
  if (LInner.Length < 3) or (LInner.Chars[0] <> '''') or
     (LInner.Chars[LInner.Length - 1] <> '''') then
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

{ ---- top-level recognizer ---- }

function RecognizeAt(const aLex: TLexemes; aIdx: Integer; aRgbOrder: Boolean;
  out aToken: TColorToken; out aConsumed: Integer): Boolean;
begin
  Result := False;
  aConsumed := 1;
  case aLex[aIdx].Kind of
    lkIdent : Result := TryIdent(aLex, aIdx, aToken, aConsumed);
    lkHex   : Result := BuildHexToken(aLex[aIdx], aRgbOrder, aToken);
    lkString: Result := BuildWebHexToken(aLex[aIdx], aToken);
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

function FormatWebHex(aRgb: TColor): string;
begin
  Result := '''#' + IntToHex(GetRValue(aRgb), 2) + IntToHex(GetGValue(aRgb), 2) +
            IntToHex(GetBValue(aRgb), 2) + '''';
end;

function FormatVclName(const aToken: TColorToken; aRgb: TColor): string;
var
  LName: string;
begin
  if aToken.Prefix.IsEmpty then
    Exit(ColorToString(aToken.Color));
  // AlphaColorToString already strips the 'cla' prefix from a matched name
  // (see System.UIConsts) and returns '#AARRGGBB' when the value is unnamed.
  LName := AlphaColorToString(TAlphaColor(MakeAlphaValue(aRgb, OPAQUE)));
  if LName.StartsWith('#', True) then
    Result := '$' + IntToHex(ColorToRGB(aToken.Color), ALPHA_HEX_DIGITS) // $00BBGGRR fallback
  else
    Result := aToken.Prefix + LName;                                    // TColorRec.Crimson
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
      Result := FormatVclName(aToken, LRgb);
    ckAlphaName:
      Result := FormatAlphaName(aToken, LRgb);
    ckWebHex:
      Result := FormatWebHex(LRgb);
  else
    Result := FormatHex(LRgb, aToken.Alpha, aToken.HexDigits, aRgbOrder);
  end;
end;

function HexUsesRgbOrder(const aToken: TColorToken; aEffective6: Boolean): Boolean;
begin
  if aToken.Kind = ckWebHex then
    Exit(True);
  if aToken.HexDigits = ALPHA_HEX_DIGITS then
    Result := aToken.Kind = ckRgbHex
  else
    Result := aEffective6;
end;

end.
