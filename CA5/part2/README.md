# CA5 - Parte 2: Pipeline CI/CD com Jenkins, Docker, Vagrant e Ansible

## 1. Visão Geral e Arquitetura da Solução

Este guia documenta a implementação passo a passo de uma pipeline completa de **Integração Contínua e Entrega Contínua (CI/CD)** para a aplicação **Bookstore** (Spring Boot / Java 17 / Gradle), orquestrada pelo **Jenkins**.

O objetivo desta segunda parte do **CA5** é eliminar todo o trabalho manual de compilação, testes, empacotamento, publicação de imagens e *deploy*. Sempre que a pipeline é executada, o código é obtido a partir do GitHub, compilado e validado com testes unitários e de integração em paralelo, empacotado num ficheiro `.jar` e numa imagem Docker leve, publicado no Docker Hub e automaticamente colocado em produção numa máquina virtual Ubuntu 24.04 através do **Ansible**.

```text
+-----------------------------------------------------------------------+
|                          Repositório GitHub                           |
|                      (Branch / Tag: ca5-part2)                        |
+-----------------------------------+-----------------------------------+
                                    | 1. Checkout (Multibranch Pipeline)
                                    v
+-----------------------------------------------------------------------+
|                     Contentor Jenkins (jenkins-ca5)                   |
|  2. Build         -> ./gradlew clean compileJava compileTestJava      |
|  3. Test (Paral.) -> Unit Tests + Integration Tests (JUnit XML)       |
|  4. Package       -> ./gradlew bootJar + Archive (.jar & Dockerfile)  |
|  5. Docker Push   -> goncalodinisaraujoisep/bookstore-ca5:<branch-#>  |
|  6. Deploy (main) -> ansible-playbook (SSH -> 192.168.56.30)          |
|  7. Health Check  -> curl [http://192.168.56.30:8080/actuator/health](http://192.168.56.30:8080/actuator/health)   |
+-----------------------------------+-----------------------------------+
                                    | SSH (chave privada) + Ansible
                                    v
+-----------------------------------------------------------------------+
|             VM de Produção - Ubuntu 24.04 (ca5-part2-prod)            |
|                       IP Privado: 192.168.56.30                       |
|      Contentor bookstore-prod a correr na porta 8080 (NAT: 8085)      |
+-----------------------------------------------------------------------+
```

### Componentes da Arquitetura

| Componente | Tecnologia | Função na Arquitetura |
| :--- | :--- | :--- |
| **Aplicação** | Spring Boot 3 / Gradle (`CA5/part2/bookstore`) | API REST da Bookstore compilada em Java 17 |
| **Orquestrador CI/CD** | Jenkins (`jenkins-ca5` em Docker) | Executa os 7 estágios da pipeline declarativa definida no `Jenkinsfile` |
| **Registry de Imagens** | Docker Hub (`goncalodinisaraujoisep/bookstore-ca5`) | Armazena as imagens versionadas por branch e número de build |
| **Servidor de Produção** | Vagrant + VirtualBox (`bento/ubuntu-24.04`) | Máquina virtual dedicada (`192.168.56.30`) que aloja a aplicação |
| **Gestão de Configuração** | Ansible (`ansible/deploy.yml`) | Provisiona o Docker na VM e garante o arranque idempotente do contentor |

### Estrutura de Diretórios (`CA5/part2`)

```text
CA5/part2/
├── bookstore/               # Código-fonte da aplicação Spring Boot (Gradle, testes unitários e integração)
├── ansible/
│   ├── inventory.ini        # Inventário Ansible apontando para a VM de produção (192.168.56.30)
│   └── deploy.yml           # Playbook para instalar Docker e fazer deploy do contentor bookstore-prod
├── Dockerfile               # Imagem minimalista de runtime (JRE 17 Alpine) para o artefacto .jar
├── Jenkinsfile              # Definição declarativa de toda a pipeline CI/CD
├── Vagrantfile              # Infraestrutura como código da VM de produção (ca5-part2-prod)
├── start-linux.sh           # Script auxiliar de arranque para ambientes Linux
├── start-windows.sh         # Script auxiliar experimental para portabilidade em Windows (WSL2)
└── README.md                # Tutorial passo a passo e relatório técnico
```

---

## 2. Empacotamento da Aplicação (`Dockerfile`)

Como a compilação e a geração do ficheiro executável (`bootJar`) são realizadas num estágio anterior da própria pipeline do Jenkins, o `Dockerfile` não precisa de incluir o JDK nem o Gradle. Optou-se por uma imagem de runtime minimalista baseada em **Eclipse Temurin 17 JRE Alpine**, reduzindo drasticamente o tamanho da imagem enviada para o Docker Hub e a superfície de ataque em produção.

#### Ficheiro `CA5/part2/Dockerfile`
```dockerfile
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app

COPY bookstore/build/libs/bookstore-*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

**Porque foi feito assim:**
* **`eclipse-temurin:17-jre-alpine`:** Contém apenas o Java Runtime Environment necessário para executar o `.jar`, sem ferramentas de compilação desnecessárias.
* **`COPY bookstore/build/libs/bookstore-*.jar app.jar`:** Aproveita diretamente o artefacto gerado e validado no estágio `Package & Archive` da pipeline, garantindo que o binário colocado na imagem é exatamente o mesmo que passou nos testes.

---

## 3. Infraestrutura de Produção como Código (`Vagrantfile`)

Para simular um servidor de produção real isolado da máquina de desenvolvimento, definiu-se uma máquina virtual Ubuntu 24.04 gerida por **Vagrant** e **VirtualBox**.

#### Ficheiro `CA5/part2/Vagrantfile`
```ruby
Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-24.04"
  config.vm.box_version = "202404.26.0"

  config.vm.define "prod" do |prod|
    prod.vm.hostname = "bookstore-prod"
    prod.vm.network "private_network", ip: "192.168.56.30"
    prod.vm.network "forwarded_port", guest: 8080, host: 8085, auto_correct: true

    prod.vm.provider "virtualbox" do |vb|
      vb.name = "ca5-part2-prod"
      vb.memory = "2048"
      vb.cpus = 2
    end
  end
end
```

**Decisões técnicas:**
* **IP privado fixo (`192.168.56.30`):** Permite que o inventário do Ansible e o estágio `Health Check` do Jenkins comuniquem sempre com o mesmo endereço sem depender de DHCP dinâmico.
* **Encaminhamento de porta (`8080 -> 8085`):** Evita conflito com a porta `8080` já ocupada pelo servidor Jenkins no anfitrião, permitindo testar a aplicação diretamente em `http://localhost:8085/books`.
* **Recursos dedicados (`2048 MB RAM`, `2 vCPUs`):** Garante estabilidade ao serviço Docker e à JVM da Bookstore dentro da VM.

#### Passos de Criação e Validação da VM:
```bash
cd CA5/part2
vagrant up
vagrant status
```

---

## 4. Configuração do Servidor Jenkins, Chaves SSH e Credenciais

O servidor Jenkins corre no contentor Docker **`jenkins-ca5`** (acessível em `http://localhost:8080`), equipado com JDK, Docker CLI (ligado ao *socket* Docker do anfitrião para construir e publicar imagens) e **Ansible** para executar o *deploy* remoto na VM `prod`.

### 4.1. Confiança SSH entre Jenkins e VM de Produção
Para que o Ansible consiga ligar-se à VM `192.168.56.30` de forma totalmente automática e sem palavras-passe:
1. Gerou-se um par de chaves SSH dedicado dentro do contentor Jenkins (`/var/jenkins_home/.ssh/ca5_prod_key`).
2. Extraiu-se a chave pública correspondente e adicionou-se ao ficheiro `~/.ssh/authorized_keys` do utilizador `vagrant` na VM de produção:
   ```bash
   JENKINS_PUB=$(docker exec jenkins-ca5 ssh-keygen -y -f /var/jenkins_home/.ssh/ca5_prod_key)
   vagrant ssh prod -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$JENKINS_PUB' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
   ```

### 4.2. Registo de Credenciais no Jenkins
Por questões de segurança, nenhuma palavra-passe ou chave privada é guardada no repositório Git. Em **Manage Jenkins -> Credentials -> System -> Global credentials**, criaram-se duas credenciais referenciadas diretamente pelo `Jenkinsfile`:

| ID da Credencial | Tipo no Jenkins | Finalidade |
| :--- | :--- | :--- |
| **`dockerhub-credentials`** | *Username with password* | Autenticação no Docker Hub (`goncalodinisaraujoisep`) para `docker push` na pipeline e `docker pull` na VM |
| **`prod-vm-ssh-key`** | *SSH Username with private key* | Utilizador `vagrant` + chave privada correspondente à chave pública autorizada na VM `192.168.56.30` |

### 4.3. Criação do Projeto Multibranch Pipeline
1. No painel principal do Jenkins, selecionou-se **New Item -> Multibranch Pipeline** com o nome **`bookstore-ca5-part2`**.
2. Em **Branch Sources**, adicionou-se a fonte **Git** apontando para o repositório GitHub da equipa.
3. Em **Build Configuration**, configurou-se o *Script Path* para **`CA5/part2/Jenkinsfile`**.

### 4.4. Mecanismo de Disparo (*Trigger*) Alternativo ao Webhook
Como o servidor Jenkins corre localmente (`http://localhost:8080`) numa rede privada atrás de NAT sem endereço IP público exposto na Internet, o GitHub não consegue enviar pedidos HTTP POST (*webhooks*) diretamente para a instância local. Em conformidade com o previsto no enunciado (*"If webhook exposure is not feasible, explain and demonstrate an alternative triggering mechanism"*), configurou-se o mecanismo nativo **Scan Multibranch Pipeline Triggers -> Periodically if not otherwise run** (com intervalo de 2 minutos), permitindo ao Jenkins detetar automaticamente novos *commits* nas *branches* do repositório e iniciar as respetivas *builds*.

---

## 5. Automação de Deploy com Ansible

O **Ansible** é responsável por garantir que a VM de produção está corretamente provisionada e a executar exatamente a versão da imagem acabada de construir na pipeline.

### 5.1. Inventário (`ansible/inventory.ini`)

```ini
[production]
prod-vm ansible_host=192.168.56.30 ansible_port=22 ansible_user=vagrant ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

> **Nota:** A diretiva `-o StrictHostKeyChecking=no` impede que a primeira ligação SSH da pipeline fique bloqueada à espera de confirmação interativa (*yes/no*) da *fingerprint* do servidor.

### 5.2. Playbook de Provisionamento e Deploy (`ansible/deploy.yml`)

```yaml
---
- name: Provision and Deploy Bookstore Container to Production VM
  hosts: production
  become: true
  vars:
    docker_image: "{{ docker_repo }}:{{ image_tag }}"
    container_name: "bookstore-prod"
    app_port: 8080

  tasks:
    - name: Update apt cache and install Docker prerequisites
      apt:
        name:
          - apt-transport-https
          - ca-certificates
          - curl
          - gnupg
          - lsb-release
        state: present
        update_cache: yes

    - name: Install Docker (docker.io)
      apt:
        name: docker.io
        state: present

    - name: Ensure Docker service is started and enabled
      service:
        name: docker
        state: started
        enabled: yes

    - name: Add vagrant user to docker group
      user:
        name: vagrant
        groups: docker
        append: yes

    - name: Log into Docker Hub
      command: docker login -u {{ docker_user }} -p {{ docker_pass }}
      no_log: true

    - name: Pull target Docker image from Docker Hub
      command: docker pull {{ docker_image }}

    - name: Stop and remove existing application container if present
      shell: |
        docker stop {{ container_name }} || true
        docker rm {{ container_name }} || true

    - name: Start new Bookstore container
      command: >
        docker run -d
        --name {{ container_name }}
        --restart unless-stopped
        -p {{ app_port }}:8080
        {{ docker_image }}

    - name: Log out from Docker Hub
      command: docker logout
      ignore_errors: yes
```

**Boas práticas aplicadas no Playbook:**
* **Idempotência:** O playbook pode correr tanto numa VM recém-criada como numa VM já em produção — instala o Docker apenas se faltar e usa `|| true` ao parar/remover o contentor anterior para não falhar no primeiro deploy.
* **Proteção de segredos (`no_log: true` e `docker logout`):** Evita que a palavra-passe do Docker Hub apareça nos logs da consola do Jenkins e termina a sessão no registo assim que o *pull* conclui.
* **Resiliência (`--restart unless-stopped`):** Garante que o contentor da Bookstore arranca automaticamente caso a VM de produção seja reiniciada.

---

## 6. A Pipeline Declarativa (`Jenkinsfile`)

O coração da solução está no `CA5/part2/Jenkinsfile`, que orquestra toda a entrega em 7 estágios sequenciais (com paralelismo na fase de testes):

#### Ficheiro `CA5/part2/Jenkinsfile`
```groovy
pipeline {
    agent any

    environment {
        DOCKER_REPO = "goncalodinisaraujoisep/bookstore-ca5"
        IMAGE_TAG = "${env.BRANCH_NAME}-${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                dir('CA5/part2/bookstore') {
                    sh './gradlew clean compileJava compileTestJava'
                }
            }
        }

        stage('Test') {
            parallel {
                stage('Unit Tests') {
                    steps {
                        dir('CA5/part2/bookstore') {
                            sh './gradlew test'
                        }
                    }
                    post {
                        always {
                            junit 'CA5/part2/bookstore/build/test-results/test/*.xml'
                        }
                    }
                }
                stage('Integration Tests') {
                    steps {
                        dir('CA5/part2/bookstore') {
                            sh './gradlew integrationTest'
                        }
                    }
                    post {
                        always {
                            junit 'CA5/part2/bookstore/build/test-results/integrationTest/*.xml'
                        }
                    }
                }
            }
        }

        stage('Package & Archive') {
            steps {
                dir('CA5/part2/bookstore') {
                    sh './gradlew bootJar'
                }
                archiveArtifacts artifacts: 'CA5/part2/bookstore/build/libs/*.jar, CA5/part2/Dockerfile', fingerprint: true
            }
        }

        stage('Build & Push Docker Image') {
            steps {
                dir('CA5/part2') {
                    withCredentials([usernamePassword(
                        credentialsId: 'dockerhub-credentials',
                        usernameVariable: 'DOCKER_USER',
                        passwordVariable: 'DOCKER_PASS'
                    )]) {
                        sh '''
                            echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                            docker build -t ${DOCKER_REPO}:${IMAGE_TAG} .
                            docker push ${DOCKER_REPO}:${IMAGE_TAG}
                            docker logout
                        '''
                    }
                }
            }
        }

        stage('Deploy to Production') {
            when {
                branch 'main'
            }
            steps {
                dir('CA5/part2') {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'dockerhub-credentials',
                            usernameVariable: 'DOCKER_USER',
                            passwordVariable: 'DOCKER_PASS'
                        ),
                        sshUserPrivateKey(
                            credentialsId: 'prod-vm-ssh-key',
                            keyFileVariable: 'SSH_KEY_FILE'
                        )
                    ]) {
                        sh '''
                            ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
                              --private-key="${SSH_KEY_FILE}" \
                              -e "docker_repo=${DOCKER_REPO} image_tag=${IMAGE_TAG} docker_user=${DOCKER_USER} docker_pass=${DOCKER_PASS}"
                        '''
                    }
                }
            }
        }

        stage('Health Check') {
            when {
                branch 'main'
            }
            steps {
                sh '''
                    sleep 10
                    curl -f [http://192.168.56.30:8080/actuator/health](http://192.168.56.30:8080/actuator/health) || curl -f [http://192.168.56.30:8080/](http://192.168.56.30:8080/)
                '''
            }
        }
    }

    post {
        success {
            echo "Pipeline ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.BRANCH_NAME}) succeeded!"
        }
        failure {
            echo "Pipeline ${env.JOB_NAME} #${env.BUILD_NUMBER} (${env.BRANCH_NAME}) failed!"
        }
    }
}
```

### Explicação Estágio a Estágio
1. **Checkout:** Sincroniza o código da branch atual a partir do GitHub.
2. **Build (Assemble):** Limpa artefactos antigos e compila tanto o código de produção como o código de testes (`compileJava compileTestJava`) para detetar erros de sintaxe logo no início.
3. **Test (em paralelo):** Executa simultaneamente os **Unit Tests** (`./gradlew test`) e os **Integration Tests** (`./gradlew integrationTest`), reduzindo o tempo total da pipeline. Os blocos `post { always }` garantem que os relatórios XML são sempre recolhidos pelo plugin **JUnit** para alimentar o gráfico *Test Result Trend*.
4. **Package & Archive:** Empacota a aplicação com `./gradlew bootJar` e arquiva tanto o ficheiro `bookstore-1.0.0.jar` como o **`Dockerfile`** no Jenkins com *fingerprinting* para garantir rastreabilidade completa de cada build.
5. **Build & Push Docker Image:** Constrói a imagem com uma tag única e rastreável (`${BRANCH_NAME}-${BUILD_NUMBER}`, ex.: `ca5-part2-9`), autentica-se com `--password-stdin` (evitando exposição na linha de comandos), publica no Docker Hub e faz `docker logout`.
6. **Deploy to Production:** Protegido pela condição `when { branch 'main' }` para que apenas *commits* integrados na branch **`main`** possam alterar o ambiente de produção (outras *branches* executam apenas até ao *push* da imagem). Injeta temporariamente a chave SSH (`prod-vm-ssh-key`) e as credenciais do Docker Hub no `ansible-playbook`.
7. **Health Check & Notificações (`post`):** Aguarda 10 segundos para a inicialização do Spring Boot dentro do contentor e valida via `curl -f` que o serviço responde com sucesso HTTP `200 OK` no endpoint `/actuator/health` (ou `/` como *fallback*). Por não existir um servidor SMTP ou *webhook* externo de Slack/Teams configurado neste ambiente académico isolado, as notificações de estado (`success` / `failure`) são emitidas de forma estruturada nos registos da pipeline.

---

## 7. Nota sobre Reprodutibilidade Multi-Ambiente (Linux vs. Windows/WSL2)

Os ficheiros base da solução (`Vagrantfile`, `Jenkinsfile`, `Dockerfile`, `ansible/inventory.ini` e `ansible/deploy.yml`) seguem estritamente os requisitos do guião e são **100% agnósticos ao sistema operativo**, sendo diretamente reproduzíveis em qualquer ambiente Linux onde o Jenkins e o VirtualBox partilhem a rede local (`192.168.56.30`).

### Experiência Extra de Portabilidade
Para além dos requisitos base do guião, procurou-se tornar o arranque da infraestrutura igualmente reproduzível de forma automatizada em máquinas **Windows** que executam o Jenkins dentro do **Docker Desktop (WSL2)** em simultâneo com o **VirtualBox**:

* **Ambiente Linux (`start-linux.sh`):** O Docker Engine e o VirtualBox partilham diretamente a tabela de encaminhamento do sistema anfitrião, bastando iniciar o contentor Jenkins e a VM (`docker start jenkins-ca5 && vagrant up`).
* **Ambiente Windows com WSL2 (`start-windows.sh` - Tentativa Extra):** Durante os testes em Windows, verificou-se uma limitação arquitetural do próprio sistema operativo: a micro-VM oculta do WSL2 onde corre o Docker Desktop não encaminha tráfego diretamente para a placa *Host-Only* (`192.168.56.x`) do VirtualBox, e a coexistência entre Hyper-V (WSL2) e VirtualBox introduz atrasos no arranque da VM. Como tentativa de resolução transparente sem alterar o `Jenkinsfile` nem o inventário Ansible, criou-se o script auxiliar `start-windows.sh` para configurar encaminhamento NAT via `VBoxManage` e uma ponte local `socat` dentro do contentor Jenkins. Contudo, devido às diferenças de permissões e tempos de arranque do VirtualBox sob Hyper-V entre reinícios do Windows, esta ponte demonstrou-se sensível ao estado da VM, confirmando que a execução em ambiente Linux nativo (ou com o Jenkins instalado diretamente no anfitrião) é a abordagem mais fiável e reprodutível.

---

## 8. Validação e Evidências de Execução

### 8.1. Overview do Projeto, Artefactos e Tendência de Testes
Na página principal do projeto no Jenkins (`http://localhost:8080/job/bookstore-ca5-part2/`), confirma-se o sucesso da build `#9`, o arquivo dos artefactos (`bookstore-1.0.0.jar` e `Dockerfile`) e o gráfico **Test Result Trend** totalmente a verde sem falhas:

> **[INSERIR PRINT 1 AQUI — Jenkins Overview]**
> *Como tirar/colar:* Abrir `http://localhost:8080/job/bookstore-ca5-part2/job/ca5-part2/` (ou `main`), capturar o ecrã mostrando o **Last Successful Artifacts** e o gráfico **Test Result Trend** a verde, e arrastar a imagem diretamente para aqui no editor do GitHub.

### 8.2. Execução Completa dos Estágios (Build `#9`)
Na vista **Stages**, verifica-se a passagem bem-sucedida de todos os estágios declarados no `Jenkinsfile` (Checkout, Build, Unit Tests & Integration Tests em paralelo, Package & Archive, Build & Push Docker Image, Deploy to Production e Health Check):

> **[INSERIR PRINT 2 AQUI — Jenkins Stage View]**
> *Como tirar/colar:* Na página da pipeline no Jenkins, capturar a tabela horizontal dos estágios (**Stage View**) mostrando todos os blocos a verde e os respetivos tempos de execução, e arrastar a imagem diretamente para aqui no editor do GitHub.

### 8.3. Imagem Publicada no Docker Hub
Após o estágio `Build & Push Docker Image`, a imagem versionada fica disponível no repositório público `goncalodinisaraujoisep/bookstore-ca5`:

> **[INSERIR PRINT 3 AQUI — Docker Hub Repository]**
> *Como tirar/colar:* Abrir `https://hub.docker.com/r/goncalodinisaraujoisep/bookstore-ca5/tags` no browser, capturar o ecrã mostrando a tag gerada pela pipeline (ex.: `ca5-part2-9` / `main-...`), e arrastar a imagem diretamente para aqui no editor do GitHub.

### 8.4. Validação da Aplicação em Produção
Após o Ansible lançar o contentor `bookstore-prod` na VM `192.168.56.30`, validou-se a resposta da API REST no endpoint `/books`:

```bash
# Em Windows (via NAT port forwarding 8085 -> 8080):
curl http://localhost:8085/books

# Em Linux (acesso direto à rede Host-Only):
curl [http://192.168.56.30:8080/books](http://192.168.56.30:8080/books)
```

A aplicação devolveu o JSON com os registos iniciais da base de dados (`Clean Code` e `Effective Java`):

> **[INSERIR PRINT 4 AQUI — Resposta JSON da API Bookstore]**
> *Como tirar/colar:* Abrir `http://localhost:8085/books` no browser (ou correr `curl http://localhost:8085/books` no terminal), capturar o ecrã mostrando a resposta JSON com os livros, e arrastar a imagem diretamente para aqui no editor do GitHub.

---

## 9. Solução Alternativa de CI/CD: Análise Comparativa e Desenho Técnico

### 9.1. Enquadramento: Porque Avaliar Alternativas ao Jenkins?
O **Jenkins** é uma ferramenta extremamente flexível e madura, sendo ideal quando é necessário controlo total sobre a infraestrutura local (como o acesso direto a máquinas virtuais VirtualBox numa rede privada). Contudo, apresenta desafios operacionais relevantes:
* **Sobrecarga de Manutenção (*Self-Hosted*):** Exige gerir um servidor dedicado (ou contentor), atualizações de segurança, backups de volumes e compatibilidade entre dezenas de *plugins*.
* **Complexidade de Triggers Locais:** Quando alojado localmente atrás de NAT, não consegue receber *webhooks* diretos do GitHub sem expor a rede através de túneis externos, obrigando a recorrer a *polling* periódico.
* **Curva de Aprendizagem:** A sintaxe baseada em Groovy (`Jenkinsfile`) e a gestão manual de agentes/credenciais tornam a configuração inicial mais morosa do que em plataformas *cloud-native*.

Para avaliar opções mais modernas e integradas, analisaram-se três alternativas líderes de mercado: **GitHub Actions**, **GitLab CI/CD** e **CircleCI**.

### 9.2. Análise Comparativa: Jenkins vs. Alternativas de CI/CD

| Critério / Funcionalidade | Jenkins (Solução Base) | GitHub Actions | GitLab CI/CD | CircleCI |
| :--- | :--- | :--- | :--- | :--- |
| **Modelo de Alojamento** | *Self-hosted* (gestão total do servidor e *plugins*) | *Cloud-native* (SaaS) com opção de *Self-Hosted Runners* | SaaS ou *Self-managed* (plataforma DevOps integrada) | *Cloud
