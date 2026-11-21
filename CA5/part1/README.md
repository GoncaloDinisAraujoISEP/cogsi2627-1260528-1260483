# CA5 - Part 1: Jenkins pipeline with blue/green deployment
 
This part builds the Gradle version of the Bookstore app (`CA1/part2`) with a Jenkins pipeline and deploys it to a local VM. Like CA2 Part 1, the app and its H2 database run in the same VM.
 
## Architecture
 
```
Windows host                          VirtualBox host-only network 192.168.56.0/24
 ├─ Jenkins controller :8080  ──SSH──►  Ubuntu VM 192.168.56.20 (agent, label "linux")
 └─ vagrant up                            │  gradle, ansible
                                          ├─► blue   192.168.56.21  (active version)
                                          └─► green  192.168.56.22  (candidate, deployed by Jenkins)
```
 
| Component | Where | Why |
|---|---|---|
| Jenkins controller | Windows host | the assignment requires Jenkins on the host machine |
| Jenkins agent | existing Ubuntu VM | Ansible has no Windows control node; the VM already had JDK, Git and Gradle from earlier CAs |
| blue / green VMs | VirtualBox, created by Vagrant on Windows | same setup as CA2 |
 
WSL2 was considered for the agent, but it needs Hyper-V, which makes VirtualBox very slow (the same problem we had in CA2).
 
Blue holds the version currently in production. Green is the deployment target of the pipeline and of the rollback job. As the assignment states, traffic switching between the two is out of scope.
 
## Files
 
```
CA5/
├── .gitignore
├── keys/ca5_key.pub            # public key only, the private key lives in Jenkins credentials
└── part1/
    ├── Jenkinsfile             # build, test, archive, deploy
    ├── Jenkinsfile.rollback    # rollback job
    ├── Vagrantfile             # blue and green VMs
    └── ansible/
        ├── ansible.cfg
        ├── inventory.ini
        ├── provision.yml       # run by Vagrant inside each VM
        ├── deploy.yml          # run by Jenkins (Deploy stage)
        ├── rollback.yml        # run by the rollback job
        └── tasks/
            ├── base.yml        # Java, service user, folders, systemd unit
            ├── install_jar.yml # copy release, switch symlink, restart
            └── healthcheck.yml # /actuator/health UP and /books returns books
```
 
## 1. Prepare the agent VM
 
Add a second network adapter to the Ubuntu VM (VirtualBox, Adapter 2, Host-only Adapter, the one with `192.168.56.1`) and give it a static IP:
 
```yaml
# /etc/netplan/60-hostonly.yaml
network:
  version: 2
  ethernets:
    enp0s8:
      dhcp4: false
      addresses: [192.168.56.20/24]
```
 
```bash
sudo chmod 600 /etc/netplan/60-hostonly.yaml && sudo netplan apply
sudo apt install -y openssh-server openjdk-17-jdk-headless openjdk-21-jre-headless git curl ansible
```
 
JDK 17 builds the app; Java 21 runs the Jenkins agent process.
 
Create the `jenkins` user and one SSH key pair. The same key is used by Jenkins to reach the agent and by Ansible to reach the VMs:
 
```bash
sudo useradd -m -s /bin/bash jenkins
sudo -u jenkins mkdir -p /home/jenkins/.ssh /home/jenkins/agent
ssh-keygen -t ed25519 -f ~/.ssh/ca5_key -N "" -C "ca5"
cat ~/.ssh/ca5_key.pub | sudo -u jenkins tee /home/jenkins/.ssh/authorized_keys > /dev/null
sudo chmod 700 /home/jenkins/.ssh && sudo chmod 600 /home/jenkins/.ssh/authorized_keys
cp ~/.ssh/ca5_key.pub CA5/keys/
```
 
The private key stays in `~/.ssh` and is never committed (`keys/ca5_key` is also in `.gitignore`).
 
## 2. Blue and green VMs
 
The [`Vagrantfile`](Vagrantfile) creates both VMs from `bento/ubuntu-24.04`, shares `CA5/keys` with them and provisions them with `ansible_local`, since Ansible cannot run on Windows:
 
```ruby
{ "blue" => "192.168.56.21", "green" => "192.168.56.22" }.each do |name, ip|
  config.vm.define name do |node|
    node.vm.network "private_network", ip: ip
    node.vm.provision "ansible_local" do |ansible|
      ansible.playbook = "ansible/provision.yml"
      ansible.extra_vars = { deploy_initial: name == "blue" }
    end
  end
end
```
 
[`provision.yml`](ansible/provision.yml) runs on both VMs:
 
1. authorizes `ca5_key.pub` for the `vagrant` user, so Jenkins can connect later;
2. runs [`tasks/base.yml`](ansible/tasks/base.yml): installs Java 17, creates the `bookstore` service user, `/opt/bookstore/releases` and `/opt/bookstore/data`, the `/etc/bookstore.env` settings (H2 file database) and a systemd unit that runs `/opt/bookstore/app.jar`;
3. on blue only (`deploy_initial`), installs the current version and runs the health check.

`app.jar` is a symlink to a file in `releases/`. Switching versions means pointing the symlink to another release and restarting the service, which is what both deploy and rollback do.
 
The initial jar is built once on the agent and copied to the Windows clone before `vagrant up` (it is ignored by Git):
 
```powershell
mkdir CA5\part1\ansible\files
scp pbarbosa@192.168.56.20:~/cogsis/cogsi2627-1260528-1260483/CA1/part2/build/libs/bookstore-1.0.0.jar CA5\part1\ansible\files\app.jar
cd CA5\part1
vagrant up
```
<img width="944" height="83" alt="image" src="https://github.com/user-attachments/assets/45141791-699f-445b-9732-54bdcf0d67da" />

<img width="942" height="79" alt="image" src="https://github.com/user-attachments/assets/dbd451d2-d839-4f72-b467-d3672fd23b13" />
 
<img width="556" height="446" alt="image" src="https://github.com/user-attachments/assets/390e733a-4e65-462b-a21e-ba54c853162d" />
 
## 3. Jenkins setup
 
Jenkins LTS was installed on Windows with the MSI (JDK 21, port 8080). After the setup wizard:
 
- **Jenkins URL:** `http://192.168.56.1:8080/`, so the agent can reach it (the rollback downloads artifacts from it);
- **Built-in node:** 0 executors, so every build runs on the agent;
- **Firewall:** inbound rule for TCP 8080 on Windows:
```powershell
New-NetFirewallRule -DisplayName "Jenkins 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
```
 
### Credentials
 
No secret is written in the repository or in the Jenkinsfiles. They are all Jenkins credentials, referenced by ID:
 
| ID | Type | Used for |
|---|---|---|
| `github-pat` | Username with password | cloning the private repository |
| `agent-ssh-key` | SSH Username with private key (`jenkins`) | connecting to the agent |
| `green-ssh-key` | SSH Username with private key (`vagrant`) | Ansible deploy and rollback on green |
| `jenkins-api` | Username with password (Jenkins user + API token) | downloading archived artifacts in the rollback |
 
<img width="885" height="556" alt="image" src="https://github.com/user-attachments/assets/1a9f5aac-0abd-4f8e-88c0-8fdf1a52e36d" />
 
### Agent
 
New permanent node `ubuntu-agent`: 2 executors, root `/home/jenkins/agent`, label `linux`, launched via SSH to `192.168.56.20` with `agent-ssh-key`, Java path `/usr/lib/jvm/java-21-openjdk-amd64/bin/java`.
 
Two settings were needed for builds to work on the agent:
 
| Problem | Cause | Fix |
|---|---|---|
| `Cannot run program "git.exe"` | the default Git tool was configured for the Windows controller | Manage Jenkins → Tools → Git: path `git` (works on both systems) |
| `Unsupported class file major version 69` | the VM's default Java is 25, not supported by Gradle 8.14.3 | node environment variable `JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64` |
 
<img width="854" height="771" alt="image" src="https://github.com/user-attachments/assets/6111b8c8-cd47-4ec0-a37b-9e48c26e484d" />

### Jobs
 
| Job | Type | Branch | Script Path |
|---|---|---|---|
| `ca5-part1` | Pipeline from SCM | `*/development` | `CA5/part1/Jenkinsfile` |
| `ca5-part1-rollback` | Pipeline from SCM | `*/development` | `CA5/part1/Jenkinsfile.rollback` |
 
Work is done on the `ca5/part1` branch and merged into `development`, which is the branch the pipeline builds.
 
## 4. Pipeline
 
[`Jenkinsfile`](Jenkinsfile):
 
| Stage | What it does |
|---|---|
| Checkout | `git branch: 'development'` with the `github-pat` credential |
| Assemble | `./gradlew clean bootJar` in `CA1/part2` |
| Test | `./gradlew test`; results published with `junit` |
| Archive | clears `dist/`, copies the jar to `dist/bookstore-stable-v1.<BUILD_NUMBER>.jar` and archives it with the test reports |
| Deploy | only when `DEPLOY` is true: runs `deploy.yml` against green |
 
```groovy
parameters {
  booleanParam(name: 'DEPLOY', defaultValue: false, description: 'Deploy the new version to the green VM')
}
environment {
  VERSION = "stable-v1.${env.BUILD_NUMBER}"
}
```
 
```groovy
stage('Deploy') {
  when { expression { params.DEPLOY } }
  steps {
    withCredentials([sshUserPrivateKey(credentialsId: 'green-ssh-key', keyFileVariable: 'SSH_KEY')]) {
      dir(env.ANSIBLE_DIR) {
        sh 'ansible-playbook deploy.yml --private-key "$SSH_KEY" -e app_jar="$WORKSPACE/dist/bookstore-$VERSION.jar" -e app_version="$VERSION"'
      }
    }
  }
}
```
 
**Version traceability.** The `stable-v1.N` name is applied in the Archive stage, which only runs if Assemble and Test passed, so only artifacts that passed all tests get a stable tag. The build is also renamed to the same version (`currentBuild.displayName`), so build `#6` appears as `stable-v1.6` and its artifact is at `job/ca5-part1/6/artifact/dist/bookstore-stable-v1.6.jar`.
 
**Post actions:**
- **Notification:** `success`, `unstable` and `failure` blocks print the result of the run;
- **Deployment verification:** when `DEPLOY` is true, `post { success }` checks from outside the VM that green's `/actuator/health` reports `UP` and `/books` returns books. The Ansible playbook already runs the same checks inside the VM, so the deploy is verified twice.

The CA1 project had no unit tests (only the `BookApiIT` integration test), so the Test stage found nothing to publish. A small unit test was added in `CA1/part2/src/test/java/com/example/bookstore/model/BookTest.java`.

The agent keeps its workspace between builds, so at first `dist/` accumulated the jars of previous builds and each build archived all of them. The Archive stage now starts with `rm -rf dist`, so every build archives only its own version.
 
### Build without deploy
 
<img width="865" height="495" alt="image" src="https://github.com/user-attachments/assets/78d42d5d-3318-4d14-b6b2-b8b50b54f888" />
 
<img width="896" height="377" alt="image" src="https://github.com/user-attachments/assets/cffac406-cda6-4fdd-98bf-8d10b384d3dc" />
 
<img width="891" height="703" alt="image" src="https://github.com/user-attachments/assets/7067c58f-d702-4bb9-838c-991024f670a7" />
 
<img width="713" height="262" alt="image" src="https://github.com/user-attachments/assets/aa31d085-1a45-442b-a948-c0a48b965a77" />

 
### Build with deploy
 
[`deploy.yml`](ansible/deploy.yml) runs on green: base setup (idempotent), copy of the new release, symlink switch, restart and health check.
 
<img width="860" height="715" alt="image" src="https://github.com/user-attachments/assets/c5f1f2a1-fbd9-44e0-a25e-e36d74ea3fcd" />
 
<img width="895" height="803" alt="image" src="https://github.com/user-attachments/assets/036cd4a7-d727-40e0-837b-8362a8f0f226" />
 
## 5. Rollback
 
[`rollback.yml`](ansible/rollback.yml) receives a version, for example `stable-v1.5`, and:
 
1. checks the format (`stable-v1.<number>`) and takes the build number from it;
2. downloads `bookstore-stable-v1.5.jar` from `JENKINS_URL/job/ca5-part1/5/artifact/dist/`, authenticated with the `jenkins-api` credential (`JENKINS_URL` is set by Jenkins itself);
3. stops the service on green, which frees port 8080 and the H2 file lock;
4. copies the jar to `releases/`, points `app.jar` to it and starts the service;
5. runs the same health checks as the deploy.

[`Jenkinsfile.rollback`](Jenkinsfile.rollback) validates the `STABLE_VERSION` parameter and runs the playbook with the `green-ssh-key` and `jenkins-api` credentials.
 
Test: green was running `stable-v1.10`, rollback to `stable-v1.5`:

```
TASK [Retrieve bookstore-stable-v1.5.jar from Jenkins] *********
changed: [192.168.56.22 -> localhost]
TASK [Stop the running application (releases port 8080 and the H2 file lock)]
changed: [192.168.56.22]
...
Rollback to stable-v1.5 completed and verified
```
 
```powershell
vagrant ssh green -c "sudo ls -l /opt/bookstore/app.jar"
# /opt/bookstore/app.jar -> /opt/bookstore/releases/bookstore-stable-v1.5.jar
```
 
<img width="886" height="818" alt="image" src="https://github.com/user-attachments/assets/ed1b13ff-bca5-4564-9118-ed9b7160485f" />
 
<img width="804" height="560" alt="image" src="https://github.com/user-attachments/assets/5fbda74f-95c9-48bf-bc6a-6b6953747c96" />
<img width="838" height="262" alt="image" src="https://github.com/user-attachments/assets/179162c2-6a04-4459-8ee2-b1c6026f558a" />
<img width="829" height="67" alt="image" src="https://github.com/user-attachments/assets/081ee65e-a389-4594-84d1-8a04db220eaf" />

 
<img width="936" height="60" alt="image" src="https://github.com/user-attachments/assets/e2fc9871-d9d5-4208-be0a-560fb08c20aa" />
 
The first rollback attempt failed with `HTTP Error 401`: the `jenkins-api` credential used the GitHub username instead of the Jenkins user ID. The ID is the one in the profile URL (`/user/<id>/`).
 
## 6. Tag
 
```bash
git tag ca5-part1
git push origin refs/tags/ca5-part1
```

## Self-assessment

| Member | No. | Contribution |
|---|---|---|
| Gonçalo Dinis Araújo | 1260528 | 50% |
| Pedro Barbosa | 1260483 | 50% | 
