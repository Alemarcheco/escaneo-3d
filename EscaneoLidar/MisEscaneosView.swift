import SwiftUI
import QuickLook

/// Lista de escaneos guardados en Documentos/Escaneos.
struct MisEscaneosView: View {
    struct Escaneo: Identifiable {
        let carpeta: URL
        let archivos: [URL]
        let fecha: Date
        var id: URL { carpeta }
    }

    @State private var escaneos: [Escaneo] = []
    @State private var verArchivo: ArchivoVista?
    @State private var visor: Visor?

    struct Visor: Identifiable {
        let archivos: [URL]
        let inicial: URL?
        let id = UUID()
    }

    var body: some View {
        List {
            if escaneos.isEmpty {
                Text("Todavía no hay escaneos guardados.")
                    .foregroundStyle(.secondary)
            }
            ForEach(escaneos) { e in
                Section(e.carpeta.lastPathComponent) {
                    ForEach(e.archivos, id: \.self) { archivo in
                        HStack {
                            Button {
                                if Visor3DView.sePuedeVer(archivo) {
                                    visor = Visor(archivos: e.archivos, inicial: archivo)
                                } else {
                                    verArchivo = ArchivoVista(url: archivo)
                                }
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(archivo.lastPathComponent)
                                    Text(descripcion(archivo))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            ShareLink(item: archivo) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if e.archivos.contains(where: Visor3DView.sePuedeVer) {
                        Button {
                            visor = Visor(archivos: e.archivos, inicial: nil)
                        } label: {
                            Label("Ver en 3D", systemImage: "cube.fill")
                        }
                    }
                    Button("Borrar este escaneo", role: .destructive) {
                        try? FileManager.default.removeItem(at: e.carpeta)
                        cargar()
                    }
                }
            }
        }
        .navigationTitle("Mis escaneos")
        .onAppear(perform: cargar)
        .refreshable { cargar() }
        .sheet(item: $verArchivo) { a in
            VistaPreviaArchivo(url: a.url).ignoresSafeArea()
        }
        .fullScreenCover(item: $visor) { v in
            Visor3DView(archivos: v.archivos, inicial: v.inicial)
        }
    }

    private func cargar() {
        let fm = FileManager.default
        let carpetas = (try? fm.contentsOfDirectory(at: Almacen.carpetaEscaneos,
                                                    includingPropertiesForKeys: [.creationDateKey],
                                                    options: [.skipsHiddenFiles])) ?? []
        escaneos = carpetas.compactMap { c -> Escaneo? in
            guard (try? c.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let archivos = ((try? fm.contentsOfDirectory(at: c, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles])) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let fecha = (try? c.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return Escaneo(carpeta: c, archivos: archivos, fecha: fecha)
        }
        .sorted { $0.fecha > $1.fecha }
    }

    private func descripcion(_ url: URL) -> String {
        let tam = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let mb = ByteCountFormatter.string(fromByteCount: Int64(tam), countStyle: .file)
        switch url.pathExtension.lowercased() {
        case "usdz": return "Modelo 3D · se ve en AR · \(mb)"
        case "obj": return "Malla para Blender, SketchUp, etc. · \(mb)"
        case "stl": return "Malla para impresión 3D · \(mb)"
        case "ply": return "Nube de puntos con color (MeshLab, CloudCompare) · \(mb)"
        default: return mb
        }
    }
}

/// Vista previa con Quick Look (USDZ se puede ver en 3D y en realidad aumentada).
struct VistaPreviaArchivo: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        return UINavigationController(rootViewController: ql)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinador { Coordinador(url: url) }

    final class Coordinador: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
