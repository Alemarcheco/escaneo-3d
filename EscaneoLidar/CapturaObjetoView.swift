import SwiftUI
import RealityKit

/// Escaneo de objetos con textura usando Object Capture de Apple (iOS 17+, requiere LiDAR).
/// 1) Se detecta el objeto, 2) se rodea tomando fotos automáticamente,
/// 3) el propio iPhone reconstruye un modelo USDZ con textura.
@MainActor
final class ModeloCaptura: ObservableObject {
    enum Fase: Equatable {
        case preparando
        case listo            // apunta al objeto
        case detectando       // caja alrededor del objeto
        case capturando       // rodeando el objeto
        case terminando
        case reconstruyendo(Double)
        case terminado(URL)
        case error(String)
    }

    @Published var sesion: ObjectCaptureSession?
    @Published var fase: Fase = .preparando

    private var carpetaFotos: URL?
    private var carpetaPuntos: URL?
    private var tareaEstados: Task<Void, Never>?
    private var tareaReconstruccion: Task<Void, Never>?
    private var fotogrametria: PhotogrammetrySession?

    static var soportado: Bool { ObjectCaptureSession.isSupported }

    func empezar() {
        guard sesion == nil, fase == .preparando else { return }
        guard ModeloCaptura.soportado else {
            fase = .error("Este iPhone no soporta Object Capture (necesita LiDAR e iOS 17 o más nuevo).")
            return
        }
        let fotos = Almacen.carpetaTemporal("FotosObjeto")
        let puntos = Almacen.carpetaTemporal("PuntosControl")
        carpetaFotos = fotos
        carpetaPuntos = puntos

        let s = ObjectCaptureSession()
        var config = ObjectCaptureSession.Configuration()
        config.checkpointDirectory = puntos
        config.isOverCaptureEnabled = false
        do {
            try s.start(imagesDirectory: fotos, configuration: config)
        } catch {
            fase = .error("No se pudo iniciar la cámara: \(error.localizedDescription)")
            return
        }
        sesion = s
        fase = .preparando

        tareaEstados = Task { [weak self] in
            for await estado in s.stateUpdates {
                self?.cambio(estado)
            }
        }
    }

    private func cambio(_ estado: ObjectCaptureSession.CaptureState) {
        switch estado {
        case .initializing: fase = .preparando
        case .ready: fase = .listo
        case .detecting: fase = .detectando
        case .capturing: fase = .capturando
        case .finishing: fase = .terminando
        case .completed:
            sesion = nil
            reconstruir()
        case .failed(let e):
            sesion = nil
            fase = .error("La captura falló: \(e.localizedDescription)")
        @unknown default:
            break
        }
    }

    func detectar() { _ = sesion?.startDetecting() }
    func capturar() { sesion?.startCapturing() }
    func finalizar() { sesion?.finish() }

    func cancelar() {
        sesion?.cancel()
        sesion = nil
        tareaEstados?.cancel()
        tareaReconstruccion?.cancel()
        fotogrametria?.cancel()
        fotogrametria = nil
    }

    func reiniciar() {
        cancelar()
        fase = .preparando
        empezar()
    }

    private func reconstruir() {
        guard let fotos = carpetaFotos else { return }
        fase = .reconstruyendo(0)
        let destinoCarpeta = Almacen.nuevaCarpeta(prefijo: "Objeto")
        let destino = destinoCarpeta.appendingPathComponent("modelo.usdz")
        let puntos = carpetaPuntos

        tareaReconstruccion = Task { [weak self] in
            do {
                var config = PhotogrammetrySession.Configuration()
                if let puntos { config.checkpointDirectory = puntos }
                let foto = try PhotogrammetrySession(input: fotos, configuration: config)
                self?.fotogrametria = foto
                try foto.process(requests: [.modelFile(url: destino)])
                for try await salida in foto.outputs {
                    switch salida {
                    case .requestProgress(_, let fraccion):
                        self?.fase = .reconstruyendo(fraccion)
                    case .requestError(_, let error):
                        self?.fase = .error("No se pudo crear el modelo: \(error.localizedDescription)")
                    case .processingComplete:
                        if FileManager.default.fileExists(atPath: destino.path) {
                            self?.fase = .terminado(destino)
                        } else if case .reconstruyendo = self?.fase {
                            self?.fase = .error("La reconstrucción terminó sin crear el archivo. Prueba con más fotos y mejor luz.")
                        }
                    default:
                        break
                    }
                }
            } catch {
                self?.fase = .error("No se pudo crear el modelo: \(error.localizedDescription)")
            }
            if let self, case .terminado = self.fase {} else {
                try? FileManager.default.removeItem(at: destinoCarpeta)
            }
        }
    }
}

struct CapturaObjetoView: View {
    @StateObject private var modelo = ModeloCaptura()
    @State private var verModelo: ArchivoVista?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let sesion = modelo.sesion {
                ObjectCaptureView(session: sesion)
                    .ignoresSafeArea()
            }

            VStack {
                Text(instruccion)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                controles
            }
            .padding()
        }
        .navigationTitle("Objeto")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { modelo.empezar() }
        .onDisappear { modelo.cancelar() }
        .sheet(item: $verModelo) { archivo in
            VistaPreviaArchivo(url: archivo.url).ignoresSafeArea()
        }
    }

    private var instruccion: String {
        switch modelo.fase {
        case .preparando: return "Preparando cámara y LiDAR…"
        case .listo: return "Pon el objeto sobre una mesa con buena luz y apunta al centro. Luego toca «Detectar»."
        case .detectando: return "Ajusta la caja para que encierre el objeto y toca «Empezar captura»."
        case .capturando: return "Camina despacio alrededor del objeto. Las fotos se toman solas. Haz una vuelta a la altura del objeto, otra más alta y otra más baja."
        case .terminando: return "Terminando captura…"
        case .reconstruyendo(let f): return "Creando el modelo 3D en el iPhone… \(Int(f * 100)) %. Puede tardar varios minutos; no cierres la app."
        case .terminado: return "¡Listo! El modelo se guardó en Mis escaneos."
        case .error(let m): return m
        }
    }

    @ViewBuilder
    private var controles: some View {
        switch modelo.fase {
        case .listo:
            botonPrincipal("Detectar", icono: "viewfinder") { modelo.detectar() }
        case .detectando:
            botonPrincipal("Empezar captura", icono: "camera.fill") { modelo.capturar() }
        case .capturando:
            botonPrincipal("Terminar y crear modelo", icono: "checkmark.circle.fill") { modelo.finalizar() }
        case .reconstruyendo(let f):
            ProgressView(value: f)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        case .terminado(let url):
            VStack(spacing: 10) {
                botonPrincipal("Ver en 3D / AR", icono: "arkit") { verModelo = ArchivoVista(url: url) }
                Button("Escanear otro objeto") { modelo.reiniciar() }
                    .buttonStyle(.bordered)
            }
        case .error:
            botonPrincipal("Intentar de nuevo", icono: "arrow.counterclockwise") { modelo.reiniciar() }
        default:
            EmptyView()
        }
    }

    private func botonPrincipal(_ titulo: String, icono: String, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Label(titulo, systemImage: icono)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
        }
        .buttonStyle(.borderedProminent)
    }
}

struct ArchivoVista: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
