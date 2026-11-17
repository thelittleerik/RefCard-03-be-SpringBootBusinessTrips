package ch.bbw.trips.storage;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class LocalStorageServiceTest {

	@TempDir
	Path tempDir;

	private Path root;
	private LocalStorageService storage;

	@BeforeEach
	void setUp() throws IOException {
		// Der Storage liegt eine Ebene tiefer, damit auch "ausserhalb des Storage" noch im Temp-Verzeichnis ist.
		root = tempDir.resolve("storage");
		storage = new LocalStorageService(root.toString());
	}

	@Test
	void storesFileUnderGeneratedNameAndLoadsItAgain() throws IOException {
		byte[] content = {1, 2, 3};

		String reference = storage.store(new MockMultipartFile("file", "../../evil.png", "image/png", content));

		assertThat(reference).matches("[0-9a-f-]{36}\\.png");
		assertThat(root.resolve(reference)).exists();
		assertThat(storage.load(reference).getContentAsByteArray()).isEqualTo(content);
	}

	@Test
	void deletesStoredFile() {
		String reference = storage.store(new MockMultipartFile("file", "a.jpg", "image/jpeg", new byte[]{1}));

		storage.delete(reference);

		assertThat(root.resolve(reference)).doesNotExist();
	}

	@Test
	void rejectsEmptyFile() {
		assertThatThrownBy(() -> storage.store(new MockMultipartFile("file", "a.png", "image/png", new byte[0])))
				.isInstanceOf(InvalidFileException.class);
	}

	@Test
	void rejectsUnsupportedContentType() {
		assertThatThrownBy(() -> storage.store(new MockMultipartFile("file", "a.pdf", "application/pdf", new byte[]{1})))
				.isInstanceOf(InvalidFileException.class)
				.hasMessageContaining("application/pdf");
		assertThat(root).isEmptyDirectory();
	}

	@Test
	void rejectsReferenceThatLeavesTheStorageRoot() throws IOException {
		Path outside = Files.createFile(tempDir.resolve("outside.png"));

		assertThatThrownBy(() -> storage.load("../" + outside.getFileName()))
				.isInstanceOf(InvalidFileException.class);
	}

	@Test
	void reportsMissingFileAsNotFound() {
		assertThatThrownBy(() -> storage.load("00000000-0000-0000-0000-000000000000.png"))
				.isInstanceOf(StorageException.class)
				.extracting(e -> ((StorageException) e).getReason())
				.isEqualTo(StorageException.Reason.NOT_FOUND);
	}
}
