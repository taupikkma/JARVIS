#!/usr/bin/env bash
# ==============================================================================
# JARVIS.AI — Android Native APK & System-Wide Floating Overlay Builder
# ==============================================================================
# Skrip ini membungkus aplikasi web JARVIS.AI (index.html) menjadi proyek
# Android Studio / Gradle siap kompilasi (.apk) lengkap dengan:
#   1. SYSTEM_ALERT_WINDOW (Tampil di atas WhatsApp, TikTok, Instagram, dll.)
#   2. Foreground Service (START_STICKY — tetap hidup walau app ditutup)
#   3. Mascot Bola JARVIS.AI Draggable + Auto-Dock setengah badan ke tepi layar
#   4. Jembatan JavaScriptInterface (window.JarvisAndroidBridge)
# ==============================================================================

set -e

APP_NAME="JARVIS.AI"
APP_ID="com.jarvis.ai.detector"
PROJECT_DIR="jarvis-ai-android"

echo ">>> [1/6] Membuat struktur proyek Capacitor Android..."
mkdir -p "$PROJECT_DIR/www"
cd "$PROJECT_DIR"

# Salin file index.html hasil desain Anda ke folder www/
if [ -f "../index.html" ]; then
  cp "../index.html" "www/index.html"
else
  echo "PERINGATAN: Pastikan file index.html berada di folder yang sama sebelum menjalankan skrip ini."
fi

cat << 'EOF' > package.json
{
  "name": "jarvis-ai-android",
  "version": "1.0.0",
  "description": "JARVIS.AI Fact & Deepfake Detector with System-Wide Floating Mascot",
  "scripts": {
    "sync": "npx cap sync android",
    "build:apk": "cd android && ./gradlew assembleDebug"
  },
  "dependencies": {
    "@capacitor/android": "^6.0.0",
    "@capacitor/core": "^6.0.0"
  },
  "devDependencies": {
    "@capacitor/cli": "^6.0.0"
  }
}
EOF

cat << EOF > capacitor.config.json
{
  "appId": "$APP_ID",
  "appName": "$APP_NAME",
  "webDir": "www",
  "server": {
    "androidScheme": "https"
  },
  "android": {
    "allowMixedContent": true
  }
}
EOF

echo ">>> [2/6] Menginstal dependensi Capacitor & menambahkan platform Android..."
npm install
npx cap add android

JAVA_PKG_PATH="android/app/src/main/java/com/jarvis/ai/detector"
mkdir -p "$JAVA_PKG_PATH"

echo ">>> [3/6] Menulis AndroidManifest.xml dengan izin Overlay, Kamera, & Mikrofon..."
cat << 'EOF' > android/app/src/main/AndroidManifest.xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <!-- Izin Internet & Media untuk Gemini Multimodal API -->
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.RECORD_AUDIO" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />
    <uses-permission android:name="android.permission.READ_MEDIA_AUDIO" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32" />

    <!-- Izin Wajib agar Popup Bola Maskot Melayang di Atas Semua Aplikasi Lain -->
    <uses-permission android:name="android.permission.SYSTEM_ALERT_WINDOW" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="JARVIS.AI"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:supportsRtl="true"
        android:theme="@style/AppTheme"
        android:usesCleartextTraffic="true">

        <activity
            android:name=".MainActivity"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|locale|smallestScreenSize|screenLayout|uiMode"
            android:exported="true"
            android:launchMode="singleTask"
            android:theme="@style/AppTheme.NoActionBarLaunch">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <!-- Foreground Service agar Bola Maskot Tetap Hidup Walau App Ditutup -->
        <service
            android:name=".JarvisFloatingOverlayService"
            android:enabled="true"
            android:exported="false"
            android:foregroundServiceType="specialUse">
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="system_wide_ai_assistant_overlay" />
        </service>

    </application>
</manifest>
EOF

echo ">>> [4/6] Membuat JarvisFloatingOverlayService.kt (System-Wide Mascot Overlay)..."
cat << 'EOF' > "$JAVA_PKG_PATH/JarvisFloatingOverlayService.kt"
package com.jarvis.ai.detector

import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import androidx.core.app.NotificationCompat
import kotlin.math.hypot

class JarvisFloatingOverlayService : Service() {

    private lateinit var windowManager: WindowManager
    private var mascotView: JarvisMascotBubbleView? = null
    private lateinit var layoutParams: WindowManager.LayoutParams

    companion object {
        const val CHANNEL_ID = "jarvis_overlay_channel"
        const val NOTIF_ID = 1001
        const val ACTION_OPEN_FEATURE = "com.jarvis.ai.detector.OPEN_FEATURE"
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        startForegroundNotification()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            stopSelf()
            return
        }

        setupFloatingMascot()
    }

    private fun startForegroundNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "JARVIS.AI Asisten Mengambang",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Menjaga bola asisten JARVIS.AI aktif di atas aplikasi lain"
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }

        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("JARVIS.AI Aktif")
            .setContentText("Ketuk bola mengambang di tepi layar untuk validasi berita & AI.")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notification)
    }

    private fun setupFloatingMascot() {
        val density = resources.displayMetrics.density
        val sizePx = (64 * density).toInt()
        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels

        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        layoutParams = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // Default bersembunyi setengah badan di sisi kanan layar
            x = screenWidth - (sizePx / 2)
            y = (screenHeight * 0.72f).toInt()
        }

        mascotView = JarvisMascotBubbleView(this).apply {
            isDockedRight = true
        }

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false

        mascotView?.setOnTouchListener { view, event ->
            val currentScreenWidth = resources.displayMetrics.widthPixels
            val currentScreenHeight = resources.displayMetrics.heightPixels

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams.x
                    initialY = layoutParams.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    // Keluarkan maskot penuh saat disentuh
                    mascotView?.isDockedLeft = false
                    mascotView?.isDockedRight = false
                    mascotView?.invalidate()
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (!isDragging && hypot(dx.toDouble(), dy.toDouble()) > 12.0) {
                        isDragging = true
                    }
                    if (isDragging) {
                        mascotView?.isMoving = true
                        mascotView?.eyeOffsetX = (dx * 0.08f).coerceIn(-10f, 10f)
                        mascotView?.eyeOffsetY = (dy * 0.08f).coerceIn(-8f, 8f)
                        layoutParams.x = (initialX + dx.toInt()).coerceIn(0, currentScreenWidth - sizePx)
                        layoutParams.y = (initialY + dy.toInt()).coerceIn(80, currentScreenHeight - sizePx - 120)
                        windowManager.updateViewLayout(view, layoutParams)
                        mascotView?.invalidate()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    mascotView?.isMoving = false
                    mascotView?.eyeOffsetX = 0f
                    mascotView?.eyeOffsetY = 0f

                    if (isDragging) {
                        // Snap ke sisi layar terdekat & bersembunyi setengah badan
                        val centerX = layoutParams.x + sizePx / 2
                        val snapToLeft = centerX < currentScreenWidth / 2
                        val targetX = if (snapToLeft) -(sizePx / 2) else currentScreenWidth - (sizePx / 2)

                        mascotView?.isDockedLeft = snapToLeft
                        mascotView?.isDockedRight = !snapToLeft
                        animateSnapX(layoutParams.x, targetX)
                    } else {
                        // Ketuk singkat -> Buka Menu Cepat JARVIS.AI di atas aplikasi lain
                        val launchIntent = Intent(this@JarvisFloatingOverlayService, MainActivity::class.java).apply {
                            action = ACTION_OPEN_FEATURE
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        }
                        startActivity(launchIntent)
                    }
                    true
                }
                else -> false
            }
        }

        windowManager.addView(mascotView, layoutParams)
    }

    private fun animateSnapX(fromX: Int, toX: Int) {
        ValueAnimator.ofInt(fromX, toX).apply {
            duration = 280
            interpolator = DecelerateInterpolator()
            addUpdateListener { anim ->
                layoutParams.x = anim.animatedValue as Int
                mascotView?.let { windowManager.updateViewLayout(it, layoutParams) }
            }
            start()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_STICKY memastikan service dihidupkan ulang sistem jika aplikasi utama ditutup
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        mascotView?.let {
            if (it.isAttachedToWindow) windowManager.removeView(it)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Custom Canvas View untuk Maskot JARVIS.AI (Lingkaran Biru + 2 Mata Putih Vertikal)
     */
    private class JarvisMascotBubbleView(context: Context) : View(context) {
        var isDockedRight = false
        var isDockedLeft = false
        var isMoving = false
        var eyeOffsetX = 0f
        var eyeOffsetY = 0f

        private val outerRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#0B1E40")
            style = Paint.Style.FILL
        }
        private val innerCirclePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.parseColor("#1665FF")
            style = Paint.Style.FILL
        }
        private val eyePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
        }
        private val eyeRect = RectF()

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val cx = width / 2f
            val cy = height / 2f
            val outerRadius = minOf(cx, cy)
            val innerRadius = outerRadius * 0.82f

            canvas.drawCircle(cx, cy, outerRadius, outerRingPaint)
            canvas.drawCircle(cx, cy, innerRadius, innerCirclePaint)

            val peekShift = when {
                isDockedRight -> -outerRadius * 0.24f
                isDockedLeft -> outerRadius * 0.24f
                else -> 0f
            }

            val eyeWidth = outerRadius * 0.28f
            val eyeHeight = outerRadius * 0.62f
            val eyeGap = outerRadius * 0.20f
            val cornerRadius = eyeWidth / 2f

            val leftEyeCenterX = cx - (eyeGap / 2f) - (eyeWidth / 2f) + peekShift + eyeOffsetX
            val rightEyeCenterX = cx + (eyeGap / 2f) + (eyeWidth / 2f) + peekShift + eyeOffsetX
            val eyeCenterY = cy + eyeOffsetY

            eyeRect.set(
                leftEyeCenterX - eyeWidth / 2f,
                eyeCenterY - eyeHeight / 2f,
                leftEyeCenterX + eyeWidth / 2f,
                eyeCenterY + eyeHeight / 2f
            )
            canvas.drawRoundRect(eyeRect, cornerRadius, cornerRadius, eyePaint)

            eyeRect.set(
                rightEyeCenterX - eyeWidth / 2f,
                eyeCenterY - eyeHeight / 2f,
                rightEyeCenterX + eyeWidth / 2f,
                eyeCenterY + eyeHeight / 2f
            )
            canvas.drawRoundRect(eyeRect, cornerRadius, cornerRadius, eyePaint)
        }
    }
}
EOF

echo ">>> [5/6] Menghubungkan MainActivity.java dengan window.JarvisAndroidBridge..."
cat << 'EOF' > "$JAVA_PKG_PATH/MainActivity.java"
package com.jarvis.ai.detector;

import android.Manifest;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.provider.Settings;
import android.webkit.JavascriptInterface;
import android.webkit.PermissionRequest;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

    private static final int REQ_OVERLAY_PERMISSION = 5001;
    private static final int REQ_MEDIA_PERMISSIONS = 5002;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        requestRuntimeMediaPermissions();

        WebView webView = getBridge().getWebView();
        webView.getSettings().setJavaScriptEnabled(true);
        webView.getSettings().setDomStorageEnabled(true);
        webView.getSettings().setMediaPlaybackRequiresUserGesture(false);

        // Jembatan langsung antara tombol toggle Popup di Web UI dengan Service Android
        webView.addJavascriptInterface(new JarvisAndroidBridge(), "JarvisAndroidBridge");

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onPermissionRequest(final PermissionRequest request) {
                runOnUiThread(() -> request.grant(request.getResources()));
            }
        });

        handleIncomingOverlayIntent(getIntent());
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        handleIncomingOverlayIntent(intent);
    }

    private void handleIncomingOverlayIntent(Intent intent) {
        if (intent != null && JarvisFloatingOverlayService.ACTION_OPEN_FEATURE.equals(intent.getAction())) {
            WebView webView = getBridge().getWebView();
            if (webView != null) {
                webView.post(() -> webView.evaluateJavascript("if (window.openFloatingMenu) window.openFloatingMenu();", null));
            }
        }
    }

    private void requestRuntimeMediaPermissions() {
        String[] perms = new String[]{
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.CAMERA
        };
        boolean needsRequest = false;
        for (String p : perms) {
            if (ContextCompat.checkSelfPermission(this, p) != PackageManager.PERMISSION_GRANTED) {
                needsRequest = true;
            }
        }
        if (needsRequest) {
            ActivityCompat.requestPermissions(this, perms, REQ_MEDIA_PERMISSIONS);
        }
    }

    public class JarvisAndroidBridge {
        @JavascriptInterface
        public void requestOverlayPermission() {
            runOnUiThread(() -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(MainActivity.this)) {
                    Intent intent = new Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:" + getPackageName())
                    );
                    startActivityForResult(intent, REQ_OVERLAY_PERMISSION);
                }
            });
        }

        @JavascriptInterface
        public void startFloatingOverlayService(String configJson) {
            runOnUiThread(() -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(MainActivity.this)) {
                    requestOverlayPermission();
                    return;
                }
                Intent serviceIntent = new Intent(MainActivity.this, JarvisFloatingOverlayService.class);
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent);
                } else {
                    startService(serviceIntent);
                }
            });
        }

        @JavascriptInterface
        public void stopFloatingOverlayService() {
            runOnUiThread(() -> {
                Intent serviceIntent = new Intent(MainActivity.this, JarvisFloatingOverlayService.class);
                stopService(serviceIntent);
            });
        }
    }
}
EOF

echo ">>> [6/6] Sinkronisasi aset web ke proyek Android..."
npx cap sync android

echo "=============================================================================="
echo "SELESAI! Proyek Android siap dikompilasi menjadi file .APK"
echo "Langkah selanjutnya untuk menghasilkan file APK:"
echo "  1. Pastikan JDK 17 & Android SDK terpasang, lalu jalankan:"
echo "     cd $PROJECT_DIR/android && ./gradlew assembleDebug"
echo "  2. File APK siap instal akan tersedia di:"
echo "     $PROJECT_DIR/android/app/build/outputs/apk/debug/app-debug.apk"
echo "=============================================================================="