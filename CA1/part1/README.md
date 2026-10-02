# CA1 Part 1 - Technical Report: Build Tools with Gradle

## 1. Overview & Team Evaluation
Relatório técnico relativo à Parte 1 do Assignment 1 (Build Tools). Implementação de automação de testes com JUnit 5, tarefas customizadas Gradle (`Copy`, `Zip`, `JavaExec`), provisionamento determinístico com Gradle Toolchains e ciclo de vida Git com tagging.

| Student Name | Student Number | Contribution (%) |
| :--- | :--- | :--- |
| Gonçalo Dinis Araújo | 1260528 | 100% |
| Pedro Barbosa | 1260483 | 100% |

---

## 2. Environment & Tooling Verification

### Gradle Wrapper & Java Toolchain
- **Gradle Wrapper (`./gradlew`):** Garante a execução da versão exata do Gradle especificada no projeto (`gradle-wrapper.properties`), dispensando instalação prévia no sistema anfitrião.
- **Java Toolchain:** Configurado no `build.gradle` para Java 21. Desacopla o JDK de compilação da JVM do sistema operativo através de auto-detecção e auto-download.

```bash
./gradlew javaToolchains
```

**Output obtido & Análise:**
```text
+ Ubuntu JDK 17 (17.0.20.1+1-1-26.04-Ubuntu)
  | Location:         /usr/lib/jvm/java-17-openjdk-amd64
  | Detected by:      Current JVM

+ Eclipse Temurin JDK 21 (21.0.12.1+1-LTS)
  | Location:         /home/dinis/.gradle/jdks/eclipse_adoptium-21-amd64-linux.2
  | Detected by:      Auto-provisioned by Gradle
```
*Análise:* Apesar de a JVM do sistema ser a versão 17, o Gradle detetou a exigência da versão 21 no build script e descarregou automaticamente o *Eclipse Temurin JDK 21*, garantindo builds reprodutíveis e independentes do ambiente anfitrião.

---

## 3. Git Workflow & Version Control
1. **Repositório Inicial:** Importado e marcado com tag inicial:
   ```bash
   git tag v1.1.0
   git push origin v1.1.0
   ```
2. **Branch de Trabalho:** Isolamento do desenvolvimento na branch `ca1-part1-tasks`:
   ```bash
   git checkout -b ca1-part1-tasks
   ```
3. **Commit de Implementação:** Commits atómicos e descritivos com implementação das tarefas, testes e build script (`feat(ca1): add runServer, backup tasks and unit test configuration`).
4. **Merge & Milestone Tagging:** Integração na `main` e criação das tags de entrega e versão:
   ```bash
   git checkout main
   git merge ca1-part1-tasks
   git tag v1.2.0
   git tag ca1-part1
   git push origin main --tags
   ```

---

## 4. Implementation Details

### 4.1. Unit Testing (JUnit 5)
Configuração no `app/build.gradle`:
```groovy
dependencies {
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.0'
    testRuntimeOnly 'org.junit.platform:junit-platform-launcher'
}

tasks.named('test') {
    useJUnitPlatform()
}
```
Teste de verificação implementado em `app/src/test/java/org/example/AppTest.java` com assertions JUnit 5 (`assertNotNull`).

### 4.2. Custom Gradle Tasks (`app/build.gradle`)
Tarefas integradas no grupo `DevOps`:

- **`runServer` (`JavaExec`):** Executa `org.example.ChatServerApp`. Suporta porto dinâmico via propriedade `serverPort` (default: 59001):
  ```groovy
  tasks.register('runServer', JavaExec) {
      group = 'DevOps'
      description = 'Executa o servidor de chat'
      classpath = sourceSets.main.runtimeClasspath
      mainClass = 'org.example.ChatServerApp'
      args = [findProperty('serverPort') ?: '59001']
  }
  ```

- **`backupSources` (`Copy`):** Copia exclusivamente os diretórios de código-fonte (`src`) para `build/backup`:
  ```groovy
  tasks.register('backupSources', Copy) {
      group = 'DevOps'
      description = 'Copia o codigo-fonte para pasta de backup'
      from 'src'
      into layout.buildDirectory.dir('backup')
  }
  ```

- **`zipBackup` (`Zip`):** Cria um ficheiro zip a partir da pasta gerada pela tarefa anterior, com dependência explícita declarada:
  ```groovy
  tasks.register('zipBackup', Zip) {
      group = 'DevOps'
      description = 'Comprime o backup do codigo-fonte'
      dependsOn 'backupSources'
      from layout.buildDirectory.dir('backup')
      archiveFileName = 'sources-backup.zip'
      destinationDirectory = layout.buildDirectory.dir('distributions')
  }
  ```

---

## 5. Execution & Verification Guide

Execute os seguintes comandos para reproduzir e validar a solução:

```bash
# Executar a suite de testes unitários
./gradlew test

# Executar o servidor (porta por omissão 59001)
./gradlew runServer

# Executar o servidor com porta customizada
./gradlew runServer -PserverPort=59002

# Gerar o arquivo zip de backup dos fontes (executa automaticamente backupSources)
./gradlew zipBackup

# Verificar JDKs e toolchains ativas
./gradlew javaToolchains
```
