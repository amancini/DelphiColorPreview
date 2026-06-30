# DelphiColorPreview

A lightweight RAD Studio (Delphi 12 Athens) IDE plugin that shows a **color swatch
in the editor gutter** next to every color literal in your source — like the color
decorators in VS Code — and lets you **Shift+click** a swatch to pick a new color,
rewriting the literal directly in your code.

![DelphiColorPreview in action](docs/preview.svg)

## Features

- Color swatches in the left gutter, on every line that contains a color literal.
- Recognizes three Delphi color forms:

  | Form          | Example                | Notes                                                        |
  |---------------|------------------------|--------------------------------------------------------------|
  | `clXXX`       | `clRed`, `clBtnFace`   | VCL named constants; system colors resolved to their real RGB |
  | `$00BBGGRR`   | `$00FF8040`            | `TColor` hex (BGR byte order); 6–8 hex digits                 |
  | `RGB(r,g,b)`  | `RGB(255, 128, 0)`     | integer-literal arguments only                               |

- Edit colors straight from the gutter (see Usage).
- No configuration, no toolbar, no menu — build, install, done.

## Requirements

- RAD Studio 12 Athens (Delphi, compiler 36.0 / package version `290`).
- Win32 design-time package (the IDE host is a 32-bit process).

## Installation

1. Open `DelphiColorPreview.dproj` in RAD Studio 12.
2. **Build** the project.
3. Right-click the project in the Project Manager → **Install**.

That's it — the swatches show up in the editor gutter immediately. To uninstall,
right-click the project → **Uninstall** (or remove it from
*Component → Install Packages…*).

> Prefer the command line? Run `build.bat` (it calls `rsvars.bat` + `msbuild`, Win32 /
> Debug) and then do step 3 in the IDE.

## Usage

- A color swatch appears in the gutter next to every line that has a color literal —
  with or without a breakpoint on that line.
- **Shift+click** a swatch to open a color picker. Choosing a color **rewrites the
  literal in your code**, keeping the original form:
  - `$00BBGGRR` stays a hex literal,
  - `RGB(r, g, b)` stays an `RGB()` call,
  - `clXXX` becomes the matching named constant when one exists (otherwise a hex literal).
- The edit goes through the editor buffer, so **Ctrl+Z** undoes it like any other change.
- A plain (non-Shift) click is left untouched, so the gutter still works for breakpoints.

## How it works

The package registers a single global `INTACodeEditorEvents` notifier through
`(BorlandIDEServices as INTACodeEditorServices).AddEditorEventsNotifier`.

- Swatches are painted at the `pgsEndPaint` gutter stage, which runs once after the
  whole gutter is drawn with a clip covering the entire gutter. The plugin enumerates
  the visible lines (`EditorState.TopLine..BottomLine` → `LineState[]`) and draws a
  swatch in each line's `GutterRect`. Using the line's own gutter rectangle means there
  is no column-to-pixel math, so the swatch never drifts.
- Line text and geometry come straight from `INTACodeEditorLineState` (`.Text`,
  `.GutterRect`).
- Editing goes through `IOTAEditView.Buffer.EditPosition` (`Move` / `Delete` /
  `InsertText`) so the IDE records a normal, undoable edit.

### Source layout

| File                         | Responsibility                                              |
|------------------------------|-------------------------------------------------------------|
| `ColorPreview.Parser.pas`    | `FindColorTokens` — scans one line into color tokens        |
| `ColorPreview.Notifier.pas`  | `TColorPreviewNotifier` — paints swatches, handles the click |
| `ColorPreview.Register.pas`  | registers / unregisters the notifier on package load        |
| `DelphiColorPreview.dpk`     | the design-only package (`requires rtl, vcl, designide`)    |

## License

[MIT](LICENSE)
