package app.napstop.core.alarm.ring.view

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityNodeInfo
import androidx.core.view.ViewCompat
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
import app.napstop.core.alarm.SwipeRule

/**
 * "Vuốt hết thanh để tắt" (spec T16 §5.8): track #262A33 72dp, round thumb #FF9F43, hint text. Released at
 * SwipeRule.isComplete → [onComplete]; otherwise it slides back (200 ms; at once with reduced motion). TalkBack: the
 * click action (double tap) stops the alarm, labelled with [a11yLabel].
 */
@SuppressLint("ViewConstructor")
class SwipeToDismissView(
    context: Context,
    private val hint: String,
    a11yLabel: String,
    typeface: Typeface?,
    private val onComplete: () -> Unit,
) : View(context) {
    private val density = resources.displayMetrics.density
    private val heightPx = (72 * density).toInt()
    private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFF262A33.toInt() }
    private val thumbPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFFF9F43.toInt() }
    private val arrowPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFF0F1115.toInt()
            style = Paint.Style.STROKE
            strokeWidth = 3 * density
            strokeCap = Paint.Cap.ROUND
        }
    private val textPaint =
        Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = 0xFFFFFFFF.toInt()
            textAlign = Paint.Align.CENTER
            textSize = 17 * resources.displayMetrics.scaledDensity
            this.typeface = typeface ?: Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
    private val rect = RectF()
    private val arrow = Path()
    private var thumbX = 0f
    private var dragStart = 0f
    private var dragging = false
    private var done = false
    private var back: ValueAnimator? = null

    init {
        contentDescription = a11yLabel
        isFocusable = true
        isClickable = true
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_YES
        ViewCompat.replaceAccessibilityAction(this, AccessibilityNodeInfoCompat.AccessibilityActionCompat.ACTION_CLICK, a11yLabel) { _, _ ->
            complete()
            true
        }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        setMeasuredDimension(MeasureSpec.getSize(widthMeasureSpec), heightPx)
    }

    private val thumbSize: Float get() = height.toFloat()

    override fun onDraw(canvas: Canvas) {
        val h = height.toFloat()
        rect.set(0f, 0f, width.toFloat(), h)
        canvas.drawRoundRect(rect, h / 2, h / 2, trackPaint)
        val y = h / 2 - (textPaint.descent() + textPaint.ascent()) / 2
        canvas.drawText(hint, (width + thumbSize) / 2f, y, textPaint)
        val inset = 6 * density
        val cx = thumbX + h / 2
        canvas.drawCircle(cx, h / 2, h / 2 - inset, thumbPaint)
        val a = 8 * density
        arrow.reset()
        arrow.moveTo(cx - a / 2, h / 2 - a)
        arrow.lineTo(cx + a / 2, h / 2)
        arrow.lineTo(cx - a / 2, h / 2 + a)
        canvas.drawPath(arrow, arrowPaint)
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (done) return false
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (e.x > thumbX + thumbSize * 1.5f) return false
                back?.cancel()
                dragging = true
                dragStart = e.x - thumbX
                parent?.requestDisallowInterceptTouchEvent(true)
                return true
            }
            MotionEvent.ACTION_MOVE ->
                if (dragging) {
                    thumbX = (e.x - dragStart).coerceIn(0f, maxOf(0f, width - thumbSize))
                    invalidate()
                    return true
                }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL ->
                if (dragging) {
                    dragging = false
                    val f = SwipeRule.fraction(thumbX, width.toFloat(), thumbSize)
                    if (e.actionMasked == MotionEvent.ACTION_UP && SwipeRule.isComplete(f)) complete() else slideBack()
                    return true
                }
        }
        return super.onTouchEvent(e)
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = android.widget.Button::class.java.name
    }

    private fun complete() {
        if (done) return
        done = true
        thumbX = maxOf(0f, width - thumbSize)
        invalidate()
        onComplete()
    }

    private fun slideBack() {
        if (!ValueAnimator.areAnimatorsEnabled()) {
            thumbX = 0f
            invalidate()
            return
        }
        back =
            ValueAnimator.ofFloat(thumbX, 0f).apply {
                duration = 200
                addUpdateListener {
                    thumbX = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
    }
}
