# ReaderTTS

Lector EPUB nativo para iOS y iPadOS con síntesis de voz local mediante Core ML. Está pensado para leer y escuchar libros sin enviar el contenido a servicios externos.

## Funciones principales

- Biblioteca local de EPUB sin DRM, con portadas, búsqueda, orden y eliminación de libros.
- Lectura con [Readium](https://github.com/readium/swift-toolkit): índice, gestos, progreso persistente y marcadores.
- Voz local con Supertonic 3 Core ML FP16: diez estilos de voz, español o inglés elegidos por la persona lectora, velocidad y precarga configurables.
- Reproducción en segundo plano, controles del sistema, temporizador de sueño y reanudación/pausa.
- Seguimiento visual del fragmento reproducido con color configurable.
- Ajustes globales de tipografía, tamaño, interlineado, espaciado, márgenes y apariencia clara/oscura.

## Arquitectura

- `Features/LibraryView.swift`: biblioteca e importación.
- `Features/ReadiumReaderView.swift`: lector Readium, progreso, marcadores y experiencia de lectura.
- `Features/ReaderSupport.swift`: ajustes compartidos, cola de síntesis y reproducción.
- `TTS/SupertonicCoreMLEngine.swift`: tokenización, predicción de duración, denoising ODE y vocoder Core ML.
- `EPUB/EPUBImporter.swift`: importación segura, extracción privada y metadatos del EPUB.

Los libros se extraen dentro del sandbox de la app. La posición, marcadores y preferencias se guardan localmente.

## Requisitos y ejecución

1. Abrir `ReaderTTS.xcodeproj` con Xcode 26.2 o posterior.
2. Configurar la firma del target y ejecutar en un dispositivo con iOS/iPadOS 18 o posterior.
3. Importar un EPUB sin DRM desde la biblioteca.

El simulador sirve para revisar la interfaz, pero las mediciones de rendimiento, memoria, batería y Neural Engine deben hacerse en un dispositivo real.

## Modelo de voz

La app integra la variante FP16 de [aufklarer/Supertonic-3-CoreML-FP16](https://huggingface.co/aufklarer/Supertonic-3-CoreML-FP16). Los cuatro modelos compilados (`TextEncoder`, `DurationPredictor`, `VectorEstimator` y `Vocoder`), el índice Unicode y los estilos de voz deben estar incluidos como recursos del target.

El motor usa CPU + Apple Neural Engine para evitar la ruta GPU/Metal que causaba inestabilidad con este exportador en versiones recientes de iPadOS. Los binarios del modelo no se versionan en Git; consulta [ModelProvenance.md](ReaderTTS/Resources/ModelProvenance.md) para la revisión, verificaciones y condiciones de redistribución.

Para habilitar TTS en un clon nuevo, descarga la revisión indicada en ese documento y coloca los directorios compilados `TextEncoder.mlmodelc`, `DurationPredictor.mlmodelc`, `VectorEstimator.mlmodelc` y `Vocoder.mlmodelc` en `ReaderTTS/Resources/CompiledModels/`. El índice Unicode y los estilos de voz sí se incluyen en el repositorio. No añadas los pesos a Git sin revisar previamente la licencia y la autorización de redistribución.

## Privacidad y límites

La lectura, el análisis del EPUB y la síntesis se realizan localmente una vez importado el libro. No se admiten EPUB con DRM. Antes de distribuir la app o los pesos, revisa la licencia OpenRAIL-M y los términos del repositorio del modelo.
