{% from "secrets.jinja" import devuser_password %}

developers_group:
  group.present:
    - name: developers

devuser:
  user.present:
    - name: devuser
    - gid: developers
    - shell: /bin/bash
    - password: {{ devuser_password | yaml_squote }}
    - hash_password: True
    - enforce_password: False
    - require:
      - group: developers_group

libpam-pwquality:
  pkg.installed

{% for key, value in [('minlen', 12), ('minclass', 3)] %}
pwquality_{{ key }}:
  file.replace:
    - name: /etc/security/pwquality.conf
    - pattern: '^#?\s*{{ key }}\s*=.*$'
    - repl: '{{ key }} = {{ value }}'
    - append_if_not_found: True
    - require:
      - pkg: libpam-pwquality
{% endfor %}

{% for key, value in [('deny', 5), ('unlock_time', 600)] %}
faillock_{{ key }}:
  file.replace:
    - name: /etc/security/faillock.conf
    - pattern: '^#?\s*{{ key }}\s*=.*$'
    - repl: '{{ key }} = {{ value }}'
    - append_if_not_found: True
{% endfor %}

{% for stack in ['common-password', 'common-auth', 'common-account'] %}
/etc/pam.d/{{ stack }}:
  file.managed:
    - source: salt://security/files/{{ stack }}
    - user: root
    - group: root
    - mode: '0644'
    - require:
      - pkg: libpam-pwquality
{% endfor %}
