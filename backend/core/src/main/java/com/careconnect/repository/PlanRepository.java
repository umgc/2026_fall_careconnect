package com.careconnect.repository;

import com.careconnect.model.Plan;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface PlanRepository extends JpaRepository<Plan, Long> {
    // Find a plan by its Stripe price ID
    Plan findByCode(String stripeId);

    // Find all active plans
    List<Plan> findByIsActiveTrue();

    // Find plans by name
    List<Plan> findByName(String name);
}
