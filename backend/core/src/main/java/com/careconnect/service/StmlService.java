package com.careconnect.service;

import com.careconnect.dto.StmlBriefDTO;
import com.careconnect.dto.StmlBriefDTO.StmlCardDTO;
import com.careconnect.model.Task;
import com.careconnect.repository.TaskRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Service
@RequiredArgsConstructor
public class StmlService {

    private final TaskRepository taskRepository;

    public StmlBriefDTO getDailyBrief(Long patientId) {
        List<StmlCardDTO> cards = new ArrayList<>();

        // Pull pending tasks as action items (STML-2)
        List<Task> tasks = taskRepository.findByPatientId(patientId).orElse(List.of()); 
      for (Task task : tasks) {
    if (!task.isCompleted()) {
        cards.add(StmlCardDTO.builder()
            .type("ACTION_ITEM")
            .headline(task.getName())
            .detail(task.getDescription())
            .sourceType("TASK")
            .timestamp(LocalDateTime.now())
            .build());
    }
}

        return StmlBriefDTO.builder()
            .patientId(patientId)
            .generatedAt(LocalDateTime.now())
            .cards(cards)
            .disclaimer("This information is drawn from your care records. It is not medical advice.")
            .build();
    }
}