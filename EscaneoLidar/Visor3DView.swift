import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO

/// Visor 3D dentro de la app: girar con un dedo, zoom con dos, mover con dos dedos.
struct Visor3DView: View {
    let archivos: [URL]
    @State private var actual: URL
    @State private var verAR: ArchivoVista?
    @Environment(\.dismiss) private var cerrar

    init(archivos: [URL], inicial: URL? = nil) {
        let vistos = archivos.filter { Visor3DView.sePuedeVer($0) }
        self.archivos = vistos
        _actual = State(initialValue: inicial ?? Visor3DView.preferido(vistos) ?? archivos.first!)
    }

    static func sePuedeVer(_ url: URL) -> Bool {
        ["usdz", "obj", "stl", "ply"].contains(url.pathExtension.lowercased())
    }

    /// Primero el modelo con textura, luego la nube con color, luego la malla.
    static func preferido(_ urls: [URL]) -> URL? {
        for ext in ["usdz", "ply", "obj", "stl"] {
            if ext == "usdz", let m = urls.first(where: { $0.lastPathComponent == "modelo.usdz" }) { return m }
            if ext == "ply", let p = urls.first(where: { $0.pathExtension.lowercased() == "ply" }) { return p }
            if ext == "obj", let o = urls.first(where: { $0.pathExtension.lowercased() == "obj" }) { return o }
        }
        return urls.first
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if archivos.count > 1 {
                    Picker("Archivo", selection: $actual) {
                        ForEach(archivos, id: \.self) { u in
                            Text(nombre(u)).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(8)
                }
                EscenaArchivo(url: actual)
                    .id(actual)
                    .ignoresSafeArea(edges: .bottom)
            }
            .background(Color.black)
            .navigationTitle(actual.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { cerrar() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if actual.pathExtension.lowercased() == "usdz" {
                        Button {
                            verAR = ArchivoVista(url: actual)
                        } label: {
                            Label("Ver en AR", systemImage: "arkit")
                        }
                    }
                    ShareLink(item: actual)
                }
            }
            .sheet(item: $verAR) { a in
                VistaPreviaArchivo(url: a.url).ignoresSafeArea()
            }
        }
    }

    private func nombre(_ u: URL) -> String {
        switch u.pathExtension.lowercased() {
        case "ply": return "Puntos"
        case "obj": return "Malla"
        case "stl": return "STL"
        case "usdz": return u.lastPathComponent == "modelo.usdz" ? "Modelo" : "USDZ"
        default: return u.lastPathComponent
        }
    }
}

/// Carga el archivo en segundo plano y lo muestra con SceneKit.
private struct EscenaArchivo: View {
    let url: URL
    @State private var escena: SCNScene?
    @State private var error: String?

    var body: some View {
        ZStack {
            if let escena {
                VistaSceneKit(escena: escena)
            } else if let error {
                Text(error).foregroundStyle(.white).padding()
            } else {
                ProgressView("Cargando modelo…").tint(.white).foregroundStyle(.white)
            }
            if escena != nil {
                VStack {
                    Spacer()
                    Text("Un dedo: girar · Dos dedos: zoom y mover")
                        .font(.caption)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
        .task(id: url) {
            let u = url
            let resultado = await Task.detached(priority: .userInitiated) { () -> Result<SCNScene, Error> in
                do { return .success(try CargadorEscena.cargar(u)) } catch { return .failure(error) }
            }.value
            switch resultado {
            case .success(let s): escena = s
            case .failure(let e): error = "No se pudo abrir: \(e.localizedDescription)"
            }
        }
    }
}

private struct VistaSceneKit: UIViewRepresentable {
    let escena: SCNScene

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.scene = escena
        v.backgroundColor = UIColor(white: 0.08, alpha: 1)
        v.allowsCameraControl = true
        v.autoenablesDefaultLighting = true
        v.antialiasingMode = .multisampling4X
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

enum CargadorEscena {
    enum Fallo: LocalizedError {
        case plyInvalido
        var errorDescription: String? { "El archivo de puntos no tiene el formato esperado." }
    }

    static func cargar(_ url: URL) throws -> SCNScene {
        let ext = url.pathExtension.lowercased()
        let escena: SCNScene
        if ext == "ply" {
            escena = SCNScene()
            escena.rootNode.addChildNode(try nubeDePuntos(url))
        } else if url.lastPathComponent == "modelo.usdz" {
            escena = try SCNScene(url: url, options: nil)
        } else {
            let asset = MDLAsset(url: url)
            if let mallas = asset.childObjects(of: MDLMesh.self) as? [MDLMesh] {
                for m in mallas {
                    m.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.6)
                }
            }
            escena = SCNScene(mdlAsset: asset)
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(white: 0.85, alpha: 1)
            material.isDoubleSided = true
            escena.rootNode.enumerateHierarchy { nodo, _ in
                nodo.geometry?.materials = [material]
            }
        }
        return escena
    }

    /// Lee el PLY binario que guarda la app (x,y,z float + r,g,b uchar).
    static func nubeDePuntos(_ url: URL) throws -> SCNNode {
        let datos = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let fin = datos.range(of: Data("end_header\n".utf8)) else { throw Fallo.plyInvalido }
        let cabecera = String(decoding: datos[datos.startIndex..<fin.lowerBound], as: UTF8.self)
        var total = 0
        for linea in cabecera.split(separator: "\n") where linea.hasPrefix("element vertex ") {
            total = Int(linea.dropFirst("element vertex ".count).trimmingCharacters(in: .whitespaces)) ?? 0
        }
        let inicio = fin.upperBound
        let paso = 15
        guard total > 0, datos.count - (inicio - datos.startIndex) >= total * paso else { throw Fallo.plyInvalido }

        var posiciones = [SIMD3<Float>](repeating: .zero, count: total)
        var colores = [SIMD3<Float>](repeating: .zero, count: total)
        datos.withUnsafeBytes { (crudo: UnsafeRawBufferPointer) in
            let base = crudo.baseAddress!.advanced(by: inicio - datos.startIndex)
            for i in 0..<total {
                let p = base.advanced(by: i * paso)
                let x = p.loadUnaligned(as: Float.self)
                let y = p.advanced(by: 4).loadUnaligned(as: Float.self)
                let z = p.advanced(by: 8).loadUnaligned(as: Float.self)
                let r = p.advanced(by: 12).load(as: UInt8.self)
                let g = p.advanced(by: 13).load(as: UInt8.self)
                let b = p.advanced(by: 14).load(as: UInt8.self)
                posiciones[i] = SIMD3<Float>(x, y, z)
                colores[i] = SIMD3<Float>(Float(r) / 255, Float(g) / 255, Float(b) / 255)
            }
        }

        let datosPos = posiciones.withUnsafeBufferPointer { Data(buffer: $0) }
        let datosCol = colores.withUnsafeBufferPointer { Data(buffer: $0) }
        let fuentePos = SCNGeometrySource(data: datosPos, semantic: .vertex, vectorCount: total,
                                          usesFloatComponents: true, componentsPerVector: 3,
                                          bytesPerComponent: 4, dataOffset: 0,
                                          dataStride: MemoryLayout<SIMD3<Float>>.stride)
        let fuenteCol = SCNGeometrySource(data: datosCol, semantic: .color, vectorCount: total,
                                          usesFloatComponents: true, componentsPerVector: 3,
                                          bytesPerComponent: 4, dataOffset: 0,
                                          dataStride: MemoryLayout<SIMD3<Float>>.stride)
        let indices = (0..<UInt32(total)).map { $0 }
        let datosInd = indices.withUnsafeBufferPointer { Data(buffer: $0) }
        let elemento = SCNGeometryElement(data: datosInd, primitiveType: .point,
                                          primitiveCount: total, bytesPerIndex: 4)
        elemento.pointSize = 0.01
        elemento.minimumPointScreenSpaceRadius = 1.5
        elemento.maximumPointScreenSpaceRadius = 6

        let geo = SCNGeometry(sources: [fuentePos, fuenteCol], elements: [elemento])
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.white
        geo.materials = [material]
        return SCNNode(geometry: geo)
    }
}
