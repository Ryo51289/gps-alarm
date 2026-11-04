package app.napstop.core.alarm

/** "Giải phép tính để tắt" (spec T16 D16): a + b with two-digit numbers, a new problem after MATH_MAX_WRONG misses. */
class MathChallenge(private val random: java.util.Random, private val c: AlarmConstants = AlarmConstants()) {
    data class Problem(val a: Int, val b: Int) {
        val answer: Int get() = a + b
    }

    sealed interface Result {
        data object Solved : Result

        data object Wrong : Result

        data class NewProblem(val p: Problem) : Result
    }

    var current: Problem = next()
        private set
    private var wrong = 0

    /** Empty input → Wrong without counting; anything else that is not the answer counts as a miss. */
    fun check(input: String): Result {
        val s = input.trim()
        if (s.isEmpty()) return Result.Wrong
        if (s.toIntOrNull() == current.answer) return Result.Solved
        wrong++
        if (wrong >= c.mathMaxWrong) {
            wrong = 0
            current = next()
            return Result.NewProblem(current)
        }
        return Result.Wrong
    }

    private fun next(): Problem = Problem(pick(c.mathARange), pick(c.mathBRange))

    private fun pick(r: IntRange): Int = r.first + random.nextInt(r.last - r.first + 1)
}
