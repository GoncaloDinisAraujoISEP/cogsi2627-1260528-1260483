{% from "secrets.jinja" import db_user, db_password %}

include:
  - security

openjdk-17-jre-headless:
  pkg.installed

/opt/h2/data:
  file.directory:
    - user: devuser
    - group: developers
    - dir_mode: '0770'
    - makedirs: True
    - require:
      - user: devuser

/opt/h2/h2.jar:
  file.managed:
    - source: https://repo1.maven.org/maven2/com/h2database/h2/2.2.224/h2-2.2.224.jar
    - skip_verify: True
    - user: devuser
    - group: developers
    - mode: '0750'
    - require:
      - file: /opt/h2/data

/opt/h2/data/appdb.mv.db:
  file.managed:
    - user: devuser
    - group: developers
    - mode: '0660'
    - replace: False
    - require:
      - file: /opt/h2/data

/etc/systemd/system/h2.service:
  file.managed:
    - mode: '0644'
    - contents: |
        [Unit]
        Description=H2 Database Server
        After=network.target

        [Service]
        User=devuser
        Group=developers
        WorkingDirectory=/opt/h2
        ExecStart=/usr/bin/java -cp /opt/h2/h2.jar org.h2.tools.Server -tcp -tcpAllowOthers -tcpPort 9092 -web -webAllowOthers -webPort 8082 -baseDir /opt/h2/data
        Restart=always

        [Install]
        WantedBy=multi-user.target

h2:
  service.running:
    - enable: True
    - require:
      - pkg: openjdk-17-jre-headless
      - file: /opt/h2/h2.jar
      - file: /opt/h2/data/appdb.mv.db
    - watch:
      - file: /etc/systemd/system/h2.service

# Credentials go through environment variables, so they never appear in the state output
h2_health_check:
  cmd.run:
    - name: >-
        /usr/bin/java -cp /opt/h2/h2.jar org.h2.tools.Shell
        -url jdbc:h2:tcp://127.0.0.1:9092/appdb -user "$H2_USER" -password "$H2_PW"
        -sql "SELECT 1" > /dev/null
        && echo "changed=no comment='H2 accepted a JDBC connection and answered SELECT 1'"
    - env:
      - H2_USER: {{ db_user | yaml_squote }}
      - H2_PW: {{ db_password | yaml_squote }}
    - stateful: True
    - retry:
        attempts: 10
        interval: 3
    - require:
      - service: h2
