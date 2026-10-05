# CA1 part2 - Ant + Ivy Alternative Implementation

The original **Maven** build of Bookstore converted to **Apache Ant**, with **Apache Ivy** for dependencies. The analysis and comparison with Gradle are in the [Part 2 README](../part2/README.md).

## Prerequisites

```bash
sudo apt install ant ant-optional        # ant-optional provides <junitlauncher>
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

## Setup

From `CA1/`:

```bash
mkdir part2-alternative && cd part2-alternative
cp -r /path/to/cogsi/bookstore/src .              # original Maven sources, no pom.xml
cp -r ../part2/src/integrationTest src/           # same integration test as Part 2
```

In `src/main/resources/application.properties`, replace `service.version=1.0.0` with `@projectVersion@` and add `service.build-timestamp=@buildTimestamp@`.

## 1. Dependency Management (`ivy.xml`)
- **Configurations:** `compile`, `runtime` (extends `compile`) and `test` (extends `runtime`), mirroring Maven scopes.
- **Explicit versions:** Spring Boot 3.3.0, H2 `2.2.224` and JUnit Platform Launcher `1.10.2`, since Ivy doesn't read the Spring Boot BOM.

## 2. Build Lifecycle (`build.xml`)
- **Ivy bootstrap:** downloads `ivy-2.5.2.jar` into `.ivy/` if absent.
- **`resolve`:** retrieves dependencies into `lib/compile`, `lib/runtime` and `lib/test`.
- **`compile` / `jar`:** Java 17 with `-parameters` (needed for `@PathVariable`); the manifest `Class-Path` points to `lib/`, so the jar runs with `java -jar` next to a `lib/` folder.
- **`run`:** equivalent to `bootRun`, using `<java fork="true">`.

```bash
ant run          # http://localhost:8080/books
```

## 3. Custom Tasks

| Target | What it does |
|---|---|
| `deployToDev` | cleans `build/deployment/dev`, copies the jar, the runtime libraries to `lib/`, and `application.properties` with `@projectVersion@` and `@buildTimestamp@` replaced |
| `runDist` | depends on `installDist` (jar, libraries and start scripts from `src/dist/bin/` in `build/install/bookstore/`), then runs `bookstore.bat` via `cmd /c` on Windows or `bookstore` on Unix |
| `javadocZip` | generates the Javadoc (private members, Java 17 API links) and zips it into `build/distributions` |
| `integrationTest` | compiles `src/integrationTest/java` and runs `**/*IT.class` with `<junitlauncher>` in a forked JVM; reports in `build/reports/integrationTest` |

```bash
ant deployToDev
ant runDist
ant javadocZip
ant integrationTest
```
