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
  windows, winsock, JwaWinAble;

type
  TFocusNotifyEvent = procedure;
  TWindowsFocusListenerThread = class(TThread)
    private
      geom: TRect;
      rootgeom: TRect;
      FOnFocusNotify: TFocusNotifyEvent;
      pipi, pipo: THandle;
      InterruptInStream: TInputPipeStream;
      InterruptOutStream: TOutputPipeStream;
      procedure WaitForWindowEvent;
      procedure interrupt;
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

procedure TWindowsFocusListenerThread.interrupt;
begin
  // Interrupt the thread to trigger another update
  InterruptOutStream.WriteAnsiString('#');
end;

procedure FocusChangeCallback(hWinEventHook: HWINEVENTHOOK; dwEvent: DWORD;
  hwnd: HWND; idObject: LONG; idChild: LONG; dwEventThread: DWORD;
  dwmsEventTime: DWORD) stdcall;
begin
  if focusThreadInstance <> nil then
     focusThreadInstance.interrupt;
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
  // init interrupt pipe
  if not CreatePipeHandles(pipi,pipo, 9) then begin
    Writeln('Error assigning pipes !');
    exit;
  end;
  InterruptInStream := TInputPipeStream.create(pipi);
  InterruptOutStream := TOutputPipeStream.create(pipo);

  // Parent init
  inherited create(False);
  // Event hook for focus change
  SetWinEventHook(EVENT_SYSTEM_FOREGROUND,
  EVENT_SYSTEM_FOREGROUND, 0,
  @FocusChangeCallback, 0, 0,
  //WINEVENT_OUTOFCONTEXT or WINEVENT_SKIPOWNPROCESS
  WINEVENT_SKIPOWNPROCESS or WINEVENT_SKIPOWNTHREAD
  );
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
  // Get the currently focused window
  wfocus := GetForegroundWindow;
  if wfocus <> longword(nil) then begin
    GetWindowRect(wfocus, wrect);
    geom.Right:=geom.Right-geom.Left;
    geom.Bottom:=geom.Bottom-geom.Top;
    rootgeom.Top:=0;
    rootgeom.Left:=0;
    rootgeom.Right:=GetSystemMetrics(SM_CXVIRTUALSCREEN);
    rootgeom.Bottom:=GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (not (FOnFocusNotify = nil)) then FOnFocusNotify();
  end;
end;

procedure TWindowsFocusListenerThread.WaitForWindowEvent();
var
  FDS : Tfdset;
begin
  FD_Zero (FDS);
  FD_Set (pipi,FDS);
  Select (pipi+1,@FDS,nil,nil,nil);
  if InterruptInStream.NumBytesAvailable > 0 then begin
    while (InterruptInStream.NumBytesAvailable > 0) do
      InterruptInStream.ReadAnsiString;
  end;
end;

procedure TWindowsFocusListenerThread.Execute();
begin
  // When the thread first starts, it should get the focused window
  updateFocusedWindowData();
  while(not Terminated) do begin
    // WaitForWindowEvent will block until there is an event
    WaitForWindowEvent;
    // After an event has occured, if the thread should still run then we need
    // to update the focused window data.
    if not Terminated then updateFocusedWindowData();
  end;
end;

end.


