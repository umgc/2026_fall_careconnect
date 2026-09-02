package com.careconnect.service;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

import java.util.List;
import java.util.Optional;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;
import org.springframework.http.HttpStatus;

import com.careconnect.dto.TemplateDto;
import com.careconnect.exception.AppException;
import com.careconnect.model.Template;
import com.careconnect.repository.TemplateRepository;

/**
 * Unit tests for {@link TemplateService}.
 *
 * <p>The repository dependency is mocked with Mockito so the service's business
 * logic is validated in isolation — no database or Spring context is required.</p>
 */
class TemplateServiceTest {

    @Mock
    private TemplateRepository templateRepository;

    @InjectMocks
    private TemplateService templateService;

    /**
     * Shared template fixture reused across tests.
     */
    private Template template;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        template = Template.builder()
                .id(1L)
                .name("Morning Routine")
                .description("Daily morning check-in tasks")
                .frequency("daily")
                .taskInterval(1)
                .doCount(7)
                .timeOfDay("08:00")
                .icon(1)
                .build();
    }

    // ==========================================================================
    // getTemplateById
    // ==========================================================================

    @Test
    @DisplayName("getTemplateById: returns the template entity when the ID exists")
    void testGetTemplateById_found() throws Exception {
        // The repository finds the template; the service must return it unchanged.
        when(templateRepository.findById(1L)).thenReturn(Optional.of(template));

        final Template result = templateService.getTemplateById(1L);

        assertNotNull(result);
        assertEquals(1L, result.getId());
        assertEquals("Morning Routine", result.getName());
        verify(templateRepository).findById(1L);
    }

    @Test
    @DisplayName("getTemplateById: throws AppException(NOT_FOUND) when the ID does not exist")
    void testGetTemplateById_notFound() throws Exception {
        // A missing template must surface as a 404 AppException, not a null return.
        when(templateRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> templateService.getTemplateById(99L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        verify(templateRepository).findById(99L);
    }

    // ==========================================================================
    // getAllTemplates
    // ==========================================================================

    @Test
    @DisplayName("getAllTemplates: returns the full list when templates exist")
    void testGetAllTemplates_returnsList() throws Exception {
        // The complete list from the repository must be returned without modification.
        final Template t2 = Template.builder().id(2L).name("Evening Routine").icon(2).build();
        when(templateRepository.findAll()).thenReturn(List.of(template, t2));

        final List<Template> result = templateService.getAllTemplates();

        assertEquals(2, result.size());
        assertEquals("Morning Routine", result.get(0).getName());
        assertEquals("Evening Routine", result.get(1).getName());
        verify(templateRepository).findAll();
    }

    @Test
    @DisplayName("getAllTemplates: returns a single-item list when exactly one template exists")
    void testGetAllTemplates_singleTemplate() throws Exception {
        // A single entry must not trigger the empty-check exception.
        when(templateRepository.findAll()).thenReturn(List.of(template));

        final List<Template> result = templateService.getAllTemplates();

        assertEquals(1, result.size());
        assertEquals("Morning Routine", result.get(0).getName());
    }

    @Test
    @DisplayName("getAllTemplates: throws AppException(NOT_FOUND) when the repository is empty")
    void testGetAllTemplates_empty_throws() throws Exception {
        // An empty templates table must produce a 404 AppException.
        when(templateRepository.findAll()).thenReturn(List.of());

        final AppException ex = assertThrows(AppException.class,
                () -> templateService.getAllTemplates());

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
    }

    // ==========================================================================
    // createTemplate
    // ==========================================================================

    @Test
    @DisplayName("createTemplate: saves new template and returns persisted entity with all mapped fields")
    void testCreateTemplate_happyPath() throws Exception {
        // Every DTO field must be transferred to the saved entity and the
        // persisted template returned.
        final List<Boolean> days = List.of(true, false, false, true, false, false, false);
        final List<String> notifs = List.of("08:00", "20:00");

        final TemplateDto dto = TemplateDto.builder()
                .name("Weekly Check")
                .description("Weekly health check-in")
                .frequency("weekly")
                .interval(1)
                .count(4)
                .daysOfWeek(days)
                .timeOfDay("09:00")
                .icon(3)
                .notifications(notifs)
                .build();

        when(templateRepository.save(any(Template.class))).thenAnswer(inv -> {
            final Template t = inv.getArgument(0);
            t.setId(10L);
            return t;
        });

        final Template result = templateService.createTemplate(dto);

        assertNotNull(result);
        assertEquals(10L, result.getId());
        assertEquals("Weekly Check", result.getName());
        assertEquals("Weekly health check-in", result.getDescription());
        assertEquals("weekly", result.getFrequency());
        assertEquals(1, result.getTaskInterval());
        assertEquals(4, result.getDoCount());
        assertEquals(days, result.getDaysOfWeek());
        assertEquals("09:00", result.getTimeOfDay());
        assertEquals(3, result.getIcon());
        assertEquals(notifs, result.getNotifications());
        verify(templateRepository).save(any(Template.class));
    }

    @Test
    @DisplayName("createTemplate: saves template with null optional fields when DTO omits them")
    void testCreateTemplate_nullOptionalFields() throws Exception {
        // Optional fields not supplied in the DTO must map to null/zero on the entity;
        // the service must not throw for missing optional values.
        final TemplateDto dto = TemplateDto.builder()
                .name("Simple Template")
                .icon(0)
                .build();

        when(templateRepository.save(any(Template.class))).thenAnswer(inv -> {
            final Template t = inv.getArgument(0);
            t.setId(20L);
            return t;
        });

        final Template result = templateService.createTemplate(dto);

        assertNotNull(result);
        assertEquals("Simple Template", result.getName());
        assertNull(result.getDescription());
        assertNull(result.getFrequency());
        assertNull(result.getDaysOfWeek());
        assertNull(result.getNotifications());
    }

    // ==========================================================================
    // updateTemplate
    // ==========================================================================

    @Test
    @DisplayName("updateTemplate: overwrites all fields on the existing entity and saves")
    void testUpdateTemplate_updatesAllFields() throws Exception {
        // Every field in the DTO must replace the stored value on the entity.
        final List<Boolean> newDays = List.of(false, true, false, true, false, false, false);
        final List<String> newNotifs = List.of("07:00");

        when(templateRepository.findById(1L)).thenReturn(Optional.of(template));
        when(templateRepository.save(any(Template.class))).thenAnswer(inv -> inv.getArgument(0));

        final TemplateDto dto = TemplateDto.builder()
                .name("Updated Name")
                .description("Updated description")
                .frequency("monthly")
                .interval(2)
                .count(12)
                .daysOfWeek(newDays)
                .timeOfDay("10:00")
                .icon(5)
                .notifications(newNotifs)
                .build();

        final Template result = templateService.updateTemplate(1L, dto);

        assertEquals("Updated Name", result.getName());
        assertEquals("Updated description", result.getDescription());
        assertEquals("monthly", result.getFrequency());
        assertEquals(2, result.getTaskInterval());
        assertEquals(12, result.getDoCount());
        assertEquals(newDays, result.getDaysOfWeek());
        assertEquals("10:00", result.getTimeOfDay());
        assertEquals(5, result.getIcon());
        assertEquals(newNotifs, result.getNotifications());
        verify(templateRepository).save(template);
    }

    @Test
    @DisplayName("updateTemplate: throws AppException(NOT_FOUND) when the template does not exist")
    void testUpdateTemplate_notFound_throws() throws Exception {
        // An update targeting an unknown ID must fail with a 404 AppException
        // before any save is attempted.
        when(templateRepository.findById(99L)).thenReturn(Optional.empty());

        final TemplateDto dto = TemplateDto.builder().name("Any").icon(0).build();

        final AppException ex = assertThrows(AppException.class,
                () -> templateService.updateTemplate(99L, dto));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        verify(templateRepository, never()).save(any());
    }

    @Test
    @DisplayName("updateTemplate: returns the entity produced by the repository save call")
    void testUpdateTemplate_returnsSavedEntity() throws Exception {
        // The repository may return a new instance (e.g., with DB-populated fields);
        // the service must pass that through rather than returning the local object.
        final Template savedTemplate = Template.builder()
                .id(1L).name("Saved").icon(0).build();

        when(templateRepository.findById(1L)).thenReturn(Optional.of(template));
        when(templateRepository.save(any(Template.class))).thenReturn(savedTemplate);

        final TemplateDto dto = TemplateDto.builder().name("Saved").icon(0).build();

        final Template result = templateService.updateTemplate(1L, dto);

        assertSame(savedTemplate, result);
    }

    // ==========================================================================
    // deleteTemplate
    // ==========================================================================

    @Test
    @DisplayName("deleteTemplate: deletes the template and returns true when it exists")
    void testDeleteTemplate_exists_returnsTrue() throws Exception {
        // The happy path: the template is found, deleted, and the method returns true.
        when(templateRepository.findById(1L)).thenReturn(Optional.of(template));

        final boolean result = templateService.deleteTemplate(1L);

        assertTrue(result);
        verify(templateRepository).delete(template);
    }

    @Test
    @DisplayName("deleteTemplate: throws AppException(NOT_FOUND) when the template does not exist")
    void testDeleteTemplate_notFound_throws() throws Exception {
        // A delete on a non-existent template must produce a 404 AppException
        // and must not call delete on the repository.
        when(templateRepository.findById(99L)).thenReturn(Optional.empty());

        final AppException ex = assertThrows(AppException.class,
                () -> templateService.deleteTemplate(99L));

        assertEquals(HttpStatus.NOT_FOUND, ex.getStatus());
        verify(templateRepository, never()).delete(any(Template.class));
    }

    @Test
    @DisplayName("deleteTemplate: passes the correct entity instance to repository.delete()")
    void testDeleteTemplate_passesCorrectEntityToRepository() throws Exception {
        // The exact Template object retrieved must be forwarded to delete(),
        // not just the ID.
        when(templateRepository.findById(1L)).thenReturn(Optional.of(template));

        templateService.deleteTemplate(1L);

        verify(templateRepository).delete(template);
    }
}
