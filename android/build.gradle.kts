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

// The no-tracker rule: fails on any firebase, measurement, analytics, ads or
// location artifact in the release runtime classpath of :app. The only
// firebase allowed are the three encoders, and only under
// com.google.android.datatransport (pulled by Play Billing). It prints what
// it allowed, so a new one shows up in review.
tasks.register("verifyNoTrackingDeps") {
    group = "verification"
    description = "No trackers in :app (release runtime classpath)."
    val allowedEncoders = setOf(
        "com.google.firebase:firebase-encoders",
        "com.google.firebase:firebase-encoders-json",
        "com.google.firebase:firebase-encoders-proto",
    )
    fun banned(id: String): Boolean {
        val lower = id.lowercase()
        return lower.startsWith("com.google.firebase:") ||
            lower.contains("measurement") ||
            lower.contains("analytics") ||
            lower.contains("play-services-ads") ||
            lower.contains("play-services-location") ||
            lower.contains("crashlytics")
    }
    doLast {
        val failures = mutableListOf<String>()
        val allowed = sortedSetOf<String>()
        for (path in listOf(":app")) {
            val p = project(path)
            val names = p.configurations.names.filter {
                it.endsWith("ReleaseRuntimeClasspath") && !it.contains("UnitTest") && !it.contains("AndroidTest")
            }
            for (name in names) {
                val root = p.configurations.getByName(name).incoming.resolutionResult.root
                val seen = mutableSetOf<String>()
                fun walk(node: org.gradle.api.artifacts.result.ResolvedComponentResult, chain: List<String>) {
                    for (dep in node.dependencies) {
                        if (dep !is org.gradle.api.artifacts.result.ResolvedDependencyResult) continue
                        val c = dep.selected
                        val module = c.moduleVersion ?: continue
                        val id = "${module.group}:${module.name}"
                        val next = chain + id
                        if (banned(id)) {
                            val viaTransport = chain.any { it.startsWith("com.google.android.datatransport:") }
                            // The Reviewer + UX, 14 Nov: Play Billing depends on it;
                            // no location permission in the merged manifest (the
                            // exact-match list, release-aab and its test).
                            val viaBilling = chain.lastOrNull() == "com.android.billingclient:billing"
                            if (id in allowedEncoders && viaTransport) {
                                allowed += "$id (via ${chain.last()})"
                            } else if (id == "com.google.android.gms:play-services-location" && viaBilling) {
                                allowed += "$id (via ${chain.last()}): Play Billing dependency; no location permission in the merged manifest"
                            } else {
                                failures += "$path $name: $id via ${next.joinToString(" > ")}"
                            }
                        }
                        if (seen.add("$id@${chain.lastOrNull()}")) walk(c, next)
                    }
                }
                walk(root, emptyList())
            }
        }
        allowed.forEach { println("allowed: $it") }
        if (failures.isNotEmpty()) {
            throw GradleException("Tracker artifacts found:\n" + failures.joinToString("\n"))
        }
        println("verifyNoTrackingDeps: no tracker artifacts in :app.")
        println("Location permissions: android/expected-permissions.txt is an exact-match list (release-aab diffs the merged AAB; release_pipeline_test rejects any LOCATION entry), so none can ship.")
    }
}
