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
  windows, winsock, JwaWinAble, Messages;

type
  TFocusNotifyEvent = procedure;
  TWindowsFocusListenerThread = class(TThread)
    private
      geom: TRect;
      rootgeom: TRect;
      fcursorPos: TPoint;
      FOnFocusNotify: TFocusNotifyEvent;
      pipi, pipo: THandle;
      InterruptInStream: TInputPipeStream;
      InterruptOutStream: TOutputPipeStream;
      procedure WaitForWindowEvent;
    public
      procedure updateFocusedWindowData;
      // Note that these rects are used to store width and height in the right
      // and bottom fields
      property CurrentRect: TRect read geom;
      property RootRect: TRect read rootgeom;
      property CursorPos: TPoint read fcursorpos;
      property OnFocusNotify: TFocusNotifyEvent write FOnFocusNotify;
      procedure Execute; override;
      procedure interrupt;
      constructor Create(_OnFocusNotify: TFocusNotifyEvent);
  end;

var
  focusThreadInstance: TWindowsFocusListenerThread = nil;

implementation

procedure TWindowsFocusListenerThread.interrupt;
begin
  // Interrupt the thread to trigger another update
  InterruptOutStream.WriteByte(0);
end;

procedure FocusChangeCallback(hWinEventHook: HWINEVENTHOOK; dwEvent: DWORD;
  hwnd: HWND; idObject: LONG; idChild: LONG; dwEventThread: DWORD;
  dwmsEventTime: DWORD) stdcall;
begin
  if focusThreadInstance <> nil then
     focusThreadInstance.interrupt;
end;

procedure hookInto(eventID: cardinal);
var
  hook  : HWINEVENTHOOK ;
  hookCallBack : WINEVENTPROC;
begin
  hookCallBack := WINEVENTPROC(@FocusChangeCallback);
  hook := SetWinEventHook(eventID, eventID, 0, hookCallBack, 0, 0,
  WINEVENT_OUTOFCONTEXT or WINEVENT_SKIPOWNPROCESS
  );
  if (hook = 0) then begin
     writeln('Fatal error: Couldn''t get windows event hook');
     exit;
  end;
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
  hookInto(EVENT_SYSTEM_FOREGROUND);
  hookInto(EVENT_OBJECT_LOCATIONCHANGE);
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
    windows.GetCursorPos(fcursorPos);
    if (not (FOnFocusNotify = nil)) then FOnFocusNotify();
  end;
end;

procedure TWindowsFocusListenerThread.WaitForWindowEvent();
begin
  InterruptInStream.ReadByte;
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


