// Address search with Apple Maps (docs/specs/T23.5.md §5.2): `MKLocalSearchCompleter` for suggestions and
// `MKLocalSearch(request:)` built from the completion the user taps, for its location.
// MapKit docs: https://developer.apple.com/documentation/mapkit/mklocalsearchcompleter
// https://developer.apple.com/documentation/mapkit/mklocalsearch/request
// https://developer.apple.com/documentation/mapkit/mklocalsearchcompleterdelegate
//
// PRIVACY: only the typed text and the Vietnam box go to Apple. No user location is read or sent (D11), nothing is
// logged (D12), and only one snapshot of the last answer is kept.
#if os(iOS)
    import Foundation
    import MapKit

    @MainActor
    public final class AddressSearchService: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
        public typealias Reply = ([String: Any]) -> Void

        static let completeTimeoutSeconds = 10.0
        static let resolveTimeoutSeconds = 15.0

        private let completer = MKLocalSearchCompleter()

        private struct Pending {
            var gen: Int64
            let query: String
            let region: MapBoundsWire
            var reply: Reply
        }

        private struct Snapshot {
            var gen: Int64
            let query: String
            let region: MapBoundsWire
            var completions: [MKLocalSearchCompletion]
            var fake: [AddressFakeItem]
        }

        private var pending: Pending?
        private var completeTimer: Task<Void, Never>?
        private var snapshot: Snapshot?
        private var search: MKLocalSearch?
        private var resolveReply: Reply?
        private var resolveTimer: Task<Void, Never>?
        private var fake: [AddressFakeItem]?

        public override init() {
            super.init()
            completer.delegate = self
            completer.resultTypes = [.address, .pointOfInterest]
        }

        /// NAPSTOP_DIAG only: a fake source instead of MapKit (nil goes back to MapKit).
        public func setFake(_ items: [AddressFakeItem]?) {
            cancel()
            snapshot = nil
            fake = items
        }

        // MARK: - complete

        public func complete(_ r: AddressCompleteRequest, reply: @escaping Reply) {
            let query = r.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.isEmpty {
                supersedePending()
                reply(AddressSearchWire.completeReply(gen: r.gen, status: "ok", items: []))
                return
            }
            if let items = fake {
                supersedePending()
                let hits = items.filter { $0.t.range(of: query, options: .caseInsensitive) != nil }
                snapshot = Snapshot(gen: r.gen, query: query, region: r.region, completions: [], fake: hits)
                reply(
                    AddressSearchWire.completeReply(
                        gen: r.gen, status: "ok", items: hits.map { (title: $0.t, subtitle: $0.s) }))
                return
            }
            // Same text and box as the last answer: answer again from it (setting the same fragment again may not
            // produce an update).
            if var snap = snapshot, snap.query == query, snap.region == r.region {
                supersedePending()
                snap.gen = r.gen
                snapshot = snap
                reply(Self.reply(gen: r.gen, completions: snap.completions))
                return
            }
            if var p = pending, p.query == query, p.region == r.region {
                // Already asking Apple the same thing: the new caller takes over.
                p.reply(AddressSearchWire.completeReply(gen: p.gen, status: "superseded", items: []))
                p.gen = r.gen
                p.reply = reply
                pending = p
                return
            }
            supersedePending()
            pending = Pending(gen: r.gen, query: query, region: r.region, reply: reply)
            completer.region = Self.region(r.region)
            completer.resultTypes = [.address, .pointOfInterest]
            completer.pointOfInterestFilter = nil
            if #available(iOS 18.0, *) {
                completer.regionPriority = .required
            }
            completer.queryFragment = query
            completeTimer?.cancel()
            completeTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.completeTimeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finishComplete(status: "timeout", completions: nil)
            }
        }

        private func supersedePending() {
            guard let p = pending else { return }
            pending = nil
            completeTimer?.cancel()
            p.reply(AddressSearchWire.completeReply(gen: p.gen, status: "superseded", items: []))
        }

        private func finishComplete(status: String, completions: [MKLocalSearchCompletion]?) {
            guard let p = pending else { return }
            pending = nil
            completeTimer?.cancel()
            if status == "ok", let completions {
                snapshot = Snapshot(gen: p.gen, query: p.query, region: p.region, completions: completions, fake: [])
                p.reply(Self.reply(gen: p.gen, completions: completions))
            } else {
                p.reply(AddressSearchWire.completeReply(gen: p.gen, status: status, items: []))
            }
        }

        private static func reply(gen: Int64, completions: [MKLocalSearchCompletion]) -> [String: Any] {
            AddressSearchWire.completeReply(
                gen: gen, status: "ok",
                items: completions.prefix(AddressSearchWire.maxItems).map { (title: $0.title, subtitle: $0.subtitle) })
        }

        static func region(_ b: MapBoundsWire) -> MKCoordinateRegion {
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (b.s + b.n) / 2, longitude: (b.w + b.e) / 2),
                span: MKCoordinateSpan(latitudeDelta: b.n - b.s, longitudeDelta: b.e - b.w))
        }

        private static func status(for error: Error) -> String {
            let ns = error as NSError
            let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError
            return AddressSearchWire.errorStatus(domain: ns.domain, code: ns.code, underlyingDomain: underlying?.domain)
        }

        // MARK: - MKLocalSearchCompleterDelegate

        public func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            // Only the first update after a query is answered; later ones for the same text find nothing pending.
            finishComplete(status: "ok", completions: completer.results)
        }

        public func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
            let status = Self.status(for: error)
            // "Not found" is an empty list, not an error.
            if status == "notFound" {
                finishComplete(status: "ok", completions: [])
            } else {
                finishComplete(status: status, completions: nil)
            }
        }

        // MARK: - resolve

        public func resolve(_ r: AddressResolveRequest, reply: @escaping Reply) {
            guard let snap = snapshot, snap.gen == r.gen else {
                reply(AddressSearchWire.status("stale"))
                return
            }
            if fake != nil {
                guard r.index < snap.fake.count else {
                    reply(AddressSearchWire.status("stale"))
                    return
                }
                let item = snap.fake[r.index]
                reply(AddressSearchWire.resolveOk(lat: item.lat, lng: item.lng, country: item.country))
                return
            }
            guard r.index < snap.completions.count else {
                reply(AddressSearchWire.status("stale"))
                return
            }
            cancelResolve(answer: "superseded")
            let request = MKLocalSearch.Request(completion: snap.completions[r.index])
            request.region = Self.region(snap.region)
            request.resultTypes = [.address, .pointOfInterest]
            if #available(iOS 18.0, *) {
                request.regionPriority = .required
            }
            let search = MKLocalSearch(request: request)
            self.search = search
            resolveReply = reply
            resolveTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.resolveTimeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.cancelResolve(answer: "timeout")
            }
            search.start { [weak self] response, error in
                // MapKit calls back on the main queue.
                MainActor.assumeIsolated {
                    guard let self, self.search === search else { return }
                    self.finishResolve(response: response, error: error)
                }
            }
        }

        private func finishResolve(response: MKLocalSearch.Response?, error: Error?) {
            let reply = resolveReply
            resolveReply = nil
            resolveTimer?.cancel()
            search = nil
            guard let reply else { return }
            if let error {
                reply(AddressSearchWire.status(Self.status(for: error)))
                return
            }
            guard let item = response?.mapItems.first else {
                reply(AddressSearchWire.status("notFound"))
                return
            }
            let coordinate: CLLocationCoordinate2D
            let country: String?
            if #available(iOS 26.0, *) {
                coordinate = item.location.coordinate
                country = item.addressRepresentations?.region?.identifier
            } else {
                coordinate = item.placemark.coordinate
                country = item.placemark.isoCountryCode
            }
            guard MapWire.validLatLng(coordinate.latitude, coordinate.longitude) else {
                reply(AddressSearchWire.status("failed"))
                return
            }
            reply(AddressSearchWire.resolveOk(lat: coordinate.latitude, lng: coordinate.longitude, country: country))
        }

        /// Stops the running `MKLocalSearch` and answers its caller with `answer`.
        private func cancelResolve(answer: String) {
            search?.cancel()
            search = nil
            resolveTimer?.cancel()
            let reply = resolveReply
            resolveReply = nil
            reply?(AddressSearchWire.status(answer))
        }

        // MARK: - cancel

        public func cancel() {
            completer.cancel()
            supersedePending()
            cancelResolve(answer: "superseded")
        }
    }
#endif
