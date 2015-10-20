program server;

uses
  demorc;

var
  drc: PDRC_Session;

begin
  drc:=drc_init;
  if drc = nil then
  begin
    writeln('fail');
    exit;
  end;
  while true do
    drc_handler(drc);
  drc_close(drc);
end.
