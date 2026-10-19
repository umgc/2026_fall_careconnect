package com.careconnect.service.cache;

import com.careconnect.model.*;
import com.careconnect.repository.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.cache.annotation.CacheEvict;
import org.springframework.stereotype.Service;
import lombok.extern.slf4j.Slf4j;

import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.time.LocalDateTime;

@Service
@Slf4j
public class AIChatCacheService {

    private static final int CACHE_TTL_MINUTES = 15;
    // Simple in-memory cache for demonstration - in production, use Redis or similar
    private final ConcurrentHashMap<String, CacheEntry<Patient>> patientCache = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, CacheEntry<UserAIConfig>> configCache = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<String, CacheEntry<ChatConversation>> conversationCache = new ConcurrentHashMap<>();
    @Autowired
    private PatientRepository patientRepository;
    @Autowired
    private UserAIConfigRepository userAIConfigRepository;
    @Autowired
    private ChatConversationRepository chatConversationRepository;

    public Optional<Patient> findPatient(Long patientId) {
        String key = "patient_" + patientId;
        CacheEntry<Patient> entry = patientCache.get(key);

        if (entry != null && !entry.isExpired()) {
            log.debug("Cache HIT: Patient {}", patientId);
            return Optional.ofNullable(entry.getValue());
        }

        log.debug("Cache MISS: Patient {} - querying database", patientId);
        Optional<Patient> patient = patientRepository.findById(patientId);

        if (patient.isPresent()) {
            patientCache.put(key, new CacheEntry<>(patient.get()));
        }

        return patient;
    }

    public Optional<UserAIConfig> findUserAIConfig(Long userId, Long patientId) {
        String key = "config_" + userId + "_" + patientId;
        CacheEntry<UserAIConfig> entry = configCache.get(key);

        if (entry != null && !entry.isExpired()) {
            log.debug("Cache HIT: UserAIConfig for user {} patient {}", userId, patientId);
            return Optional.ofNullable(entry.getValue());
        }

        log.debug("Cache MISS: UserAIConfig for user {} patient {} - querying database", userId, patientId);
        Optional<UserAIConfig> config = userAIConfigRepository.findByUserIdAndPatientIdAndIsActiveTrue(userId, patientId);

        if (config.isPresent()) {
            configCache.put(key, new CacheEntry<>(config.get()));
        }

        return config;
    }

    public UserAIConfig saveUserAIConfig(UserAIConfig config) {
        UserAIConfig saved = userAIConfigRepository.save(config);

        // Update cache
        String key = "config_" + saved.getUserId() + "_" + saved.getPatientId();
        configCache.put(key, new CacheEntry<>(saved));

        log.debug("Cache UPDATE: UserAIConfig for user {} patient {}", saved.getUserId(), saved.getPatientId());
        return saved;
    }

    public Optional<ChatConversation> findConversation(String conversationId) {
        String key = "conversation_" + conversationId;
        CacheEntry<ChatConversation> entry = conversationCache.get(key);

        if (entry != null && !entry.isExpired()) {
            log.debug("Cache HIT: Conversation {}", conversationId);
            return Optional.ofNullable(entry.getValue());
        }

        log.debug("Cache MISS: Conversation {} - querying database", conversationId);
        Optional<ChatConversation> conversation = chatConversationRepository.findByConversationIdAndIsActiveTrue(conversationId);

        if (conversation.isPresent()) {
            conversationCache.put(key, new CacheEntry<>(conversation.get()));
        }

        return conversation;
    }

    public ChatConversation saveConversation(ChatConversation conversation) {
        ChatConversation saved = chatConversationRepository.save(conversation);

        // Update cache
        String key = "conversation_" + saved.getConversationId();
        conversationCache.put(key, new CacheEntry<>(saved));

        log.debug("Cache UPDATE: Conversation {}", saved.getConversationId());
        return saved;
    }

    @CacheEvict(value = "patients", key = "#patientId")
    public void evictPatient(Long patientId) {
        String key = "patient_" + patientId;
        patientCache.remove(key);
        log.debug("Cache EVICT: Patient {}", patientId);
    }

    @CacheEvict(value = "userAIConfigs", key = "#userId + '_' + #patientId")
    public void evictUserAIConfig(Long userId, Long patientId) {
        String key = "config_" + userId + "_" + patientId;
        configCache.remove(key);
        log.debug("Cache EVICT: UserAIConfig for user {} patient {}", userId, patientId);
    }

    @CacheEvict(value = "conversations", key = "#conversationId")
    public void evictConversation(String conversationId) {
        String key = "conversation_" + conversationId;
        conversationCache.remove(key);
        log.debug("Cache EVICT: Conversation {}", conversationId);
    }

    public void cleanupExpiredEntries() {
        // Clean up expired cache entries to prevent memory leaks
        patientCache.entrySet().removeIf(entry -> entry.getValue().isExpired());
        configCache.entrySet().removeIf(entry -> entry.getValue().isExpired());
        conversationCache.entrySet().removeIf(entry -> entry.getValue().isExpired());

        log.debug("Cache cleanup completed");
    }

    public void clearAllCaches() {
        patientCache.clear();
        configCache.clear();
        conversationCache.clear();
        log.info("All caches cleared");
    }

    private static class CacheEntry<T> {
        private final T value;
        private final LocalDateTime timestamp;

        public CacheEntry(T value) {
            this.value = value;
            this.timestamp = LocalDateTime.now();
        }

        public T getValue() {
            return value;
        }

        public boolean isExpired() {
            return LocalDateTime.now().isAfter(timestamp.plusMinutes(CACHE_TTL_MINUTES));
        }
    }
}