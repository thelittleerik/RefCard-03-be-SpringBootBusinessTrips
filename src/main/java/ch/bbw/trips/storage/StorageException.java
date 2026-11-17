package ch.bbw.trips.storage;

public class StorageException extends RuntimeException {
	private static final long serialVersionUID = 1L;

	public enum Reason {
		/** Die Datei existiert im Storage nicht (mehr). */
		NOT_FOUND,
		/** Der Storage lehnt den Zugriff ab, z. B. fehlende IAM-Rechte auf den Bucket. */
		ACCESS_DENIED,
		/** Der Storage ist nicht erreichbar oder antwortet mit einem Fehler. */
		UNAVAILABLE
	}

	private final Reason reason;

	public StorageException(Reason reason, String message, Throwable cause) {
		super(message, cause);
		this.reason = reason;
	}

	public Reason getReason() {
		return reason;
	}
}
