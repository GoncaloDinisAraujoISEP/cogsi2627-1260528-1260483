# Relatório Técnico: CA2 - Parte 2 (Arquitetura Multi-VM com Vagrant)

## 1. Introdução e Visão Geral da Arquitetura

O objetivo desta etapa consistiu na evolução do ambiente de execução da aplicação **Bookstore** de um cenário mononó para uma arquitetura distribuída de 3 camadas (*three-tier*), orquestrada via **Vagrant** sobre o **VirtualBox**.

A solução desacopla as responsabilidades do sistema em três máquinas virtuais Linux (Ubuntu 24.04 LTS), isoladas numa rede privada interna (`private_network`) e com um ponto único de entrada gerido por um Reverse Proxy Nginx.

```
+-------------------------------------------------------------+
|                     Host Machine (Windows)                  |
|                   Browser / curl: localhost:8080            |
+------------------------------+------------------------------+
                               | Port Forward: 8080 -> 80
                               v
               +-------------------------------+
               |          proxy Node           |
               |         192.168.56.12         |
               |        (Nginx Gateway)        |
               +---------------+---------------+
                               | HTTP Proxy (porta 8080)
                               v
               +-------------------------------+
               |           app Node            |
               |         192.168.56.11         |
               |      (Spring Boot / Java 17)  |
               +---------------+---------------+
                               | TCP JDBC (porta 9092)
                               v
               +-------------------------------+
               |           db Node             |
               |         192.168.56.10         |
               |     (H2 Server Mode + UFW)    |
               +-------------------------------+
```

### Tabela de Topologia e Endereçamento de Rede

| Nó | IP Privado | Serviços Ativos | Portas Internas | Port Forward Host |
| :--- | :--- | :--- | :--- | :--- |
| **`proxy`** | `192.168.56.12` | Nginx (Reverse Proxy) | `80/tcp` | `8080` (host) $\rightarrow$ `80` (guest) |
| **`app`** | `192.168.56.11` | Spring Boot (Bookstore API) | `8080/tcp` | N/A (tráfego interno via proxy) |
| **`db`** | `192.168.56.10` | H2 Database Server Mode | `9092/tcp` | N/A (acesso restrito à `app`) |

---

## 2. Passo a Passo da Implementação e Desafios Superados

A implementação decorreu de forma incremental ao longo de quatro fases principais:

### 2.1. Configuração da Base de Dados H2 e Gestão de Permissões (`db`)
No nó de dados, foi configurado o serviço `h2.service` sob o Systemd para executar o servidor H2 em modo daemon, permitindo conexões TCP externas através do parâmetro `-tcpAllowOthers`.

* **Desafio de Idempotência:** Durante os testes iniciais de arranque, a flag de segurança `-ifNotExists` do servidor H2 impedia que novas conexões criassem a base de dados em tempo de execução se o ficheiro físico ainda não existisse na diretoria `/opt/h2-data`.
* **Solução:** O script de provisionamento `db_provision.sh` foi otimizado para pré-criar o diretório e o ficheiro da base de dados antes do arranque do serviço Systemd:
  ```bash
  mkdir -p /opt/h2-data
  touch /opt/h2-data/bookstore.mv.db
  chmod -R 777 /opt/h2-data
  ```

### 2.2. Restrição de Segurança por Firewall com UFW (`db`)
Conforme as boas práticas de segurança em redes privadas, a base de dados não deve estar acessível indiscriminadamente. Configurou-se o firewall `ufw` na VM `db` com uma política restritiva:
* Negação de todo o tráfego de entrada por defeito (`default deny incoming`).
* Abertura estrita da porta TCP `9092` **apenas** para o IP de origem `192.168.56.11` (nó `app`).

<img width="951" height="245" alt="image" src="https://github.com/user-attachments/assets/e2e16814-54aa-4e9b-a3b1-a0faa6b756ea" />


### 2.3. Provisionamento da Aplicação e Health Check de Rede (`app`)
A aplicação Spring Boot Bookstore depende diretamente da base de dados H2 remota. Se a aplicação arrancar antes do serviço H2 estar pronto para escutar conexões TCP, o Hibernate falha a inicialização do `EntityManagerFactory`.

* **Implementação de Health Check:** No script `app_provision.sh`, recorreu-se ao utilitário `netcat` (`nc`) para implementar um ciclo de espera ativa que verifica a disponibilidade da porta `9092` no IP `192.168.56.10` antes do arranque do serviço `bookstore.service`:
  ```bash
  echo "=== [APP] Health Check: Aguardar pelo servidor H2 (192.168.56.10:9092) ==="
  until nc -z -v -w5 192.168.56.10 9092; do
      echo "A aguardar pela base de dados H2..."
      sleep 3
  done
  echo "Ligacao estabelecida com sucesso ao H2!"
  ```

### 2.4. Integração do Reverse Proxy Nginx (`proxy`)
O nó `proxy` foi provisionado com Nginx, atuando como *gateway* de entrada do cluster. Foi configurado um bloco de servidor para redirecionar todas as requisições HTTP recebidas na porta `80` para a instância interna do Spring Boot em `http://192.168.56.11:8080`, preservando os cabeçalhos HTTP (`Host`, `X-Real-IP`, `X-Forwarded-For`).

* **Health Check e Resiliência de Arranque:**
Para mitigar condições de corrida (*race conditions*) durante o provisionamento sequencial (`vagrant up`) e prevenir erros transitórios de `502 Bad Gateway`, foi incorporado um ciclo ativo com `netcat` no `proxy_provision.sh`. O serviço Nginx só é reiniciado após a porta TCP `8080` do nó `app` (`192.168.56.11`) se encontrar totalmente aberta e a responder. Adicionalmente, procedeu-se ao ajuste equilibrado dos recursos no `Vagrantfile` (`db`: 1024MB/1CPU, `app`: 2048MB/2CPUs, `proxy`: 512MB/1CPU) e à definição de `boot_timeout = 800` para acomodar o tempo de compilação da aplicação Spring Boot.

---

---

## 3. Validação e Testes do Ambiente

### 3.1. Estado do Cluster de Máquinas Virtuais
A orquestração do cluster foi validada através da CLI do Vagrant a partir do sistema anfitrião:

```powershell
vagrant status
```

<img width="700" height="212" alt="image" src="https://github.com/user-attachments/assets/43c35386-08b2-47dd-ba41-d0dd6ef3c64e" />


### 3.2. Acesso à API REST através do Navegador Host
O acesso à solução é efetuado a partir do browser da máquina anfitriã através de `http://localhost:8080`.

1. **Endpoint Raiz (HAL JSON Catalog):**
   Ao aceder à raiz, o Reverse Proxy recebe o pedido na porta `8080` mapeada, entrega-o à `app` e esta devolve o catálogo oficial HATEOAS com os hiperlinks de navegação (`_links`).

<img width="463" height="555" alt="image" src="https://github.com/user-attachments/assets/c1e20320-5ddb-41e9-ae5f-c1ff867fc661" />


2. **Endpoint de Recursos de Negócio (`/books`):**
   Acedendo a `http://localhost:8080/books`, valida-se o ciclo completo da arquitetura: o browser contacta o Nginx (`proxy`), que contacta a Bookstore (`app`), que consulta as tabelas de entidades no servidor H2 (`db`).

<img width="392" height="373" alt="image" src="https://github.com/user-attachments/assets/77570eb7-8808-4c85-8bda-26782c91b39c" />


---

## 4. Guia Rápido de Execução

Para reproduzir o ambiente integral a partir do repositório:

1. Clonar o repositório e aceder à pasta do projeto:
   ```powershell
   git clone https://github.com/GoncaloDinisAraujoISEP/cogsi2627-1260528-1260483
   cd CA2/part2
   ```
2. Inicializar o cluster completo:
   ```powershell
   vagrant up
   ```
3. Testar a conectividade no browser do anfitrião:
   - Catálogo API: `http://localhost:8080`
   - Coleção Livros: `http://localhost:8080/books`
4. Encerrar o ambiente de forma controlada após os testes:
   ```powershell
   vagrant halt
   ```

---

## 5. Reflexão Teórica: Desenvolvimento vs. CI/CD

> **Questão:** A estratégia de provisionamento adotada neste projeto está mais alinhada com um ambiente de Desenvolvimento ou com um pipeline de CI/CD?

A abordagem implementada neste trabalho posiciona-se predominantemente como uma estratégia orientada a **Desenvolvimento**, pelas seguintes razões arquiteturais:

1. **Uso de Pastas Partilhadas (*Synced Folders*):** O nó `app` utiliza uma diretoria partilhada (`/vagrant_ca1`) diretamente mapeada para o código-fonte da máquina anfitriã (`CA1/part2`). Esta técnica viabiliza o desenvolvimento interativo e ciclos rápidos de teste, mas quebra a imutabilidade exigida em pipelines de CI/CD e ambientes de produção.
2. **Compilação e Resolução Dinâmica de Dependências em Arranque:** A aplicação é compilada e executada diretamente dentro da VM através do `./gradlew bootRun`. Em ambientes de CI/CD / Produção, a boa prática dita que os artefactos devem ser previamente compilados, testados e empacotados num ficheiro imutável (ex.: ficheiro `.jar` final ou imagem Docker/AMI pré-construída com Packer), garantindo determinismo e tempos de provisionamento imediatos.
3. **Persistência Local do H2:** O servidor H2 executa em ficheiro local no sistema de ficheiros da VM `db`. Em ambientes reais de produção/cloud, utilizam-se bases de dados geridas (ex.: AWS RDS) ou volumes externos desanexáveis com mecanismos avançados de replicação e backup.

Conclui-se, portanto, que este ambiente cumpre com excelência o propósito de um ambiente de desenvolvimento local multi-nó para testes de integração fiéis à arquitetura de produção.

---

## 6. Autoavaliação e Contribuição da Equipa

Em conformidade com os critérios de avaliação da unidade curricular, a distribuição percentual do esforço e contributo dos elementos da equipa foi a seguinte:

| Número Mecanográfico | Nome do Estudante | Contribuição (%) |
| :---: | :--- | :---: |
| 1260528 | Gonçalo Dinis Araújo | 50% |
| 1260483 | Pedro Barbosa | 50% |
