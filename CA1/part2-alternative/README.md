# CA1 part2 - Ant + Ivy Alternative Implementation

## 1. Dependency Management (`ivy.xml`)
- **Configurations (Scopes):** Replicates Maven scopes through hierarchic configurations: `compile`, `runtime` (extends `compile`), and `test` (extends `runtime`).
- **Explicit Versioning:** Manually specifies Spring Boot 3.3.0 dependencies, H2 (`2.2.224`), and JUnit Platform Launcher (`1.10.2`) due to the absence of native Spring Boot BOM support.

## 2. Build Lifecycle (`build.xml`)
- **Ivy Bootstrap:** Automatically downloads `ivy-2.5.2.jar` from Maven Central if absent and registers Ivy task definitions.
- **Resolution & Compilation:** The `resolve` target downloads artifacts into scoped folders (`lib/compile`, `lib/runtime`, `lib/test`). Compiles Java 17 code with `-parameters` flag retention for Spring routing.
- **Packaging & Execution:** Generates an executable JAR with a relative manifest `Class-Path` and provides an equivalent `run` target (`bootRun`) using `<java fork="true">`.

## 3. Four Custom Assignment Tasks
- **`deployToDev`:** Cleans `build/deployment/dev`, copies the application JAR, flattens runtime libraries into `lib/`, and injects `@projectVersion@` along with runtime `@buildTimestamp@` into `application.properties` via token filtering.
- **`runDist`:** Orchestrates the distribution packaging (`installDist`), assigns execution permissions (`chmod 755`), and detects the operating system to invoke either `bookstore.bat` (Windows) or `./bookstore` (Unix).
- **`javadocZip`:** Generates private-member API documentation linked to the Java 17 online documentation and packages it into `build/distributions/bookstore-1.0.0-javadoc.zip`.
- **`integrationTest`:** Compiles dedicated integration test sources (`src/integrationTest/java`) and executes `**/*IT.class` using the Ant `<junitlauncher>` task with console and XML reporting.
