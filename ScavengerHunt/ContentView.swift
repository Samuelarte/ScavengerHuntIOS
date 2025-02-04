import SwiftUI
import PhotosUI
import MapKit
import CoreLocation
import ImageIO

struct Task: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    var isCompleted: Bool = false
    var image: UIImage? = nil
    var location: CLLocationCoordinate2D? = nil
    var uploaded: Bool = false
}

struct ContentView: View {
    @StateObject var viewModel = TaskViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.tasks.indices, id: \.self) { index in
                    NavigationLink(destination: TaskDetailView(taskIndex: index, viewModel: viewModel)) {
                        HStack {
                            Text(viewModel.tasks[index].title)
                                .strikethrough(viewModel.tasks[index].isCompleted, color: .gray)
                            Spacer()
                            if viewModel.tasks[index].isCompleted {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scavenger Hunt")
        }
    }
}

class TaskViewModel: ObservableObject {
    @Published var tasks: [Task] = [
        Task(title: "Find a red flower", description: "Take a photo of a red flower"),
        Task(title: "Capture a sunset", description: "Take a photo of the sunset"),
        Task(title: "Spot a squirrel", description: "Take a photo of a squirrel")
    ]

    func completeTask(index: Int, image: UIImage, location: CLLocationCoordinate2D?) {
        tasks[index].isCompleted = true
        tasks[index].image = image
        tasks[index].location = location
    }

    func uploadTask(index: Int, completion: @escaping () -> Void) {
        // Simulate a 2-second network upload
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.tasks[index].uploaded = true
            completion()
        }
    }
}

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var currentLocation: CLLocationCoordinate2D?

    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
    }
}

// MARK: - EXIF Location Extraction (Photo Library Only)
fileprivate func extractPhotoLocation(from image: UIImage) -> CLLocationCoordinate2D? {
    guard let imageData = image.jpegData(compressionQuality: 1.0) else { return nil }
    guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
    guard let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let gpsData = metadata[kCGImagePropertyGPSDictionary] as? [CFString: Any] else {
        return nil
    }

    guard let latitude = gpsData[kCGImagePropertyGPSLatitude] as? Double,
          let longitude = gpsData[kCGImagePropertyGPSLongitude] as? Double else {
        return nil
    }

    let latRef = (gpsData[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
    let lonRef = (gpsData[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"
    let finalLat = (latRef == "S") ? -latitude : latitude
    let finalLon = (lonRef == "W") ? -longitude : longitude

    return CLLocationCoordinate2D(latitude: finalLat, longitude: finalLon)
}

// MARK: - PhotoPicker
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self)
            else {
                return
            }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    if let image = image as? UIImage {
                        self.parent.image = image
                        self.parent.onImagePicked(image)
                    }
                }
            }
        }
    }
}

// MARK: - CameraPicker with Device Location
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    let onImagePicked: (UIImage, CLLocationCoordinate2D?) -> Void
    @ObservedObject var locationManager: LocationManager

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            picker.dismiss(animated: true)
            if let image = info[.originalImage] as? UIImage {
                // Rely on device's location for camera images
                let deviceLocation = parent.locationManager.currentLocation
                parent.image = image
                parent.onImagePicked(image, deviceLocation)
            }
        }
    }
}

struct TaskDetailView: View {
    let taskIndex: Int
    @ObservedObject var viewModel: TaskViewModel

    @State private var selectedImage: UIImage?
    @State private var isPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isUploaded = false
    @State private var isUploading = false
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        VStack {
            Text(viewModel.tasks[taskIndex].title)
                .font(.largeTitle)
                .padding()

            Text(viewModel.tasks[taskIndex].description)
                .padding()

            // Display the selected image
            if let image = viewModel.tasks[taskIndex].image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(10)

                // Show upload button or status
                if isUploaded {
                    Text("✅ Photo Uploaded!")
                        .font(.headline)
                        .foregroundColor(.green)
                } else {
                    if isUploading {
                        Text("Uploading...")
                            .foregroundColor(.orange)
                            .padding(.bottom, 4)
                    }

                    Button("Upload Photo") {
                        isUploading = true
                        viewModel.uploadTask(index: taskIndex) {
                            isUploading = false
                            isUploaded = true
                        }
                    }
                    .padding()
                    .background(Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }

            // Add/Take Photo Buttons
            HStack {
                Button("Add Photo") {
                    isPickerPresented = true
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)

                Button("Take Photo") {
                    isCameraPresented = true
                }
                .padding()
                .background(Color.green)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .sheet(isPresented: $isPickerPresented) {
                PhotoPicker(image: $selectedImage) { image in
                    selectedImage = image
                    let extractedLocation = extractPhotoLocation(from: image)
                    viewModel.completeTask(
                        index: taskIndex,
                        image: image,
                        location: extractedLocation
                    )
                }
            }
            .sheet(isPresented: $isCameraPresented) {
                CameraPicker(
                    image: $selectedImage,
                    onImagePicked: { image, deviceLocation in
                        selectedImage = image
                        viewModel.completeTask(
                            index: taskIndex,
                            image: image,
                            location: deviceLocation
                        )
                    },
                    locationManager: locationManager
                )
            }

            // Display map once photo is uploaded and location is known
            if isUploaded, let location = viewModel.tasks[taskIndex].location {
                Map(
                    initialPosition: .region(
                        MKCoordinateRegion(
                            center: location,
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )
                    )
                ) {
                    Marker("Task Location", coordinate: location)
                }
                .frame(height: 200)
                .cornerRadius(10)
            }
        }
        .padding()
    }
}

