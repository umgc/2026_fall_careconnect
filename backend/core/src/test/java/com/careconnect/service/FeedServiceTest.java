package com.careconnect.service;

import com.careconnect.dto.PostWithCommentCountDto;
import com.careconnect.model.Post;
import com.careconnect.model.User;
import com.careconnect.repository.CommentRepository;
import com.careconnect.repository.PostRepository;
import com.careconnect.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.*;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

import java.util.Optional;

class FeedServiceTest {

    @Mock
    private PostRepository postRepository;
    @Mock
    private CommentRepository commentRepository;
    @Mock
    private UserRepository userRepository;
    @Mock
    private GamificationService gamificationService;

    @InjectMocks
    private FeedService feedService;

    private Post post;
    private User user;

    @BeforeEach
    void setUp() throws Exception {
        MockitoAnnotations.openMocks(this);
        ReflectionTestUtils.setField(feedService, "gamificationService", gamificationService);

        user = new User();
        user.setId(1L);
        user.setEmail("user@test.com");
        user.setName("Test User");
        user.setPassword("pass");

        post = new Post();
        post.setId(10L);
        post.setUserId(1L);
        post.setContent("Hello World");
        post.setImageUrl("http://img.com/photo.jpg");
        post.setCreatedAt(LocalDateTime.now());
    }

    @Test
    @DisplayName("createPost - first post by user - unlocks achievement")
    void createPost_firstPost_unlocksAchievement() throws Exception {
        when(postRepository.save(any(Post.class))).thenReturn(post);
        when(postRepository.countByUserId(1L)).thenReturn(1L);

        final Post result = feedService.createPost(1L, "Hello World", "http://img.com/photo.jpg");

        assertNotNull(result);
        assertEquals(10L, result.getId());
        assertEquals("Hello World", result.getContent());
        assertEquals("http://img.com/photo.jpg", result.getImageUrl());
        verify(gamificationService).unlockAchievement(1L, "First Post Created", 50);
    }

    @Test
    @DisplayName("createPost - not first post - does not unlock achievement")
    void createPost_notFirstPost_doesNotUnlockAchievement() throws Exception {
        when(postRepository.save(any(Post.class))).thenReturn(post);
        when(postRepository.countByUserId(1L)).thenReturn(5L);

        final Post result = feedService.createPost(1L, "Hello World", null);

        assertNotNull(result);
        verify(gamificationService, never()).unlockAchievement(anyLong(), anyString(), anyInt());
    }

    @Test
    @DisplayName("createPost - null imageUrl - creates post with null imageUrl")
    void createPost_nullImageUrl_createsPostWithNullImageUrl() throws Exception {
        when(postRepository.save(any(Post.class))).thenAnswer(invocation -> {
            final Post saved = invocation.getArgument(0);
            saved.setId(11L);
            return saved;
        });
        when(postRepository.countByUserId(1L)).thenReturn(2L);

        final Post result = feedService.createPost(1L, "No image post", null);

        assertNotNull(result);
        assertNull(result.getImageUrl());
    }

    @Test
    @DisplayName("getAllPosts - posts exist - returns all posts")
    void getAllPosts_postsExist_returnsAllPosts() throws Exception {
        final Post post2 = new Post();
        post2.setId(11L);
        post2.setUserId(2L);
        post2.setContent("Post 2");
        post2.setCreatedAt(LocalDateTime.now());

        when(postRepository.findAllByOrderByCreatedAtDesc()).thenReturn(List.of(post, post2));

        final List<Post> result = feedService.getAllPosts();

        assertEquals(2, result.size());
    }

    @Test
    @DisplayName("getAllPosts - no posts - returns empty list")
    void getAllPosts_noPosts_returnsEmptyList() throws Exception {
        when(postRepository.findAllByOrderByCreatedAtDesc()).thenReturn(List.of());

        final List<Post> result = feedService.getAllPosts();

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getPostsByUser - user has posts - returns user posts")
    void getPostsByUser_userHasPosts_returnsUserPosts() throws Exception {
        when(postRepository.findAllByUserIdOrderByCreatedAtDesc(1L)).thenReturn(List.of(post));

        final List<Post> result = feedService.getPostsByUser(1L);

        assertEquals(1, result.size());
        assertEquals(1L, result.get(0).getUserId());
    }

    @Test
    @DisplayName("getPostsByUser - user has no posts - returns empty list")
    void getPostsByUser_userHasNoPosts_returnsEmptyList() throws Exception {
        when(postRepository.findAllByUserIdOrderByCreatedAtDesc(999L)).thenReturn(List.of());

        final List<Post> result = feedService.getPostsByUser(999L);

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getAllPostsWithCommentCount - user with name - returns name as username")
    void getAllPostsWithCommentCount_userWithName_returnsNameAsUsername() throws Exception {
        when(postRepository.findAllByOrderByCreatedAtDesc()).thenReturn(List.of(post));
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(commentRepository.countByPostId(10L)).thenReturn(3);

        final List<PostWithCommentCountDto> result = feedService.getAllPostsWithCommentCount();

        assertEquals(1, result.size());
        assertEquals("Test User", result.get(0).getUsername());
        assertEquals(3, result.get(0).getCommentCount());
        assertEquals("Hello World", result.get(0).getContent());
        assertEquals("http://img.com/photo.jpg", result.get(0).getImageUrl());
    }

    @Test
    @DisplayName("getAllPostsWithCommentCount - user with null name - returns email as username")
    void getAllPostsWithCommentCount_userWithNullName_returnsEmailAsUsername() throws Exception {
        user.setName(null);
        when(postRepository.findAllByOrderByCreatedAtDesc()).thenReturn(List.of(post));
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(commentRepository.countByPostId(10L)).thenReturn(0);

        final List<PostWithCommentCountDto> result = feedService.getAllPostsWithCommentCount();

        assertEquals(1, result.size());
        assertEquals("user@test.com", result.get(0).getUsername());
    }

    @Test
    @DisplayName("getAllPostsWithCommentCount - user with empty name - returns email as username")
    void getAllPostsWithCommentCount_userWithEmptyName_returnsEmailAsUsername() throws Exception {
        user.setName("");
        when(postRepository.findAllByOrderByCreatedAtDesc()).thenReturn(List.of(post));
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(commentRepository.countByPostId(10L)).thenReturn(0);

        final List<PostWithCommentCountDto> result = feedService.getAllPostsWithCommentCount();

        assertEquals(1, result.size());
        assertEquals("user@test.com", result.get(0).getUsername());
    }

    @Test
    @DisplayName("getAllPostsWithCommentCount - user not found - returns Unknown as username")
    void getAllPostsWithCommentCount_userNotFound_returnsUnknownAsUsername() throws Exception {
        when(postRepository.findAllByOrderByCreatedAtDesc()).thenReturn(List.of(post));
        when(userRepository.findById(1L)).thenReturn(Optional.empty());
        when(commentRepository.countByPostId(10L)).thenReturn(0);

        final List<PostWithCommentCountDto> result = feedService.getAllPostsWithCommentCount();

        assertEquals(1, result.size());
        assertEquals("Unknown", result.get(0).getUsername());
    }

    @Test
    @DisplayName("getAllPostsWithCommentCount - no posts - returns empty list")
    void getAllPostsWithCommentCount_noPosts_returnsEmptyList() throws Exception {
        when(postRepository.findAllByOrderByCreatedAtDesc()).thenReturn(List.of());

        final List<PostWithCommentCountDto> result = feedService.getAllPostsWithCommentCount();

        assertTrue(result.isEmpty());
    }

    @Test
    @DisplayName("getPostsByUserAndFriends - user with friends and posts - returns posts with comment counts")
    void getPostsByUserAndFriends_userWithFriendsAndPosts_returnsPostsWithCommentCounts() throws Exception {
        final List<Long> friendIds = new ArrayList<>(List.of(2L, 3L));
        when(userRepository.findConfirmedFriendIds(1L)).thenReturn(friendIds);
        when(postRepository.findAllByUserIdInOrderByCreatedAtDesc(anyList())).thenReturn(List.of(post));
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(commentRepository.countByPostId(10L)).thenReturn(5);

        final List<PostWithCommentCountDto> result = feedService.getPostsByUserAndFriends(1L);

        assertEquals(1, result.size());
        assertEquals("Test User", result.get(0).getUsername());
        assertEquals(5, result.get(0).getCommentCount());
    }

    @Test
    @DisplayName("getPostsByUserAndFriends - user with no friends - returns only own posts")
    void getPostsByUserAndFriends_noFriends_returnsOwnPosts() throws Exception {
        final List<Long> friendIds = new ArrayList<>();
        when(userRepository.findConfirmedFriendIds(1L)).thenReturn(friendIds);
        when(postRepository.findAllByUserIdInOrderByCreatedAtDesc(List.of(1L))).thenReturn(List.of(post));
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(commentRepository.countByPostId(10L)).thenReturn(0);

        final List<PostWithCommentCountDto> result = feedService.getPostsByUserAndFriends(1L);

        assertEquals(1, result.size());
    }

    @Test
    @DisplayName("getPostsByUserAndFriends - user with null name in post - returns email")
    void getPostsByUserAndFriends_userWithNullName_returnsEmail() throws Exception {
        user.setName(null);
        final List<Long> friendIds = new ArrayList<>();
        when(userRepository.findConfirmedFriendIds(1L)).thenReturn(friendIds);
        when(postRepository.findAllByUserIdInOrderByCreatedAtDesc(List.of(1L))).thenReturn(List.of(post));
        when(userRepository.findById(1L)).thenReturn(Optional.of(user));
        when(commentRepository.countByPostId(10L)).thenReturn(0);

        final List<PostWithCommentCountDto> result = feedService.getPostsByUserAndFriends(1L);

        assertEquals("user@test.com", result.get(0).getUsername());
    }

    @Test
    @DisplayName("getPostsByUserAndFriends - post author not found - returns Unknown")
    void getPostsByUserAndFriends_postAuthorNotFound_returnsUnknown() throws Exception {
        final List<Long> friendIds = new ArrayList<>();
        when(userRepository.findConfirmedFriendIds(1L)).thenReturn(friendIds);
        when(postRepository.findAllByUserIdInOrderByCreatedAtDesc(List.of(1L))).thenReturn(List.of(post));
        when(userRepository.findById(1L)).thenReturn(Optional.empty());
        when(commentRepository.countByPostId(10L)).thenReturn(0);

        final List<PostWithCommentCountDto> result = feedService.getPostsByUserAndFriends(1L);

        assertEquals("Unknown", result.get(0).getUsername());
    }

    @Test
    @DisplayName("getPostsByUserAndFriends - no posts - returns empty list")
    void getPostsByUserAndFriends_noPosts_returnsEmptyList() throws Exception {
        final List<Long> friendIds = new ArrayList<>();
        when(userRepository.findConfirmedFriendIds(1L)).thenReturn(friendIds);
        when(postRepository.findAllByUserIdInOrderByCreatedAtDesc(List.of(1L))).thenReturn(List.of());

        final List<PostWithCommentCountDto> result = feedService.getPostsByUserAndFriends(1L);

        assertTrue(result.isEmpty());
    }
}
