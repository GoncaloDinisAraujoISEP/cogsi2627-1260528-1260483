# CA3 - Alternative: Configuration Management with SaltStack

The same three VMs as the Ansible solution (`proxy`, `app`, `db`), configured with **SaltStack** state files. The comparison between the tools and the design are in the [CA3 README](../README.md#9-alternative-solutions).

## Mode: masterless

Salt normally uses a **master** that sends states to agents (**minions**) over an event bus. Here each VM runs `salt-call --local`, which applies states stored on the VM itself, with no master. A single script on the control node drives everything over SSH, which keeps the comparison with Ansible fair.

## Files

```
ansible-alternative/
├── apply.sh                 # installs Salt on each VM, uploads and applies the states
└── salt/
    ├── top.sls              # state-to-host mapping (same as site.yml)
    ├── secrets.jinja        # DB credentials and devuser password
    ├── common/init.sls      # base packages (all VMs)
    ├── security/            # developers/devuser + PAM (included by db and app)
    │   ├── init.sls
    │   └── files/           # same PAM stacks as the Ansible role
    ├── db/init.sls          # H2 server + health check
    ├── app/init.sls         # Bookstore + health check
    └── proxy/init.sls       # Nginx + health check
```

## Prerequisites

- The VMs created with the `Vagrantfile` in `CA3` (`vagrant up`).
- A Linux control node with `sshpass` and `curl`, able to reach `192.168.56.0/24`.
- The Bookstore JAR in `CA3/roles/app/files/app.jar`, the same file used by Ansible (see the [CA3 README](../README.md#prerequisites)).

## 1. Run

From the `CA3` folder:

```bash
bash ansible-alternative/apply.sh
```

For each VM, in the order db, app, proxy, the script:

1. Installs `salt-minion` from the Salt Project repository, only if `salt-call` is missing, and disables the minion daemon (not needed without a master).
2. Uploads the needed states to `/srv/salt`. `security` goes only to `app` and `db`, and the JAR only to `app`.
3. Runs `salt-call --local state.apply common` and then `salt-call --local state.apply <role>`.

At the end it checks the whole chain through the proxy with `curl http://192.168.56.10/books`.

## 2. States

### `security` (included by `db` and `app`)

| State                                    | Salt function                                                                | Requirement                                            |
| ---------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------ |
| `developers_group`, `devuser`            | `group.present`, `user.present` (`hash_password`, `enforce_password: False`) | group and user                                         |
| `pwquality_minlen`, `pwquality_minclass` | `file.replace` in `pwquality.conf`                                           | 12 chars, 3 classes                                    |
| `faillock_deny`, `faillock_unlock_time`  | `file.replace` in `faillock.conf`                                            | 5 failures, 10 min                                     |
| `/etc/pam.d/common-*`                    | `file.managed`                                                               | history (`pam_pwhistory`) and lockout (`pam_faillock`) |

The PAM files are identical to the ones in the Ansible role. Their explanation and the distribution-specific notes are in the [CA3 README](../README.md#5-pam-password-policy).

### `db`

| State                            | Salt function                                                     |
| -------------------------------- | ----------------------------------------------------------------- |
| `/opt/h2/data`                   | `file.directory`, `devuser:developers`, `0770`                    |
| `/opt/h2/h2.jar`                 | `file.managed` from Maven Central (H2 2.2.224)                    |
| `/opt/h2/data/appdb.mv.db`       | `file.managed`, `0660`, `replace: False` (never overwrites data)  |
| `/etc/systemd/system/h2.service` | `file.managed`                                                    |
| `h2`                             | `service.running`, restarted by `watch` when the unit changes     |
| `h2_health_check`                | `cmd.run`: H2 `Shell` runs `SELECT 1` over JDBC; `retry` 10 × 3 s |

### `app`

| State                                   | Salt function                                                                      |
| --------------------------------------- | ---------------------------------------------------------------------------------- |
| `/opt/app`, `/opt/app/app.jar`          | `file.directory` / `file.managed`, `devuser:developers`                            |
| `/etc/springapp.env`                    | `file.managed`, `root`, `0600`, `show_changes: False`                              |
| `/etc/systemd/system/springapp.service` | `file.managed`                                                                     |
| `springapp`                             | `service.running`, restarted by `watch` on the JAR, env file and unit              |
| `app_health_check`                      | `http.wait_for_successful_query` on `/books`: status 200 and body contains `title` |

### `proxy`

| State                                  | Salt function                                                       |
| -------------------------------------- | ------------------------------------------------------------------- |
| `nginx`                                | `pkg.installed` + `service.running` with `reload: True` and `watch` |
| `/etc/nginx/sites-enabled/default`     | `file.absent`                                                       |
| `/etc/nginx/sites-available/bookstore` | `file.managed` (reverse proxy to `192.168.56.12:8080`)              |
| `/etc/nginx/sites-enabled/bookstore`   | `file.symlink`                                                      |
| `proxy_health_check`                   | `http.wait_for_successful_query` on `http://127.0.0.1/books`        |

## 3. Idempotency

```bash
bash ansible-alternative/apply.sh
```

- **States:** `pkg.installed`, `user.present`, `file.*` and `service.running` only act when the VM differs from the declared state.
- **Restarts:** services are restarted (or reloaded) only through `watch`, when a watched file changes.
- **H2 health check:** a `cmd.run` would always count as a change, so it uses `stateful: True` and prints `changed=no`.

## 4. Requirements not fully covered

| Requirement                                    | Status       | Reason                                                                                                                                                                                                                                         |
| ---------------------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `no_log` for sensitive data                    | partial      | Salt has no single `no_log`. The equivalents used are `show_changes: False` (env file), environment variables for the H2 check, and `user.present`, which does not print the password. At debug log level, Salt can still log rendered values. |
| Secret storage                                 | plain text   | `secrets.jinja` keeps the values in the repository, like `group_vars/all.yml`. The Salt way would be Pillar with GPG encryption, which needs a pillar root or a master.                                                                        |
| Integrity of the H2 download                   | not verified | `skip_verify: True`: no checksum is checked, while Ansible's `get_url` relies on HTTPS. Adding `source_hash` would fix it.                                                                                                                     |
| Distributing the JAR                           | outside Salt | Without a master there is no file server, so `apply.sh` uploads the JAR next to the states and Salt copies it from `salt://app/app.jar`.                                                                                                       |
| Inventory listing (`ansible-inventory --list`) | n/a          | The masterless equivalent is the static list in `apply.sh` plus `top.sls`. With a master, `salt-key -L` and `salt '*' grains.items` would show the minions.                                                                                    |

## 5. Differences found compared with Ansible

- **Agent:** Ansible needs only SSH and Python on the VMs. Salt needs `salt-minion` installed first, from an external repository, which is the slowest part of the first run.
- **Dependencies:** Ansible runs tasks top to bottom. Salt also follows file order, but dependencies are explicit (`require`, `watch`), and it fails early if a required state failed.
- **Restart on change:** Salt's `watch` plays the role of Ansible handlers, with less code: no separate handler file and no `flush_handlers`.
- **Health checks:** Salt has a ready-made state for HTTP checks (`http.wait_for_successful_query`). For commands, `cmd.run` needs `stateful` to avoid reporting a change every run, where Ansible uses `changed_when: false`.
- **Templating:** Salt states pass through Jinja before YAML, so loops (`{% for %}`) generate states. This is powerful, but errors show up at render time and are harder to read than Ansible's.
- **Secrets:** Ansible's `no_log` is one switch per task. In Salt the protection depends on each state function.
