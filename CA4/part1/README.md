# CA4 Part 1 - Containerization with Docker: Tutorial & Technical Report

## 1. Overview & Project Structure

Este guia documenta o processo prático de contentorização das aplicações **Chat Server** e **Bookstore**, cobrindo a evolução iterativa das imagens através de três estratégias distintas de empacotamento:
- **v1:** Build executado dentro do próprio contentor (instalação de dependências, clone do repositório Git e compilação interna com JDK).
- **v2:** Criação de imagens de runtime leves a partir de artefactos previamente compilados no host de desenvolvimento (utilizando JRE e executando como binário empacotado).
- **v3:** Multi-stage build com segregação de privilégios (`appuser`, UID `10001`) para minimização de superfície de ataque e otimização de camadas.

### Estrutura de Diretórios da Parte 1
```text
CA4/part1/
├── chat/
│   ├── app/
│   │   ├── build.gradle
│   │   └── src/
│   ├── Dockerfile.v1
│   ├── Dockerfile.v2
│   ├── Dockerfile.v3
│   ├── gradlew
│   └── settings.gradle
└── bookstore/
    ├── src/
    ├── Dockerfile.v1
    ├── Dockerfile.v2
    ├── Dockerfile.v3
    ├── build.gradle
    ├── gradlew
    └── settings.gradle
```

### Configuração de Isolamento (.dockerignore)

O ficheiro `.dockerignore` funciona como o `.gitignore`: indica ao Docker o que **não deve enviar** para o contexto de build (`docker build`), reduzindo o seu tamanho e evitando incluir ficheiros locais ou sensíveis.

* **Chat Server (`CA4/part1/chat/.dockerignore`):**
  * Ignora o histórico Git (`.git`), caches locais do Gradle (`.gradle`), pastas de IDE (`bin`, `out`) e ficheiros de registo (`*.log`).
  * Mantém a regra `!**/build/libs/*.jar` de forma defensiva, para garantir que o JAR compilado no host está disponível para o `COPY` da `v2`.

* **Bookstore (`CA4/part1/bookstore/.dockerignore`):**
  * Ignora `.git`, `.gradle`, `out`, `*.log` e todo o conteúdo de `build/` (`build/*`).
  * Abre a exceção `!build/libs/*.jar`, deixando passar apenas o JAR gerado pelo `bootJar`, que é o ficheiro de que a `v2` precisa.

> **Nota:** na Bookstore, a exceção `!` permite à `v2` copiar o JAR mesmo com `build/*` excluído, e mantém fora do contexto as classes e relatórios intermédios. Na `v3` (*multi-stage*), o `COPY . .` do estágio `builder` também respeita o `.dockerignore`, pelo que os ficheiros excluídos não entram no estágio de compilação.

---

## 2. Aplicação 1: Chat Server (Java 21)

A aplicação Chat Server corre sobre Java 21, expõe a porta de rede `59001` e executa a classe principal `org.example.ChatServerApp`.

---

### Versão 1: Build no Contentor com Git Clone (`Dockerfile.v1`)

Nesta abordagem inicial, uma imagem completa com JDK descarrega as ferramentas do sistema, clona o repositório e compila o código no interior do contentor durante o build.

#### Ficheiro `CA4/part1/chat/Dockerfile.v1`
```dockerfile
FROM eclipse-temurin:17-jdk

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN git clone https://github.com/lmpnogueira/cogsi.git .
WORKDIR /app/build_tools/gradle_demo

RUN ./gradlew build --no-daemon

EXPOSE 59001
CMD ["./gradlew", "runServer", "--no-daemon"]
```

#### Passos de Execução:
1. **Construir a imagem a partir do contexto da aplicação:**
   ```bash
   docker build -f CA4/part1/chat/Dockerfile.v1 -t chat:v1 CA4/part1/chat
   ```

2. **Arrancar o contentor em background expondo a porta `59001`:**
   ```bash
   docker run -d --name chat-v1-app -p 59001:59001 chat:v1
   ```

3. **Verificar o estado ativo do contentor:**
   ```bash
   docker ps
   ```

4. **Parar e remover o contentor de teste:**
   ```bash
   docker stop chat-v1-app && docker rm chat-v1-app
   ```

<img width="1442" height="595" alt="image" src="https://github.com/user-attachments/assets/fd7c0a13-7278-48d8-9754-960affdbb522" />


---

### Versão 2: Utilização de Artefacto Previamente Compilado (`Dockerfile.v2`)

Nesta variante, a compilação ocorre no host via Gradle local. Apenas o ficheiro JAR final é transferido para uma imagem minimalista de execução baseada em JRE (`eclipse-temurin:21-jre`).

#### Ficheiro `CA4/part1/chat/Dockerfile.v2`
```dockerfile
FROM eclipse-temurin:21-jre

WORKDIR /app
COPY app/build/libs/*.jar app.jar

EXPOSE 59001
CMD ["java", "-cp", "app.jar", "org.example.ChatServerApp", "59001"]
```

#### Passos de Execução:
1. **Compilar os artefactos no host utilizando o Gradle Wrapper:**
   ```bash
   cd CA4/part1/chat
   ./gradlew :app:build --no-daemon
   cd ../../..
   ```

2. **Construir a imagem Docker v2:**
   ```bash
   docker build -f CA4/part1/chat/Dockerfile.v2 -t chat:v2 CA4/part1/chat
   ```

3. **Arrancar o contentor e validar:**
   ```bash
   docker run -d --name chat-v2-app -p 59001:59001 chat:v2
   docker ps
   ```

4. **Parar e remover:**
   ```bash
   docker stop chat-v2-app && docker rm chat-v2-app
   ```

<img width="1430" height="721" alt="image" src="https://github.com/user-attachments/assets/82205ef3-e652-4c9e-a7ce-93862fcd1825" />


---

### Versão 3: Multi-Stage Build e Utilizador Não-Root (`Dockerfile.v3`)

O estágio de compilação (`builder`) utiliza a imagem Gradle oficial com JDK 21 para compilar e montar a distribuição da aplicação (`installDist`). A imagem final utiliza apenas o JRE 21, cria um utilizador dedicado sem privilégios administrativos (`appuser`, UID `10001`), ajusta a posse dos ficheiros (`chown`) e corre o processo com segurança reforçada.

#### Ficheiro `CA4/part1/chat/Dockerfile.v3`
```dockerfile
FROM gradle:jdk21 AS builder
WORKDIR /workspace
COPY . .
RUN ./gradlew :app:installDist --no-daemon

FROM eclipse-temurin:21-jre
WORKDIR /app

RUN useradd -u 10001 appuser && chown -R appuser:appuser /app

COPY --from=builder --chown=appuser:appuser /workspace/app/build/install/app /app

USER 10001

EXPOSE 59001
CMD ["java", "-cp", "lib/*", "org.example.ChatServerApp", "59001"]
```

#### Passos de Execução:
1. **Construir a imagem via multi-stage:**
   ```bash
   docker build -f CA4/part1/chat/Dockerfile.v3 -t chat:v3 CA4/part1/chat
   ```

2. **Executar o contentor:**
   ```bash
   docker run -d --name chat-v3-app -p 59001:59001 chat:v3
   ```

3. **Validar execução sob UID não-privilegiado (10001) e métricas de consumo:**
   ```bash
   docker top chat-v3-app
   docker stats chat-v3-app --no-stream
   ```

4. **Limpar:**
   ```bash
   docker stop chat-v3-app && docker rm chat-v3-app
   ```

<img width="1447" height="147" alt="image" src="https://github.com/user-attachments/assets/7baa1239-f755-4438-8661-0ba58f919bfd" />


---

## 3. Aplicação 2: Bookstore (Spring Boot / Java 17)

A Bookstore é uma aplicação Spring Boot 3 que opera com Java 17 na porta HTTP `8080`.

> **Nota de Segurança e Arquitetura (Injeção de Configurações):**
> Para permitir que a aplicação execute em modo autónomo (stand-alone) na Parte 1 sem depender da infraestrutura de VMs legada (CA2/CA3), as variáveis de base de dados H2 em memória são injetadas dinamicamente em runtime através das flags `-e`.
> Esta abordagem cumpre os princípios de *least privilege* e defesa em profundidade, evitando a instrução `ENV` no Dockerfile que deixaria credenciais estáticas gravadas permanentemente nas camadas públicas da imagem (`docker history`) ao publicar no Docker Hub.

---

### Versão 1: Clone do Repositório e Compilação (`Dockerfile.v1`)

#### Ficheiro `CA4/part1/bookstore/Dockerfile.v1`
```dockerfile
FROM eclipse-temurin:17-jdk

RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY .git /tmp/repo/.git
RUN git clone /tmp/repo/.git . && rm -rf /tmp/repo
WORKDIR /app/CA1/part2

RUN chmod +x gradlew && ./gradlew bootJar --no-daemon

EXPOSE 8080
CMD ["java", "-jar", "build/libs/bookstore-1.0.0.jar"]
```

#### Passos de Execução:
1. **Construir a imagem a partir da raiz do repositório:**
   ```bash
   docker build -f CA4/part1/bookstore/Dockerfile.v1 -t bookstore:v1 .
   ```

2. **Arrancar o contentor com as variáveis de inicialização da base de dados H2:**

   ```
   docker run -d --name bookstore-v1-app -p 8080:8080 \
     -e SPRING_DATASOURCE_URL="jdbc:h2:mem:bookstoredb;DB_CLOSE_DELAY=-1" \
     -e SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.h2.Driver" \
     -e SPRING_DATASOURCE_USERNAME="sa" \
     -e SPRING_DATASOURCE_PASSWORD="" \
     -e SPRING_JPA_DATABASE_PLATFORM="org.hibernate.dialect.H2Dialect" \
     bookstore:v1
   
   ```

3. **Aguardar a inicialização e verificar o estado e o endpoint HTTP:**

   ```
   sleep 8
   docker ps
   curl -I http://localhost:8080
   
   ```

4. **Limpar:**

   ```
   docker stop bookstore-v1-app && docker rm bookstore-v1-app
   
   ```

<img width="1412" height="237" alt="image" src="https://github.com/user-attachments/assets/c9fdaf37-eb9c-472d-8702-264c06154798" />



---

### Versão 2: Imagem Baseada no `bootJar` Compilado no Host (`Dockerfile.v2`)

#### Ficheiro `CA4/part1/bookstore/Dockerfile.v2`
```dockerfile
FROM eclipse-temurin:17-jre

WORKDIR /app
COPY build/libs/*.jar app.jar

EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

#### Passos de Execução:

1. **Gerar o pacote executável no ambiente do anfitrião:**

   ```
   cd CA4/part1/bookstore
   ./gradlew bootJar --no-daemon
   cd ../../..
   
   ```

2. **Construir a imagem com o JRE 17:**

   ```
   docker build -f CA4/part1/bookstore/Dockerfile.v2 -t bookstore:v2 CA4/part1/bookstore
   
   ```

3. **Arrancar o contentor com as variáveis de base de dados e validar:**

   ```
   docker run -d --name bookstore-v2-app -p 8080:8080 \
     -e SPRING_DATASOURCE_URL="jdbc:h2:mem:bookstoredb;DB_CLOSE_DELAY=-1" \
     -e SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.h2.Driver" \
     -e SPRING_DATASOURCE_USERNAME="sa" \
     -e SPRING_DATASOURCE_PASSWORD="" \
     -e SPRING_JPA_DATABASE_PLATFORM="org.hibernate.dialect.H2Dialect" \
     bookstore:v2
   
   sleep 8
   docker ps
   curl -I http://localhost:8080
   
   ```

4. **Limpar:**

   ```
   docker stop bookstore-v2-app && docker rm bookstore-v2-app
   
   ```
<img width="1218" height="176" alt="image" src="https://github.com/user-attachments/assets/194fd616-236c-4f60-9b9f-6c619d326ea8" />
<img width="1451" height="67" alt="image" src="https://github.com/user-attachments/assets/b64b97b1-3bab-4124-8d38-827087920ed5" />
<img width="1045" height="113" alt="image" src="https://github.com/user-attachments/assets/a2bbe72d-ec40-4ddd-92ca-269df1d599fd" />


---

### Versão 3: Multi-Stage Build e Execução com UID 10001 (`Dockerfile.v3`)

#### Ficheiro `CA4/part1/bookstore/Dockerfile.v3`
```dockerfile
FROM gradle:8-jdk17 AS builder
WORKDIR /workspace
COPY . .
RUN ./gradlew bootJar --no-daemon

FROM eclipse-temurin:17-jre
WORKDIR /app

RUN useradd -u 10001 appuser && chown -R appuser:appuser /app
COPY --from=builder --chown=appuser:appuser /workspace/build/libs/*.jar app.jar

USER 10001

EXPOSE 8080
CMD ["java", "-jar", "app.jar"]
```

#### Passos de Execução:

1. **Construir a imagem segura via multi-stage:**

   ```
   docker build -f CA4/part1/bookstore/Dockerfile.v3 -t bookstore:v3 CA4/part1/bookstore
   
   ```

2. **Executar o contentor com as variáveis da base de dados:**

   ```
   docker run -d --name bookstore-v3-app -p 8080:8080 \
     -e SPRING_DATASOURCE_URL="jdbc:h2:mem:bookstoredb;DB_CLOSE_DELAY=-1" \
     -e SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.h2.Driver" \
     -e SPRING_DATASOURCE_USERNAME="sa" \
     -e SPRING_DATASOURCE_PASSWORD="" \
     -e SPRING_JPA_DATABASE_PLATFORM="org.hibernate.dialect.H2Dialect" \
     bookstore:v3
   
   ```

3. **Verificar os dados servidos e os privilégios do processo:**

   ```
   sleep 8
   curl -I http://localhost:8080
   docker top bookstore-v3-app
   docker run --rm bookstore:v3 id
   
   ```

4. **Limpar:**

   ```
   docker stop bookstore-v3-app && docker rm bookstore-v3-app
   
   ```


<img width="1440" height="716" alt="image" src="https://github.com/user-attachments/assets/852c902c-be76-41e1-adcc-2aa1c5cb6873" />


---


## 4. Comparação e Métricas das Imagens

Para avaliar o impacto prático de cada estratégia de empacotamento, foram analisadas três variáveis fundamentais: **tempo de compilação sem cache (`--no-cache`)**, **contagem de camadas no histórico (`docker history`)** e **tamanho ocupado em disco (`docker images`)**.

### Tabela Comparativa de Métricas

| Aplicação | Versão | Estratégia de Build | Tempo de Build (`real`) | Camadas (`docker history`) | Tamanho em Disco | Build Tools na Imagem Final? | Execução Non-Root? |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Chat Server** | `v1` | Monolítico (Clone + compilação interna) | 1m 39.04s | 24 | 2.10 GB | Sim (JDK, Gradle, Git, caches) | Não (`root`) |
| **Chat Server** | `v2` | Host Build + JRE Runtime | 20.04s | 20 | 457 MB | Não (Apenas JRE base) | Não (`root`) |
| **Chat Server** | `v3` | Multi-Stage Build + Non-Root | 36.41s | 22 | 461 MB | Não (Isoladas no builder) | Sim (`appuser` / `10001`) |
| **Bookstore** | `v1` | Monolítico (Compilação interna via Gradle) | 1m 21.44s | 25 | 1.39 GB | Sim (JDK, Gradle, caches) | Não (`root`) |
| **Bookstore** | `v2` | Host Build + JRE Runtime | 17.62s | 20 | 525 MB | Não (Apenas JRE base) | Não (`root`) |
| **Bookstore** | `v3` | Multi-Stage Build + Non-Root | 1m 03.03s | 22 | 525 MB | Não (Isoladas no builder) | Sim (`appuser` / `10001`) |

#### Justificação Técnica dos Resultados:
1. **Redução da Pegada em Disco:**
   * A versão `v1` inclui o ecossistema completo de desenvolvimento (`git`, SDKs e diretórios de cache), resultando em imagens de tamanho excessivo (1.39 GB e 2.10 GB).
   * A transição para bases minimalistas focadas exclusivamente no runtime (`eclipse-temurin:17-jre` e `21-jre`) nas versões `v2` e `v3` gerou uma poupança imediata superior a 70% do espaço ocupado em disco.

2. **Duração do Processo de Build vs. Portabilidade:**
   * A versão `v2` apresenta o menor tempo de build (~17s a 20s), dado que o Docker se limita a executar a instrução `COPY` do binário já compilado no anfitrião. Contudo, quebra o isolamento ao exigir que o ambiente local tenha o JDK e Gradle configurados de raiz.
   * A versão `v3` (*multi-stage build*) equilibra tempo e reprodutibilidade: o processo de build corre de forma estanque no estágio transitório (`builder`), copiando unicamente o artefacto estritamente necessário para a imagem final de entrega.

3. **Análise de Camadas (`docker history`):**
   * A contagem de camadas inclui metadados (`ENV`, `WORKDIR`, `EXPOSE`) e a hierarquia herdada da imagem base oficial.
   * A versão `v3` regista 22 camadas (em contraste com as 20 camadas da `v2`) em consequência direta do endurecimento de segurança: a instrução de criação do utilizador local de sistema (`RUN useradd`) e a diretiva de execução desprivilegiada (`USER 10001`).

---


### 4.1 Inspeção Detalhada de Camadas (`docker history`)

A inspeção detalhada das camadas evidencia de forma prática o desperdício de espaço no modelo tradicional face ao desacoplamento obtido no modelo *multi-stage*:

#### Camadas da Versão v1 (Monolítica):
Observa-se que apenas a instrução `./gradlew build` introduz 738 MB de dependências e artefactos desnecessários na imagem final:

<!-- COLOCA AQUI O TEU PRINT DO COMANDO "docker history chat:v1" (onde se vê a linha dos 738MB) -->
![Docker History Chat v1](docs/screenshots/docker-history-chat-v1.png)

#### Camadas da Versão v3 (Multi-Stage):
No estágio final, a camada que transporta a aplicação (`COPY --from=builder`) ocupa apenas 2.31 MB, sendo executada com restrições explícitas de utilizador (`USER 10001`):

<!-- COLOCA AQUI O TEU PRINT DO COMANDO "docker history chat:v3" (onde se vê a linha dos 2.31MB e USER 10001) -->
![Docker History Chat v3](docs/screenshots/docker-history-chat-v3.png)

---

### 4.2 Prova de Isolamento e Comunicação Host-Container

Para comprovar que o contentor executa de forma autónoma e responde a pedidos originados a partir do exterior (sistema operativo anfitrião), o serviço `chat:v3` foi instanciado mapeando a porta de socket `59001`:

1. O contentor foi iniciado em segundo plano com redirecionamento de porta:
   ```bash
   docker run -d --name chat-test -p 59001:59001 chat:v3
   ```
2. A partir do anfitrião, foi executado o cliente gráfico Java Swing:
   ```bash
   cd CA4/part1/chat && ./gradlew :app:runClient
   ```
3. Foram enviadas mensagens interativas pela aplicação, validando o ciclo de processamento do servidor dentro do contentor.

<!-- COLOCA AQUI O TEU PRINT QUE TEM A JANELA "Chatter - Gonclao" E A TABELA docker stats POR TRÁS -->
![Evidência de Execução e Monitorização](docs/screenshots/chat-client-stats.png)

* **Monitorização em Tempo Real (`docker stats`):**
  Como evidenciado na captura, o contentor opera com estabilidade e consumo de memória contido (~56.59 MiB), sendo a comunicação bidirecional confirmada pelo tráfego contínuo na interface de rede (`NET I/O: 2.04kB / 804B`).

---

## 5. Publicação e Utilização no Docker Hub

As imagens de produção (`v1`, `v2` e `v3`) foram etiquetadas e enviadas para o registo público oficial no Docker Hub sob o utilizador `goncalodinisaraujoisep`.

### 5.1 Procedimento de Publicação (Tag & Push)
Para publicar as imagens construídas localmente no Docker Hub:

```bash
# 1. Autenticação no Docker Hub
docker login

# 2. Atribuir a tag com o namespace do repositório remoto
docker tag chat:v1 goncalodinisaraujoisep/chat-server:v1
docker tag chat:v2 goncalodinisaraujoisep/chat-server:v2
docker tag chat:v3 goncalodinisaraujoisep/chat-server:v3

docker tag bookstore:v1 goncalodinisaraujoisep/bookstore:v1
docker tag bookstore:v2 goncalodinisaraujoisep/bookstore:v2
docker tag bookstore:v3 goncalodinisaraujoisep/bookstore:v3

# 3. Enviar as imagens para o repositório público
docker push goncalodinisaraujoisep/chat-server:v1
docker push goncalodinisaraujoisep/chat-server:v2
docker push goncalodinisaraujoisep/chat-server:v3

docker push goncalodinisaraujoisep/bookstore:v1
docker push goncalodinisaraujoisep/bookstore:v2
docker push goncalodinisaraujoisep/bookstore:v3
```

### 5.2 Como Obter e Executar (Fetch & Run)
Qualquer utilizador externo ou avaliador pode descarregar e executar as imagens finais a partir do Docker Hub sem necessitar do código-fonte ou de ambientes Java/Gradle instalados no host:

* **Executar o Chat Server (v3):**
  ```bash
  docker pull goncalodinisaraujoisep/chat-server:v3
  docker run -d --name chat-server -p 59001:59001 goncalodinisaraujoisep/chat-server:v3
  ```

* **Executar a Bookstore (v3 com injeção de parâmetros H2):**
  ```bash
  docker pull goncalodinisaraujoisep/bookstore:v3
  docker run -d --name bookstore-app -p 8080:8080 \
    -e SPRING_DATASOURCE_URL="jdbc:h2:mem:bookstoredb;DB_CLOSE_DELAY=-1" \
    -e SPRING_DATASOURCE_DRIVER_CLASS_NAME="org.h2.Driver" \
    -e SPRING_DATASOURCE_USERNAME="sa" \
    -e SPRING_DATASOURCE_PASSWORD="" \
    -e SPRING_JPA_DATABASE_PLATFORM="org.hibernate.dialect.H2Dialect" \
    goncalodinisaraujoisep/bookstore:v3
  ```

---



## 6. Procedimento de Versionamento no Git

Após validação de todos os passos, a entrega da Parte 1 é concluída na branch dedicada com a respetiva tag:

```bash
# 1. Registar as alterações da documentação e ficheiros de configuração
git add CA4/part1/
git commit -m "docs(ca4-part1): complete technical tutorial and containerization report"

# 2. Enviar a branch ca4-part1 para o repositório remoto
git push origin refs/heads/ca4-part1

# 3. Criar e sincronizar a tag ca4-part1
git tag -f ca4-part1
git push origin refs/tags/ca4-part1 -f
```
