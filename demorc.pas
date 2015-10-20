{$MODE FPC}
{$PACKRECORDS C}
unit demorc;

interface

const
  DRC_DEFAULT_HOST = '127.0.0.1';
  DRC_DEFAULT_PORT = 53280;

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
  sockets
  {$IFDEF WINDOWS}
  ,winsock
  {$ELSE}
  ,unix, baseunix
  {$ENDIF}
  ;

type
  TDRC_Session = record
    listenSocket: LongInt;
    activeFdSet: TFDSet;
    readFdSet: TFDSet;
  end;

function DRC_Init: PDRC_Session;
begin
  DRC_Init:=DRC_Init(DRC_DEFAULT_HOST,DRC_DEFAULT_PORT);
end;

function DRC_Init(IP: String; Port: Word): PDRC_Session;
var
  serverAddr: TInetSockAddr;
  session: PDRC_Session;
begin
  session:=new(PDRC_Session);
  with TDRC_Session(session^) do
  begin
    listenSocket := fpSocket(AF_INET, SOCK_STREAM, 0);
    if listenSocket = -1 then
      exit(nil);

    FillChar(serverAddr,sizeof(ServerAddr),0);
    serverAddr.sin_family := AF_INET;
    serverAddr.sin_port := htons(Port);
    serverAddr.sin_addr.s_addr := StrToHostAddr(IP).s_addr;

    if fpBind(listenSocket,@ServerAddr,sizeof(ServerAddr)) = -1 then
      exit(nil);
    if fpListen (listenSocket,1) = -1 then
      exit(nil);

    {$IFDEF WINDOWS}
    FD_ZERO(activeFdSet);
    FD_SET(listenSocket,activeFdSet);
    {$ELSE}
    fpFD_ZERO(activeFdSet);
    fpFD_SET(listenSocket,activeFdSet);
    {$ENDIF}
  end;
  DRC_Init:=session;
end;

function DRC_Handler(DRCSession: PDRC_Session): Boolean;
begin
end;

function DRC_Close(DRCSession: PDRC_Session): Boolean;
begin
end;

end.
