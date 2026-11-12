import SwiftUI
import ARKit
import RealityKit

/// Pantalla principal: elegir tipo de escaneo o ver los guardados.
struct InicioView: View {
    private let tieneLidar = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

    var body: some View {
        NavigationStack {
            List {
                if !tieneLidar {
                    Section {
                        Label("Este iPhone no tiene sensor LiDAR. Se necesita un iPhone 12 Pro o más nuevo (modelo Pro / Pro Max) o un iPad Pro.",
                              systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Escanear") {
                    NavigationLink {
                        EscaneoEspacioView()
                    } label: {
                        Opcion(titulo: "Espacio / habitación",
                               detalle: "Malla 3D en vivo con el LiDAR y nube de puntos con color. Ideal para cuartos, muebles y objetos grandes.",
                               icono: "cube.transparent", color: .cyan)
                    }
                    .disabled(!tieneLidar)

                    NavigationLink {
                        CapturaObjetoView()
                    } label: {
                        Opcion(titulo: "Objeto con textura",
                               detalle: "Rodeas el objeto, la app toma fotos y crea un modelo 3D realista (USDZ).",
                               icono: "camera.metering.matrix", color: .purple)
                    }
                    .disabled(!tieneLidar)
                }

                Section("Archivos") {
                    NavigationLink {
                        MisEscaneosView()
                    } label: {
                        Opcion(titulo: "Mis escaneos",
                               detalle: "Ver en 3D / AR, compartir o borrar. También están en la app Archivos > En mi iPhone > Escáner 3D.",
                               icono: "folder.fill", color: .blue)
                    }
                }
            }
            .navigationTitle("Escáner 3D")
        }
    }
}

private struct Opcion: View {
    let titulo: String
    let detalle: String
    let icono: String
    let color: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icono)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(titulo).font(.headline)
                Text(detalle).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
