package com.careconnect.service;

import com.careconnect.repository.*;
import com.careconnect.security.JwtTokenProvider;
import com.careconnect.security.Role;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

public record ProfessionalInfoDto(String licenseNumber, String issuingState, int yearsExperience) {
}
