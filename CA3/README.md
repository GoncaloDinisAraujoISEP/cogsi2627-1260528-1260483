# CA3 - Configuration Management with Ansible

The multi-VM setup from CA2 Part 2 (`app`, `db`, `proxy`) is now configured with **Ansible** instead of shell scripts. Vagrant only creates the three VMs; everything installed or configured inside them comes from the playbook [`site.yml`](site.yml) and its roles.

The alternative implementation with **SaltStack** is in [`ansible-alternative`](ansible-alternative/README.md).

## Architecture

| VM      | IP            | Service                                      | Port                       |
| ------- | ------------- | -------------------------------------------- | -------------------------- |
| `proxy` | 192.168.56.10 | Nginx reverse proxy                          | 80 (host: 8080)            |
| `app`   | 192.168.56.12 | Bookstore (Spring Boot), systemd `springapp` | 8080                       |
| `db`    | 192.168.56.11 | H2 in server mode, systemd `h2`              | 9092 (TCP), 8082 (console) |

```
Host ──HTTP :80──▶ proxy (Nginx) ──HTTP :8080──▶ app (Bookstore) ──JDBC TCP :9092──▶ db (H2)
```

## Files

```
CA3/
├── Vagrantfile            # 3 VMs on a private network, no provisioning
├── ansible.cfg            # inventory, remote user, become
├── hosts.ini              # inventory: groups db, app, proxy
├── site.yml               # playbook
├── group_vars/all.yml     # shared variables (DB host, credentials)
├── roles/
│   ├── common/            # apt cache and base packages (all VMs)
│   ├── security/          # developers/devuser + PAM policy (app, db)
│   │   ├── tasks/main.yml #   import_tasks: users.yml, pam.yml
│   │   └── files/         #   PAM stacks: common-auth, common-account, common-password
│   ├── db/                # H2 server   (tasks + handlers)
│   ├── app/               # Bookstore   (tasks + handlers, files/app.jar)
│   └── proxy/             # Nginx       (tasks + handlers)
└── ansible-alternative/   # same goals with SaltStack
```

## Prerequisites

- VirtualBox and Vagrant on the host.
- A Linux control node with `ansible`, `sshpass` and `passlib` (`pip install passlib`, used by `password_hash`), able to reach `192.168.56.0/24`.
- The Bookstore JAR, built from CA1/part2 and copied into the `app` role:
  ```bash
  cd CA1/part2 && ./gradlew bootJar
  mkdir -p ../../CA3/roles/app/files
  cp build/libs/bookstore-1.0.0.jar ../../CA3/roles/app/files/app.jar
  ```

## 1. Create the VMs

```bash
cd CA3
vagrant up
```

The `Vagrantfile` uses `bento/ubuntu-24.04`, gives each VM a fixed IP on a private network, and sets `config.ssh.insert_key = false`, so every VM accepts the `vagrant`/`vagrant` login used by the inventory.

## 2. Inventory

[`hosts.ini`](hosts.ini) puts each VM in its own group, and `site.yml` targets those groups:

```ini
[db]
192.168.56.11 ansible_user=vagrant ansible_ssh_pass=vagrant

[app]
192.168.56.12 ansible_user=vagrant ansible_ssh_pass=vagrant

[proxy]
192.168.56.10 ansible_user=vagrant ansible_ssh_pass=vagrant
```

[`ansible.cfg`](ansible.cfg) points to this inventory, disables host key checking (the VMs are recreated often) and runs tasks with `sudo` (`become = True`).

```bash
ansible-inventory --list
```

```json
{
    "_meta": { "hostvars": { "192.168.56.10": {...}, "192.168.56.11": {...}, "192.168.56.12": {...} } },
    "all":   { "children": ["app", "db", "proxy", "ungrouped"] },
    "app":   { "hosts": ["192.168.56.12"] },
    "db":    { "hosts": ["192.168.56.11"] },
    "proxy": { "hosts": ["192.168.56.10"] }
}
```

## 3. Playbook and roles

`site.yml` runs five plays, in this order:

| Play                 | Hosts   | Role       | Why this order                                        |
| -------------------- | ------- | ---------- | ----------------------------------------------------- |
| Common configuration | all     | `common`   | base packages first                                   |
| Developers and PAM   | app, db | `security` | the services run as `devuser`, so it must exist first |
| Database             | db      | `db`       | the app needs H2 up to start                          |
| Application          | app     | `app`      | the proxy health check needs the app up               |
| Reverse proxy        | proxy   | `proxy`    | end-to-end check                                      |

### `security` (app and db)

Split into two files with `import_tasks`:

- **`users.yml`:** creates the group `developers` and the user `devuser` with `developers` as its group. The password is hashed with `password_hash` and set only when the user is created (`update_password: on_create`).
- **`pam.yml`:** the password policy (section 5).

### `db`

1. Installs OpenJDK 17.
2. Creates `/opt/h2/data` (`devuser:developers`, `0770`).
3. Downloads H2 2.2.224, the same version as the Bookstore's JDBC driver, so client and server match.
4. Creates `/opt/h2/data/appdb.mv.db` with mode `0660`.
5. Installs `h2.service`: H2 in TCP server mode on port 9092, accepting remote connections, running as `devuser`.
6. Health check (section 6).

### `app`

1. Installs OpenJDK 17.
2. Creates `/opt/app` (`devuser:developers`, `0770`) and copies the JAR into it.
3. Writes the database connection settings to `/etc/springapp.env` (owner `root`, mode `0600`), loaded by systemd with `EnvironmentFile`. Spring Boot reads them as `SPRING_DATASOURCE_*` environment variables, which take precedence over the `application.properties` inside the JAR.
4. Installs `springapp.service`, running as `devuser`.
5. Health check (section 6).

### `proxy`

1. Installs Nginx and removes the default site.
2. Creates the `bookstore` site, with `proxy_pass http://192.168.56.12:8080`, and enables it.
3. Health check (section 6).

### Handlers

Services are started with `state: started`, which does nothing if they are already running. Configuration tasks `notify` a handler (`Restart h2`, `Restart springapp`, `Reload nginx`), so a service is restarted only when its JAR, unit file or configuration changes. `meta: flush_handlers` runs any pending restart before the health check, so the check always tests the new configuration.

## 4. Sensitive data and permissions

### Credentials

The database credentials and the `devuser` password are variables in [`group_vars/all.yml`](group_vars/all.yml). Every task that handles them uses `no_log: true`, so their arguments and results never appear in the Ansible output:

| Task                               | Role       | Sensitive data       |
| ---------------------------------- | ---------- | -------------------- |
| Create devuser                     | `security` | user password        |
| Write database connection settings | `app`      | DB user and password |
| Health check (H2 query)            | `db`       | DB user and password |

The credentials are in plain text to keep the assignment reproducible. In a real deployment, the file would be encrypted with `ansible-vault encrypt group_vars/all.yml`.

### Access restrictions

| Path                       | VM  | Owner                | Mode   |
| -------------------------- | --- | -------------------- | ------ |
| `/opt/app`                 | app | `devuser:developers` | `0770` |
| `/opt/app/app.jar`         | app | `devuser:developers` | `0750` |
| `/etc/springapp.env`       | app | `root:root`          | `0600` |
| `/opt/h2/data`             | db  | `devuser:developers` | `0770` |
| `/opt/h2/data/appdb.mv.db` | db  | `devuser:developers` | `0660` |

Both services run as `devuser`, so they can read the application and write the database, while users outside `developers` cannot access either. The credentials file is only readable by root: systemd reads it before starting the service as `devuser`.

## 5. PAM password policy

Applied to the `app` and `db` VMs by `roles/security/tasks/pam.yml`.

| Requirement                      | PAM module      | File                           | Configuration                                               |
| -------------------------------- | --------------- | ------------------------------ | ----------------------------------------------------------- |
| Minimum 12 characters            | `pam_pwquality` | `/etc/security/pwquality.conf` | `minlen = 12`                                               |
| 3 of the 4 character classes     | `pam_pwquality` | `/etc/security/pwquality.conf` | `minclass = 3`                                              |
| No reuse of the last 5 passwords | `pam_pwhistory` | `/etc/pam.d/common-password`   | `password required pam_pwhistory.so remember=5 use_authtok` |
| Lock for 10 min after 5 failures | `pam_faillock`  | `/etc/security/faillock.conf`  | `deny = 5`, `unlock_time = 600`                             |
|                                  |                 | `/etc/pam.d/common-auth`       | `preauth` before `pam_unix`, `authfail` after it            |
|                                  |                 | `/etc/pam.d/common-account`    | `account required pam_faillock.so`                          |

The `pwquality.conf` and `faillock.conf` values are set with `lineinfile` (it replaces the commented default line). The three PAM stacks are copied whole from [`roles/security/files`](roles/security/files), so their content is always the same and the order of the modules is guaranteed.

`common-password`:

```
password  requisite                   pam_pwquality.so retry=3
password  required                    pam_pwhistory.so remember=5 use_authtok
password  [success=1 default=ignore]  pam_unix.so obscure use_authtok try_first_pass yescrypt
password  requisite                   pam_deny.so
password  required                    pam_permit.so
```

`common-auth`:

```
auth  requisite                   pam_faillock.so preauth
auth  [success=2 default=ignore]  pam_unix.so nullok
auth  [default=die]               pam_faillock.so authfail
auth  requisite                   pam_deny.so
auth  required                    pam_permit.so
```

How `common-auth` works:

- `preauth` refuses the login straight away if the account is locked.
- If the password is right, `pam_unix` skips the next two lines (`success=2`) and reaches `pam_permit`.
- If it is wrong, `authfail` records the failure and ends the authentication (`default=die`). The fifth failure locks the account.
- `account required pam_faillock.so` in `common-account` clears the counter after a successful login.

### Distribution-specific notes

|                              | Ubuntu / Debian (used here)                   | RHEL / Fedora / Rocky                                          |
| ---------------------------- | --------------------------------------------- | -------------------------------------------------------------- |
| PAM files                    | `/etc/pam.d/common-*`, shared by all services | `/etc/pam.d/system-auth` and `password-auth`                   |
| Who generates them           | `pam-auth-update`                             | `authselect`                                                   |
| Enabling lockout and history | edit the `common-*` files (as done here)      | `authselect enable-feature with-faillock` and `with-pwhistory` |
| Quality package              | `libpam-pwquality`                            | `libpwquality` (installed by default)                          |

- **`pam-auth-update`:** on Ubuntu, it regenerates the `common-*` files when PAM packages are installed or reconfigured. Running the playbook again restores this configuration.
- **`pam_tally2`:** the older lockout module was removed from recent distributions (Ubuntu 22.04+ and RHEL 8+), which is why `pam_faillock` is used.
- **`remember=`:** this option belongs to `pam_pwhistory` (or `pam_unix`). `pam_pwquality` does not support it.

### Verification

```bash
vagrant ssh app
sudo useradd -m testuser
echo 'testuser:Initial#Pass2026' | sudo chpasswd

# Complexity: as testuser, try a short password and one with only 2 classes
su - testuser -c passwd
#   "The password is shorter than 12 characters"
#   "The password contains less than 3 character classes"

# History: change the password, then try to set a previous one
#   "Password has been already used."

# Lockout: 5 wrong passwords, then check
su - testuser          # wrong password x5
sudo faillock --user testuser
sudo faillock --user testuser --reset
```

## 6. Health checks

Each check tests the service at application level, not just the process or the port:

| VM    | Check                                               | How                                                                                  |
| ----- | --------------------------------------------------- | ------------------------------------------------------------------------------------ |
| db    | H2 accepts a JDBC connection and answers `SELECT 1` | `command` running the H2 `Shell` client against `jdbc:h2:tcp://127.0.0.1:9092/appdb` |
| app   | `GET /books` returns 200 and a book list            | `uri` on `http://127.0.0.1:8080/books`, body must contain `title`                    |
| proxy | Nginx forwards `/books` to the app                  | `uri` on `http://127.0.0.1/books`, body must contain `title`                         |

The proxy check covers the whole chain: Nginx → Bookstore → H2.

### Errors and transient conditions

| Situation                               | Handling                                                                                       |
| --------------------------------------- | ---------------------------------------------------------------------------------------------- |
| H2 download fails (network)             | `get_url` with `until: h2_download is succeeded`, `retries: 5`, `delay: 5`                     |
| H2 not ready after a (re)start          | `until: h2_check.rc == 0`, `retries: 10`, `delay: 3`; `failed_when: h2_check.rc != 0`          |
| Spring Boot still starting              | `until` on status 200 and body, `retries: 20`, `delay: 5`; `failed_when` on the same condition |
| App not reachable through the proxy yet | same pattern, `retries: 10`, `delay: 3`                                                        |

The health checks also use `changed_when: false` (or are read-only modules), so they never count as changes.

## 7. Run

```bash
cd CA3
ansible-playbook site.yml
```

From the host:

```bash
curl http://192.168.56.10/books
```

## 8. Idempotency

```bash
ansible-playbook site.yml
```

On the second run nothing should change:

- **Packages:** `apt` with `state: present`, and an apt cache valid for one hour.
- **Users:** `devuser` keeps its password (`update_password: on_create`).
- **Files and units:** `copy`, `file` and `lineinfile` only report a change when the content differs.
- **Database file:** created with `touch` and `modification_time: preserve` / `access_time: preserve`, so its timestamps are not updated.
- **Services:** `state: started` instead of `restarted`; restarts only come from handlers, when something changed.
- **Health checks:** read-only.

## 9. Alternative solutions

### Comparison with Ansible

|                          | Ansible                 | SaltStack                           | Puppet                    | Chef                |
| ------------------------ | ----------------------- | ----------------------------------- | ------------------------- | ------------------- |
| Agent                    | none (SSH)              | minion (or masterless)              | agent                     | client              |
| Model                    | push                    | push (master) or local              | pull (agent polls server) | pull                |
| Language                 | YAML playbooks          | YAML + Jinja states                 | Puppet DSL (declarative)  | Ruby DSL (recipes)  |
| Ordering                 | top to bottom           | file order + `require`/`watch`      | dependency graph          | top to bottom       |
| Change-triggered restart | handlers                | `watch`                             | `notify`/`subscribe`      | `notifies`          |
| Secrets                  | Ansible Vault, `no_log` | Pillar (GPG), `show_changes: False` | Hiera (eyaml)             | encrypted data bags |
| Scale                    | small/medium fleets     | very large fleets, event bus        | large fleets              | large fleets        |

### Design with SaltStack

Each Ansible role maps to a Salt state with the same name, and the same requirements are covered:

| Goal                  | Ansible                    | Salt                                                        |
| --------------------- | -------------------------- | ----------------------------------------------------------- |
| Inventory / targeting | `hosts.ini` groups         | `top.sls` (minion IDs)                                      |
| Modularity            | roles + `import_tasks`     | one state per role + `include`                              |
| Users and permissions | `group`, `user`, `file`    | `group.present`, `user.present`, `file.directory`           |
| PAM policy            | `lineinfile`, `copy`       | `file.replace`, `file.managed`                              |
| Services              | `systemd` + handlers       | `service.running` + `watch`                                 |
| Health checks         | `uri`, `command` + `until` | `http.wait_for_successful_query`, `cmd.run` + `retry`       |
| Secrets               | `group_vars` + `no_log`    | Jinja/Pillar + `show_changes: False`, environment variables |

Salt runs **masterless** (`salt-call --local` on each VM), driven over SSH by one script, to keep it comparable to Ansible's agentless model. Implementation, results and limitations: [`ansible-alternative/README.md`](ansible-alternative/README.md).

## 10. Tag

```bash
git tag ca3
git push origin refs/tags/ca3
```

## Self-assessment

| Student              | Number  | Contribution |
| -------------------- | ------- | ------------ |
| Gonçalo Dinis Araújo | 1260528 | 50%          |
| Pedro Barbosa        | 1260483 | 50%          |
