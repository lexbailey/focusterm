program focusterm;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes,
  { you can add units after this }
  XFocusListenerThread, xlib, sysutils, dateutils,
  sdposerial, math, IniFiles;

type
  TserialHandler = class(TObject)
    public
      procedure gotSerial(obj: TObject);
  end;

var
  FocusThread: TXFocusListenerThread;
  XDisplay: PDisplay;
  serial: TSdpoSerial;
  serialHandler: TserialHandler;
  conf: TINIFile;

  portName: string;
  focusColour: string;
  otherColour: string;
  fo_r_h, fo_g_h, fo_b_h, fo_r_l, fo_g_l, fo_b_l: char;
  ot_r_h, ot_g_h, ot_b_h, ot_r_l, ot_g_l, ot_b_l: char;
  l_skip, l_light, l_tot: integer;
  ls_l, ls_h, ll_l, ll_h, lt_l, lt_h : char;
  gi: integer;


const
  iniFileName = 'focusbar.conf';

function isLit(i, numLEDs: integer):boolean;
var relPos, relStart, relEnd: extended;
begin
  relPos := i/numLEDs;
  relStart := max(0,FocusThread.CurrentRect.Left) / FocusThread.RootRect.Right;
  relEnd := (FocusThread.CurrentRect.Left+FocusThread.CurrentRect.Right) / FocusThread.RootRect.Right;
  result := (relStart<=relPos) and (relPos <= relEnd);
end;

procedure waitForReply(serial: TSdpoSerial);
var startTime: int64;
begin
  startTime := DateTimeToUnix(now);
  while (not (serial.DataAvailable)) and (not(startTime + 1 < DateTimeToUnix(now))) do begin  end;
  while (serial.DataAvailable) do begin serial.ReadData end;
end;

procedure wakeSerial(serial: TSdpoSerial);
begin
  serial.WriteData('A');
  waitForReply(serial);
end;

procedure FocusChanged();
var buf : array[0..6] of char;
  i: integer;
const sleepDelay: integer = 1;
begin  {
  writeln(Format('Focus is on %d @%d,%d size: %dx%d',[
    FocusThread.CurrentWindow,
    FocusThread.CurrentRect.Left,
    FocusThread.CurrentRect.Top,
    FocusThread.CurrentRect.Right,
    FocusThread.CurrentRect.Bottom
  ]));
        }
  wakeSerial(serial);
  serial.writeData('s' + ls_h + ls_l);
  waitForReply(serial);
  serial.writeData('l' + ll_h + ll_l);
  waitForReply(serial);
  serial.writeData('t' + lt_h + lt_l);
  waitForReply(serial);
  serial.writeData('r');
  waitForReply(serial);

  for i := 0 to l_light-1 do begin
    buf[0] := 'd';

    if (isLit(i, l_light)) then begin
      buf[1] := char(fo_r_h);
      buf[2] := char(fo_g_h);
      buf[3] := char(fo_b_h);
      buf[4] := char(fo_r_l);
      buf[5] := char(fo_g_l);
      buf[6] := char(fo_b_l);
    end else
    begin
      buf[1] := char(ot_r_h);
      buf[2] := char(ot_g_h);
      buf[3] := char(ot_b_h);
      buf[4] := char(ot_r_l);
      buf[5] := char(ot_g_l);
      buf[6] := char(ot_b_l);
    end;


    serial.WriteBuffer(buf, 7);
    waitForReply(serial);
  end;
  serial.writeData('e');


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

  l_skip   := conf.ReadInteger('leds', 'skip', 0);
  l_light  := conf.ReadInteger('leds', 'use', 30);
  l_tot    := conf.ReadInteger('leds', 'total', 30);

  focusColour := conf.ReadString ('colours', 'focus', '00ff00');
  otherColour := conf.ReadString ('colours', 'other', '000000');

  if l_skip > 255 then fatalError('Cannot skip this many LEDs, max is 255');
  if l_light > 255 then fatalError('Cannot use this many LEDs, max is 255');
  if l_tot > 255 then fatalError('Maximum supported strip length is 255');

  if length(focusColour) <> 6 then fatalError('Invalid focus colour. ' +
                                                     'Expected six hex digits');
  if length(otherColour) <> 6 then fatalError('Invalid other colour. ' +
                                                     'Expected six hex digits');

  ls_l := char($40 or  (l_skip  and  $f)       );
  ls_h := char($40 or ((l_skip  and $f0) shr 4));

  ll_l := char($40 or  (l_light and  $f)       );
  ll_h := char($40 or ((l_light and $f0) shr 4));

  lt_l := char($40 or  (l_tot   and  $f)       );
  lt_h := char($40 or ((l_tot   and $f0) shr 4));

  fo_r_h := hexCharToEncInt(focusColour[1]);
  fo_r_l := hexCharToEncInt(focusColour[2]);
  fo_g_h := hexCharToEncInt(focusColour[3]);
  fo_g_l := hexCharToEncInt(focusColour[4]);
  fo_b_h := hexCharToEncInt(focusColour[5]);
  fo_b_l := hexCharToEncInt(focusColour[6]);

  ot_r_h := hexCharToEncInt(otherColour[1]);
  ot_r_l := hexCharToEncInt(otherColour[2]);
  ot_g_h := hexCharToEncInt(otherColour[3]);
  ot_g_l := hexCharToEncInt(otherColour[4]);
  ot_b_h := hexCharToEncInt(otherColour[5]);
  ot_b_l := hexCharToEncInt(otherColour[6]);

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
    while (true) do begin
      readln();
      FocusThread.interrupt;
    end;
  end else
  begin
    writeln('Unable to open X display');
  end;

end.

