```prototipo apnas```

# Technical Report - Class Assignment 3 (CA3): Configuration Management with Ansible

## Team Self-Evaluation

| Student Name | Student Number | Contribution (%) |
| :--- | :--- | :--- |
| Gonçalo Dinis Araújo | 1260528 | 50% |
| Pedro Barbosa | 1260483 | 50% |

---

## 1. Architecture Overview and Network Topology

This assignment migrates the shell-based infrastructure provisioning established in CA2 to a fully automated, declarative Ansible management workflow. The multi-VM infrastructure consists of three isolated Ubuntu Linux virtual machines managed via Vagrant:

* **`proxy` (`192.168.56.10`):** Front-facing reverse proxy running Nginx, listening on port 80 and forwarding incoming traffic to the application tier.
* **`app` (`192.168.56.12`):** Core application server running the Bookstore Spring Boot application as a systemd service, bound to port 8080.
* **`db` (`192.168.56.11`):** Dedicated database tier running H2 Database in server mode on TCP port 9092.

```
[ Client / Host Browser ]
           | (HTTP :80)
           v
  [ proxy VM: 192.168.56.10 ] (Nginx Reverse Proxy)
           | (HTTP :8080)
           v
   [ app VM: 192.168.56.12 ] (Spring Boot Bookstore API)
           | (TCP :9092 - JDBC)
           v
    [ db VM: 192.168.56.11 ] (H2 Server Engine /opt/h2/data/appdb.mv.db)
```

### Ansible Inventory Verification

The mapping between managed virtual machines and Ansible host groups was defined in `hosts.ini` and verified using `ansible-inventory --list`:

```json
{
    "_meta": {
        "hostvars": {
            "192.168.56.10": {
                "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
                "ansible_ssh_pass": "vagrant",
                "ansible_user": "vagrant"
            },
            "192.168.56.11": {
                "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
                "ansible_ssh_pass": "vagrant",
                "ansible_user": "vagrant"
            },
            "192.168.56.12": {
                "ansible_ssh_common_args": "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null",
                "ansible_ssh_pass": "vagrant",
                "ansible_user": "vagrant"
            }
        }
    },
    "all": {
        "children": [
            "app",
            "db",
            "proxy",
            "ungrouped"
        ]
    },
    "app": {
        "hosts": [
            "192.168.56.12"
        ]
    },
    "db": {
        "hosts": [
            "192.168.56.11"
        ]
    },
    "proxy": {
        "hosts": [
            "192.168.56.10"
        ]
    }
}
```

---

## 2. Solution Design and Modularity (Ansible Roles)

To guarantee high maintainability, readability, and separation of concerns, the solution was organized into dedicated **Ansible Roles**:

* **`roles/common`:** Applied to all hosts. Configures baseline apt caches, core packages, and global system PAM security policies.
* **`roles/db`:** Deploys OpenJDK 17, provisions the isolated system user `devuser` and group `developers`, downloads the H2 standalone engine, creates the database storage file, manages the `h2.service` daemon, and executes an automated port health check.
* **`roles/app`:** Creates the restricted `/opt/app` environment, transfers the pre-built Bookstore JAR artifact, provisions systemd supervision (`springapp.service`), connects dynamically to the remote H2 TCP URL, and verifies application bootstrapping using an active HTTP retry loop.
* **`roles/proxy`:** Deploys Nginx, removes default site configurations, registers the reverse proxy upstream routing rule, restarts the web server, and runs an end-to-end API health check.

---

## 3. Security Implementation

### 3.1 Restricted Service Accounts and File Permissions
In compliance with the assignment specification:
* A dedicated system group `developers` and user account `devuser` are created on both `app` and `db` nodes.
* The application directory `/opt/app` and the database storage directory `/opt/h2/data` are assigned strict permissions `0770` (read/write/execute restricted to owner and group).
* The database persistence file `/opt/h2/data/appdb.mv.db` is provisioned with permission `0660`, preventing access by unprivileged users outside the `developers` group.

### 3.2 Pluggable Authentication Modules (PAM) Password Security Policy
The PAM configuration on Ubuntu Linux was implemented declaratively within `roles/common/tasks/main.yml`:
1. **Password Complexity (`/etc/security/pwquality.conf` via `libpam-pwquality`):**
   * `minlen = 12`: Enforces a minimum password length of 12 characters.
   * `minclass = 3`: Mandates characters from at least 3 of the 4 standard character classes (uppercase, lowercase, digits, special symbols).
2. **Password History Reuse (`/etc/pam.d/common-password`):**
   * Configured `pam_pwquality.so` with `remember=5`, prohibiting the reuse of any of the last 5 previous passwords.
3. **Account Lockout Policy (`/etc/pam.d/common-auth`):**
   * Configured `pam_faillock.so` using directive:
     `auth required pam_faillock.so preauth silent audit deny=5 unlock_time=600`
   * Locks the account for 600 seconds (10 minutes) immediately following 5 consecutive failed authentication attempts.

---

## 4. Health Checks and Verification

Rather than merely validating running processes, health check tasks ensure operational application readiness:
* **Database Readiness:** The `db` role utilizes `ansible.builtin.wait_for` to ensure TCP port `9092` is actively listening and ready for incoming JDBC connections before application deployment starts.
* **Application Readiness:** The `app` role uses `ansible.builtin.uri` with `retries: 15` and `delay: 4` polling `http://127.0.0.1:8080/books`. This accommodates JVM startup latency, ensuring the Spring context and Hibernate schema validation are fully initialized before proceeding.
* **Reverse Proxy Validation:** The `proxy` role queries `http://127.0.0.1/books` expecting `status_code: 200`, confirming end-to-end proxy forwarding.

Final external validation executed from the host terminal:
```bash
curl http://192.168.56.10/books
```
**Output:**
```json
[{"id":1,"title":"Clean Code","author":"Robert C. Martin","price":30.0},{"id":2,"title":"Effective Java","author":"Joshua Bloch","price":40.0}]
```

---

## 5. Playbook Idempotency Analysis

The entire playbook (`site.yml`) was executed twice in immediate succession to demonstrate idempotency.

### First Execution (`PLAY RECAP`):
```
192.168.56.10              : ok=13   changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
192.168.56.11              : ok=17   changed=6    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
192.168.56.12              : ok=16   changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Second Execution (`PLAY RECAP`):
```
192.168.56.10              : ok=13   changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
192.168.56.11              : ok=17   changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
192.168.56.12              : ok=16   changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### Explanation of Reported Changes:
* **`app` and `proxy` nodes:** The remaining `changed=2` entries occur because the systemd tasks for restarting services specify `state: restarted`. In Ansible, the `restarted` state is an imperative action that explicitly signals systemd to bounce the process on every execution, thereby triggering a state change flag. Replacing `state: restarted` with `state: started` and utilizing Ansible `handlers` triggered by configuration file notifications achieves zero (`changed=0`) modifications on subsequent runs.
* **`db` node:** The single reported change stems from updating the apt cache with a short validation lifetime. All package installations, user creation tasks, file permissions, and directory structures exhibited strict idempotency (`ok`), leaving existing states unmodified.

---

## 6. Alternative Solution: Configuration Management with SaltStack

### 6.1 Technological Comparison
An enterprise-grade alternative to Ansible is **SaltStack (Salt)**:
* **Architecture:** While Ansible is predominantly **agentless** (operating over OpenSSH using push-based execution), SaltStack typically operates using an **event-driven client-server model** (Salt Master and Salt Minions) communicating via ZeroMQ or raw TCP sockets.
* **Execution Model:** Ansible processes playbooks sequentially over SSH connections, which introduces communication overhead on large VM fleets. SaltStack's agent-based model allows asynchronous execution across thousands of minions simultaneously in milliseconds.
* **Configuration Format:** Both tools support YAML. Ansible uses Playbooks and Roles; SaltStack uses **SLS (SaLt State) files** and organizes data using Pillar and Grains.

### 6.2 Proposed Design for CA3 using SaltStack
If CA3 were implemented with SaltStack:
1. **Infrastructure Layout:** The host or a control VM acts as the `salt-master`. The three VMs (`proxy`, `app`, `db`) run `salt-minion` services connected to the master.
2. **Top File (`/srv/salt/top.sls`):**
   ```yaml
   base:
     '*':
       - common.pam
     'db':
       - db.h2
     'app':
       - app.bookstore
     'proxy':
       - proxy.nginx
   ```
3. **State Definition Example (`/srv/salt/db/h2.sls`):**
   ```yaml
   developers_group:
     group.present:
       - name: developers

   devuser_account:
     user.present:
       - name: devuser
       - groups:
         - developers

   /opt/h2/data/appdb.mv.db:
     file.managed:
       - user: devuser
       - group: developers
       - mode: '0660'
       - makedirs: True

   h2_service:
     service.running:
       - name: h2
       - enable: True
   ```
