unit windowsfocuslistenerthread;
{
See header description for TXFocusListenerThread.
This does that but for windows.
}

{$mode objfpc}{$H+}

interface

uses
  Classes,
  pipes,
  windows,
  JwaWinAble;

type
  TFocusNotifyEvent = procedure;
  TWindowsFocusListenerThread = class(TThread)
    private
      geom: TRect;
      rootgeom: TRect;
      FOnFocusNotify: TFocusNotifyEvent;
      pipi, pipo: longint;
      InterruptInStream: TInputPipeStream;
      InterruptOutStream: TOutputPipeStream;
      procedure WaitForWindowEvent;
    public
      procedure updateFocusedWindowData;
      // Note that these rects are used to store width and height in the right
      // and bottom fields
      property CurrentRect: TRect read geom;
      property RootRect: TRect read rootgeom;
      property OnFocusNotify: TFocusNotifyEvent write FOnFocusNotify;
      procedure Execute; override;
      constructor Create(_OnFocusNotify: TFocusNotifyEvent);
  end;

var
  focusThreadInstance: TWindowsFocusListenerThread = nil;

implementation


procedure FocusChangeCallback(hWinEventHook: HWINEVENTHOOK; dwEvent: DWORD;
  hwnd: HWND; idObject: LONG; idChild: LONG; dwEventThread: DWORD;
  dwmsEventTime: DWORD) stdcall;
begin
end;

// Constructor that sets some fields and starts the thread
constructor TWindowsFocusListenerThread.Create(_OnFocusNotify: TFocusNotifyEvent);
begin
  // To get around callback issues, this unit contains a reference to an
  // instance of itself. This means there can only be one instance
  if focusThreadInstance <> nil then
     exit;
  // Init fields
  FOnFocusNotify := _OnFocusNotify;
  // Parent init
  inherited create(False);

 { SetWinEventHook(EVENT_SYSTEM_FOREGROUND,
  EVENT_SYSTEM_FOREGROUND, NULL,
  @FocusChangeCallback, 0, 0,
  WINEVENT_OUTOFCONTEXT or WINEVENT_SKIPOWNPROCESS);
  }
  // All done, keep a reference to ourself handy in this unit.
  focusThreadInstance := self;
end;

// Get the currently focused window ID, its geometry and the root window
// geometry
procedure TWindowsFocusListenerThread.updateFocusedWindowData();
var
   // Various window IDs
   wfocus: HWND;

   wrect: LPRECT;
begin
  wrect := @geom;
  // Get the currently focused window into a local variable (not the field yet)
  wfocus := GetForegroundWindow;
  writeln('update');
  if wfocus <> longword(nil) then begin
    writeln('gotwindow');
    GetWindowRect(wfocus, wrect);
    geom.Right:=geom.Right-geom.Left;
    geom.Bottom:=geom.Bottom-geom.Top;
    writeln('gotwindow2');
    //geom.Left := wrect^.Left;
    //geom.Top := wrect^.Top;
    //geom.Right := wrect^.Right;
    //geom.Bottom := wrect^.Bottom;
    writeln('gotwindow3');

    rootgeom.Top:=0;
    rootgeom.Left:=0;
    rootgeom.Right:=GetSystemMetrics(SM_CXVIRTUALSCREEN);
    rootgeom.Bottom:=GetSystemMetrics(SM_CYVIRTUALSCREEN);

    if (not (FOnFocusNotify = nil)) then FOnFocusNotify();
  end;
end;

procedure TWindowsFocusListenerThread.WaitForWindowEvent();
begin
  sleep(100);
//  EVENT_SYSTEM_FOREGROUND
end;

procedure TWindowsFocusListenerThread.Execute();
begin
  // When the thread first starts, it should get the focused window
  updateFocusedWindowData();
  while(not Terminated) do begin
    writeln('loop');
    // WaitForWindowEvent will block until there is an event
    WaitForWindowEvent;
    writeln('event');
    // After an event has occured, if the thread should still run then we need
    // to update the focused window data.
    if not Terminated then updateFocusedWindowData();
  end;
end;

end.


