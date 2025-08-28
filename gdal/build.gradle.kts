import org.gradle.internal.jvm.Jvm

plugins {
    id("com.android.library")
}

android {
    namespace = "com.example.gdal"
    compileSdk = 35

    defaultConfig {
        minSdk = 21
        // This must match the version of the NDK Mapbox uses, or you'll get conflicts with
        // libc++_shared.so. Make sure Dockerfile downloads the same version.
        ndkVersion = "27.3.13750724"

        consumerProguardFiles("consumer-rules.pro")
    }

    testOptions {
        targetSdk = 35
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    // Compile against Java 17
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Tell Gradle to run against Java 17
    java {
        toolchain {
            languageVersion.set(JavaLanguageVersion.of(17))
        }
    }

    libraryVariants.all {
        val ndkDir = android.ndkDirectory
        val apiVersion = 21

        if (name == "release") {
            tasks.register<Exec>("BuildGDALNative_Release") {
                commandLine("bash", "build_cpp.sh", ndkDir, apiVersion, "Release")
            }
        } else if (name == "debug") {
            tasks.register<Exec>("BuildGDALNative_Debug") {
                commandLine("bash", "build_cpp.sh", ndkDir, apiVersion, "Debug")
            }
        }
    }

    tasks.whenTaskAdded {
        if (name == "assembleRelease") {
            dependsOn("BuildGDALNative_Release")
        } else if (name == "assembleDebug") {
            dependsOn("BuildGDALNative_Debug")
        } else if (name == "BuildGDALNative_Release" || name == "BuildGDALNative_Debug") {
            dependsOn("cleanJni")
        }
    }

    tasks.register<Delete>("cleanJni") {
        delete("libs")
        delete("src/main/jniLibs")
    }
    tasks.named("clean") {
        dependsOn("cleanJni")
    }
}

dependencies {
    implementation(fileTree(kotlin.collections.mapOf("dir" to "libs", "include" to kotlin.collections.listOf("*.jar"))))
}