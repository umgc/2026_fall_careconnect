package com.careconnect.repository;

import com.careconnect.model.DeviceToken;
import com.careconnect.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface DeviceTokenRepository extends JpaRepository<DeviceToken, Long> {

    List<DeviceToken> findByUserAndIsActiveTrue(User user);

    List<DeviceToken> findByUserIdAndIsActiveTrue(Long userId);

    Optional<DeviceToken> findByFcmTokenAndIsActiveTrue(String fcmToken);

    Optional<DeviceToken> findByUserAndDeviceIdAndIsActiveTrue(User user, String deviceId);

    @Modifying
    @Query("UPDATE DeviceToken dt SET dt.isActive = false WHERE dt.user = :user AND dt.deviceId = :deviceId")
    void deactivateByUserAndDeviceId(@Param("user") User user, @Param("deviceId") String deviceId);

    @Modifying
    @Query("UPDATE DeviceToken dt SET dt.isActive = false WHERE dt.fcmToken = :fcmToken")
    void deactivateByFcmToken(@Param("fcmToken") String fcmToken);

    @Query("SELECT dt FROM DeviceToken dt WHERE dt.user.id IN :userIds AND dt.isActive = true")
    List<DeviceToken> findActiveTokensByUserIds(@Param("userIds") List<Long> userIds);
}
