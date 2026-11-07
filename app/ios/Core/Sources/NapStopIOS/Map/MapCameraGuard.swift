// D11 camera guard of the MapKit view (docs/specs/T23.3.md §4.2): pure arithmetic, no Apple framework, tested on Linux
// (`test-wsl.sh`) with the same table as the Dart `centerEastLimit` (fixtures/map_wire/cases.json, MW06b).
// Invariant: the east edge of the visible area never passes `eastLimit` (110.9°E), whatever the view's aspect ratio.

public enum MapCameraGuard {
    /// Layer 2: east limit of the camera center while the view spans `visibleLngSpan` degrees of longitude:
    /// `min(capEast, eastLimit − span / 2)`. A span ≤ 0 or not finite gives `capEast`.
    public static func centerEastLimit(visibleLngSpan: Double, capEast: Double, eastLimit: Double) -> Double {
        guard visibleLngSpan.isFinite, visibleLngSpan > 0 else { return capEast }
        return min(capEast, eastLimit - visibleLngSpan / 2)
    }

    /// Layer 1: the camera distance at which the view spans `maxLngSpan` degrees, from one measure (distance and span
    /// scale together on the Mercator plane). nil when an input is ≤ 0 or not finite: keep the previous value.
    public static func maxDistance(currentDistance: Double, currentLngSpan: Double, maxLngSpan: Double) -> Double? {
        guard currentDistance.isFinite, currentDistance > 0, currentLngSpan.isFinite, currentLngSpan > 0,
            maxLngSpan.isFinite, maxLngSpan > 0
        else { return nil }
        return currentDistance * maxLngSpan / currentLngSpan
    }

    /// Span (degrees of longitude) the view will show once `frame` has fitted a box into it (R2-1, R3-1).
    /// The box is `rectLngSpan` wide and `rectHeightLng` tall, the height also in degrees of longitude (map points ×
    /// 360 / world width: Mercator map points are square). The view is `viewWidth` × `viewHeight` points with paddings.
    /// MapKit fits the box on the tighter axis, so the visible span is the larger of
    ///   width-limited:  rectLngSpan   × viewWidth / (viewWidth − left − right)
    ///   height-limited: rectHeightLng × viewWidth / (viewHeight − top − bottom)   (same scale on both axes).
    /// nil when an input is not finite or negative, or the paddings leave no room (keep the current boundary then).
    public static func targetLngSpan(
        rectLngSpan: Double, rectHeightLng: Double, viewWidth: Double, viewHeight: Double, padTop: Double,
        padLeft: Double, padBottom: Double, padRight: Double
    ) -> Double? {
        let values = [rectLngSpan, rectHeightLng, viewWidth, viewHeight, padTop, padLeft, padBottom, padRight]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }), viewWidth > 0, viewHeight > 0 else { return nil }
        let innerWidth = viewWidth - padLeft - padRight
        let innerHeight = viewHeight - padTop - padBottom
        guard innerWidth > 0, innerHeight > 0 else { return nil }
        return max(rectLngSpan * viewWidth / innerWidth, rectHeightLng * viewWidth / innerHeight)
    }
}
