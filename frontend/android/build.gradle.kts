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

    project.configurations.configureEach {
        resolutionStrategy {
            force("androidx.concurrent:concurrent-futures:1.2.0")
        }
    }
    project.pluginManager.withPlugin("com.android.library") {
        project.dependencies.add("compileOnly", "androidx.concurrent:concurrent-futures:1.2.0")
    }
}

//subprojects {
//    afterEvaluate { project ->
//        if (project.hasProperty("android")) {
//            project.android {
//                if (namespace == null) {
//                    namespace project.group
//                }
//            }
//        }
//    }
//}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
