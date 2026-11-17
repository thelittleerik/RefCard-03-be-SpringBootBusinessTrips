package ch.bbw.trips.storage;

import org.springframework.core.io.Resource;
import org.springframework.web.multipart.MultipartFile;

/**
 * Ablage für hochgeladene Bilder. Die Datenbank hält nur die zurückgegebene Referenz,
 * nie die Bilddaten selbst. Implementierungen: lokales Dateisystem (RefCard 04) und S3 (RefCard 05).
 */
public interface StorageService {

	/** Speichert die Datei und liefert die Referenz, unter der sie wieder geladen werden kann. */
	String store(MultipartFile file);

	Resource load(String reference);

	void delete(String reference);
}
