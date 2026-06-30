unit ColorPreview.Notifier;

{ Code-editor events notifier that paints a color swatch in the LEFT gutter
  (the breakpoint column) for every color literal found on a visible line, and
  opens a color picker on Shift+click, rewriting the literal in place (with IDE
  undo support).

  Painting is done once per repaint at the pgsEndPaint gutter stage: that stage
  runs after the whole gutter is drawn, with a clip covering the entire gutter,
  so the swatch can sit at the far left on every line (with or without an actual
  breakpoint). Geometry comes from each line's own GutterRect, so there is no
  column-to-pixel math and the swatch never drifts. }

interface

uses
  System.Classes,
  System.Types,
  System.UITypes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  ToolsAPI,
  ToolsAPI.Editor,
  ColorPreview.Parser;

type
  /// <summary>
  ///   Draws color swatches in the IDE code-editor gutter and opens a color
  ///   picker when a swatch is Shift+clicked.
  /// </summary>
  TColorPreviewNotifier = class(TNTACodeEditorNotifier)
  private
    type
      TSwatch = record
        Area  : TRect;        // client-coordinate hit area of the swatch
        Token : TColorToken;  // the literal this swatch represents
        Line  : Integer;      // 1-based logical line
      end;
    var
      FSwatches : TList<TSwatch>;
    procedure DrawSwatch(aCanvas: TCanvas; const aArea: TRect; aColor: TColor);
    procedure DrawLineSwatches(aCanvas: TCanvas; const aLineState: INTACodeEditorLineState);
    procedure ApplyColor(const aSwatch: TSwatch);
    function FormatLiteral(aColor: TColor; aKind: TColorKind): string;
    { Handlers wired to the base TNTACodeEditorNotifier.On* events (the paint /
      mouse methods are not virtual, so they are consumed as events). }
    procedure HandlePaintGutter(const aRect: TRect; const aStage: TPaintGutterStage;
      const aBeforeEvent: Boolean; var aAllowDefaultPainting: Boolean;
      const aContext: INTACodeEditorPaintContext);
    procedure HandleMouseDown(const aEditor: TWinControl; aButton: TMouseButton;
      aShift: TShiftState; aX, aY: Integer);
  protected
    function AllowedEvents: TCodeEditorEvents; override;
    function AllowedGutterStages: TPaintGutterStages; override;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Dialogs;

const
  SWATCH_LEFT       = 2;   // px offset from the left edge of the gutter
  SWATCH_MARGIN     = 2;   // px vertical inset within the gutter line
  SWATCH_WIDTH      = 20;  // swatch width (wider than tall for visibility)
  MAX_SWATCH_HEIGHT = 14;  // cap the height so it stays a neat marker

{ Builds the swatch rect whose left edge is aLeftEdge, vertically centered
  inside the given gutter line rect. }
function MakeSwatchRect(const aGutter: TRect; aLeftEdge, aWidth, aHeight: Integer): TRect;
var
  LTop: Integer;
begin
  LTop := aGutter.Top + (aGutter.Height - aHeight) div 2;
  Result := TRect.Create(aLeftEdge, LTop, aLeftEdge + aWidth, LTop + aHeight);
end;

{ TColorPreviewNotifier }

constructor TColorPreviewNotifier.Create;
begin
  inherited Create;
  FSwatches := TList<TSwatch>.Create;
  OnEditorPaintGutter := HandlePaintGutter;
  OnEditorMouseDown := HandleMouseDown;
end;

destructor TColorPreviewNotifier.Destroy;
begin
  FSwatches.Free;
  inherited Destroy;
end;

function TColorPreviewNotifier.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintGutterEvents, cevMouseEvents];
end;

function TColorPreviewNotifier.AllowedGutterStages: TPaintGutterStages;
begin
  Result := [pgsEndPaint];   // fires once, after the whole gutter is painted
end;

procedure TColorPreviewNotifier.HandlePaintGutter(const aRect: TRect;
  const aStage: TPaintGutterStage; const aBeforeEvent: Boolean;
  var aAllowDefaultPainting: Boolean; const aContext: INTACodeEditorPaintContext);
var
  LState     : INTACodeEditorState;
  LLineState : INTACodeEditorLineState;
  LVisLine   : Integer;
begin
  if aBeforeEvent or (aStage <> pgsEndPaint) or (not Assigned(aContext)) then
    Exit;
  LState := aContext.EditorState;
  if not Assigned(LState) then
    Exit;
  FSwatches.Clear;
  for LVisLine := LState.TopLine to LState.BottomLine do
  begin
    LLineState := LState.LineState[LVisLine];
    if Assigned(LLineState) then
      DrawLineSwatches(aContext.Canvas, LLineState);
  end;
end;

procedure TColorPreviewNotifier.DrawLineSwatches(aCanvas: TCanvas;
  const aLineState: INTACodeEditorLineState);
var
  LTokens : TColorTokens;
  LSwatch : TSwatch;
  LGutter : TRect;
  LHeight : Integer;
  LWidth  : Integer;
  LLeft   : Integer;
  LIndex  : Integer;
begin
  LTokens := FindColorTokens(aLineState.Text);
  if Length(LTokens) = 0 then
    Exit;
  LGutter := aLineState.GutterRect;   // leftmost area, where breakpoints appear
  LHeight := LGutter.Height - SWATCH_MARGIN * 2;
  if LHeight > MAX_SWATCH_HEIGHT then
    LHeight := MAX_SWATCH_HEIGHT;
  LWidth := SWATCH_WIDTH;
  if LWidth > LGutter.Width - SWATCH_LEFT * 2 then
    LWidth := LGutter.Width - SWATCH_LEFT * 2;   // keep it inside the gutter column
  LLeft := LGutter.Left + SWATCH_LEFT;
  for LIndex := 0 to High(LTokens) do
  begin
    LSwatch.Area := MakeSwatchRect(LGutter, LLeft + LIndex * (LWidth + 1), LWidth, LHeight);
    LSwatch.Token := LTokens[LIndex];
    LSwatch.Line := aLineState.LogicalLineNum;
    FSwatches.Add(LSwatch);
    DrawSwatch(aCanvas, LSwatch.Area, ColorToRGB(LTokens[LIndex].Color));
  end;
end;

procedure TColorPreviewNotifier.DrawSwatch(aCanvas: TCanvas; const aArea: TRect;
  aColor: TColor);
var
  LPenColor, LBrushColor : TColor;
  LPenWidth              : Integer;
begin
  LPenColor := aCanvas.Pen.Color;
  LBrushColor := aCanvas.Brush.Color;
  LPenWidth := aCanvas.Pen.Width;
  try
    aCanvas.Brush.Color := aColor;
    aCanvas.Pen.Color := clGray;
    aCanvas.Pen.Width := 1;
    aCanvas.Rectangle(aArea);
  finally
    aCanvas.Pen.Color := LPenColor;
    aCanvas.Brush.Color := LBrushColor;
    aCanvas.Pen.Width := LPenWidth;
  end;
end;

procedure TColorPreviewNotifier.HandleMouseDown(const aEditor: TWinControl;
  aButton: TMouseButton; aShift: TShiftState; aX, aY: Integer);
var
  LSwatch: TSwatch;
begin
  // Picker on Shift+click, so a plain click stays free for breakpoints.
  if (aButton <> TMouseButton.mbLeft) or (not (ssShift in aShift)) then
    Exit;
  for LSwatch in FSwatches do
    if LSwatch.Area.Contains(TPoint.Create(aX, aY)) then
    begin
      ApplyColor(LSwatch);
      Break;
    end;
end;

procedure TColorPreviewNotifier.ApplyColor(const aSwatch: TSwatch);
var
  LDialog : TColorDialog;
  LView   : IOTAEditView;
  LPos    : IOTAEditPosition;
begin
  LView := (BorlandIDEServices as IOTAEditorServices).TopView;
  if not Assigned(LView) then
    Exit;
  LDialog := TColorDialog.Create(nil);
  try
    LDialog.Color := ColorToRGB(aSwatch.Token.Color);
    if not LDialog.Execute then
      Exit;
    LPos := LView.Buffer.EditPosition;
    LPos.Move(aSwatch.Line, aSwatch.Token.StartCol);
    LPos.Delete(aSwatch.Token.Length);
    LPos.InsertText(FormatLiteral(LDialog.Color, aSwatch.Token.Kind));
  finally
    LDialog.Free;
  end;
  (BorlandIDEServices as INTACodeEditorServices).InvalidateTopEditor;
end;

function TColorPreviewNotifier.FormatLiteral(aColor: TColor;
  aKind: TColorKind): string;
var
  LRgb: TColor;
begin
  LRgb := ColorToRGB(aColor);
  case aKind of
    ckRgbCall:
      Result := Format('RGB(%d, %d, %d)',
        [GetRValue(LRgb), GetGValue(LRgb), GetBValue(LRgb)]);
    ckName:
      Result := ColorToString(aColor);   // clXXX name when known, else $hex
  else
    Result := '$' + IntToHex(LRgb, 8);   // ckHex -> $00BBGGRR
  end;
end;

end.
