## Solução Alternativa de CI/CD: Análise Comparativa e Desenho Técnico

### 1. Enquadramento: Porque Avaliar Alternativas ao Jenkins?

O **Jenkins** é uma ferramenta extremamente flexível e madura, sendo ideal quando é necessário controlo total sobre a infraestrutura local (como o acesso direto a máquinas virtuais VirtualBox numa rede privada). Contudo, apresenta desafios operacionais relevantes em equipas modernas:
* **Sobrecarga de Manutenção (*Self-Hosted*):** Exige gerir um servidor dedicado (ou contentor), atualizações de segurança, backups de volumes e compatibilidade entre dezenas de *plugins*.
* **Complexidade de Triggers Locais:** Quando alojado localmente atrás de NAT, não consegue receber *webhooks* diretos do GitHub sem expor a rede através de túneis externos, obrigando a recorrer a *polling* periódico.
* **Curva de Aprendizagem:** A sintaxe baseada em Groovy (`Jenkinsfile`) e a gestão manual de agentes/credenciais tornam a configuração inicial mais morosa do que em plataformas *cloud-native*.

Para avaliar opções mais modernas e integradas, analisaram-se três alternativas líderes de mercado: **GitHub Actions**, **GitLab CI/CD** e **CircleCI**.

---

### 2. Análise Comparativa: Jenkins vs. Alternativas de CI/CD

| Critério / Funcionalidade | Jenkins (Solução Base) | GitHub Actions | GitLab CI/CD | CircleCI |
| :--- | :--- | :--- | :--- | :--- |
| **Modelo de Alojamento** | *Self-hosted* (gestão total do servidor e *plugins*) | *Cloud-native* (SaaS) com opção de *Self-Hosted Runners* | SaaS ou *Self-managed* (plataforma DevOps integrada) | *Cloud-native* (SaaS) com opção *Server/Runner* |
| **Definição da Pipeline** | `Jenkinsfile` (Groovy declarativo ou *scripted*) | Ficheiros YAML em `.github/workflows/*.yml` | Ficheiro único `.gitlab-ci.yml` (YAML) | Ficheiro `.circleci/config.yml` (YAML) |
| **Integração Git & Triggers** | Requer configuração de *Multibranch* + *Webhooks* (ou *polling*) | **Nativa** (eventos `push`, `pull_request`, `workflow_dispatch` sem webhooks manuais) | **Nativa** (disparo imediato em commits, *merge requests* e *tags*) | Integração externa via OAuth/Webhook com GitHub ou Bitbucket |
| **Execução Paralela** | Bloco `parallel` no `Jenkinsfile` (partilha recursos do agente) | **Nativa** (vários *jobs* independentes em paralelo ou `strategy.matrix`) | **Nativa** (vários *jobs* no mesmo *stage* ou DAG com `needs`) | Excelente (suporte nativo a paralelismo e divisão automática de testes) |
| **Gestão de Segredos** | *Credentials Manager* interno (exige configuração manual na UI) | **GitHub Secrets** (encriptados por repositório ou ambiente, ex.: `production`) | **CI/CD Variables** (protegidas e mascaradas por branch) | *Contexts* e variáveis de ambiente por projeto |
| **Ecossistema / Extensões** | +1.800 *plugins* (requer gestão de versões e reinícios) | **GitHub Marketplace** (Actions versionadas diretamente no YAML, sem instalação prévia) | *Templates* YAML reutilizáveis e *Container Registry* embutido | **Orbs** (pacotes YAML reutilizáveis) |
| **Acesso a VMs Locais (Vagrant)** | **Simples** (corre na mesma máquina/rede que o VirtualBox) | **Requer *Self-Hosted Runner*** local (runners na cloud não acedem a IPs privados `192.168.56.x`) | **Requer *GitLab Runner*** local registado na máquina | **Requer *Self-Hosted Runner*** local |

#### Síntese da Comparação
* **GitLab CI/CD** oferece uma experiência *all-in-one* muito forte (incluindo *Container Registry* próprio), mas obrigaria a migrar o repositório de código do GitHub para o GitLab para tirar partido da integração nativa.
* **CircleCI** destaca-se pela velocidade de *caching* e otimização de testes paralelos, mas introduz mais uma plataforma externa separada do repositório GitHub.
* **GitHub Actions** é a **alternativa mais adequada para este projeto**: o código já reside no GitHub, elimina a necessidade de manter um servidor Jenkins apenas para orquestração, fornece *triggers* nativos sem configuração de *webhooks* e suporta nativamente *runners* auto-alojados (*Self-Hosted Runners*) para o passo de *deploy* na VM local.

---

### 3. Desenho da Solução Alternativa com GitHub Actions

O objetivo deste desenho é resolver **exatamente os mesmos requisitos do CA5** (compilação Gradle, testes unitários e de integração em paralelo, arquivo de artefactos e `Dockerfile`, publicação da imagem no Docker Hub, *deploy* via Ansible restrito à branch `main`, *health check* e notificações), substituindo o Jenkins pelo **GitHub Actions**.

#### 3.1. Arquitetura Proposta

```text
+-------------------------------------------------------------------------+
|                           Repositório GitHub                            |
|                  (Evento nativo: push em main / dev)                    |
+------------------------------------+------------------------------------+
                                     | Trigger imediato (sem webhook manual)
                                     v
+-------------------------------------------------------------------------+
|               GitHub Actions - Cloud Runners (ubuntu-latest)            |
|                                                                         |
|  [Job 1: build]          -> ./gradlew clean compileJava compileTestJava |
|         |                                                               |
|         +---> [Job 2a: unit-tests]        (em paralelo + JUnit report)  |
|         +---> [Job 2b: integration-tests] (em paralelo + JUnit report)  |
|         |                                                               |
|         v                                                               |
|  [Job 3: package-and-push]                                              |
|    - ./gradlew bootJar                                                  |
|    - Upload Artifacts (.jar + Dockerfile)                               |
|    - Docker Build & Push (goncalodinisaraujoisep/bookstore-ca5:<tag>)   |
+------------------------------------+------------------------------------+
                                     | Apenas se github.ref == 'refs/heads/main'
                                     v
+-------------------------------------------------------------------------+
|           GitHub Self-Hosted Runner (na máquina anfitriã local)         |
|  [Job 4: deploy-and-verify]                                             |
|    - Executa ansible-playbook contra 192.168.56.30 (SSH via Secrets)    |
|    - Executa Health Check (curl [http://192.168.56.30:8080/actuator/](http://192.168.56.30:8080/actuator/)...) |
|    - Envia Notificação (Slack / Discord / GitHub Summary)               |
+------------------------------------+------------------------------------+
                                     | SSH + Ansible
                                     v
+-------------------------------------------------------------------------+
|              VM de Produção - Ubuntu 24.04 (192.168.56.30)              |
|                 Contentor bookstore-prod na porta 8080                  |
+-------------------------------------------------------------------------+
```

#### 3.2. Mapeamento dos Requisitos do CA5 (Jenkins vs. GitHub Actions)

| Requisito do Enunciado | Implementação Atual (Jenkins) | Desenho Equivalente (GitHub Actions) |
| :--- | :--- | :--- |
| **Execução sensível à branch (*Branch-aware*)** | *Multibranch Pipeline* com `Jenkinsfile` | Evento `on: push: branches: [main, ca5-part2, '**']` |
| **Disparo automático em commits** | *Webhook* ou *Polling* periódico | **Nativo** em cada `git push`, sem configuração de rede |
| **Testes Unitários e de Integração em paralelo** | Bloco `parallel { ... }` no estágio `Test` | Dois *jobs* distintos (`unit-tests` e `integration-tests`) com `needs: build`, executados em simultâneo em VMs isoladas |
| **Arquivo do JAR, `Dockerfile` e Relatórios** | `archiveArtifacts` + `junit` | `actions/upload-artifact@v4` (para `.jar` e `Dockerfile`) + `dorny/test-reporter@v1` (para relatórios XML JUnit) |
| **Build & Push da Imagem Docker** | `docker login` / `build` / `push` com `withCredentials` | `docker/login-action@v3` + `docker/build-push-action@v6` usando `${{ secrets.DOCKERHUB_USERNAME }}` e `${{ secrets.DOCKERHUB_TOKEN }}` |
| **Deploy restrito apenas à branch `main`** | Condição `when { branch 'main' }` | Condição `if: github.ref == 'refs/heads/main'` no *job* de *deploy* |
| **Deploy via Ansible + Health Check** | `ansible-playbook` + `curl -f` no contentor Jenkins | *Job* com `runs-on: self-hosted` executando o mesmo `ansible/deploy.yml` e validação `curl` |
| **Notificações de Sucesso / Falha** | Bloco `post { success / failure }` | *Step* condicional com `if: always()` usando *actions* nativas de Slack/Teams/Email ou `$GITHUB_STEP_SUMMARY` |

#### 3.3. Esboço Técnico do Workflow (`.github/workflows/ca5-part2.yml`)

O excerto seguinte ilustra como a pipeline completa seria declarada em GitHub Actions para cumprir integralmente os requisitos da Parte 2:

```yaml
name: CA5 Part 2 - Bookstore CI/CD

on:
  push:
    branches: ['main', 'ca5-part2', 'dev']

env:
  DOCKER_REPO: goncalodinisaraujoisep/bookstore-ca5

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'
          cache: 'gradle'
      - name: Compile Java and Tests
        working-directory: CA5/part2/bookstore
        run: ./gradlew clean compileJava compileTestJava

  unit-tests:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17', cache: 'gradle' }
      - name: Run Unit Tests
        working-directory: CA5/part2/bookstore
        run: ./gradlew test
      - name: Publish Unit Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: unit-test-results
          path: CA5/part2/bookstore/build/test-results/test/*.xml

  integration-tests:
    needs: build
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17', cache: 'gradle' }
      - name: Run Integration Tests
        working-directory: CA5/part2/bookstore
        run: ./gradlew integrationTest
      - name: Publish Integration Test Results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: integration-test-results
          path: CA5/part2/bookstore/build/test-results/integrationTest/*.xml

  package-and-push:
    needs: [unit-tests, integration-tests]
    runs-on: ubuntu-latest
    outputs:
      image_tag: ${{ steps.meta.outputs.tag }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: 'temurin', java-version: '17', cache: 'gradle' }
      - name: Build JAR
        working-directory: CA5/part2/bookstore
        run: ./gradlew bootJar
      - name: Archive JAR and Dockerfile
        uses: actions/upload-artifact@v4
        with:
          name: bookstore-artifacts-${{ github.run_number }}
          path: |
            CA5/part2/bookstore/build/libs/*.jar
            CA5/part2/Dockerfile
      - name: Define Image Tag
        id: meta
        run: echo "tag=${GITHUB_REF_NAME}-${GITHUB_RUN_NUMBER}" >> "$GITHUB_OUTPUT"
      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - name: Build and Push Docker Image
        uses: docker/build-push-action@v6
        with:
          context: CA5/part2
          file: CA5/part2/Dockerfile
          push: true
          tags: ${{ env.DOCKER_REPO }}:${{ steps.meta.outputs.tag }}

  deploy-production:
    needs: package-and-push
    if: github.ref == 'refs/heads/main'
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Deploy with Ansible
        working-directory: CA5/part2
        env:
          SSH_PRIVATE_KEY: ${{ secrets.PROD_VM_SSH_KEY }}
        run: |
          echo "$SSH_PRIVATE_KEY" > /tmp/prod_key && chmod 600 /tmp/prod_key
          ansible-playbook -i ansible/inventory.ini ansible/deploy.yml \
            --private-key=/tmp/prod_key \
            -e "docker_repo=${{ env.DOCKER_REPO }} image_tag=${{ needs.package-and-push.outputs.image_tag }} docker_user=${{ secrets.DOCKERHUB_USERNAME }} docker_pass=${{ secrets.DOCKERHUB_TOKEN }}"
          rm -f /tmp/prod_key
      - name: Health Check
        run: |
          sleep 10
          curl -f [http://192.168.56.30:8080/actuator/health](http://192.168.56.30:8080/actuator/health) || curl -f [http://192.168.56.30:8080/](http://192.168.56.30:8080/)
      - name: Notify Pipeline Status
        if: always()
        run: echo "Deploy status for ${{ github.sha }}: ${{ job.status }}" >> "$GITHUB_STEP_SUMMARY"
```

---

### 4. Análise Crítica, Limitações e Reflexão

1. **O Desafio da Rede Privada (Cloud vs. Local):**
   A principal limitação de utilizar uma ferramenta *cloud-native* como o GitHub Actions neste cenário académico é a conectividade com a VM de produção. Os *runners* geridos pelo GitHub (`ubuntu-latest`) correm em datacenters públicos da Microsoft e **não têm rota de rede** para o endereço privado `192.168.56.30` de uma máquina VirtualBox local.
   * **Como o desenho resolve isto:** Utiliza uma **arquitetura híbrida** — os *jobs* de compilação, testes paralelos e *Docker push* correm na *cloud* (sem consumir CPU/RAM local e com paralelismo real em máquinas separadas), enquanto apenas o *job* final de *deploy* (`deploy-production`) é delegado a um **GitHub Self-Hosted Runner** na máquina local. Como o *Self-Hosted Runner* inicia ligações *outbound* (HTTPS) para o GitHub, não é necessário abrir portas no *router* nem configurar *webhooks*.
   * **Alternativa em Produção Real:** Num ambiente empresarial real, a VM de produção estaria alojada numa *cloud* pública (AWS EC2, Azure VM ou GCP) ou ligada via VPN *mesh* (ex.: Tailscale), permitindo executar 100% da pipeline em *runners* geridos sem qualquer componente local.

2. **Vantagens do GitHub Actions face ao Jenkins:**
   * **Zero manutenção de servidor:** Elimina a necessidade de manter o contentor `jenkins-ca5`, atualizar *plugins* ou gerir backups do `jenkins_home`.
   * **Triggers nativos e instantâneos:** Não exige *polling* periódico nem exposição de IP público para receber *webhooks*.
   * **Isolamento real nos testes paralelos:** No Jenkins (com um único agente), os testes em paralelo partilham o mesmo sistema de ficheiros e CPU; no GitHub Actions, cada *job* corre numa VM limpa e descartável.

3. **Âmbito da Implementação:**
   A solução alternativa com GitHub Actions foi analisada e desenhada em detalhe ao nível arquitetural e de especificação de *workflow*, não tendo sido ativada em execução contínua sobre a VM local devido à dependência de um *Self-Hosted Runner* permanentemente ativo na máquina do utilizador. Em contrapartida, a solução base com **Jenkins + Docker + Vagrant + Ansible** encontra-se integralmente implementada, testada e validada de ponta a ponta.
