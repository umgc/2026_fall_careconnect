package com.careconnect.service;

import com.careconnect.model.Post;
import com.careconnect.repository.PostRepository;
import com.careconnect.dto.PostWithCommentCountDto;
import com.careconnect.repository.CommentRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import com.careconnect.repository.UserRepository;

import java.time.LocalDateTime;
import java.util.List;

@Service
public class FeedService {

    private final PostRepository postRepository;
    private final CommentRepository commentRepository;
    private final UserRepository userRepository;

    @Autowired
    private GamificationService gamificationService;

    @Autowired
    public FeedService(PostRepository postRepository, CommentRepository commentRepository, UserRepository userRepository) {
        this.postRepository = postRepository;
        this.commentRepository = commentRepository;
        this.userRepository = userRepository;
    }

    // Create a new post (with optional image URL)
    public Post createPost(Long userId, String content, String imageUrl) {
        Post post = new Post();
        post.setUserId(userId);
        post.setContent(content);
        post.setCreatedAt(LocalDateTime.now());
        post.setImageUrl(imageUrl);  // ✅ Assign uploaded image path
        Post savedPost = postRepository.save(post);

        long totalPosts = postRepository.countByUserId(userId);
        if (totalPosts == 1) {
            gamificationService.unlockAchievement(userId, "First Post Created", 50);
        }

        return savedPost;
    }

    // Fetch all posts globally
    public List<Post> getAllPosts() {
        return postRepository.findAllByOrderByCreatedAtDesc();
    }

    // Fetch posts by a specific user
    public List<Post> getPostsByUser(Long userId) {
        return postRepository.findAllByUserIdOrderByCreatedAtDesc(userId);
    }

    public List<PostWithCommentCountDto> getAllPostsWithCommentCount() {
        List<Post> posts = postRepository.findAllByOrderByCreatedAtDesc();
        return posts.stream().map(post -> {
            String username = userRepository.findById(post.getUserId())
                    .map(user -> {
                        String name = user.getName();
                        return (name != null && !name.isEmpty()) ? name : user.getEmail();
                    }).orElse("Unknown");

            return new PostWithCommentCountDto(
                    post.getId(),
                    post.getUserId(),
                    post.getContent(),
                    post.getImageUrl(),
                    post.getCreatedAt(),
                    commentRepository.countByPostId(post.getId()),
                    username
            );
        }).toList();
    }

    public List<PostWithCommentCountDto> getPostsByUserAndFriends(Long userId) {
        List<Long> friendIds = userRepository.findConfirmedFriendIds(userId);
        friendIds.add(userId);

        List<Post> posts = postRepository.findAllByUserIdInOrderByCreatedAtDesc(friendIds);
        return posts.stream().map(post -> {
            String username = userRepository.findById(post.getUserId())
                    .map(u -> (u.getName() != null && !u.getName().isEmpty()) ? u.getName() : u.getEmail())
                    .orElse("Unknown");
            return new PostWithCommentCountDto(
                    post.getId(),
                    post.getUserId(),
                    post.getContent(),
                    post.getImageUrl(),
                    post.getCreatedAt(),
                    commentRepository.countByPostId(post.getId()),
                    username
            );
        }).toList();
    }

}
