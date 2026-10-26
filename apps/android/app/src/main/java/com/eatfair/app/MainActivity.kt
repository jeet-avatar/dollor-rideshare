package com.eatfair.app

import android.animation.ObjectAnimator
import android.os.Bundle
import android.view.View
import android.view.animation.OvershootInterpolator
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.tooling.preview.Preview
import androidx.core.animation.doOnEnd
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.core.view.WindowCompat
import androidx.navigation.compose.rememberNavController
import com.eatfair.app.ui.navigation.NavigationGraph
import com.eatfair.app.ui.theme.DollorTheme
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import android.Manifest
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.lifecycleScope
import com.eatfair.shared.data.repository.DollorRepository
import com.google.firebase.messaging.FirebaseMessaging
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    var showSplashScreen = true

    @Inject lateinit var repository: DollorRepository

    private val notificationPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

    override fun onResume() {
        super.onResume()
        // Register after sign-in and whenever the app returns; the server upserts by user.
        FirebaseMessaging.getInstance().token.addOnSuccessListener { token ->
            lifecycleScope.launch { repository.registerPushToken(token) }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= 33) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)

        installSplashScreen().apply {
            setKeepOnScreenCondition { showSplashScreen }

            setOnExitAnimationListener { splashScreenView ->
                // Safely get iconView - can be null on some devices
                val iconView = splashScreenView.iconView
                if (iconView == null) {
                    splashScreenView.remove()
                    return@setOnExitAnimationListener
                }

                val zoomX = ObjectAnimator.ofFloat(
                    iconView,
                    View.SCALE_X, 0.5f, 0.0f
                )

                val zoomY = ObjectAnimator.ofFloat(
                    iconView,
                    View.SCALE_Y, 0.5f, 0.0f
                )
                zoomX.duration = 500L
                zoomY.duration = 500L

                zoomX.interpolator = OvershootInterpolator()
                zoomY.interpolator = OvershootInterpolator()

                zoomX.doOnEnd { splashScreenView.remove() }
                zoomY.doOnEnd { splashScreenView.remove() }

                zoomX.start()
                zoomY.start()

            }
        }

        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )

        WindowCompat.setDecorFitsSystemWindows(window, false)

        setContent {
            DollorTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    Box(modifier = Modifier.padding(innerPadding)) {
                        NavigationGraph()
                    }
                }
            }
        }

        CoroutineScope(Dispatchers.IO).launch {
            delay(2000)
            showSplashScreen = false
        }
    }
}