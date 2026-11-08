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

Ambas as aplicações incluem um ficheiro `.dockerignore` nas respetivas pastas para evitar o envio desnecessário de artefactos pesados e ficheiros sensíveis durante o contexto de build (`docker build`):

* Exclusão de diretorias de build (`build/`, `.gradle/`, `target/`);

* Exclusão de ficheiros de ambiente e chaves locais (`.env`, `*.log`, `.git/` nos contextos locais);

* Redução direta do tempo de transferência de contexto para o daemon Docker.

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

Para analisar a eficácia da redução do tamanho e impacto da escolha de imagens de runtime:

```bash
docker images | grep -E "chat|bookstore"
```

| Imagem | Versão | Tamanho em Disco (DISK USAGE) | Tamanho de Conteúdo (CONTENT SIZE) | Análise de Eficiência e Superfície de Segurança |
| :--- | :--- | :--- | :--- | :--- |
| `chat:v1` | v1 | ~2.1GB | ~800MB | Ineficiente: Inclui JDK integral, Git, dependências de compilação e corre como `root`. |
| `chat:v2` | v2 | ~457MB | ~116MB | Otimizado: Imagem JRE minimalista. Depende do host para compilar. Corre como `root`. |
| `chat:v3` | v3 | ~461MB | ~118MB | **Recomendado:** Multi-stage build reprodutível, JRE e utilizador não-root (`appuser`, UID 10001). |
| `bookstore:v1` | v1 | ~1.38GB | ~492MB | Ineficiente: Histórico `.git`, dependências de build e JDK dentro da imagem. |
| `bookstore:v2` | v2 | ~525MB | ~156MB | Otimizado: JRE 17 com fat JAR Spring Boot pré-compilado. Corre como `root`. |
| `bookstore:v3` | v3 | ~525MB | ~156MB | **Recomendado:** Multi-stage build com Gradle, base JRE e utilizador desprivilegiado (`appuser`, UID 10001). |

<img width="1385" height="372" alt="image" src="https://github.com/user-attachments/assets/0d17f21a-81ca-4c54-9d83-f6ad04679aff" />

---

## 5. Procedimento de Versionamento no Git

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
