unit XFocusListenerThread;

{$mode objfpc}{$H+}

interface

uses
  Classes,
  xlib, x, ctypes, cmem, BaseUnix, Unix, pipes, math;

type
  TFocusNotifyEvent = procedure;
  TXFocusListenerThread = class(TThread)
    private
      FXDisplay: PDisplay;
      FCurrentWindow: TWindow;
      geom: TRect;
      rootgeom: TRect;
      FOnFocusNotify: TFocusNotifyEvent;
      pipi, pipo: longint;
      InterruptInStream: TInputPipeStream;
      InterruptOutStream: TOutputPipeStream;
      procedure WaitForXEvent;
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
      procedure interrupt;
  end;

var
  focusThreadInstance: TXFocusListenerThread = nil;

implementation

procedure TXFocusListenerThread.interrupt;
begin
  // Interrupt the thread to trigger another update
  InterruptOutStream.WriteAnsiString('#');
end;

function XErrorIgnoreBadWindow(EXDisplay: PDisplay;
            ErrorEvent: PXErrorEvent): cint;
var
  buf: PChar;
begin
  // If this is a BadWidow error then ignore it
  if ErrorEvent^.error_code = BadWindow then begin
  end else
  begin
    // For any other error, print the message and die
    buf := malloc(256);
    XGetErrorText(EXDisplay, ErrorEvent^.error_code, buf, 255);
    writeln('Unexpected X error: ', buf);
    free(buf);
    halt(1);
  end;
end;

// Constructor that sets some fields and starts the thread
constructor TXFocusListenerThread.Create(_XDisplay: PDisplay;
  _OnFocusNotify: TFocusNotifyEvent);
begin
  // To get around callback issues, this unit contains a reference to an
  // instance of itself. This means there can only be one instance
  if focusThreadInstance <> nil then
     exit;
  // Init fields
  FXDisplay := _XDisplay;
  FOnFocusNotify := _OnFocusNotify;
  // Create a pipe for interrupting the thread if needed.
  if assignpipe(pipi,pipo) <> 0 then begin
    Writeln('Error assigning pipes !');
    exit;
  end;
  InterruptInStream := TInputPipeStream.create(pipi);
  InterruptOutStream := TOutputPipeStream.create(pipo);
  // Use our custom error handler that ignores BadWindow.
  XSetErrorHandler(TXErrorHandler(@XErrorIgnoreBadWindow));
  // Parent init
  inherited create(False);
  // All done, keep a reference to ourself handy in this unit.
  focusThreadInstance := self;
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

   didError: boolean;
begin

  didError := false;

  // Get the currently focused window into a local variable (not the field yet)
  XGetInputFocus(FXDisplay, @wfocus, @return_to);
  // WFocus now contains a window id for a window that is focused but might not
  // be a top level window, walk up the tree until we find a top level window
  if wfocus <> None then begin
    repeat
      // Get parent into wparent
      if XQueryTree(FXDisplay, wfocus, @wroot, @wparent, @children, @nchildren)
                                                         <> 0 then begin
        // don't care about the children, free them
        if nchildren > 0 then
            XFree(children);
        // If the parent of this window is the root window then this is a top
        // level
        if wparent = wroot then begin
          break;
        end else
          // Not yet found top level, check parent
          wfocus := wparent;
      end else
      begin
        // If there was a problem getting the parent, mark the error and break
        didError := True;
        break;
      end;
    until false;

    if not didError then begin
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
    end else
    begin
      // If there was an error, set the curent window to 0
      FCurrentWindow:=0;
    end;
  end;
end;

// Wait for an X event to be available, when it is, discard it and return
// (We don't care much about the event, we just need to know it happened)
procedure TXFocusListenerThread.WaitForXEvent;
var
  nextxevent: TXEvent;
  FDS : Tfdset;
  XFD : cint;
begin
  // Select the 'FocusChange' and 'StructureNotify' events for the focused
  // window
  XSelectInput(FXDisplay, FCurrentWindow,
                          FocusChangeMask or StructureNotifyMask);
  // Wait for the next event on that window or for an interrupt from the pipe.
  // To do this, first we create a descriptor set with the X event queue and
  // the interrupt pipe.
  fpFD_Zero (FDS);                    // New file descriptor set
  XFlush(FXDisplay);                  // flush
  XFD := ConnectionNumber(FXDisplay); // Get the X event queue file descriptor
  fpFD_Set (XFD,FDS);                 // Add the X event Q FD to the set
  fpFD_Set (pipi,FDS);                // Add the interrupt pipe FD to the set
  // select on the file handles for X event queue and our internal interrupt
  // pipe. This blocks until one of them has data to read.
  fpSelect (max(pipi, XFD)+1,@FDS,nil,nil,nil);
  // As soon as there is something to do, we continue here...
  while (XPending(FXDisplay) > 0) do begin
    // If we continued because there was an X event, we deal with it here.
    XNextEvent(FXDisplay, @nextxevent);
  end;

  if InterruptInStream.NumBytesAvailable > 0 then begin
    // If we continued because there was an interrupt, we dea with it here
    writeln('Interrupt');
    //Interrupt fired, clear up waiting data to mark interrupt as complete
    while (InterruptInStream.NumBytesAvailable > 0) do
      InterruptInStream.ReadAnsiString;
  end;

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

