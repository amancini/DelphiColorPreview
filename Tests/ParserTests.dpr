program ParserTests;

{$APPTYPE CONSOLE}
{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.TestFramework,
  DUnitX.Loggers.Console,
  ColorPreview.Parser in '..\ColorPreview.Parser.pas',
  TestColorParser in 'TestColorParser.pas';

var
  LRunner  : ITestRunner;
  LResults : IRunResults;
begin
  LRunner := TDUnitX.CreateRunner;
  LRunner.AddLogger(TDUnitXConsoleLogger.Create(True));
  LResults := LRunner.Execute;
  if not LResults.AllPassed then
    ExitCode := 1;
end.
