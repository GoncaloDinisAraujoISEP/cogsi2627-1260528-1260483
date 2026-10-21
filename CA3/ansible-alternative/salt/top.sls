# Same mapping as site.yml. apply.sh applies the states explicitly per VM
# (salt-call --local state.apply <state>); app and db include "security".
base:
  '*':
    - common
  'db':
    - db
  'app':
    - app
  'proxy':
    - proxy
