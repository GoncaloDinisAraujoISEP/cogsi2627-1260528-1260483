# CA2 - Parte 2: Arquitetura Alternativa ao Vagrant (Multipass / LXD com Cloud-Init)

## 1. Visão Geral da Arquitetura

Em conformidade com os requisitos da **Parte 2 do trabalho prático CA2**, concebeu-se e implementou-se uma arquitetura multi-nó isolada para suportar a execução da aplicação *Bookstore* (desenvolvida sobre a framework Spring Boot com Gradle) com base de dados segregada e acesso unificado através de um proxy reverso.

Como solução alternativa à orquestração baseada em **Vagrant + VirtualBox**, explorou-se uma abordagem declarativa moderna assente no ecossistema Canonical através de manifestos **Cloud-Init** (`#cloud-config`).

A arquitetura mantém a segregação estrita de responsabilidades em três camadas de execução:
- **`db`**: Instância Ubuntu 24.04 executando o motor de base de dados H2 Database em modo TCP Server na porta `9092`, gerido via unidade systemd (`h2.service`) e protegido por regras de firewall UFW restritas ao tráfego proveniente da aplicação.
- **`app`**: Instância com OpenJDK 17 e Git, alojando a aplicação Spring Boot *Bookstore* gerida como serviço de sistema (`bookstore.service`), comunicando via protocolo JDBC/TCP com o nó `db`.
- **`proxy`**: Instância de terminação com NGINX configurado como Reverse Proxy na porta `80`, atuando como porta de entrada e reencaminhando as requisições HTTP para a aplicação no nó `app` (porta `8080`).

### 1.1. Adaptação Técnica ao Ambiente de Execução (KVM / LXD)
Durante os testes de arranque com o Multipass num ambiente virtualizado anfitrião, identificou-se a indisponibilidade de extensões de virtualização de hardware aninhada (`/dev/kvm missing`), impedindo o lançamento de máquinas virtuais completas.

Para superar esta limitação técnica sem comprometer os requisitos da alternativa, utilizou-se o motor de contentores de sistema **LXD/LXC** da Canonical. Esta solução permitiu processar **rigorosamente os mesmos manifestos declarativos Cloud-Init** (`user.user-data`) com isolamento completo de namespaces e serviços systemd independentes, com desempenho superior e menor pegada de memória.

---

## 2. Tutorial de Reprodução e Execução

Para reproduzir a solução de forma totalmente automatizada a partir da raiz da pasta `CA2/part2-alternative/`:

### 2.1. Execução Automática em Comando Único (One-Command)
Para lançar e configurar todo o cluster sem qualquer intervenção manual, execute o script de orquestração fornecido:

```bash
cd CA2/part2-alternative
./up.sh
```

### 2.2. O que o script de automação (`up.sh`) executa:
1. **Lançamento Declarativo:** Cria as três instâncias (`db`, `app`, `proxy`) injetando os respetivos manifestos `cloud-init` com limites de recursos definidos (CPU e RAM).
2. **Sincronização de Provisionamento:** Aguarda de forma bloqueante até que o processo de inicialização de cada nó termine com sucesso (`cloud-init status --wait`).
3. **Interligação Dinâmica de Rede:**
   - Deteta os endereços IPv4 atribuídos por DHCP pela bridge virtual do LXD.
   - Aplica a regra de firewall no nó `db` permitindo apenas conexões provenientes do IP do nó `app` na porta `9092`.
   - Injeta o IP atual do nó `db` na unidade systemd do nó `app` e recarrega o serviço `bookstore.service`.
   - Atualiza a diretiva `proxy_pass` da configuração NGINX no nó `proxy` apontando para o IP do `app:8080`, ativando o ficheiro em `/etc/nginx/sites-enabled/`.
4. **Health Check Proativo:** Executa sondagens ativas (`polling`) ao endpoint `/health` até que a aplicação Spring Boot conclua o arranque e a ligação com a base de dados H2.
5. **Apresentação de URLs:** Disponibiliza no terminal os endereços prontos para validação funcional.

---

## 3. Evidências de Execução e Validação Funcional

### 3.1. Estado do Cluster e Topologia de Rede
Os três nós foram instanciados com sucesso, obtendo endereçamento IP dedicado na mesma sub-rede virtual:

```bash
lxc list
```
<img width="955" alt="Lista de instâncias LXC em execução" src="https://github.com/user-attachments/assets/7aee1928-f84a-4733-9219-34dd9916d8b4" />

---

### 3.2. Conclusão do Provisionamento (Cloud-Init)
A validação do ciclo de vida das instâncias comprova que todos os manifestos declarativos foram executados sem erros:

```bash
lxc exec db -- cloud-init status
lxc exec app -- cloud-init status
lxc exec proxy -- cloud-init status
```
<img width="865" alt="Estado de conclusão do Cloud-Init" src="https://github.com/user-attachments/assets/ea208f52-cf49-42cf-b3aa-2361ca0623a3" />

---

### 3.3. Terminação de Tráfego no Proxy Reverso (NGINX)
O acesso HTTP à raiz do proxy na porta `80` reencaminha transparentemente para o serviço Spring Boot, devolvendo resposta `HTTP/1.1 200 OK` e os hiperlinks HATEOAS da aplicação:

```bash
curl -i http://10.148.196.175/
```
<img width="2024" alt="Resposta do Proxy Reverso NGINX" src="https://github.com/user-attachments/assets/56e13d4a-1c1e-4de0-89e0-a9455c145e7a" />

---

### 3.4. Comunicação Integrada com a Base de Dados (`/books`)
A consulta de dados comprova a integridade da cadeia de comunicação completa (*Cliente* $\rightarrow$ *Proxy NGINX* $\rightarrow$ *Spring Boot* $\rightarrow$ *H2 TCP Server*):

```bash
curl -s http://10.148.196.175/books | jq .
```
<img width="1206" alt="Listagem de dados persistidos" src="https://github.com/user-attachments/assets/799c87a2-d37a-4ef3-a6d6-44f3726c3a6b" />

---

### 3.5. Monitorização e Saúde do Serviço (`/health`)
O endpoint operacional do Spring Boot Actuator confirma o estado ativo (`UP`) através da camada de proxy:

```bash
curl -i http://10.148.196.175/health
```
<img width="856" alt="Verificação de Saúde via Actuator" src="https://github.com/user-attachments/assets/d5f75672-6b1b-4188-8dae-1ddb94bafaf9" />

---

## 4. Análise Comparativa: Vagrant vs. Multipass / Cloud-Init

| Dimensão Técnica | Vagrant (HashiCorp) | Multipass / LXD (Canonical) |
| :--- | :--- | :--- |
| **Ecossistema e Suporte a SO** | Agnóstico a SO: suporta distribuições Linux (Debian, RHEL, Alpine), Windows e FreeBSD. | Focado prioritariamente no ecossistema Ubuntu (imagens cloud oficiais da Canonical). |
| **Paradigma de Configuração** | Ficheiro `Vagrantfile` baseado numa DSL mista imperativa/declarativa em Ruby. | CLI nativa aliada a manifestos declarativos YAML padrão (`cloud-init`). |
| **Topologia de Rede Local** | Suporte determinístico para redes privadas estáticas (`private_network`) e port-forwarding local. | Alocação prioritária via DHCP gerido pela bridge virtual; IPs atribuídos dinamicamente. |
| **Integração com Produção** | Requer plugins e adaptadores para reprodução direta em clouds públicas. | Elevada paridade com clouds modernas (AWS, Azure, OCI), partilhando a especificação standard `cloud-init`. |
| **Overhead e Desempenho** | Maior consumo de memória e latência de I/O devido à virtualização completa e pastas partilhadas. | Arranque ágil com menor pegada de memória em repouso (sobretudo em arquiteturas de contentores de sistema). |

---

## 5. Avaliação Crítica e Limitações Observadas

Durante a implementação prática da arquitetura alternativa, identificaram-se os seguintes pontos críticos:
1. **Dependência de Virtualização por Hardware (KVM):** Ao tentar executar VMs completas com Multipass dentro de uma máquina virtual convidada sem *nested virtualization* ativada, o arranque falha pela ausência de `/dev/kvm`. O recurso a contentores LXD permitiu ultrapassar esta barreira sem desvirtuar o paradigma declarativo do Cloud-Init.
2. **Resolução de Nomes e Ordem de Provisionamento:** O Vagrant oferece mecanismos síncronos e redes privadas estáticas previsíveis. No modelo com Cloud-Init e IPs atribuídos via DHCP, a resolução interna e as regras de firewall dependem da injeção dinâmica de endereços em tempo de execução, garantida pelo script de orquestração `up.sh`.

Em conclusão, o **Vagrant** permanece a ferramenta de eleição para fluxos de desenvolvimento local que exigem redes privadas fixas previsíveis e suporte multi-SO, enquanto a abordagem assente em **Cloud-Init** aproxima o ambiente de desenvolvimento das práticas modernas de automação em infraestruturas *Cloud Native*.
