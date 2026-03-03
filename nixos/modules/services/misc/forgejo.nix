{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.forgejo;

  exe = lib.getExe cfg.package;

  useMysql = cfg.database.type == "mysql";
  usePostgresql = cfg.database.type == "postgres";
  useSqlite = cfg.database.type == "sqlite3";

  inherit (lib)
    mkChangedOptionModule
    mkDefault
    mkIf
    mkMerge
    mkRemovedOptionModule
    mkRenamedOptionModule
    optionalAttrs
    optionals
    optionalString
    ;
in
{
  imports = [
    (mkRenamedOptionModule
      [ "services" "forgejo" "appName" ]
      [ "services" "forgejo" "settings" "DEFAULT" "APP_NAME" ]
    )
    (mkRemovedOptionModule [ "services" "forgejo" "extraConfig" ]
      "services.forgejo.extraConfig has been removed. Please use the freeform services.forgejo.settings option instead"
    )
    (mkRemovedOptionModule [ "services" "forgejo" "database" "password" ]
      "services.forgejo.database.password has been removed. Please use services.forgejo.database.passwordFile instead"
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "mailerPasswordFile" ]
      [ "services" "forgejo" "secrets" "mailer" "PASSWD" ]
    )

    # copied from services.gitea; remove at some point
    (mkRenamedOptionModule
      [ "services" "forgejo" "cookieSecure" ]
      [ "services" "forgejo" "settings" "session" "COOKIE_SECURE" ]
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "disableRegistration" ]
      [ "services" "forgejo" "settings" "service" "DISABLE_REGISTRATION" ]
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "domain" ]
      [ "services" "forgejo" "settings" "server" "DOMAIN" ]
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "httpAddress" ]
      [ "services" "forgejo" "settings" "server" "HTTP_ADDR" ]
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "httpPort" ]
      [ "services" "forgejo" "settings" "server" "HTTP_PORT" ]
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "log" "level" ]
      [ "services" "forgejo" "settings" "log" "LEVEL" ]
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "log" "rootPath" ]
      [ "services" "forgejo" "settings" "log" "ROOT_PATH" ]
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "rootUrl" ]
      [ "services" "forgejo" "settings" "server" "ROOT_URL" ]
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "ssh" "clonePort" ]
      [ "services" "forgejo" "settings" "server" "SSH_PORT" ]
    )
    (mkRenamedOptionModule
      [ "services" "forgejo" "staticRootPath" ]
      [ "services" "forgejo" "settings" "server" "STATIC_ROOT_PATH" ]
    )
    (mkChangedOptionModule
      [ "services" "forgejo" "enableUnixSocket" ]
      [ "services" "forgejo" "settings" "server" "PROTOCOL" ]
      (config: if config.services.forgejo.enableUnixSocket then "http+unix" else "http")
    )
    (mkRemovedOptionModule [ "services" "forgejo" "ssh" "enable" ]
      "services.forgejo.ssh.enable has been migrated into freeform setting services.forgejo.settings.server.DISABLE_SSH. Keep in mind that the setting is inverted"
    )
  ];

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.database.createDatabase -> useSqlite || cfg.database.user == cfg.user;
        message = "services.forgejo.database.user must match services.forgejo.user if the database is to be automatically provisioned";
      }
      {
        assertion = cfg.database.createDatabase && usePostgresql -> cfg.database.user == cfg.database.name;
        message = ''
          When creating a database via NixOS, the db user and db name must be equal!
          If you already have an existing DB+user and this assertion is new, you can safely set
          `services.forgejo.createDatabase` to `false` because removal of `ensureUsers`
          and `ensureDatabases` doesn't have any effect.
        '';
      }
    ];

    services.forgejo.settings = {
      DEFAULT = {
        RUN_MODE = mkDefault "prod";
        RUN_USER = mkDefault cfg.user;
        WORK_PATH = mkDefault cfg.stateDir;
      };

      database = mkMerge [
        {
          DB_TYPE = cfg.database.type;
        }
        (mkIf (useMysql || usePostgresql) {
          HOST =
            if cfg.database.socket != null then
              cfg.database.socket
            else
              cfg.database.host + ":" + toString cfg.database.port;
          NAME = cfg.database.name;
          USER = cfg.database.user;
        })
        (mkIf useSqlite {
          PATH = cfg.database.path;
        })
        (mkIf usePostgresql {
          SSL_MODE = "disable";
        })
      ];

      repository = {
        ROOT = cfg.repositoryRoot;
      };

      server = mkIf cfg.lfs.enable {
        LFS_START_SERVER = true;
      };

      session = {
        COOKIE_NAME = mkDefault "session";
      };

      security = {
        INSTALL_LOCK = true;
      };

      lfs = mkIf cfg.lfs.enable {
        PATH = cfg.lfs.contentDir;
      };
    };

    services.forgejo.secrets = {
      security = {
        SECRET_KEY = "${cfg.customDir}/conf/secret_key";
        INTERNAL_TOKEN = "${cfg.customDir}/conf/internal_token";
      };

      oauth2 = {
        JWT_SECRET = "${cfg.customDir}/conf/oauth2_jwt_secret";
      };

      database = mkIf (cfg.database.passwordFile != null) {
        PASSWD = cfg.database.passwordFile;
      };

      server = mkIf cfg.lfs.enable {
        LFS_JWT_SECRET = "${cfg.customDir}/conf/lfs_jwt_secret";
      };
    };

    services.postgresql = optionalAttrs (usePostgresql && cfg.database.createDatabase) {
      enable = mkDefault true;

      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensureDBOwnership = true;
        }
      ];
    };

    services.mysql = optionalAttrs (useMysql && cfg.database.createDatabase) {
      enable = mkDefault true;
      package = mkDefault pkgs.mariadb;

      ensureDatabases = [ cfg.database.name ];
      ensureUsers = [
        {
          name = cfg.database.user;
          ensurePermissions = {
            "${cfg.database.name}.*" = "ALL PRIVILEGES";
          };
        }
      ];
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.dump.backupDir}' 0750 ${cfg.user} ${cfg.group} ${cfg.dump.age} -"
      "z '${cfg.dump.backupDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.repositoryRoot}' 0750 ${cfg.user} ${cfg.group} - -"
      "z '${cfg.repositoryRoot}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/conf' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.customDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.customDir}/conf' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/data' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/log' 0750 ${cfg.user} ${cfg.group} - -"
      "z '${cfg.stateDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "z '${cfg.stateDir}/.ssh' 0700 ${cfg.user} ${cfg.group} - -"
      "z '${cfg.stateDir}/conf' 0750 ${cfg.user} ${cfg.group} - -"
      "z '${cfg.customDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "z '${cfg.customDir}/conf' 0750 ${cfg.user} ${cfg.group} - -"
      "z '${cfg.stateDir}/data' 0750 ${cfg.user} ${cfg.group} - -"
      "z '${cfg.stateDir}/log' 0750 ${cfg.user} ${cfg.group} - -"

      # If we have a folder or symlink with Forgejo locales, remove it
      # And symlink the current Forgejo locales in place
      "L+ '${cfg.stateDir}/conf/locale' - - - - ${cfg.package.out}/locale"

    ]
    ++ optionals cfg.lfs.enable [
      "d '${cfg.lfs.contentDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "z '${cfg.lfs.contentDir}' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.forgejo-secrets = mkIf (!cfg.useWizard) {
      description = "Forgejo secret bootstrap helper";
      script = ''
        if [ ! -s '${cfg.secrets.security.SECRET_KEY}' ]; then
            ${exe} generate secret SECRET_KEY > '${cfg.secrets.security.SECRET_KEY}'
        fi

        if [ ! -s '${cfg.secrets.oauth2.JWT_SECRET}' ]; then
            ${exe} generate secret JWT_SECRET > '${cfg.secrets.oauth2.JWT_SECRET}'
        fi

        ${optionalString cfg.lfs.enable ''
          if [ ! -s '${cfg.secrets.server.LFS_JWT_SECRET}' ]; then
              ${exe} generate secret LFS_JWT_SECRET > '${cfg.secrets.server.LFS_JWT_SECRET}'
          fi
        ''}

        if [ ! -s '${cfg.secrets.security.INTERNAL_TOKEN}' ]; then
            ${exe} generate secret INTERNAL_TOKEN > '${cfg.secrets.security.INTERNAL_TOKEN}'
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = cfg.user;
        Group = cfg.group;
        ReadWritePaths = [ cfg.customDir ];
        UMask = "0077";
      };
    };

    system.services.forgejo = {
      imports = [ pkgs.forgejo.services.default ];
    };

    services.openssh.settings.AcceptEnv = mkIf (!cfg.settings.server.START_SSH_SERVER or false) [
      "GIT_PROTOCOL"
    ];

    users.users = mkIf (cfg.user == "forgejo") {
      forgejo = {
        home = cfg.stateDir;
        useDefaultShell = true;
        group = cfg.group;
        isSystemUser = true;
      };
    };

    users.groups = mkIf (cfg.group == "forgejo") {
      forgejo = { };
    };

    systemd.services.forgejo-dump = mkIf cfg.dump.enable {
      description = "forgejo dump";
      after = [ "forgejo.service" ];
      path = [ cfg.package ];

      environment = {
        USER = cfg.user;
        HOME = cfg.stateDir;
        FORGEJO_WORK_DIR = cfg.stateDir;
        FORGEJO_CUSTOM = cfg.customDir;
      };

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        ExecStart =
          "${exe} dump --type ${cfg.dump.type}"
          + optionalString (cfg.dump.file != null) " --file ${cfg.dump.file}";
        WorkingDirectory = cfg.dump.backupDir;
      };
    };

    systemd.timers.forgejo-dump = mkIf cfg.dump.enable {
      description = "Forgejo dump timer";
      partOf = [ "forgejo-dump.service" ];
      wantedBy = [ "timers.target" ];
      timerConfig.OnCalendar = cfg.dump.interval;
    };
  };

  meta.doc = ./forgejo.md;
  meta.maintainers = lib.teams.forgejo.members;
}
