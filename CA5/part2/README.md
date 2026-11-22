# CA5 - Parte 2: Pipeline CI/CD com Jenkins, Docker, Vagrant e Ansible

## 1. Visão Geral e História da Arquitetura

O objetivo desta segunda parte do **CA5** consistiu em automatizar todo o ciclo de vida da aplicação **Bookstore** (Spring Boot / Gradle) através de uma pipeline completa de **Integração Contínua e Entrega Contínua (CI/CD)** orquestrada pelo **Jenkins**.

Em vez de compilar código, construir imagens e configurar servidores manualmente, toda a entrega passou a ser desencadeada a partir do repositório Git: sempre que a pipeline executa, o Jenkins valida o código, corre os testes unitários, empacota o artefacto `.jar`, publica uma nova imagem no Docker Hub e utiliza o **Ansible** para atualizar automaticamente a máquina virtual de produção (`prod`).

```
+-------------------------------------------------------------------+
|                        Repositório GitHub                         |
|                    (Branch / Tag: ca5-part2)                      |
+---------------------------------+---------------------------------+
                                  | Checkout (Multibranch Pipeline)
                                  v
+-------------------------------------------------------------------+
|                   Contentor Jenkins (jenkins-ca5)                 |
|  1. Build & Testes Unitários (./gradlew test bootJar)             |
|  2. Arquivo de Artefactos (bookstore-1.0.0.jar) & Relatório JUnit |
|  3. Docker Build & Push (Docker Hub: pbarbosa08/...)              |
|  4. Deploy via Ansible Playbook (SSH -> 192.168.56.30)            |
+---------------------------------+---------------------------------+
                                  | SSH + Ansible
                                  v
+-------------------------------------------------------------------+
|               VM de Produção - Ubuntu 24.04 (prod)                |
|                       IP Privado: 192.168.56.30                   |
|          Contentor Bookstore a correr na porta TCP 8080           |
+-------------------------------------------------------------------+
```

### Componentes da Solução

| Componente | Tecnologia | Função na Arquitetura |
| :--- | :--- | :--- |
| **Orquestrador CI/CD** | Jenkins (`jenkins-ca5` em Docker) | Executa os estágios da pipeline definidos no `Jenkinsfile` |
| **Aplicação** | Spring Boot / Gradle (`CA1/part2`) | API REST da Bookstore empacotada num contentor Docker |
| **Registry de Imagens** | Docker Hub | Armazena as imagens Docker versionadas geradas pela pipeline |
| **Servidor de Produção** | Vagrant + VirtualBox (`Ubuntu 24.04`) | Máquina virtual alvo (`192.168.56.30`) onde a aplicação corre |
| **Gestão de Configuração** | Ansible | Provisiona o Docker na VM e garante o arranque do contentor atualizado |

---

## 2. Estrutura de Ficheiros (`CA5/part2`)

```text
CA5/part2/
├── Jenkinsfile              # Definição declarativa de todos os estágios da pipeline
├── Vagrantfile              # Definição da VM de produção (prod - 192.168.56.30)
├── ansible/
│   ├── inventory.ini        # Inventário apontando para 192.168.56.30 (utilizador vagrant)
│   └── deploy.yml           # Playbook Ansible para instalar Docker e lançar o contentor
├── start-linux.sh           # Script de arranque automático para ambientes Linux
├── start-windows.sh         # Script de arranque e ponte de rede para Windows (WSL2)
└── README.md                # Documentação técnica e evidências de execução
```

---

## 3. Passo a Passo da Implementação

### Passo 1: Preparação da Infraestrutura Base
Para suportar o fluxo CI/CD de ponta a ponta, prepararam-se dois ambientes distintos:
1. **Servidor Jenkins (`jenkins-ca5`):** Contentor Docker equipado com JDK, Docker CLI (ligado ao *socket* do anfitrião para construir imagens) e Ansible para executar o *deploy* remoto.
2. **Servidor de Produção (`prod`):** Máquina virtual Ubuntu 24.04 criada via Vagrant (`Vagrantfile`), configurada com uma interface de rede privada (`eth1`) no endereço fixo **`192.168.56.30`**.

### Passo 2: Configuração de Segurança e Credenciais no Jenkins
Para evitar qualquer exposição de palavras-passe ou chaves privadas no repositório Git, todos os segredos foram armazenados no gestor de credenciais do Jenkins (*Manage Jenkins -> Credentials*):
* **`dockerhub-creds` (*Username with password*):** Credenciais da conta Docker Hub para autenticar o `docker push` da imagem construída.
* **`ca5-prod-ssh-key` (*SSH Username with private key*):** Chave privada SSH associada ao utilizador `vagrant`, cuja chave pública correspondente foi previamente autorizada em `~/.ssh/authorized_keys` na VM `prod`, permitindo ao Ansible ligar-se sem intervenção manual.

### Passo 3: Anatomia da Pipeline (`Jenkinsfile`)
A pipeline foi configurada no Jenkins como um **Multibranch Pipeline** ligado ao repositório GitHub, executando sequencialmente os seguintes estágios:

1. **Checkout:** Obtém o código-fonte do repositório na revisão atual.
2. **Build & Test:** Executa `./gradlew test bootJar` dentro da pasta da aplicação. Os resultados dos testes unitários são recolhidos pelo plugin **JUnit** para gerar o histórico de qualidade, e o ficheiro `bookstore-1.0.0.jar` é arquivado no Jenkins como artefacto da build.
3. **Docker Build & Push:** Constrói a imagem Docker da aplicação com a *tag* correspondente ao número da build / commit e publica-a no Docker Hub.
4. **Deploy to Production (Ansible):** Executa o playbook `ansible/deploy.yml` contra o inventário `192.168.56.30`. O Ansible garante que o serviço Docker está ativo na VM, faz *pull* da imagem mais recente do Docker Hub, substitui qualquer contentor anterior e inicia a nova versão da Bookstore na porta `8080`.
5. **Health Check:** Valida no final do *deploy* que a API responde com código HTTP `200 OK` no endpoint `/books`.

<img width="2551" height="1039" alt="image" src="https://github.com/user-attachments/assets/ce8ebda9-4564-48d2-a30b-de863e411d49" />


---

## 4. Inicialização do Ambiente e Desafios Superados (Linux vs. Windows)

Durante o desenvolvimento em equipa, identificou-se uma diferença importante entre correr a infraestrutura num sistema **Linux nativo** e num sistema **Windows (WSL2 + Docker Desktop + VirtualBox)**. Para garantir que qualquer membro da equipa ou docente consegue arrancar o ambiente com um único comando sem alterar o `Jenkinsfile` nem o inventário Ansible, criaram-se dois scripts dedicados.

### 4.1. Execução em Linux (Nativo ou VM Ubuntu)
Em Linux, o Docker Engine e o VirtualBox partilham diretamente a tabela de encaminhamento do sistema anfitrião. O contentor `jenkins-ca5` alcança o IP `192.168.56.30` sem qualquer configuração adicional:

```bash
chmod +x start-linux.sh
./start-linux.sh
```
Após o arranque, a aplicação em produção fica acessível diretamente em `http://192.168.56.30:8080/books`.

### 4.2. Execução em Windows (WSL2 + Docker Desktop + VirtualBox)
No Windows, surgiram três obstáculos técnicos inerentes à arquitetura de virtualização do sistema operativo:
1. **Isolamento de Redes:** O Docker Desktop executa o contentor Jenkins dentro da micro-VM oculta do **WSL2**, cuja rede virtual não encaminha tráfego diretamente para a placa *Host-Only* (`192.168.56.x`) do VirtualBox (resultando em erros de *No route to host* / *Connection timed out*).
2. **Coexistência Hyper-V / VirtualBox:** A execução simultânea do WSL2 (Hyper-V) e do VirtualBox atrasa o arranque da VM, fazendo por vezes com que a interface privada `eth1` inicie no estado `DOWN` ou que o `vagrant up` atinja o *boot timeout*.
3. **Conflito na Porta NAT Padrão (`2222`):** O encaminhamento SSH padrão do Vagrant na porta `2222` sofre conflitos de ligação quando acedido através de pontes externas.

**Solução Implementada (`start-windows.sh`):**
Para manter o repositório limpo e funcional em ambos os sistemas operativos, o script `start-windows.sh` automatiza a criação de uma ponte transparente:
1. Inicia o contentor `jenkins-ca5` e a VM `prod`.
2. Cria regras de encaminhamento NAT no VirtualBox (`VBoxManage`) mapeando a porta `2225` do Windows para a porta `22` (SSH) da VM, e a porta `8085` para a porta `8080` (Bookstore).
3. Garante por SSH que a placa `eth1` está ativa (`UP`) com o IP `192.168.56.30/24` e que a chave pública extraída do contentor Jenkins está autorizada na VM.
4. Instala e executa o utilitário **`socat`** dentro do contentor Jenkins, associando o IP `192.168.56.30` à interface *loopback* do contentor e encaminhando o tráfego da porta `22` para `host.docker.internal:2225`.

```bash
chmod +x start-windows.sh
./start-windows.sh
```
Desta forma, o Ansible dentro do Jenkins comunica normalmente com `192.168.56.30:22` sem qualquer alteração ao código do projeto, e a aplicação fica acessível no browser do Windows em `http://localhost:8085/books`.

---

## 5. Validação e Evidências de Execução

### 5.1. Execução Completa da Pipeline no Jenkins
Após acionar o **Build Now** no Jenkins, todos os estágios da pipeline (Checkout, Build & Test, Docker Build & Push, Deploy to Production e Health Check) concluíram com sucesso (**Build #9** a verde).

<img width="2558" height="1087" alt="image" src="https://github.com/user-attachments/assets/f526153e-1f84-4f53-8a5d-7be6942cd0a1" />

### 5.2. Validação da Aplicação em Produção
Para confirmar que o contentor da Bookstore foi efetivamente atualizado e iniciado na VM de produção pelo Ansible, acedeu-se ao endpoint `/books`, verificando a resposta JSON com os registos iniciais da base de dados:

```bash
curl http://localhost:8085/books   # (ou [http://192.168.56.30:8080/books](http://192.168.56.30:8080/books) em Linux)
```

<img width="1655" height="220" alt="image" src="https://github.com/user-attachments/assets/5476be81-7347-4c3c-8956-0a898e140cb3" />


### 5.3. Controlo de Versões e Tagging
Por fim, validou-se que a árvore de trabalho do Git se encontrava limpa e publicou-se a *tag* oficial **`ca5-part2`** no repositório remoto antes da integração na branch `main`:

```bash
git status
git tag -f ca5-part2
git push -f origin refs/tags/ca5-part2
```

---

## 6. Autoavaliação e Contribuição da Equipa

Em conformidade com os critérios de avaliação da unidade curricular, a distribuição do esforço e contributo dos elementos do grupo foi a seguinte:

| Número Mecanográfico | Nome do Estudante | Contribuição (%) |
| :---: | :--- | :---: |
| 1260528 | Gonçalo Dinis Araújo | 50% |
| 1260483 | Pedro Barbosa | 50% |
