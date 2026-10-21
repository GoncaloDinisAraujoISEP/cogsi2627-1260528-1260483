developers_group_app:
  group.present:
    - name: developers

devuser_app:
  user.present:
    - name: devuser
    - groups:
      - developers

app_packages:
  pkg.installed:
    - pkgs:
      - openjdk-17-jre-headless
      - curl

/opt/app:
  file.directory:
    - user: devuser
    - group: developers
    - dir_mode: '0770'
    - makedirs: True

spring_boot_service:
  service.running:
    - name: springapp
    - enable: True
