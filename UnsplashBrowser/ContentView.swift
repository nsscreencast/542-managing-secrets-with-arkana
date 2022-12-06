@preconcurrency import SwiftUI

actor ImageCache: ObservableObject {
    private var imageTasks: [URL: Task<NSImage, Error>] = [:]
    
    func image(for url: URL) async throws -> NSImage {
        // if there's already a request for this url, wait for the result
        if let existingTask = imageTasks[url] {
            return try await existingTask.value
        }
        
        let imageTask = Task<NSImage, Error> {
            // if we have this already cached, return it
            if let cachedData = try await cachedData(for: url), let cachedImage = NSImage(data: cachedData) {
                return cachedImage
            }
        
            // make the request & cache it
            let (data, _) = try await URLSession.shared.data(from: url)
            try await writeCachedData(data, for: url)
            
            return NSImage(data: data)!
        }
        imageTasks[url] = imageTask
        
        return try await imageTask.value
    }
    
    private func writeCachedData(_ data: Data, for url: URL) async throws {
        let fileURL = cacheDir.appendingPathComponent(filename(for: url))
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try await Task {
            try data.write(to: fileURL)
        }.value
    }
    
    private func cachedData(for url: URL) async throws -> Data? {
        let fileURL = cacheDir.appendingPathComponent(filename(for: url))
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let task = Task { try Data(contentsOf: fileURL) }
        return try await task.value
    }
    
    private lazy var cacheDir: URL = {
        let path = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true)[0]
        return URL(fileURLWithPath: path)
    }()
    
    private func filename(for url: URL) -> String {
        url.absoluteString
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "?", with: "&")
    }
}

struct ImageCacheEnvironmentKey: EnvironmentKey {
    static var defaultValue = ImageCache()
}

extension EnvironmentValues {
    var imageCache: ImageCache {
        get { self[ImageCacheEnvironmentKey.self] }
        set { self[ImageCacheEnvironmentKey.self] = newValue }
    }
}

@MainActor
final class PhotosViewModel: ObservableObject {
    @Published var photos: [UnsplashPhoto] = []
    @Published var isLoading = false
    
    private let client: UnsplashApiClient
    private var page = 1
    
    init(client: UnsplashApiClient) {
        self.client = client
    }
    
    func fetch() async throws {
        isLoading = true
        while page < 10 {
            let photosPage = try await client.photos(page: page)
            page += 1
            for photo in photosPage.results {
                if !photos.contains(where: { $0.id == photo.id }) {
                    photos.append(photo)
                }
            }
            print("we have \(photos.count) photos")
            try? await Task.sleep(nanoseconds: NSEC_PER_SEC / 5)
        }
        isLoading = false
    }
}

struct ContentView: View, Sendable {
    @ObservedObject var viewModel: PhotosViewModel
    @Environment(\.imageCache) var imageCache
    
    var cols: [GridItem] {
        [
            GridItem(.adaptive(minimum: 200, maximum: 600), spacing: 1)
        ]
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols) {
                ForEach(viewModel.photos) { photo in
                    PhotoView(photo: photo, imageCache: imageCache)
                }
            }
            .padding()
        }
        .frame(minWidth: 400, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .overlay(
            ProgressView("Loading").opacity(viewModel.isLoading ? 1 : 0)
        )
        .task {
            try? await self.viewModel.fetch()
        }
    }
    
    func square(_ color: Color) -> some View {
        Rectangle()
            .fill(color)
            .aspectRatio(1, contentMode: .fill)
    }
}

@MainActor
final class PhotoViewModel: ObservableObject {
    @Published var isLoading = true
    @Published var image: NSImage?
    
    let photo: UnsplashPhoto
    let url: URL
    let imageCache: ImageCache
    
    init(photo: UnsplashPhoto, imageCache: ImageCache) {
        self.photo = photo
        url = photo.urls[.small]!
        self.imageCache = imageCache
    }
    
    func loadImage() async {
        let url = self.photo.urls[.regular]!
        isLoading = true
        image = try! await imageCache.image(for: url)
        isLoading = false
    }
}

@MainActor
struct PhotoView: View {
    @StateObject var viewModel: PhotoViewModel
    
    init(photo: UnsplashPhoto, imageCache: ImageCache) {
        _viewModel = StateObject<PhotoViewModel>.init(wrappedValue: .init(photo: photo, imageCache: imageCache))
    }
    
    var body: some View {
        ZStack {
            Color.clear
                .background (
                    Image(nsImage: viewModel.image ?? NSImage())
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .layoutPriority(-1)
                        .transition(.opacity)
                )
                .overlay(
                    ProgressView().opacity(viewModel.isLoading ? 1 : 0)
                )
        }
        .clipped()
        .aspectRatio(1, contentMode: .fit)
        .layoutPriority(1)
        .task {
            await viewModel.loadImage()
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: .init(client: .init()))
            .frame(width: 1200, height: 1000)
    }
}
