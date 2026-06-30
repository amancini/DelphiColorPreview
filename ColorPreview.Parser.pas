unit ColorPreview.Parser;

{ Scans a single source line and extracts the color literals it contains.
  Three literal kinds are recognized: VCL clXXX constants, $00BBGGRR TColor
  hex values, and RGB(r,g,b) calls with integer arguments. }

interface

uses
  Vcl.Graphics;

type
  /// <summary>Kind of color literal found in source code.</summary>
  TColorKind = (ckName, ckHex, ckRgbCall);

  /// <summary>A color literal located inside a single source line.</summary>
  TColorToken = record
    StartCol : Integer;    // 1-based column of the first character
    Length   : Integer;    // number of characters the literal spans
    Color    : TColor;     // resolved TColor value
    Kind     : TColorKind;
  end;

  TColorTokens = TArray<TColorToken>;

/// <summary>
///   Scans a single source line and returns every color literal it contains
///   (clXXX constants, $00BBGGRR hex, and RGB(r,g,b) calls with int arguments).
/// </summary>
function FindColorTokens(const aLineText: string): TColorTokens;

implementation

uses
  System.SysUtils,
  System.Character,
  System.Generics.Collections,
  Winapi.Windows;

const
  MIN_HEX_DIGITS  = 6;     // shortest hex treated as a color ($RRGGBB)
  MAX_HEX_DIGITS  = 8;     // longest hex treated as a color ($00BBGGRR)
  RGB_ARG_COUNT   = 3;
  RGB_MAX_CHANNEL = 255;

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
  LToken.StartCol := aStart;
  LToken.Length := LScan - aStart;
  LToken.Color := RGB(LChannels[0], LChannels[1], LChannels[2]);
  LToken.Kind := ckRgbCall;
  aTokens.Add(LToken);
  aPos := LScan;
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
  if (LWord.Length > 2) and LWord.StartsWith('cl', True) and
     IdentToColor(LWord, LColorInt)
  then
  begin
    LToken.StartCol := LStart;
    LToken.Length := LWord.Length;
    LToken.Color := TColor(LColorInt);
    LToken.Kind := ckName;
    aTokens.Add(LToken);
  end;
end;

procedure TryHexToken(const aText: string; var aPos: Integer;
  aTokens: TList<TColorToken>);
var
  LStart, LDigits : Integer;
  LLiteral        : string;
  LColor          : TColor;
  LToken          : TColorToken;
begin
  LStart := aPos;
  Inc(aPos);                                  // skip '$'
  while (aPos <= aText.Length) and IsHexDigit(aText[aPos]) do
    Inc(aPos);
  LDigits := aPos - LStart - 1;
  if (LDigits < MIN_HEX_DIGITS) or (LDigits > MAX_HEX_DIGITS) then
    Exit;
  LLiteral := aText.Substring(LStart - 1, aPos - LStart);
  if not TryStringToColor(LLiteral, LColor) then
    Exit;
  LToken.StartCol := LStart;
  LToken.Length := aPos - LStart;
  LToken.Color := LColor;
  LToken.Kind := ckHex;
  aTokens.Add(LToken);
end;

function FindColorTokens(const aLineText: string): TColorTokens;
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
        TryHexToken(aLineText, LPos, LTokens)
      else
        Inc(LPos);
    end;
    Result := LTokens.ToArray;
  finally
    LTokens.Free;
  end;
end;

end.
