program focusterm;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes,
  { you can add units after this }
  XFocusListenerThread, xlib, sysutils, dateutils,
  sdposerial, math, IniFiles, SerialSenderThread;

type
  TserialHandler = class(TObject)
    public
      procedure gotSerial(obj: TObject);
  end;

var
  FocusThread: TXFocusListenerThread;
  SerialThread: TSerialSenderThread;
  XDisplay: PDisplay;
  serial: TSdpoSerial;
  serialHandler: TserialHandler;
  conf: TINIFile;

  portName: string;
  focusColour: string;
  otherColour: string;
  MyLEDSettings: TLEDSettings;
  gi: integer;

  lastStart, lastStop: integer;


const
  iniFileName = 'focusbar.conf';



procedure FocusChanged();
var
  hasChanged: boolean;
  thisStart, thisStop: integer;
const sleepDelay: integer = 1;
begin
  writeln(Format('Focus is on %d @%d,%d size: %dx%d',[
    FocusThread.CurrentWindow,
    FocusThread.CurrentRect.Left,
    FocusThread.CurrentRect.Top,
    FocusThread.CurrentRect.Right,
    FocusThread.CurrentRect.Bottom
  ]));


  thisStart := max(0,FocusThread.CurrentRect.Left);
  thisStop := FocusThread.CurrentRect.Left+FocusThread.CurrentRect.Right;

  hasChanged := (thisStart <> lastStart) or (thisStop <> lastStop);

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

  conf := TIniFile.Create(iniFileName);

  portName := conf.ReadString ('connection', 'port', '/dev/ttyUSB0');

  MyLEDSettings.l_skip   := conf.ReadInteger('leds', 'skip', 0);
  MyLEDSettings.l_light  := conf.ReadInteger('leds', 'use', 30);
  MyLEDSettings.l_tot    := conf.ReadInteger('leds', 'total', 30);

  focusColour := conf.ReadString ('colours', 'focus', '00ff00');
  otherColour := conf.ReadString ('colours', 'other', '000000');

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

  serial := TSdpoSerial.Create(nil);
  serial.BaudRate:=br115200;
  serial.StopBits:=sbOne;
  serial.DataBits:=db8bits;
  serial.Parity:=pNone;
  serial.FlowControl:=fcHardware;
  serial.Device:=portName;
  serialHandler := TserialHandler.Create;
  serial.OnRxData:=@serialHandler.gotSerial;
  serial.Active:=true;

  XDisplay := XOpenDisplay(nil);
  if not (XDisplay = nil) then begin
    FocusThread := TXFocusListenerThread.Create(XDisplay, @FocusChanged);
    SerialThread := TSerialSenderThread.create(serial, FocusThread);
    SerialThread.LEDSettings := MyLEDSettings;
    while (true) do begin
      readln();
      FocusThread.interrupt;
    end;
  end else
  begin
    writeln('Unable to open X display');
  end;

end.

