program listen;

uses sockets{$IFDEF WINDOWS}, winsock{$ELSE}, unix, baseunix{$ENDIF};

const
  SOCKET_ERROR = -1;
  MAX_CLIENTS = 16;

var
    listenSocket: LongInt;
    newSocket: LongInt;
    serverAddr  : TInetSockAddr;
    peerAddr: TInetSockAddr;
    addrSize: TSockLen;
    frame: longint = 0;

    clientSockets : array[0..MAX_CLIENTS-1] of longint;

function AddClient(fd: longint): boolean;
var
  i: LongInt;
begin
  addclient:=false;
  i:=0;
  while i < MAX_CLIENTS do begin
    if clientSockets[i] = 0 then begin
      clientSockets[i]:=fd;
      addclient:=true;
      break;
    end else
      inc(i);
  end;
end;
 
Procedure PrintError(const msg : string);
begin
    writeln(msg, SocketError);
    halt(100);
end;
 
 
const
  MAX_MSG_LEN = 512;
 
var
  activeset: TFDSet;
  readset: TFDSet;
  i,j: Integer;
  buffer: array[0..MAX_MSG_LEN-1] of char;
  maxFd: LongInt;
 
begin
    maxFd := 64; // hack
 
    listenSocket := fpSocket(AF_INET, SOCK_STREAM, 0);
    if listenSocket = SOCKET_ERROR then
      PrintError ('Server : Socket : ');
 
    FillChar(serverAddr,sizeof(ServerAddr),0);
    serverAddr.sin_family := AF_INET;
    serverAddr.sin_port := htons(50000);
    serverAddr.sin_addr.s_addr := htonl($7F000001);
    if fpBind(listenSocket,@ServerAddr,sizeof(ServerAddr)) = SOCKET_ERROR then
      PrintError ('Server : Bind : ');
    if fpListen (listenSocket,1) = SOCKET_ERROR then
      PrintError ('Server : Listen : ');
 
    {$IFDEF WINDOWS}
    FD_ZERO(activeset);
    FD_SET(listenSocket,activeset);
    {$ELSE}
    fpFD_ZERO(activeset);
    fpFD_SET(listenSocket,activeset);
    {$ENDIF}
 
    while true do begin
      inc(frame);
 
      readset:=activeset;
      {$IFDEF WINDOWS}
      if select(maxFd,@readset,nil,nil,nil) < 0 then
      {$ELSE}
      if fpSelect(maxFd,@readset,nil,nil,0) < 0 then
      {$ENDIF}
        PrintError ('Server : Select : ');
 
      {$IFDEF WINDOWS}
      if FD_ISSET(listenSocket,readset) then begin
      {$ELSE}
      if fpFD_ISSET(listenSocket,readset) > 0 then begin
      {$ENDIF}
        addrSize:=sizeof(peerAddr);
        newSocket:=fpAccept(listenSocket, @peerAddr, @addrSize);
        writeln('Server : Incoming from : ',NetAddrToStr(peeraddr.sin_addr),':',ntohs(peeraddr.sin_port));
 
        if AddClient(newSocket) then begin
          {$IFDEF WINDOWS}
          FD_SET(newSocket, activeset);
          {$ELSE}
          fpFD_SET(newSocket, activeset);
          {$ENDIF}
        end else begin
          writeln('Server : Too many connections.');
          {$IFDEF WINDOWS}
          CloseSocket(newSocket);
          {$ELSE}
          fpClose(newSocket);
          {$ENDIF}
        end;
      end;

      for i:=0 to MAX_CLIENTS-1 do begin
        if ClientSockets[i] <> 0 then begin
          {$IFDEF WINDOWS}
          if FD_ISSET(ClientSockets[i],readset) then begin
          {$ELSE}
          if fpFD_ISSET(ClientSockets[i],readset) > 0 then begin
          {$ENDIF}
            j:=fpRecv(ClientSockets[i], @buffer, MAX_MSG_LEN, 0);
            if j <= 0 then begin
              writeln('Server : Disconnect ');
             {$IFDEF WINDOWS}
              FD_CLR(ClientSockets[i],activeset);
              CloseSocket(ClientSockets[i]);
              {$ELSE}
              fpFD_CLR(ClientSockets[i],activeset);
              fpClose(ClientSockets[i]);
              {$ENDIF}
              ClientSockets[i]:=0;
            end else begin
              buffer[j]:=#0; // zero terminate
              write('Server: Msg : ',PChar(@buffer));
            end;
          end;
        end;
      end;

//      writeln('frame:',frame);
    end;

end.
