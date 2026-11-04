// Trip runtime (T15 D1): pure-JVM module that coordinates the Trip Engine on Android: actor, effect
// planning, restore, fallback slots, snapshot store. No Android API on the classpath, so every
// decision of the platform layer is JVM-tested; :app only binds the ports to Android services.
import org.gradle.api.tasks.testing.logging.TestExceptionFormat
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.time.Duration

plugins { id("org.jetbrains.kotlin.jvm") }

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }

dependencies {
    implementation(project(":core-trip"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
    testImplementation(platform("org.junit:junit-bom:6.1.3"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
    // Test only: reads fixtures/traces/*.expect.json and debug journals (Maven Central, checked 2026-11-03).
    testImplementation("org.json:json:20260814")
}

val repoRoot = rootProject.projectDir.resolve("../..").canonicalFile
val fixturesDir = repoRoot.resolve("fixtures/traces")

tasks.test {
    useJUnitPlatform()
    maxHeapSize = "2g"
    timeout.set(Duration.ofMinutes(10))
    systemProperty("napstop.fixturesDir", fixturesDir.absolutePath)
    systemProperty("napstop.mainSrcDir", projectDir.resolve("src/main/kotlin").absolutePath)
    systemProperty("napstop.outDir", layout.buildDirectory.dir("napstop").get().asFile.absolutePath)
    providers.gradleProperty("napstop.dumpDoze").orNull?.let { systemProperty("napstop.dumpDoze", it) }
    providers.gradleProperty("napstop.dozeOnly").orNull?.let { systemProperty("napstop.dozeOnly", it) }
    providers.gradleProperty("napstop.dumpKill").orNull?.let { systemProperty("napstop.dumpKill", it) }
    inputs.dir(fixturesDir).withPathSensitivity(PathSensitivity.RELATIVE)
    testLogging { events("failed"); exceptionFormat = TestExceptionFormat.FULL }
}

// Debug journal of a device run (spec T15 §5.14, protocol LM1-LM4):
//   ./gradlew :core-runtime:analyzeJournal -Pjournal=/path/to/journal.ndjson
tasks.register<JavaExec>("analyzeJournal") {
    group = "verification"
    description = "Prints wake-up delays, fix gaps and the first alarm of a T15 debug journal."
    classpath = sourceSets["test"].runtimeClasspath
    mainClass.set("app.napstop.core.trip.runtime.JournalAnalyzer")
    args(providers.gradleProperty("journal").orNull ?: "")
}
