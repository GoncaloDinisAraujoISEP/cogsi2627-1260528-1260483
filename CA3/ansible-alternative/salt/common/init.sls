install_pam_tools:
  pkg.installed:
    - pkgs:
      - curl
      - git
      - libpam-pwquality

pwquality_conf:
  file.append:
    - name: /etc/security/pwquality.conf
    - text:
      - "minlen = 12"
      - "minclass = 3"

pam_password_remember:
  file.replace:
    - name: /etc/pam.d/common-password
    - pattern: '^(password\s+requisite\s+pam_pwquality\.so)(.*)'
    - repl: '\1 remember=5'

pam_account_lockout:
  file.line:
    - name: /etc/pam.d/common-auth
    - content: 'auth required pam_faillock.so preauth silent audit deny=5 unlock_time=600'
    - mode: insert
    - before: '^auth.*pam_unix\.so'
