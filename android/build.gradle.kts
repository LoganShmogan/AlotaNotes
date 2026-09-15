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

    // Force every plugin subproject to compile against SDK 36, regardless of
    // what each plugin's own build.gradle hardcodes. Some plugins (e.g.
    // file_picker 8.x) hardcode an older compileSdk directly rather than
    // deriving it from flutter.compileSdkVersion, which otherwise produces a
    // "plugin X requires compiling against version Y" AAR-metadata build
    // failure the moment any *other* plugin needs 36+. This is the standard,
    // widely-documented Flutter workaround for that class of error -- safer
    // than bumping the offending plugin's own pub version, which can drag in
    // unrelated (and, in one case tried here, actually broken) transitive
    // dependency versions. Must be registered here, before
    // evaluationDependsOn below forces early evaluation of some subprojects.
    afterEvaluate {
        extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.let { android ->
            android.compileSdk = 36
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
