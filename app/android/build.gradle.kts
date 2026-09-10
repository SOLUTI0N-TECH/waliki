allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// Some plugins pulled in by reown_appkit (coinbase_wallet_sdk) still declare
// compileSdk 31 and sqflite needs API 36 symbols. Pin every
// Android subproject so the AAR metadata check passes.
// NOTE: this must run BEFORE evaluationDependsOn(":app") below — once a project
// is evaluated, afterEvaluate can no longer be registered.
subprojects {
    afterEvaluate {
        // coinbase_wallet_sdk 1.0.10 declares consumerProguardFiles
        // "consumer-rules.pro" but does not ship the file, so the build dies on
        // mergeDebugConsumerProguardFiles. Create an empty one in place — this
        // keeps the workaround in the repo instead of every machine.
        if (name == "coinbase_wallet_sdk") {
            val rules = file("consumer-rules.pro")
            if (!rules.exists()) {
                rules.writeText("# created by waliki: upstream package omits this file")
            }
        }
        extensions.findByName("android")?.let { ext ->
            val android = ext as com.android.build.gradle.BaseExtension
            android.compileSdkVersion(36)
            if ((android.defaultConfig.minSdkVersion?.apiLevel ?: 0) < 23) {
                android.defaultConfig.minSdk = 23
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
