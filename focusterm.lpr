program focusterm;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes,
  { you can add units after this }
  XFocusListenerThread, xlib, sysutils;

var
  FocusThread: TXFocusListenerThread;
  XDisplay: PDisplay;

procedure FocusChanged();
begin
  writeln(Format('Focus is on %d @%d,%d size: %dx%d',[
    FocusThread.CurrentWindow,
    FocusThread.CurrentRect.Left,
    FocusThread.CurrentRect.Top,
    FocusThread.CurrentRect.Right,
    FocusThread.CurrentRect.Bottom
  ]));
end;

begin
  XDisplay := XOpenDisplay(nil);
  if not (XDisplay = nil) then begin
    FocusThread := TXFocusListenerThread.Create(XDisplay, @FocusChanged);
    readln();
  end else
  begin
    writeln('Unable to open X display');
  end;

end.

