package ch.bbw.trips.repo;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.context.WebApplicationContext;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {"app.storage.type=local", "app.storage.location=target/test-uploads"})
class EmployeePhotoApiTest {

	private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 13, 10, 26, 10};

	@Autowired
	private WebApplicationContext context;

	@Autowired
	private EmployeeRepository employeeRepository;

	private MockMvc mvc;
	private Long employeeId;

	@BeforeEach
	void setUp() {
		mvc = MockMvcBuilders.webAppContextSetup(context).build();
		employeeId = employeeRepository.save(new Employee(null, "Photo Tester", "QA")).getId();
	}

	@Test
	void uploadedPhotoCanBeDownloadedAgain() throws Exception {
		mvc.perform(multipart("/v1/employees/{id}/photo", employeeId)
						.file(new MockMultipartFile("file", "me.png", "image/png", PNG)))
				.andExpect(status().isOk())
				.andExpect(jsonPath("$.profilePictureFilename").isNotEmpty());

		mvc.perform(get("/v1/employees/{id}/photo", employeeId))
				.andExpect(status().isOk())
				.andExpect(content().contentType("image/png"))
				.andExpect(content().bytes(PNG));
	}

	@Test
	void deletedPhotoIsGone() throws Exception {
		mvc.perform(multipart("/v1/employees/{id}/photo", employeeId)
						.file(new MockMultipartFile("file", "me.png", "image/png", PNG)))
				.andExpect(status().isOk());

		mvc.perform(delete("/v1/employees/{id}/photo", employeeId)).andExpect(status().isNoContent());

		mvc.perform(get("/v1/employees/{id}/photo", employeeId)).andExpect(status().isNotFound());
		assertThat(employeeRepository.findById(employeeId).orElseThrow().getProfilePictureFilename()).isNull();
	}

	@Test
	void employeeWithoutPhotoReturns404() throws Exception {
		mvc.perform(get("/v1/employees/{id}/photo", employeeId)).andExpect(status().isNotFound());
	}

	@Test
	void unsupportedFileTypeIsRejectedWith400() throws Exception {
		mvc.perform(multipart("/v1/employees/{id}/photo", employeeId)
						.file(new MockMultipartFile("file", "cv.pdf", "application/pdf", new byte[]{1})))
				.andExpect(status().isBadRequest())
				.andExpect(jsonPath("$.error").isNotEmpty());
	}

	@Test
	void unknownEmployeeReturns404() throws Exception {
		mvc.perform(multipart("/v1/employees/{id}/photo", 999_999L)
						.file(new MockMultipartFile("file", "me.png", "image/png", PNG)))
				.andExpect(status().isNotFound());
	}
}
