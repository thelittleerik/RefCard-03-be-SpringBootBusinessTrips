package ch.bbw.trips.repo;

import ch.bbw.trips.storage.StorageException;
import ch.bbw.trips.storage.StorageService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Fehlerfälle des Storage (z. B. fehlende Bucket-Rechte) dürfen nicht als Stacktrace/500 beim Client ankommen. */
@SpringBootTest
class EmployeePhotoStorageFailureTest {

	@Autowired
	private WebApplicationContext context;

	@Autowired
	private EmployeeRepository employeeRepository;

	@MockitoBean
	private StorageService storageService;

	private MockMvc mvc;
	private Long employeeId;

	@BeforeEach
	void setUp() {
		mvc = MockMvcBuilders.webAppContextSetup(context).build();
		employeeId = employeeRepository.save(new Employee(null, "Failure Tester", "QA")).getId();
	}

	@Test
	void missingBucketPermissionsAreReportedAs502AndNothingIsLinked() throws Exception {
		when(storageService.store(any())).thenThrow(new StorageException(
				StorageException.Reason.ACCESS_DENIED, "Zugriff auf den Bild-Storage verweigert", null));

		mvc.perform(multipart("/v1/employees/{id}/photo", employeeId)
						.file(new MockMultipartFile("file", "me.png", "image/png", new byte[]{1})))
				.andExpect(status().isBadGateway())
				.andExpect(jsonPath("$.error").value("Zugriff auf den Bild-Storage verweigert"));

		assertThat(employeeRepository.findById(employeeId).orElseThrow().getProfilePictureFilename()).isNull();
	}

	@Test
	void unreachableStorageIsReportedAs503() throws Exception {
		when(storageService.store(any())).thenThrow(new StorageException(
				StorageException.Reason.UNAVAILABLE, "Bild-Storage ist momentan nicht erreichbar", null));

		mvc.perform(multipart("/v1/employees/{id}/photo", employeeId)
						.file(new MockMultipartFile("file", "me.png", "image/png", new byte[]{1})))
				.andExpect(status().isServiceUnavailable());
	}
}
