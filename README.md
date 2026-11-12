# Escáner 3D (LiDAR para iPhone)

App nativa para iPhone (Swift + ARKit + RealityKit) que usa el sensor **LiDAR** para escanear en 3D.

## Qué hace

| Modo | Cómo funciona | Archivos que crea |
|---|---|---|
| **Espacio / habitación** | ARKit reconstruye una malla en vivo con el LiDAR (se ve dibujada sobre la cámara). Al mismo tiempo junta una nube de puntos con el color de la cámara. | `malla.obj`, `malla.usdz`, `malla.stl`, `nube_puntos.ply` |
| **Objeto con textura** | Object Capture de Apple: detectas el objeto, lo rodeas y el iPhone toma fotos solo. Luego el propio iPhone crea un modelo realista. | `modelo.usdz` (con textura) |
| **Mis escaneos** | Ver en 3D y en realidad aumentada (Quick Look), compartir o borrar. Los archivos también están en *Archivos › En mi iPhone › Escáner 3D › Escaneos*. | |

- La malla del modo Espacio es gris (sin textura): sirve para medir, planos, Blender, impresión 3D.
- Para algo con colores reales: la nube de puntos `.ply` (MeshLab, CloudCompare, Blender) o el modo Objeto.

## Requisitos

- iPhone **con LiDAR**: iPhone 12 Pro / Pro Max o más nuevo (solo modelos Pro), o iPad Pro 2020+.
- iOS 17 o más nuevo.

## Cómo se compila

GitHub Actions (`.github/workflows/ios.yml`) usa una Mac de GitHub, genera el proyecto con XcodeGen y compila
un **.ipa sin firmar**. Sale en *Actions › artifact `EscaneoLidar-ipa`* y en *Releases*.

## Cómo instalarlo en el iPhone (sin Mac)

Apple no deja instalar un .ipa sin firmarlo. Con una cuenta de Apple normal (gratis) se puede firmar desde Windows:

1. Instalar **Sideloadly** (sideloadly.io) en la PC con Windows, junto con iTunes e iCloud *de la web de Apple* (no los de Microsoft Store).
2. Conectar el iPhone por cable, abrir Sideloadly, arrastrar `EscaneoLidar.ipa`, poner tu Apple ID y darle *Start*.
3. En el iPhone: *Ajustes › Privacidad y seguridad › Modo de desarrollador* → activar (pide reiniciar).
4. *Ajustes › General › VPN y gestión de dispositivos* → confiar en tu Apple ID.

Con Apple ID gratis la app dura **7 días**; después se vuelve a instalar igual con Sideloadly (los escaneos guardados se conservan si no la borras).
Con la cuenta de desarrollador de Apple (99 USD/año) dura 1 año y se puede usar TestFlight.

## Con una Mac (opcional)

```bash
brew install xcodegen
xcodegen generate
open EscaneoLidar.xcodeproj
```
Elegir tu equipo en *Signing & Capabilities* y darle Run con el iPhone conectado.
