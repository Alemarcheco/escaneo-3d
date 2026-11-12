import SwiftUI
import RealityKit

struct EscaneoEspacioView: View {
    @StateObject private var control = ControladorEscaneo()
    @State private var pedirGuardar = false
    @State private var verVisor = false

    var body: some View {
        ZStack {
            VistaAR(control: control)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text(control.aviso)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 16) {
                    Label("\(formato(control.triangulos)) triángulos", systemImage: "triangle")
                    Label("\(formato(control.puntos)) puntos", systemImage: "circle.grid.3x3.fill")
                }
                .font(.caption.monospacedDigit())
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                HStack(spacing: 12) {
                    Boton(titulo: control.capturandoPuntos ? "Pausar puntos" : "Seguir puntos",
                          icono: control.capturandoPuntos ? "pause.fill" : "play.fill") {
                        control.capturandoPuntos.toggle()
                    }
                    Boton(titulo: control.mostrarMalla ? "Ocultar malla" : "Ver malla",
                          icono: control.mostrarMalla ? "eye.slash" : "eye") {
                        control.mostrarMalla.toggle()
                    }
                    Boton(titulo: "Reiniciar", icono: "arrow.counterclockwise") {
                        control.iniciar()
                    }
                    .disabled(control.guardando)
                }

                Button {
                    pedirGuardar = true
                } label: {
                    Label(control.guardando ? "Guardando…" : "Guardar escaneo", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(control.guardando)
            }
            .padding()

            if control.guardando {
                ProgressView("Creando archivos 3D…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .navigationTitle("Espacio")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Qué quieres guardar?", isPresented: $pedirGuardar, titleVisibility: .visible) {
            Button("Malla + nube de puntos") { control.guardarEscaneo(malla: true, nubePuntos: true) }
            Button("Solo malla (OBJ, USDZ, STL)") { control.guardarEscaneo(malla: true, nubePuntos: false) }
            Button("Solo nube de puntos con color (PLY)") { control.guardarEscaneo(malla: false, nubePuntos: true) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Escaneo", isPresented: Binding(get: { control.mensajeFinal != nil },
                                              set: { if !$0 { control.mensajeFinal = nil } })) {
            if control.ultimosArchivos.contains(where: Visor3DView.sePuedeVer) {
                Button("Ver en 3D") { verVisor = true }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(control.mensajeFinal ?? "")
        }
        .fullScreenCover(isPresented: $verVisor) {
            Visor3DView(archivos: control.ultimosArchivos)
        }
        .onDisappear { control.pausar() }
    }

    private func formato(_ n: Int) -> String {
        n.formatted(.number.locale(Locale(identifier: "es")))
    }
}

private struct Boton: View {
    let titulo: String
    let icono: String
    let accion: () -> Void

    var body: some View {
        Button(action: accion) {
            VStack(spacing: 4) {
                Image(systemName: icono).font(.title3)
                Text(titulo).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct VistaAR: UIViewRepresentable {
    let control: ControladorEscaneo

    func makeUIView(context: Context) -> ARView {
        let vista = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        vista.renderOptions.insert(.disableMotionBlur)
        control.conectar(vista)
        return vista
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}
