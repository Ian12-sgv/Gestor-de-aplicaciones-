package com.company.corporateappstore.corporate_app_store

import android.Manifest
import android.app.AlertDialog
import android.app.DownloadManager
import android.content.Context
import android.os.Environment
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class MainActivity : FlutterActivity() {
    private var notificationPermissionResult: MethodChannel.Result? = null

    // APK waiting to be installed once the conflicting (differently signed) version is removed.
    private var pendingReinstall: PendingReinstall? = null

    // Installers can only be launched while the store is on screen (Android blocks
    // background activity starts); otherwise the "ready to install" notification is used.
    private var isInForeground = false

    // PACKAGE_ADDED/REPLACED are not delivered to manifest receivers on Android 8+,
    // so listen at runtime while the store is alive.
    private val packageInstallReceiver = PackageInstallReceiver()

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_PACKAGE_ADDED)
            addAction(Intent.ACTION_PACKAGE_REPLACED)
            addDataScheme("package")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(packageInstallReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(packageInstallReceiver, filter)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(packageInstallReceiver)
        } catch (_: IllegalArgumentException) {
            // Already unregistered.
        }
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
    }

    override fun onPause() {
        isInForeground = false
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleDownloadInstallIntent(intent)
    }

    override fun onPostResume() {
        super.onPostResume()
        handleDownloadInstallIntent(intent)
        resumePendingReinstall()
    }

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

                "ensureNotificationPermission" -> {
                    ensureNotificationPermission(result)
                }

                "enqueueApkDownload" -> {
                    val downloadUrl = call.argument<String>("downloadUrl")
                    val fileName = call.argument<String>("fileName")
                    val appName = call.argument<String>("appName")
                    val targetPackageName = call.argument<String>("packageName")

                    result.success(
                        if (
                            downloadUrl.isNullOrBlank() ||
                            fileName.isNullOrBlank() ||
                            appName.isNullOrBlank() ||
                            targetPackageName.isNullOrBlank()
                        ) {
                            launchResult(
                                status = "unavailable",
                                message = "No se recibieron los datos necesarios para descargar la app.",
                            )
                        } else {
                            enqueueApkDownload(
                                downloadUrl = downloadUrl,
                                fileName = fileName,
                                appName = appName,
                                targetPackageName = targetPackageName,
                            )
                        },
                    )
                }

                "getApkDownloadProgress" -> {
                    val downloadId = call.argument<Number>("downloadId")?.toLong()
                    result.success(
                        downloadId?.let { getApkDownloadProgress(it) },
                    )
                }

                "installDownloadedApk" -> {
                    val downloadId = call.argument<Number>("downloadId")?.toLong()
                    val apkPath = call.argument<String>("apkPath")
                    result.success(
                        if (downloadId == null || apkPath.isNullOrBlank()) {
                            launchResult(
                                status = "unavailable",
                                message = "No se recibio la descarga a instalar.",
                            )
                        } else {
                            installDownloadedApk(downloadId, apkPath)
                        },
                    )
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)

        if (requestCode != NOTIFICATION_PERMISSION_REQUEST_CODE) {
            return
        }

        val granted =
            grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
    }

    private fun ensureNotificationPermission(result: MethodChannel.Result) {
        if (
            Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }

        if (notificationPermissionResult != null) {
            result.success(false)
            return
        }

        notificationPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST_CODE,
        )
    }

    private fun enqueueApkDownload(
        downloadUrl: String,
        accessToken: String? = null,
        fileName: String,
        appName: String,
        targetPackageName: String,
    ): Map<String, Any> {
        val downloadManager =
            getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
                ?: return launchResult(
                    status = "unavailable",
                    message = "El gestor de descargas de Android no esta disponible.",
                )
        val downloadsDirectory = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: return launchResult(
                status = "unavailable",
                message = "No hay almacenamiento disponible para guardar el APK.",
            )
        val safeFileName = fileName.replace(Regex("[^A-Za-z0-9._-]"), "_")
        val relativeDestination = "corporate_store_apks/$safeFileName"
        val destinationFile = File(downloadsDirectory, relativeDestination)

        if (!destinationFile.parentFile.exists() && !destinationFile.parentFile.mkdirs()) {
            return launchResult(
                status = "unavailable",
                message = "No se pudo preparar el almacenamiento para la descarga.",
            )
        }

        return try {
            val request = DownloadManager.Request(Uri.parse(downloadUrl)).apply {
                setTitle("Descargando $appName")
                setDescription("La descarga continuara aunque cierres PDBStore.")
                setMimeType(APK_MIME_TYPE)
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
                setDestinationInExternalFilesDir(
                    this@MainActivity,
                    Environment.DIRECTORY_DOWNLOADS,
                    relativeDestination,
                )
                if (!accessToken.isNullOrBlank()) {
                    addRequestHeader("Authorization", "Bearer $accessToken")
                }
                addRequestHeader("Accept", APK_MIME_TYPE)
            }
            val downloadId = downloadManager.enqueue(request)
            DownloadQueueStore.saveDownload(
                context = applicationContext,
                downloadId = downloadId,
                filePath = destinationFile.absolutePath,
                appName = appName,
                packageName = targetPackageName,
            )
            mapOf(
                "status" to "queued",
                "message" to "Descarga iniciada en segundo plano. Te avisaremos cuando este lista para instalar.",
                "downloadId" to downloadId,
                "filePath" to destinationFile.absolutePath,
            )
        } catch (error: IllegalArgumentException) {
            Log.w(TAG, "Unable to enqueue APK download", error)
            launchResult(
                status = "unavailable",
                message = "No se pudo iniciar la descarga del APK.",
            )
        } catch (error: SecurityException) {
            Log.w(TAG, "Android blocked APK download", error)
            launchResult(
                status = "unavailable",
                message = "Android bloqueo la descarga del APK.",
            )
        }
    }

    private fun installDownloadedApk(downloadId: Long, apkPath: String): Map<String, Any> {
        if (!isInForeground) {
            return launchResult(
                status = "deferred",
                message = "La descarga termino. Toca la notificacion para instalar.",
            )
        }

        // Installing from the open store: drop the pending "ready" notification.
        DownloadQueueStore.readDownload(applicationContext, downloadId)?.let { record ->
            DownloadQueueStore.markReadyForInstall(applicationContext, record)
        }
        DownloadQueueStore.removeDownload(applicationContext, downloadId)
        ApkDownloadNotifications.cancelReadyToInstall(applicationContext, downloadId)
        return installApk(apkPath)
    }

    private fun getApkDownloadProgress(downloadId: Long): Map<String, Any>? {
        val downloadManager =
            getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager ?: return null
        val cursor = downloadManager.query(DownloadManager.Query().setFilterById(downloadId))
            ?: return null

        cursor.use {
            if (!it.moveToFirst()) {
                return null
            }
            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val received = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
            val total = it.getLong(it.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES))
            return mapOf(
                "status" to status,
                "receivedBytes" to received,
                "totalBytes" to total,
            )
        }
    }

    private fun handleDownloadInstallIntent(intent: Intent?) {
        if (intent?.action != ApkDownloadReceiver.ACTION_INSTALL_DOWNLOADED_APK) {
            return
        }

        val apkPath = intent.getStringExtra(ApkDownloadReceiver.EXTRA_APK_PATH)
        if (!apkPath.isNullOrBlank()) {
            installApk(apkPath)
        }
        intent.action = null
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

        val signatureConflict = detectSignatureConflict(apkFile)
        if (signatureConflict != null) {
            Log.w(
                TAG,
                "Signature conflict for package=${signatureConflict.packageName}; " +
                    "asking to uninstall the installed version before installing ${apkFile.absolutePath}",
            )
            showSignatureConflictDialog(signatureConflict, apkFile)
            return launchResult(
                status = "signatureConflict",
                message = "La nueva version esta firmada con otra llave. " +
                    "Confirma en el aviso para desinstalar la version actual y continuar.",
            )
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

    /**
     * Android refuses to update an app when the new APK is signed with a different key
     * (INSTALL_FAILED_UPDATE_INCOMPATIBLE) and the system installer only shows a generic
     * "App not installed". Detect it up front so the user can remove the old version first.
     */
    private fun detectSignatureConflict(apkFile: File): SignatureConflict? {
        val archiveInfo = readArchivePackageInfo(apkFile) ?: return null
        val targetPackageName = archiveInfo.packageName ?: return null
        if (targetPackageName == applicationContext.packageName) {
            return null
        }

        val installedInfo = findPackageInfoWithSignatures(targetPackageName) ?: return null
        val archiveSigners = signerDigests(archiveInfo, includeHistory = false)
        val installedSigners = signerDigests(installedInfo, includeHistory = true)

        if (archiveSigners.isEmpty() || installedSigners.isEmpty()) {
            return null
        }

        if (archiveSigners.any { it in installedSigners }) {
            return null
        }

        val appLabel = installedInfo.applicationInfo
            ?.loadLabel(packageManager)
            ?.toString()
            ?: targetPackageName

        return SignatureConflict(packageName = targetPackageName, appLabel = appLabel)
    }

    private fun showSignatureConflictDialog(conflict: SignatureConflict, apkFile: File) {
        if (isFinishing || isDestroyed) {
            return
        }

        AlertDialog.Builder(this)
            .setTitle("Hay que reinstalar ${conflict.appLabel}")
            .setMessage(
                "La nueva version de ${conflict.appLabel} viene firmada con otra llave, " +
                    "por eso Android no permite actualizarla encima de la actual.\n\n" +
                    "Para continuar se desinstalara la version instalada y despues se " +
                    "instalara la nueva. Los datos guardados en esa app dentro del " +
                    "telefono se perderan.",
            )
            .setPositiveButton("Desinstalar y continuar") { _, _ ->
                pendingReinstall = PendingReinstall(
                    packageName = conflict.packageName,
                    apkPath = apkFile.absolutePath,
                )
                val launch = uninstallApp(conflict.packageName)
                if (launch["status"] != "launchedUninstaller") {
                    pendingReinstall = null
                }
            }
            .setNegativeButton("Cancelar", null)
            .show()
    }

    private fun resumePendingReinstall() {
        val pending = pendingReinstall ?: return

        // The uninstall may still be finishing right after we come back; give it a moment.
        window.decorView.postDelayed({
            if (pendingReinstall != pending) {
                return@postDelayed
            }
            pendingReinstall = null

            if (findPackageInfo(pending.packageName) != null) {
                Log.i(TAG, "Uninstall of ${pending.packageName} was cancelled; skipping reinstall")
                return@postDelayed
            }

            Log.i(TAG, "Old ${pending.packageName} removed; installing ${pending.apkPath}")
            installApk(pending.apkPath)
        }, REINSTALL_CHECK_DELAY_MS)
    }

    private fun readArchivePackageInfo(apkFile: File): PackageInfo? {
        val path = apkFile.absolutePath
        val info = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageArchiveInfo(
                    path,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong()),
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageManager.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageArchiveInfo(path, PackageManager.GET_SIGNATURES)
            }
        } catch (error: Exception) {
            Log.w(TAG, "Could not read package info from ${apkFile.absolutePath}", error)
            null
        }

        info?.applicationInfo?.apply {
            sourceDir = path
            publicSourceDir = path
        }
        return info
    }

    private fun findPackageInfoWithSignatures(packageName: String): PackageInfo? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SIGNING_CERTIFICATES.toLong()),
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            }
        } catch (_: PackageManager.NameNotFoundException) {
            null
        } catch (_: SecurityException) {
            null
        }
    }

    private fun signerDigests(packageInfo: PackageInfo, includeHistory: Boolean): Set<String> {
        val signatures: Array<Signature>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val signingInfo = packageInfo.signingInfo ?: return emptySet()
            when {
                signingInfo.hasMultipleSigners() -> signingInfo.apkContentsSigners
                includeHistory -> signingInfo.signingCertificateHistory
                else -> signingInfo.signingCertificateHistory?.takeLast(1)?.toTypedArray()
            }
        } else {
            @Suppress("DEPRECATION")
            packageInfo.signatures
        }

        val digest = MessageDigest.getInstance("SHA-256")
        return signatures.orEmpty()
            .map { signature -> digest.digest(signature.toByteArray()).joinToString("") { "%02x".format(it) } }
            .toSet()
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
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 4102
        private const val REINSTALL_CHECK_DELAY_MS = 1200L
    }

    private data class SignatureConflict(
        val packageName: String,
        val appLabel: String,
    )

    private data class PendingReinstall(
        val packageName: String,
        val apkPath: String,
    )
}
