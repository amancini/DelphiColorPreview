unit ColorPreview.Register;

{ Package entry point: registers the color-preview editor-events notifier when
  the design-time package is loaded and removes it when it is unloaded. }

interface

implementation

uses
  System.SysUtils,
  ToolsAPI,
  ToolsAPI.Editor,
  ColorPreview.Notifier;

var
  GNotifier      : INTACodeEditorEvents;   // keeps the notifier instance alive
  GNotifierIndex : Integer;

procedure RegisterNotifier;
var
  LServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, LServices) then
  begin
    GNotifier := TColorPreviewNotifier.Create;
    GNotifierIndex := LServices.AddEditorEventsNotifier(GNotifier);
  end;
end;

procedure UnregisterNotifier;
var
  LServices: INTACodeEditorServices;
begin
  if (GNotifierIndex > 0) and
     Supports(BorlandIDEServices, INTACodeEditorServices, LServices)
  then
    LServices.RemoveEditorEventsNotifier(GNotifierIndex);
  GNotifier := nil;
  GNotifierIndex := 0;
end;

initialization
  RegisterNotifier;

finalization
  UnregisterNotifier;

end.
