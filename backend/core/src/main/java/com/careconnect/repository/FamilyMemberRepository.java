package com.careconnect.repository;

import com.careconnect.model.FamilyMember;
import com.careconnect.model.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface FamilyMemberRepository extends JpaRepository<FamilyMember, Long> {
    Optional<FamilyMember> findByUser(User user);

    Optional<FamilyMember> findByEmail(String email);

    boolean existsByEmail(String email);
}
