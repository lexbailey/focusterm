program focusterm;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes,
  { you can add units after this }
  {$IFDEF UNIX}
  XFocusListenerThread, xlib,
  {$ENDIF}
  {$IFDEF WINDOWS}
  WindowsFocusListenerThread,
  windows, messages,
  JwaWinAble,
  {$ENDIF}
  sysutils, dateutils,
  sdposerial, math, IniFiles, SerialSenderThread;

type
  TserialHandler = class(TObject)
    public
      procedure gotSerial(obj: TObject);
  end;

var
  {$IFDEF UNIX}
  FocusThread: TXFocusListenerThread;
  XDisplay: PDisplay;
  {$ENDIF}
  {$IFDEF WINDOWS}
  FocusThread: TWindowsFocusListenerThread;
  {$ENDIF}
  SerialThread: TSerialSenderThread;
  serial: TSdpoSerial;
  serialHandler: TserialHandler;
  conf: TINIFile;

  portName: string;
  focusColour: string;
  otherColour: string;
  cursorColour: string;
  MyLEDSettings: TLEDSettings;
  gi: integer;

  lastStart, lastStop: integer;

  lastCurx : integer;

  attempts: integer;

  iniFileName : string;

  isValid : boolean;

  {$IFDEF WINDOWS}
  message : MSG;
  {$ENDIF}

const

  attemptLimit = 10;


procedure FocusChanged();
var
  hasChanged: boolean;
  thisStart, thisStop: integer;
  thisCurx: integer;
const sleepDelay: integer = 1;
begin
  thisStart := max(0,FocusThread.CurrentRect.Left);
  thisStop := FocusThread.CurrentRect.Left+FocusThread.CurrentRect.Right;
  thisCurx := FocusThread.CursorPos.x;

  hasChanged := (thisStart <> lastStart) or (thisStop <> lastStop)
             or (thisCurx <> lastCurx);

  if hasChanged then begin
    lastStart := thisStart;
    lastStop := thisStop;
    SerialThread.interrupt;
  end;

end;

procedure TserialHandler.gotSerial(obj: TObject);
begin
  while serial.DataAvailable do begin
    writeln(serial.ReadData);
  end;
end;

procedure fatalError(err: string);
begin
  writeln('Fatal error: ' + err);
  halt(1);
end;

function hexCharToEncInt(h: char): char;
begin
  case h of
    '0': result := char($0);
    '1': result := char($1);
    '2': result := char($2);
    '3': result := char($3);
    '4': result := char($4);
    '5': result := char($5);
    '6': result := char($6);
    '7': result := char($7);
    '8': result := char($8);
    '9': result := char($9);
    'a', 'A': result := char($a);
    'b', 'B': result := char($b);
    'c', 'C': result := char($c);
    'd', 'D': result := char($d);
    'e', 'E': result := char($e);
    'f', 'F': result := char($f);
  else fatalError('Invalid character in hex string: ' + h);
  end;

  result := char(ord(result) or $40)

end;

begin

  {$IFDEF UNIX}
  iniFileName := GetUserDir + '/.focusbar.conf';
  {$ENDIF}
  {$IFDEF WINDOWS}
  iniFileName := GetEnvironmentVariable('appdata') + '/focusbar/focusbar.conf';
  {$ENDIF}

  conf := TIniFile.Create(iniFileName);

  {$IFDEF UNIX}
  portName := conf.ReadString ('connection', 'port', '/dev/ttyUSB0');
  {$ENDIF}
  {$IFDEF WINDOWS}
  portName := conf.ReadString ('connection', 'port', 'COM1');
  {$ENDIF}


  MyLEDSettings.l_skip   := conf.ReadInteger('leds', 'skip', 0);
  MyLEDSettings.l_light  := conf.ReadInteger('leds', 'use', 30);
  MyLEDSettings.l_tot    := conf.ReadInteger('leds', 'total', 30);
  MyLEDSettings.rev      := conf.ReadBool('leds', 'reverse', false);
  MyLEDSettings.mouse    := conf.ReadBool('leds', 'showmouse', true);

  focusColour := conf.ReadString ('colours', 'focus', '00ff00');
  otherColour := conf.ReadString ('colours', 'other', '000000');
  cursorColour := conf.ReadString ('colours', 'cursor', '7f2222');

  if MyLEDSettings.l_skip > 255 then fatalError('Cannot skip this many LEDs, max is 255');
  if MyLEDSettings.l_light > 255 then fatalError('Cannot use this many LEDs, max is 255');
  if MyLEDSettings.l_tot > 255 then fatalError('Maximum supported strip length is 255');

  if length(focusColour) <> 6 then fatalError('Invalid focus colour. ' +
                                                     'Expected six hex digits');
  if length(otherColour) <> 6 then fatalError('Invalid other colour. ' +
                                                     'Expected six hex digits');

  MyLEDSettings.ls_l := char($40 or  (MyLEDSettings.l_skip  and  $f)       );
  MyLEDSettings.ls_h := char($40 or ((MyLEDSettings.l_skip  and $f0) shr 4));

  MyLEDSettings.ll_l := char($40 or  (MyLEDSettings.l_light and  $f)       );
  MyLEDSettings.ll_h := char($40 or ((MyLEDSettings.l_light and $f0) shr 4));

  MyLEDSettings.lt_l := char($40 or  (MyLEDSettings.l_tot   and  $f)       );
  MyLEDSettings.lt_h := char($40 or ((MyLEDSettings.l_tot   and $f0) shr 4));

  MyLEDSettings.fo_r_h := hexCharToEncInt(focusColour[1]);
  MyLEDSettings.fo_r_l := hexCharToEncInt(focusColour[2]);
  MyLEDSettings.fo_g_h := hexCharToEncInt(focusColour[3]);
  MyLEDSettings.fo_g_l := hexCharToEncInt(focusColour[4]);
  MyLEDSettings.fo_b_h := hexCharToEncInt(focusColour[5]);
  MyLEDSettings.fo_b_l := hexCharToEncInt(focusColour[6]);

  MyLEDSettings.ot_r_h := hexCharToEncInt(otherColour[1]);
  MyLEDSettings.ot_r_l := hexCharToEncInt(otherColour[2]);
  MyLEDSettings.ot_g_h := hexCharToEncInt(otherColour[3]);
  MyLEDSettings.ot_g_l := hexCharToEncInt(otherColour[4]);
  MyLEDSettings.ot_b_h := hexCharToEncInt(otherColour[5]);
  MyLEDSettings.ot_b_l := hexCharToEncInt(otherColour[6]);

  MyLEDSettings.cc_r_h := hexCharToEncInt(cursorColour[1]);
  MyLEDSettings.cc_r_l := hexCharToEncInt(cursorColour[2]);
  MyLEDSettings.cc_g_h := hexCharToEncInt(cursorColour[3]);
  MyLEDSettings.cc_g_l := hexCharToEncInt(cursorColour[4]);
  MyLEDSettings.cc_b_h := hexCharToEncInt(cursorColour[5]);
  MyLEDSettings.cc_b_l := hexCharToEncInt(cursorColour[6]);

  serial := TSdpoSerial.Create(nil);
  serial.BaudRate:=br115200;
  serial.StopBits:=sbOne;
  serial.DataBits:=db8bits;
  serial.Parity:=pNone;
  serial.FlowControl:=fcHardware;
  serial.Device:=portName;
  serialHandler := TserialHandler.Create;
  serial.OnRxData:=@serialHandler.gotSerial;
  attempts := 0;
  try
    serial.Active:=true;
  except
    while (attempts < attemptLimit) do begin
      sleep(10000);
      Writeln('Connecting to ' + portName + '...');
      inc(attempts);
      try
        serial.Active:=true;
      except
      end;
    end;
  end;


  {$IFDEF UNIX}
  XDisplay := XOpenDisplay(nil);
  isValid := not (XDisplay = nil);
  {$ENDIF}

  {$IFDEF WINDOWS}
  isValid := true;
  {$ENDIF}

  if isValid then begin
    {$IFDEF UNIX}
    FocusThread := TXFocusListenerThread.Create(XDisplay, @FocusChanged);
    {$ENDIF}
    {$IFDEF WINDOWS}
    FocusThread := TWindowsFocusListenerThread.Create(@FocusChanged);
    {$ENDIF}
    SerialThread := TSerialSenderThread.create(serial, FocusThread);
    SerialThread.LEDSettings := MyLEDSettings;
    while (true) do begin
      {$IFDEF UNIX}
      // For unix systems, this thread can now sleep forever.
      // However, the focus thread is interrupted whenever a line can
      // be read from stdin. This is handy for debugging.
      readln();
      FocusThread.interrupt;
      {$ENDIF}
      {$IFDEF WINDOWS}
      // In windows, we need to use this loop to process application messages
      if GetMessage(@message, QWord(nil), 0, 0) then begin
         TranslateMessage(@message);
         DispatchMessage(@message);
      end;
      {$ENDIF}
    end;
  end else
  begin
    {$IFDEF UNIX}
    writeln('Unable to open X display');
    {$ENDIF}
    {$IFDEF WINDOWS}
    writeln('Huh, this shouldn''t happen!')
    {$ENDIF}
  end;

end.

