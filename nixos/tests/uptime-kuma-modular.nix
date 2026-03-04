{ lib, pkgs, ... }:

{
  _class = "nixosTest";

  name = "uptime-kuma";

  nodes.machine = _: {
    system.services = {
      uptime-kuma-1 = {
        imports = [ pkgs.uptime-kuma.services.default ];
        uptime-kuma = {
          systemd.stateDir = "uptime-kuma-1";
          settings = {
            PORT = "3001";
            DATA_DIR = "/var/lib/uptime-kuma-1/";
          };
        };
      };
      uptime-kuma-2 = {
        imports = [ pkgs.uptime-kuma.services.default ];
        uptime-kuma = {
          systemd.stateDir = "uptime-kuma-2";
          settings = {
            PORT = "3002";
            DATA_DIR = "/var/lib/uptime-kuma-2/";
          };
        };
      };
    };
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("uptime-kuma-1.service")
    machine.wait_for_unit("uptime-kuma-2.service")
    machine.wait_for_open_port(3001)
    machine.wait_for_open_port(3002)
    machine.succeed("curl --fail http://localhost:3001/")
    machine.succeed("curl --fail http://localhost:3002/")
  '';

  meta.maintainers = with lib.maintainers; [ james-1701 ];
}
