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
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

// The lint check that runs on library plugins crashes inside the Firebase plugin (a bug in the lint tool, not in our code).
// It only checks code style, so it is switched off for the release build; the app itself is built as usual.
subprojects {
    tasks.configureEach {
        if (name.startsWith("lintVital") || name == "lintAnalyzeRelease") enabled = false
    }
}
