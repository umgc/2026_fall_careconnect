package com.careconnect.dto;

import java.time.LocalDateTime;

public class InboxMessageDto {
    private Long messageId;
    private Long peerId;
    private String peerName;
    private String peerEmail;
    private String peerRole;
    private String content;
    private LocalDateTime timestamp;
    private boolean hasUnread;

    // Default constructor
    public InboxMessageDto() {
    }

    public InboxMessageDto(Long messageId, Long peerId, String peerName, String peerEmail,
                           String peerRole, String content, LocalDateTime timestamp, boolean hasUnread) {
        this.messageId = messageId;
        this.peerId = peerId;
        this.peerName = peerName;
        this.peerEmail = peerEmail;
        this.peerRole = peerRole;
        this.content = content;
        this.timestamp = timestamp;
        this.hasUnread = hasUnread;
    }

    // Getters and Setters

    public Long getMessageId() {
        return messageId;
    }

    public void setMessageId(Long messageId) {
        this.messageId = messageId;
    }

    public Long getPeerId() {
        return peerId;
    }

    public void setPeerId(Long peerId) {
        this.peerId = peerId;
    }

    public String getPeerName() {
        return peerName;
    }

    public void setPeerName(String peerName) {
        this.peerName = peerName;
    }

    public String getPeerEmail() {
        return peerEmail;
    }

    public void setPeerEmail(String peerEmail) {
        this.peerEmail = peerEmail;
    }

    public String getPeerRole() {
        return peerRole;
    }

    public void setPeerRole(String peerRole) {
        this.peerRole = peerRole;
    }

    public String getContent() {
        return content;
    }

    public void setContent(String content) {
        this.content = content;
    }

    public LocalDateTime getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(LocalDateTime timestamp) {
        this.timestamp = timestamp;
    }

    public boolean isHasUnread() {
        return hasUnread;
    }

    public void setHasUnread(boolean hasUnread) {
        this.hasUnread = hasUnread;
    }
}