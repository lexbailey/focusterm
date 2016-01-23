unit SerialSenderThread;
{
This unit contains TLEDSettings and TSerialSenderThread

TLEDSettings is simply a record for holding (mostly) raw data to send to the
LED strip for setting up the colour and LED skip and light values.

TSerialSenderThread extends TThread and simply waits for a call to Interrupt
and then sends data out via the serial port (using a TSDPOSerial instance
provided to the constructor)
}


{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SdpoSerial, Unix, pipes, XFocusListenerThread, math, dateutils,
  BaseUnix;

type

  // For holding details of what the LED strip is expecting
  TLEDSettings = record
    fo_r_h, fo_g_h, fo_b_h, fo_r_l, fo_g_l, fo_b_l: char;
    ot_r_h, ot_g_h, ot_b_h, ot_r_l, ot_g_l, ot_b_l: char;
    l_skip, l_light, l_tot: integer;
    ls_l, ls_h, ll_l, ll_h, lt_l, lt_h : char;
    rev: boolean;
  end;

  // Thread that sends serial stuff to the LED strip
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
  // Determine if LED i should be lit
  // Remember that the rects are used to store width and height in the right
  // and bottom fields
  if FLEDSettings.rev then begin
    i := (numLEDs - i) -1;
  end;
  relPos := i/numLEDs;
  relStart := max(0,FFocus.CurrentRect.Left) / FFocus.RootRect.Right;
  relEnd :=
  (FFocus.CurrentRect.Left+FFocus.CurrentRect.Right) / FFocus.RootRect.Right;
  result := (relStart<=relPos) and (relPos <= relEnd);
end;

procedure waitForReply(serial: TSdpoSerial);
var startTime: int64;
begin
  startTime := DateTimeToUnix(now);
  while (not (serial.DataAvailable)) and
        (not (startTime + 1 < DateTimeToUnix(now))) do begin end;
  while (serial.DataAvailable) do begin serial.ReadData end;
end;

procedure wakeSerial(serial: TSdpoSerial);
begin
  // Write a byte to the serial port and wait for a response
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
    // Wait to be interrupted by 'selecting' the interrupt pipe
    fpFD_Zero (FDS);
    fpFD_Set (pipi,FDS);
    fpSelect (pipi+1,@FDS,nil,nil,nil);
    if InterruptInStream.NumBytesAvailable > 0 then begin
      while (InterruptInStream.NumBytesAvailable > 0) do
        InterruptInStream.ReadAnsiString;
    end;
    // Write data to serial
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

