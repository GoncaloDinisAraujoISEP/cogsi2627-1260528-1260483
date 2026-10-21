developers_group:
  group.present:
    - name: developers

devuser:
  user.present:
    - name: devuser
    - groups:
      - developers

db_packages:
  pkg.installed:
    - pkgs:
      - openjdk-17-jre-headless
      - wget

/opt/h2/data:
  file.directory:
    - user: devuser
    - group: developers
    - dir_mode: '0770'
    - makedirs: True

download_h2_jar:
  file.managed:
    - name: /opt/h2/h2-2.3.232.jar
    - source: https://repo1.maven.org/maven2/com/h2database/h2/2.3.232/h2-2.3.232.jar
    - skip_verify: True
    - user: devuser
    - group: developers
    - mode: '0644'

/opt/h2/data/appdb.mv.db:
  file.managed:
    - user: devuser
    - group: developers
    - mode: '0660'
    - replace: False

h2_service:
  service.running:
    - name: h2
    - enable: True
