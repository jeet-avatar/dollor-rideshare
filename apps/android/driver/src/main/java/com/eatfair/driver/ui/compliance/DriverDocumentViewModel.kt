package com.eatfair.driver.ui.compliance

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.ExifInterface
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.eatfair.shared.data.repository.DollorRepository
import com.eatfair.shared.model.DriverDocumentsStatus
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.RequestBody.Companion.asRequestBody
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import javax.inject.Inject
import kotlin.math.max

/**
 * Drives the driver's license + insurance photo capture steps of onboarding.
 *
 * Mirrors iOS's DriverOnboardingViewModel.upload(documentType:imageData:) and
 * DocumentCaptureView — same backend contract (POST/GET /api/auth/driver/documents,
 * see DollorRepository.uploadDriverDocument / getDriverDocumentsStatus), same
 * "camera or library, then resize to <=2000px JPEG before upload" behavior.
 */
@HiltViewModel
class DriverDocumentViewModel @Inject constructor(
    private val repository: DollorRepository
) : ViewModel() {

    data class UiState(
        val isLoadingStatus: Boolean = true,
        /** True when the status request failed: the uploaded flags are unknown, not "not uploaded". */
        val statusFailed: Boolean = false,
        val licenseUploaded: Boolean = false,
        val insuranceUploaded: Boolean = false,
        val uploadingType: String? = null,
        val error: String? = null
    )

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        refreshStatus()
    }

    fun refreshStatus() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoadingStatus = true, statusFailed = false) }
            repository.getDriverDocumentsStatus()
                .onSuccess { response ->
                    applyStatus(response.documents)
                }
                .onFailure {
                    // Unknown is not "not uploaded": the screen offers a retry instead of dropping a
                    // verified driver onto the onboarding steps (e.g. after a slow relaunch).
                    _uiState.update { it.copy(isLoadingStatus = false, statusFailed = true) }
                }
        }
    }

    private fun applyStatus(documents: DriverDocumentsStatus) {
        _uiState.update {
            it.copy(
                isLoadingStatus = false,
                licenseUploaded = documents.driversLicense.uploaded,
                insuranceUploaded = documents.insurance.uploaded
            )
        }
    }

    /**
     * Resizes/compresses the captured image (max 2000px on the long side, JPEG quality 85 —
     * matching iOS's `UIImage.resizedForDocumentUpload()`) and uploads it as [documentType]
     * ("drivers_license" | "insurance" | "vehicle_registration").
     */
    fun upload(context: Context, uri: Uri, documentType: String) {
        if (_uiState.value.uploadingType != null) return
        viewModelScope.launch {
            _uiState.update { it.copy(uploadingType = documentType, error = null) }

            val file = withContext(Dispatchers.IO) { prepareUploadFile(context, uri, documentType) }
            if (file == null) {
                _uiState.update { it.copy(uploadingType = null, error = "Couldn't read that photo. Please try again.") }
                return@launch
            }

            val requestFile = file.asRequestBody("image/jpeg".toMediaTypeOrNull())
            val filePart = MultipartBody.Part.createFormData("file", file.name, requestFile)

            repository.uploadDriverDocument(filePart, documentType)
                .onSuccess {
                    when (documentType) {
                        "drivers_license" -> _uiState.update { it.copy(licenseUploaded = true) }
                        "insurance" -> _uiState.update { it.copy(insuranceUploaded = true) }
                    }
                    _uiState.update { it.copy(uploadingType = null) }
                }
                .onFailure { e ->
                    _uiState.update { it.copy(uploadingType = null, error = e.message ?: "Upload failed. Please try again.") }
                }

            file.delete()
        }
    }

    fun clearError() {
        _uiState.update { it.copy(error = null) }
    }

    /** Decodes [uri], applies its EXIF rotation, downscales to [maxDimension] and writes a JPEG temp file. */
    private fun prepareUploadFile(context: Context, uri: Uri, prefix: String, maxDimension: Int = 2000): File? {
        return try {
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return null

            val orientation = context.contentResolver.openInputStream(uri)?.use { stream ->
                ExifInterface(stream).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL
                )
            } ?: ExifInterface.ORIENTATION_NORMAL

            val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
            val rotated = applyExifRotation(decoded, orientation)

            val longerSide = max(rotated.width, rotated.height)
            val resized = if (longerSide > maxDimension) {
                val scale = maxDimension.toFloat() / longerSide
                Bitmap.createScaledBitmap(
                    rotated,
                    (rotated.width * scale).toInt(),
                    (rotated.height * scale).toInt(),
                    true
                )
            } else {
                rotated
            }

            val outputStream = ByteArrayOutputStream()
            resized.compress(Bitmap.CompressFormat.JPEG, 85, outputStream)

            val file = File(context.cacheDir, "${prefix}_${System.currentTimeMillis()}.jpg")
            FileOutputStream(file).use { it.write(outputStream.toByteArray()) }
            file
        } catch (e: Exception) {
            null
        }
    }

    private fun applyExifRotation(bitmap: Bitmap, orientation: Int): Bitmap {
        val matrix = android.graphics.Matrix()
        when (orientation) {
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
            else -> return bitmap
        }
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
    }
}
