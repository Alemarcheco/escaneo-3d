import ARKit
import simd

/// Acumula puntos 3D con color a partir del mapa de profundidad del LiDAR.
final class NubeDePuntos {
    struct Punto {
        var posicion: SIMD3<Float>
        var r: UInt8, g: UInt8, b: UInt8
    }

    private(set) var puntos: [Punto] = []
    private var ocupados = Set<SIMD3<Int32>>()

    /// Tamaño del vóxel para no repetir puntos (metros).
    var resolucion: Float = 0.01
    /// Distancia máxima que se acepta (metros). El LiDAR mide bien hasta ~5 m.
    var distanciaMaxima: Float = 4.0
    /// Tomar 1 de cada `paso` píxeles del mapa de profundidad (256x192).
    var paso = 2
    var limite = 3_000_000

    var cantidad: Int { puntos.count }

    func vaciar() {
        puntos.removeAll(keepingCapacity: false)
        ocupados.removeAll(keepingCapacity: false)
    }

    /// Agrega los puntos de un cuadro de ARKit. Devuelve cuántos puntos nuevos entraron.
    @discardableResult
    func agregar(cuadro: ARFrame) -> Int {
        guard puntos.count < limite,
              let profundidad = cuadro.sceneDepth ?? cuadro.smoothedSceneDepth else { return 0 }
        if case .normal = cuadro.camera.trackingState {} else { return 0 }

        let mapa = profundidad.depthMap
        let confianza = profundidad.confidenceMap
        let imagen = cuadro.capturedImage

        CVPixelBufferLockBaseAddress(mapa, .readOnly)
        CVPixelBufferLockBaseAddress(imagen, .readOnly)
        if let c = confianza { CVPixelBufferLockBaseAddress(c, .readOnly) }
        defer {
            CVPixelBufferUnlockBaseAddress(mapa, .readOnly)
            CVPixelBufferUnlockBaseAddress(imagen, .readOnly)
            if let c = confianza { CVPixelBufferUnlockBaseAddress(c, .readOnly) }
        }

        let anchoP = CVPixelBufferGetWidth(mapa)
        let altoP = CVPixelBufferGetHeight(mapa)
        let filaP = CVPixelBufferGetBytesPerRow(mapa)
        guard let baseP = CVPixelBufferGetBaseAddress(mapa) else { return 0 }

        var baseC: UnsafeMutableRawPointer? = nil
        var filaC = 0
        if let c = confianza {
            baseC = CVPixelBufferGetBaseAddress(c)
            filaC = CVPixelBufferGetBytesPerRow(c)
        }

        // Imagen de la cámara en YCbCr bi-planar (420f).
        guard CVPixelBufferGetPlaneCount(imagen) >= 2,
              let baseY = CVPixelBufferGetBaseAddressOfPlane(imagen, 0),
              let baseUV = CVPixelBufferGetBaseAddressOfPlane(imagen, 1) else { return 0 }
        let filaY = CVPixelBufferGetBytesPerRowOfPlane(imagen, 0)
        let filaUV = CVPixelBufferGetBytesPerRowOfPlane(imagen, 1)
        let anchoI = CVPixelBufferGetWidthOfPlane(imagen, 0)
        let altoI = CVPixelBufferGetHeightOfPlane(imagen, 0)

        let k = cuadro.camera.intrinsics            // para la resolución de la imagen
        let fx = k[0][0], fy = k[1][1], cx = k[2][0], cy = k[2][1]
        let escalaX = Float(anchoI) / Float(anchoP)
        let escalaY = Float(altoI) / Float(altoP)
        let camara = cuadro.camera.transform

        var nuevos = 0
        var v = 0
        while v < altoP {
            let filaProf = baseP.advanced(by: v * filaP).assumingMemoryBound(to: Float32.self)
            var u = 0
            while u < anchoP {
                defer { u += paso }
                if let bc = baseC {
                    let conf = bc.advanced(by: v * filaC).assumingMemoryBound(to: UInt8.self)[u]
                    if conf < UInt8(ARConfidenceLevel.high.rawValue) { continue }
                }
                let d = filaProf[u]
                if !(d > 0.1 && d < distanciaMaxima) { continue }

                let xi = Float(u) * escalaX
                let yi = Float(v) * escalaY
                // Coordenadas de cámara de ARKit: x derecha, y arriba, -z hacia adelante.
                let local = SIMD4<Float>((xi - cx) * d / fx, -(yi - cy) * d / fy, -d, 1)
                let mundo = camara * local
                let p = SIMD3<Float>(mundo.x, mundo.y, mundo.z)

                let clave = SIMD3<Int32>(Int32((p.x / resolucion).rounded()),
                                         Int32((p.y / resolucion).rounded()),
                                         Int32((p.z / resolucion).rounded()))
                if ocupados.contains(clave) { continue }
                ocupados.insert(clave)

                let px = min(Int(xi), anchoI - 1)
                let py = min(Int(yi), altoI - 1)
                let y = Float(baseY.advanced(by: py * filaY).assumingMemoryBound(to: UInt8.self)[px])
                let uv = baseUV.advanced(by: (py / 2) * filaUV).assumingMemoryBound(to: UInt8.self)
                let cb = Float(uv[(px / 2) * 2]) - 128
                let cr = Float(uv[(px / 2) * 2 + 1]) - 128
                let r = y + 1.402 * cr
                let g = y - 0.344136 * cb - 0.714136 * cr
                let b = y + 1.772 * cb

                puntos.append(Punto(posicion: p, r: NubeDePuntos.byte(r), g: NubeDePuntos.byte(g), b: NubeDePuntos.byte(b)))
                nuevos += 1
            }
            v += paso
        }
        return nuevos
    }

    private static func byte(_ x: Float) -> UInt8 {
        UInt8(max(0, min(255, x.rounded())))
    }

    /// Guarda la nube en formato PLY binario (lo abren MeshLab, CloudCompare, Blender).
    func guardarPLY(en url: URL) throws {
        var datos = Data()
        let cabecera = """
        ply
        format binary_little_endian 1.0
        comment Escaner 3D (LiDAR iPhone)
        element vertex \(puntos.count)
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header\n
        """
        datos.append(cabecera.data(using: .ascii)!)
        datos.reserveCapacity(datos.count + puntos.count * 15)
        for p in puntos {
            var x = p.posicion.x, y = p.posicion.y, z = p.posicion.z
            withUnsafeBytes(of: &x) { datos.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { datos.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { datos.append(contentsOf: $0) }
            datos.append(contentsOf: [p.r, p.g, p.b])
        }
        try datos.write(to: url)
    }
}
