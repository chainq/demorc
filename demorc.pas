{$MODE FPC}
{$PACKRECORDS C}
unit demorc;

interface

const
  DRC_DEFAULT_HOST = '127.0.0.1';
  DRC_DEFAULT_PORT = 53280;
  DRC_DEFAULT_MAX_CLIENTS = 16;

type
  TDRC_MsgHeader = record
    Length: word;
    MsgID: word;
  end;
  PDRC_MsgHeader = ^TDRC_MsgHeader;

type
  PDRC_Session = Pointer;

function DRC_Init: PDRC_Session;
function DRC_Init(IP: String; Port: Word): PDRC_Session;
function DRC_Handler(DRCSession: PDRC_Session): Boolean;
function DRC_Close(DRCSession: PDRC_Session): Boolean;

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
// because of function naming (r u for real?)
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
  end;
  PDRC_Session_Int = ^TDRC_Session;

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
    writeln('Server : Incoming from : ',NetAddrToStr(peerAddr.sin_addr),':',ntohs(peerAddr.sin_port));

    i:=0;
    while i < maxClientSockets do
    begin
      if clientSockets[i] = 0 then
      begin
        clientSockets[i]:=newSocket;
        FD_SET(newSocket, activeFdSet);
        AcceptClient:=true;
        break;
      end;
      inc(i);
    end;

    if i >= maxClientSockets then
    begin
      writeln('Server : Too many connections.');
      CloseSocket(newSocket);
    end;
  end;
end;

function ReadClient(var DRCSession: TDRC_Session; idx: LongInt): boolean;
const
  MAX_MSG_LEN = 512;
var
  buffer: array[0..MAX_MSG_LEN-1] of char;
  len: LongInt;
begin
  ReadClient:=false;
  with DRCSession do
  begin
    len:=fpRecv(ClientSockets[idx], @buffer, MAX_MSG_LEN, 0);
    if len <= 0 then
    begin
      writeln('Server : Disconnect ');
      FD_CLR(clientSockets[idx],activeFdSet);
      CloseSocket(clientSockets[idx]);
      clientSockets[idx]:=0;
    end
    else
    begin
      buffer[len]:=#0; // zero terminate
      write('Server: Msg : ',PChar(@buffer));
    end;
  end;
end;


function DRC_Init: PDRC_Session;
begin
  DRC_Init:=DRC_Init(DRC_DEFAULT_HOST,DRC_DEFAULT_PORT);
end;

function DRC_Init(IP: String; Port: Word): PDRC_Session;
var
  session: PDRC_Session;
begin
  DRC_Init:=nil;
  session:=new(PDRC_Session_Int);
  with TDRC_Session(session^) do
  begin
    maxClientSockets:=DRC_DEFAULT_MAX_CLIENTS;
    clientSockets:=GetMem(sizeof(LongInt) * DRC_DEFAULT_MAX_CLIENTS);
    FillDWord(clientSockets^,maxClientSockets,0);

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
begin
  DRC_Handler:=false;
  if DRCSession <> nil then
    with TDRC_Session(DRCSession^) do
    begin
      readFdSet:=activeFdSet;
      {$IFDEF WINDOWS}
      if select(0,@readFdSet,nil,nil,nil) < 0 then
      {$ELSE}
      if fpSelect(maxClientSockets * 4,@readFdSet,nil,nil,0) < 0 then
      {$ENDIF}
      begin
        // FIX ME!
        writeln('fail?');
        exit;
      end;

      if FD_ISSET(listenSocket,readFdset) then
        AcceptClient(TDRC_Session(DRCSession^));

      for i:=0 to maxClientSockets-1 do
        if ClientSockets[i] <> 0 then
        begin
          if FD_ISSET(ClientSockets[i],readFdSet) then
          begin
            ReadClient(TDRC_Session(DRCSession^),i);
          end;
        end;
    end;
end;

function DRC_Close(DRCSession: PDRC_Session): Boolean;
begin
end;

end.
