package com.careconnect.controller;

import com.careconnect.model.Comment;
import com.careconnect.service.CommentService;
import com.careconnect.repository.UserRepository;
import com.careconnect.model.User;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.*;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.security.SecurityRequirement;
import io.swagger.v3.oas.annotations.tags.Tag;

import java.util.List;

@RestController
@RequestMapping("/v1/api/comments")
@Tag(name = "Comments", description = "Comment management endpoints for posts")
@SecurityRequirement(name = "JWT Authentication")
public class CommentController {

    @Autowired
    private CommentService commentService;

    @Autowired
    private UserRepository userRepository;

    @GetMapping("/post/{postId}")
    @Operation(
            summary = "Get comments for a post",
            description = "Retrieve all comments for a specific post, ordered by creation time."
    )
    @ApiResponses({
            @ApiResponse(
                    responseCode = "200",
                    description = "Comments retrieved successfully",
                    content = @Content(
                            mediaType = "application/json",
                            schema = @Schema(implementation = Comment.class, type = "array"),
                            examples = @ExampleObject(value = "[\n    {\n        \"id\": 1,\n        \"postId\": 123,\n        \"userId\": 456,\n        \"username\": \"john_doe\",\n        \"content\": \"Great post!\",\n        \"createdAt\": \"2025-01-15T10:30:00Z\"\n    }\n]")
                    )
            ),
            @ApiResponse(
                    responseCode = "403",
                    description = "Not authenticated"
            )
    })
    public ResponseEntity<?> getCommentsForPost(
            @Parameter(description = "ID of the post to get comments for", required = true)
            @PathVariable Long postId
    ) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("Not authenticated");
        }

        List<Comment> comments = commentService.getCommentsForPost(postId);
        return ResponseEntity.ok(comments);
    }

    @PostMapping("/post/{postId}")
    public ResponseEntity<?> addCommentToPost(
            @PathVariable Long postId,
            @RequestBody Comment comment
    ) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null || !authentication.isAuthenticated()) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("Not authenticated");
        }

        // Get user from JWT token (email is the subject)
        String email = authentication.getName();
        User user = userRepository.findByEmail(email).orElse(null);
        if (user == null) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("User not found");
        }

        // Verify the comment belongs to the authenticated user
        if (!user.getId().equals(comment.getUserId())) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("Cannot comment as another user");
        }

        Comment saved = commentService.addComment(postId, comment.getUserId(), comment.getUsername(), comment.getContent());
        return ResponseEntity.status(HttpStatus.CREATED).body(saved);
    }
}
