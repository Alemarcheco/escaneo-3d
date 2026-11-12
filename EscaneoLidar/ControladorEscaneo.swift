import ARKit
import RealityKit
import Combine

/// Maneja la sesión de ARKit con LiDAR: malla en vivo + nube de puntos.
final class ControladorEscaneo: NSObject, ObservableObject, ARSessionDelegate {
    @Published var triangulos = 0
    @Published var puntos = 0
    @Published var capturandoPuntos = true
    @Published var mostrarMalla = true { didSet { aplicarVistaMalla() } }
    @Published var aviso = "Mueve el iPhone despacio apuntando a paredes, piso y objetos."
    @Published var guardando = false
    @Published var mensajeFinal: String?
    /// Archivos del último escaneo guardado (para abrir el visor 3D).
    @Published var ultimosArchivos: [URL] = []

    private weak var vista: ARView?
    private var anclas: [UUID: ARMeshAnchor] = [:]
    private let nube = NubeDePuntos()
    private var ultimoCuadro: TimeInterval = 0
    private var ultimaCuenta: TimeInterval = 0

    func conectar(_ vista: ARView) {
        self.vista = vista
        vista.session.delegate = self
        aplicarVistaMalla()
        iniciar()
    }

    func iniciar() {
        guard let vista else { return }
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            config.sceneReconstruction = .meshWithClassification
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.environmentTexturing = .none
        anclas.removeAll()
        nube.vaciar()
        triangulos = 0
        puntos = 0
        vista.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func pausar() {
        vista?.session.pause()
    }

    private func aplicarVistaMalla() {
        guard let vista else { return }
        if mostrarMalla {
            vista.debugOptions.insert(.showSceneUnderstanding)
        } else {
            vista.debugOptions.remove(.showSceneUnderstanding)
        }
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let t = frame.timestamp
        if capturandoPuntos, !guardando, t - ultimoCuadro > 0.25 {
            ultimoCuadro = t
            nube.agregar(cuadro: frame)
        }
        if t - ultimaCuenta > 0.5 {
            ultimaCuenta = t
            puntos = nube.cantidad
            triangulos = ExportadorMalla.triangulos(Array(anclas.values))
            aviso = texto(para: frame.camera.trackingState)
        }
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { guardar(anchors) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { guardar(anchors) }
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for a in anchors { anclas.removeValue(forKey: a.identifier) }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        aviso = "Error de ARKit: \(error.localizedDescription)"
    }

    private func guardar(_ anchors: [ARAnchor]) {
        for case let m as ARMeshAnchor in anchors { anclas[m.identifier] = m }
    }

    private func texto(para estado: ARCamera.TrackingState) -> String {
        switch estado {
        case .normal:
            return capturandoPuntos ? "Escaneando… muévete despacio y rodea las cosas." : "Malla activa. Nube de puntos en pausa."
        case .notAvailable:
            return "Seguimiento no disponible."
        case .limited(let motivo):
            switch motivo {
            case .excessiveMotion: return "Vas muy rápido: mueve el iPhone más despacio."
            case .insufficientFeatures: return "Poca textura o poca luz: apunta a otra zona o enciende la luz."
            case .initializing: return "Iniciando… mueve el iPhone un poco."
            case .relocalizing: return "Recuperando posición…"
            @unknown default: return "Seguimiento limitado."
            }
        }
    }

    // MARK: - Guardar

    func guardarEscaneo(malla: Bool, nubePuntos: Bool) {
        guard !guardando else { return }
        guardando = true
        mensajeFinal = nil
        let copiaAnclas = Array(anclas.values)
        let nubeActual = nube
        DispatchQueue.global(qos: .userInitiated).async {
            let carpeta = Almacen.nuevaCarpeta(prefijo: "Espacio")
            var hechos: [String] = []
            var urls: [URL] = []
            var errores: [String] = []
            if malla {
                do {
                    let archivos = try ExportadorMalla.exportar(copiaAnclas, carpeta: carpeta, nombre: "malla",
                                                                extensiones: ["obj", "usdz", "stl"])
                    hechos += archivos.map { $0.lastPathComponent }
                    urls += archivos
                } catch {
                    errores.append(error.localizedDescription)
                }
            }
            if nubePuntos {
                if nubeActual.cantidad == 0 {
                    errores.append("La nube de puntos está vacía.")
                } else {
                    do {
                        let url = carpeta.appendingPathComponent("nube_puntos.ply")
                        try nubeActual.guardarPLY(en: url)
                        hechos.append(url.lastPathComponent)
                        urls.append(url)
                    } catch {
                        errores.append(error.localizedDescription)
                    }
                }
            }
            if hechos.isEmpty { try? FileManager.default.removeItem(at: carpeta) }
            DispatchQueue.main.async {
                self.guardando = false
                self.ultimosArchivos = urls
                if hechos.isEmpty {
                    self.mensajeFinal = "No se guardó nada.\n" + errores.joined(separator: "\n")
                } else {
                    var m = "Guardado en «\(carpeta.lastPathComponent)»:\n" + hechos.joined(separator: "\n")
                    if !errores.isEmpty { m += "\n\nAvisos:\n" + errores.joined(separator: "\n") }
                    self.mensajeFinal = m
                }
            }
        }
    }
}
