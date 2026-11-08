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

> **[INSERIR PRINT AQUI: Build da imagem `chat:v1`, arranque e verificação com `docker ps`]**

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

> **[INSERIR PRINT AQUI: Execução do build local do Gradle, `docker build` e contentor `chat:v2` a correr]**

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

> **[INSERIR PRINT AQUI: Saída do comando `docker top` (mostrando UID 10001) e `docker stats` da imagem `chat:v3`]**

---

## 3. Aplicação 2: Bookstore (Spring Boot / Java 17)

A Bookstore é uma aplicação Spring Boot 3 que opera com Java 17 na porta HTTP `8080`.

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
CMD ["java", "-jar", "build/libs/bookstore-0.0.1-SNAPSHOT.jar"]
```

#### Passos de Execução:
1. **Construir a imagem a partir da raiz do repositório:**
   ```bash
   docker build -f CA4/part1/bookstore/Dockerfile.v1 -t bookstore:v1 .
   ```

2. **Arrancar o contentor:**
   ```bash
   docker run -d --name bookstore-v1-app -p 8080:8080 bookstore:v1
   docker ps
   ```

3. **Verificar resposta HTTP no endpoint da aplicação:**
   ```bash
   curl -I http://localhost:8080/books
   ```

4. **Limpar:**
   ```bash
   docker stop bookstore-v1-app && docker rm bookstore-v1-app
   ```

> **[INSERIR PRINT AQUI: Build, arranque do contentor `bookstore:v1` e teste via `curl`]**

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
   ```bash
   cd CA4/part1/bookstore
   ./gradlew bootJar --no-daemon
   cd ../../..
   ```

2. **Construir a imagem com o JRE 17:**
   ```bash
   docker build -f CA4/part1/bookstore/Dockerfile.v2 -t bookstore:v2 CA4/part1/bookstore
   ```

3. **Arrancar e validar endpoint:**
   ```bash
   docker run -d --name bookstore-v2-app -p 8080:8080 bookstore:v2
   curl -I http://localhost:8080/books
   ```

4. **Limpar:**
   ```bash
   docker stop bookstore-v2-app && docker rm bookstore-v2-app
   ```

> **[INSERIR PRINT AQUI: Execução do comando `bootJar` e resposta HTTP do `bookstore:v2`]**

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
   ```bash
   docker build -f CA4/part1/bookstore/Dockerfile.v3 -t bookstore:v3 CA4/part1/bookstore
   ```

2. **Executar o contentor:**
   ```bash
   docker run -d --name bookstore-v3-app -p 8080:8080 bookstore:v3
   ```

3. **Verificar os dados servidos e os privilégios do processo:**
   ```bash
   curl -s http://localhost:8080/books | head -n 15
   docker top bookstore-v3-app
   ```

4. **Limpar:**
   ```bash
   docker stop bookstore-v3-app && docker rm bookstore-v3-app
   ```

> **[INSERIR PRINT AQUI: Resposta JSON obtida via `curl` e processo com UID 10001 demonstrado no `docker top`]**

---

## 4. Comparação e Métricas das Imagens

Para analisar a eficácia da redução do tamanho e impacto da escolha de imagens de runtime:

```bash
docker images | grep -E "chat|bookstore"
```

| Imagem | Versão | Tamanho Aproximado | Análise de Eficiência e Segurança |
| :--- | :--- | :--- | :--- |
| `chat:v1` | v1 | ~950MB - 1.1GB | Ineficiente: Inclui JDK integral, Git, ficheiros temporários do sistema operativo e corre com permissões de `root`. |
| `chat:v2` | v2 | ~300MB - 350MB | Eficiente em espaço (JRE). Depende da máquina de build do host para gerar o JAR. Corre como `root`. |
| `chat:v3` | v3 | ~300MB - 350MB | **Abordagem recomendada:** Build reprodutível e isolado (multi-stage), runtime mínima (JRE) e sem permissões de root (`appuser`, UID 10001). |
| `bookstore:v1` | v1 | ~900MB - 1GB | Ineficiente: Camada de clone do Git e cadeia completa de compilação em JDK. |
| `bookstore:v2` | v2 | ~280MB - 320MB | Redução substancial empacotando apenas o fat JAR Spring Boot sobre JRE 17. |
| `bookstore:v3` | v3 | ~280MB - 320MB | **Abordagem recomendada:** Construção multi-stage com Gradle e Spring Boot executando em ambiente não-privilegiado. |

> **[INSERIR PRINT AQUI: Listagem comparativa de imagens com `docker images`]**

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