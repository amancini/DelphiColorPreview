unit ColorPreview.Notifier;

{ Code-editor events notifier that paints a color swatch in the LEFT gutter
  (the breakpoint column) for every color literal found on a visible line, and
  opens the custom color picker on Shift+click, rewriting the literal in place
  (with IDE undo support).

  Painting is done once per repaint at the pgsEndPaint gutter stage: that stage
  runs after the whole gutter is drawn, with a clip covering the entire gutter,
  so the swatch can sit at the far left on every line (with or without an actual
  breakpoint). Geometry comes from each line's own GutterRect, so there is no
  column-to-pixel math and the swatch never drifts.

  The set of recognized literals and the byte order of bare hex follow the
  global switch in ColorPreview.Settings. }

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
  ///   Draws color swatches in the IDE code-editor gutter and opens the color
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
      FSwatches       : TList<TSwatch>;
      FCurrentRgbOrder : Boolean;   // effective 6-digit hex order for this repaint
      FDetectedFile   : string;    // file name behind the cached FFileIsFmx
      FFileIsFmx      : Boolean;    // does the current unit use the FMX framework
    function CurrentFileIsFmx: Boolean;
    procedure DrawLineSwatches(aCanvas: TCanvas; const aLineState: INTACodeEditorLineState);
    procedure ApplyColor(const aSwatch: TSwatch);
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
  System.SysUtils,
  ColorPreview.Render,
  ColorPreview.Settings,
  ColorPreview.PickerForm;

const
  SWATCH_LEFT       = 2;    // px offset from the left edge of the gutter
  SWATCH_MARGIN     = 2;    // px vertical inset within the gutter line
  SWATCH_WIDTH      = 20;   // swatch width (wider than tall for visibility)
  MAX_SWATCH_HEIGHT = 14;   // cap the height so it stays a neat marker
  DETECT_SCAN_BYTES = 16384; // bytes scanned from the top to detect an FMX unit

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
  FCurrentRgbOrder := EffectiveRgbOrder(GetByteOrderMode, CurrentFileIsFmx);
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
  LTokens := FindColorTokens(aLineState.Text, FCurrentRgbOrder);
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
    DrawColorPreview(aCanvas, LSwatch.Area, LTokens[LIndex].Color, LTokens[LIndex].Alpha);
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
  LView     : IOTAEditView;
  LPos      : IOTAEditPosition;
  LToken    : TColorToken;
  LColor    : TColor;
  LAlpha    : Byte;
  LWriteRgb : Boolean;
begin
  LView := (BorlandIDEServices as IOTAEditorServices).TopView;
  if not Assigned(LView) then
    Exit;
  LToken := aSwatch.Token;
  LColor := ColorToRGB(LToken.Color);
  LAlpha := LToken.Alpha;
  if not EditColor(LToken, CurrentFileIsFmx, LColor, LAlpha, LWriteRgb) then
    Exit;
  LToken.Color := LColor;
  LToken.Alpha := LAlpha;
  LPos := LView.Buffer.EditPosition;
  LPos.Move(aSwatch.Line, aSwatch.Token.StartCol);
  LPos.Delete(aSwatch.Token.Length);
  LPos.InsertText(FormatColorLiteral(LToken, LWriteRgb));
  (BorlandIDEServices as INTACodeEditorServices).InvalidateTopEditor;
end;

{ Detects whether the active unit uses the FMX framework by scanning the top of
  its buffer for an 'FMX.' unit reference. Cached per file name so repaints are
  cheap; refreshed when the active file changes. }
function TColorPreviewNotifier.CurrentFileIsFmx: Boolean;
var
  LBuffer : IOTAEditBuffer;
  LReader : IOTAEditReader;
  LText   : AnsiString;
  LName   : string;
  LRead   : Integer;
begin
  LBuffer := (BorlandIDEServices as IOTAEditorServices).TopBuffer;
  if not Assigned(LBuffer) then
    Exit(False);
  LName := LBuffer.FileName;
  if SameText(LName, FDetectedFile) then
    Exit(FFileIsFmx);
  FDetectedFile := LName;
  FFileIsFmx := False;
  LReader := LBuffer.CreateReader;
  if Assigned(LReader) then
  begin
    SetLength(LText, DETECT_SCAN_BYTES);
    LRead := LReader.GetText(0, PAnsiChar(LText), DETECT_SCAN_BYTES);
    SetLength(LText, LRead);
    FFileIsFmx := Pos(AnsiString('FMX.'), LText) > 0;
  end;
  Result := FFileIsFmx;
end;

end.
