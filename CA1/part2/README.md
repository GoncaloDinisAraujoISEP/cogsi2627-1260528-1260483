# CA1 - Part 2: Converting Bookstore from Maven to Gradle

The Bookstore app (Spring Boot 3.3.0, Java 17, H2) was converted from Maven to Gradle, and four custom tasks were added: `deployToDev`, `runDist`, `javadocZip` and `integrationTest`. The full build script is in [`build.gradle`](build.gradle); this README walks through the steps and the key parts.

Original code: https://github.com/lmpnogueira/cogsi/tree/main/bookstore

## Prerequisites

Gradle 8.14.3 doesn't run on Java 25+, so `JAVA_HOME` must point to JDK 17:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
```

## 1. Create the project

```bash
gradle init --type java-application --dsl groovy
mv app/build.gradle . && rm -rf app
sed -i "/include('app')/d" settings.gradle          # single-module project, like the original
./gradlew wrapper --gradle-version 8.14.3           # Spring Boot 3.3.0 plugin doesn't support Gradle 9
cp -r /path/to/cogsi/bookstore/src .                # only the sources, no pom.xml or .git
rm -rf src/main/java/org src/test/java/org          # sample classes from init
```

In `settings.gradle`, set `rootProject.name = 'bookstore'` (used to name the jar and start scripts). Add a `.gitignore` with `.gradle/` and `build/`.

## 2. Dependencies and plugins

Dependencies and plugins are declared in [`gradle/libs.versions.toml`](gradle/libs.versions.toml). The libraries have no version: the `io.spring.dependency-management` plugin imports Spring Boot's BOM, which sets compatible versions for all of them (the role `spring-boot-starter-parent` had in Maven).

```groovy
plugins {
    id 'application'                                   // installDist; also applies the java plugin
    alias(libs.plugins.spring.boot)                    // bootRun, bootJar
    alias(libs.plugins.spring.dependency.management)   // Spring Boot BOM
}

java { toolchain { languageVersion = JavaLanguageVersion.of(17) } }

application { mainClass = 'com.example.bookstore.BookstoreApplication' }
```

## 3. Run

```bash
./gradlew bootRun
```

Open http://localhost:8080/books.

<img width="459" height="357" alt="image" src="https://github.com/user-attachments/assets/f9282130-8cd5-49a8-b925-c5cf513943c4" />

## 4. `deployToDev`

In `application.properties`, the version is replaced with placeholders:

```properties
service.version=@projectVersion@
service.build-timestamp=@buildTimestamp@
```

`deployToDev` groups four tasks:

| Task | Type | What it does |
|---|---|---|
| `cleanDeployDev` | `Delete` | empties `build/deployment/dev` |
| `copyAppToDev` | `Copy` | copies the `bootJar` output |
| `copyLibsToDev` | `Copy` | copies `runtimeClasspath` JARs to `lib/` (no test libraries) |
| `copyConfigToDev` | `Copy` | copies `*.properties`, replacing the placeholders with `ReplaceTokens` |

The `ReplaceTokens` filter is set inside `doFirst` so the timestamp is computed at execution time. With the configuration cache enabled (`gradle.properties`), it would otherwise be frozen in the cache.

```bash
./gradlew deployToDev
tree build/deployment/dev
cat build/deployment/dev/application.properties
```

<img width="459" height="713" alt="image" src="https://github.com/user-attachments/assets/35982bf0-f7b7-46ba-a5c2-d97e13688d0f" />
<img width="328" height="328" alt="image" src="https://github.com/user-attachments/assets/26b325eb-1387-468e-9b19-c3c1888a29e7" />

## 5. `runDist`

Depends on `installDist`, which generates `build/install/bookstore/` with the app libraries and two start scripts. The task runs `bookstore.bat` (through `cmd /c`) on Windows and `./bookstore` on other systems, based on the `os.name` property.

```bash
./gradlew runDist
```

<img width="410" height="330" alt="image" src="https://github.com/user-attachments/assets/cbf9115d-e81c-4100-9902-105158653487" />

## 6. `javadocZip`

Depends on `javadoc` and zips its output into `build/distributions`. The `javadoc` task keeps the original Maven settings (private members, don't fail on errors) and adds a title and links to the Java 17 API.

```bash
./gradlew javadocZip
ls build/distributions
```

<img width="798" height="37" alt="image" src="https://github.com/user-attachments/assets/2d56ca26-a08a-422d-90a9-89959bfd8768" />
<img width="928" height="461" alt="image" src="https://github.com/user-attachments/assets/4b3e042d-198f-474e-aa64-7bd1765ca49a" />

## 7. Integration tests

A separate `integrationTest` source set keeps the slower tests (which start the whole app) apart from the unit tests:

```groovy
sourceSets {
    integrationTest {
        compileClasspath += sourceSets.main.output   // access to the app classes
        runtimeClasspath += sourceSets.main.output
    }
}

configurations {
    integrationTestImplementation.extendsFrom testImplementation   // reuse JUnit, spring-boot-starter-test
    integrationTestRuntimeOnly.extendsFrom testRuntimeOnly
}

tasks.register('integrationTest', Test) {
    testClassesDirs = sourceSets.integrationTest.output.classesDirs
    classpath = sourceSets.integrationTest.runtimeClasspath
    shouldRunAfter 'test'
    useJUnitPlatform()
}

tasks.named('check') { dependsOn 'integrationTest' }   // ./gradlew build also runs them
```

The test, [`src/integrationTest/java/com/example/bookstore/BookApiIT.java`](src/integrationTest/java/com/example/bookstore/BookApiIT.java), starts the app on a random port and checks that `/books` returns `200 OK` with the seeded "Clean Code" book.

```bash
./gradlew integrationTest
```

<img width="917" height="530" alt="image" src="https://github.com/user-attachments/assets/4beb892e-0a46-499a-a9bd-11d0d030f7d7" />

## 8. Tag

```bash
git tag ca1-part2
git push origin ca1-part2
```

## Alternative to Gradle

### 1. Analysis

Maven was excluded (it was the original build). We also considered **Bazel** (too heavy for a single module) and **Mill** (little Spring Boot documentation), and chose **Ant + Ivy**: every requirement maps to a built-in Ant task, and it contrasts clearly with Gradle.

| Dimension | Gradle | Ant + Ivy |
| :--- | :--- | :--- |
| **Paradigm** | Declarative, convention-based DSL (Groovy/Kotlin) | Imperative XML (`build.xml`); every step declared by hand |
| **Dependencies** | Built in, transitive, with BOM support | Ivy add-on (`ivy.xml`); no BOM, so every version is explicit |
| **Extensibility** | Tasks (`Copy`, `Zip`, `Exec`) and plugins | `<target>`, `<macrodef>`, or Java classes extending `org.apache.tools.ant.Task` |
| **Performance** | Incremental builds, build cache, daemon, configuration cache | Only timestamp checks in tasks like `<javac>` and `<copy>` |
| **Spring Boot** | Official plugin (`bootRun`, `bootJar`) | None: plain jar + libraries on the classpath |

### 2. Design

| Goal | Gradle | Ant + Ivy |
| :--- | :--- | :--- |
| Dependencies | `libs.versions.toml` + BOM | `ivy.xml` with `compile`, `runtime`, `test` configurations |
| Run the app | `bootRun` | `<java fork="true">` |
| `deployToDev` | `Delete` + 3 `Copy`, `ReplaceTokens` | `<delete>` + 3 `<copy>`, `<filterset>` |
| `runDist` | `installDist` + `Exec` | `installDist` target with hand-written scripts + `<exec osfamily=...>` |
| `javadocZip` | `javadoc` + `Zip` | `<javadoc>` + `<zip>` |
| Integration tests | `integrationTest` source set + `Test` | separate `<javac>` + `<junitlauncher>` |

### 3. Implementation and reflection

Implemented in [`../part2-alternative`](../part2-alternative). Main differences from Gradle:

- **More is written by hand:** folders, classpaths and start scripts that Gradle's plugins provide by convention.
- **Dependency versions:** without the BOM, keeping versions compatible is our job.
- **Spring Boot:** without its plugin we had to add the `-parameters` compiler flag (for `@PathVariable`) and the manifest `Class-Path`; there's no fat jar.
- **Simpler in some places:** Ant re-reads the build on every run, so `<tstamp>` is always current, while Gradle's configuration cache forced the filter into `doFirst`.

## Self-assessment

| Member | No. | Contribution |
|---|---|---|
| Gonçalo Dinis Araújo | 1260528 | 50% |
| Pedro Barbosa | 1260483 | 50% |
