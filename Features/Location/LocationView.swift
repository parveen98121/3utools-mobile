import SwiftUI
import MapKit
import SwiftData
import UIKit

struct LocationView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedLocation.date, order: .reverse) private var saved: [SavedLocation]

    @State private var virtual = VirtualLocationManager.shared
    @State private var permission = LocationPermissionManager()
    @State private var search = LocationSearchManager()
    @State private var map = MapLocationManager()

    @State private var latitudeText = ""
    @State private var longitudeText = ""
    @State private var dragCoordinate: CLLocationCoordinate2D?
    @State private var showNotice = true
    @State private var showSaved = false
    @State private var showLimits = false
    @State private var showCoordinates = false
    @State private var message: String?

    private var history: LocationHistoryManager { LocationHistoryManager(context: context) }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            VStack(spacing: 8) {
                searchBar
                if !search.results.isEmpty { resultsList }
                if virtual.isActive {
                    activeBanner
                } else if showNotice {
                    notice
                }
                Spacer()
                HStack {
                    Spacer()
                    mapButtons
                }
                if let selected = map.selected {
                    selectionPanel(selected)
                } else {
                    hintPanel
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .navigationTitle("Virtual Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showLimits = true
                } label: {
                    Label("How it works", systemImage: "questionmark.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSaved = true
                } label: {
                    Label("History and favourites", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $showSaved) {
            SavedLocationsSheet { location in
                show(location)
                showSaved = false
            }
        }
        .sheet(isPresented: $showLimits) {
            LocationLimitsView()
        }
        .alert("Virtual Location", isPresented: Binding(get: { message != nil || search.errorMessage != nil },
                                                        set: { if !$0 { message = nil; search.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? search.errorMessage ?? "")
        }
        .onAppear {
            if permission.permission == .notDetermined {
                permission.requestPermission()
            }
            permission.start()
            // Reopen on the virtual location when one was set in an earlier session.
            if map.selected == nil, let current = virtual.current {
                map.centre(on: current.coordinate)
            }
        }
        .onDisappear { permission.stop() }
        .onChange(of: map.selected) { _, place in
            if let place {
                latitudeText = Format.coordinate(place.latitude)
                longitudeText = Format.coordinate(place.longitude)
                history.remember(place, in: saved)
            }
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $map.camera) {
                UserAnnotation()

                if let current = virtual.current {
                    Annotation("Virtual location", coordinate: current.coordinate, anchor: .center) {
                        Image(systemName: "figure.stand")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Theme.gradient, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 3)
                    }
                }

                if let selected = map.selected {
                    Annotation(selected.name, coordinate: dragCoordinate ?? selected.coordinate, anchor: .bottom) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 40))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Theme.brandPurple)
                            .shadow(radius: 3)
                            .scaleEffect(dragCoordinate == nil ? 1 : 1.25)
                            .animation(.spring(response: 0.25), value: dragCoordinate == nil)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 4, coordinateSpace: .named("map"))
                                    .onChanged { value in
                                        dragCoordinate = proxy.convert(value.location, from: .named("map"))
                                    }
                                    .onEnded { value in
                                        let end = proxy.convert(value.location, from: .named("map")) ?? dragCoordinate
                                        dragCoordinate = nil
                                        if let end {
                                            Task { await dropPin(latitude: end.latitude, longitude: end.longitude, moveCamera: false) }
                                        }
                                    }
                            )
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .coordinateSpace(.named("map"))
            .onMapCameraChange(frequency: .onEnd) { context in
                map.visibleRegion = context.region
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                Task { await dropPin(latitude: coordinate.latitude, longitude: coordinate.longitude, moveCamera: false) }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var mapButtons: some View {
        VStack(spacing: 0) {
            mapButton("plus") { map.zoom(by: 0.5) }
            Divider().frame(width: 36)
            mapButton("minus") { map.zoom(by: 2) }
            Divider().frame(width: 36)
            mapButton("location.fill") {
                if permission.permission == .granted {
                    map.showActualLocation()
                } else {
                    message = permission.explanation
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func mapButton(_ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
        }
    }

    // MARK: - Actions

    /// Puts the pin at a coordinate, then fills in its name and address when they can be looked up.
    private func dropPin(latitude: Double, longitude: Double, name: String? = nil,
                         address: String = "", moveCamera: Bool) async {
        guard CoordinateParser.validated(latitude: latitude, longitude: longitude) != nil else {
            message = "Enter a latitude between -90 and 90 and a longitude between -180 and 180."
            return
        }
        map.select(SelectedPlace(name: name ?? "Dropped pin", address: address,
                                 latitude: latitude, longitude: longitude), moveCamera: moveCamera)
        guard address.isEmpty else { return }
        if let found = await search.reverseGeocode(latitude: latitude, longitude: longitude) {
            map.updateDetails(name: name == nil ? found.name : nil, address: found.address,
                              forLatitude: latitude, longitude: longitude)
        }
    }

    private func runSearch() async {
        let near = virtual.effectiveLocation(actual: permission.actualPoint)
        if case .coordinate(let coordinate) = await search.search(near: near) {
            search.clear()
            await dropPin(latitude: coordinate.latitude, longitude: coordinate.longitude, moveCamera: true)
        }
    }

    private func goToTypedCoordinates() async {
        guard let latitude = Double(latitudeText.replacingOccurrences(of: ",", with: ".")),
              let longitude = Double(longitudeText.replacingOccurrences(of: ",", with: ".")) else {
            message = "Enter a latitude between -90 and 90 and a longitude between -180 and 180."
            return
        }
        await dropPin(latitude: latitude, longitude: longitude, moveCamera: true)
    }

    private func show(_ location: SavedLocation) {
        map.select(SelectedPlace(name: location.name, address: location.address,
                                 latitude: location.latitude, longitude: location.longitude), moveCamera: true)
    }

    private func setVirtualLocation(_ place: SelectedPlace) {
        let accepted = virtual.set(name: place.name, address: place.address,
                                   latitude: place.latitude, longitude: place.longitude)
        if accepted {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            message = "These coordinates are out of range."
        }
    }

    /// Returns the app to the phone's actual location and removes the pin.
    private func restoreActualLocation() {
        virtual.restore()
        map.clearSelection()
        latitudeText = ""
        longitudeText = ""
        if permission.permission == .granted {
            map.showActualLocation()
        }
    }

    // MARK: - Overlays

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search a city, address, place or “lat, lon”", text: $search.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await runSearch() } }
            if search.isSearching {
                ProgressView()
            } else if !search.query.isEmpty {
                Button {
                    search.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(search.results) { result in
                    Button {
                        let coordinate = result.item.placemark.coordinate
                        let name = result.title
                        let address = result.subtitle
                        search.clear()
                        Task {
                            await dropPin(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                          name: name, address: address, moveCamera: true)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).font(.subheadline.weight(.medium))
                            Text(result.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 240)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var notice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.brandBlue)
            Text("Pick a place and tap “Set virtual location”. It works entirely on this iPhone and changes the location used inside this app. Tap ? for details.")
                .font(.caption)
            Button {
                withAnimation { showNotice = false }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold))
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var activeBanner: some View {
        if let current = virtual.current {
            HStack(spacing: 8) {
                Image(systemName: "figure.stand").foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Virtual location active in this app")
                        .font(.caption.weight(.bold))
                    Text("\(current.name) · \(Format.coordinate(current.latitude)), \(Format.coordinate(current.longitude))")
                        .font(.caption2)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                Spacer(minLength: 4)
                Button("Restore") { restoreActualLocation() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.25))
                    .controlSize(.small)
            }
            .padding(10)
            .background(Theme.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var hintPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let actual = permission.actual {
                Label("Your actual location", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                Text("\(Format.coordinate(actual.coordinate.latitude)), \(Format.coordinate(actual.coordinate.longitude))")
                    .font(.system(.footnote, design: .monospaced))
            } else if permission.permission != .granted {
                Label(permission.permission == .notDetermined ? "Location access not set" : "Location access is off",
                      systemImage: "location.slash.fill")
                    .font(.subheadline.weight(.semibold))
                Text(permission.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if permission.permission == .notDetermined {
                    Button("Allow location access") { permission.requestPermission() }
                } else {
                    Button("Open Settings") { AppSettings.open() }
                }
            }

            Text("Tap the map to drop a pin, drag the pin to adjust it, or search above.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            let recents = LocationHistoryManager.recents(from: saved)
            if !recents.isEmpty {
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(recents) { location in
                            Button {
                                show(location)
                            } label: {
                                Label(location.name, systemImage: location.isFavorite ? "star.fill" : "clock")
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Button {
                showCoordinates.toggle()
            } label: {
                Label("Enter latitude and longitude", systemImage: "number")
                    .font(.footnote)
            }
            if showCoordinates { coordinateFields }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var coordinateFields: some View {
        HStack(spacing: 8) {
            TextField("Latitude", text: $latitudeText)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
            TextField("Longitude", text: $longitudeText)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
            Button("Go") {
                Task { await goToTypedCoordinates() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func selectionPanel(_ selected: SelectedPlace) -> some View {
        let favourite = history.isFavourite(selected, in: saved)
        let isCurrent = virtual.current.map {
            abs($0.latitude - selected.latitude) < 0.00001 && abs($0.longitude - selected.longitude) < 0.00001
        } ?? false
        let distance = permission.actualPoint.map { GeoMath.distanceText(GeoMath.distance(from: $0, to: selected.point)) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected.name).font(.headline).lineLimit(1)
                    if !selected.address.isEmpty {
                        Text(selected.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    history.toggleFavourite(selected, in: saved)
                } label: {
                    Image(systemName: favourite ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(favourite ? .yellow : .secondary)
                }
            }

            HStack(spacing: 16) {
                labelled("Latitude", Format.coordinate(selected.latitude))
                labelled("Longitude", Format.coordinate(selected.longitude))
                if let distance {
                    labelled("From actual", distance)
                }
            }

            coordinateFields

            Button {
                setVirtualLocation(selected)
            } label: {
                Label(isCurrent ? "Virtual location set here" : "Set virtual location",
                      systemImage: isCurrent ? "checkmark.circle.fill" : "figure.stand")
            }
            .buttonStyle(GradientButtonStyle())
            .disabled(isCurrent)
            .opacity(isCurrent ? 0.6 : 1)

            HStack(spacing: 8) {
                Button {
                    map.openDirections(to: selected)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    UIPasteboard.general.string = "\(Format.coordinate(selected.latitude)), \(Format.coordinate(selected.longitude))"
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                Button {
                    restoreActualLocation()
                } label: {
                    Label("Restore", systemImage: "location.fill")
                }
                .buttonStyle(.bordered)
            }
            .font(.footnote)
            .lineLimit(1)

            Text("“Restore” returns the app to your actual location and removes the pin.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.footnote, design: .monospaced).weight(.semibold))
        }
    }
}

// MARK: - History and favourites

struct SavedLocationsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedLocation.date, order: .reverse) private var saved: [SavedLocation]

    @State private var showFavourites = false
    let onPick: (SavedLocation) -> Void

    private var history: LocationHistoryManager { LocationHistoryManager(context: context) }

    private var visible: [SavedLocation] {
        showFavourites ? saved.filter(\.isFavorite) : saved
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("List", selection: $showFavourites) {
                    Text("History").tag(false)
                    Text("Favourites").tag(true)
                }
                .pickerStyle(.segmented)
                .padding()

                if visible.isEmpty {
                    EmptyStateView(title: showFavourites ? "No favourites yet" : "No history yet",
                                   systemImage: showFavourites ? "star" : "clock",
                                   message: showFavourites
                                       ? "Tap the star on a selected place to save it."
                                       : "Places you select on the map appear here.")
                } else {
                    List {
                        ForEach(visible) { location in
                            Button {
                                onPick(location)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(location.name).foregroundStyle(.primary)
                                        if !location.address.isEmpty {
                                            Text(location.address).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Text("\(Format.coordinate(location.latitude)), \(Format.coordinate(location.longitude))")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if location.isFavorite {
                                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { history.delete(visible[index]) }
                        }
                    }
                }
            }
            .navigationTitle("Saved places")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !showFavourites && !saved.isEmpty {
                        Button("Clear history", role: .destructive) {
                            history.clearHistory(saved)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - What the feature does and does not do

struct LocationLimitsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("What Virtual Location does") {
                    point("Works on the iPhone alone", "No computer, cable, pairing file or extra app is needed. Open the tab, pick a place, tap “Set virtual location”.")
                    point("Changes this app's location", "The place you set becomes the location this app uses: the map opens there, searches look for places around it, the Home screen shows it, and distances are measured from your actual position to it.")
                    point("Remembers it", "The virtual location, your favourites and your history are stored on the phone and are still there when you reopen the app.")
                    point("Restores in one tap", "“Restore” returns the app to your actual location.")
                }

                Section("What it does not do") {
                    point("It does not change GPS for other apps", "Maps, WhatsApp, games and every other app keep receiving the phone's real GPS position. iOS has no public feature that lets one app change the location another app receives.")
                    point("Why", "Location on iOS comes from the system. Each app can only read it. Apple provides location simulation only as a developer testing tool that is driven from a computer running Apple's developer software, with the phone in Developer Mode.")
                    point("What this means for you", "If you need other apps to see a different location, that needs a computer-based developer tool; this app cannot do it by itself, and it does not pretend to.")
                }

                Section("Permissions") {
                    point("Location access is optional", "With it, the map shows your actual position and the distance to the place you pick. Without it, everything else still works.")
                }
            }
            .navigationTitle("How it works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func point(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
