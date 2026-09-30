# CA1 - Part 2: Moving the Bookstore application from Maven to Gradle

## 1. What we did

Bookstore is a REST API built with Spring Boot 3.3.0 (Java 17). It manages books, clients and orders, and keeps everything in an in-memory H2 database. It was originally built with **Maven**. In this part, we moved the build to **Gradle** and added four tasks of our own:

| Task | What it does |
|---|---|
| `deployToDev` | prepares a ready-to-install folder with the application, the libraries it needs and its configuration |
| `runDist` | starts the application using the launch scripts Gradle generates, picking the right script for Linux or Windows |
| `javadocZip` | generates the code documentation (Javadoc) and puts it in a zip |
| `integrationTest` | runs integration tests, which live in a folder separate from the regular tests |

Original code: https://github.com/lmpnogueira/cogsi/tree/main/bookstore

### A few concepts before we start

For readers who don't deal with this every day:

- **Build tool** (Maven, Gradle): the program that turns source code into an application you can run. It compiles the code, downloads external libraries, runs the tests and packages everything into a `.jar` file.
- **Dependency**: a library written by someone else that our code uses (Spring, for example). Instead of storing it in the repository, we tell Gradle its name and version, and Gradle downloads it from the internet (from Maven Central).
- **Task**: an action Gradle knows how to perform, such as `compileJava`, `test` or `bootRun`. A task can depend on others. For example, before running the application, Gradle compiles it.
- **Plugin**: a package that adds tasks and configuration to Gradle. The Spring Boot plugin, for instance, is what provides the `bootRun` task.

---

## 2. Creating the Gradle project

### 2.1 Generating the skeleton with `gradle init`

In an empty folder, `CA1/part2`, we ran:

```bash
gradle init --type java-application --dsl groovy
```

`gradle init` creates a sample project with Gradle's typical structure: `build.gradle` (where the build is described), `settings.gradle` (project name), the version catalog and the **Gradle Wrapper** (`gradlew`).

The wrapper is a small script that ships with the project. When someone runs `./gradlew`, the script downloads the exact Gradle version the project needs. Nobody has to install Gradle by hand, and everyone uses the same version.

`init` puts the code inside an `app/` subfolder. Since the original application is a single project, we moved everything up to the root folder:

```bash
mv app/build.gradle .
rm -rf app
sed -i "/include('app')/d" settings.gradle
```

We also changed the project name in `settings.gradle`, because Gradle uses that name for the files it generates (`bookstore-1.0.0.jar`, the `bookstore` script, and so on):

```groovy
rootProject.name = 'bookstore'
```

The generated `settings.gradle` also includes the `foojay-resolver-convention` plugin. We kept it because it lets Gradle download JDK 17 automatically if it isn't installed on the machine (see section 3.3).

### 2.2 Bringing in the application code

From the original repository we copied only the `src` folder. The `pom.xml` (Maven's build file) is no longer needed, and `.git` is left out so the two histories don't get mixed.

```bash
cp -r /path/to/cogsi/bookstore/src .
```

We also deleted the sample classes `init` had created (`App.java` and `AppTest.java`).

Finally, we added a `.gitignore` so the folders Gradle generates don't end up in the repository. `build/` holds the compilation output and `.gradle/` is Gradle's internal cache. Both are recreated on every machine, so there's no point in storing them. The wrapper, on the other hand, must be in the repository, because it's what guarantees everyone uses the same Gradle version:

```gitignore
# Local Gradle cache
.gradle/
# Build output
build/

# Make sure the wrapper is tracked
!gradlew
!gradlew.bat
!gradle/wrapper/gradle-wrapper.jar
!gradle/wrapper/gradle-wrapper.properties
```

Final structure:

```
CA1/part2/
├── .gitignore
├── build.gradle            - build description
├── settings.gradle         - project name
├── gradle.properties
├── gradlew / gradlew.bat   - wrapper (Linux / Windows)
├── gradle/
│   ├── libs.versions.toml  - version catalog
│   └── wrapper/
└── src/
    ├── main/               - application code
    ├── test/               - unit tests
    └── integrationTest/    - integration tests
```

---

## 3. Dependencies and plugins

### 3.1 From `pom.xml` to `build.gradle`

Maven and Gradle use different names for the same things. The table shows how they map:

| In Maven (`pom.xml`) | In Gradle | What it's for |
|---|---|---|
| `spring-boot-starter-parent` 3.3.0 | plugins `org.springframework.boot` and `io.spring.dependency-management` | picking compatible versions for all Spring libraries |
| `<java.version>17` | `java.toolchain.languageVersion = 17` | the application's Java version |
| `compile` scope (the default) | `implementation` | library needed to compile and run |
| `runtime` scope (H2) | `runtimeOnly` | only needed when the application runs |
| `test` scope | `testImplementation` | only needed for tests |
| `spring-boot-maven-plugin` | plugin `org.springframework.boot` | `bootRun` and `bootJar` tasks |
| `maven-javadoc-plugin` | `javadoc` task configuration | generating the documentation |

### 3.2 Version catalog (`gradle/libs.versions.toml`)

The assignment recommends keeping dependencies in a version catalog. It's a separate file where each library and plugin is written once, with its name and version. `build.gradle` then refers to them by a short name, such as `libs.spring.boot.starter.web`.

```toml
[versions]
spring-boot = "3.3.0"
spring-dependency-management = "1.1.7"

[libraries]
spring-boot-starter-web = { module = "org.springframework.boot:spring-boot-starter-web" }
spring-boot-starter-data-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-starter-hateoas = { module = "org.springframework.boot:spring-boot-starter-hateoas" }
spring-boot-starter-actuator = { module = "org.springframework.boot:spring-boot-starter-actuator" }
spring-boot-starter-test = { module = "org.springframework.boot:spring-boot-starter-test" }
h2 = { module = "com.h2database:h2" }
junit-platform-launcher = { module = "org.junit.platform:junit-platform-launcher" }

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
spring-dependency-management = { id = "io.spring.dependency-management", version.ref = "spring-dependency-management" }
```

Notice that the libraries have no version. That's on purpose. The `io.spring.dependency-management` plugin brings in Spring Boot's official list (called a **BOM**, *bill of materials*) with the right version of each library, already tested to work together. It plays the same role `spring-boot-starter-parent` played in Maven. In practice, we only have to maintain one version: Spring Boot's.

We removed the `guava` and `junit-jupiter` entries that `init` had added as examples, since the application doesn't use them.

### 3.3 `build.gradle`: the base

```groovy
import org.apache.tools.ant.filters.ReplaceTokens

plugins {
    id 'application'
    alias(libs.plugins.spring.boot)
    alias(libs.plugins.spring.dependency.management)
}

group = 'com.example'
version = '1.0.0'

repositories {
    mavenCentral()
}

dependencies {
    implementation libs.spring.boot.starter.web
    implementation libs.spring.boot.starter.data.jpa
    implementation libs.spring.boot.starter.hateoas
    implementation libs.spring.boot.starter.actuator
    runtimeOnly libs.h2
    testImplementation libs.spring.boot.starter.test
    testRuntimeOnly libs.junit.platform.launcher
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(17)
    }
}

application {
    mainClass = 'com.example.bookstore.BookstoreApplication'
}

tasks.named('test') {
    useJUnitPlatform()
}

tasks.named('javadoc') {
    title = 'Bookstore API'
    failOnError = false
    options.memberLevel = JavadocMemberLevel.PRIVATE
    options.encoding = 'UTF-8'
    options.links('https://docs.oracle.com/en/java/javase/17/docs/api/')
}
```

Going through it piece by piece:

- **`plugins`**: `application` is meant for applications you run (it gives us `installDist`, used later on) and it automatically applies the `java` plugin (which provides compilation, tests and the jar). That's why `java` doesn't need to be declared separately. The `alias(...)` lines apply the two Spring Boot plugins with the versions from the catalog.
- **`repositories`**: tells Gradle where to fetch libraries from (Maven Central, the most widely used public repository for Java).
- **`java.toolchain`**: tells Gradle to compile and run the application with Java 17, even if the machine has a different default version installed. If Java 17 isn't there, Gradle downloads it.
- **`application.mainClass`**: the class with the `main` method, where the application starts.
- **`javadoc`**: mirrors the Maven configuration (it also documents private methods and doesn't fail the build if there are errors in the comments). We added a title, UTF-8 encoding so accented characters display correctly, and a link to the official Java 17 documentation. Thanks to that link, whenever our code uses Java classes like `String` or `List`, the name becomes a link to the matching Oracle page.

---

## 4. Running the application with `bootRun`

```bash
./gradlew bootRun
```

While it's running, the application can be tested in the browser or with `curl`:

- http://localhost:8080 : entry point, with links to the other routes
- http://localhost:8080/books
- http://localhost:8080/clients
- http://localhost:8080/orders
- http://localhost:8080/h2-console : database console (JDBC URL `jdbc:h2:mem:bookstore`, user `sa`, no password)

<img width="459" height="357" alt="image" src="https://github.com/user-attachments/assets/f9282130-8cd5-49a8-b925-c5cf513943c4" />

To compile, run the tests and build the jar without starting the application:

```bash
./gradlew build
```

---

## 5. The `deployToDev` task

The goal is to assemble in `build/deployment/dev` everything needed to install the application in a development environment: the jar, the libraries and the configuration file with its values already filled in.

### 5.1 Placeholders in the configuration file

In `src/main/resources/application.properties`, we replaced the hand-written version with placeholders (tokens) wrapped in `@`:

```properties
# Custom service metadata properties
service.version=@projectVersion@
service.build-timestamp=@buildTimestamp@
service.environment=dev
```

During the deploy, Gradle replaces `@projectVersion@` with the project version (`1.0.0`) and `@buildTimestamp@` with the date and time of the build. The benefit is that the version is now defined in a single place (`build.gradle`), with no need to update it by hand in the configuration file.

### 5.2 Implementation

The task is split into four steps, and `deployToDev` simply groups them:

```groovy
def deployDir = layout.buildDirectory.dir('deployment/dev')

// 1. Delete whatever a previous deploy left behind
tasks.register('cleanDeployDev', Delete) {
    group = 'deployment'
    delete deployDir
}

// 2. Copy the application jar
tasks.register('copyAppToDev', Copy) {
    group = 'deployment'
    dependsOn 'cleanDeployDev'
    from tasks.named('bootJar')
    into deployDir
}

// 3. Copy the libraries needed at runtime into lib/
tasks.register('copyLibsToDev', Copy) {
    group = 'deployment'
    dependsOn 'cleanDeployDev'
    from(configurations.runtimeClasspath) { include '*.jar' }
    into deployDir.map { it.dir('lib') }
}

// 4. Copy the configuration, replacing the placeholders
tasks.register('copyConfigToDev', Copy) {
    group = 'deployment'
    dependsOn 'cleanDeployDev'
    def projectVersion = project.version.toString()
    from('src/main/resources') { include '*.properties' }
    into deployDir
    doFirst {
        filter(ReplaceTokens, tokens: [
            projectVersion: projectVersion,
            buildTimestamp: java.time.Instant.now().toString()
        ])
    }
}

tasks.register('deployToDev') {
    group = 'deployment'
    description = 'Clean + copia app, libs de runtime e config para build/deployment/dev'
    dependsOn 'copyAppToDev', 'copyLibsToDev', 'copyConfigToDev'
}
```

### 5.3 Why it's built this way

We split the deploy into four small tasks instead of a single one with all the code inside. This way, each step can be run and tested on its own (for example, `./gradlew copyConfigToDev`), and Gradle knows exactly what each one reads and writes.

In `from tasks.named('bootJar')` we don't give the path to the jar. We give the task that produces it. That way, Gradle works out by itself that it must build the jar before copying it.

`bootJar` produces a "fat jar": a single file that already contains all the libraries. So to run the application, the jar alone is enough. The `lib/` folder is what step 3 of the assignment asks for, and it holds only the libraries used at runtime (`runtimeClasspath`), leaving out the ones that are only needed for tests. It's what you would use for a deploy with a "thin" jar, one without the libraries bundled inside.

`ReplaceTokens` is a filter that ships with Gradle. It reads the file as it copies it and swaps each `@placeholder@` for the given value. The original file in `src/main/resources` is left untouched.

The filter sits inside a `doFirst` because of the *configuration cache*, which `gradle init` enabled in `gradle.properties` (`org.gradle.configuration-cache=true`). To see why, you need to know that Gradle works in two phases:

1. **Configuration**: reads `build.gradle` and sets up the list of tasks and what each one will do.
2. **Execution**: runs the tasks.

With the configuration cache on, Gradle saves the result of phase 1 and skips that phase on later runs. If `Instant.now()` were placed directly in the task body, it would be evaluated in phase 1 and stored in the cache. The timestamp would stay the same until someone changed `build.gradle`. Inside `doFirst`, the code runs in phase 2, right before the copy, so the date and time always match the moment of the deploy.

The project version, on the other hand, is read in phase 1 and stored in the `projectVersion` variable. This is required with the configuration cache, because Gradle doesn't allow access to the `project` object during execution.

### 5.4 Checking the result

```bash
./gradlew deployToDev
tree build/deployment/dev
cat build/deployment/dev/application.properties
```

<img width="459" height="713" alt="image" src="https://github.com/user-attachments/assets/35982bf0-f7b7-46ba-a5c2-d97e13688d0f" />
<img width="328" height="328" alt="image" src="https://github.com/user-attachments/assets/26b325eb-1387-468e-9b19-c3c1888a29e7" />

To confirm the application actually uses this configuration:

```bash
cd build/deployment/dev
java -jar bookstore-1.0.0.jar
curl http://localhost:8080/info/details
```

Spring Boot gives priority to an `application.properties` file located in the folder the application is started from, over the one packaged inside the jar. That's why the response shows version `1.0.0`. If the application is started with `bootRun`, the same response shows the literal text `@projectVersion@`, because no replacement happens there.

---

## 6. The `runDist` task

The `installDist` task (from the `application` plugin) generates, in `build/install/bookstore/`, a version of the application ready to distribute, with two folders:

- `lib/`: the application jar and all its libraries;
- `bin/`: two launch scripts, `bookstore` for Linux/macOS and `bookstore.bat` for Windows.

`runDist` runs `installDist` first and then executes the right script for the operating system:

```groovy
tasks.register('runDist', Exec) {
    group = 'application'
    description = 'Corre a app com os scripts gerados pelo installDist'
    dependsOn 'installDist'
    def isWindows = System.getProperty('os.name').toLowerCase().contains('windows')
    workingDir = layout.buildDirectory.dir("install/${project.name}/bin").get().asFile
    commandLine isWindows ? ['cmd', '/c', "${project.name}.bat"] : ["./${project.name}"]
}
```

The operating system is read from Java's `os.name` property. On Windows, a `.bat` file can't be executed directly and has to be launched through `cmd /c`.

```bash
./gradlew runDist
```

<img width="410" height="330" alt="image" src="https://github.com/user-attachments/assets/cbf9115d-e81c-4100-9902-105158653487" />

---

## 7. The `javadocZip` task

Javadoc is documentation generated from the `/** ... */` comments in the code, as HTML pages. This task generates it (with the options from section 3.3) and then bundles everything into a zip, which is easier to share:

```groovy
tasks.register('javadocZip', Zip) {
    group = 'documentation'
    dependsOn 'javadoc'
    from tasks.named('javadoc')
    archiveFileName = "${project.name}-${project.version}-javadoc.zip"
    destinationDirectory = layout.buildDirectory.dir('distributions')
}
```

```bash
./gradlew javadocZip
ls build/distributions
```

<img width="798" height="37" alt="image" src="https://github.com/user-attachments/assets/2d56ca26-a08a-422d-90a9-89959bfd8768" />

The documentation can also be opened directly in the browser, at `build/docs/javadoc/index.html`, with the following command:
`xdg-open build/docs/javadoc/index.html`

<img width="928" height="461" alt="image" src="https://github.com/user-attachments/assets/4b3e042d-198f-474e-aa64-7bd1765ca49a" />

---

## 8. Integration tests

A **unit test** checks one piece of code in isolation and is fast. An **integration test** checks several pieces working together. Here, it starts the whole application and makes a real HTTP request. It's slower, so it makes sense to keep these tests in their own folder and be able to run them separately.

In Gradle, that separate folder is a **source set**: a group of code with its own dependencies and its own compilation. `main` and `test` are the two that exist by default. We created a third one, `integrationTest`.

### 8.1 Configuration

```groovy
sourceSets {
    integrationTest {
        compileClasspath += sourceSets.main.output
        runtimeClasspath += sourceSets.main.output
    }
}

configurations {
    integrationTestImplementation.extendsFrom testImplementation
    integrationTestRuntimeOnly.extendsFrom testRuntimeOnly
}

tasks.register('integrationTest', Test) {
    group = 'verification'
    description = 'Corre os testes de integração'
    testClassesDirs = sourceSets.integrationTest.output.classesDirs
    classpath = sourceSets.integrationTest.runtimeClasspath
    shouldRunAfter 'test'
    useJUnitPlatform()
}

tasks.named('check') { dependsOn 'integrationTest' }
```

What each block does:

- **`sourceSets`**: creates the source set. Gradle starts looking for code in `src/integrationTest/java`. The two lines inside give the tests access to the application classes.
- **`configurations`**: the integration tests inherit the same libraries as the regular tests (JUnit, `spring-boot-starter-test`), so we don't have to repeat them.
- **`integrationTest`**: the task that runs these tests. `shouldRunAfter 'test'` makes sure that, when both are requested, the unit tests (which are faster) run first.
- **`check`**: with this line, `./gradlew build` also runs the integration tests.

This setup follows the same structure shown in class (T5b, *Custom source sets*). The difference is in `extendsFrom`. In the slides, the source set inherits from `implementation`, meaning the application libraries, and the test libraries are declared separately. We inherit from `testImplementation`, which already includes `implementation`. This way, the integration tests get both the application libraries and the test libraries (JUnit, AssertJ, `spring-boot-starter-test`) in one go, without declaring them a second time.

### 8.2 Checking that the source set exists

To see the project's source sets and what each one has access to, we added a helper task based on exercise 2 of TP5:

```groovy
tasks.register('printSourceSetInfo') {
    group = 'help'
    description = "Prints details about the project's source sets."
    notCompatibleWithConfigurationCache('Lê o modelo do projeto durante a execução')
    doLast {
        sourceSets.configureEach { srcSet ->
            println "[${srcSet.name}]"
            println "--> Source directories: ${srcSet.allJava.srcDirs}"
            println "--> Output directories: ${srcSet.output.classesDirs.files}"
            println "--> Compile classpath: ${srcSet.compileClasspath.files}"
            println "--> Runtime classpath: ${srcSet.runtimeClasspath.files}\n"
        }
    }
}
```

The `notCompatibleWithConfigurationCache` line isn't in the version from class. We needed it because the task reads `sourceSets` (which belong to `project`) during execution, and the configuration cache doesn't allow that. With this line, Gradle turns off the cache only when this task runs.

```bash
./gradlew -q printSourceSetInfo
```

<img width="928" height="75" alt="image" src="https://github.com/user-attachments/assets/300e0e41-630d-41b1-beb4-47a424f24b30" />

The output lists three source sets: `main`, `test` and `integrationTest`. In `integrationTest`, the classpath includes `build/classes/java/main`, which confirms the integration tests can access the application classes.

### 8.3 The test

File `src/integrationTest/java/com/example/bookstore/BookApiIT.java`:

```java
package com.example.bookstore;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class BookApiIT {

    @Autowired
    private TestRestTemplate rest;

    @Test
    void listsSeededBooks() {
        ResponseEntity<String> response = rest.getForEntity("/books", String.class);
        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).contains("Clean Code");
    }
}
```

The test starts the application on any free port, requests the list of books and checks two things: that the response is `200 OK`, and that it includes the book "Clean Code", created automatically at startup by `DataInitializer`.

The file's folder has to match the `com.example.bookstore` package, which is the same as the main class. Otherwise, Spring can't find the application to start.

```bash
./gradlew integrationTest
```

The report is written to `build/reports/tests/integrationTest/index.html` and can be opened the same way as the Javadoc.

<img width="917" height="530" alt="image" src="https://github.com/user-attachments/assets/4beb892e-0a46-499a-a9bd-11d0d030f7d7" />

---

## 9. Problems we ran into

### 9.1 The application wouldn't start: `ClassNotFoundException: org.example.bookstore.BookstoreApplication`

When no package is given, `gradle init` uses `org.example`, and it left that in the `mainClass` of `build.gradle`. The Bookstore code lives in `com.example`, so Gradle was looking for the main class in the wrong place.

We changed `mainClass` to `com.example.bookstore.BookstoreApplication` and `group` to `com.example`.

### 9.2 `Could not resolve placeholder 'service.version'`

While adding the placeholders to `application.properties`, the `service.version` line ended up being deleted. The `InfoController` class needs that value, and without it the application doesn't start. We put the line back with the value `@projectVersion@`.

### 9.3 `Could not get unknown property 'ReplaceTokens'`

The filter class hadn't been imported. Adding this line at the top of `build.gradle` fixed it:

```groovy
import org.apache.tools.ant.filters.ReplaceTokens
```

### 9.4 `bootJar` failed with `CopyProcessingSpec.getDirMode()`

`gradle init` was run with Gradle 9, and the wrapper was left on that version. The Spring Boot 3.3.0 plugin predates Gradle 9 and uses a method (`getDirMode()`) that Gradle 9 removed. `bootRun` worked because it doesn't use that method; only building the jar calls it.

There were two ways out: downgrade Gradle to 8.x, or upgrade Spring Boot to 3.5.x (which supports Gradle 9). We chose the first, to keep the same Spring Boot version as the original `pom.xml`:

```bash
./gradlew wrapper --gradle-version 8.14.3
```

### 9.5 `Unsupported class file major version 69`

After downgrading to Gradle 8.14.3, the build couldn't even read `build.gradle`. Gradle itself is a Java program and needs a Java installation to run. It was using the machine's Java 25, and Gradle 8.14.3 only runs on Java 24 or older. The "69" is the internal number that identifies Java 25.

The toolchain set in `build.gradle` doesn't help here, because it only selects the Java used to compile and run the application, not the Java that runs Gradle itself.

We fixed it by pointing the `JAVA_HOME` variable to Java 17 before running Gradle:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
./gradlew --stop      # stops the Gradle process that was running on Java 25
./gradlew --version   # the "Daemon JVM" line should show Java 17
```

This fix only applies to the terminal where it was made. In a new session, the `export` has to be repeated (or added to `~/.bashrc`).

### 9.6 Summary: three different versions to keep track of

These last two problems show that a Gradle build involves three different "versions", each controlled in a different place:

| What | Where it's set | In this project |
|---|---|---|
| Gradle version | `gradle/wrapper/gradle-wrapper.properties` (wrapper) | 8.14.3 |
| Java that runs Gradle | the machine's `JAVA_HOME` variable | Java 17 |
| Java that compiles and runs the application | `build.gradle` (`java.toolchain`) | Java 17 |

The first and third are stored in the repository, so they're the same for anyone who clones it. The second depends on each person's machine: `JAVA_HOME` has to point to a Java version between 17 and 24.

---

## 10. Task summary

| Task | Group | What it does |
|---|---|---|
| `bootRun` | application | runs the application |
| `build` | build | compiles, runs all tests and builds the jars |
| `deployToDev` | deployment | assembles `build/deployment/dev` with the jar, the libraries and the filled-in configuration |
| `runDist` | application | runs the application through the `installDist` scripts, depending on the operating system |
| `javadocZip` | documentation | generates the Javadoc and puts it in a zip |
| `integrationTest` | verification | runs the tests in `src/integrationTest` |

To list the tasks in each group:

```bash
./gradlew tasks --group deployment
./gradlew tasks --group documentation
```

To check the order in which tasks run, without actually running them, use the `--dry-run` option. Gradle prints every task that would run, in the right order, marked as `SKIPPED`:

```bash
./gradlew deployToDev --dry-run
./gradlew runDist --dry-run
./gradlew javadocZip --dry-run
```

<img width="584" height="529" alt="image" src="https://github.com/user-attachments/assets/a2b6f7d7-3c0f-4d3f-8075-5bf5e16bc108" />

In each one, you should see that:

- **`deployToDev`**: `cleanDeployDev` runs before the three copies, and `bootJar` before `copyAppToDev`.
- **`runDist`**: the jar and the launch scripts (`jar`, `startScripts`) are built and installed (`installDist`) before the application is launched.
- **`javadocZip`**: `javadoc` runs before the zip.

---

## 11. Alternative to Gradle

*(to be completed)*

---

## 12. Self-assessment

| Member | No. | Contribution |
|---|---|---|
| Gonçalo Dinis Araújo | 1260528 | xx% |
| Pedro Barbosa | 1260483 | xx% |
