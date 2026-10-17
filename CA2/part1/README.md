# CA2 - Part 1: Virtualization with Vagrant

A single Vagrant VM (VirtualBox) that clones the group repository, builds and runs the two applications from CA1:

- **Bookstore** (`CA1/part2`, Spring Boot), with its H2 database persisted on the host;
- **Chat server** (`CA1/part1`), used by chat clients running on the host.

Everything is defined in [`Vagrantfile`](Vagrantfile), [`provision.sh`](provision.sh) and [`start-apps.sh`](start-apps.sh).

## Prerequisites

- Windows host with VirtualBox and Vagrant installed
- Hardware virtualization enabled in the BIOS (and Hyper-V disabled, otherwise VirtualBox runs very slowly)
- JDK 17+ on the host, to run the chat clients
- A GitHub personal access token (classic, `repo` scope) to clone the private repository

## 1. Base box

```ruby
config.vm.box = "bento/ubuntu-24.04"
config.vm.box_version = "202510.26.0"
```

- **Bento** boxes are maintained by Chef, open source, and built with Packer from the official Ubuntu ISOs. They also ship the VirtualBox Guest Additions, needed for synced folders.
- **Ubuntu 24.04** is an LTS release, so it keeps receiving updates.
- **The version is pinned**, so every `vagrant up` starts from exactly the same image.

```powershell
vagrant box list
```

<img width="499" height="42" alt="01-box-list" src="https://github.com/user-attachments/assets/0c84baf3-1573-402f-964d-21f26cf15845" />

## 2. VM configuration (`Vagrantfile`)

| Setting | Value | Why |
|---|---|---|
| Resources | 2 CPUs, 4 GB RAM | enough for two Gradle builds and two JVMs |
| Forwarded ports | 8080 → 8080, 59001 → 59001 | Bookstore and chat server reachable from the host |
| Synced folder | `./h2-data` → `/h2-data` | dedicated folder for the H2 database files only |
| Provisioner `setup` | `provision.sh` | install, clone, build, configure (first `up` and `vagrant provision`) |
| Provisioner `start` | `start-apps.sh`, `run: "always"` | start the apps on every boot |

The provisioning steps are controlled by environment variables set on the host:

| Variable | Default | Effect |
|---|---|---|
| `REPO_URL` | group repository (HTTPS) | repository to clone |
| `REPO_BRANCH` | `main` | branch to check out |
| `GITHUB_TOKEN` | empty | token used to clone the private repository |
| `CHAT_DIR` | `CA1/part1` | folder of the chat project |
| `CLONE_REPO` | `true` | clone/update the repository |
| `BUILD_APPS` | `true` | build both applications |
| `START_APPS` | `true` | start both applications |

## 3. Provisioning (`provision.sh`)

The script is idempotent: each step checks the current state before changing anything.

1. **Dependencies:** installs `git`, `openjdk-17-jdk-headless` (Bookstore and Gradle 8.14.3) and `openjdk-21-jdk-headless` (the chat project's toolchain), only if missing. Gradle is not installed: each project uses its own wrapper.
2. **Repository:** clones it if missing; otherwise fetches and checks out `REPO_BRANCH`. The token is sent as an HTTP header, so it is never written to `.git/config`.
3. **Build:** `./gradlew bootJar` for the Bookstore and `./gradlew installDist` for the chat app.
4. **Bookstore configuration:** writes `/opt/bookstore/application.properties` with a file-based H2 database in the synced folder:
   ```properties
   spring.datasource.url=jdbc:h2:file:/h2-data/bookstore
   spring.jpa.hibernate.ddl-auto=update
   spring.h2.console.settings.web-allow-others=true
   ```
5. **systemd units:** `bookstore.service` and `chat-server.service`.

The services are not enabled at boot on purpose. Vagrant mounts the synced folder only after the VM boots, so a service started by systemd would create the H2 file on the VM disk, underneath the mount point. `start-apps.sh` (`run: "always"`) starts them after the mount.

### Run

```powershell
cd CA2\part1
$env:REPO_URL     = "https://github.com/GoncaloDinisAraujoISEP/cogsi2627-1260528-1260483.git"
$env:REPO_BRANCH  = "ca2-part1"
$env:GITHUB_TOKEN = "<token>"
vagrant up
```

First provisioning, cloning the repository and building both apps:
<img width="1579" height="298" alt="02-instalation" src="https://github.com/user-attachments/assets/981f60eb-dac9-43ae-ad2f-f535fa9bbdaa" />
<img width="900" height="300" alt="02-instalation(1)" src="https://github.com/user-attachments/assets/b071e2a4-f26f-47f6-924c-302ae2a3adcf" />

```powershell
vagrant status
```

<img width="662" height="183" alt="03-vagrant-status" src="https://github.com/user-attachments/assets/e6d66315-c60d-4d4f-9da4-311bbff5a05b" />

## 4. Checking the VM

```powershell
vagrant ssh -c "lsb_release -d; ls /usr/lib/jvm"
```
<img width="890" height="79" alt="04-vm-os-jdks" src="https://github.com/user-attachments/assets/d9015252-6ec5-432f-ae39-d76ef772c428" />

```powershell
vagrant ssh -c "cd ~/repo && git branch --show-current && git log --oneline -3"
```
<img width="779" height="123" alt="05-vm-repo-branch" src="https://github.com/user-attachments/assets/9f48d99e-538f-4786-a9ee-e416e5c11c3c" />

```powershell
vagrant ssh -c "systemctl status bookstore chat-server --no-pager --lines=0"
```
<img width="947" height="427" alt="06-vm-services" src="https://github.com/user-attachments/assets/ed8ab157-bead-46fd-8731-315c344f5f21" />

```powershell
vagrant ssh -c "ss -tlnp | grep -E '8080|59001'"
```
<img width="824" height="64" alt="07-vm-ports" src="https://github.com/user-attachments/assets/55747ffb-25bf-454c-bc12-e92e03f4f8e6" />

## 5. Idempotency

Running the provisioning again does not reinstall or rebuild anything: dependencies are already installed, the repository is already up to date, and Gradle reports every task as `UP-TO-DATE`.

```powershell
vagrant provision
```

<img width="873" height="164" alt="08-provision-idempotent" src="https://github.com/user-attachments/assets/bf8de923-6877-4c2a-a94c-97edf6e57a42" />
<img width="956" height="196" alt="08-provision-idempotent(1)" src="https://github.com/user-attachments/assets/644c9b22-8f35-4339-ad54-cc272d7e027a" />

## 6. Using the applications from the host

### Bookstore

http://localhost:8080/books

<img width="402" height="504" alt="09-localhost" src="https://github.com/user-attachments/assets/6792ea0d-1b2b-4f99-a18c-4f6503407787" />

H2 console at http://localhost:8080/h2-console (JDBC URL `jdbc:h2:file:/h2-data/bookstore`, user `sa`, no password):

<img width="963" height="569" alt="10-h2-console" src="https://github.com/user-attachments/assets/c84269a9-aa4f-4170-970e-ee7f0f830083" />

### Chat

The server runs in the VM; the clients run on the host, one per terminal:

```powershell
cd CA1\part1
.\gradlew.bat runClient -PserverIP=localhost -PserverPort=59001
```

<img width="940" height="208" alt="11-chat-running" src="https://github.com/user-attachments/assets/4fd4f132-b178-4963-b042-ef7bf71c7231" />
<img width="1260" height="387" alt="11-chat-testes" src="https://github.com/user-attachments/assets/ccd4def2-48c8-4fab-83b9-d140a708f335" />

## 7. H2 persistence

The database file lives in `CA2/part1/h2-data` on the host, so the data survives `vagrant reload`, `halt` and even `destroy`. The book "Persisted" (id 52) in the screenshots of section 6 was created before the VM was destroyed and recreated.

To avoid duplicating the sample data on every start, `DataInitializer` (CA1/part2) now skips the inserts when the database already has books:

```java
if (bookRepo.count() > 0) return;
```

Creating a new book:

```powershell
curl.exe -X POST http://localhost:8080/books -H "Content-Type: application/json" -d '{\"title\":\"Persisted\",\"author\":\"Test\",\"price\":10}'
```

<img width="940" height="61" alt="12-h2-post-book" src="https://github.com/user-attachments/assets/c35e2b11-5ac9-45dd-86ec-953e5d4cada1" />

The database file on the host:

<img width="731" height="348" alt="14-persistence-h2-data" src="https://github.com/user-attachments/assets/4a7ae238-a30c-4a28-b47d-ae4116602b9d" />
<img width="764" height="83" alt="14-h2-persistence-file" src="https://github.com/user-attachments/assets/2f055ddd-a77d-4fbf-8e1c-0e1a9e97d406" />

## 8. Controlling provisioning with environment variables

Skip clone and build (only reconfigure):

```powershell
$env:CLONE_REPO = "false"
$env:BUILD_APPS = "false"
vagrant provision
```

<img width="1086" height="621" alt="15-skip-env-clone-build" src="https://github.com/user-attachments/assets/8e9ed621-bba1-4717-8229-3864975096a1" />

Boot without starting the applications:

```powershell
$env:START_APPS = "false"
vagrant reload
```

<img width="833" height="536" alt="16-env-no-start" src="https://github.com/user-attachments/assets/1738b0d6-22fd-4dbb-8d9a-952d4692d5b1" />

Back to the defaults:

```powershell
Remove-Item Env:CLONE_REPO, Env:BUILD_APPS, Env:START_APPS
vagrant reload
```

<img width="1905" height="983" alt="16-env-yes-start" src="https://github.com/user-attachments/assets/3c30d439-a4c4-4df6-9b78-f244f85ecd71" />

## 9. Limitation: GUI applications

The chat client uses Swing and needs a display. The VM has no graphical environment, so running the client inside it fails with `HeadlessException`:

```powershell
vagrant ssh -c "cd ~/repo/CA1/part1 && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ./gradlew runClient"
```

<img width="1086" height="664" alt="17-vm-headless-client" src="https://github.com/user-attachments/assets/c6c20b7f-7721-48fa-b0ed-02352b982f07" />

For this reason only the server runs in the VM, and the clients run on the host, connecting through the forwarded port 59001.

## 10. Daily use

```powershell
vagrant up        # start the VM; start-apps.sh starts both apps
vagrant halt      # shut it down cleanly before turning off the host
```

## 11. Tag

```powershell
git tag ca2-part1
git push origin ca2-part1
```<img width="499" height="42" alt="01-box-list" src="https://github.com/user-attachments/assets/30bcd67e-1726-4c92-83d8-38bc1a5cf765" />
