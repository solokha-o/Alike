import Core
import DesignSystem
import MapKit
import NavigationKit
import Photos
import SwiftUI

#if os(iOS)

// MARK: - Metadata View

struct MetadataView: View {
    let asset: PHAsset
    @Environment(\.dismiss) private var dismiss

    private var metadata: AssetMetadata {
        asset.displayMetadata
    }

    var body: some View {
        RoutedNavigationStack {
            List {
                PhotoInfoPreview(asset: asset)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                Section {
                    LabeledContent {
                        Text(metadata.resolution)
                    } label: {
                        Text(DetailsL10n.ClusterDetails.resolution)
                    }

                    LabeledContent {
                        Text(formattedMegapixels)
                    } label: {
                        Text(DetailsL10n.ClusterDetails.megapixels)
                    }

                    LabeledContent {
                        Text(photoType)
                    } label: {
                        Text(DetailsL10n.ClusterDetails.type)
                    }

                    LabeledContent {
                        Text(metadata.isFavorite ? DetailsL10n.ClusterDetails.yes : DetailsL10n.ClusterDetails.no)
                    } label: {
                        Text(DetailsL10n.ClusterDetails.favorite)
                    }
                } header: {
                    Text(DetailsL10n.ClusterDetails.details)
                }

                if metadata.creationDate != nil || metadata.modificationDate != nil {
                    Section {
                        if metadata.creationDate != nil {
                            LabeledContent {
                                Text(metadata.formattedCreationDate)
                            } label: {
                                Text(DetailsL10n.ClusterDetails.created)
                            }
                        }

                        if let modified = metadata.formattedModificationDate {
                            LabeledContent {
                                Text(modified)
                            } label: {
                                Text(DetailsL10n.ClusterDetails.modified)
                            }
                        }
                    } header: {
                        Text(DetailsL10n.ClusterDetails.dates)
                    }
                }

                if let location = metadata.location {
                    PhotoInfoLocationSection(location: location)
                }
            }
            .navigationTitle(Text(DetailsL10n.ClusterDetails.photoInfo))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text(DetailsL10n.ClusterDetails.done)
                    }
                }
            }
        }
    }

    private var formattedMegapixels: String {
        PhotoMetadataPresentation.megapixelsText(metadata.megapixelCount)
    }

    private var photoType: String {
        PhotoMetadataPresentation.photoTypeText(metadata.photoTraits)
    }
}

private struct PhotoInfoPreview: View {
    let asset: PHAsset

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.secondary.opacity(ColorOpacity.placeholderFill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .accessibilityLabel(Text(DetailsL10n.Common.photoPreview))
            } else if isLoading {
                ProgressView()
                    .accessibilityLabel(Text(DetailsL10n.Common.loadingPhotoPreview))
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(DetailsL10n.Common.photoPreviewUnavailable))
            }
        }
        .frame(height: 180)
        .frame(maxWidth: .infinity)
        .task(id: asset.localIdentifier) {
            defer { isLoading = false }
            image = try? await asset.loadImage(targetSize: CGSize(width: 800, height: 600))
        }
    }
}

private struct PhotoInfoLocationSection: View {
    let location: AssetLocation

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
    }

    private var region: MKCoordinateRegion {
        MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )
    }

    var body: some View {
        Section {
            Map(initialPosition: .region(region), interactionModes: []) {
                Marker(DetailsL10n.ClusterDetails.photoLocation, coordinate: coordinate)
            }
            .frame(height: 160)
            .listRowInsets(EdgeInsets())
            .accessibilityLabel(Text(DetailsL10n.ClusterDetails.mapShowingWherePhotoWas))

            Button {
                openInMaps()
            } label: {
                Label(DetailsL10n.ClusterDetails.openInMaps, systemImage: "map")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityHint(Text(DetailsL10n.ClusterDetails.opensPhotoLocationMaps))
        } header: {
            Text(DetailsL10n.ClusterDetails.location)
        }
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = DetailsL10n.ClusterDetails.photoLocation
        mapItem.openInMaps()
    }
}

#else

struct MetadataView: View {
    var body: some View {
        EmptyView()
    }
}

#endif
