allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// CameraX 1.5.0 exposes CallbackToFutureAdapter in public class signatures,
// but its published metadata marks concurrent-futures as runtime-only. JDK 24
// needs that type on javac's compile classpath while compiling the Flutter
// camera plugin.
subprojects {
    if (name == "camera_android_camerax") {
        pluginManager.withPlugin("com.android.library") {
            dependencies.add(
                "compileOnly",
                "androidx.concurrent:concurrent-futures:1.1.0"
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
