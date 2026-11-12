import ARKit
import ModelIO

/// Convierte las mallas del LiDAR (ARMeshAnchor) en un archivo 3D.
enum ExportadorMalla {
    enum Fallo: LocalizedError {
        case sinMalla
        case formatoNoSoportado(String)
        var errorDescription: String? {
            switch self {
            case .sinMalla: return "Todavía no hay malla. Mueve el iPhone despacio apuntando a las superficies."
            case .formatoNoSoportado(let e): return "Este iPhone no puede exportar .\(e)"
            }
        }
    }

    static func asset(de anclas: [ARMeshAnchor]) throws -> MDLAsset {
        let asset = MDLAsset()
        for ancla in anclas {
            if let malla = malla(de: ancla) { asset.add(malla) }
        }
        if asset.count == 0 { throw Fallo.sinMalla }
        return asset
    }

    /// Exporta a cada extensión pedida (obj, usdz, usdc, ply, stl). Devuelve los archivos creados.
    static func exportar(_ anclas: [ARMeshAnchor], carpeta: URL, nombre: String, extensiones: [String]) throws -> [URL] {
        let asset = try asset(de: anclas)
        var hechos: [URL] = []
        for ext in extensiones {
            guard MDLAsset.canExportFileExtension(ext) else { continue }
            let url = carpeta.appendingPathComponent("\(nombre).\(ext)")
            try asset.export(to: url)
            hechos.append(url)
        }
        if hechos.isEmpty { throw Fallo.formatoNoSoportado(extensiones.joined(separator: ", ")) }
        return hechos
    }

    /// Cuenta los triángulos de todas las anclas (para mostrar en pantalla).
    static func triangulos(_ anclas: [ARMeshAnchor]) -> Int {
        anclas.reduce(0) { $0 + $1.geometry.faces.count }
    }

    private static let material: MDLMaterial = {
        let m = MDLMaterial(name: "gris", scatteringFunction: MDLPhysicallyPlausibleScatteringFunction())
        m.setProperty(MDLMaterialProperty(name: "baseColor", semantic: .baseColor, float3: SIMD3<Float>(0.8, 0.8, 0.82)))
        return m
    }()

    private static func malla(de ancla: ARMeshAnchor) -> MDLMesh? {
        let geo = ancla.geometry
        let vertices = geo.vertices
        let caras = geo.faces
        guard vertices.count > 0, caras.count > 0 else { return nil }

        // Vértices pasados a coordenadas del mundo, para que todas las piezas encajen.
        var posiciones = [SIMD3<Float>]()
        posiciones.reserveCapacity(vertices.count)
        let base = vertices.buffer.contents().advanced(by: vertices.offset)
        for i in 0..<vertices.count {
            let p = base.advanced(by: i * vertices.stride).assumingMemoryBound(to: Float.self)
            let m = ancla.transform * SIMD4<Float>(p[0], p[1], p[2], 1)
            posiciones.append(SIMD3<Float>(m.x, m.y, m.z))
        }
        var datosV = Data(capacity: posiciones.count * 12)
        for p in posiciones {
            var x = p.x, y = p.y, z = p.z
            withUnsafeBytes(of: &x) { datosV.append(contentsOf: $0) }
            withUnsafeBytes(of: &y) { datosV.append(contentsOf: $0) }
            withUnsafeBytes(of: &z) { datosV.append(contentsOf: $0) }
        }

        let totalIndices = caras.count * caras.indexCountPerPrimitive
        let bytesIndices = totalIndices * caras.bytesPerIndex
        let datosI = Data(bytes: caras.buffer.contents(), count: bytesIndices)
        let tipoIndice: MDLIndexBitDepth = caras.bytesPerIndex == 2 ? .uInt16 : .uInt32

        let bufferV = MDLMeshBufferData(type: .vertex, data: datosV)
        let bufferI = MDLMeshBufferData(type: .index, data: datosI)

        let submalla = MDLSubmesh(indexBuffer: bufferI,
                                  indexCount: totalIndices,
                                  indexType: tipoIndice,
                                  geometryType: .triangles,
                                  material: material)

        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                      format: .float3,
                                                      offset: 0,
                                                      bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 12)

        let malla = MDLMesh(vertexBuffer: bufferV,
                            vertexCount: vertices.count,
                            descriptor: descriptor,
                            submeshes: [submalla])
        malla.name = ancla.identifier.uuidString
        return malla
    }
}
