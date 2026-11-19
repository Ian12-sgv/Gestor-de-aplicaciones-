package com.company.corporateappstore.corporate_app_store

import android.app.DownloadManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import java.io.File

class ApkDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) {
            return
        }

        val downloadId = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
        if (downloadId < 0) {
            return
        }

        val record = DownloadQueueStore.readDownload(context, downloadId) ?: return
        val downloadManager =
            context.getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
                ?: return

        val query = DownloadManager.Query().setFilterById(downloadId)
        val cursor = downloadManager.query(query) ?: return

        cursor.use {
            if (!it.moveToFirst()) {
                return
            }

            val status = it.getInt(it.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            if (status == DownloadManager.STATUS_SUCCESSFUL && File(record.filePath).exists()) {
                DownloadQueueStore.markReadyForInstall(context, record)
                DownloadQueueStore.removeDownload(context, downloadId)
                ApkDownloadNotifications.showReadyToInstall(context, record)
                return
            }

            if (status == DownloadManager.STATUS_FAILED) {
                DownloadQueueStore.removeDownload(context, downloadId)
                ApkDownloadNotifications.showDownloadFailed(context, record.appName)
            }
        }
    }

    companion object {
        const val ACTION_INSTALL_DOWNLOADED_APK =
            "com.company.corporateappstore.corporate_app_store.INSTALL_DOWNLOADED_APK"
        const val EXTRA_APK_PATH = "apkPath"
    }
}

class PackageInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val packageName = intent.data?.schemeSpecificPart.orEmpty()
        if (packageName.isBlank()) {
            return
        }

        val appName = DownloadQueueStore.consumeReadyForInstall(context, packageName) ?: return
        ApkDownloadNotifications.showInstalled(context, appName)
    }
}

internal data class DownloadRecord(
    val downloadId: Long,
    val filePath: String,
    val appName: String,
    val packageName: String,
)

internal object DownloadQueueStore {
    private const val PREFERENCES_NAME = "corporate_store_downloads"
    private const val DOWNLOAD_PREFIX = "download."
    private const val READY_PREFIX = "ready."

    fun saveDownload(
        context: Context,
        downloadId: Long,
        filePath: String,
        appName: String,
        packageName: String,
    ) {
        preferences(context).edit()
            .putString("$DOWNLOAD_PREFIX$downloadId.path", filePath)
            .putString("$DOWNLOAD_PREFIX$downloadId.name", appName)
            .putString("$DOWNLOAD_PREFIX$downloadId.package", packageName)
            .apply()
    }

    fun readDownload(context: Context, downloadId: Long): DownloadRecord? {
        val preferences = preferences(context)
        val filePath = preferences.getString("$DOWNLOAD_PREFIX$downloadId.path", null)
        val appName = preferences.getString("$DOWNLOAD_PREFIX$downloadId.name", null)
        val packageName = preferences.getString("$DOWNLOAD_PREFIX$downloadId.package", null)

        if (filePath.isNullOrBlank() || appName.isNullOrBlank() || packageName.isNullOrBlank()) {
            return null
        }

        return DownloadRecord(
            downloadId = downloadId,
            filePath = filePath,
            appName = appName,
            packageName = packageName,
        )
    }

    fun removeDownload(context: Context, downloadId: Long) {
        preferences(context).edit()
            .remove("$DOWNLOAD_PREFIX$downloadId.path")
            .remove("$DOWNLOAD_PREFIX$downloadId.name")
            .remove("$DOWNLOAD_PREFIX$downloadId.package")
            .apply()
    }

    fun markReadyForInstall(context: Context, record: DownloadRecord) {
        preferences(context).edit()
            .putString("$READY_PREFIX${record.packageName}", record.appName)
            .apply()
    }

    fun consumeReadyForInstall(context: Context, packageName: String): String? {
        val preferences = preferences(context)
        val appName = preferences.getString("$READY_PREFIX$packageName", null)
        if (appName != null) {
            preferences.edit().remove("$READY_PREFIX$packageName").apply()
        }
        return appName
    }

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
}

internal object ApkDownloadNotifications {
    private const val CHANNEL_ID = "apk_downloads"
    private const val CHANNEL_NAME = "Descargas de aplicaciones"
    private const val READY_NOTIFICATION_OFFSET = 10000
    private const val INSTALLED_NOTIFICATION_OFFSET = 20000

    fun showReadyToInstall(context: Context, record: DownloadRecord) {
        val installIntent = Intent(context, MainActivity::class.java).apply {
            action = ApkDownloadReceiver.ACTION_INSTALL_DOWNLOADED_APK
            putExtra(ApkDownloadReceiver.EXTRA_APK_PATH, record.filePath)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            context,
            record.downloadId.hashCode(),
            installIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        notify(
            context = context,
            notificationId = record.downloadId.hashCode() + READY_NOTIFICATION_OFFSET,
            title = "APK descargada",
            text = "${record.appName} esta lista para instalar. Toca aqui para continuar.",
            pendingIntent = pendingIntent,
        )
    }

    fun cancelReadyToInstall(context: Context, downloadId: Long) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(downloadId.hashCode() + READY_NOTIFICATION_OFFSET)
    }

    fun showDownloadFailed(context: Context, appName: String) {
        notify(
            context = context,
            notificationId = appName.hashCode() + READY_NOTIFICATION_OFFSET,
            title = "No se pudo descargar la aplicacion",
            text = "La descarga de $appName no se completo. Vuelve a intentarlo desde PDBStore.",
            pendingIntent = launchAppPendingIntent(context),
        )
    }

    fun showInstalled(context: Context, appName: String) {
        notify(
            context = context,
            notificationId = appName.hashCode() + INSTALLED_NOTIFICATION_OFFSET,
            title = "Aplicacion instalada",
            text = "$appName se instalo correctamente.",
            pendingIntent = launchAppPendingIntent(context),
        )
    }

    private fun launchAppPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notify(
        context: Context,
        notificationId: Int,
        title: String,
        text: String,
        pendingIntent: PendingIntent,
    ) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        ensureChannel(notificationManager)

        val builder =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(context, CHANNEL_ID)
            } else {
                Notification.Builder(context)
            }

        notificationManager.notify(
            notificationId,
            builder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(text)
                .setStyle(Notification.BigTextStyle().bigText(text))
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .setPriority(Notification.PRIORITY_HIGH)
                .build(),
        )
    }

    private fun ensureChannel(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        notificationManager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }
}

