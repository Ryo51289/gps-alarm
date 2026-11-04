package app.napstop.core.bridge

import app.napstop.core.alarm.AlarmPort
import app.napstop.core.alarm.PreAlertRequest
import app.napstop.core.alarm.RingFacts
import app.napstop.core.alarm.RingRequest
import app.napstop.core.alarm.StopCause
import app.napstop.core.trip.runtime.AppVisibility
import app.napstop.core.trip.runtime.BatteryReading
import app.napstop.core.trip.runtime.DeviceEnv
import app.napstop.core.trip.runtime.FallbackLedger
import app.napstop.core.trip.runtime.FinishedRecord
import app.napstop.core.trip.runtime.FixSink
import app.napstop.core.trip.runtime.FlpRequestSpec
import app.napstop.core.trip.runtime.ForegroundResult
import app.napstop.core.trip.runtime.LocationAccess
import app.napstop.core.trip.runtime.LocationSource
import app.napstop.core.trip.runtime.OsAlarmScheduler
import app.napstop.core.trip.runtime.RawFix
import app.napstop.core.trip.runtime.RestoreCause
import app.napstop.core.trip.runtime.SlotKind
import app.napstop.core.trip.runtime.RingConfig
import app.napstop.core.trip.runtime.RuntimePorts
import app.napstop.core.trip.runtime.RuntimeStore
import app.napstop.core.trip.runtime.StartReason
import app.napstop.core.trip.runtime.StoredTrip
import app.napstop.core.trip.runtime.TimeSource
import app.napstop.core.trip.runtime.TrackingController
import app.napstop.core.trip.runtime.TrackingNotice
import app.napstop.core.trip.runtime.TripNotice
import app.napstop.core.trip.runtime.TripNotifier
import app.napstop.core.trip.runtime.TripRuntime
import app.napstop.core.trip.runtime.WakeMechanism
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope

/**
 * Minimal platform fakes for a [TripRuntime] in :app JVM tests (the full set lives in :core-runtime tests). Wall and
 * elapsed follow the test scheduler; start() answers Started synchronously.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RuntimeFakes(scope: TestScope) {
    val wall0 = 1_700_000_000_000L
    var onFix: FixSink? = null
    val rings = ArrayList<RingRequest>()
    private val time =
        object : TimeSource {
            override fun wallMs() = wall0 + scope.testScheduler.currentTime

            override fun elapsedMs() = 1_000_000L + scope.testScheduler.currentTime

            override fun elapsedNanos() = elapsedMs() * 1_000_000L

            override fun bootCount() = 1
        }
    lateinit var runtime: TripRuntime
    private var foreground = false
    private val tracking =
        object : TrackingController {
            override fun start(tripId: String, reason: StartReason) {
                foreground = true
                runtime.onForegroundResult(tripId, ForegroundResult.Started)
            }

            override fun updateTrackingNotification(content: TrackingNotice) = Unit

            override fun stop() {
                foreground = false
            }

            override val isForeground: Boolean get() = foreground
        }
    private val location =
        object : LocationSource {
            override fun request(spec: FlpRequestSpec, sink: FixSink) {
                this@RuntimeFakes.onFix = sink
            }

            override fun stop() {
                onFix = null
            }

            override suspend fun lastKnown(): RawFix? = null
        }
    private val scheduler =
        object : OsAlarmScheduler {
            override fun canScheduleExact() = true

            override fun setWake(triggerElapsedMs: Long, mechanism: WakeMechanism, triggerWallMs: Long, wakeAtMs: Long) = Unit

            override fun cancelWake() = Unit

            override fun setFallback(slot: Int, tripId: String, generation: Long, targetAtMs: Long, triggerWallMs: Long, exact: Boolean, kind: SlotKind) = Unit

            override fun cancelFallback(slot: Int) = Unit

            override fun setRestoreRetry(triggerElapsedMs: Long, attempt: Int, cause: RestoreCause, sinceWallMs: Long, exact: Boolean) = Unit

            override fun cancelRestoreRetry() = Unit
        }
    private var ringing = false
    private val alarm =
        object : AlarmPort {
            override fun ringNow(request: RingRequest) {
                rings += request
                ringing = true
            }

            override fun ringFallback(request: RingRequest) = ringNow(request)

            override fun stopRinging(tripId: String, cause: StopCause) {
                ringing = false
            }

            override fun preAlert(request: PreAlertRequest) = Unit

            override fun overshoot(tripId: String, pastM: Int) = Unit

            override fun ringFacts(tripId: String) = RingFacts.NONE.copy(ringingNow = ringing)

            override fun clearTrip(tripId: String) = Unit
        }
    private val notifier =
        object : TripNotifier {
            override fun show(tripId: String, notice: TripNotice, destinationName: String?, alert: Boolean) = Unit

            override fun clear(tripId: String, notice: TripNotice) = Unit

            override fun clearAll(tripId: String) = Unit
        }
    val finished = LinkedHashMap<String, FinishedRecord>()
    private val store =
        object : RuntimeStore {
            var active: StoredTrip? = null
            var ledger = FallbackLedger.EMPTY

            override fun readActive() = active

            override fun writeActive(t: StoredTrip) {
                active = t
            }

            override fun deleteActive() {
                active = null
            }

            override fun readLedger() = ledger

            override fun writeLedger(l: FallbackLedger) {
                ledger = l
            }

            override fun writeRingConfig(c: RingConfig) = Unit

            override fun readRingConfig(): RingConfig? = null

            override fun deleteRingConfig() = Unit

            override fun writeFinished(r: FinishedRecord) {
                finished[r.tripId] = r
            }

            override fun readFinished() = finished.values.toList()

            override fun deleteFinished(ids: List<String>) {
                ids.forEach { finished.remove(it) }
            }
        }
    private val env =
        object : DeviceEnv {
            override fun locationAccess() = LocationAccess(true, true, true, true)

            override fun battery(): BatteryReading? = null
        }

    init {
        val d = StandardTestDispatcher(scope.testScheduler)
        runtime =
            TripRuntime(
                RuntimePorts(time, location, tracking, scheduler, alarm, notifier, store, AppVisibility { true }, env),
                scope.backgroundScope,
                d,
                d,
                d,
                warn = {},
            )
    }

    /** A fresh fix [northM] metres north of (16.0, 108.0), south-bound at 15 m/s. */
    fun fix(northM: Double) {
        onFix?.onFix(RawFix(16.0 + northM / 111_195.0, 108.0, 8f, 15f, time.elapsedNanos())) {}
    }
}
