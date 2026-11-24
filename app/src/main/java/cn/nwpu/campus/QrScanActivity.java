package cn.nwpu.campus;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ImageFormat;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.SurfaceTexture;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.media.Image;
import android.media.ImageReader;
import android.os.Bundle;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Size;
import android.view.Gravity;
import android.view.Surface;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.TextView;
import android.widget.Toast;

import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.ReaderException;
import com.google.zxing.PlanarYUVLuminanceSource;
import com.google.zxing.Reader;
import com.google.zxing.Result;
import com.google.zxing.common.HybridBinarizer;

import java.nio.ByteBuffer;
import java.util.Collections;
import java.util.EnumMap;
import java.util.Map;

/**
 * 扫码导入课表：Camera2 预览 + ImageReader(YUV_420_888) 采集 + ZXing core
 * 解码。只识别二维码，识别成功后把文本 setResult 返回给调用方解析；
 * 内容格式与压缩约定见 MainActivity.applyBackupText。
 */
public class QrScanActivity extends Activity {
    /** 解码帧间隔，避免连续图像堆积拖慢预览。 */
    private static final long DECODE_INTERVAL_MS = 120L;
    private static final int MAX_SCAN_EDGE = 720;

    private TextureView previewView;
    private HandlerThread decodeThread;
    private Handler decodeHandler;
    private final Reader reader = new MultiFormatReader();
    private final Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);

    private CameraDevice camera;
    private CameraCaptureSession session;
    private ImageReader imageReader;
    private Size previewSize;
    private Size captureSize;
    private long lastDecodeAt;
    private boolean closed;

    @SuppressLint("MissingPermission")
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        if (checkSelfPermission(Manifest.permission.CAMERA)
                != PackageManager.PERMISSION_GRANTED) {
            finishWithResult(null);
            return;
        }
        hints.put(DecodeHintType.POSSIBLE_FORMATS,
                Collections.singletonList(com.google.zxing.BarcodeFormat.QR_CODE));
        hints.put(DecodeHintType.TRY_HARDER, Boolean.TRUE);
        decodeThread = new HandlerThread("AoxiangQrDecode");
        decodeThread.start();
        decodeHandler = new Handler(decodeThread.getLooper());
        buildContent();
        openCamera();
    }

    private void buildContent() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);

        previewView = new TextureView(this);
        root.addView(previewView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        previewView.setSurfaceTextureListener(new TextureView.SurfaceTextureListener() {
            @Override public void onSurfaceTextureAvailable(SurfaceTexture texture,
                    int width, int height) {
                startSession();
            }

            @Override public void onSurfaceTextureSizeChanged(SurfaceTexture texture,
                    int width, int height) {}

            @Override public boolean onSurfaceTextureDestroyed(SurfaceTexture texture) {
                return true;
            }

            @Override public void onSurfaceTextureUpdated(SurfaceTexture texture) {}
        });

        root.addView(new ScanOverlayView(this), new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        Button cancel = new Button(this);
        cancel.setText("取消");
        cancel.setTextColor(Color.WHITE);
        cancel.getBackground().setAlpha(0);
        FrameLayout.LayoutParams cancelParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.END);
        cancelParams.setMargins(0, dp(36), dp(20), 0);
        cancel.setOnClickListener(v -> finishWithResult(null));
        root.addView(cancel, cancelParams);

        TextView hint = new TextView(this);
        hint.setText("对准课表二维码即可自动导入");
        hint.setTextColor(Color.WHITE);
        hint.setTextSize(14);
        hint.setGravity(Gravity.CENTER);
        FrameLayout.LayoutParams hintParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL);
        hintParams.setMargins(0, 0, 0, dp(64));
        root.addView(hint, hintParams);

        setContentView(root);
    }

    private void openCamera() {
        CameraManager manager = (CameraManager) getSystemService(Context.CAMERA_SERVICE);
        try {
            String cameraId = null;
            CameraCharacteristics characteristics = null;
            for (String id : manager.getCameraIdList()) {
                CameraCharacteristics candidate = manager.getCameraCharacteristics(id);
                Integer facing = candidate.get(CameraCharacteristics.LENS_FACING);
                if (facing != null && facing == CameraCharacteristics.LENS_FACING_BACK) {
                    cameraId = id;
                    characteristics = candidate;
                    break;
                }
            }
            if (cameraId == null || characteristics == null) {
                Toast.makeText(this, "未找到可用的后置摄像头", Toast.LENGTH_LONG).show();
                finishWithResult(null);
                return;
            }
            android.hardware.camera2.params.StreamConfigurationMap map =
                    characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            captureSize = chooseSize(
                    map.getOutputSizes(ImageFormat.YUV_420_888));
            previewSize = chooseSize(
                    map.getOutputSizes(SurfaceTexture.class));
            imageReader = ImageReader.newInstance(captureSize.getWidth(),
                    captureSize.getHeight(), ImageFormat.YUV_420_888, 2);
            imageReader.setOnImageAvailableListener(this::onImageAvailable,
                    decodeHandler);
            manager.openCamera(cameraId, new CameraDevice.StateCallback() {
                @Override public void onOpened(CameraDevice device) {
                    camera = device;
                    startSession();
                }

                @Override public void onDisconnected(CameraDevice device) {
                    device.close();
                }

                @Override public void onError(CameraDevice device, int error) {
                    device.close();
                    Toast.makeText(QrScanActivity.this, "相机启动失败", Toast.LENGTH_LONG).show();
                    finishWithResult(null);
                }
            }, decodeHandler);
        } catch (Exception error) {
            Toast.makeText(this, "相机启动失败", Toast.LENGTH_LONG).show();
            finishWithResult(null);
        }
    }

    /** 选择最接近 720p 的采集尺寸与同宽高比最接近屏幕的预览尺寸，降低解码负担。 */
    private Size chooseSize(Size[] sizes) {
        Size best = sizes[0];
        long bestGap = Long.MAX_VALUE;
        for (Size size : sizes) {
            long gap = Math.abs((long) size.getWidth() * size.getHeight()
                    - (long) MAX_SCAN_EDGE * 1280);
            if (gap < bestGap) {
                bestGap = gap;
                best = size;
            }
        }
        return best;
    }

    private synchronized void startSession() {
        if (closed || camera == null || previewView == null
                || !previewView.isAvailable() || imageReader == null) return;
        try {
            SurfaceTexture texture = previewView.getSurfaceTexture();
            texture.setDefaultBufferSize(previewSize.getWidth(), previewSize.getHeight());
            Surface previewSurface = new Surface(texture);
            camera.createCaptureSession(java.util.Arrays.asList(
                    previewSurface, imageReader.getSurface()),
                    new CameraCaptureSession.StateCallback() {
                        @Override public void onConfigured(CameraCaptureSession configured) {
                            session = configured;
                            try {
                                CaptureRequest.Builder request = camera.createCaptureRequest(
                                        CameraDevice.TEMPLATE_PREVIEW);
                                request.addTarget(previewSurface);
                                request.addTarget(imageReader.getSurface());
                                request.set(CaptureRequest.CONTROL_AF_MODE,
                                        CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
                                session.setRepeatingRequest(request.build(), null, decodeHandler);
                            } catch (Exception ignored) {
                            }
                        }

                        @Override public void onConfigureFailed(CameraCaptureSession session) {
                            Toast.makeText(QrScanActivity.this, "相机预览失败",
                                    Toast.LENGTH_LONG).show();
                        }
                    }, decodeHandler);
        } catch (Exception ignored) {
        }
    }

    private void onImageAvailable(ImageReader reader) {
        Image image = null;
        try {
            image = reader.acquireLatestImage();
            if (image == null) return;
            long now = System.currentTimeMillis();
            if (now - lastDecodeAt < DECODE_INTERVAL_MS) return;
            lastDecodeAt = now;
            Result result = decode(image);
            if (result != null) {
                finishWithResult(result.getText());
            }
        } catch (Exception ignored) {
        } finally {
            if (image != null) image.close();
        }
    }

    /**
     * Y 平面按行提取后旋转为竖屏方向，再取中央与取景框一致的方形区域，
     * 交给 ZXing 以二维码格式解码。
     */
    private Result decode(Image image) {
        Image.Plane plane = image.getPlanes()[0];
        ByteBuffer buffer = plane.getBuffer();
        int width = image.getWidth();
        int height = image.getHeight();
        int rowStride = plane.getRowStride();
        byte[] rotated = new byte[width * height];
        for (int row = 0; row < height; row++) {
            for (int column = 0; column < width; column++) {
                // 竖屏显示时顺时针旋转 90 度：旋转后 (column, row) <- 原 (row, 宽-1-column)。
                rotated[column * height + (height - 1 - row)] =
                        buffer.get(row * rowStride + column);
            }
        }
        int rotatedWidth = height;
        int rotatedHeight = width;
        int edge = Math.min(rotatedWidth, Math.min(rotatedHeight, MAX_SCAN_EDGE));
        int left = (rotatedWidth - edge) / 2;
        int top = (rotatedHeight - edge) / 2;
        PlanarYUVLuminanceSource source = new PlanarYUVLuminanceSource(
                rotated, rotatedWidth, rotatedHeight, left, top, edge, edge, false);
        try {
            return reader.decode(new BinaryBitmap(new HybridBinarizer(source)), hints);
        } catch (ReaderException ignored) {
            // NotFoundException / ChecksumException / FormatException 都表示本帧不可读。
            return null;
        } finally {
            reader.reset();
        }
    }

    private void finishWithResult(String text) {
        closed = true;
        Intent intent = new Intent();
        if (text != null) intent.putExtra("qr_text", text);
        setResult(text == null ? RESULT_CANCELED : RESULT_OK, intent);
        finish();
    }

    @Override protected void onDestroy() {
        closed = true;
        if (session != null) {
            try {
                session.close();
            } catch (Exception ignored) {}
            session = null;
        }
        if (camera != null) {
            camera.close();
            camera = null;
        }
        if (imageReader != null) {
            imageReader.close();
            imageReader = null;
        }
        if (decodeThread != null) {
            decodeThread.quitSafely();
            decodeThread = null;
        }
        super.onDestroy();
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    /** 半透明遮罩与中央取景框，全代码绘制，与项目无 XML 布局的风格一致。 */
    private static final class ScanOverlayView extends View {
        private final Paint mask = new Paint();
        private final Paint frame = new Paint();

        ScanOverlayView(Context context) {
            super(context);
            mask.setColor(0x88000000);
            frame.setColor(Color.WHITE);
            frame.setStyle(Paint.Style.STROKE);
            frame.setStrokeWidth(4);
        }

        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            int width = getWidth();
            int height = getHeight();
            int edge = Math.min(width, height) * 2 / 3;
            int left = (width - edge) / 2;
            int top = (height - edge) / 2;
            Rect hole = new Rect(left, top, left + edge, top + edge);
            canvas.drawRect(0, 0, width, hole.top, mask);
            canvas.drawRect(0, hole.bottom, width, height, mask);
            canvas.drawRect(0, hole.top, hole.left, hole.bottom, mask);
            canvas.drawRect(hole.right, hole.top, width, hole.bottom, mask);
            // 四角白色括号标记取景区域。
            float corner = edge / 6f;
            canvas.drawLine(hole.left, hole.top, hole.left + corner, hole.top, frame);
            canvas.drawLine(hole.left, hole.top, hole.left, hole.top + corner, frame);
            canvas.drawLine(hole.right - corner, hole.top, hole.right, hole.top, frame);
            canvas.drawLine(hole.right, hole.top, hole.right, hole.top + corner, frame);
            canvas.drawLine(hole.left, hole.bottom, hole.left + corner, hole.bottom, frame);
            canvas.drawLine(hole.left, hole.bottom - corner, hole.left, hole.bottom, frame);
            canvas.drawLine(hole.right - corner, hole.bottom, hole.right, hole.bottom, frame);
            canvas.drawLine(hole.right, hole.bottom - corner, hole.right, hole.bottom, frame);
        }
    }
}
