package com.careconnect.service.homecare;

import com.careconnect.ai.AIService;
import com.careconnect.ai.AIServiceFactory;
import com.careconnect.dto.ChatRequest;
import com.careconnect.dto.ChatResponse;
import com.careconnect.model.homecare.HomeCareDocumentType;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class HomeCareLlmExtractionServiceTest {

    @Mock
    private AIServiceFactory aiServiceFactory;

    @Mock
    private AIService aiService;

    @InjectMocks
    private HomeCareLlmExtractionService service;

    @Test
    void extractDocumentData_validResponse_returnsTrimmedStructuredJson() {
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse("  {\"fullName\":\"Jane Doe\",\"phone\":\"555-0100\"}  ");

        when(aiServiceFactory.getService()).thenReturn(aiService);
        when(aiService.processChat(any(ChatRequest.class))).thenReturn(chatResponse);

        String result = service.extractDocumentData(
                HomeCareDocumentType.EMPLOYMENT_APPLICATION,
                "Full Name: Jane Doe\nPhone: 555-0100");

        assertThat(result).isEqualTo("{\"fullName\":\"Jane Doe\",\"phone\":\"555-0100\"}");
    }

    @Test
    void extractDocumentData_promptContainsOnlySelectedDocumentSchema() {
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse("{}");

        when(aiServiceFactory.getService()).thenReturn(aiService);
        when(aiService.processChat(any(ChatRequest.class))).thenReturn(chatResponse);

        service.extractDocumentData(HomeCareDocumentType.CERTIFICATION, "CNA License #12345");

        ArgumentCaptor<ChatRequest> captor = ArgumentCaptor.forClass(ChatRequest.class);
        verify(aiService).processChat(captor.capture());
        String prompt = captor.getValue().getMessage();

        // Document type determines which schema the LLM is constrained to.
        assertThat(prompt).contains("Certification / License");
        for (String key : HomeCareDocumentType.CERTIFICATION.getFieldSchema().keySet()) {
            assertThat(prompt).contains("\"" + key + "\"");
        }
        // Fields from other document types must not appear in the prompt.
        assertThat(prompt).doesNotContain("\"positionAppliedFor\"");
        assertThat(prompt).doesNotContain("\"filingStatus\"");
        assertThat(prompt).doesNotContain("invoiceNumber");
    }

    @Test
    void extractDocumentData_promptIncludesRawDocumentText() {
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse("{}");

        when(aiServiceFactory.getService()).thenReturn(aiService);
        when(aiService.processChat(any(ChatRequest.class))).thenReturn(chatResponse);

        service.extractDocumentData(HomeCareDocumentType.TAX_FORM, "W-4 Employee: John Smith");

        ArgumentCaptor<ChatRequest> captor = ArgumentCaptor.forClass(ChatRequest.class);
        verify(aiService).processChat(captor.capture());
        assertThat(captor.getValue().getMessage()).contains("W-4 Employee: John Smith");
    }

    @Test
    void extractDocumentData_nullAiResponse_returnsEmpty() {
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse(null);

        when(aiServiceFactory.getService()).thenReturn(aiService);
        when(aiService.processChat(any())).thenReturn(chatResponse);

        String result = service.extractDocumentData(
                HomeCareDocumentType.WORK_AUTHORIZATION, "Raw text");

        assertThat(result).isEmpty();
    }

    @Test
    void extractDocumentData_whitespaceResponse_returnsEmpty() {
        ChatResponse chatResponse = new ChatResponse();
        chatResponse.setAiResponse("   ");

        when(aiServiceFactory.getService()).thenReturn(aiService);
        when(aiService.processChat(any())).thenReturn(chatResponse);

        String result = service.extractDocumentData(
                HomeCareDocumentType.EMPLOYMENT_APPLICATION, "Raw text");

        assertThat(result).isEmpty();
    }
}
