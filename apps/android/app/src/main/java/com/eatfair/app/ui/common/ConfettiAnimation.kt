package com.eatfair.app.ui.common

import com.eatfair.shared.ui.Lx
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.rotate
import com.eatfair.shared.model.ConfettiParticle
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlin.random.Random

@Composable
fun ConfettiAnimation() {
    val confettiColors = listOf(
        Lx.OrangeDeep,
        Lx.Success,
        Lx.Orange,
        Lx.Gold,
        Lx.OrangeBright,
        Lx.Gold
    )

    var particles by remember {
        mutableStateOf(
            List(50) {
                ConfettiParticle(
                    x = Random.nextFloat(),
                    y = -0.1f - Random.nextFloat() * 0.3f,
                    size = Random.nextFloat() * 10f + 5f,
                    color = confettiColors.random(),
                    rotation = Random.nextFloat() * 360f,
                    velocity = Random.nextFloat() * 2f + 1f
                )
            }
        )
    }

    LaunchedEffect(Unit) {
        while (isActive) {
            delay(16) // ~60 FPS
            particles = particles.map { particle ->
                val newY = particle.y + particle.velocity * 0.01f
                if (newY > 1.2f) {
                    // Reset particle to top
                    particle.copy(
                        y = -0.1f,
                        x = Random.nextFloat()
                    )
                } else {
                    particle.copy(
                        y = newY,
                        rotation = particle.rotation + 5f
                    )
                }
            }
        }
    }

    Canvas(modifier = Modifier.fillMaxSize()) {
        particles.forEach { particle ->
            val x = particle.x * size.width
            val y = particle.y * size.height

            rotate(particle.rotation, Offset(x, y)) {
                drawCircle(
                    color = particle.color,
                    radius = particle.size,
                    center = Offset(x, y)
                )
            }
        }
    }
}
