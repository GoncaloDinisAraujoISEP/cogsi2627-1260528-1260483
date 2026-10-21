nginx:
  pkg.installed: []
  service.running:
    - enable: True
    - reload: True
    - require:
      - pkg: nginx
    - watch:
      - file: /etc/nginx/sites-enabled/default
      - file: /etc/nginx/sites-available/bookstore
      - file: /etc/nginx/sites-enabled/bookstore

/etc/nginx/sites-enabled/default:
  file.absent:
    - require:
      - pkg: nginx

/etc/nginx/sites-available/bookstore:
  file.managed:
    - mode: '0644'
    - require:
      - pkg: nginx
    - contents: |
        server {
            listen 80 default_server;
            listen [::]:80 default_server;
            server_name _;

            location / {
                proxy_pass http://192.168.56.12:8080;
                proxy_set_header Host $host;
                proxy_set_header X-Real-IP $remote_addr;
                proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
                proxy_set_header X-Forwarded-Proto $scheme;
            }
        }

/etc/nginx/sites-enabled/bookstore:
  file.symlink:
    - target: /etc/nginx/sites-available/bookstore
    - require:
      - file: /etc/nginx/sites-available/bookstore

proxy_health_check:
  http.wait_for_successful_query:
    - name: http://127.0.0.1/books
    - status: 200
    - match: title
    - wait_for: 60
    - require:
      - service: nginx
