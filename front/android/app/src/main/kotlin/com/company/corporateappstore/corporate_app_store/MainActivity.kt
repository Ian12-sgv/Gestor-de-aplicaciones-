package com.company.corporateappstore.corporate_app_store

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledAppsInfo" -> {
                    val packageNames = call.argument<List<String>>("packageNames").orEmpty()
                    result.success(getInstalledAppsInfo(packageNames))
                }

                "openApp" -> {
                    val packageName = call.argument<String>("packageName")
                    result.success(
                        if (packageName.isNullOrBlank()) {
                            false
                        } else {
                            openApp(packageName)
                        },
                    )
                }

                "uninstallApp" -> {
                    val packageName = call.argument<String>("packageName")
                    result.success(
                        if (packageName.isNullOrBlank()) {
                            launchResult(
                                status = "unavailable",
                                message = "No se recibio el paquete de la app.",
                            )
                        } else {
                            uninstallApp(packageName)
                        },
                    )
                }

                "getInstallEnvironmentInfo" -> {
                    result.success(getInstallEnvironmentInfo())
                }

                "openInstallPermissionSettings" -> {
                    result.success(openInstallPermissionSettings())
                }

                "getApkCacheDirectory" -> {
                    result.success(resolveApkCacheDirectory())
                }

                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath")
                    result.success(
                        if (apkPath.isNullOrBlank()) {
                            launchResult(
                                status = "unavailable",
                                message = "No se recibio la ruta del APK.",
                            )
                        } else {
                            installApk(apkPath)
                        },
                    )
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun getInstallEnvironmentInfo(): Map<String, Any> {
        val canInstallUnknownApps =
            Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                packageManager.canRequestPackageInstalls()
        val settingsIntent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        )
        val settingsAvailable = settingsIntent.resolveActivity(packageManager) != null
        val installerAvailable = detectInstallerAvailability()

        return mapOf(
            "manufacturer" to Build.MANUFACTURER.orEmpty(),
            "model" to Build.MODEL.orEmpty(),
            "sdkInt" to Build.VERSION.SDK_INT,
            "canInstallUnknownApps" to canInstallUnknownApps,
            "installerAvailable" to installerAvailable,
            "settingsAvailable" to settingsAvailable,
            "policyHint" to resolvePolicyHint(
                manufacturer = Build.MANUFACTURER.orEmpty(),
                canInstallUnknownApps = canInstallUnknownApps,
                installerAvailable = installerAvailable,
            ),
        )
    }

    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || packageManager.canRequestPackageInstalls()) {
            return true
        }

        val settingsIntent = Intent(
            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
            Uri.parse("package:$packageName"),
        ).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            startActivity(settingsIntent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun getInstalledAppsInfo(packageNames: List<String>): Map<String, Map<String, Any?>> {
        return packageNames.associateWith { packageName ->
            val packageInfo = findPackageInfo(packageName)

            if (packageInfo == null) {
                mapOf(
                    "installed" to false,
                    "versionName" to null,
                    "versionCode" to null,
                )
            } else {
                mapOf(
                    "installed" to true,
                    "versionName" to packageInfo.versionName,
                    "versionCode" to resolveVersionCode(packageInfo),
                )
            }
        }
    }

    private fun openApp(packageName: String): Boolean {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return false

        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        return try {
            startActivity(launchIntent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun uninstallApp(packageName: String): Map<String, Any> {
        if (packageName == applicationContext.packageName) {
            return launchResult(
                status = "unavailable",
                message = "No puedes eliminar el portal corporativo desde si mismo.",
            )
        }

        if (findPackageInfo(packageName) == null) {
            return launchResult(
                status = "unavailable",
                message = "La app no esta instalada en este dispositivo.",
            )
        }

        val uninstallIntent = Intent(Intent.ACTION_DELETE).apply {
            data = Uri.parse("package:$packageName")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            startActivity(uninstallIntent)
            launchResult(
                status = "launchedUninstaller",
                message = "Se abrio la confirmacion para eliminar la app.",
            )
        } catch (_: ActivityNotFoundException) {
            launchResult(
                status = "unavailable",
                message = "No hay una pantalla disponible para eliminar esta app.",
            )
        } catch (_: SecurityException) {
            launchResult(
                status = "unavailable",
                message = "Android bloqueo la eliminacion de esta app.",
            )
        }
    }

    private fun installApk(apkPath: String): Map<String, Any> {
        val apkFile = File(apkPath)
        Log.i(TAG, "installApk requested for path=${apkFile.absolutePath}")

        if (!apkFile.exists()) {
            Log.w(TAG, "installApk aborted because APK file does not exist: ${apkFile.absolutePath}")
            return launchResult(
                status = "unavailable",
                message = "El APK descargado no esta disponible.",
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !packageManager.canRequestPackageInstalls()) {
            val settingsIntent = Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            return try {
                startActivity(settingsIntent)
                launchResult(
                    status = "needsPermission",
                    message = "Habilita la instalacion de apps desde esta aplicacion y vuelve a intentarlo.",
                )
            } catch (_: ActivityNotFoundException) {
                launchResult(
                    status = "unavailable",
                    message = "No fue posible abrir la configuracion de permisos de instalacion.",
                )
            }
        }

        val contentUri = createContentUriForApk(apkFile) ?: run {
            Log.w(
                TAG,
                "FileProvider could not create a content URI for ${apkFile.absolutePath}. " +
                    "cacheDir=$cacheDir filesDir=$filesDir externalCacheDir=$externalCacheDir",
            )
            return launchResult(
                status = "unavailable",
                message = "No fue posible preparar el APK para instalarlo.",
            )
        }
        Log.i(TAG, "FileProvider content URI created successfully: $contentUri")

        var securityBlocked = false

        for (installIntent in buildInstallIntents(contentUri)) {
            if (installIntent.resolveActivity(packageManager) == null) {
                Log.w(TAG, "No activity resolved for install intent action=${installIntent.action}")
                continue
            }

            try {
                Log.i(TAG, "Launching install intent action=${installIntent.action}")
                startActivity(installIntent)
                return launchResult(
                    status = "launchedInstaller",
                    message = "Se abrio el instalador del sistema.",
                )
            } catch (_: ActivityNotFoundException) {
                Log.w(TAG, "ActivityNotFoundException while launching install intent action=${installIntent.action}")
                continue
            } catch (_: SecurityException) {
                Log.w(TAG, "SecurityException while launching install intent action=${installIntent.action}")
                securityBlocked = true
            }
        }

        return if (securityBlocked) {
            launchResult(
                status = "unavailable",
                message = "Android bloqueo la apertura del instalador.",
            )
        } else {
            launchResult(
                status = "unavailable",
                message = "No hay un instalador disponible para abrir el APK.",
            )
        }
    }

    private fun findPackageInfo(packageName: String): PackageInfo? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0),
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, 0)
            }
        } catch (_: PackageManager.NameNotFoundException) {
            null
        } catch (_: SecurityException) {
            null
        }
    }

    private fun resolveVersionCode(packageInfo: PackageInfo): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode.toInt()
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode
        }
    }

    private fun launchResult(status: String, message: String): Map<String, Any> {
        return mapOf(
            "status" to status,
            "message" to message,
        )
    }

    private fun resolveApkCacheDirectory(): String {
        val apkDirectory = File(cacheDir, "corporate_store_apks")

        if (!apkDirectory.exists()) {
            apkDirectory.mkdirs()
        }

        return apkDirectory.absolutePath
    }

    private fun detectInstallerAvailability(): Boolean {
        val probeDirectory = File(resolveApkCacheDirectory())

        if (!probeDirectory.exists() && !probeDirectory.mkdirs()) {
            return false
        }

        val probeFile = File(probeDirectory, "installer_probe.apk")

        if (!probeFile.exists()) {
            try {
                probeFile.writeBytes(byteArrayOf())
            } catch (_: Exception) {
                return false
            }
        }

        val contentUri = createContentUriForApk(probeFile) ?: return false
        return buildInstallIntents(contentUri).any { intent ->
            intent.resolveActivity(packageManager) != null
        }
    }

    private fun createContentUriForApk(apkFile: File): Uri? {
        return try {
            FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                apkFile,
            )
        } catch (error: IllegalArgumentException) {
            Log.w(
                TAG,
                "FileProvider rejected path ${apkFile.absolutePath} for authority " +
                    "${applicationContext.packageName}.fileprovider",
                error,
            )
            null
        }
    }

    private fun buildInstallIntents(contentUri: Uri): List<Intent> {
        val installPackageIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            data = contentUri
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val viewIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(contentUri, APK_MIME_TYPE)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        return listOf(installPackageIntent, viewIntent)
    }

    private fun resolvePolicyHint(
        manufacturer: String,
        canInstallUnknownApps: Boolean,
        installerAvailable: Boolean,
    ): String {
        if (!installerAvailable) {
            return "El dispositivo no expone un instalador compatible para APKs."
        }

        if (!canInstallUnknownApps) {
            return "Android requiere habilitar la instalacion de apps fuera de Play Store para esta aplicacion."
        }

        return when (manufacturer.lowercase()) {
            "zebra", "honeywell", "pointmobile", "point mobile" ->
                "En equipos empresariales esta accion tambien puede quedar controlada por la politica MDM o por el perfil administrado del fabricante."
            "samsung", "lenovo" ->
                "Verifica politicas de Knox, Device Owner o perfil administrado si Android bloquea la instalacion aunque el permiso este habilitado."
            else ->
                "Si la instalacion falla, revisa politicas del dispositivo, perfil administrado y restricciones de origen desconocido."
        }
    }

    companion object {
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val CHANNEL_NAME = "corporate_app_store/android_apps"
        private const val TAG = "CorporateAppStore"
    }
}
