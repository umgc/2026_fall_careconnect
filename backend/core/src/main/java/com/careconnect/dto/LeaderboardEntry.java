package com.careconnect.dto;

public class LeaderboardEntry {
    private Long userId;
    private String name;
    private String lastName;
    private String firstName;
    private int xp;
    private int level;
    private String profileImageUrl;

    public LeaderboardEntry(Long userId, String lastName, String firstName, int xp, int level, String profileImageUrl) {
        this.userId = userId;
        this.name = lastName + " " + firstName;
        this.lastName = lastName;
        this.firstName = firstName;
        this.xp = xp;
        this.level = level;
        this.profileImageUrl = profileImageUrl;
    }

    public Long getUserId() {
        return userId;
    }

    public String getName() {
        return name;
    }

    public int getXp() {
        return xp;
    }

    public int getLevel() {
        return level;
    }

    public String getProfileImageUrl() {
        return profileImageUrl;
    }
}