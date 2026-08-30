package com.careconnect.config;

import com.careconnect.model.Achievement;
import com.careconnect.repository.AchievementRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.MockitoAnnotations;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.*;

/**
 * Unit tests for AchievementInitializer.
 * <p>
 * Validates achievement initialization logic during application startup,
 * including creation of default achievements, duplicate prevention,
 * and error handling to ensure application stability.
 */
class AchievementInitializerTest {

    @Mock
    private AchievementRepository achievementRepository;

    @InjectMocks
    private AchievementInitializer achievementInitializer;

    private ByteArrayOutputStream errContent;
    private PrintStream originalErr;

    @BeforeEach
    void setUp() throws Exception {
        // Arrange: Initialize mocks and capture System.err output
        MockitoAnnotations.openMocks(this);

        // Capture System.err for testing error messages
        errContent = new ByteArrayOutputStream();
        originalErr = System.err;
        System.setErr(new PrintStream(errContent));
    }

    @AfterEach
    void tearDown() throws Exception {
        // Restore original System.err
        System.setErr(originalErr);
    }

    @Test
    void initAchievementsCreatesAllDefaultAchievements() throws Exception {
        // Arrange: Mock repository to return empty (no existing achievements)
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        when(achievementRepository.save(any(Achievement.class))).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: All 5 default achievements should be saved
        verify(achievementRepository, times(5)).save(any(Achievement.class));
        verify(achievementRepository, times(5)).findByTitle(anyString());

        // Verify no error messages
        final String errorOutput = errContent.toString();
        assertTrue(errorOutput.isEmpty(), "No errors should be logged for successful initialization");
    }

    @Test
    void initAchievementsCreatesFirstLoginAchievement() throws Exception {
        // Arrange: Mock repository to return empty
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        final ArgumentCaptor<Achievement> achievementCaptor = ArgumentCaptor.forClass(Achievement.class);
        when(achievementRepository.save(achievementCaptor.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Verify First Login achievement was created with correct details
        final Achievement firstLogin = achievementCaptor.getAllValues().stream()
                .filter(a -> "First Login".equals(a.getTitle()))
                .findFirst()
                .orElse(null);

        assertNotNull(firstLogin, "First Login achievement should be created");
        assertEquals("First Login", firstLogin.getTitle());
        assertEquals("Awarded for logging in for the first time.", firstLogin.getDescription());
        assertEquals("login-icon.png", firstLogin.getIcon());
    }

    @Test
    void initAchievementsCreatesMadeAFriendAchievement() throws Exception {
        // Arrange: Mock repository to return empty
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        final ArgumentCaptor<Achievement> achievementCaptor = ArgumentCaptor.forClass(Achievement.class);
        when(achievementRepository.save(achievementCaptor.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Verify Made a Friend achievement was created
        final Achievement madeAFriend = achievementCaptor.getAllValues().stream()
                .filter(a -> "Made a Friend".equals(a.getTitle()))
                .findFirst()
                .orElse(null);

        assertNotNull(madeAFriend, "Made a Friend achievement should be created");
        assertEquals("Made a Friend", madeAFriend.getTitle());
        assertEquals("Awarded for adding your first friend.", madeAFriend.getDescription());
        assertEquals("friend-icon.png", madeAFriend.getIcon());
    }

    @Test
    void initAchievementsCreatesAddedFamilyMemberAchievement() throws Exception {
        // Arrange: Mock repository to return empty
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        final ArgumentCaptor<Achievement> achievementCaptor = ArgumentCaptor.forClass(Achievement.class);
        when(achievementRepository.save(achievementCaptor.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Verify Added Family Member achievement was created
        final Achievement addedFamily = achievementCaptor.getAllValues().stream()
                .filter(a -> "Added Family Member".equals(a.getTitle()))
                .findFirst()
                .orElse(null);

        assertNotNull(addedFamily, "Added Family Member achievement should be created");
        assertEquals("Added Family Member", addedFamily.getTitle());
        assertEquals("Awarded for adding your first family member.", addedFamily.getDescription());
        assertEquals("family-icon.png", addedFamily.getIcon());
    }

    @Test
    void initAchievementsCreatesFirstPostCreatedAchievement() throws Exception {
        // Arrange: Mock repository to return empty
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        final ArgumentCaptor<Achievement> achievementCaptor = ArgumentCaptor.forClass(Achievement.class);
        when(achievementRepository.save(achievementCaptor.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Verify First Post Created achievement was created
        final Achievement firstPost = achievementCaptor.getAllValues().stream()
                .filter(a -> "First Post Created".equals(a.getTitle()))
                .findFirst()
                .orElse(null);

        assertNotNull(firstPost, "First Post Created achievement should be created");
        assertEquals("First Post Created", firstPost.getTitle());
        assertEquals("Awarded for creating your first post.", firstPost.getDescription());
        assertEquals("post-icon.png", firstPost.getIcon());
    }

    @Test
    void initAchievementsCreatesFiveDayStreakAchievement() throws Exception {
        // Arrange: Mock repository to return empty
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        final ArgumentCaptor<Achievement> achievementCaptor = ArgumentCaptor.forClass(Achievement.class);
        when(achievementRepository.save(achievementCaptor.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Verify 5-Day Streak achievement was created
        final Achievement fiveDayStreak = achievementCaptor.getAllValues().stream()
                .filter(a -> "5-Day Streak".equals(a.getTitle()))
                .findFirst()
                .orElse(null);

        assertNotNull(fiveDayStreak, "5-Day Streak achievement should be created");
        assertEquals("5-Day Streak", fiveDayStreak.getTitle());
        assertEquals("Awarded for logging in 5 days in a row.", fiveDayStreak.getDescription());
        assertEquals("streak-icon.png", fiveDayStreak.getIcon());
    }

    @Test
    void initAchievementsSkipsExistingAchievements() throws Exception {
        // Arrange: Mock some achievements already exist
        final Achievement existingAchievement = new Achievement();
        existingAchievement.setTitle("First Login");
        existingAchievement.setDescription("Awarded for logging in for the first time.");
        existingAchievement.setIcon("login-icon.png");

        when(achievementRepository.findByTitle("First Login"))
                .thenReturn(Optional.of(existingAchievement));
        when(achievementRepository.findByTitle(argThat(title -> !"First Login".equals(title))))
                .thenReturn(Optional.empty());
        when(achievementRepository.save(any(Achievement.class))).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Only 4 achievements should be saved (First Login already exists)
        verify(achievementRepository, times(4)).save(any(Achievement.class));
        verify(achievementRepository, times(5)).findByTitle(anyString());
    }

    @Test
    void initAchievementsSkipsAllWhenAllExist() throws Exception {
        // Arrange: Mock all achievements already exist
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.of(new Achievement()));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: No achievements should be saved
        verify(achievementRepository, never()).save(any(Achievement.class));
        verify(achievementRepository, times(5)).findByTitle(anyString());
    }

    @Test
    void initAchievementsHandlesFindByTitleException() throws Exception {
        // Arrange: Mock repository to throw exception on findByTitle
        when(achievementRepository.findByTitle(anyString()))
                .thenThrow(new RuntimeException("Database connection error"));

        // Act: Initialize achievements - should not throw exception
        assertDoesNotThrow(() -> achievementInitializer.initAchievements());

        // Assert: Error messages should be logged for each achievement
        final String errorOutput = errContent.toString();
        assertTrue(errorOutput.contains("Failed to create achievement 'First Login'"));
        assertTrue(errorOutput.contains("Failed to create achievement 'Made a Friend'"));
        assertTrue(errorOutput.contains("Failed to create achievement 'Added Family Member'"));
        assertTrue(errorOutput.contains("Failed to create achievement 'First Post Created'"));
        assertTrue(errorOutput.contains("Failed to create achievement '5-Day Streak'"));

        // No save should be attempted
        verify(achievementRepository, never()).save(any(Achievement.class));
    }

    @Test
    void initAchievementsHandlesSaveException() throws Exception {
        // Arrange: Mock findByTitle succeeds but save throws exception
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        when(achievementRepository.save(any(Achievement.class)))
                .thenThrow(new RuntimeException("Failed to save to database"));

        // Act: Initialize achievements - should not throw exception
        assertDoesNotThrow(() -> achievementInitializer.initAchievements());

        // Assert: Error messages should be logged
        final String errorOutput = errContent.toString();
        assertTrue(errorOutput.contains("Failed to create achievement"));

        // All save attempts should be made
        verify(achievementRepository, times(5)).save(any(Achievement.class));
    }

    @Test
    void initAchievementsHandlesPartialFailure() throws Exception {
        // Arrange: First two achievements fail, rest succeed
        when(achievementRepository.findByTitle("First Login"))
                .thenThrow(new RuntimeException("Database error"));
        when(achievementRepository.findByTitle("Made a Friend"))
                .thenThrow(new RuntimeException("Database error"));
        when(achievementRepository.findByTitle(argThat(title ->
                !"First Login".equals(title) && !"Made a Friend".equals(title))))
                .thenReturn(Optional.empty());
        when(achievementRepository.save(any(Achievement.class))).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Only 3 achievements should be saved
        verify(achievementRepository, times(3)).save(any(Achievement.class));

        // Error messages for the two failed achievements
        final String errorOutput = errContent.toString();
        assertTrue(errorOutput.contains("Failed to create achievement 'First Login'"));
        assertTrue(errorOutput.contains("Failed to create achievement 'Made a Friend'"));
    }

    @Test
    void initAchievementsHandlesExceptionInInitMethod() throws Exception {
        // Arrange: Mock repository to throw exception that bubbles to initAchievements
        when(achievementRepository.findByTitle(anyString()))
                .thenThrow(new RuntimeException("Critical database failure"));

        // Act: Initialize achievements - should catch exception and log error
        assertDoesNotThrow(() -> achievementInitializer.initAchievements());

        // Assert: Top-level error message should NOT be logged
        // (individual achievement errors are logged instead)
        final String errorOutput = errContent.toString();
        assertTrue(errorOutput.contains("Failed to create achievement"));
    }

    @Test
    void initAchievementsDoesNotThrowExceptionOnCompleteFailure() throws Exception {
        // Arrange: Mock complete repository failure
        when(achievementRepository.findByTitle(anyString()))
                .thenThrow(new RuntimeException("Complete system failure"));

        // Act & Assert: Method should handle exception gracefully
        assertDoesNotThrow(() -> achievementInitializer.initAchievements(),
                "initAchievements should not throw exception to avoid application startup failure");
    }

    @Test
    void initAchievementsCreatesAchievementWithCorrectAttributes() throws Exception {
        // Arrange: Capture created achievements
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        final ArgumentCaptor<Achievement> achievementCaptor = ArgumentCaptor.forClass(Achievement.class);
        when(achievementRepository.save(achievementCaptor.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Verify all captured achievements have non-null attributes
        for (final Achievement achievement : achievementCaptor.getAllValues()) {
            assertNotNull(achievement.getTitle(), "Achievement title should not be null");
            assertNotNull(achievement.getDescription(), "Achievement description should not be null");
            assertNotNull(achievement.getIcon(), "Achievement icon should not be null");
            assertFalse(achievement.getTitle().isEmpty(), "Achievement title should not be empty");
            assertFalse(achievement.getDescription().isEmpty(), "Achievement description should not be empty");
            assertFalse(achievement.getIcon().isEmpty(), "Achievement icon should not be empty");
        }
    }

    @Test
    void initAchievementsCreatesFiveUniqueAchievements() throws Exception {
        // Arrange: Mock repository
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        final ArgumentCaptor<Achievement> achievementCaptor = ArgumentCaptor.forClass(Achievement.class);
        when(achievementRepository.save(achievementCaptor.capture())).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Verify 5 unique achievements were created
        assertEquals(5, achievementCaptor.getAllValues().size());

        final long uniqueTitles = achievementCaptor.getAllValues().stream()
                .map(Achievement::getTitle)
                .distinct()
                .count();

        assertEquals(5, uniqueTitles, "All achievement titles should be unique");
    }

    @Test
    void createAchievementIfNotExistsHandlesNullPointerException() throws Exception {
        // Arrange: Mock repository to return null (edge case)
        when(achievementRepository.findByTitle(anyString())).thenReturn(null);

        // Act & Assert: Should handle gracefully
        assertDoesNotThrow(() -> achievementInitializer.initAchievements());
    }

    @Test
    void initAchievementsVerifiesAllExpectedTitlesAreQueried() throws Exception {
        // Arrange: Mock repository
        when(achievementRepository.findByTitle(anyString())).thenReturn(Optional.empty());
        when(achievementRepository.save(any(Achievement.class))).thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Initialize achievements
        achievementInitializer.initAchievements();

        // Assert: Verify all expected titles were queried
        verify(achievementRepository).findByTitle("First Login");
        verify(achievementRepository).findByTitle("Made a Friend");
        verify(achievementRepository).findByTitle("Added Family Member");
        verify(achievementRepository).findByTitle("First Post Created");
        verify(achievementRepository).findByTitle("5-Day Streak");
    }

    @Test
    void initAchievementsCompletesEvenWithMultipleExceptions() throws Exception {
        // Arrange: Simulate various exceptions for different achievements
        when(achievementRepository.findByTitle("First Login")).thenReturn(Optional.empty());
        when(achievementRepository.save(argThat(a -> a != null && "First Login".equals(a.getTitle()))))
                .thenThrow(new RuntimeException("Save failed"));

        when(achievementRepository.findByTitle("Made a Friend"))
                .thenThrow(new RuntimeException("Find failed"));

        when(achievementRepository.findByTitle("Added Family Member")).thenReturn(Optional.empty());
        when(achievementRepository.save(argThat(a -> a != null && "Added Family Member".equals(a.getTitle()))))
                .thenAnswer(invocation -> invocation.getArgument(0));

        when(achievementRepository.findByTitle("First Post Created")).thenReturn(Optional.empty());
        when(achievementRepository.save(argThat(a -> a != null && "First Post Created".equals(a.getTitle()))))
                .thenAnswer(invocation -> invocation.getArgument(0));

        when(achievementRepository.findByTitle("5-Day Streak")).thenReturn(Optional.empty());
        when(achievementRepository.save(argThat(a -> a != null && "5-Day Streak".equals(a.getTitle()))))
                .thenAnswer(invocation -> invocation.getArgument(0));

        // Act: Should complete without throwing
        assertDoesNotThrow(() -> achievementInitializer.initAchievements());

        // Assert: At least 3 achievements should be successfully saved
        verify(achievementRepository, atLeast(3)).save(any(Achievement.class));
    }
}
