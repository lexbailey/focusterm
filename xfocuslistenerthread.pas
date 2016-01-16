unit XFocusListenerThread;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils,
  xlib, x, ctypes, BaseUnix,Unix;

type
  TFocusNotifyEvent = procedure;
  TXFocusListenerThread = class(TThread)
    private
      FXDisplay: PDisplay;
      FCurrentWindow: TWindow;
      geom: TRect;
      rootgeom: TRect;
      FOnFocusNotify: TFocusNotifyEvent;
      pipi, pipo: Text;
      procedure WaitForXEvent;
      function XErrorIgnoreBadWindow(EXDisplay: PDisplay;
                                                ErrorEvent: PXErrorEvent): cint;
    public
      procedure updateFocusedWindowData;
      property XDisplay: PDisplay write FXDisplay;
      property CurrentWindow: TWindow read FCurrentWindow;
      property CurrentRect: TRect read geom;
      property RootRect: TRect read rootgeom;
      property OnFocusNotify: TFocusNotifyEvent write FOnFocusNotify;
      procedure Execute; override;
      constructor Create(_XDisplay: PDisplay;
                  _OnFocusNotify: TFocusNotifyEvent);
  end;

implementation

function TXFocusListenerThread.XErrorIgnoreBadWindow(EXDisplay: PDisplay;
            ErrorEvent: PXErrorEvent): cint;
begin
  Writeln(pipo,''); // Interrupt the thread to trigger another update
  result := 0;
end;

// Constructor that sets some fields and starts the thread
constructor TXFocusListenerThread.Create(_XDisplay: PDisplay;
  _OnFocusNotify: TFocusNotifyEvent);
begin
  FXDisplay := _XDisplay;
  FOnFocusNotify := _OnFocusNotify;
  if assignpipe(pipi,pipo) <> 0 then
    Writeln('Error assigning pipes !');
    exit(1);
  XSetErrorHandler(TXErrorHandler(@this.XErrorIgnoreBadWindow));
  inherited create(False);
end;

// Get the currently focused window ID, its geometry and the root window
// geometry
procedure TXFocusListenerThread.updateFocusedWindowData();
var
   // Various window IDs
   wroot, wfocus, wparent: TWindow;

   // Window geometry variables
   x, y: cint;
   width, height, border_width, depth: cuint;

   // Unused variables, needed to match function signiature
   children: ^TWindow;
   nchildren: cint;
   return_to: cint;
begin

  // Get the currently focused window into a local variable (not the field yet)
  XGetInputFocus(FXDisplay, @wfocus, @return_to);
  // WFocus now contains a window id for a window that is focused but might not
  // be a top level window

  // Walk up the tree until we find a top level window
  repeat
    // Get parent into wparent
    XQueryTree(FXDisplay, wfocus, @wroot, @wparent, @children, @nchildren);
    // don't care about the children, free them
    XFree(children);
    // If the parent of this window is the root window then this is a top level
    if wparent = wroot then begin
      break;
    end else
      // Not yet found top level, check parent
      wfocus := wparent;
  until false;

  // We have a top level window, update the current window ID field
  FCurrentWindow := wfocus;
  // Get the gemoetry
  XGetGeometry(FXDisplay, wfocus, @wroot, @x, @y, @width, @height,
                          @border_width, @depth);
  geom := Rect(x,y, width, height);

  // Also get the geometry for the root window
  XGetGeometry(FXDisplay, wroot, @wroot, @x, @y, @width, @height,
                          @border_width, @depth);
  rootgeom := Rect(x,y, width, height);

  //If the callback is set, call it
  if not (FOnFocusNotify = nil) then FOnFocusNotify();
end;

// Wait for an X event to be available, when it is, discard it and return
// (We don't care much about the event, we just need to know it happened)
procedure TXFocusListenerThread.WaitForXEvent;
var
  nextxevent: TXEvent;
  FDS : FDSet;
  XFD : cint;
begin
  // Select the 'FocusChange' and 'StructureNotify' events for the focused
  // window
  XSelectInput(FXDisplay, FCurrentWindow,
                          FocusChangeMask or StructureNotifyMask);
  // Wait for the next event on that window or for an interrupt from the pipe
  // Create a descriptor set with the X event queue and the interrupt pipe
  FD_Zero (FDS);
  FD_Set (pipi,FDS);
  XFD := ConnectionNumber(FXDisplay);
  Select (1,@FDS,nil,nil,nil);
  while(XPending(FXDisplay))
    XNextEvent(FXDisplay, @nextxevent);
  // Deselect all events for this window
  XSelectInput(FXDisplay, FCurrentWindow, NoEventMask);
end;

procedure TXFocusListenerThread.Execute();
begin
  // When the thread first starts, it should get the focused window
  updateFocusedWindowData();
  while(not Terminated) do begin
    // WaitForXEvent will block until there is an event
    WaitForXEvent;
    // After an event has occured, if the thread should still run then we need
    // to update the focused window data.
    if not Terminated then updateFocusedWindowData();
  end;
end;

end.

