unit SerialSenderThread;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SdpoSerial, Unix, pipes, XFocusListenerThread, math, dateutils,
  BaseUnix;

type

  TLEDSettings = record
    fo_r_h, fo_g_h, fo_b_h, fo_r_l, fo_g_l, fo_b_l: char;
    ot_r_h, ot_g_h, ot_b_h, ot_r_l, ot_g_l, ot_b_l: char;
    l_skip, l_light, l_tot: integer;
    ls_l, ls_h, ll_l, ll_h, lt_l, lt_h : char;
  end;

  TSerialSenderThread = class(TThread)
    private
      FSerial: TSdpoSerial;
      FFocus: TXFocusListenerThread;
      pipi, pipo: longint;
      InterruptInStream: TInputPipeStream;
      InterruptOutStream: TOutputPipeStream;
      FLEDSettings: TLEDSettings;

    public
      procedure Execute; override;
      procedure interrupt;
      property LEDSettings : TLEDSettings read FLEDSettings write FLEDSettings;
      function islit(i, numLEDs: integer):boolean;
      constructor Create(_serial: TSdpoSerial; _focus: TXFocusListenerThread);

  end;


implementation

procedure TSerialSenderThread.interrupt;
begin
  // Interrupt the thread to trigger another update
  InterruptOutStream.WriteAnsiString('#');
end;

constructor TSerialSenderThread.Create(_serial: TSdpoSerial; _focus: TXFocusListenerThread);
begin
  FSerial := _serial;
  FFocus := _focus;
  // Create a pipe for interrupting the thread if needed.
  if assignpipe(pipi,pipo) <> 0 then begin
    Writeln('Error assigning pipes !');
    exit;
  end;
  InterruptInStream := TInputPipeStream.create(pipi);
  InterruptOutStream := TOutputPipeStream.create(pipo);
  Inherited create(false);
end;

function TSerialSenderThread.isLit(i, numLEDs: integer):boolean;
var relPos, relStart, relEnd: extended;
begin
  relPos := i/numLEDs;
  relStart := max(0,FFocus.CurrentRect.Left) / FFocus.RootRect.Right;
  relEnd := (FFocus.CurrentRect.Left+FFocus.CurrentRect.Right) / FFocus.RootRect.Right;
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

procedure TSerialSenderThread.Execute;
var
  FDS : Tfdset;
  buf : array[0..6] of char;
  i: integer;
begin
  while (not terminated) do begin
    fpFD_Zero (FDS);
    fpFD_Set (pipi,FDS);
    fpSelect (pipi+1,@FDS,nil,nil,nil);
    if InterruptInStream.NumBytesAvailable > 0 then begin
      writeln('Serial Interrupt');
      while (InterruptInStream.NumBytesAvailable > 0) do
        InterruptInStream.ReadAnsiString;
    end;
    writeln('Send stuff!');
    wakeSerial(FSerial);
    FSerial.writeData('s' + FLEDSettings.ls_h + FLEDSettings.ls_l);
    waitForReply(FSerial);
    FSerial.writeData('l' + FLEDSettings.ll_h + FLEDSettings.ll_l);
    waitForReply(FSerial);
    FSerial.writeData('t' + FLEDSettings.lt_h + FLEDSettings.lt_l);
    waitForReply(FSerial);
    FSerial.writeData('r');
    waitForReply(FSerial);

    for i := 0 to FLEDSettings.l_light-1 do begin
      buf[0] := 'd';

      if (isLit(i, FLEDSettings.l_light)) then begin
        buf[1] := char(FLEDSettings.fo_r_h);
        buf[2] := char(FLEDSettings.fo_g_h);
        buf[3] := char(FLEDSettings.fo_b_h);
        buf[4] := char(FLEDSettings.fo_r_l);
        buf[5] := char(FLEDSettings.fo_g_l);
        buf[6] := char(FLEDSettings.fo_b_l);
      end else
      begin
        buf[1] := char(FLEDSettings.ot_r_h);
        buf[2] := char(FLEDSettings.ot_g_h);
        buf[3] := char(FLEDSettings.ot_b_h);
        buf[4] := char(FLEDSettings.ot_r_l);
        buf[5] := char(FLEDSettings.ot_g_l);
        buf[6] := char(FLEDSettings.ot_b_l);
      end;


      FSerial.WriteBuffer(buf, 7);
      waitForReply(FSerial);
    end;
    FSerial.writeData('e');

  end;
end;

end.

