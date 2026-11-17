package ch.bbw.trips.storage;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;

/** Ablage auf dem lokalen Dateisystem bzw. einem gemounteten Volume (RefCard 04). */
@Service
@ConditionalOnProperty(name = "app.storage.type", havingValue = "local", matchIfMissing = true)
public class LocalStorageService implements StorageService {

	private final Path root;

	public LocalStorageService(@Value("${app.storage.location:./uploads}") String location) throws IOException {
		this.root = Paths.get(location).toAbsolutePath().normalize();
		Files.createDirectories(root);
	}

	@Override
	public String store(MultipartFile file) {
		String filename = ImageFiles.newFilename(file);
		try (InputStream in = file.getInputStream()) {
			Files.copy(in, resolve(filename), StandardCopyOption.REPLACE_EXISTING);
		} catch (IOException e) {
			throw new StorageException(StorageException.Reason.UNAVAILABLE,
					"Datei konnte nicht gespeichert werden", e);
		}
		return filename;
	}

	@Override
	public Resource load(String reference) {
		Path file = resolve(reference);
		if (!Files.isReadable(file)) {
			throw new StorageException(StorageException.Reason.NOT_FOUND,
					"Datei nicht gefunden: " + reference, null);
		}
		return new FileSystemResource(file);
	}

	@Override
	public void delete(String reference) {
		try {
			Files.deleteIfExists(resolve(reference));
		} catch (IOException e) {
			throw new StorageException(StorageException.Reason.UNAVAILABLE,
					"Datei konnte nicht gelöscht werden", e);
		}
	}

	private Path resolve(String reference) {
		ImageFiles.requireSafeReference(reference);
		Path target = root.resolve(reference).normalize();
		if (!root.equals(target.getParent())) {
			throw new InvalidFileException("Ungültiger Dateipfad");
		}
		return target;
	}
}
