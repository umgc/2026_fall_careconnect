package com.careconnect.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import com.careconnect.model.Task;
import com.careconnect.model.User;

/**
 * Repository interface for managing {@link Task} entities.
 *
 * <p>
 * This interface extends {@link JpaRepository}, providing built-in
 * CRUD operations and query support. It also defines custom finder
 * methods for retrieving tasks by patient or by recurrence grouping.
 * </p>
 *
 * <p>
 * Spring Data JPA automatically implements these query methods
 * by parsing their method names into SQL queries at runtime.
 * </p>
 */
public interface TaskRepository extends JpaRepository<Task, Long> {

    /**
     * Finds all tasks assigned to a given patient.
     *
     * <p>
     * Example usage: retrieving tasks for a specific patient
     * object that has already been loaded from the database.
     * </p>
     *
     * @param user the {@link User} entity representing the patient
     * @return an {@link Optional} containing a list of tasks for the patient,
     * or empty if no tasks exist
     */
    Optional<List<Task>> findByPatient(User user);

    /**
     * Finds all tasks for a patient by their unique patient ID.
     *
     * <p>
     * Example usage: retrieving tasks without loading the
     * entire {@link User} entity.
     * </p>
     *
     * @param patientId the ID of the patient
     * @return an {@link Optional} containing a list of tasks for the patient,
     * or empty if no tasks exist
     */
    Optional<List<Task>> findByPatientId(Long patientId);

    /**
     * Finds all tasks that belong to a recurring series,
     * identified by the parent task’s ID.
     *
     * <p>
     * Example usage: retrieving all child tasks generated
     * from a parent recurring task definition.
     * </p>
     *
     * @param parentTaskId the ID of the parent task
     * @return list of tasks that reference the given parent task ID
     */
    List<Task> findByParentTaskId(Long parentTaskId);

}
