unit ColorPreview.PickerForm;

{ Custom color editor shown on Shift+click, replacing the plain TColorDialog.
  It adds what TColorDialog cannot do: an Alpha slider (for TAlphaColor literals)
  and a byte-order selector (Auto / BGR / RGB). RGB hue selection is still
  delegated to the native TColorDialog via the "Choose color..." button. The
  literal preview mirrors exactly what will be written back.

  The form is built entirely in code (CreateNew), so there is no .dfm, and it is
  themed to match the IDE via IOTAIDEThemingServices. }

interface

uses
  Vcl.Graphics,
  ColorPreview.Parser;

/// <summary>
///   Shows the color editor seeded from aToken. Returns True when confirmed.
///   aColor/aAlpha carry the initial values in and the chosen values out;
///   aWriteRgb returns the byte order to use when writing this hex token back.
///   aFileIsFmx tells the editor whether the current unit is FMX (for the Auto
///   byte-order mode). The chosen mode is persisted globally on confirm.
/// </summary>
function EditColor(const aToken: TColorToken; aFileIsFmx: Boolean;
  var aColor: TColor; var aAlpha: Byte; out aWriteRgb: Boolean): Boolean;

implementation

uses
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Dialogs,
  ToolsAPI,
  ColorPreview.Render,
  ColorPreview.Settings;

const
  OPAQUE     = 255;
  FORM_WIDTH = 288;

type
  TColorPickerForm = class(TForm)
  private
    FToken      : TColorToken;
    FColor      : TColor;
    FAlpha      : Byte;
    FFileIsFmx  : Boolean;
    FPreview    : TPaintBox;
    FModeCombo  : TComboBox;
    FAlphaLabel : TLabel;
    FAlphaBar   : TTrackBar;
    FLiteral    : TLabel;
    procedure BuildUI;
    procedure BuildTopRow;
    procedure BuildModeAndAlpha;
    procedure BuildButtons;
    procedure PreviewPaint(aSender: TObject);
    procedure ChooseClick(aSender: TObject);
    procedure AlphaChanged(aSender: TObject);
    procedure ModeChanged(aSender: TObject);
    function  CurrentMode: TByteOrderMode;
    function  CurrentWriteRgb: Boolean;
    function  AlphaAllowed: Boolean;
    function  WorkingAlpha: Byte;
    procedure UpdateState;
  public
    constructor CreateForToken(const aToken: TColorToken; aFileIsFmx: Boolean;
      aColor: TColor; aAlpha: Byte);
  end;

{ TColorPickerForm }

constructor TColorPickerForm.CreateForToken(const aToken: TColorToken;
  aFileIsFmx: Boolean; aColor: TColor; aAlpha: Byte);
begin
  inherited CreateNew(nil);
  FToken := aToken;
  FFileIsFmx := aFileIsFmx;
  FColor := aColor;
  FAlpha := aAlpha;
  BuildUI;
  FModeCombo.ItemIndex := Ord(GetByteOrderMode);
  FAlphaBar.Position := aAlpha;
  UpdateState;
end;

procedure TColorPickerForm.BuildUI;
begin
  Caption := 'Color Preview';
  BorderStyle := bsDialog;
  Position := poScreenCenter;
  ClientWidth := FORM_WIDTH;
  ClientHeight := 244;
  BuildTopRow;
  BuildModeAndAlpha;
  BuildButtons;
end;

procedure TColorPickerForm.BuildTopRow;
var
  LChoose: TButton;
begin
  FPreview := TPaintBox.Create(Self);
  FPreview.Parent := Self;
  FPreview.SetBounds(12, 12, 120, 64);
  FPreview.OnPaint := PreviewPaint;

  LChoose := TButton.Create(Self);
  LChoose.Parent := Self;
  LChoose.SetBounds(144, 12, 132, 30);
  LChoose.Caption := 'Choose color...';
  LChoose.OnClick := ChooseClick;

  FLiteral := TLabel.Create(Self);
  FLiteral.Parent := Self;
  FLiteral.SetBounds(144, 52, 132, 24);
  FLiteral.AutoSize := False;
end;

procedure TColorPickerForm.BuildModeAndAlpha;
var
  LModeLabel: TLabel;
begin
  LModeLabel := TLabel.Create(Self);
  LModeLabel.Parent := Self;
  LModeLabel.SetBounds(12, 88, 150, 16);
  LModeLabel.Caption := 'Byte order (hex):';

  FModeCombo := TComboBox.Create(Self);
  FModeCombo.Parent := Self;
  FModeCombo.SetBounds(12, 106, 150, 24);
  FModeCombo.Style := csDropDownList;
  FModeCombo.Items.Add('Auto (from file)');
  FModeCombo.Items.Add('BGR (VCL)');
  FModeCombo.Items.Add('RGB (FMX/web)');
  FModeCombo.OnChange := ModeChanged;

  FAlphaLabel := TLabel.Create(Self);
  FAlphaLabel.Parent := Self;
  FAlphaLabel.SetBounds(12, 140, 200, 16);

  FAlphaBar := TTrackBar.Create(Self);
  FAlphaBar.Parent := Self;
  FAlphaBar.SetBounds(10, 158, 268, 30);
  FAlphaBar.Min := 0;
  FAlphaBar.Max := OPAQUE;
  FAlphaBar.Frequency := 16;
  FAlphaBar.OnChange := AlphaChanged;
end;

procedure TColorPickerForm.BuildButtons;
var
  LOk, LCancel: TButton;
begin
  LOk := TButton.Create(Self);
  LOk.Parent := Self;
  LOk.SetBounds(118, 204, 78, 28);
  LOk.Caption := 'OK';
  LOk.Default := True;
  LOk.ModalResult := mrOk;

  LCancel := TButton.Create(Self);
  LCancel.Parent := Self;
  LCancel.SetBounds(200, 204, 78, 28);
  LCancel.Caption := 'Cancel';
  LCancel.Cancel := True;
  LCancel.ModalResult := mrCancel;
end;

function TColorPickerForm.CurrentMode: TByteOrderMode;
begin
  if FModeCombo.ItemIndex < 0 then
    Result := bomAuto
  else
    Result := TByteOrderMode(FModeCombo.ItemIndex);
end;

function TColorPickerForm.CurrentWriteRgb: Boolean;
begin
  Result := HexUsesRgbOrder(FToken, EffectiveRgbOrder(CurrentMode, FFileIsFmx));
end;

function TColorPickerForm.AlphaAllowed: Boolean;
begin
  Result := (FToken.Kind = ckAlphaName) or
            ((FToken.Kind in [ckVclHex, ckRgbHex]) and CurrentWriteRgb);
end;

function TColorPickerForm.WorkingAlpha: Byte;
begin
  if AlphaAllowed then
    Result := FAlpha
  else
    Result := OPAQUE;
end;

procedure TColorPickerForm.UpdateState;
var
  LToken: TColorToken;
begin
  FAlphaBar.Enabled := AlphaAllowed;
  FAlphaLabel.Enabled := AlphaAllowed;
  FAlphaLabel.Caption := Format('Alpha: %d', [WorkingAlpha]);
  LToken := FToken;
  LToken.Color := FColor;
  LToken.Alpha := WorkingAlpha;
  FLiteral.Caption := FormatColorLiteral(LToken, CurrentWriteRgb);
  FPreview.Invalidate;
end;

procedure TColorPickerForm.PreviewPaint(aSender: TObject);
begin
  DrawColorPreview(FPreview.Canvas, FPreview.ClientRect, FColor, WorkingAlpha);
end;

procedure TColorPickerForm.ChooseClick(aSender: TObject);
var
  LDialog: TColorDialog;
begin
  LDialog := TColorDialog.Create(Self);
  try
    LDialog.Color := ColorToRGB(FColor);
    if LDialog.Execute then
    begin
      FColor := LDialog.Color;
      UpdateState;
    end;
  finally
    LDialog.Free;
  end;
end;

procedure TColorPickerForm.AlphaChanged(aSender: TObject);
begin
  FAlpha := Byte(FAlphaBar.Position);
  UpdateState;
end;

procedure TColorPickerForm.ModeChanged(aSender: TObject);
begin
  UpdateState;
end;

function EditColor(const aToken: TColorToken; aFileIsFmx: Boolean;
  var aColor: TColor; var aAlpha: Byte; out aWriteRgb: Boolean): Boolean;
var
  LForm    : TColorPickerForm;
  LTheming : IOTAIDEThemingServices;
begin
  aWriteRgb := False;
  LForm := TColorPickerForm.CreateForToken(aToken, aFileIsFmx, aColor, aAlpha);
  try
    if Supports(BorlandIDEServices, IOTAIDEThemingServices, LTheming) and
       LTheming.IDEThemingEnabled then
    begin
      LTheming.RegisterFormClass(TColorPickerForm);
      LTheming.ApplyTheme(LForm);
    end;
    Result := LForm.ShowModal = mrOk;
    if Result then
    begin
      aColor := LForm.FColor;
      aAlpha := LForm.WorkingAlpha;
      aWriteRgb := LForm.CurrentWriteRgb;
      SetByteOrderMode(LForm.CurrentMode);
    end;
  finally
    LForm.Free;
  end;
end;

end.
