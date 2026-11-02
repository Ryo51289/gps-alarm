// Trip Engine (T12): pure-JVM module, package app.napstop.core.trip. No Android API on the
// classpath, so "no Android dependency" is enforced by the compiler (T12 K1).
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
    // No runtime dependency besides kotlin-stdlib (T12 K2).
    testImplementation(platform("org.junit:junit-bom:6.1.3"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

val repoRoot = rootProject.projectDir.resolve("../..").canonicalFile
val fixturesDir = repoRoot.resolve("fixtures/traces")
val p05Dir = repoRoot.resolve("fixtures/p05")

tasks.test {
    useJUnitPlatform()
    maxHeapSize = "2g"
    timeout.set(Duration.ofMinutes(15))
    systemProperty("napstop.fixturesDir", fixturesDir.absolutePath)
    systemProperty("napstop.p05Dir", p05Dir.absolutePath)
    systemProperty("napstop.mainSrcDir", projectDir.resolve("src/main/kotlin").absolutePath)
    systemProperty("napstop.testSrcDir", projectDir.resolve("src/test/kotlin").absolutePath)
    systemProperty("napstop.outDir", layout.buildDirectory.dir("napstop").get().asFile.absolutePath)
    systemProperty("napstop.updateP05", providers.gradleProperty("napstop.updateP05").getOrElse("false"))
    systemProperty("napstop.dumpTranscripts", providers.gradleProperty("napstop.dumpTranscripts").getOrElse("false"))
    inputs.dir(fixturesDir).withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.dir(p05Dir).withPathSensitivity(PathSensitivity.RELATIVE)
    testLogging { events("failed"); exceptionFormat = TestExceptionFormat.FULL }
}
