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
