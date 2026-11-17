package ch.bbw.trips.storage;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnMissingBean;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.S3ClientBuilder;

import java.net.URI;

@Configuration
@ConditionalOnProperty(name = "app.storage.type", havingValue = "s3")
public class S3StorageConfig {

	/**
	 * Zugangsdaten kommen aus der Default-Credential-Chain des SDK: auf ECS die Task-Rolle,
	 * lokal (MinIO) die Umgebungsvariablen AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY. Im Code steht nichts davon.
	 */
	@Bean
	@ConditionalOnMissingBean
	public S3Client s3Client(@Value("${app.storage.s3.region}") String region,
							 @Value("${app.storage.s3.endpoint:}") String endpoint,
							 @Value("${app.storage.s3.path-style-access:false}") boolean pathStyleAccess) {
		S3ClientBuilder builder = S3Client.builder().region(Region.of(region));
		if (StringUtils.hasText(endpoint)) {
			builder.endpointOverride(URI.create(endpoint));
		}
		return builder.forcePathStyle(pathStyleAccess).build();
	}

	@Bean
	public StorageService s3StorageService(S3Client s3Client,
										   @Value("${app.storage.s3.bucket}") String bucket,
										   @Value("${app.storage.s3.prefix:employee-photos/}") String prefix) {
		if (!StringUtils.hasText(bucket)) {
			throw new IllegalStateException("app.storage.s3.bucket (Umgebungsvariable S3_BUCKET) ist nicht gesetzt");
		}
		return new S3StorageService(s3Client, bucket, prefix);
	}
}
