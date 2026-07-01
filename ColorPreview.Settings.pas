unit ColorPreview.Settings;

{ Owns the global byte-order preference for bare hex color literals.

  Only 6-digit hex ($RRGGBB vs $BBGGRR) is genuinely ambiguous and governed by
  this preference; 8-digit hex is auto-detected by its high byte in the parser
  ($00xxxxxx = VCL BGR, $AAxxxxxx = FMX ARGB), and named constants are always
  order-fixed.

  Modes:
    bomAuto (default) - decide 6-digit order per file: FMX unit -> RGB, else BGR
    bomBgr            - force VCL BGR
    bomRgb            - force RGB/web order
  The value is persisted under the IDE's own registry key. }

interface

type
  TByteOrderMode = (bomAuto, bomBgr, bomRgb);

/// <summary>Current global byte-order mode (default bomAuto).</summary>
function GetByteOrderMode: TByteOrderMode;

/// <summary>Sets the byte-order mode and writes it through to the registry.</summary>
procedure SetByteOrderMode(aValue: TByteOrderMode);

/// <summary>Resolves the effective RGB-order flag for ambiguous 6-digit hex,
///  given the current mode and whether the current file is an FMX unit.</summary>
function EffectiveRgbOrder(aMode: TByteOrderMode; aFileIsFmx: Boolean): Boolean;

implementation

uses
  System.Win.Registry,
  Winapi.Windows,
  ToolsAPI;

const
  SETTINGS_SUBKEY = '\ColorPreview';
  VALUE_MODE      = 'ByteOrderMode';
  MODE_MIN        = Ord(Low(TByteOrderMode));
  MODE_MAX        = Ord(High(TByteOrderMode));

var
  GLoaded : Boolean = False;
  GMode   : TByteOrderMode = bomAuto;

function RegistryKey: string;
begin
  Result := (BorlandIDEServices as IOTAServices).GetBaseRegistryKey + SETTINGS_SUBKEY;
end;

procedure LoadSetting;
var
  LReg   : TRegistry;
  LValue : Integer;
begin
  GLoaded := True;
  LReg := TRegistry.Create(KEY_READ);
  try
    LReg.RootKey := HKEY_CURRENT_USER;
    if LReg.OpenKeyReadOnly(RegistryKey) and LReg.ValueExists(VALUE_MODE) then
    begin
      LValue := LReg.ReadInteger(VALUE_MODE);
      if (LValue >= MODE_MIN) and (LValue <= MODE_MAX) then
        GMode := TByteOrderMode(LValue);
    end;
  finally
    LReg.Free;
  end;
end;

function GetByteOrderMode: TByteOrderMode;
begin
  if not GLoaded then
    LoadSetting;
  Result := GMode;
end;

procedure SetByteOrderMode(aValue: TByteOrderMode);
var
  LReg: TRegistry;
begin
  GMode := aValue;
  GLoaded := True;
  LReg := TRegistry.Create(KEY_WRITE);
  try
    LReg.RootKey := HKEY_CURRENT_USER;
    if LReg.OpenKey(RegistryKey, True) then
      LReg.WriteInteger(VALUE_MODE, Ord(aValue));
  finally
    LReg.Free;
  end;
end;

function EffectiveRgbOrder(aMode: TByteOrderMode; aFileIsFmx: Boolean): Boolean;
begin
  case aMode of
    bomBgr: Result := False;
    bomRgb: Result := True;
  else
    Result := aFileIsFmx;   // bomAuto
  end;
end;

end.
