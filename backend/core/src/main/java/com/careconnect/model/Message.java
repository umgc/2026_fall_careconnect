package com.careconnect.model;

import jakarta.persistence.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "messages")
public class Message {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long senderId;

    @Column(nullable = false)
    private Long receiverId;

    @Column(nullable = false, columnDefinition = "TEXT")
    private String content;

    @Column(nullable = false)
    private LocalDateTime timestamp;

    @Column(name = "is_read", nullable = false)
    private boolean isRead = false;

    @Column(name = "attachment_id")
    private Long attachmentId;

    @Column(name = "attachment_name")
    private String attachmentName;

    @Column(name = "attachment_content_type")
    private String attachmentContentType;

    @Column(name = "attachment_size")
    private Long attachmentSize;

    /**
     * Set on a share card: what the card opens. A card holds only these two ids, never the data
     * itself, and grants nothing: the data's own access rule is checked when it is opened.
     */
    @Enumerated(EnumType.STRING)
    @Column(name = "share_kind", length = 32)
    private ShareKind shareKind;

    /** The {@code patient.id} whose data a share card opens. */
    @Column(name = "share_patient_id")
    private Long sharePatientId;

    /** What a share card opens: one tab of the patient's page. */
    public enum ShareKind {
        /** The Medicare tab. Needs the patient's MEDICARE_VIEW consent as well as the link. */
        MEDICARE,
        /** The Health tab: known risks, pain, recent symptoms and medications. The link is enough. */
        HEALTH
    }

    // Constructors
    public Message() {
    }

    public Message(Long senderId, Long receiverId, String content) {
        this.senderId = senderId;
        this.receiverId = receiverId;
        this.content = content;
        this.timestamp = LocalDateTime.now();
        this.isRead = false;
    }

    // Getters and Setters
    public Long getId() {
        return id;
    }

    public Long getSenderId() {
        return senderId;
    }

    public void setSenderId(Long senderId) {
        this.senderId = senderId;
    }

    public Long getReceiverId() {
        return receiverId;
    }

    public void setReceiverId(Long receiverId) {
        this.receiverId = receiverId;
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

    public boolean isRead() {
        return isRead;
    }

    public void setRead(boolean isRead) {
        this.isRead = isRead;
    }

    public Long getAttachmentId() {
        return attachmentId;
    }

    public void setAttachmentId(Long attachmentId) {
        this.attachmentId = attachmentId;
    }

    public String getAttachmentName() {
        return attachmentName;
    }

    public void setAttachmentName(String attachmentName) {
        this.attachmentName = attachmentName;
    }

    public String getAttachmentContentType() {
        return attachmentContentType;
    }

    public void setAttachmentContentType(String attachmentContentType) {
        this.attachmentContentType = attachmentContentType;
    }

    public Long getAttachmentSize() {
        return attachmentSize;
    }

    public void setAttachmentSize(Long attachmentSize) {
        this.attachmentSize = attachmentSize;
    }

    public ShareKind getShareKind() {
        return shareKind;
    }

    public void setShareKind(ShareKind shareKind) {
        this.shareKind = shareKind;
    }

    public Long getSharePatientId() {
        return sharePatientId;
    }

    public void setSharePatientId(Long sharePatientId) {
        this.sharePatientId = sharePatientId;
    }
}