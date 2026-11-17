package ch.bbw.trips.storage;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.core.io.InputStreamResource;
import org.springframework.core.io.Resource;
import org.springframework.web.multipart.MultipartFile;
import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

import java.io.IOException;
import java.io.InputStream;

/**
 * Ablage in einem S3-Bucket (RefCard 05). Alle Objekte liegen unter einem festen Präfix,
 * damit die IAM-/Bucket-Policy genau diesen Bereich freigeben kann.
 */
public class S3StorageService implements StorageService {
	private static final Logger log = LoggerFactory.getLogger(S3StorageService.class);

	private final S3Client s3;
	private final String bucket;
	private final String prefix;

	public S3StorageService(S3Client s3, String bucket, String prefix) {
		this.s3 = s3;
		this.bucket = bucket;
		this.prefix = prefix;
	}

	@Override
	public String store(MultipartFile file) {
		String filename = ImageFiles.newFilename(file);
		PutObjectRequest request = PutObjectRequest.builder()
				.bucket(bucket).key(key(filename)).contentType(file.getContentType()).build();
		try (InputStream in = file.getInputStream()) {
			s3.putObject(request, RequestBody.fromInputStream(in, file.getSize()));
		} catch (SdkException e) {
			throw translate("speichern", e);
		} catch (IOException e) {
			throw new StorageException(StorageException.Reason.UNAVAILABLE,
					"Datei konnte nicht gelesen werden", e);
		}
		return filename;
	}

	@Override
	public Resource load(String reference) {
		ImageFiles.requireSafeReference(reference);
		try {
			ResponseInputStream<GetObjectResponse> object =
					s3.getObject(GetObjectRequest.builder().bucket(bucket).key(key(reference)).build());
			Long length = object.response().contentLength();
			return new InputStreamResource(object) {
				@Override
				public long contentLength() {
					return length == null ? -1 : length;
				}
			};
		} catch (SdkException e) {
			throw translate("laden", e);
		}
	}

	@Override
	public void delete(String reference) {
		ImageFiles.requireSafeReference(reference);
		try {
			s3.deleteObject(DeleteObjectRequest.builder().bucket(bucket).key(key(reference)).build());
		} catch (SdkException e) {
			throw translate("löschen", e);
		}
	}

	/**
	 * Prüft beim Start einmal, ob der Task tatsächlich in den Bucket schreiben darf. Fehlende Rechte
	 * sollen sofort im Log auffallen und nicht erst beim ersten Upload einer Benutzerin.
	 */
	@EventListener(ApplicationReadyEvent.class)
	public void verifyAccess() {
		String probe = key(".write-check");
		try {
			s3.putObject(PutObjectRequest.builder().bucket(bucket).key(probe).contentType("text/plain").build(),
					RequestBody.fromString("ok"));
			s3.deleteObject(DeleteObjectRequest.builder().bucket(bucket).key(probe).build());
			log.info("S3-Storage bereit: s3://{}/{}", bucket, prefix);
		} catch (SdkException e) {
			log.error("S3-Storage NICHT nutzbar (s3://{}/{}): {} - Bild-Uploads werden fehlschlagen. "
							+ "Prüfen: Bucket-Name, Region, Task-Rolle und Bucket-Policy.",
					bucket, prefix, translate("prüfen", e).getMessage());
		}
	}

	private String key(String filename) {
		return prefix + filename;
	}

	private StorageException translate(String action, SdkException e) {
		if (e instanceof NoSuchKeyException) {
			return new StorageException(StorageException.Reason.NOT_FOUND, "Datei nicht gefunden", e);
		}
		if (e instanceof S3Exception s3Exception) {
			int status = s3Exception.statusCode();
			if (status == 401 || status == 403) {
				return new StorageException(StorageException.Reason.ACCESS_DENIED,
						"Zugriff auf den Bild-Storage verweigert (fehlende Berechtigung auf den Bucket)", e);
			}
			if (status == 404) {
				return new StorageException(StorageException.Reason.UNAVAILABLE,
						"Bild-Storage nicht gefunden (Bucket existiert nicht)", e);
			}
		}
		log.warn("S3-Fehler beim Datei {}: {}", action, e.getMessage());
		return new StorageException(StorageException.Reason.UNAVAILABLE,
				"Bild-Storage ist momentan nicht erreichbar", e);
	}
}
