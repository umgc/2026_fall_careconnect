package com.careconnect.service;

import com.careconnect.model.CheckIn;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class CheckInService {

    public List<CheckIn> getAllCheckIns() {
        // Placeholder: fetch all from DB later
        return List.of();
    }

    public CheckIn getCheckInByID(Long id) {
        // Placeholder: fetch single record by ID later
        return new CheckIn();
    }
}
