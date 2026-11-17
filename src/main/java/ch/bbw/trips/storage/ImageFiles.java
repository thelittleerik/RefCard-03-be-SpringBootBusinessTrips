package ch.bbw.trips.storage;

import org.springframework.web.multipart.MultipartFile;

import java.util.Map;
import java.util.UUID;

/** Gemeinsame Validierung und Namensvergabe für beide Storage-Implementierungen. */
final class ImageFiles {

	private static final Map<String, String> EXTENSION_BY_TYPE = Map.of(
			"image/png", "png",
			"image/jpeg", "jpg",
			"image/webp", "webp");

	private ImageFiles() {
	}

	/**
	 * Prüft die Datei und erzeugt einen kollisionsfreien Namen. Der Original-Dateiname wird bewusst
	 * nicht übernommen: Die Endung kommt aus der Whitelist, der Rest ist eine UUID.
	 */
	static String newFilename(MultipartFile file) {
		if (file == null || file.isEmpty()) {
			throw new InvalidFileException("Datei ist leer");
		}
		String extension = EXTENSION_BY_TYPE.get(file.getContentType());
		if (extension == null) {
			throw new InvalidFileException("Nicht unterstützter Dateityp: " + file.getContentType()
					+ " (erlaubt: PNG, JPEG, WebP)");
		}
		return UUID.randomUUID() + "." + extension;
	}

	/** Lässt nur Namen zu, wie {@link #newFilename} sie erzeugt - keine Pfadanteile. */
	static void requireSafeReference(String reference) {
		if (reference == null || !reference.matches("[A-Za-z0-9-]+\\.(png|jpg|webp)")) {
			throw new InvalidFileException("Ungültige Dateireferenz");
		}
	}
}
