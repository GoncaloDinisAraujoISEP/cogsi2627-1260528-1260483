{% from "secrets.jinja" import db_host, db_user, db_password %}

include:
  - security

openjdk-17-jre-headless:
  pkg.installed

/opt/app:
  file.directory:
    - user: devuser
    - group: developers
    - dir_mode: '0770'
    - makedirs: True
    - require:
      - user: devuser

# app.jar is copied next to this file by apply.sh (masterless file server is local)
/opt/app/app.jar:
  file.managed:
    - source: salt://app/app.jar
    - user: devuser
    - group: developers
    - mode: '0750'
    - require:
      - file: /opt/app

/etc/springapp.env:
  file.managed:
    - user: root
    - group: root
    - mode: '0600'
    - show_changes: False
    - contents: |
        SPRING_DATASOURCE_URL=jdbc:h2:tcp://{{ db_host }}:9092/appdb
        SPRING_DATASOURCE_USERNAME={{ db_user }}
        SPRING_DATASOURCE_PASSWORD={{ db_password }}
        SPRING_JPA_HIBERNATE_DDL_AUTO=update

/etc/systemd/system/springapp.service:
  file.managed:
    - mode: '0644'
    - contents: |
        [Unit]
        Description=Bookstore Spring Boot Application
        After=network.target

        [Service]
        User=devuser
        Group=developers
        WorkingDirectory=/opt/app
        EnvironmentFile=/etc/springapp.env
        ExecStart=/usr/bin/java -jar /opt/app/app.jar
        Restart=always

        [Install]
        WantedBy=multi-user.target

springapp:
  service.running:
    - enable: True
    - require:
      - pkg: openjdk-17-jre-headless
    - watch:
      - file: /opt/app/app.jar
      - file: /etc/springapp.env
      - file: /etc/systemd/system/springapp.service

app_health_check:
  http.wait_for_successful_query:
    - name: http://127.0.0.1:8080/books
    - status: 200
    - match: title
    - wait_for: 120
    - require:
      - service: springapp
