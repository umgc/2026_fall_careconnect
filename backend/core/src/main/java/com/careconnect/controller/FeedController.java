package com.careconnect.controller;

import com.careconnect.dto.PostWithCommentCountDto;
import com.careconnect.repository.CaregiverRepository;
import com.careconnect.repository.PatientRepository;
import com.careconnect.security.AuthorizationService;
import com.careconnect.security.Role;
import com.careconnect.security.UnauthorizedException;
import com.careconnect.util.SecurityUtil;
import org.springframework.beans.factory.annotation.Value;
import com.careconnect.model.Post;
import com.careconnect.service.FeedService;
import com.careconnect.repository.UserRepository;
import com.careconnect.model.User;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;

import java.io.File;
import java.io.IOException;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/v1/api/feed")
@Tag(name = "Feed", description = "Social feed management endpoints for posts and content sharing")
@SecurityRequirement(name = "JWT Authentication")
public class FeedController {


    @Autowired
    private SecurityUtil securityUtil;

    @Autowired
    private AuthorizationService authorizationService;

    @Autowired
    private FeedService feedService;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private PatientRepository patientRepository;

    @Autowired
    private CaregiverRepository caregiverRepository;

    @GetMapping("/all")
    @Operation(
            summary = "Get global feed",
            description = "Retrieve all posts from the global feed. Requires authentication."
    )
    @ApiResponses({
            @ApiResponse(
                    responseCode = "200",
                    description = "Global feed retrieved successfully",
                    content = @Content(
                            mediaType = "application/json",
                            schema = @Schema(implementation = PostWithCommentCountDto.class, type = "array")
                    )
            ),
            @ApiResponse(
                    responseCode = "403",
                    description = "Not authenticated",
                    content = @Content(
                            mediaType = "application/json",
                            examples = @ExampleObject(value = "{\n    \"error\": \"Not authenticated\"\n}")
                    )
            )
    })
    public ResponseEntity<?> getGlobalFeed() {
        // RBAC: Defense-in-depth - ensure caller is authenticated
        securityUtil.resolveCurrentUser();
        List<PostWithCommentCountDto> posts = feedService.getAllPostsWithCommentCount();
        return ResponseEntity.ok(posts);
    }

    @GetMapping("/user/{userId}")
    public ResponseEntity<?> getUserFeed(@PathVariable Long userId) {

        // Get user from JWT token (email is the subject).
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        String email = authentication.getName();
        User user = userRepository.findByEmail(email).orElse(null);
        if (user == null) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("User not found");
        }

        // Allow users to view their own feed, or admins to view any feed
        if (!user.getId().equals(userId) && !user.getRole().name().equals("ADMIN")) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("Access denied");
        }

        List<Post> posts = feedService.getPostsByUser(userId);
        return ResponseEntity.ok(posts);
    }

    @GetMapping("/friends-feed")
    public ResponseEntity<?> getFriendsFeed() {
        // (Updated) Removed manual authentication check

        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        String email = auth.getName();
        User user = userRepository.findByEmail(email).orElse(null);
        if (user == null) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("User not found");
        }

        List<PostWithCommentCountDto> posts = feedService.getPostsByUserAndFriends(user.getId());
        return ResponseEntity.ok(posts);
    }

    @PostMapping(value = "/create", consumes = "application/json")
    public ResponseEntity<?> createPost(@RequestBody Post postData) {

        // Get user from JWT token (email is the subject)
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        String email = authentication.getName();
        User user = userRepository.findByEmail(email).orElse(null);
        if (user == null) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("User not found");
        }

        // Verify the post belongs to the authenticated user
        if (!user.getId().equals(postData.getUserId())) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("Cannot create post as another user");
        }
        try {
            Post savedPost = feedService.createPost(user.getId(), postData.getContent(), null);

            PostWithCommentCountDto dto = new PostWithCommentCountDto(
                    savedPost.getId(),
                    savedPost.getUserId(),
                    savedPost.getContent(),
                    null,
                    savedPost.getCreatedAt(),
                    0,
                    resolveDisplayName(user)
            );

            return ResponseEntity.status(HttpStatus.CREATED).body(dto);

        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body("Error creating post: " + e.getMessage());
        }
    }

    private String resolveDisplayName(User user) {
        if (user.getRole() == Role.PATIENT) {
            return patientRepository.findByUserId(user.getId())
                    .map(p -> p.getFirstName() + " " + p.getLastName())
                    .orElse(user.getEmail());
        } else if (user.getRole() == Role.CAREGIVER) {
            return caregiverRepository.findByUserId(user.getId())
                    .map(c -> c.getFirstName() + " " + c.getLastName())
                    .orElse(user.getEmail());
        } else {
            return user.getEmail();
        }
    }
}

