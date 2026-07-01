unit ColorPreview.Parser;

{ Scans a single source line and extracts the color literals it contains, and
  formats a color value back into a literal.

  Recognized literal families:
    - VCL clXXX constants               (BGR, order-fixed)
    - RGB(r,g,b) calls, integer args     (channels, order-fixed)
    - FMX TAlphaColor named consts       (ARGB, order-fixed):
        claXXX, TAlphaColorRec.X, TAlphaColors.X
    - $ hex literals                     (BGR or RGB, per the byte-order switch):
        BGR mode -> $00BBGGRR (VCL TColor); RGB mode -> $RRGGBB / $AARRGGBB (web/FMX)

  Only the bare hex family depends on the byte-order switch (aRgbOrder); every
  other family has a fixed interpretation. }

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
    Prefix    : string;     // alpha-name prefix as typed: 'cla' | 'TAlphaColorRec.' | 'TAlphaColors.'
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
///   Returns the RGB-order flag to use when writing a hex token back. An
///   8-digit literal keeps the family it was auto-detected as (by high byte);
///   a 6-digit literal follows aEffective6 (the file/mode-derived order).
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
  MIN_HEX_DIGITS  = 6;     // shortest hex treated as a color ($RRGGBB)
  MAX_HEX_DIGITS  = 8;     // longest hex treated as a color ($00BBGGRR / $AARRGGBB)
  RGB_ARG_COUNT   = 3;
  RGB_MAX_CHANNEL = 255;
  OPAQUE          = 255;
  ALPHA_HEX_DIGITS = 8;    // hex width that carries an alpha byte in RGB mode

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

procedure SkipSpaces(const aText: string; var aPos: Integer);
begin
  while (aPos <= aText.Length) and (aText[aPos] = ' ') do
    Inc(aPos);
end;

function ReadIdentifier(const aText: string; var aPos: Integer): string;
var
  LStart: Integer;
begin
  LStart := aPos;
  while (aPos <= aText.Length) and IsIdentChar(aText[aPos]) do
    Inc(aPos);
  Result := aText.Substring(LStart - 1, aPos - LStart);
end;

{ Reads one decimal channel (0..255) and, when expected, the trailing comma. }
function ReadChannel(const aText: string; var aPos: Integer; aExpectComma: Boolean;
  out aValue: Integer): Boolean;
var
  LStart: Integer;
begin
  Result := False;
  SkipSpaces(aText, aPos);
  LStart := aPos;
  while (aPos <= aText.Length) and aText[aPos].IsDigit do
    Inc(aPos);
  if aPos = LStart then
    Exit;
  aValue := StrToIntDef(aText.Substring(LStart - 1, aPos - LStart), -1);
  if (aValue < 0) or (aValue > RGB_MAX_CHANNEL) then
    Exit;
  SkipSpaces(aText, aPos);
  if aExpectComma then
  begin
    if (aPos > aText.Length) or (aText[aPos] <> ',') then
      Exit;
    Inc(aPos);
  end;
  Result := True;
end;

{ aStart points at the 'R' of "RGB"; aPos points just past the "RGB" word. }
procedure TryRgbCall(const aText: string; aStart: Integer; var aPos: Integer;
  aTokens: TList<TColorToken>);
var
  LScan     : Integer;
  LChannels : array[0 .. RGB_ARG_COUNT - 1] of Integer;
  LIdx      : Integer;
  LToken    : TColorToken;
begin
  LScan := aPos;
  SkipSpaces(aText, LScan);
  if (LScan > aText.Length) or (aText[LScan] <> '(') then
    Exit;
  Inc(LScan);
  for LIdx := 0 to RGB_ARG_COUNT - 1 do
    if not ReadChannel(aText, LScan, LIdx < RGB_ARG_COUNT - 1, LChannels[LIdx]) then
      Exit;
  SkipSpaces(aText, LScan);
  if (LScan > aText.Length) or (aText[LScan] <> ')') then
    Exit;
  Inc(LScan);
  LToken.StartCol  := aStart;
  LToken.Length    := LScan - aStart;
  LToken.Color     := RGB(LChannels[0], LChannels[1], LChannels[2]);
  LToken.Alpha     := OPAQUE;
  LToken.HexDigits := 0;
  LToken.Prefix    := String.Empty;
  LToken.Kind      := ckRgbCall;
  aTokens.Add(LToken);
  aPos := LScan;
end;

{ Adds an FMX TAlphaColor named-constant token. aValue is the resolved ARGB
  value; aPrefix is the source prefix ('cla' / 'TAlphaColorRec.' / 'TAlphaColors.'). }
procedure AddAlphaName(aTokens: TList<TColorToken>; aStart, aLength: Integer;
  aValue: TAlphaColor; const aPrefix: string);
var
  LRec   : TAlphaColorRec;
  LToken : TColorToken;
begin
  LRec := TAlphaColorRec.Create(aValue);
  LToken.StartCol  := aStart;
  LToken.Length    := aLength;
  LToken.Color     := RGB(LRec.R, LRec.G, LRec.B);
  LToken.Alpha     := LRec.A;
  LToken.HexDigits := 0;
  LToken.Prefix    := aPrefix;
  LToken.Kind      := ckAlphaName;
  aTokens.Add(LToken);
end;

{ Handles TAlphaColorRec.X / TAlphaColors.X. aStart points at the record name,
  aPos just past it (the '.' is the next char). }
procedure TryAlphaMember(const aText: string; aStart: Integer; var aPos: Integer;
  const aRecord: string; aTokens: TList<TColorToken>);
var
  LMember   : string;
  LColorInt : Integer;
begin
  if (aPos > aText.Length) or (aText[aPos] <> '.') then
    Exit;
  Inc(aPos);                                    // skip '.'
  LMember := ReadIdentifier(aText, aPos);
  if (not LMember.IsEmpty) and IdentToAlphaColor('cla' + LMember, LColorInt) then
    AddAlphaName(aTokens, aStart, aPos - aStart, TAlphaColor(LColorInt), aRecord + '.');
end;

procedure TryIdentifierToken(const aText: string; var aPos: Integer;
  aTokens: TList<TColorToken>);
var
  LStart, LColorInt : Integer;
  LWord             : string;
  LToken            : TColorToken;
begin
  LStart := aPos;
  LWord := ReadIdentifier(aText, aPos);
  if SameText(LWord, 'RGB') then
  begin
    TryRgbCall(aText, LStart, aPos, aTokens);
    Exit;
  end;
  if SameText(LWord, 'TAlphaColorRec') or SameText(LWord, 'TAlphaColors') then
  begin
    TryAlphaMember(aText, LStart, aPos, LWord, aTokens);
    Exit;
  end;
  if (LWord.Length > 2) and LWord.StartsWith('cl', True) and
     IdentToColor(LWord, LColorInt)
  then
  begin
    LToken.StartCol  := LStart;
    LToken.Length    := LWord.Length;
    LToken.Color     := TColor(LColorInt);
    LToken.Alpha     := OPAQUE;
    LToken.HexDigits := 0;
    LToken.Prefix    := String.Empty;
    LToken.Kind      := ckVclName;
    aTokens.Add(LToken);
    Exit;
  end;
  if (LWord.Length > 3) and LWord.StartsWith('cla', True) and
     IdentToAlphaColor(LWord, LColorInt)
  then
    AddAlphaName(aTokens, LStart, LWord.Length, TAlphaColor(LColorInt), 'cla');
end;

{ Parses a bare hex literal in RGB/web order: $RRGGBB (opaque) or $AARRGGBB. }
function ParseRgbHex(const aLiteral: string; aDigits: Integer; var aToken: TColorToken): Boolean;
var
  LValue : Int64;
  LR, LG, LB, LA : Byte;
begin
  Result := False;
  if (aDigits <> MIN_HEX_DIGITS) and (aDigits <> ALPHA_HEX_DIGITS) then
    Exit;                                       // skip odd widths (e.g. 7) in RGB mode
  LValue := StrToInt64Def(aLiteral, -1);        // '$..' parses as hexadecimal
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

{ Parses an 8-digit hex, auto-detecting the family by its high byte:
  $00xxxxxx -> VCL BGR TColor; $AAxxxxxx (high byte <> 0) -> FMX ARGB.
  A real VCL literal is always written $00BBGGRR, so a non-zero high byte
  unambiguously means an alpha color - no byte-order switch needed. }
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

procedure TryHexToken(const aText: string; var aPos: Integer; aRgbOrder: Boolean;
  aTokens: TList<TColorToken>);
var
  LStart, LDigits : Integer;
  LLiteral        : string;
  LColor          : TColor;
  LToken          : TColorToken;
begin
  LStart := aPos;
  Inc(aPos);                                    // skip '$'
  while (aPos <= aText.Length) and IsHexDigit(aText[aPos]) do
    Inc(aPos);
  LDigits := aPos - LStart - 1;
  if (LDigits < MIN_HEX_DIGITS) or (LDigits > MAX_HEX_DIGITS) then
    Exit;
  LLiteral := aText.Substring(LStart - 1, aPos - LStart);
  LToken.StartCol  := LStart;
  LToken.Length    := aPos - LStart;
  LToken.HexDigits := LDigits;
  LToken.Prefix    := String.Empty;
  if LDigits = ALPHA_HEX_DIGITS then
  begin
    if not ParseHex8(LLiteral, LToken) then     // 8 digits: auto by high byte
      Exit;
  end
  else if aRgbOrder then
  begin
    if not ParseRgbHex(LLiteral, LDigits, LToken) then
      Exit;
  end
  else
  begin
    if not TryStringToColor(LLiteral, LColor) then
      Exit;
    LToken.Color := LColor;
    LToken.Alpha := OPAQUE;
    LToken.Kind  := ckVclHex;
  end;
  aTokens.Add(LToken);
end;

function FindColorTokens(const aLineText: string; aRgbOrder: Boolean): TColorTokens;
var
  LTokens : TList<TColorToken>;
  LPos    : Integer;
  LCh     : Char;
begin
  if aLineText.IsEmpty then
    Exit(nil);
  LTokens := TList<TColorToken>.Create;
  try
    LPos := 1;
    while LPos <= aLineText.Length do
    begin
      LCh := aLineText[LPos];
      if IsIdentStart(LCh) then
        TryIdentifierToken(aLineText, LPos, LTokens)
      else if LCh = '$' then
        TryHexToken(aLineText, LPos, aRgbOrder, LTokens)
      else
        Inc(LPos);
    end;
    Result := LTokens.ToArray;
  finally
    LTokens.Free;
  end;
end;

{ Composes an ARGB value from an opaque RGB TColor plus an alpha byte. }
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
    Exit('$' + IntToHex(LValue, ALPHA_HEX_DIGITS));   // custom color -> $AARRGGBB
  if aToken.Prefix.IsEmpty or SameText(aToken.Prefix, 'cla') then
    Result := LName
  else
    Result := aToken.Prefix + LName.Substring(3);      // e.g. TAlphaColorRec.Red
end;

function FormatHex(aRgb: TColor; aAlpha: Byte; aHexDigits: Integer; aRgbOrder: Boolean): string;
begin
  if not aRgbOrder then
    Exit('$' + IntToHex(aRgb, ALPHA_HEX_DIGITS));       // VCL $00BBGGRR
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
      Result := ColorToString(aToken.Color);   // clXXX name when known, else $hex
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
