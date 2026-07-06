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
    [Test] procedure AlphaName_RoundTrip_Cla;
    [Test] procedure AlphaRec_RoundTrip;
    [Test] procedure TooShortHex_NoToken;
    [Test] procedure PlainNumber_NoToken;
    [Test] procedure StringLiteral_NonWeb_NoToken;
    [Test] procedure WebHex_Six;
    [Test] procedure WebHex_ShortExpands;
    [Test] procedure WebHex_NonHex_NoToken;
    [Test] procedure WebHex_Unterminated_NoToken;
    [Test] procedure WebHex_RoundTrip;
    [Test] procedure ColorRec_Member;
    [Test] procedure ColorRec_RoundTrip;
    [Test] procedure Colors_Disabled;
    // --- decimal color literals (context-gated) ---
    [Test] procedure Decimal_ColorAssign_Bgr;
    [Test] procedure Decimal_TextColor;
    [Test] procedure Decimal_RoundTrip;
    [Test] procedure Decimal_ArgbInRgbFile;
    [Test] procedure Decimal_NotColorTarget_NoToken;
    [Test] procedure Decimal_InCall_NoToken;
    [Test] procedure Decimal_ColorIndex_NoToken;
  end;

implementation

uses
  System.UITypes,
  Vcl.Graphics,
  Winapi.Windows,
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

procedure TColorParserTests.AlphaName_RoundTrip_Cla;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  A := claRed;', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual('claRed', FormatColorLiteral(L[0], False));
end;

procedure TColorParserTests.AlphaRec_RoundTrip;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  A := TAlphaColorRec.Blue;', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual('TAlphaColorRec.Blue', FormatColorLiteral(L[0], False));
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

procedure TColorParserTests.StringLiteral_NonWeb_NoToken;
var
  L: TColorTokens;
begin
  // Color-family substrings inside string literals are NOT colors (avoids
  // false positives); only web-hex '#RRGGBB' is recognized (a later task).
  L := FindColorTokens('  Caption := ''clRed'';', False);
  Assert.AreEqual(0, Length(L));
end;

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

procedure TColorParserTests.WebHex_Unterminated_NoToken;
var
  L: TColorTokens;
begin
  // Unterminated string (no closing quote) must NOT produce a token.
  L := FindColorTokens('  S := ''#AABBCCX', False);
  Assert.AreEqual(0, Length(L));
end;

procedure TColorParserTests.WebHex_RoundTrip;
var
  L: TColorTokens;
begin
  L := FindColorTokens('  S := ''#FF8800'';', False);
  Assert.AreEqual(1, Length(L));
  Assert.AreEqual('''#FF8800''', FormatColorLiteral(L[0], False));
end;

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

initialization
  TDUnitX.RegisterTestFixture(TColorParserTests);

end.
