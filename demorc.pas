{
  Copyright (c) 2015  Karoly Balogh <charlie@amigaspirit.hu>

  Permission to use, copy, modify, and/or distribute this software for
  any purpose with or without fee is hereby granted, provided that the
  above copyright notice and this permission notice appear in all copies.

  THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
  WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
  WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL
  THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
  CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
  LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
  NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
  CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
}

{ Simple server-client messaging system, designed to ease the
  development tooling of demoscene productions written in
  Free Pascal }

{ Thanks to Attila Nagy "aha" for ideas and inspiration }

{$MODE FPC}
{$PACKRECORDS C}
{$DEFINE DRC_HAS_DEFAULT_LOGGER}
unit demorc;

interface

type
  TDRC_MsgSize = Word;

const
  DRC_DEFAULT_HOST = '127.0.0.1';
  DRC_DEFAULT_PORT = 53280;
  DRC_DEFAULT_MAX_CLIENTS = 16;
  DRC_MAX_BUFFER_SIZE = high(TDRC_MsgSize);

type
  TDRC_MsgHeader = packed record
    Length: TDRC_MsgSize;
    MsgID: word;
  end;
  PDRC_MsgHeader = ^TDRC_MsgHeader;

type
  PDRC_Session = Pointer;

type
  TDRC_MsgHandler = function(session: PDRC_Session; buf: Pointer; var length: TDRC_MsgSize): boolean; cdecl;
  PDRC_MsgHandler = ^TDRC_MsgHandler;
  TDRC_Logger = procedure(s: PChar); cdecl;

function DRC_Init: PDRC_Session;
function DRC_Init(const IP: String; Port: Word): PDRC_Session;
function DRC_Handler(DRCSession: PDRC_Session): Boolean;
function DRC_Close(DRCSession: PDRC_Session): Boolean;

function DRC_AddMsgHandler(DRCSession: PDRC_Session; MsgID: Word; handler: TDRC_MsgHandler): Boolean;
function DRC_RemoveMsgHandler(DRCSession: PDRC_Session; MsgID: Word): Boolean;

function DRC_SetLogger(DRCSession: PDRC_Session; newlogger: TDRC_Logger): Boolean;
procedure DRC_DefaultLogger(s: PChar); cdecl;

implementation

uses
  sockets, ctypes
  {$IFDEF WINDOWS}
  ,winsock
  {$ELSE}
  {$IFDEF UNIX}
  ,unix, baseunix
  {$ELSE}
  {$ERROR Unsupported system.}
  {$ENDIF}
  {$ENDIF}
  ;

{$IFDEF UNIX}
// Workaround for cross-platform RTL incompatibility braindamage
// because of function naming (R U for real?)
function FD_ZERO(var nset: TFDSet):cint; inline;
begin
  FD_ZERO:=fpFD_ZERO(nset);
end;

function FD_CLR(fdno: cint; var nset: TFDSet):cint; inline;
begin
  FD_CLR:=fpFD_CLR(fdno,nset);
end;

function FD_SET(fdno: cint; var nset: TFDSet):cint; inline;
begin
  FD_SET:=fpFD_SET(fdno, nset);
end;

function FD_ISSET(fdno: cint; const nset: TFDSet):boolean; inline;
begin
  FD_ISSET:=fpFD_ISSET(fdno, nset) > 0;
end;
{$ENDIF}

type
  TDRC_Session = record
    serverAddr: TInetSockAddr;
    listenSocket: LongInt;
    activeFdSet: TFDSet;
    maxClientSockets: LongInt;
    clientSockets: PLongInt;
    clientBuffers: PPByte;
    clientBuffersPos: PLongInt;
    msgHandlers: PDRC_MsgHandler;
    handlerBuf: PByte;
    logger: TDRC_Logger;
  end;
  PDRC_Session_Int = ^TDRC_Session;

{ lets not include the entire sysutils for this... }
function IntToStr(I : Longint) : String;
Var S : String;
begin
 Str (I,S);
 IntToStr:=S;
end;

procedure logline(var DRCSession: TDRC_Session; const s: AnsiString);
begin
  with DRCSession do
  begin
    if logger <> nil then
      logger(PChar(s));
  end;
end;

function AcceptClient(var DRCSession: TDRC_Session): boolean;
var
  i: LongInt;
  newSocket: LongInt;
  peerAddr: TInetSockAddr;
  addrSize: TSockLen;
begin
  AcceptClient:=false;
  with DRCSession do
  begin
    addrSize:=sizeof(peerAddr);
    newSocket:=fpAccept(listenSocket, @peerAddr, @addrSize);
    logline(DRCSession,'Server : Incoming from : '+NetAddrToStr(peerAddr.sin_addr)+':'+IntToStr(ntohs(peerAddr.sin_port)));

    i:=0;
    while i < maxClientSockets do
    begin
      if clientSockets[i] = 0 then
      begin
        clientSockets[i]:=newSocket;
        clientBuffers[i]:=GetMem(high(TDRC_MsgSize)+sizeof(TDRC_MsgHeader));
        clientBuffersPos[i]:=0;
        FillChar(clientBuffers[i]^,high(TDRC_MsgSize)+sizeof(TDRC_MsgHeader),0);
        FD_SET(newSocket, activeFdSet);
        AcceptClient:=true;
        logline(DRCSession,'Server : Accepted as client #'+IntToStr(i));
        break;
      end;
      inc(i);
    end;

    if i >= maxClientSockets then
    begin
      logline(DRCSession,'Server : Too many connections. Maximum allowed is '+IntToStr(maxClientSockets));
      CloseSocket(newSocket);
    end;
  end;
end;

function CloseClient(var DRCSession: TDRC_Session; idx: LongInt): boolean;
begin
  CloseClient:=false;
  with DRCSession do
  begin
    if clientSockets[idx] <> 0 then
    begin
      logline(DRCSession,'Server : Disconnecting client #'+IntToStr(idx));
      FD_CLR(clientSockets[idx],activeFdSet);
      CloseSocket(clientSockets[idx]);
      clientSockets[idx]:=0;
      FreeMem(clientBuffers[idx]);
      clientBuffers[idx]:=nil;
      CloseClient:=true;
    end;
  end;
end;

{ returns true when we have at least 1 packet in the buffer }
function ReadClient(var DRCSession: TDRC_Session; idx: LongInt): boolean;
var
  len: LongInt;
  pos: LongInt;
begin
  ReadClient:=false;
  with DRCSession do
  begin
    pos:=clientBuffersPos[idx];
    len:=fpRecv(ClientSockets[idx], @clientBuffers[idx][pos], sizeof(TDRC_MsgHeader)+high(TDRC_MsgSize)-pos,0);
    if len <= 0 then
    begin
      CloseClient(DRCSession,idx);
      exit;
    end;
    inc(pos,len);
    clientBuffersPos[idx]:=pos;

    { return true if we have at least 1 full packet available in the buffer }
    if pos >= sizeof(TDRC_MsgHeader) then
    begin
      ReadClient:=(LEToN(PDRC_MsgHeader(@clientBuffers[idx][0])^.length) + sizeof(TDRC_MsgHeader)) >= pos;
    end;
  end;
end;

{ when this function is called, there should be at least 1 packet guaranteed in the buffer }
function ParsePackets(var DRCSession: TDRC_Session; idx: LongInt): boolean;
var
  pos: LongInt;
  max: LongInt;
  pHeader: PDRC_MsgHeader;
  pData: Pointer;
  msgID: LongInt;
  len: LongInt;
  newLen: TDRC_MsgSize;
  handler: TDRC_MsgHandler;
begin
  ParsePackets:=false;
  with DRCSession do
  begin
    pos:=0;
    max:=clientBuffersPos[idx];
    while pos < max do
    begin
      pHeader:=PDRC_MsgHeader(@clientBuffers[idx][pos]);
      pData:=@clientBuffers[idx][pos+sizeof(TDRC_MsgHeader)];
      len:=LEToN(pHeader^.Length);
      msgID:=LEToN(pHeader^.MsgID);

      { if the message handler wasn't nil, copy the buffer over and call the handler function }
      if msgHandlers[msgID] <> nil then
      begin
        handler:=msgHandlers[msgID];
        Move(pData^,handlerBuf^,len);
        newLen:=len;
        if handler(@DRCSession,handlerBuf,newLen) then
        begin
          // TODO: call reply code!
        end;
      end
      else
      begin
        logline(DRCSession,'Server : Unknown Message with ID: '+HexStr(msgID,4)+' length: '+IntToStr(len)+' from client #'+IntToStr(idx));
      end;
      inc(pos,len+sizeof(TDRC_MsgHeader));
    end;
  end;
end;

function DRC_Init: PDRC_Session;
begin
  DRC_Init:=DRC_Init(DRC_DEFAULT_HOST,DRC_DEFAULT_PORT);
end;

function DRC_Init(const IP: String; Port: Word): PDRC_Session;
var
  session: PDRC_Session;
begin
  DRC_Init:=nil;
  session:=new(PDRC_Session_Int);
  with TDRC_Session(session^) do
  begin
{$IFDEF DRC_HAS_DEFAULT_LOGGER}
    DRC_SetLogger(session,@DRC_DefaultLogger);
{$ENDIF}
    maxClientSockets:=DRC_DEFAULT_MAX_CLIENTS;
    clientSockets:=GetMem(sizeof(LongInt) * DRC_DEFAULT_MAX_CLIENTS);
    clientBuffers:=GetMem(sizeof(PPByte) * DRC_DEFAULT_MAX_CLIENTS);
    clientBuffersPos:=GetMem(sizeof(LongInt) * DRC_DEFAULT_MAX_CLIENTS);
    msgHandlers:=GetMem(sizeof(PDRC_MsgHandler) * high(TDRC_MsgSize));
    FillDWord(clientSockets^,maxClientSockets,0);
    FillChar(clientBuffers^,maxClientSockets*sizeof(PPByte),0);
    FillDWord(clientBuffersPos^,maxClientSockets,0);
    FillChar(msgHandlers^,sizeof(PDRC_MsgHandler) * high(TDRC_MsgSize),0);

    listenSocket := fpSocket(AF_INET, SOCK_STREAM, 0);
    if listenSocket = -1 then
      exit;

    FillChar(serverAddr,sizeof(serverAddr),0);
    serverAddr.sin_family := AF_INET;
    serverAddr.sin_port := htons(Port);
    serverAddr.sin_addr.s_addr := StrToNetAddr(IP).s_addr;

    if fpBind(listenSocket,@ServerAddr,sizeof(ServerAddr)) = -1 then
      exit;
    if fpListen (listenSocket,1) = -1 then
      exit;

    FD_ZERO(activeFdSet);
    FD_SET(listenSocket,activeFdSet);
  end;
  DRC_Init:=session;
end;

function DRC_Handler(DRCSession: PDRC_Session): Boolean;
var
  readFdSet: TFDSet;
  i: LongInt;
  TV : TimeVal;
begin
  DRC_Handler:=false;
  if DRCSession <> nil then
    with TDRC_Session(DRCSession^) do
    begin
      readFdSet:=activeFdSet;
      {$IFDEF WINDOWS}
      TV.tv_sec  := 0;
      TV.tv_usec := 0;
      if select(0,@readFdSet,nil,nil,@TV) < 0 then
      {$ELSE}
      if fpSelect(maxClientSockets * 4,@readFdSet,nil,nil,0) < 0 then
      {$ENDIF}
      begin
        // FIX ME!
        logline(TDRC_Session(DRCSession^),'fail?');
        exit;
      end;

      if FD_ISSET(listenSocket,readFdset) then
        AcceptClient(TDRC_Session(DRCSession^));

      for i:=0 to maxClientSockets-1 do
        if ClientSockets[i] <> 0 then
        begin
          if FD_ISSET(ClientSockets[i],readFdSet) then
          begin
            if ReadClient(TDRC_Session(DRCSession^),i) then
              ParsePackets(TDRC_Session(DRCSession^),i);
          end;
        end;
    end;
end;

function DRC_Close(DRCSession: PDRC_Session): Boolean;
var i: LongInt;
begin
  DRC_Close:=false;
  if DRCSession <> nil then
  begin
    with TDRC_Session(DRCSession^) do
    begin
      for i:=0 to maxClientSockets-1 do
      begin
        if clientSockets[i]<>0 then
        begin
          CloseClient(TDRC_Session(DRCSession^),i);
        end;
      end;
      CloseSocket(listenSocket);
      FreeMem(clientSockets);
      FreeMem(clientBuffers);
      FreeMem(clientBuffersPos);
      FreeMem(msgHandlers);
      Dispose(PDRC_Session_Int(DRCSession));
    end;
    DRC_Close:=true;
  end;
end;


function DRC_AddMsgHandler(DRCSession: PDRC_Session; MsgID: Word; handler: TDRC_MsgHandler): Boolean;
begin
  DRC_AddMsgHandler:=false;
  if DRCSession <> nil then
  begin
    with TDRC_Session(DRCSession^) do
    begin
      msgHandlers[MsgID]:=handler;
      DRC_AddMsgHandler:=true;
    end;
  end;
end;

function DRC_RemoveMsgHandler(DRCSession: PDRC_Session; MsgID: Word): Boolean;
begin
  DRC_RemoveMsgHandler:=false;
  if DRCSession <> nil then
  begin
    with TDRC_Session(DRCSession^) do
    begin
      msgHandlers[MsgID]:=nil;
      DRC_RemoveMsgHandler:=true;
    end;
  end;
end;

function DRC_SetLogger(DRCSession: PDRC_Session; newlogger: TDRC_Logger): boolean;
begin
  DRC_SetLogger:=false;
  if DRCSession <> nil then
  begin
    with TDRC_Session(DRCSession^) do
    begin
      logger:=newlogger;
    end;
  end;
end;

procedure DRC_DefaultLogger(s: PChar); cdecl;
begin
  writeln(s);
end;

end.
