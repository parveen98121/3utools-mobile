import SwiftUI
import MapKit
import SwiftData
import UIKit

struct LocationView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedLocation.date, order: .reverse) private var saved: [SavedLocation]

    @State private var model = LocationViewModel()
    @State private var showNotice = true
    @State private var showSaved = false
    @State private var showCoordinates = false

    var body: some View {
        ZStack(alignment: .top) {
            map
            VStack(spacing: 8) {
                searchBar
                if !model.results.isEmpty { resultsList }
                if showNotice { notice }
                Spacer()
                if let selected = model.selected {
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
                model.show(location)
                showSaved = false
            }
        }
        .alert("Location", isPresented: Binding(get: { model.message != nil },
                                                set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.message ?? "")
        }
        .onAppear {
            if model.service.permission == .notDetermined {
                model.service.requestPermission()
            }
            model.service.start()
        }
        .onDisappear { model.service.stop() }
        .onChange(of: model.selected) { _, place in
            if let place { remember(place) }
        }
    }

    // MARK: - Map

    private var map: some View {
        MapReader { proxy in
            Map(position: $model.camera) {
                UserAnnotation()
                if let selected = model.selected {
                    Marker(selected.name, systemImage: "mappin", coordinate: selected.coordinate)
                        .tint(Theme.brandPurple)
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local) else { return }
                Task {
                    await model.select(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                       name: nil, moveCamera: false)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    // MARK: - Overlays

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search a place, address or “lat, lon”", text: $model.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await model.search() } }
            if model.isSearching {
                ProgressView()
            } else if !model.query.isEmpty {
                Button {
                    model.query = ""
                    Task { await model.search() }
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
                ForEach(model.results) { result in
                    Button {
                        Task { await model.select(result) }
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
            Text("A pin here is a marker inside this app only. iOS does not allow an app to change the phone's GPS location for other apps.")
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

    private var hintPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.service.permission == .denied || model.service.permission == .restricted {
                Label("Location access is off", systemImage: "location.slash.fill")
                    .font(.subheadline.weight(.semibold))
                Button("Open Settings") { AppSettings.open() }
            } else if let current = model.service.current {
                Label("Your actual location", systemImage: "location.fill")
                    .font(.subheadline.weight(.semibold))
                Text("\(Format.coordinate(current.coordinate.latitude)), \(Format.coordinate(current.coordinate.longitude))")
                    .font(.system(.footnote, design: .monospaced))
            }
            Text("Tap the map to drop a pin, or search above.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
            TextField("Latitude", text: $model.latitudeText)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
            TextField("Longitude", text: $model.longitudeText)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
            Button("Go") {
                Task { await model.selectTypedCoordinates() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func selectionPanel(_ selected: SelectedPlace) -> some View {
        let favourite = saved.contains(where: { $0.isFavorite && matches($0, selected) })
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
                    toggleFavourite(selected)
                } label: {
                    Image(systemName: favourite ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(favourite ? .yellow : .secondary)
                }
            }

            HStack(spacing: 16) {
                labelled("Latitude", Format.coordinate(selected.latitude))
                labelled("Longitude", Format.coordinate(selected.longitude))
                if let distance = model.distanceText {
                    labelled("From you", distance)
                }
            }

            coordinateFields

            HStack(spacing: 8) {
                Button {
                    model.openInMaps()
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
                    model.restoreActualLocation()
                } label: {
                    Label("Restore", systemImage: "location.fill")
                }
                .buttonStyle(.bordered)
            }
            .font(.footnote)
            .lineLimit(1)

            Text("“Restore” removes the pin and returns the map to your actual location.")
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

    // MARK: - Saved locations

    private func matches(_ saved: SavedLocation, _ place: SelectedPlace) -> Bool {
        abs(saved.latitude - place.latitude) < 0.00001 && abs(saved.longitude - place.longitude) < 0.00001
    }

    /// Adds the place to history, or refreshes the entry that is already there.
    private func remember(_ place: SelectedPlace) {
        if let existing = saved.first(where: { matches($0, place) }) {
            existing.date = Date()
            existing.name = place.name
            if !place.address.isEmpty { existing.address = place.address }
        } else {
            context.insert(SavedLocation(name: place.name, address: place.address,
                                         latitude: place.latitude, longitude: place.longitude))
        }
    }

    private func toggleFavourite(_ place: SelectedPlace) {
        if let existing = saved.first(where: { matches($0, place) }) {
            existing.isFavorite.toggle()
        } else {
            context.insert(SavedLocation(name: place.name, address: place.address,
                                         latitude: place.latitude, longitude: place.longitude, isFavorite: true))
        }
    }
}

struct SavedLocationsSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedLocation.date, order: .reverse) private var saved: [SavedLocation]

    @State private var showFavourites = false
    let onPick: (SavedLocation) -> Void

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
                            for index in offsets { context.delete(visible[index]) }
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
                            for location in saved where !location.isFavorite { context.delete(location) }
                        }
                    }
                }
            }
        }
    }
}
