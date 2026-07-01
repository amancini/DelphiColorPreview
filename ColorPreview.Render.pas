unit ColorPreview.Render;

{ Shared color-preview drawing, used both by the gutter swatch and by the
  picker's preview box. A fully opaque color is a solid fill; a translucent one
  is blended over a light/dark checkerboard so the transparency is visible. A
  thin gray border is drawn in both cases. }

interface

uses
  System.Types,
  Vcl.Graphics;

/// <summary>Paints a color preview into aArea. aAlpha = 255 draws a solid fill;
///  a lower value blends the color over a checkerboard.</summary>
procedure DrawColorPreview(aCanvas: TCanvas; const aArea: TRect; aColor: TColor; aAlpha: Byte);

implementation

uses
  System.Math,
  Winapi.Windows;

const
  CHECKER_SIZE  = 4;                  // px per checkerboard cell
  CHECKER_LIGHT = TColor($00FFFFFF);  // clWhite
  CHECKER_DARK  = TColor($00C0C0C0);  // light gray
  OPAQUE        = 255;

function BlendChannel(aFore, aBack, aAlpha: Byte): Byte;
begin
  Result := Byte((aFore * aAlpha + aBack * (OPAQUE - aAlpha)) div OPAQUE);
end;

{ Blends aColor over aBackground at the given alpha. Both must be concrete RGB. }
function BlendColor(aColor, aBackground: TColor; aAlpha: Byte): TColor;
begin
  Result := RGB(
    BlendChannel(GetRValue(aColor), GetRValue(aBackground), aAlpha),
    BlendChannel(GetGValue(aColor), GetGValue(aBackground), aAlpha),
    BlendChannel(GetBValue(aColor), GetBValue(aBackground), aAlpha));
end;

procedure DrawCheckerboard(aCanvas: TCanvas; const aArea: TRect; aLight, aDark: TColor);
var
  LRow, LCol, LX, LY : Integer;
  LCell              : TRect;
begin
  LY := aArea.Top;
  LRow := 0;
  while LY < aArea.Bottom do
  begin
    LX := aArea.Left;
    LCol := 0;
    while LX < aArea.Right do
    begin
      LCell := TRect.Create(LX, LY, Min(LX + CHECKER_SIZE, aArea.Right),
        Min(LY + CHECKER_SIZE, aArea.Bottom));
      if Odd(LRow + LCol) then
        aCanvas.Brush.Color := aDark
      else
        aCanvas.Brush.Color := aLight;
      aCanvas.FillRect(LCell);
      Inc(LX, CHECKER_SIZE);
      Inc(LCol);
    end;
    Inc(LY, CHECKER_SIZE);
    Inc(LRow);
  end;
end;

procedure DrawColorPreview(aCanvas: TCanvas; const aArea: TRect; aColor: TColor; aAlpha: Byte);
var
  LSolid      : TColor;
  LPenColor   : TColor;
  LBrushColor : TColor;
  LBrushStyle : TBrushStyle;
  LPenWidth   : Integer;
begin
  LSolid := ColorToRGB(aColor);
  LPenColor := aCanvas.Pen.Color;
  LBrushColor := aCanvas.Brush.Color;
  LBrushStyle := aCanvas.Brush.Style;
  LPenWidth := aCanvas.Pen.Width;
  try
    aCanvas.Brush.Style := bsSolid;
    if aAlpha >= OPAQUE then
    begin
      aCanvas.Brush.Color := LSolid;
      aCanvas.FillRect(aArea);
    end
    else
      DrawCheckerboard(aCanvas, aArea,
        BlendColor(LSolid, CHECKER_LIGHT, aAlpha),
        BlendColor(LSolid, CHECKER_DARK, aAlpha));
    aCanvas.Brush.Style := bsClear;
    aCanvas.Pen.Color := clGray;
    aCanvas.Pen.Width := 1;
    aCanvas.Rectangle(aArea);
  finally
    aCanvas.Pen.Color := LPenColor;
    aCanvas.Brush.Color := LBrushColor;
    aCanvas.Brush.Style := LBrushStyle;
    aCanvas.Pen.Width := LPenWidth;
  end;
end;

end.
