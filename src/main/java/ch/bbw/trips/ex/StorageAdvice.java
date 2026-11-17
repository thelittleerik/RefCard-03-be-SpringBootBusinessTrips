package ch.bbw.trips.ex;

import ch.bbw.trips.storage.InvalidFileException;
import ch.bbw.trips.storage.StorageException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.multipart.MaxUploadSizeExceededException;

import java.util.Map;

@RestControllerAdvice
public class StorageAdvice {
	private static final Logger log = LoggerFactory.getLogger(StorageAdvice.class);

	@ExceptionHandler(InvalidFileException.class)
	ResponseEntity<Map<String, String>> invalidFile(InvalidFileException ex) {
		return error(HttpStatus.BAD_REQUEST, ex.getMessage());
	}

	@ExceptionHandler(MaxUploadSizeExceededException.class)
	ResponseEntity<Map<String, String>> tooLarge(MaxUploadSizeExceededException ex) {
		return error(HttpStatus.CONTENT_TOO_LARGE, "Datei ist zu gross (maximal 5 MB)");
	}

	/**
	 * Storage-Fehler sind keine Fehler des Clients: fehlende Bucket-Rechte werden als 502 gemeldet,
	 * ein nicht erreichbarer Storage als 503. Die Ursache steht im Log, nicht in der Antwort.
	 */
	@ExceptionHandler(StorageException.class)
	ResponseEntity<Map<String, String>> storage(StorageException ex) {
		HttpStatus status = switch (ex.getReason()) {
			case NOT_FOUND -> HttpStatus.NOT_FOUND;
			case ACCESS_DENIED -> HttpStatus.BAD_GATEWAY;
			case UNAVAILABLE -> HttpStatus.SERVICE_UNAVAILABLE;
		};
		if (status.is5xxServerError()) {
			log.error("Storage-Fehler ({}): {}", ex.getReason(), ex.getMessage(), ex.getCause());
		}
		return error(status, ex.getMessage());
	}

	private static ResponseEntity<Map<String, String>> error(HttpStatus status, String message) {
		return ResponseEntity.status(status).body(Map.of("error", message));
	}
}
