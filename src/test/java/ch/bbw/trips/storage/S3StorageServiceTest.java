package ch.bbw.trips.storage;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockMultipartFile;
import software.amazon.awssdk.core.exception.SdkClientException;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.DeleteObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class S3StorageServiceTest {

	private static final String BUCKET = "test-bucket";
	private static final String PREFIX = "employee-photos/";
	private static final String REFERENCE = "00000000-0000-0000-0000-000000000000.png";

	private final S3Client s3 = mock(S3Client.class);
	private final S3StorageService storage = new S3StorageService(s3, BUCKET, PREFIX);

	@Test
	void storesObjectUnderPrefixWithContentType() {
		String reference = storage.store(new MockMultipartFile("file", "portrait.png", "image/png", new byte[]{1, 2}));

		ArgumentCaptor<PutObjectRequest> request = ArgumentCaptor.forClass(PutObjectRequest.class);
		verify(s3).putObject(request.capture(), any(RequestBody.class));
		assertThat(request.getValue().bucket()).isEqualTo(BUCKET);
		assertThat(request.getValue().key()).isEqualTo(PREFIX + reference);
		assertThat(request.getValue().contentType()).isEqualTo("image/png");
	}

	@Test
	void doesNotCallS3ForInvalidFile() {
		assertThatThrownBy(() -> storage.store(new MockMultipartFile("file", "a.gif", "image/gif", new byte[]{1})))
				.isInstanceOf(InvalidFileException.class);

		verify(s3, never()).putObject(any(PutObjectRequest.class), any(RequestBody.class));
	}

	@Test
	void deletesObjectUnderPrefix() {
		storage.delete(REFERENCE);

		ArgumentCaptor<DeleteObjectRequest> request = ArgumentCaptor.forClass(DeleteObjectRequest.class);
		verify(s3).deleteObject(request.capture());
		assertThat(request.getValue().key()).isEqualTo(PREFIX + REFERENCE);
	}

	@Test
	void reportsMissingPermissionsAsAccessDenied() {
		when(s3.putObject(any(PutObjectRequest.class), any(RequestBody.class)))
				.thenThrow(S3Exception.builder().statusCode(403).message("Access Denied").build());

		assertThatThrownBy(() -> storage.store(new MockMultipartFile("file", "a.png", "image/png", new byte[]{1})))
				.isInstanceOf(StorageException.class)
				.extracting(e -> ((StorageException) e).getReason())
				.isEqualTo(StorageException.Reason.ACCESS_DENIED);
	}

	@Test
	void reportsMissingObjectAsNotFound() {
		when(s3.getObject(any(GetObjectRequest.class)))
				.thenThrow(NoSuchKeyException.builder().statusCode(404).message("no such key").build());

		assertThatThrownBy(() -> storage.load(REFERENCE))
				.isInstanceOf(StorageException.class)
				.extracting(e -> ((StorageException) e).getReason())
				.isEqualTo(StorageException.Reason.NOT_FOUND);
	}

	@Test
	void reportsUnreachableStorageAsUnavailable() {
		when(s3.getObject(any(GetObjectRequest.class)))
				.thenThrow(SdkClientException.create("Unable to execute HTTP request"));

		assertThatThrownBy(() -> storage.load(REFERENCE))
				.isInstanceOf(StorageException.class)
				.extracting(e -> ((StorageException) e).getReason())
				.isEqualTo(StorageException.Reason.UNAVAILABLE);
	}

	@Test
	void rejectsReferenceWithPathBeforeCallingS3() {
		assertThatThrownBy(() -> storage.load("../other-prefix/secret.png"))
				.isInstanceOf(InvalidFileException.class);

		verify(s3, never()).getObject(any(GetObjectRequest.class));
	}
}
