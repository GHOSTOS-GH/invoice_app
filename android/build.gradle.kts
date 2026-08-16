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

// blue_thermal_printer (1.2.3, dernière version sur pub.dev) est un vieux plugin
// qui ne déclare pas de `namespace` dans son build.gradle. L'AGP 8.x l'exige,
// sinon le build échoue avec "Namespace not specified". On l'injecte ici.
subprojects {
    if (name == "blue_thermal_printer") {
        plugins.withId("com.android.library") {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                namespace = "id.kakzaki.blue_thermal_printer"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
