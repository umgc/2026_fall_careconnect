package com.careconnect.controller;

import com.careconnect.dto.TemplateDto;
import com.careconnect.model.Template;
import com.careconnect.security.AuthorizationService;
import com.careconnect.service.TemplateService;
import com.careconnect.util.SecurityUtil;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class TemplateControllerTest {

    private static final Long TEMPLATE_ID = 1L;
    @Mock
    private TemplateService templateService;
    @Mock
    private SecurityUtil securityUtil;
    @Mock
    private AuthorizationService authorizationService;
    @InjectMocks
    private TemplateController controller;

    private Template template(String name) {
        return Template.builder().id(TEMPLATE_ID).name(name).icon(0).build();
    }

    private TemplateDto templateDto(String name) {
        return TemplateDto.builder().name(name).icon(0).build();
    }

    // ─── getAllTemplates ───────────────────────────────────────────────────────

    @Test
    void getAllTemplates_returnsOkWithList() throws Exception {
        final List<Template> templates = List.of(template("T1"), template("T2"));
        when(templateService.getAllTemplates()).thenReturn(templates);

        final ResponseEntity<List<Template>> response = controller.getAllTemplates();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(templates);
        verify(templateService).getAllTemplates();
    }

    // ─── getAll ───────────────────────────────────────────────────────────────

    @Test
    void getAll_returnsOkWithList() throws Exception {
        final List<Template> templates = List.of(template("T1"));
        when(templateService.getAllTemplates()).thenReturn(templates);

        final ResponseEntity<List<Template>> response = controller.getAll();

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(templates);
    }

    // ─── getTemplateById ──────────────────────────────────────────────────────

    @Test
    void getTemplateById_returnsOkWithTemplate() throws Exception {
        final Template t = template("MyTemplate");
        when(templateService.getTemplateById(TEMPLATE_ID)).thenReturn(t);

        final ResponseEntity<Template> response = controller.getTemplateById(TEMPLATE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(t);
        verify(templateService).getTemplateById(TEMPLATE_ID);
    }

    // ─── createTemplate ───────────────────────────────────────────────────────

    @Test
    void createTemplate_returnsOkWithCreatedTemplate() throws Exception {
        final TemplateDto dto = templateDto("New");
        final Template created = template("New");
        when(templateService.createTemplate(dto)).thenReturn(created);

        final ResponseEntity<Template> response = controller.createTemplate(dto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(created);
        verify(templateService).createTemplate(dto);
    }

    // ─── updateTemplate ───────────────────────────────────────────────────────

    @Test
    void updateTemplate_returnsOkWithUpdatedTemplate() throws Exception {
        final TemplateDto dto = templateDto("Updated");
        final Template updated = template("Updated");
        when(templateService.updateTemplate(TEMPLATE_ID, dto)).thenReturn(updated);

        final ResponseEntity<Template> response = controller.updateTemplate(TEMPLATE_ID, dto);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(updated);
        verify(templateService).updateTemplate(TEMPLATE_ID, dto);
    }

    // ─── deleteTemplate ───────────────────────────────────────────────────────

    @Test
    void deleteTemplate_returnsNoContent() throws Exception {
        when(templateService.deleteTemplate(TEMPLATE_ID)).thenReturn(true);

        final ResponseEntity<Void> response = controller.deleteTemplate(TEMPLATE_ID);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        verify(templateService).deleteTemplate(TEMPLATE_ID);
    }
}
