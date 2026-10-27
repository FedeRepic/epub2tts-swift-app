# Procedencia de activos de desarrollo

- Repositorio: `aufklarer/Supertonic-3-CoreML-FP16`
- Revisión descargada: `2e5aa113851b85195fb694aae1d62cd640365f6b`
- Descarga: 2026-10-16
- Licencia declarada en la ficha: OpenRAIL-M. Antes de distribuir, revisar y archivar el texto completo de licencia y obligaciones de atribución.
- Tamaño local descargado: aproximadamente 345 MB. La ficha del modelo declara aproximadamente 189 MB para FP16; no asumir que son equivalentes al tamaño del paquete final.

Los pesos binarios de las cuatro redes descargadas coinciden con los SHA-256 publicados por Hugging Face:

| Activo | SHA-256 |
| --- | --- |
| DurationPredictor `weight.bin` | `7f709c544087966d6b2538ac50b7a4014d6e1049e21d713cf3bc71c4c5b9307c` |
| TextEncoder `weight.bin` | `9618a75954419ab1e19d1f0946df20ab391d993632f0d2478085c32ddc17e8d7` |
| VectorEstimator `weight.bin` | `593cb7df14efd8d98e6e0543e0c18fb5778f3602e36164ec0dcf35f5c713e1fd` |
| Vocoder `weight.bin` | `b45e4c17a45cc4de30dcedae9f662548aa35f8f9763632c342b8bbef3089fcee` |

No añadir estos archivos al control de versiones sin una decisión explícita sobre almacenamiento y redistribución.

La geometría e integración inicial se contrastaron contra el proyecto de referencia [soniqo/speech-swift](https://github.com/soniqo/speech-swift), con licencia Apache-2.0. Esta aplicación no incorpora dicho paquete ni sus dependencias; toda distribución futura debe revisar y conservar los avisos aplicables.
