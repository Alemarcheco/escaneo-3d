import Foundation

/// Carpeta donde se guardan los escaneos (visible en la app Archivos).
enum Almacen {
    static var carpetaEscaneos: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("Escaneos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Crea una carpeta nueva con fecha y hora, p. ej. "Espacio 2026-11-12 18-05-31".
    static func nuevaCarpeta(prefijo: String) -> URL {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es")
        f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let url = carpetaEscaneos.appendingPathComponent("\(prefijo) \(f.string(from: Date()))", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Carpeta temporal para fotos y checkpoints de Object Capture.
    static func carpetaTemporal(_ nombre: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nombre, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
