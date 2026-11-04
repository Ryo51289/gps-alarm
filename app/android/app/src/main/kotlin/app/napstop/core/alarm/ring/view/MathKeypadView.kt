package app.napstop.core.alarm.ring.view

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.GridLayout
import android.widget.LinearLayout
import android.widget.TextView
import app.napstop.core.alarm.MathChallenge

/**
 * "Giải phép tính để tắt" (spec T16 D16, §5.8): "a + b = ?", the typed answer, a 3×4 keypad drawn here (no system
 * keyboard: not every ROM shows one on a secure lock screen), "Xoá", "Xong". Wrong → [wrongText] (live region),
 * input cleared; a new problem after 3 misses.
 */
@SuppressLint("ViewConstructor", "SetTextI18n")
class MathKeypadView(
    context: Context,
    private val challenge: MathChallenge,
    hint: String,
    private val wrongText: String,
    deleteText: String,
    confirmText: String,
    typeface: Typeface?,
    private val onSolved: () -> Unit,
) : LinearLayout(context) {
    private val d = resources.displayMetrics.density
    private val problem: TextView
    private val input: TextView
    private val error: TextView
    private val typed = StringBuilder()

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        addView(label(hint, 17f, 0xFFC9CCD3.toInt(), typeface))
        problem = label("", 32f, 0xFFFFFFFF.toInt(), typeface).also { addView(it) }
        input =
            label("", 32f, 0xFFFF9F43.toInt(), typeface).also {
                it.minHeight = (48 * d).toInt()
                addView(it)
            }
        error =
            label("", 16f, 0xFFFF8A8A.toInt(), typeface).also {
                it.accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
                addView(it)
            }
        val grid =
            GridLayout(context).apply {
                columnCount = 3
                rowCount = 4
            }
        val keys = listOf("1", "2", "3", "4", "5", "6", "7", "8", "9", deleteText, "0", confirmText)
        for (k in keys) {
            val b =
                Button(context).apply {
                    text = k
                    textSize = 22f
                    isAllCaps = false
                    setTextColor(0xFFFFFFFF.toInt())
                    this.typeface = typeface
                    minHeight = (64 * d).toInt()
                    minWidth = (64 * d).toInt()
                    contentDescription = k
                    background =
                        GradientDrawable().apply {
                            setColor(if (k == confirmText) 0xFF3A3F4B.toInt() else 0xFF262A33.toInt())
                            cornerRadius = 16 * d
                        }
                    setOnClickListener { press(k, deleteText, confirmText) }
                }
            val lp =
                GridLayout.LayoutParams(GridLayout.spec(GridLayout.UNDEFINED, 1f), GridLayout.spec(GridLayout.UNDEFINED, 1f)).apply {
                    width = 0
                    height = (64 * d).toInt()
                    setMargins((4 * d).toInt(), (4 * d).toInt(), (4 * d).toInt(), (4 * d).toInt())
                }
            grid.addView(b, lp)
        }
        addView(grid, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply { topMargin = (8 * d).toInt() })
        showProblem()
    }

    private fun label(t: String, sp: Float, color: Int, tf: Typeface?): TextView =
        TextView(context).apply {
            text = t
            textSize = sp
            setTextColor(color)
            gravity = Gravity.CENTER
            typeface = tf
        }

    private fun press(k: String, deleteText: String, confirmText: String) {
        when (k) {
            deleteText -> if (typed.isNotEmpty()) typed.setLength(typed.length - 1)
            confirmText -> {
                when (val r = challenge.check(typed.toString())) {
                    MathChallenge.Result.Solved -> {
                        onSolved()
                        return
                    }
                    MathChallenge.Result.Wrong -> if (typed.isNotEmpty()) error.text = wrongText
                    is MathChallenge.Result.NewProblem -> {
                        error.text = wrongText
                        showProblem()
                    }
                }
                typed.setLength(0)
            }
            else -> if (typed.length < 3) typed.append(k)
        }
        input.text = typed.toString()
    }

    private fun showProblem() {
        val p = challenge.current
        problem.text = "${p.a} + ${p.b} = ?"
        problem.contentDescription = "${p.a} + ${p.b}"
    }
}
